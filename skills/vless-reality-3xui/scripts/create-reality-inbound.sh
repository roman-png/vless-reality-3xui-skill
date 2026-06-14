#!/usr/bin/env bash
# Create a VLESS-Reality inbound on a LOCAL 3x-ui panel via its API, and print a vless:// link.
# Run ON the server (it talks to 127.0.0.1:<panel-port>). NO SECRETS ARE STORED IN THIS FILE.
# All values come from flags or environment variables.
set -euo pipefail

PANEL_PORT="${PANEL_PORT:-}"        # 3x-ui panel port
WEB_PATH="${WEB_PATH:-}"            # 3x-ui secret webBasePath (with or without slashes)
PANEL_USER="${PANEL_USER:-}"
PANEL_PASS="${PANEL_PASS:-}"
PUBLIC_HOST="${PUBLIC_HOST:-}"      # server public IP or domain, used in the share link
DEST="${DEST:-www.microsoft.com}"  # camouflage site (foreign, TLS1.3+h2)
SERVERNAMES="${SERVERNAMES:-www.microsoft.com}"  # comma-separated SNIs the server will accept
PORT="${PORT:-443}"
REMARK="${REMARK:-reality}"
XRAY_BIN="${XRAY_BIN:-/usr/local/x-ui/bin/xray-linux-amd64}"

usage() {
  cat <<USAGE
Create a VLESS-Reality inbound via the local 3x-ui API.
Required (flag or env): --panel-port --web-path --panel-user --panel-pass --public-host
Optional: --dest (default www.microsoft.com) --servernames (CSV) --port (443) --remark
Example:
  PANEL_PASS='...' $0 --panel-port 54321 --web-path /secret/ --panel-user admin \\
     --public-host 203.0.113.10 --dest www.microsoft.com --servernames www.microsoft.com,vk.com
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --panel-port) PANEL_PORT="$2"; shift 2;;
    --web-path) WEB_PATH="$2"; shift 2;;
    --panel-user) PANEL_USER="$2"; shift 2;;
    --panel-pass) PANEL_PASS="$2"; shift 2;;
    --public-host) PUBLIC_HOST="$2"; shift 2;;
    --dest) DEST="$2"; shift 2;;
    --servernames) SERVERNAMES="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --remark) REMARK="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $1" >&2; usage; exit 1;;
  esac
done

for v in PANEL_PORT WEB_PATH PANEL_USER PANEL_PASS PUBLIC_HOST; do
  eval "val=\${$v}"; [ -n "$val" ] || { echo "missing required: $v" >&2; usage; exit 1; }
done
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
[ -x "$XRAY_BIN" ] || { echo "xray binary not found at $XRAY_BIN (set XRAY_BIN)" >&2; exit 1; }

WP="${WEB_PATH#/}"; WP="${WP%/}"
BASE="http://127.0.0.1:${PANEL_PORT}/${WP}"
CK="$(mktemp)"
cleanup() { [ -f "$CK" ] && : > "$CK" && command rm -f "$CK" 2>/dev/null || true; }
trap cleanup EXIT

extract_csrf() { grep -o 'name="csrf-token" content="[^"]*"' | sed 's/.*content="//; s/"$//'; }

# 3x-ui requires: CSRF token from the page + session cookie on every POST.
LOGIN_CSRF="$(curl -fsS -c "$CK" "${BASE}/" | extract_csrf)"
curl -fsS -b "$CK" -c "$CK" -X POST "${BASE}/login" \
  -H "X-CSRF-Token: ${LOGIN_CSRF}" \
  -d "username=${PANEL_USER}&password=${PANEL_PASS}" >/dev/null
# Authenticated token lives on the /panel/ page.
ACSRF="$(curl -fsS -b "$CK" "${BASE}/panel/" | extract_csrf)"

# Secrets generated on the server; never written to disk by this script.
KEYS="$("$XRAY_BIN" x25519)"
PRIV="$(printf '%s\n' "$KEYS" | sed -n 's/^PrivateKey:[[:space:]]*//p')"
PUB="$(printf  '%s\n' "$KEYS" | sed -n 's/^Password (PublicKey):[[:space:]]*//p')"
[ -n "$PRIV" ] || PRIV="$(printf '%s\n' "$KEYS" | sed -n 's/^Private key:[[:space:]]*//p')"
[ -n "$PUB"  ] || PUB="$(printf  '%s\n' "$KEYS" | sed -n 's/^Public key:[[:space:]]*//p')"
[ -n "$PRIV" ] && [ -n "$PUB" ] || { echo "failed to parse x25519 keypair" >&2; exit 1; }
UUID="$(cat /proc/sys/kernel/random/uuid)"
SID="$(openssl rand -hex 8)"
SUBID="$(openssl rand -hex 8)"
SNI_JSON="$(printf '%s' "$SERVERNAMES" | jq -R 'split(",") | map(gsub("^\\s+|\\s+$";""))')"
FIRST_SNI="$(printf '%s' "$SERVERNAMES" | cut -d, -f1 | tr -d ' ')"

SETTINGS="$(jq -cn --arg id "$UUID" --arg sub "$SUBID" \
  '{clients:[{id:$id,flow:"xtls-rprx-vision",email:$sub,enable:true,subId:$sub}],decryption:"none",fallbacks:[]}')"
STREAM="$(jq -cn --arg dest "${DEST}:443" --argjson sn "$SNI_JSON" --arg priv "$PRIV" --arg pub "$PUB" --arg sid "$SID" \
  '{network:"tcp",security:"reality",externalProxy:[],realitySettings:{show:false,xver:0,dest:$dest,serverNames:$sn,privateKey:$priv,shortIds:[$sid],settings:{publicKey:$pub,fingerprint:"chrome",spiderX:"/"}},tcpSettings:{header:{type:"none"}}}')"
SNIFF='{"enabled":true,"destOverride":["http","tls","quic"]}'
PAYLOAD="$(jq -cn --arg remark "$REMARK" --argjson port "$PORT" --arg set "$SETTINGS" --arg stream "$STREAM" --arg sniff "$SNIFF" \
  '{up:0,down:0,total:0,remark:$remark,enable:true,expiryTime:0,listen:"",port:$port,protocol:"vless",settings:$set,streamSettings:$stream,sniffing:$sniff}')"

RESP="$(curl -fsS -b "$CK" -X POST "${BASE}/panel/api/inbounds/add" \
  -H "X-CSRF-Token: ${ACSRF}" -H 'Content-Type: application/json' -d "$PAYLOAD")"
echo "$RESP" | jq -e '.success == true' >/dev/null || { echo "inbound add failed: $RESP" >&2; exit 1; }

LINK="vless://${UUID}@${PUBLIC_HOST}:${PORT}?type=tcp&security=reality&pbk=${PUB}&fp=chrome&sni=${FIRST_SNI}&sid=${SID}&flow=xtls-rprx-vision&spx=%2F#${REMARK}"
echo "OK: VLESS-Reality inbound created on port ${PORT}."
echo "accepted serverNames: ${SERVERNAMES}"
echo "dest: ${DEST}"
echo
echo "SHARE LINK (client sni MUST stay = ${FIRST_SNI}):"
echo "${LINK}"

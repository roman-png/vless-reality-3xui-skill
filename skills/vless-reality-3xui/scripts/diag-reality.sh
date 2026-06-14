#!/usr/bin/env bash
# Diagnose "Reality connects but no traffic". Temporarily runs an isolated xray on :443 with
# show:true + debug logging, captures the EXACT reject reason for a real client, then restores
# the 3x-ui xray. Run ON the server (root). Needs the inbound's UUID / privateKey / shortId.
set -euo pipefail

UUID="${UUID:-}"
PRIV="${PRIV:-}"
SID="${SID:-}"
DEST="${DEST:-www.microsoft.com}"           # serverNames for the diag = [DEST]; a client using any
WINDOW="${WINDOW:-120}"                       # other SNI will show up as "server name mismatch: <its-sni>"
XRAY_BIN="${XRAY_BIN:-/usr/local/x-ui/bin/xray-linux-amd64}"

while [ $# -gt 0 ]; do
  case "$1" in
    --uuid) UUID="$2"; shift 2;;
    --priv) PRIV="$2"; shift 2;;
    --sid) SID="$2"; shift 2;;
    --dest) DEST="$2"; shift 2;;
    --window) WINDOW="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
for v in UUID PRIV SID; do
  eval "val=\${$v}"; [ -n "$val" ] || { echo "missing $v (read it from the inbound's realitySettings)" >&2; exit 1; }
done

ERRLOG="$(mktemp)"; CFG="$(mktemp)"
cat > "$CFG" <<JSON
{ "log": {"loglevel":"debug","error":"${ERRLOG}"},
  "inbounds": [{"listen":"0.0.0.0","port":443,"protocol":"vless",
    "settings":{"clients":[{"id":"${UUID}","flow":"xtls-rprx-vision"}],"decryption":"none"},
    "streamSettings":{"network":"tcp","security":"reality","realitySettings":{
      "show":true,"dest":"${DEST}:443","serverNames":["${DEST}"],"privateKey":"${PRIV}","shortIds":["${SID}"]}}}],
  "outbounds": [{"protocol":"freedom"}] }
JSON

echo "Stopping x-ui and running diag xray on :443 for ${WINDOW}s ..."
systemctl stop x-ui
"$XRAY_BIN" run -c "$CFG" >/dev/null 2>>"$ERRLOG" &
DPID=$!
echo ">>> RECONNECT THE CLIENT NOW and try to load a website. <<<"
sleep "$WINDOW"
kill "$DPID" 2>/dev/null || true
systemctl start x-ui

echo
echo "=== Reality verdicts ==="
grep -iE 'REALITY|server name mismatch|failed to read client hello' "$ERRLOG" | tail -n 40 \
  || echo "(no reality lines: the client never reached this server — check reachability / firewall)"
echo
echo "Interpretation:"
echo "  'server name mismatch: X'     => client SNI X is not in serverNames. Fix client sni, or add X."
echo "  'failed to read client hello' => ClientHello lost in transit => clamp MSS (mss-clamp.sh)."
echo "  no lines at all                => TCP never arrived => network/firewall, not Reality."

# Leave logs for inspection; remove the temp config.
command rm -f "$CFG" 2>/dev/null || true
echo "(full debug log kept at: ${ERRLOG})"

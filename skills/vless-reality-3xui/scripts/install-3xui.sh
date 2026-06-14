#!/usr/bin/env bash
# Install MHSanaei 3x-ui non-interactively and apply known panel settings. Run ON the server (root).
# Credentials are generated locally if not supplied; they are PRINTED ONCE and never committed.
set -euo pipefail

PANEL_USER="${PANEL_USER:-$(openssl rand -hex 6)}"
PANEL_PASS="${PANEL_PASS:-$(openssl rand -hex 16)}"
PANEL_PORT="${PANEL_PORT:-$(shuf -i 20000-62000 -n 1)}"
WEB_PATH="${WEB_PATH:-$(openssl rand -hex 8)}"

[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive

if ! command -v curl >/dev/null; then apt-get update -y && apt-get install -y curl; fi
command -v jq >/dev/null || apt-get install -y jq

# Install with stdin from /dev/null so the installer's interactive prompts take defaults.
bash -c "$(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)" </dev/null

# Apply known settings via the binary (the x-ui wrapper menu is interactive).
cd /usr/local/x-ui
./x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" -port "$PANEL_PORT" -webBasePath "/${WEB_PATH}/" >/dev/null 2>&1 \
  || ./x-ui setting -username "$PANEL_USER" -password "$PANEL_PASS" -port "$PANEL_PORT" >/dev/null 2>&1
systemctl restart x-ui
sleep 2

if command -v ufw >/dev/null; then ufw allow "${PANEL_PORT}/tcp" >/dev/null 2>&1 || true; fi

echo "=== 3x-ui installed ==="
echo "Panel URL: http://<SERVER-IP>:${PANEL_PORT}/${WEB_PATH}/"
echo "Username : ${PANEL_USER}"
echo "Password : ${PANEL_PASS}"
echo "Port     : ${PANEL_PORT}"
echo "WebPath  : ${WEB_PATH}"
echo "Active   : $(systemctl is-active x-ui)"
echo "Store these in a password manager. DO NOT commit them anywhere."

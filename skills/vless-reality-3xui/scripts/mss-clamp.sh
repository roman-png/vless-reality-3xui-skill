#!/usr/bin/env bash
# Clamp the advertised TCP MSS so a large (~1.7 KB) Reality ClientHello survives small-MTU paths
# (mobile networks, tunnels). Reboot-safe via a systemd oneshot, because ufw does NOT manage the
# mangle table. Run ON the server (root).
set -euo pipefail

MSS="${MSS:-1200}"
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }

# Apply now (idempotent).
iptables -t mangle -C POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$MSS" 2>/dev/null \
  || iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss "$MSS"

# Persist across reboot.
cat > /etc/systemd/system/mss-clamp.service <<EOF
[Unit]
Description=Clamp TCP MSS to ${MSS} for Reality (reboot-safe)
After=network-online.target ufw.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'iptables -t mangle -C POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss ${MSS} 2>/dev/null || iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss ${MSS}'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mss-clamp.service >/dev/null 2>&1 || true

echo "MSS clamp ${MSS} applied and persisted (mss-clamp.service)."
iptables -t mangle -L POSTROUTING -n -v | grep -i tcpmss || echo "(rule missing!)"

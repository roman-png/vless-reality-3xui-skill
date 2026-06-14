# Diagnostics: "Reality connects but no traffic"

This is the failure mode that wastes the most time. The client UI shows "connected" (or
"timeout" for some sing-box-based clients), but no website loads. The TCP connection — and even
the full TLS handshake — can succeed while the tunnel never carries data.

## Golden rule: read the server's reality log BEFORE changing anything

Do not start toggling client options, changing the SNI at random, lowering MTU, swapping client
apps, or assuming "the ISP blocks the IP". Get ground truth first.

Run [`scripts/diag-reality.sh`](../scripts/diag-reality.sh). It runs an isolated xray on `:443`
with `realitySettings.show:true` and `loglevel:debug`, captures one real reconnect, then restores
the panel. The log answers it in one line:

| Server log line | Meaning | Fix |
|---|---|---|
| `REALITY: processed invalid connection ... server name mismatch: <sni>` | The client sent SNI `<sni>`, which is not in the server `serverNames`. Reality relays to `dest` and the client quietly drops. **#1 cause.** | Set the client `sni` to a server `serverName`, or add `<sni>` to `serverNames`. |
| `REALITY: processed invalid connection ... failed to read client hello` | The ClientHello did not arrive intact (truncated/lost). | MTU. Clamp MSS on the server (`scripts/mss-clamp.sh`). |
| (no reality lines at all) | TCP never reached the server. | Firewall / provider blocks the IP:port — check `ufw`, the provider cloud firewall, `Test-NetConnection host 443`. |

## Why it looks like "connected but no traffic" instead of a clean error

On an SNI mismatch (or any failed Reality auth) the server does **not** reject the TCP connection
— it transparently relays the TLS handshake to the real `dest` site. So the client completes a
valid TLS handshake (it even receives a real certificate) and only then notices there is no
Reality signal, so it closes and retries. From the outside this looks like a healthy connection
that simply carries no data. That is why you must read the **server** log, not the client.

## Layered verification (cheap to expensive)

1. **Server listening:** `ss -tlnp | grep ':443 '`.
2. **Local end-to-end** (proves the inbound works regardless of any network/DPI): run a temporary
   xray client to `127.0.0.1:443` with the same keys plus a SOCKS inbound, then
   `curl --socks5-hostname 127.0.0.1:<port> -o /dev/null -w '%{http_code}' https://www.google.com/generate_204`.
   `204` means the server side is perfect — the problem is the client or its network.
3. **External plain TLS** from a clean machine (NOT through another VPN):
   `echo | openssl s_client -connect <host>:443 -servername <a-serverName>` should return the
   `dest` site's certificate. If this works, the network carries TLS to the server fine.
4. **Real client** while `diag-reality.sh` is running: the definitive test (see the table).

## tcpdump, if you still need wire-level truth

```
tcpdump -i <iface> -nn -s 160 -X 'tcp dst port 443 and dst host <server-ip>'
```

A Reality ClientHello starts with bytes `16 03` and is large (~1.7 KB); on a small-MTU path it
spans two or more TCP segments. If the later segments are lost you get `failed to read client
hello` — that is the MTU case, fix with the MSS clamp.

## Hypotheses that LOOK right but usually are not

Confirm with the reality log before believing any of these:

- **"The ISP blocks the server IP."** Usually not — TCP and plain TLS get through. Confirm with a
  clean external `openssl s_client`.
- **"Client TLS-fragment / Mux is on."** A real cause of `failed to read client hello`, but rule
  it out by reading the log, not by assuming.
- **"Server Xray is too new / version skew."** Rarely the cause; Reality is stable across
  versions. The log will say `server name mismatch`, not a version error.
- **"MTU."** Real on mobile, but it produces `failed to read client hello`, never `server name
  mismatch`. Do not clamp MSS to fix a mismatch.

## Most common real root cause

A **plain SNI mismatch**: the client profile was hand-edited or imported with a different `sni=`
than the server's `serverNames`. Standardise on one canonical `vless://` link per inbound and do
not edit the `sni=` field on clients.

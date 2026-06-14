---
name: vless-reality-3xui
description: Deploy and debug a VLESS-Reality (Xray, flow xtls-rprx-vision, TCP/443) node managed by the 3x-ui panel on an Ubuntu/Debian VPS. Use when the user wants to stand up a self-hosted Reality node, create or repair a Reality inbound via the 3x-ui API, generate a vless:// share link, or diagnose a Reality node that "connects but passes no traffic". Includes a battle-tested diagnostic playbook for SNI mismatch, MTU/ClientHello loss, and DPI/SNI filtering.
disable-model-invocation: true
metadata:
  requires:
    bins:
      - bash
      - ssh
      - jq
      - curl
---

# VLESS-Reality via 3x-ui

Stand up a self-hosted **VLESS-Reality** node (Xray, `flow=xtls-rprx-vision`, TCP/443) behind the **3x-ui** panel, produce a working `vless://` share link, and — most importantly — *diagnose it correctly* when a client "connects but nothing loads".

Reality needs **no domain and no TLS certificate**: it borrows the TLS handshake of a real public site (the `dest` / `serverNames`), so on the wire the traffic looks like ordinary HTTPS to that site.

This skill is manual-first: it mutates a remote VPS. Invoke it only when the user explicitly asks to deploy, repair, or diagnose a Reality node. Read-only inspection is always fine.

## Hard rules (learned the hard way)

1. **When a Reality client "connects but passes no traffic", DO NOT GUESS. Turn on `realitySettings.show:true` + xray `loglevel:debug` on the server FIRST, reconnect the client, and read the one line that names the cause.** It is almost always one of:
   - `REALITY: processed invalid connection ... server name mismatch: <sni>` → the client's SNI does not match any server `serverNames`. **This is the #1 cause.** Fix the client `sni` or add that name to `serverNames`.
   - `REALITY: processed invalid connection ... failed to read client hello` → the ClientHello did not arrive intact → almost always **MTU** (rule 3).
   Use [`scripts/diag-reality.sh`](scripts/diag-reality.sh). Skipping this step can burn an entire debugging session chasing the wrong cause (MTU, client version, fragment toggles, "network blocking").
2. **The client's `sni` MUST exactly equal one of the server's `serverNames`.** On a mismatch Reality silently falls back to relaying to `dest`; the TLS handshake *completes*, the client gets no Reality signal and quietly closes — which presents as "connected, no internet", not as an error.
3. **Prefer a FOREIGN `dest`/SNI (e.g. `www.microsoft.com`).** A *domestic* SNI (e.g. `vk.com`, `yandex.ru`) pointed at a *foreign* server IP can be reset by a censor doing SNI↔IP correlation (observed on Russian ISPs): the handshake completes but no data flows. See [`references/sni-and-dpi.md`](references/sni-and-dpi.md).
4. **On mobile / small-MTU networks, clamp MSS on the server** so the large (~1.7 KB) Reality ClientHello arrives intact. See [`scripts/mss-clamp.sh`](scripts/mss-clamp.sh).
5. **Never hardcode real values.** Host, credentials, keys, IPs are passed as flags/env. Run a secret scan before any commit (`git grep -nEi` for tokens/keys/passwords).

## Inputs

- SSH target `root@<host>` (key-based preferred)
- (Windows + password-only host) one-time plain-text password, used once to install the SSH key
- panel admin username / password / port / secret web path (or let the script randomise them)
- camouflage `dest`/SNI (default `www.microsoft.com`); optionally extra accepted `serverNames`
- the server's public IP or domain, for the share link

## Workflow

### 0. (Windows) Bootstrap key-based SSH — [`scripts/ssh-bootstrap-key.ps1`](scripts/ssh-bootstrap-key.ps1)
Generates a dedicated ed25519 key and installs it using OpenSSH `SSH_ASKPASS` (no `plink`/`sshpass` needed on Windows), then verifies key login. After this, never send the password again.

### 1. Install 3x-ui (non-interactive) — [`scripts/install-3xui.sh`](scripts/install-3xui.sh)
Run on the server (root). Installs MHSanaei 3x-ui with stdin from `/dev/null` (so prompts take defaults), then sets known panel username/password/port/secret webBasePath and opens the panel port in `ufw`. Prints the panel URL + credentials once.

### 2. Create the Reality inbound — [`scripts/create-reality-inbound.sh`](scripts/create-reality-inbound.sh)
Run on the server. Logs into the **local** panel API (handles the CSRF-token + session-cookie flow that current 3x-ui requires on every POST), generates an x25519 keypair / shortId / uuid, creates a VLESS-Reality inbound on 443 with `flow=xtls-rprx-vision`, and prints the ready `vless://` link. Accepts multiple comma-separated `serverNames`.

### 3. (mobile / small MTU) Clamp MSS — [`scripts/mss-clamp.sh`](scripts/mss-clamp.sh)
Adds an MSS clamp in the `mangle` table and a systemd oneshot so it survives reboot (`ufw` does **not** manage `mangle`, so persist it yourself).

### 4. Diagnose — [`scripts/diag-reality.sh`](scripts/diag-reality.sh)
Temporarily runs an isolated xray on 443 with `show:true` + debug logging, captures the exact reject reason for a real client connection, then restores the panel's xray. THE tool for "connects but no traffic" (rule 1).

## Verify

- Server is listening: `ss -tlnp | grep ':443 '`
- **Local end-to-end** (proves the inbound itself works, independent of the client's network): start a temporary xray client pointed at `127.0.0.1:443` with the same keys, then `curl --socks5-hostname 127.0.0.1:<socks> -o /dev/null -w '%{http_code}' https://www.google.com/generate_204` → expect `204`.
- **Real client:** import the printed `vless://` link. If it connects but passes no traffic, go straight to step 4 — do not guess.

## Decision rules

- Reality `dest` must be a real site with TLS 1.3 + HTTP/2 + X25519, reachable from the **server**. Verify: `echo | openssl s_client -connect <dest>:443 -servername <dest> -alpn h2`.
- Changing `dest`/`serverNames` later: update the inbound only; the uuid/keys are unchanged, so the share link stays valid except its `sni=` value.
- Current 3x-ui (master) API: base `<webBasePath>panel/api/inbounds/` (`add` / `update/:id` / `list`); `settings`, `streamSettings`, `sniffing` are JSON **strings** inside the body — build them with `jq`. POST needs the CSRF token from `<meta name="csrf-token">` on `<webBasePath>panel/` plus the session cookie; GET is exempt.
- Keep the panel on a random high port behind a secret `webBasePath` with strong credentials; for maximum safety expose it only via SSH tunnel.
- Never commit panel credentials, the inbound private key, uuid, the server IP, or SSH details.

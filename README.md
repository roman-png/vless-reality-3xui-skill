# vless-reality-3xui-skill

A Claude Code skill (and plugin) to **deploy and — crucially — debug** a self-hosted
**VLESS-Reality** node (Xray, `flow=xtls-rprx-vision`, TCP/443) managed by the **3x-ui** panel on
an Ubuntu/Debian VPS.

Reality needs no domain and no TLS certificate; it camouflages as ordinary HTTPS to a real site.
The hard part is never the happy path — it is diagnosing *"the client connects but nothing loads"*.
This skill encodes that diagnostic playbook so you don't lose a day to it.

## What's inside

- `skills/vless-reality-3xui/SKILL.md` — workflow + hard rules
- `skills/vless-reality-3xui/references/diagnostics.md` — the "connects but no traffic" playbook (read this)
- `skills/vless-reality-3xui/references/sni-and-dpi.md` — SNI matching + foreign-vs-domestic SNI / DPI
- `skills/vless-reality-3xui/scripts/`
  - `ssh-bootstrap-key.ps1` — Windows: install an SSH key on a password-only host via `SSH_ASKPASS`
  - `install-3xui.sh` — non-interactive 3x-ui install + known panel settings
  - `create-reality-inbound.sh` — create a Reality inbound via the 3x-ui API, print the `vless://` link
  - `mss-clamp.sh` — MSS clamp for small-MTU/mobile paths (reboot-safe)
  - `diag-reality.sh` — isolated xray with `show:true`+debug to read the exact reject reason

## The lessons (TL;DR)

1. **"Reality connects but no traffic" → run `diag-reality.sh` and read the log _before guessing_.**
   It says `server name mismatch: <sni>` (the #1 cause) or `failed to read client hello` (MTU).
2. The client `sni` must **exactly** equal one of the server `serverNames`.
3. Prefer a **foreign** `dest`/SNI (`www.microsoft.com`). A domestic SNI to a foreign IP can be
   reset by SNI↔IP-correlating censors.
4. On mobile / small-MTU networks, clamp MSS (`mss-clamp.sh`).

## Install

- **skillsbd:** `npx skillsbd add roman-png/vless-reality-3xui-skill/vless-reality-3xui`
- **Claude Code plugin marketplace:** add this repo as a marketplace, then install the
  `vless-reality-3xui` plugin.
- **Manual:** copy `skills/vless-reality-3xui` into `~/.claude/skills/`.

## Safety

Every script takes host, credentials, keys, and IPs as flags/env — **no secrets are baked into
this repo**. Never commit panel credentials, the inbound private key, the node uuid, the server
IP, or SSH details. Run a secret scan before pushing.

## License

MIT — see [LICENSE](LICENSE).

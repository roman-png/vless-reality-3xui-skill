# vless-reality-3xui-skill

[English](README.md) · **Русский**

Skill (и плагин) для Claude Code, чтобы **развернуть и — главное — отладить** self-hosted ноду
**VLESS-Reality** (Xray, `flow=xtls-rprx-vision`, TCP/443) под управлением панели **3x-ui** на
Ubuntu/Debian VPS.

Reality не требует домена и TLS-сертификата — он маскируется под обычный HTTPS к реальному сайту.
Сложность не в «счастливом пути», а в диагностике ситуации *«клиент подключается, но ничего не
грузится»*. Этот скилл фиксирует тот самый диагностический плейбук, чтобы не терять на нём день.

## Что внутри

- `skills/vless-reality-3xui/SKILL.md` — воркфлоу + жёсткие правила
- `skills/vless-reality-3xui/references/diagnostics.md` — плейбук «подключается, но трафика нет» (читать первым)
- `skills/vless-reality-3xui/references/sni-and-dpi.md` — совпадение SNI + иностранный/российский SNI и DPI
- `skills/vless-reality-3xui/scripts/`
  - `ssh-bootstrap-key.ps1` — Windows: установка SSH-ключа на хост с парольным входом через `SSH_ASKPASS`
  - `install-3xui.sh` — неинтерактивная установка 3x-ui + заданные настройки панели
  - `create-reality-inbound.sh` — создание Reality-инбаунда через API 3x-ui, печать ссылки `vless://`
  - `mss-clamp.sh` — MSS-клэмп для сетей с малым MTU/мобильных (переживает перезагрузку)
  - `diag-reality.sh` — изолированный xray с `show:true`+debug, чтобы прочитать точную причину отказа

## Уроки (кратко)

1. **«Reality подключается, но трафика нет» → запусти `diag-reality.sh` и прочитай лог _прежде чем
   гадать_.** Он скажет `server name mismatch: <sni>` (причина №1) или `failed to read client hello` (MTU).
2. SNI клиента должен **точно** совпадать с одним из `serverNames` сервера.
3. Предпочитай **иностранный** `dest`/SNI (`www.microsoft.com`). Российский SNI на зарубежный IP
   может резаться провайдером, который коррелирует SNI с IP (наблюдалось на российских ISP/ТСПУ).
4. На мобильных/малых MTU — делай MSS-клэмп (`mss-clamp.sh`).

## Установка

- **skillsbd:** `npx skillsbd add roman-png/vless-reality-3xui-skill/vless-reality-3xui`
- **Маркетплейс плагинов Claude Code:** добавь этот репозиторий как marketplace и установи плагин
  `vless-reality-3xui`.
- **Вручную:** скопируй `skills/vless-reality-3xui` в `~/.claude/skills/`.

## Безопасность

Каждый скрипт принимает хост, креды, ключи и IP через флаги/env — **в репозитории нет секретов**.
Никогда не коммить креды панели, приватный ключ инбаунда, uuid ноды, IP сервера или SSH-детали.
Перед пушем прогоняй скан на секреты.

## Лицензия

MIT — см. [LICENSE](LICENSE).

---
name: telegram-send
description: >
  Send Telegram messages from Andrey's first-person Telegram userapi session, or
  explicitly from a bot. Use whenever the user asks to send, write, ping, DM,
  reply in Telegram, forward to Telegram, "отправь", "напиши", or "пингани".
  Always use the bundled script for actual Telegram writes.
compatibility: Requires GIT workspace. Userapi needs Telethon plus TELEGRAM_API_ID, TELEGRAM_API_HASH, and TELEGRAM_USER_SESSION or TELEGRAM_USER_SESSION_FILE. Bot mode needs TELEGRAM_BOT_TOKEN.
---

# Telegram Send

Use the script on the server only. It resolves people by name/profile and sends
by userapi by default. If the current agent is local, call it through SSH; do
not run actual Telegram sends locally.

## Commands

Dry-run:

```bash
ssh ai4u.kt.team 'cd /home/a.putin/GIT &&
  python3 .agents/skills/telegram-send/scripts/telegram_send.py \
    --to "Герман" \
    --message "Спокойной ночи, какие планы на день" \
    --dry-run'
```

Send from Andrey:

```bash
ssh ai4u.kt.team 'cd /home/a.putin/GIT &&
  assistants/relationship-warmer/.venv/bin/python \
    .agents/skills/telegram-send/scripts/telegram_send.py \
    --to "Герман" \
    --message "Спокойной ночи, какие планы на день" \
    --yes'
```

Formatted HTML:

```bash
ssh ai4u.kt.team 'cd /home/a.putin/GIT &&
  assistants/relationship-warmer/.venv/bin/python \
    .agents/skills/telegram-send/scripts/telegram_send.py \
    --to "@username" \
    --parse-mode html \
    --message-file /tmp/telegram-message.html \
    --yes'
```

Bot identity, only when explicitly acceptable:

```bash
ssh ai4u.kt.team 'cd /home/a.putin/GIT &&
  python3 .agents/skills/telegram-send/scripts/telegram_send.py \
    --sender bot \
    --to "$TELEGRAM_CHAT_ID" \
    --stdin \
    --yes'
```

## Recipient

`--to` accepts phone, `@username`, numeric id, `peoples/*.md` names such as
`Герман` or `german-putin`, and `telegram-chats/state.json` chat names. The
script fails on ambiguous names.

## Rules

- Default sender is `user`: first-person Telegram userapi.
- Actual sends run from `ai4u.kt.team` / `/home/a.putin/GIT`.
- Never fallback from `user` to `bot` for "от меня".
- Use `--dry-run` first for fuzzy recipients, generated text, sensitive content,
  groups, or channels.
- Use `--message-file` or `--stdin` for long/complex formatted messages.
- Do not put secrets, login codes, 2FA, sessions, or private exports in git.

## Troubleshooting

- `telethon is required`: run with `assistants/relationship-warmer/.venv/bin/python`
  or another venv with Telethon.
- `session ... not authorized`: run `python -m relationship_warmer login-user`
  interactively.
- `Server closed the connection` / timeout: retry once or run from the server/VPN
  environment where MTProto works. Do not switch to bot identity.

Details live in script help:

```bash
ssh ai4u.kt.team 'cd /home/a.putin/GIT &&
  python3 .agents/skills/telegram-send/scripts/telegram_send.py --help'
```

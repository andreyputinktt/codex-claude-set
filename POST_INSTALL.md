# Post-Install Onboarding

Run this after the server bootstrap, Codex device login, and app-server daemon
verification.

## 1. Create The Control Telegram Bot

Goal: the user can message Telegram and reach the chosen backend: Codex by
default, or Claude, Hermes, Cursor, OpenClaw, or a custom command.

If the user did not provide a bot token, guide them:

1. Open Telegram.
2. Start `@BotFather`.
3. Send:

```text
/newbot
```

4. BotFather asks for display name. Suggest:

```text
<Name> AI Server
```

5. BotFather asks for username. It must end with `_bot`. Suggest:

```text
<login>_codex_bot
```

Examples:

```text
ivan_codex_bot
maria_claude_bot
pavel_ai_server_bot
```

6. Ask the user to paste the token into the Codex chat. Do not echo it back.
7. Write the token to the server env file and restart the Telegram bridge.
8. Ask the user to send `/getid` to the bot.
9. Save the returned chat id as the owner id and restart the service.
10. Verify `/status`.
11. Verify dialog controls:
    - `/new` creates a fresh Codex dialog.
    - `/chats` shows recent dialogs as inline buttons.
    - Selecting a button switches the active dialog.

Backend choice question:

```text
Через что должен отвечать этот бот: Codex, Claude, Hermes, Cursor/OpenCode,
OpenClaw или отдельная shell-команда? Если не уверен, ставлю Codex.
```

Default: Codex with full access in `GIT/`.

The control bot keeps bounded recent dialog context and stores dialog state in
`TELEGRAM_DIALOG_STATE` (default `/var/lib/codex-telegram-bridge/dialogs.json`).
`TELEGRAM_DIALOG_BUTTON_LIMIT` controls how many recent chats are shown as
buttons; default is `90`.

## 2. Offer Another Assistant Bot

After the control bot works, ask exactly:

```text
Нужно ли мне создать сейчас еще какого-то тебе бота-ассистента в Telegram?
Идея для старта: личный дневник с ИИ-комментариями, аналог mentor-bot.
```

If the user says yes, collect:

- purpose;
- short bot username suffix;
- target backend: Codex, Claude, Hermes, Cursor/OpenCode, OpenClaw, custom;
- owner-only or multiple allowed users;
- text only or text plus voice/audio;
- memory location and retention;
- daily/weekly summaries;
- external integrations;
- what counts as a useful first MVP.

For BotFather, suggest usernames:

```text
<login>_diary_bot
<login>_mentor_bot
<login>_gmail_bot
<login>_news_bot
```

Create the assistant as a new microservice repo:

```text
GIT/assistants/<assistant-name>
```

Use OpenSpec automatically. Keep root docs as an index only. Store the token in
that assistant repo `.env`, never in git.

## Personal Diary Bot MVP Idea

Small but useful first version:

- user sends text or voice;
- bot transcribes voice when OpenAI provider exists;
- saves entries by date;
- replies with one concise reflection and one question;
- weekly summary finds repeated themes, tensions, wins, and next experiments;
- user can ask "what pattern do you see?" or "summarize my week".

Repo name suggestion:

```text
GIT/assistants/diary-bot
```

Bot username suggestion:

```text
<login>_diary_bot
```

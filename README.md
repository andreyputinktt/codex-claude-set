# Codex-Claude Set

Bootstrap kit for a KT-style personal AI server: Codex CLI, Claude Code,
Hermes Agent, OpenSpec, caveman lite, Telegram control bot, Git automation,
shared env files, ChatGPT remote access, and optional Windows station setup.

This repo is designed for one workflow: an employee opens Codex locally, pastes
the prompt from [PROMPT.md](PROMPT.md), answers the questions, and lets Codex
finish the server setup end to end.

Additional reusable scenarios live in [recipes/](recipes/), including
[recipes/mentor-bot.md](recipes/mentor-bot.md) for a personal mentor bot with
profile, people records, diaries, voice transcription, and Telegram control.

## What It Builds

- Ubuntu server user with sudo and stable SSH keepalive.
- Codex CLI with `sandbox_mode = "danger-full-access"`,
  `approval_policy = "never"`, and explicit
  `[sandbox_workspace_write] network_access = true` fallback.
- Codex app-server daemon with remote control for ChatGPT mobile/web, plus a
  systemd unit, periodic healthcheck timer, and `ai-codex-health` diagnostics.
- Claude Code, OpenCode, OpenClaw, Hermes Agent, OpenSpec, skills CLI, Node,
  Python, Docker, audio/OCR/PDF/dev packages, and Chromium for browser-based
  scrapers.
- `GIT/` root with `README.md`, `DEV.md`, `AGENTS.md`, `CLAUDE.md`,
  `llm-wiki.md`, shared `.env-*` convention, and minimal folder discipline.
- GitHub/GitLab account-level SSH key flow, not one repo deploy keys.
- Safe local secret setter for root shared `.env-*` files and project `.env`
  files, with upload to the Ubuntu server over SSH.
- Helper for creating new microservice repos.
- Telegram bot bridge under the selected Linux user, including `/status`,
  `/getid`, `/run`, `/new`, `/chats`, text-to-Codex, recent-dialog switching by
  inline buttons, and voice/audio transcription when OpenAI is configured.
- Guided post-install flow for BotFather: first create the control bot, then
  ask whether the user wants another Telegram assistant bot.
- Optional local speech transcription microservice shared by all bots.
- Optional Windows station: Git/OpenSSH/Cursor/VS Code plus thin wrappers that
  forward work to the Ubuntu server.

## Fast Start

1. If this is a new Ubuntu server, first ask Codex to check SSH stability before
   the main setup. Ubuntu defaults often drop long SSH sessions, so verify or
   configure keepalive before running the installer.
2. Open [PROMPT.md](PROMPT.md).
3. Paste the whole prompt into Codex.
4. Give Codex:
   - server IP or hostname;
   - OpenAI or Claude login/email for a personal default Linux username;
   - Linux user login to create/use, if different from that default;
   - auth type: password now, SSH key request, or existing SSH key;
   - whether the server is KT-managed;
   - Git provider choices: GitHub, personal GitLab, KT GitLab, or several;
   - Telegram bot token and owner chat id, if Telegram control is needed;
   - OpenAI API key, if voice/audio transcription is needed.
5. Codex copies this repo to the server and runs:

```bash
sudo bash bootstrap.sh
```

6. Codex finishes by running:

```bash
codex login --device-auth
codex app-server daemon bootstrap
codex app-server daemon start
codex app-server daemon enable-remote-control
```

Then the user opens the device link, enters the code, and connects from
ChatGPT/Codex using the same ChatGPT account.

7. Codex continues with [POST_INSTALL.md](POST_INSTALL.md): helps create a
   Telegram bot in BotFather and offers to design another assistant bot.

8. For first-time user setup, run:

```bash
ai-first-run
```

It guides root-folder organization, README skeletons, default server/login,
OpenAI/Anthropic/Gemini/Telegram secrets, mail accounts, GitHub SSH, and
corporate GitLab access.

## Windows Station

Use Windows as a station/client, not as the execution host. The server remains
the source of truth for repos, secrets, `.env-*`, services, daemon state,
Telegram, OpenSpec, and long-running work.

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\windows\bootstrap.ps1 -ServerHost <SERVER_IP_OR_HOST> -ServerUser <LINUX_USER>
```

Then use:

```powershell
ai-shell
codex-server exec "Reply exactly: CODEX_OK"
```

See [WINDOWS.md](WINDOWS.md) and [PROMPT_WINDOWS.md](PROMPT_WINDOWS.md).

## KT Server Access

If the target is a KT-managed server, do not ask for a password first. Generate
or reuse the employee public key and ask Timofeev to add it.

Message template:

```text
Дима, привет! Нужен доступ к серверу для рабочего AI/Codex окружения.

Сервер: <SERVER_IP_OR_HOST>
Пользователь: <LINUX_LOGIN>
Нужны права: sudo, доступ по SSH.
Публичный ключ:
<PUBLIC_SSH_KEY>

После добавления я подключусь и сам разверну Codex/Claude/OpenSpec/Git/Telegram.
```

If the server is not KT-managed, password auth is acceptable for first setup.
After setup, switch to SSH key only.

## Security

- Never commit `.env`, `.env-*`, tokens, passwords, Telegram bot tokens, OpenAI
  API keys, private keys, runtime logs, or exported private data.
- Enter API keys and bot tokens through `scripts/set-secret.sh` on macOS/Linux
  or `windows/set-secret.ps1` on Windows. The scripts prompt with hidden input,
  can ask for several keys in one run, save ignored env files locally, and copy
  them to the server with mode `600`. When a simple token check exists, pass a
  verification command so the script tests the token before upload.
- Git provider access uses account-level SSH keys unless a repository truly
  requires a deploy key.
- Telegram bot must be owner-allowlisted. `/getid` can work before allowlist;
  normal commands must not.
- Codex full access is intentional for this server profile. Do not use this kit
  on shared production servers without explicit approval.

## Updating Local Rules

Employee environments deployed from this kit should periodically check this
upstream repo for updated rules and copy relevant changes into their local
server `GIT/` docs. Use at least a monthly cadence, and always refresh before
large setup, infra, or agent-policy work.

This does not apply to the upstream author while making the changes.

## Scraper Runtime

Browser-based scraper repos need:

- OS packages from bootstrap: `nodejs`, `npm`, `chromium-browser`,
  `fonts-liberation`, `fonts-noto-core`, `fonts-noto-color-emoji`;
- repo-local npm dependencies from `package-lock.json`, installed with
  `npm ci` when the lockfile exists, otherwise `npm install`;
- scraper code should prefer `CHROME_PATH` when set and otherwise auto-detect
  `google-chrome-stable`, `google-chrome`, `chromium-browser`, or `chromium`.

## References

- OpenAI Help: [Using Codex with your ChatGPT plan](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan)
- OpenAI Help: [Codex CLI and Sign in with ChatGPT](https://help.openai.com/en/articles/11381614-api-codex-cli-and-sign-in-with-chatgpt)
- OpenAI Help: [Codex CLI getting started](https://help.openai.com/en/articles/11096431)
- Hermes Agent: [official install docs](https://hermes-agent.nousresearch.com/docs/getting-started/installation/)

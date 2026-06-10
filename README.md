# Codex-Claude Set

Bootstrap kit for a KT-style personal AI server: Codex CLI, Claude Code,
Hermes Agent, OpenSpec, caveman lite, Telegram control bot, Git automation,
shared env files, ChatGPT remote access, and optional Windows station setup.

This repo is designed for one beginner-safe workflow: a user opens Codex or
Claude locally, runs the onboarding wizard or gives the agent
[PROMPT.md](PROMPT.md), answers concrete questions, follows account/server
links, and reaches a working local+server AI workspace.

Additional reusable scenarios live in [recipes/](recipes/), including
[recipes/mentor-bot.md](recipes/mentor-bot.md) for a personal mentor bot with
profile, people records, diaries, voice transcription, and Telegram control.
There is also [recipes/relationship-warmer.md](recipes/relationship-warmer.md)
for a channel-agnostic relationship warmer over Telegram/Gmail plus Telegram
birthday congratulations through first-person userapi.

## What It Builds

- Beginner onboarding for macOS/Linux and Windows: local package checks, SSH
  key preparation, Git provider guidance, provider API key prompts, starter
  workspace creation, and server mirror.
- Ubuntu server user with sudo and stable SSH keepalive.
- Codex CLI with `sandbox_mode = "danger-full-access"`,
  `approval_policy = "never"`, and explicit
  `[sandbox_workspace_write] network_access = true` fallback.
- Codex app-server daemon with remote control for ChatGPT mobile/web, plus a
  systemd unit, periodic healthcheck timer, and `ai-codex-health` diagnostics.
- Weekly boilerplate updater: `ai-boilerplate-refresh.timer` pulls
  `~/GIT/codex-claude-set`, reinstalls bundled helper scripts, refreshes the
  workspace index, updates nested Git ignores, and writes
  `~/GIT/UPSTREAM-INSTRUCTIONS.md`.
- Claude Code, OpenCode, OpenClaw, Hermes Agent, OpenSpec, skills CLI, Node,
  Python, Docker, audio/OCR/PDF/dev packages, and Chromium for browser-based
  scrapers.
- `GIT/` root with `README.md`, `DEV.md`, `AGENTS.md`, `CLAUDE.md`,
  `llm-wiki.md`, shared `.env-*` convention, and minimal folder discipline.
- Generic llm-wiki discipline: root README chooses the folder, each folder
  README owns its details and dependencies, `AGENTS.md`/`CLAUDE.md` stay thin
  pointers, and no root-level thematic routing or dependency graph is generated.
- Matching starter folder shape on the computer and on the server, maintained by
  `ai-index-refresh` and `ai-mirror-workspace`.
- Root `.gitignore` protection for nested Git repositories through
  `ai-ignore-nested-git-repos`, so child repos are not tracked twice by the
  parent workspace index.
- GitHub/GitLab account-level SSH key flow, not one repo deploy keys.
- Safe local secret setter for root shared `.env-*` files and project `.env`
  files, with upload to the Ubuntu server over SSH.
- Helper for creating new microservice repos.
- Telegram bot bridge under the selected Linux user, including `/status`,
  `/getid`, `/run`, `/new`, `/chats`, text-to-agent for Codex or Hermes,
  recent-dialog switching by inline buttons, and voice/audio transcription when
  OpenAI is configured.
- Bundled `telegram-send` skill installable from this repo for first-person
  Telegram userapi sends and optional bot sends.
- Guided post-install flow for BotFather: first create the control bot, then
  ask whether the user wants another Telegram assistant bot.
- Optional local speech transcription microservice shared by all bots.
- Optional Windows station: Git/OpenSSH/Cursor/VS Code plus thin wrappers that
  forward work to the Ubuntu server.

## Fast Start

### macOS / Linux

If Codex or Claude is already installed locally, paste this into it:

```text
Follow codex-claude-set. Run scripts/beginner-onboarding.sh and guide me through
every question until my local and server AI workspace is ready.
```

Or run directly:

```bash
cd codex-claude-set
scripts/beginner-onboarding.sh
```

The wizard asks for:

- personal GitHub and optional work Git provider;
- whether the user is a KT employee;
- server type: KT `ai4u.kt.team`, personal Timeweb/other Ubuntu server, or no
  server yet;
- server IP/hostname and Linux username;
- whether password SSH is available and whether to switch to key-only SSH;
- local starter folder, mirrored server folder, and strict llm-wiki index;
- optional Hermes/OpenClaw backend preference;
- OpenAI, Anthropic/Claude, and Gemini API keys through hidden secret prompts.

KT-specific defaults live in [config/kt.env](config/kt.env), with bash helper
formatting in [config/kt.sh](config/kt.sh). For KT employees the wizard also
asks them to connect project context through OSNO-VA sync-service:

```text
Сходите в https://sync-service.osno-va.com/ и нажмите кнопку "Подключить агента" и дайте последнюю инструкцию установки в этот чат.
```

When SSH works, Codex copies this repo to the server and runs:

```bash
sudo bash bootstrap.sh
```

Then Codex finishes by running:

```bash
codex login --device-auth
codex app-server daemon bootstrap --remote-control
codex app-server daemon start
codex app-server daemon enable-remote-control
ai-codex-health
```

Then the user opens the device link, enters the code, and connects from
ChatGPT/Codex using the same ChatGPT account.

Codex continues with [POST_INSTALL.md](POST_INSTALL.md): helps create a Telegram
bot in BotFather and offers to design another assistant bot.

For first-time user setup on the server, run:

```bash
ai-first-run
```

It guides root-folder organization, README skeletons, default server/login,
OpenAI/Anthropic/Gemini/Telegram secrets, mail accounts, GitHub SSH, and
corporate GitLab access.

`ai-index-refresh` also checks nested Git repositories and appends their paths to
the root `.gitignore`. To run that check directly:

```bash
ai-ignore-nested-git-repos --root ~/GIT
```

### Windows

Run the Windows beginner wrapper:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\windows\onboarding.ps1
```

It creates the same local starter folder contract, configures Windows as a thin
station, creates/reuses SSH keys, and then uses Remote SSH / `ai-shell` /
`codex-server` to work on the Ubuntu server.

### Manual Agent Prompt

If the user cannot run scripts directly, open [PROMPT.md](PROMPT.md), paste it
into Codex/Claude, and answer the questions. The prompt instructs the agent to
use the same scripts instead of improvising.

## Bundled Skills

Install bundled skills into an existing server workspace:

```bash
cd ~/GIT/codex-claude-set
scripts/install-skills.sh --git-root ~/GIT --home "$HOME"
```

The `telegram-send` skill is installed into `GIT/.agents/skills` and
`~/.agents/skills`, with lightweight Codex/Claude/Hermes/Cursor adapters in the
workspace.

## Windows Station

Use Windows as a station/client, not as the execution host. The server remains
the source of truth for repos, secrets, `.env-*`, services, daemon state,
Telegram, OpenSpec, and long-running work.

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\windows\onboarding.ps1
```

Then use:

```powershell
ai-shell
codex-server exec "Reply exactly: CODEX_OK"
```

See [WINDOWS.md](WINDOWS.md) and [PROMPT_WINDOWS.md](PROMPT_WINDOWS.md).

## KT Server Access

KT defaults are configured in [config/kt.env](config/kt.env): AI server host,
corporate GitLab URL, sync-service URL, and the employee project-context request.

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

Employee environments deployed from this kit install a weekly updater:

```bash
systemctl status ai-boilerplate-refresh.timer --no-pager
sudo systemctl start ai-boilerplate-refresh.service
```

The updater pulls `~/GIT/codex-claude-set`, reinstalls bundled helper scripts,
runs `ai-index-refresh`, updates nested Git ignores, and writes
`~/GIT/UPSTREAM-INSTRUCTIONS.md`. Agents should read that file and the current
upstream `README.md`, `DEV.md`, `INSTALL.md`, and relevant recipes before large
setup, infrastructure, or agent-policy work.

The updater does not overwrite local workspace `README.md` or `DEV.md`; local
facts stay local.

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

# Prompt To Paste Into Codex

You are setting up my KT-style Codex/Claude AI server. Work end to end. Do not
stop at a plan unless you are blocked by missing credentials. Use safe defaults,
but ask me for values that cannot be inferred.

Goal: make the target server work like Andrey's AI automation server:

- Codex CLI installed and configured with full access:
  `approval_policy = "never"`, `sandbox_mode = "danger-full-access"`, and network enabled.
- Codex app-server daemon running with remote control, so I can connect from
  ChatGPT/Codex on tablet or web.
- Claude Code, OpenCode, OpenClaw, Hermes Agent, OpenSpec, skills CLI, Node/npm,
  Python, Docker, git, gh, audio/OCR/PDF/dev packages installed.
- `GIT/` root configured with README/DEV/AGENTS/CLAUDE/llm-wiki principles.
- `caveman lite` is the default communication style; I should not need to ask.
- OpenSpec is automatic for real code/behavior/deploy changes; I should not need
  to name it.
- Telegram control bot works under my Linux user. It must support text, `/run`,
  `/status`, `/getid`, and voice/audio transcription if OpenAI API key exists.
- Git creation is automatic: decide whether a request is a new microservice or a
  change to an existing repo. Create a new repo when needed.
- Git provider setup guides me through GitHub, personal GitLab, KT GitLab, or
  several providers at once.
- Shared OpenAI env is stored once as `GIT/.env-openai` and loaded by bots.
- No secrets in git.

First ask me these questions, one compact batch:

1. Server IP/hostname.
2. OpenAI or Claude login/email, used to derive a personal default Linux
   username.
3. Linux username to create/use, if different from that personal default. Do not
   use generic names such as `ai`.
4. Is this server KT-managed? If yes, prepare SSH key access request for
   Timofeev. If no, ask whether to use password now or existing SSH key.
5. Git provider choices: GitHub, GitLab personal, GitLab KT, or several.
6. GitHub/GitLab username/group namespace.
7. Whether this computer is Windows and should be configured as a station.
8. Telegram bot token and owner chat id, or "help me create Telegram bot".
9. OpenAI API key, or "skip voice transcription".

Server access rules:

- If this is a new Ubuntu server, check SSH stability before the main setup.
  Ubuntu defaults often drop long SSH sessions, so verify or configure server
  keepalive first and keep the current session open until a second SSH login
  works.
- If KT-managed, do not require password first. Generate/reuse an SSH public key
  and give me this SMS for Timofeev:

```text
Дима, привет! Нужен доступ к серверу для рабочего AI/Codex окружения.

Сервер: <SERVER_IP_OR_HOST>
Пользователь: <LINUX_LOGIN>
Нужны права: sudo, доступ по SSH.
Публичный ключ:
<PUBLIC_SSH_KEY>

После добавления я подключусь и сам разверну Codex/Claude/OpenSpec/Git/Telegram.
```

- If not KT-managed, password auth is acceptable for the first setup. Configure
  SSH keepalive and later recommend switching to key-only auth.

User naming rules:

- If the Linux username is not explicitly given, derive it from the OpenAI or
  Claude login/email. Example: `ivan.petrov@example.com` becomes `ivan-petrov`.
- Never default to generic names such as `ai`. The server user should make clear
  which human owns the environment.

Windows station rules:

- If the user works from Windows, treat Windows as a station/client by default.
- Do not create project state, secrets, repos, services, or long-running
  processes on Windows unless explicitly requested.
- Use SSH into the configured Ubuntu AI server and work under `~/GIT`.
- Local Windows commands are for station setup, SSH verification, editor setup,
  and thin wrappers only.

Implementation:

1. For a new Ubuntu server, verify SSH keepalive/stability before copying or
   running the installer.
2. Clone or create this setup repo locally as `codex-claude-set`.
3. Copy it to the server under `/tmp/codex-claude-set`.
4. Run `sudo bash /tmp/codex-claude-set/bootstrap.sh`.
5. Answer installer prompts using the values I gave you.
6. Verify:
   - `codex --version`
   - `claude --version`
   - `openclaw --version`
   - `hermes --version`
   - `openspec --version`
   - `skills --version`
   - `codex login status`
   - `codex app-server daemon version`
   - Telegram service status if configured
   - speech transcriber health if configured
   - `ssh -T git@github.com` or GitLab equivalent if provider key was added
7. If the user works from Windows, configure it with `windows/bootstrap.ps1`,
   verify `ai-server`, and explain `ai-shell`, `codex-server`, and Cursor/VS
   Code Remote SSH into `ai-server:~/GIT`.
8. Run `codex login --device-auth`, give me the URL and code, and wait while I
   complete login.
9. After login, run:

```bash
codex app-server daemon bootstrap
codex app-server daemon start
codex app-server daemon enable-remote-control
codex app-server daemon restart
codex app-server daemon version
```

10. Help me open ChatGPT/Codex remote access:
   - same ChatGPT account as device login;
   - workspace/admin setting must allow Codex Local and Remote Control when the
     account is Business/Enterprise/Edu;
   - open ChatGPT mobile/web, go to Codex, choose remote/local app connection,
     and follow the app instructions.
11. Run the post-install Telegram onboarding:
   - If I did not provide a Telegram bot token, help me create one through
     BotFather.
   - Explain exactly what to type:
     `/newbot`, display name, then username in the format
     `<login>_<shortPurpose>_bot`, for example `ivan_codex_bot`,
     `maria_diary_bot`, or `pavel_gmail_bot`.
   - Tell me to paste the token directly into this chat after BotFather gives it.
   - Help me get my chat id with `/getid` after the bot service starts.
   - Ask which agent the bot should call: Codex, Claude, Hermes, Cursor, or a
     custom shell command. Default to Codex when unsure.
12. After the control bot works, ask:

```text
Нужно ли мне создать сейчас еще какого-то тебе бота-ассистента в Telegram?
Идея для старта: личный дневник с ИИ-комментариями, аналог mentor-bot.
```

If I say yes, talk through requirements:

- purpose and short bot username suffix;
- who can access it;
- where memory should live;
- text only or voice/audio too;
- daily/weekly summaries;
- whether it should use Codex, Claude, Hermes, Cursor, or another backend.

Then start a new Codex/Claude implementation session or give me a ready prompt
for a new session. Help me create the BotFather key for that assistant using a
short username like `<login>_<purpose>_bot`, and ask me to paste the token into
the chat. Create the assistant as a new microservice repo under
`GIT/assistants/<name>` unless it is clearly just a small adapter.

If ChatGPT shows "waiting for desktop app", check on the server:

```bash
codex login status
codex app-server daemon version
pgrep -a -u "$USER" -f "codex|app-server"
ss -xlpn | grep app-server
```

Restart the daemon after successful login.

Deliverables:

- Server is configured.
- If requested, Windows station is configured as a thin client to the server.
- The user knows what was installed and how to connect.
- The root `GIT/` docs describe current server, Git providers, Telegram, env,
  OpenSpec, caveman lite, repo creation, and deploy/autosync.
- Telegram onboarding is complete or explicitly skipped.
- No secret is printed in final output.

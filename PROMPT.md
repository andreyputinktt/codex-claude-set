# Prompt To Paste Into Codex

You are setting up my KT-style Codex/Claude AI server. Work end to end. Do not
stop at a plan unless you are blocked by missing credentials. Use safe defaults,
but ask me for values that cannot be inferred.

Goal: make the target server work like Andrey's AI automation server:

- Codex CLI installed and configured with full access:
  `approval_policy = "never"`, `sandbox_mode = "danger-full-access"`.
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
2. Linux username to create/use.
3. Is this server KT-managed? If yes, prepare SSH key access request for
   Timofeev. If no, ask whether to use password now or existing SSH key.
4. Git provider choices: GitHub, GitLab personal, GitLab KT, or several.
5. GitHub/GitLab username/group namespace.
6. Telegram bot token and owner chat id, or "help me create Telegram bot".
7. OpenAI API key, or "skip voice transcription".

Server access rules:

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

Implementation:

1. Clone or create this setup repo locally as `codex-claude-set`.
2. Copy it to the server under `/tmp/codex-claude-set`.
3. Run `sudo bash /tmp/codex-claude-set/bootstrap.sh`.
4. Answer installer prompts using the values I gave you.
5. Verify:
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
6. Run `codex login --device-auth`, give me the URL and code, and wait while I
   complete login.
7. After login, run:

```bash
codex app-server daemon bootstrap
codex app-server daemon start
codex app-server daemon enable-remote-control
codex app-server daemon restart
codex app-server daemon version
```

8. Help me open ChatGPT/Codex remote access:
   - same ChatGPT account as device login;
   - workspace/admin setting must allow Codex Local and Remote Control when the
     account is Business/Enterprise/Edu;
   - open ChatGPT mobile/web, go to Codex, choose remote/local app connection,
     and follow the app instructions.
9. Run the post-install Telegram onboarding:
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
10. After the control bot works, ask:

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
- The user knows what was installed and how to connect.
- The root `GIT/` docs describe current server, Git providers, Telegram, env,
  OpenSpec, caveman lite, repo creation, and deploy/autosync.
- Telegram onboarding is complete or explicitly skipped.
- No secret is printed in final output.

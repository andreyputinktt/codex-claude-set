#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run as root or via sudo: sudo bash bootstrap.sh" >&2
    exit 1
  fi
}

ask() {
  local name="$1"
  local prompt="$2"
  local default="${3:-}"
  local value
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " value || true
    value="${value:-$default}"
  else
    read -r -p "$prompt: " value || true
  fi
  printf -v "$name" "%s" "$value"
}

ask_secret() {
  local name="$1"
  local prompt="$2"
  local value
  read -r -s -p "$prompt (empty to skip): " value || true
  echo
  printf -v "$name" "%s" "$value"
}

sanitize_linux_user() {
  local raw="$1"
  local base="${raw%@*}"
  base="$(printf "%s" "$base" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//')"
  if [[ -z "$base" ]]; then
    base="codexuser"
  fi
  if [[ ! "$base" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    base="u-$base"
  fi
  printf "%s" "${base:0:30}"
}

as_user() {
  sudo -H -u "$SETUP_USER" bash -lc "$*"
}

write_user_file() {
  local path="$1"
  local mode="$2"
  local owner="$SETUP_USER:$SETUP_USER"
  install -D -m "$mode" /dev/null "$path"
  chown "$owner" "$path"
  cat > "$path"
  chown "$owner" "$path"
}

need_root

DEFAULT_USER="${SUDO_USER:-}"
[[ "$DEFAULT_USER" == "root" ]] && DEFAULT_USER=""
ask LOGIN_HINT "OpenAI/Claude login or email for default Linux username" ""
if [[ -n "$LOGIN_HINT" ]]; then
  DEFAULT_USER="$(sanitize_linux_user "$LOGIN_HINT")"
fi
ask SETUP_USER "Linux user to create/use" "${DEFAULT_USER:-codexuser}"
ask GIT_NAMESPACE "GitHub/GitLab namespace or username" "$SETUP_USER"
ask SERVER_LABEL "Server label or hostname for SSH key titles" "$(hostname -f 2>/dev/null || hostname)"
ask DEFAULT_MODEL "Default Codex model" "gpt-5.5"
ask TELEGRAM_MODE "Configure Telegram bridge? yes/no" "no"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_OWNER_CHAT_ID=""
if [[ "$TELEGRAM_MODE" =~ ^[Yy] ]]; then
  ask_secret TELEGRAM_BOT_TOKEN "Telegram bot token"
  ask TELEGRAM_OWNER_CHAT_ID "Telegram owner chat id"
fi
ask_secret OPENAI_API_KEY "OpenAI API key for shared provider and transcription"

USER_HOME="/home/$SETUP_USER"
GIT_ROOT="$USER_HOME/GIT"

if ! id "$SETUP_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$SETUP_USER"
fi

usermod -aG sudo "$SETUP_USER"
install -D -m 0440 /dev/null "/etc/sudoers.d/90-$SETUP_USER-ai"
printf "%s ALL=(ALL) NOPASSWD:ALL\n" "$SETUP_USER" > "/etc/sudoers.d/90-$SETUP_USER-ai"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  apt-transport-https ca-certificates curl gnupg lsb-release software-properties-common \
  build-essential pkg-config git git-lfs gh jq unzip zip rsync tmux htop tree ripgrep fd-find \
  net-tools iproute2 dnsutils openssh-client openssh-server sshpass sudo \
  python3 python3-venv python3-pip python3-dev pipx \
  nodejs npm \
  chromium-browser fonts-liberation fonts-noto-core fonts-noto-color-emoji \
  docker.io docker-compose-v2 \
  ffmpeg sox libmagic1 poppler-utils tesseract-ocr tesseract-ocr-rus imagemagick \
  sqlite3 postgresql-client redis-tools \
  shellcheck yamllint

usermod -aG docker "$SETUP_USER" || true
systemctl enable --now docker >/dev/null 2>&1 || true

mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/01-codex-stable-connections.conf <<'EOF'
TCPKeepAlive yes
ClientAliveInterval 30
ClientAliveCountMax 240
MaxStartups 50:30:200
LoginGraceTime 2m
EOF
sshd -t
systemctl reload ssh || systemctl reload sshd || true

npm install -g npm@latest
npm install -g \
  @openai/codex \
  @anthropic-ai/claude-code \
  opencode-ai \
  openclaw \
  @fission-ai/openspec \
  openspec-extensions \
  openspec-mcp \
  openspec-webui \
  skills

if ! command -v hermes >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh \
    | HERMES_HOME=/root/.hermes bash -s -- --skip-setup
fi

# The upstream root installer may create a venv whose Python points into
# /root/.local. Move that runtime to a world-readable FHS path so every Linux
# user can execute /usr/local/bin/hermes.
if [[ -L /usr/local/lib/hermes-agent/venv/bin/python ]]; then
  HERMES_PY="$(readlink -f /usr/local/lib/hermes-agent/venv/bin/python || true)"
  if [[ "$HERMES_PY" == /root/.local/share/uv/python/*/bin/python3.11 ]]; then
    HERMES_PY_DIR="$(cd "$(dirname "$HERMES_PY")/.." && pwd)"
    install -d -m 0755 /usr/local/lib/uv-python
    rsync -a --delete "$HERMES_PY_DIR/" /usr/local/lib/uv-python/"$(basename "$HERMES_PY_DIR")"/
    ln -sfn /usr/local/lib/uv-python/"$(basename "$HERMES_PY_DIR")" /usr/local/lib/uv-python/cpython-3.11-linux-x86_64-gnu
    ln -sfn /usr/local/lib/uv-python/cpython-3.11-linux-x86_64-gnu/bin/python3.11 /usr/local/lib/hermes-agent/venv/bin/python
    chmod -R a+rX /usr/local/lib/uv-python /usr/local/lib/hermes-agent
    chmod +x /usr/local/bin/hermes
  fi
fi

install -d -o "$SETUP_USER" -g "$SETUP_USER" "$USER_HOME/.ssh" "$GIT_ROOT" \
  "$USER_HOME/.codex" "$USER_HOME/.agents/skills" "$GIT_ROOT/assistants"
chmod 700 "$USER_HOME/.ssh"

KEY="$USER_HOME/.ssh/github_account_ed25519"
if [[ ! -f "$KEY" ]]; then
  as_user "ssh-keygen -t ed25519 -N '' -C 'github-account@$SERVER_LABEL' -f '$KEY'"
fi

as_user "git config --global user.name '$GIT_NAMESPACE'"
as_user "git config --global user.email '$GIT_NAMESPACE@users.noreply.github.com'"
as_user "git config --global init.defaultBranch main"
as_user "git config --global pull.rebase true"
as_user "git config --global rebase.autoStash true"
as_user "git config --global push.default simple"

cat > "$USER_HOME/.ssh/config" <<EOF
Host github.com
  HostName github.com
  User git
  IdentityFile $KEY
  IdentitiesOnly yes

Host gitlab.com
  HostName gitlab.com
  User git
  IdentityFile $KEY
  IdentitiesOnly yes

Host gitlab.kt.team
  HostName gitlab.kt.team
  User git
  IdentityFile $KEY
  IdentitiesOnly yes
EOF
chown "$SETUP_USER:$SETUP_USER" "$USER_HOME/.ssh/config"
chmod 600 "$USER_HOME/.ssh/config"

cat > "$USER_HOME/.codex/config.toml" <<EOF
model = "$DEFAULT_MODEL"
model_reasoning_effort = "high"
approval_policy = "never"
sandbox_mode = "danger-full-access"

[sandbox_workspace_write]
network_access = true

[projects."$GIT_ROOT"]
trust_level = "trusted"
EOF
chown "$SETUP_USER:$SETUP_USER" "$USER_HOME/.codex/config.toml"
chmod 600 "$USER_HOME/.codex/config.toml"

cat > "$GIT_ROOT/README.md" <<EOF
# Repository Index

Root workspace for AI-assisted work. Read this file first, then \`DEV.md\`,
then the target repo README.

## Principles

- Loose coupling: each service or assistant is its own repo.
- README files are indexes, not diaries.
- OpenSpec is automatic for behavior/code/deploy changes.
- Caveman lite is the default response style.
- Secrets stay in ignored \`.env\` files.
- Windows workstations are clients only; run code, git, env, services, and
  long-running tasks on this Ubuntu server unless local Windows work is
  explicitly requested.

## Repos

Add new repos here as they are created.
EOF

cat > "$GIT_ROOT/DEV.md" <<EOF
# Development And Server Rules

Server: $SERVER_LABEL
User: $SETUP_USER
Git root: $GIT_ROOT

## Style

Default to caveman lite: short, clear, no filler.

## Caveman And Context Economy

Caveman is an agent/Claude skill set, not a required shell command. Do not assume
\`caveman\` exists in PATH.

- Normal replies: \`caveman lite\`.
- Broad search / locate / review: prefer \`cavecrew\` so subagent output is
  compressed before it enters main context.
- Commit/review text: use \`caveman-commit\` / \`caveman-review\` when the task
  matches.
- Long prose memory/docs files: use \`caveman-compress\` only when explicitly
  useful. Do not compress code, configs, env, logs, or OpenSpec artifacts by
  default.

## Env

Shared providers live at root as ignored files:

- \`.env-openai\`
- \`.env-anthropic\`
- \`.env-gemini\`
- \`.env-github\`
- \`.env-gitlab\`
- \`.env-telegram\`

Service-specific secrets live in that service repo \`.env\`.

## Git

Use account-level SSH keys for GitHub/GitLab. Public key:

\`\`\`text
$(cat "$KEY.pub")
\`\`\`

New standalone service, bot, API, job, or UI means new repo. Changes to an
existing service happen in that repo. Root \`GIT/\` is only an index and shared
infrastructure.

## Windows Station

If the user connects from Windows, treat Windows as a station/client. Use SSH or
editor Remote SSH into this server and work under \`$GIT_ROOT\`. Do not create
project state, secrets, repos, services, or long-running processes on Windows
unless explicitly requested.

## OpenSpec

Use OpenSpec automatically for behavior, code, deploy, integration, schema, bot,
prompt, or workflow changes.

## Codex Stability

Passwordless sudo is expected for this server profile. Do not repeatedly ask the
user whether sudo is available; verify with \`sudo -n true\` when needed.

Codex is configured for long SSH-driven work through the app-server daemon:

- systemd unit: \`codex-app-server-daemon.service\`;
- health timer: \`codex-app-server-healthcheck.timer\`;
- quick check: \`ai-codex-health\`.

When investigating \`codex run stopped\`, do not dump raw
\`~/.codex/sessions/**/*.jsonl\`, screenshots, base64, or broad \`rg\` output
into the agent context. Parse and summarize first. Large raw tool outputs can
inflate a turn past 150k input tokens and cause another stopped run.

Use \`ai-codex-session-summary\` or bounded \`jq\` filters for session logs.

## Telegram

Bots must be owner-allowlisted. \`/getid\` may work before allowlist. Text,
voice, and audio are expected inputs.
EOF

cat > "$GIT_ROOT/llm-wiki.md" <<'EOF'
# LLM Wiki

Start with root README, then DEV, then the target repo README. Every repo keeps
README.md, AGENTS.md, CLAUDE.md, and DEV.md when needed. One fact lives in one
place. Keep folders minimal.
EOF

cat > "$GIT_ROOT/AGENTS.md" <<'EOF'
# Agent guide
@README.md

Dev rules: [DEV.md](DEV.md).
EOF

cat > "$GIT_ROOT/CLAUDE.md" <<'EOF'
@README.md
EOF

cat > "$GIT_ROOT/.gitignore" <<'EOF'
.env
.env-*
!.env.example
node_modules/
.venv/
venv/
__pycache__/
*.py[cod]
*.log
logs/
tmp/
.cache/
.DS_Store
assistants/*/
EOF

chown -R "$SETUP_USER:$SETUP_USER" "$GIT_ROOT"

if [[ -n "$OPENAI_API_KEY" ]]; then
  cat > "$GIT_ROOT/.env-openai" <<EOF
OPENAI_API_KEY=$OPENAI_API_KEY
OPENAI_DEFAULT_MODEL=$DEFAULT_MODEL
OPENAI_FAST_MODEL=gpt-5.4-mini
OPENAI_TRANSCRIPTION_MODEL=gpt-4o-transcribe
OPENAI_TRANSCRIPTION_LANGUAGE=ru
OPENAI_TRANSCRIPTION_PROMPT=Clean Russian speech transcription. Preserve names, product terms, and commands.
EOF
  chown "$SETUP_USER:$SETUP_USER" "$GIT_ROOT/.env-openai"
  chmod 600 "$GIT_ROOT/.env-openai"
fi

if [[ ! -d "$GIT_ROOT/.git" ]]; then
  as_user "cd '$GIT_ROOT' && git init && git add README.md DEV.md llm-wiki.md AGENTS.md CLAUDE.md .gitignore && git commit -m 'Initialize AI server index' || true"
fi

cat > /usr/local/bin/ai-new-repo <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
name="${1:?usage: ai-new-repo <name> [description]}"
description="${2:-AI microservice}"
root="${GIT_ROOT:-$HOME/GIT}"
owner="${GIT_NAMESPACE:-$(git config --global user.name || whoami)}"
path="$root/$name"
mkdir -p "$path"
cd "$path"
git init
cat > README.md <<README
# $name

$description

## Run

Document local and server commands here.
README
cat > AGENTS.md <<'AGENTS'
# Agent guide
@README.md

Dev rules: [DEV.md](DEV.md).
AGENTS
cat > CLAUDE.md <<'CLAUDE'
@README.md
CLAUDE
cat > DEV.md <<'DEV'
# Development

Use OpenSpec for behavior/code/deploy changes. Keep secrets out of git.
DEV
cat > .gitignore <<'IGNORE'
.env
.env-*
!.env.example
.venv/
node_modules/
__pycache__/
*.log
IGNORE
openspec init . --tools codex >/dev/null 2>&1 || true
git add .
git commit -m "Initialize $name" || true
git remote add origin "git@github.com:$owner/$name.git" 2>/dev/null || true
echo "Created $path"
echo "If GitHub is authenticated: gh repo create $owner/$name --private --source . --remote origin --push"
EOF
chmod 755 /usr/local/bin/ai-new-repo

cat > /usr/local/bin/ai-git-autosync <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
root="${1:-$HOME/GIT}"
find "$root" -maxdepth 3 -name .git -type d | while read -r gitdir; do
  repo="$(dirname "$gitdir")"
  cd "$repo"
  git add -A
  if ! git diff --cached --quiet; then
    git commit -m "Autosync $(date -u +%Y-%m-%dT%H:%M:%SZ)" || true
  fi
  git pull --rebase --autostash || true
  git push || true
done
EOF
chmod 755 /usr/local/bin/ai-git-autosync

cat > /usr/local/bin/ai-codex-health <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "== codex versions =="
command -v codex || true
codex --version || true
codex login status || true
codex app-server daemon version || true

echo
echo "== processes =="
pgrep -a -u "$USER" -f "codex|app-server" || true

echo
echo "== systemd =="
systemctl status codex-app-server-daemon --no-pager || true
systemctl status codex-app-server-healthcheck.timer --no-pager || true

echo
echo "== app-server logs =="
tail -n 80 "$HOME/.codex/app-server-control/app-server.log" 2>/dev/null || true
tail -n 80 "$HOME/.codex/app-server-daemon/app-server.stderr.log" 2>/dev/null || true
tail -n 80 "$HOME/.codex/app-server-daemon/app-server-updater.stderr.log" 2>/dev/null || true

echo
echo "== latest session token counts =="
latest="$(find "$HOME/.codex/sessions" -type f -name '*.jsonl' 2>/dev/null | sort | tail -n 1 || true)"
if [[ -n "$latest" ]]; then
  echo "$latest"
  jq -r '
    select(.type=="event_msg" and .payload.type=="token_count")
    | [
        .timestamp,
        (.payload.info.last_token_usage.input_tokens // ""),
        (.payload.info.total_token_usage.total_tokens // ""),
        (.payload.info.model_context_window // ""),
        (.payload.rate_limits.primary.used_percent // ""),
        (.payload.rate_limits.secondary.used_percent // "")
      ]
    | @tsv
  ' "$latest" 2>/dev/null | tail -n 20 || true
fi
EOF
chmod 755 /usr/local/bin/ai-codex-health

cat > /usr/local/bin/ai-codex-session-summary <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -gt 0 ]]; then
  files=("$@")
else
  mapfile -t files < <(find "$HOME/.codex/sessions" -type f -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 5 | cut -d' ' -f2-)
fi

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "No Codex session files found."
  exit 0
fi

for file in "${files[@]}"; do
  [[ -f "$file" ]] || continue
  echo "== $file =="
  jq -r '
    select(.type=="event_msg")
    | [
        .timestamp,
        (.payload.type // ""),
        (.payload.info.last_token_usage.input_tokens // ""),
        (.payload.info.total_token_usage.total_tokens // ""),
        (.payload.info.model_context_window // ""),
        (.payload.rate_limits.primary.used_percent // ""),
        (.payload.rate_limits.secondary.used_percent // ""),
        ((.payload.message // "") | gsub("[\r\n]+"; " ") | .[0:220])
      ]
    | @tsv
  ' "$file" 2>/dev/null | tail -n 80 || true
done
EOF
chmod 755 /usr/local/bin/ai-codex-session-summary

cat > /etc/systemd/system/ai-git-autosync.service <<EOF
[Unit]
Description=AI git autosync for $SETUP_USER

[Service]
Type=oneshot
User=$SETUP_USER
Environment=GIT_ROOT=$GIT_ROOT
ExecStart=/usr/local/bin/ai-git-autosync $GIT_ROOT
EOF

cat > /etc/systemd/system/ai-git-autosync.timer <<'EOF'
[Unit]
Description=Run AI git autosync every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=ai-git-autosync.service

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now ai-git-autosync.timer >/dev/null 2>&1 || true

if [[ "$TELEGRAM_MODE" =~ ^[Yy] && -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_OWNER_CHAT_ID" ]]; then
  install -d -m 0755 /opt/codex-telegram-bridge
  install -m 0755 "$SCRIPT_DIR/telegram-bridge.py" /opt/codex-telegram-bridge/bridge.py
  cat > /etc/codex-telegram-bridge.env <<EOF
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
TELEGRAM_OWNER_CHAT_ID=$TELEGRAM_OWNER_CHAT_ID
CODEX_USER=$SETUP_USER
CODEX_WORKDIR=$GIT_ROOT
TRANSCRIBE_URL=http://127.0.0.1:8765/v1/transcribe
EOF
  chmod 600 /etc/codex-telegram-bridge.env
  cat > /etc/systemd/system/codex-telegram-bridge.service <<'EOF'
[Unit]
Description=Codex Telegram Bridge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/codex-telegram-bridge.env
ExecStart=/usr/bin/python3 /opt/codex-telegram-bridge/bridge.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  python3 -m venv /opt/codex-telegram-bridge/.venv
  /opt/codex-telegram-bridge/.venv/bin/pip install --upgrade pip >/dev/null
  /opt/codex-telegram-bridge/.venv/bin/pip install requests >/dev/null
  sed -i 's#ExecStart=/usr/bin/python3#ExecStart=/opt/codex-telegram-bridge/.venv/bin/python#' /etc/systemd/system/codex-telegram-bridge.service
  systemctl daemon-reload
  systemctl enable --now codex-telegram-bridge.service
fi

if [[ -n "$OPENAI_API_KEY" ]]; then
  install -d -m 0755 /opt/speech-transcriber
  install -m 0755 "$SCRIPT_DIR/speech-transcriber.py" /opt/speech-transcriber/app.py
  python3 -m venv /opt/speech-transcriber/.venv
  /opt/speech-transcriber/.venv/bin/pip install --upgrade pip >/dev/null
  /opt/speech-transcriber/.venv/bin/pip install fastapi uvicorn python-multipart openai >/dev/null
  cat > /etc/systemd/system/speech-transcriber.service <<EOF
[Unit]
Description=Shared OpenAI speech transcriber
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SETUP_USER
WorkingDirectory=/opt/speech-transcriber
EnvironmentFile=$GIT_ROOT/.env-openai
ExecStart=/opt/speech-transcriber/.venv/bin/uvicorn app:app --host 127.0.0.1 --port 8765
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now speech-transcriber.service
fi

cat > /etc/systemd/system/codex-app-server-daemon.service <<EOF
[Unit]
Description=Ensure Codex app-server daemon for $SETUP_USER
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$SETUP_USER
Group=$SETUP_USER
Environment=HOME=$USER_HOME
Environment=PATH=/usr/local/bin:/usr/bin:/bin
WorkingDirectory=$GIT_ROOT
ExecStart=/usr/local/bin/codex app-server daemon bootstrap --remote-control
ExecStart=/usr/local/bin/codex app-server daemon start
ExecStart=/usr/local/bin/codex app-server daemon enable-remote-control
ExecStart=/usr/local/bin/codex app-server daemon version
ExecStop=/usr/local/bin/codex app-server daemon stop
RemainAfterExit=yes
TimeoutStartSec=90
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/codex-app-server-healthcheck.service <<EOF
[Unit]
Description=Healthcheck Codex app-server daemon for $SETUP_USER
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=$SETUP_USER
Group=$SETUP_USER
Environment=HOME=$USER_HOME
Environment=PATH=/usr/local/bin:/usr/bin:/bin
WorkingDirectory=$GIT_ROOT
ExecStart=/usr/local/bin/codex app-server daemon start
ExecStart=/usr/local/bin/codex app-server daemon enable-remote-control
ExecStart=/usr/local/bin/codex app-server daemon version
TimeoutStartSec=60
EOF
cat > /etc/systemd/system/codex-app-server-healthcheck.timer <<'EOF'
[Unit]
Description=Run Codex app-server daemon healthcheck periodically

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s
Persistent=true
Unit=codex-app-server-healthcheck.service

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now codex-app-server-daemon.service >/dev/null 2>&1 || true
systemctl enable --now codex-app-server-healthcheck.timer >/dev/null 2>&1 || true

echo
echo "=== Public SSH key for Git providers ==="
cat "$KEY.pub"
echo
echo "=== Timofeev SMS template ==="
cat <<EOF
Дима, привет! Нужен доступ к серверу для рабочего AI/Codex окружения.

Сервер: $SERVER_LABEL
Пользователь: $SETUP_USER
Нужны права: sudo, доступ по SSH.
Публичный ключ:
$(cat "$KEY.pub")

После добавления я подключусь и сам разверну Codex/Claude/OpenSpec/Git/Telegram.
EOF
echo
echo "=== Next ==="
echo "1. Add this key to GitHub/GitLab account-level SSH keys."
echo "2. Run as $SETUP_USER: codex login --device-auth"
echo "3. After login: codex app-server daemon bootstrap --remote-control && codex app-server daemon restart && ai-codex-health"
echo "4. In ChatGPT/Codex, use the same ChatGPT account and connect to remote/local Codex."

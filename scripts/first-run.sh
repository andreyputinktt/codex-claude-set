#!/usr/bin/env bash
set -euo pipefail

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

ask_yes_no() {
  local name="$1"
  local prompt="$2"
  local default="${3:-yes}"
  local value
  read -r -p "$prompt [$default]: " value || true
  value="${value:-$default}"
  if [[ "$value" =~ ^[YyДд] ]]; then
    printf -v "$name" "yes"
  else
    printf -v "$name" "no"
  fi
}

info() {
  echo
  echo "==> $*"
}

write_if_missing() {
  local path="$1"
  shift
  if [[ -f "$path" ]]; then
    return
  fi
  mkdir -p "$(dirname "$path")"
  printf "%s\n" "$@" > "$path"
}

append_or_replace_env() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  if [[ -f "$file" ]]; then
    awk -v key="$key" '
      BEGIN { pattern = "^[[:space:]]*" key "[[:space:]]*=" }
      $0 !~ pattern { print }
    ' "$file" > "$tmp"
  fi
  printf "%s=%s\n" "$key" "$value" >> "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

find_set_secret() {
  local script_dir repo_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_dir="$(cd "$script_dir/.." && pwd)"
  if command -v ai-set-secret >/dev/null 2>&1; then
    command -v ai-set-secret
    return
  fi
  if [[ -x "$script_dir/set-secret.sh" ]]; then
    printf "%s\n" "$script_dir/set-secret.sh"
    return
  fi
  if [[ -x "$repo_dir/scripts/set-secret.sh" ]]; then
    printf "%s\n" "$repo_dir/scripts/set-secret.sh"
    return
  fi
  echo "set-secret.sh not found" >&2
  exit 1
}

set_secret() {
  local name="$1"
  local provider="$2"
  local verify_command="${3:-}"
  shift 3 || true
  local args=(--name "$name" --provider "$provider" --git-root "$GIT_ROOT" --no-upload)
  if [[ -n "$verify_command" ]]; then
    args+=(--verify-command "$verify_command")
  fi
  "$SET_SECRET" "${args[@]}"
}

create_workspace_skeleton() {
  local root="$1"
  mkdir -p "$root"/{assistants,projects,services,sites,contexts,outputs,archives,docs}
  write_if_missing "$root/README.md" \
    "# Repository Index" \
    "" \
    "Root workspace for AI-assisted work. Start here, then read DEV.md, then the target folder or repo README." \
    "" \
    "## Folders" \
    "" \
    "| Folder | Purpose |" \
    "| --- | --- |" \
    "| assistants/ | Telegram bots and assistant services. |" \
    "| projects/ | Client or internal project context repos. |" \
    "| services/ | APIs, workers, scheduled jobs, and reusable services. |" \
    "| sites/ | Websites and frontend apps. |" \
    "| contexts/ | Shared context packs and local knowledge indexes. |" \
    "| outputs/ | Generated artifacts and delivery files. |" \
    "| archives/ | Inactive local material kept for reference. |" \
    "| docs/ | Workspace-level docs that are not owned by one repo. |"
  write_if_missing "$root/DEV.md" \
    "# Development And Server Rules" \
    "" \
    "Keep secrets in ignored .env files. Use README files as indexes. Use OpenSpec for code, behavior, deploy, integration, prompt, and workflow changes."
  write_if_missing "$root/AGENTS.md" \
    "# Agent guide" \
    "@README.md" \
    "" \
    "Dev rules: [DEV.md](DEV.md)."
  write_if_missing "$root/CLAUDE.md" "@README.md"
  write_if_missing "$root/llm-wiki.md" \
    "# LLM Wiki" \
    "" \
    "Read root README, then DEV, then the target repo README. One fact lives in one place. Keep folders minimal and add README files to folders that own logic or data."
  write_if_missing "$root/.gitignore" \
    ".env" \
    ".env-*" \
    "!.env.example" \
    "node_modules/" \
    ".venv/" \
    "venv/" \
    "__pycache__/" \
    "*.log" \
    "logs/" \
    "tmp/" \
    ".cache/" \
    ".DS_Store"

  local folder
  for folder in assistants projects services sites contexts outputs archives docs; do
    write_if_missing "$root/$folder/README.md" \
      "# $folder" \
      "" \
      "Index for $folder. Keep this README current and link to child repos or important files instead of duplicating details."
  done
}

print_key_file() {
  local path="$1"
  if [[ -f "$path.pub" ]]; then
    cat "$path.pub"
  else
    ssh-keygen -t ed25519 -N "" -C "$USER@$(hostname)" -f "$path"
    cat "$path.pub"
  fi
}

SET_SECRET="$(find_set_secret)"

echo "Codex-Claude first-run onboarding"
echo "This script configures the local/server GIT root, shared secrets, Git providers, mail notes, and Telegram control."

ask GIT_ROOT "Root GIT folder" "${GIT_ROOT:-$HOME/GIT}"
mkdir -p "$GIT_ROOT"

ask_yes_no REORGANIZE "Create/reorganize the root folder skeleton and README files according to llm-wiki?" "yes"
if [[ "$REORGANIZE" == "yes" ]]; then
  create_workspace_skeleton "$GIT_ROOT"
fi

LOCAL_ENV="$GIT_ROOT/.env-local"

ask AI_SERVER_HOST "Main AI server hostname" "ai4u.kt.team"
append_or_replace_env "$LOCAL_ENV" "AI_SERVER_HOST" "$AI_SERVER_HOST"

ask KT_LOGIN "Default login you usually want to use, for example your kt.team login/email" ""
if [[ -n "$KT_LOGIN" ]]; then
  append_or_replace_env "$LOCAL_ENV" "KT_LOGIN" "$KT_LOGIN"
fi

info "OpenAI API key"
echo "Get or create it here: https://platform.openai.com/api-keys"
ask_yes_no WANT_OPENAI "Enter OPENAI_API_KEY now?" "yes"
if [[ "$WANT_OPENAI" == "yes" ]]; then
  set_secret "OPENAI_API_KEY" "openai" 'curl -fsS -H "Authorization: Bearer $OPENAI_API_KEY" https://api.openai.com/v1/models >/dev/null'
fi

info "Telegram control bot"
echo "Create a bot through BotFather: https://t.me/BotFather"
echo "Use /newbot, choose a display name, then a username ending with _bot."
ask_yes_no WANT_TELEGRAM "Enter TELEGRAM_BOT_TOKEN now?" "yes"
if [[ "$WANT_TELEGRAM" == "yes" ]]; then
  set_secret "TELEGRAM_BOT_TOKEN" "telegram" 'curl -fsS "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getMe" >/dev/null'
  echo "After the service is running, send /getid to the bot and save that id."
  ask TELEGRAM_OWNER_CHAT_ID "Telegram owner chat id (empty to skip for now)" ""
  if [[ -n "$TELEGRAM_OWNER_CHAT_ID" ]]; then
    append_or_replace_env "$GIT_ROOT/.env-telegram" "TELEGRAM_OWNER_CHAT_ID" "$TELEGRAM_OWNER_CHAT_ID"
  fi
fi

info "Claude Code / Anthropic"
echo "Create an Anthropic API key here: https://console.anthropic.com/settings/keys"
ask_yes_no WANT_ANTHROPIC "Enter ANTHROPIC_API_KEY now?" "yes"
if [[ "$WANT_ANTHROPIC" == "yes" ]]; then
  set_secret "ANTHROPIC_API_KEY" "anthropic" 'curl -fsS -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" https://api.anthropic.com/v1/models >/dev/null'
fi

info "Gemini"
echo "Create a Gemini API key here: https://aistudio.google.com/app/apikey"
ask_yes_no WANT_GEMINI "Enter GEMINI_API_KEY now? Optional" "no"
if [[ "$WANT_GEMINI" == "yes" ]]; then
  set_secret "GEMINI_API_KEY" "gemini" 'curl -fsS "https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY" >/dev/null'
fi

info "Mail accounts"
ask GMAIL_ACCOUNT "Gmail / Google Workspace account (empty to skip)" ""
[[ -n "$GMAIL_ACCOUNT" ]] && append_or_replace_env "$LOCAL_ENV" "GMAIL_ACCOUNT" "$GMAIL_ACCOUNT"
ask YANDEX_ACCOUNT "Yandex mail account (empty to skip)" ""
[[ -n "$YANDEX_ACCOUNT" ]] && append_or_replace_env "$LOCAL_ENV" "YANDEX_ACCOUNT" "$YANDEX_ACCOUNT"
echo "Gmail OAuth is configured through Google Cloud / Workspace consent when a concrete mail service needs it."
echo "Yandex app passwords are managed here: https://passport.yandex.ru/profile/access"

info "GitHub SSH for personal Git"
echo "Personal GitHub SSH keys are for personal work, not corporate GitLab."
GITHUB_KEY="$HOME/.ssh/github_account_ed25519"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
echo "Add this public key at: https://github.com/settings/keys"
print_key_file "$GITHUB_KEY"
ask GITHUB_USERNAME "GitHub username/namespace (empty to skip)" ""
[[ -n "$GITHUB_USERNAME" ]] && append_or_replace_env "$LOCAL_ENV" "GITHUB_USERNAME" "$GITHUB_USERNAME"

info "Corporate GitLab"
ask GITLAB_URL "Corporate GitLab URL" "https://gitlab.kt-team.de/"
append_or_replace_env "$LOCAL_ENV" "GITLAB_URL" "$GITLAB_URL"
ask GITLAB_GROUP "Your GitLab group/namespace, if any (empty to skip)" ""
[[ -n "$GITLAB_GROUP" ]] && append_or_replace_env "$LOCAL_ENV" "GITLAB_GROUP" "$GITLAB_GROUP"
echo "Add SSH keys at: ${GITLAB_URL%/}/-/user_settings/ssh_keys"
echo "Create access tokens at: ${GITLAB_URL%/}/-/user_settings/personal_access_tokens"
ask_yes_no WANT_GITLAB_TOKEN "Enter GITLAB_TOKEN now?" "yes"
if [[ "$WANT_GITLAB_TOKEN" == "yes" ]]; then
  set_secret "GITLAB_TOKEN" "gitlab" "curl -fsS --header \"PRIVATE-TOKEN: \$GITLAB_TOKEN\" \"${GITLAB_URL%/}/api/v4/user\" >/dev/null"
fi

info "Done"
echo "Local setup notes saved to $LOCAL_ENV"
echo "If Telegram token or owner id changed on the server, restart: sudo systemctl restart codex-telegram-bridge"

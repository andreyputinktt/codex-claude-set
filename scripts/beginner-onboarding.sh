#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/beginner-onboarding.sh

Question-led beginner setup for a Codex/Claude AI workspace:
- installs/checks local prerequisites on macOS/Linux;
- creates a strict llm-wiki starter folder;
- prepares SSH access for KT or personal servers;
- mirrors the starter folder shape to the server;
- guides GitHub/GitLab SSH and provider API keys.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

info() {
  echo
  echo "==> $*"
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

sanitize_linux_user() {
  local raw="$1"
  local base="${raw%@*}"
  base="$(printf "%s" "$base" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//')"
  [[ -n "$base" ]] || base="codexuser"
  if [[ ! "$base" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    base="u-$base"
  fi
  printf "%s" "${base:0:30}"
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
  printf "%s=%q\n" "$key" "$value" >> "$tmp"
  mv "$tmp" "$file"
  chmod 600 "$file"
}

ensure_key() {
  local key_path="$1"
  local comment="$2"
  mkdir -p "$(dirname "$key_path")"
  chmod 700 "$(dirname "$key_path")"
  if [[ ! -f "$key_path" ]]; then
    ssh-keygen -t ed25519 -N "" -C "$comment" -f "$key_path"
  fi
  cat "$key_path.pub"
}

set_secret_if_wanted() {
  local want_name="$1"
  local env_name="$2"
  local provider="$3"
  local verify_command="$4"
  local args=(--name "$env_name" --provider "$provider" --git-root "$LOCAL_ROOT")

  ask_yes_no "$want_name" "Enter $env_name now?" "no"
  if [[ "${!want_name}" != "yes" ]]; then
    return
  fi

  if [[ -n "$SERVER_TARGET" && "$SERVER_READY" == "yes" ]]; then
    args+=(--server "$SERVER_TARGET")
  fi
  args+=(--verify-command "$verify_command")
  "$SCRIPT_DIR/set-secret.sh" "${args[@]}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config/kt.sh
source "$SCRIPT_DIR/../config/kt.sh"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

cat <<'EOF'
Beginner Codex/Claude onboarding

You can answer "no" or leave optional items empty. Keep browser/account pages
open when the script prints a link. Secrets are entered through hidden prompts.
EOF

ask_yes_no WANT_PREREQS "Install/check local packages first?" "yes"
if [[ "$WANT_PREREQS" == "yes" ]]; then
  ask_yes_no WANT_AGENT_TOOLS "Install/update Codex, Claude Code, OpenClaw, OpenCode npm tools too?" "no"
  if [[ "$WANT_AGENT_TOOLS" == "yes" ]]; then
    "$SCRIPT_DIR/install-local-prereqs.sh" --agent-tools
  else
    "$SCRIPT_DIR/install-local-prereqs.sh"
  fi
fi

ask LOGIN_HINT "Your OpenAI/Claude or work email, used for default Linux login" ""
DEFAULT_USER="$(sanitize_linux_user "$LOGIN_HINT")"
ask_yes_no IS_KT_EMPLOYEE "Ты сотрудник КТ?" "yes"
ask LOCAL_ROOT "Starter folder on this computer" "${GIT_ROOT:-$HOME/GIT}"
LOCAL_ROOT="$(mkdir -p "$LOCAL_ROOT" && cd "$LOCAL_ROOT" && pwd)"
LOCAL_ENV="$LOCAL_ROOT/.env-local"

info "Creating strict llm-wiki starter folder"
"$SCRIPT_DIR/refresh-llm-wiki-index.sh" --root "$LOCAL_ROOT"
append_or_replace_env "$LOCAL_ENV" "LOCAL_GIT_ROOT" "$LOCAL_ROOT"
[[ -n "$LOGIN_HINT" ]] && append_or_replace_env "$LOCAL_ENV" "LOGIN_HINT" "$LOGIN_HINT"
append_or_replace_env "$LOCAL_ENV" "IS_KT_EMPLOYEE" "$IS_KT_EMPLOYEE"
if [[ "$IS_KT_EMPLOYEE" == "yes" ]]; then
  info "KT project context"
  kt_print_sync_agent_request
  append_or_replace_env "$LOCAL_ENV" "KT_SYNC_SERVICE_URL" "$KT_SYNC_SERVICE_URL"
fi

info "Git accounts"
ask_yes_no WANT_GITHUB "Do you want personal GitHub configured?" "yes"
if [[ "$WANT_GITHUB" == "yes" ]]; then
  GITHUB_KEY="$HOME/.ssh/github_account_ed25519"
  echo "Add this key at: https://github.com/settings/keys"
  ensure_key "$GITHUB_KEY" "github-account@$(hostname)"
  ask GITHUB_NAMESPACE "GitHub username/namespace" ""
  [[ -n "$GITHUB_NAMESPACE" ]] && append_or_replace_env "$LOCAL_ENV" "GITHUB_NAMESPACE" "$GITHUB_NAMESPACE"
fi

ask_yes_no WANT_WORK_GIT "Do you also want work GitLab/GitHub configured?" "no"
if [[ "$WANT_WORK_GIT" == "yes" ]]; then
  ask WORK_GIT_URL "Work Git URL" "$KT_GITLAB_URL"
  append_or_replace_env "$LOCAL_ENV" "WORK_GIT_URL" "$WORK_GIT_URL"
  echo "Add SSH keys in your work Git profile settings."
  if [[ "$WORK_GIT_URL" == *"gitlab"* ]]; then
    echo "Common GitLab URL: ${WORK_GIT_URL%/}/-/user_settings/ssh_keys"
  fi
fi

info "Server choice"
cat <<EOF
Choose server:
  kt       - KT employee server, default ${KT_AI_SERVER_HOST}.
  personal - your own Timeweb/other Ubuntu server.
  none     - local workspace only for now.
EOF
DEFAULT_SERVER_KIND="personal"
[[ "$IS_KT_EMPLOYEE" == "yes" ]] && DEFAULT_SERVER_KIND="kt"
ask SERVER_KIND "Server type: kt, personal, or none" "$DEFAULT_SERVER_KIND"
SERVER_HOST=""
SERVER_USER=""
SERVER_TARGET=""
SERVER_READY="no"

case "$SERVER_KIND" in
  kt)
    ask SERVER_HOST "KT AI server hostname" "$KT_AI_SERVER_HOST"
    ask SERVER_USER "Linux username on the server" "$DEFAULT_USER"
    SERVER_TARGET="$SERVER_USER@$SERVER_HOST"
    "$SCRIPT_DIR/prepare-server-access.sh" --host "$SERVER_HOST" --user "$SERVER_USER" --kind kt
    ;;
  personal)
    ask SERVER_HOST "Personal server IP or hostname" ""
    ask SERVER_USER "Linux username on the server" "$DEFAULT_USER"
    SERVER_TARGET="$SERVER_USER@$SERVER_HOST"
    "$SCRIPT_DIR/prepare-server-access.sh" --host "$SERVER_HOST" --user "$SERVER_USER" --kind personal
    ask_yes_no SERVER_READY "Does key-based SSH work now?" "yes"
    ;;
  none|"")
    SERVER_KIND="none"
    ;;
  *)
    die "server type must be kt, personal, or none"
    ;;
esac

if [[ "$SERVER_KIND" != "none" ]]; then
  append_or_replace_env "$LOCAL_ENV" "AI_SERVER_HOST" "$SERVER_HOST"
  append_or_replace_env "$LOCAL_ENV" "AI_SERVER_USER" "$SERVER_USER"
  append_or_replace_env "$LOCAL_ENV" "AI_SERVER_TARGET" "$SERVER_TARGET"
fi

if [[ "$SERVER_KIND" != "none" ]]; then
  ask_yes_no WANT_MIRROR "Mirror starter folder shape to $SERVER_TARGET now?" "yes"
  if [[ "$WANT_MIRROR" == "yes" ]]; then
    if "$SCRIPT_DIR/mirror-workspace.sh" --local-root "$LOCAL_ROOT" --server "$SERVER_TARGET" --remote-root "~/GIT"; then
      SERVER_READY="yes"
    else
      echo "Mirror skipped or failed. You can rerun it after SSH access works:"
      echo "scripts/mirror-workspace.sh --local-root \"$LOCAL_ROOT\" --server \"$SERVER_TARGET\""
    fi
  fi
fi

info "Agent backend preference"
cat <<'EOF'
Choose initial backend preference:
  codex      - Codex/Claude only for now.
  hermes     - also use Hermes where available.
  openclaw   - also use OpenClaw where available.
  both       - Hermes and OpenClaw.
EOF
ask BACKENDS "Backend preference" "codex"
append_or_replace_env "$LOCAL_ENV" "AI_AGENT_BACKENDS" "$BACKENDS"

info "Provider API keys"
echo "OpenAI API keys: https://platform.openai.com/api-keys"
set_secret_if_wanted WANT_OPENAI "OPENAI_API_KEY" "openai" \
  'curl -fsS -H "Authorization: Bearer $OPENAI_API_KEY" https://api.openai.com/v1/models >/dev/null'

echo "Anthropic API keys: https://console.anthropic.com/settings/keys"
set_secret_if_wanted WANT_ANTHROPIC "ANTHROPIC_API_KEY" "anthropic" \
  'curl -fsS -H "x-api-key: $ANTHROPIC_API_KEY" -H "anthropic-version: 2023-06-01" https://api.anthropic.com/v1/models >/dev/null'

echo "Gemini API keys: https://aistudio.google.com/app/apikey"
set_secret_if_wanted WANT_GEMINI "GEMINI_API_KEY" "gemini" \
  'curl -fsS "https://generativelanguage.googleapis.com/v1beta/models?key=$GEMINI_API_KEY" >/dev/null'

info "Done"
cat <<EOF
Local starter folder: $LOCAL_ROOT
Local notes: $LOCAL_ENV
Server target: ${SERVER_TARGET:-not selected}

Next steps:
1. If server access was pending, send the printed public key/request and wait for access.
2. Run server bootstrap through Codex/Claude with PROMPT.md, or manually:
   rsync -az --exclude .git ./codex-claude-set/ ${SERVER_TARGET:-USER@HOST}:/tmp/codex-claude-set/
   ssh ${SERVER_TARGET:-USER@HOST} 'sudo bash /tmp/codex-claude-set/bootstrap.sh'
3. After bootstrap, run on the server:
   ai-first-run
   ai-index-refresh --root ~/GIT
EOF

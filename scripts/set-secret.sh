#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/set-secret.sh --name ENV_NAME [--name OTHER_ENV] [--provider openai] [--verify-command "cmd"] [--server user@host]
  scripts/set-secret.sh --name ENV_NAME --name OTHER_ENV --project path/in/GIT [--verify-command "cmd"] [--server user@host]

Examples:
  scripts/set-secret.sh --name OPENAI_API_KEY --provider openai --server a.putin@178.105.78.17
  scripts/set-secret.sh --name OPENAI_API_KEY --name GITLAB_TOKEN --server a.putin@178.105.78.17
  scripts/set-secret.sh --name TELEGRAM_BOT_TOKEN --project assistants/meeting --server ai-server
  scripts/set-secret.sh --name GITLAB_TOKEN --verify-command 'curl -fsS --header "PRIVATE-TOKEN: $GITLAB_TOKEN" https://gitlab.com/api/v4/user >/dev/null'

Rules:
  - Never pass the secret value as an argument.
  - Repeat --name to request several secrets in one run.
  - If --verify-command is set, it runs with saved env values before upload.
  - Without --project, writes to GIT/.env-<provider>.
  - With --project, writes to GIT/<project>/.env.
  - If --server is set, uploads the same env file to the server GIT root.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

shell_quote() {
  printf "%q" "$1"
}

infer_provider() {
  local name="$1"
  case "$name" in
    OPENAI_* ) echo "openai" ;;
    ANTHROPIC_* ) echo "anthropic" ;;
    GEMINI_* ) echo "gemini" ;;
    GOOGLE_*|GMAIL_* ) echo "google" ;;
    GITHUB_*|GH_* ) echo "github" ;;
    GITLAB_*|GLAB_* ) echo "gitlab" ;;
    TELEGRAM_* ) echo "telegram" ;;
    * ) return 1 ;;
  esac
}

find_default_git_root() {
  local script_dir repo_dir cwd
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  repo_dir="$(cd "$script_dir/.." && pwd)"
  cwd="$(pwd)"

  if [[ "$(basename "$repo_dir")" == "codex-claude-set" && -f "$repo_dir/../DEV.md" ]]; then
    cd "$repo_dir/.." && pwd
    return
  fi
  if [[ -f "$cwd/DEV.md" && -f "$cwd/README.md" ]]; then
    pwd
    return
  fi
  cd "$repo_dir" && pwd
}

dotenv_value() {
  local value="$1"
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    die "secret value must be one line"
  fi
  if [[ "$value" =~ ^[A-Za-z0-9_./:@+=,-]+$ ]]; then
    printf "%s" "$value"
  else
    printf "'%s'" "$(printf "%s" "$value" | sed "s/'/'\\\\''/g")"
  fi
}

update_env_file() {
  local target="$1"
  local name="$2"
  local encoded_value="$3"
  local tmp

  mkdir -p "$(dirname "$target")"
  tmp="$(mktemp)"
  chmod 600 "$tmp"

  if [[ -f "$target" ]]; then
    awk -v key="$name" '
      BEGIN { pattern = "^[[:space:]]*(export[[:space:]]+)?" key "[[:space:]]*=" }
      $0 !~ pattern { print }
    ' "$target" > "$tmp"
  fi

  printf "%s=%s\n" "$name" "$encoded_value" >> "$tmp"
  mv "$tmp" "$target"
  chmod 600 "$target"
}

upload_env_file() {
  local server="$1"
  local local_file="$2"
  local remote_git_root="$3"
  local remote_rel="$4"
  local tmp_name=".codex-claude-set-env.$$"
  local quoted_git_root quoted_rel quoted_tmp

  quoted_git_root="$(shell_quote "$remote_git_root")"
  quoted_rel="$(shell_quote "$remote_rel")"
  quoted_tmp="$(shell_quote "$tmp_name")"

  info "Uploading $(basename "$local_file") to $server:$remote_git_root/$remote_rel"
  scp -q "$local_file" "$server:$tmp_name"
  ssh "$server" "set -euo pipefail
git_root=$quoted_git_root
remote_rel=$quoted_rel
tmp_name=$quoted_tmp
case \"\$git_root\" in
  /*) base=\"\$git_root\" ;;
  *) base=\"\$HOME/\$git_root\" ;;
esac
target=\"\$base/\$remote_rel\"
mkdir -p \"\$(dirname \"\$target\")\"
mv \"\$HOME/\$tmp_name\" \"\$target\"
chmod 600 \"\$target\"
echo \"saved \$target\""
}

target_for_name() {
  local name="$1"
  local provider

  if [[ -n "$PROJECT" ]]; then
    printf "%s\t%s\n" "$GIT_ROOT/$PROJECT/.env" "$PROJECT/.env"
    return
  fi

  if [[ -n "$PROVIDER" ]]; then
    provider="$PROVIDER"
  else
    provider="$(infer_provider "$name")" || die "cannot infer provider for $name; pass --provider"
  fi
  [[ "$provider" =~ ^[a-z0-9_-]+$ ]] || die "--provider must be lowercase safe text"
  printf "%s\t%s\n" "$GIT_ROOT/.env-$provider" ".env-$provider"
}

remember_changed_file() {
  local file="$1"
  local rel="$2"
  local idx

  for ((idx = 0; idx < CHANGED_COUNT; idx++)); do
    [[ "${CHANGED_FILES[$idx]}" == "$file" ]] && return
  done
  CHANGED_FILES+=("$file")
  CHANGED_RELS+=("$rel")
  CHANGED_COUNT=$((CHANGED_COUNT + 1))
}

run_verify_command() {
  local idx

  [[ -n "$VERIFY_COMMAND" ]] || return
  info "Running verification command"
  (
    set -a
    for ((idx = 0; idx < CHANGED_COUNT; idx++)); do
      # shellcheck disable=SC1090
      source "${CHANGED_FILES[$idx]}"
    done
    set +a
    bash -lc "$VERIFY_COMMAND"
  )
  info "Verification passed"
}

NAMES=()
PROVIDER=""
PROJECT=""
SERVER=""
GIT_ROOT="${GIT_ROOT:-}"
REMOTE_GIT_ROOT="GIT"
VERIFY_COMMAND=""
NO_UPLOAD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      [[ -n "${2:-}" ]] || die "--name requires a value"
      NAMES+=("$2")
      shift 2
      ;;
    --provider)
      PROVIDER="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT="${2:-}"
      shift 2
      ;;
    --server)
      SERVER="${2:-}"
      shift 2
      ;;
    --git-root)
      GIT_ROOT="${2:-}"
      shift 2
      ;;
    --remote-git-root)
      REMOTE_GIT_ROOT="${2:-}"
      shift 2
      ;;
    --verify-command|--check-command)
      VERIFY_COMMAND="${2:-}"
      shift 2
      ;;
    --no-upload)
      NO_UPLOAD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ "${#NAMES[@]}" -gt 0 ]] || die "--name is required"
if [[ -n "$VERIFY_COMMAND" && "${#NAMES[@]}" -eq 0 ]]; then
  die "--verify-command requires at least one --name"
fi
for NAME in "${NAMES[@]}"; do
  [[ "$NAME" =~ ^[A-Z_][A-Z0-9_]*$ ]] || die "--name must look like ENV_VAR_NAME"
done
[[ "$PROJECT" != /* ]] || die "--project must be relative to GIT root"
[[ "$PROJECT" != *".."* ]] || die "--project must not contain .."

if [[ -z "$GIT_ROOT" ]]; then
  GIT_ROOT="$(find_default_git_root)"
fi

CHANGED_FILES=()
CHANGED_RELS=()
CHANGED_COUNT=0

for NAME in "${NAMES[@]}"; do
  TARGET_ROW="$(target_for_name "$NAME")"
  TARGET_FILE="${TARGET_ROW%%$'\t'*}"
  REMOTE_REL="${TARGET_ROW#*$'\t'}"

  if [[ -f "$TARGET_FILE" ]]; then
    info "Updating $TARGET_FILE"
  else
    info "Creating $TARGET_FILE"
  fi

  printf "Enter value for %s (input hidden): " "$NAME" >&2
  IFS= read -r -s SECRET_VALUE || true
  echo >&2
  [[ -n "$SECRET_VALUE" ]] || die "empty value for $NAME; nothing written"

  ENCODED_VALUE="$(dotenv_value "$SECRET_VALUE")"
  unset SECRET_VALUE

  update_env_file "$TARGET_FILE" "$NAME" "$ENCODED_VALUE"
  unset ENCODED_VALUE
  remember_changed_file "$TARGET_FILE" "$REMOTE_REL"
done

info "Saved locally with chmod 600"
run_verify_command

if [[ "$NO_UPLOAD" -eq 0 && -n "$SERVER" ]]; then
  for ((i = 0; i < CHANGED_COUNT; i++)); do
    upload_env_file "$SERVER" "${CHANGED_FILES[$i]}" "$REMOTE_GIT_ROOT" "${CHANGED_RELS[$i]}"
  done
elif [[ "$NO_UPLOAD" -eq 0 ]]; then
  info "No --server given; local file was not uploaded"
fi

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/mirror-workspace.sh --server USER@HOST [--local-root DIR] [--remote-root DIR]

Mirrors the starter llm-wiki workspace shape from this computer to the server.
It copies root docs and folder README files, not secrets or full repo contents.

Options:
  --server USER@HOST      SSH target.
  --local-root DIR        Local workspace root. Default: $GIT_ROOT or $HOME/GIT.
  --remote-root DIR       Remote workspace root. Default: ~/GIT.
  --no-remote-refresh     Do not run ai-index-refresh remotely.
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

find_script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

SERVER=""
LOCAL_ROOT="${GIT_ROOT:-$HOME/GIT}"
REMOTE_ROOT="~/GIT"
REMOTE_REFRESH=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server)
      SERVER="${2:-}"
      shift 2
      ;;
    --local-root)
      LOCAL_ROOT="${2:-}"
      shift 2
      ;;
    --remote-root)
      REMOTE_ROOT="${2:-}"
      shift 2
      ;;
    --no-remote-refresh)
      REMOTE_REFRESH=0
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

[[ -n "$SERVER" ]] || die "--server is required"
SCRIPT_DIR="$(find_script_dir)"
LOCAL_ROOT="$(mkdir -p "$LOCAL_ROOT" && cd "$LOCAL_ROOT" && pwd)"

info "Refreshing local llm-wiki index"
"$SCRIPT_DIR/refresh-llm-wiki-index.sh" --root "$LOCAL_ROOT"

info "Creating remote root: $SERVER:$REMOTE_ROOT"
ssh "$SERVER" "mkdir -p $(shell_quote "$REMOTE_ROOT")"

info "Mirroring starter docs and folder shape"
rsync -az \
  --include='*/' \
  --include='README.md' \
  --include='DEV.md' \
  --include='AGENTS.md' \
  --include='CLAUDE.md' \
  --include='llm-wiki.md' \
  --include='.gitignore' \
  --exclude='.git/' \
  --exclude='.env' \
  --exclude='.env-*' \
  --exclude='*.pem' \
  --exclude='*.key' \
  --exclude='node_modules/' \
  --exclude='.venv/' \
  --exclude='venv/' \
  --exclude='__pycache__/' \
  --exclude='logs/' \
  --exclude='tmp/' \
  --exclude='.cache/' \
  --exclude='*' \
  "$LOCAL_ROOT/" "$SERVER:$REMOTE_ROOT/"

if [[ "$REMOTE_REFRESH" -eq 1 ]]; then
  info "Running remote llm-wiki refresh when available"
  if ssh "$SERVER" "command -v ai-index-refresh >/dev/null 2>&1"; then
    ssh "$SERVER" "ai-index-refresh --root $(shell_quote "$REMOTE_ROOT")"
  else
    tmp_remote="/tmp/ai-index-refresh.$$"
    tmp_ignore_remote="/tmp/ai-ignore-nested-git-repos.$$"
    scp -q "$SCRIPT_DIR/refresh-llm-wiki-index.sh" "$SERVER:$tmp_remote"
    scp -q "$SCRIPT_DIR/ignore-nested-git-repos.sh" "$SERVER:$tmp_ignore_remote"
    ssh "$SERVER" "AI_IGNORE_NESTED_GIT_SCRIPT=$(shell_quote "$tmp_ignore_remote") bash $(shell_quote "$tmp_remote") --root $(shell_quote "$REMOTE_ROOT"); rm -f $(shell_quote "$tmp_remote") $(shell_quote "$tmp_ignore_remote")"
  fi
fi

info "Workspace mirror complete"

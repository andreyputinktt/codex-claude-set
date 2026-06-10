#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/update-boilerplate-instructions.sh [--root DIR] [--repo-url URL]
                                             [--user USER] [--repo-dir DIR]

Refreshes an installed codex-claude-set boilerplate:
- clones or pulls the upstream boilerplate repo;
- reinstalls bundled helper scripts when running as root;
- refreshes the workspace llm-wiki index and nested Git ignores;
- writes UPSTREAM-INSTRUCTIONS.md with the current upstream revision and rules.

This intentionally does not overwrite the user's local README.md or DEV.md.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

log() {
  echo "==> $*"
}

shell_quote() {
  printf "%q" "$1"
}

run_as_target_user() {
  local command="$1"
  if [[ -n "$TARGET_USER" && "$(id -u)" -eq 0 ]]; then
    sudo -H -u "$TARGET_USER" bash -lc "$command"
  else
    bash -lc "$command"
  fi
}

install_helper() {
  local source="$1"
  shift
  [[ "$(id -u)" -eq 0 ]] || return 0
  [[ -f "$source" ]] || return 0
  local target
  for target in "$@"; do
    install -m 0755 "$source" "$target"
  done
}

write_upstream_instructions() {
  local revision pulled_at instructions_file
  revision="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || printf unknown)"
  pulled_at="$(date +"%Y-%m-%dT%H:%M:%S%z")"
  instructions_file="$ROOT/UPSTREAM-INSTRUCTIONS.md"

  cat > "$instructions_file" <<EOF
# Upstream Boilerplate Instructions

Managed by \`ai-boilerplate-refresh\`.

- Last refresh: $pulled_at
- Upstream repo: $REPO_URL
- Local boilerplate repo: $REPO_DIR
- Revision: $revision

## How To Use

Agents should read the current upstream files before setup, infrastructure, or
agent-policy changes:

1. \`$REPO_DIR/README.md\`
2. \`$REPO_DIR/DEV.md\`
3. \`$REPO_DIR/INSTALL.md\`
4. \`$REPO_DIR/PROMPT.md\`
5. relevant files under \`$REPO_DIR/recipes/\`

The weekly updater pulls this repo, reinstalls helper scripts, refreshes the
workspace index, and updates nested Git ignores. It does not overwrite local
workspace \`README.md\` or \`DEV.md\`; durable local facts still belong in the
local workspace docs.

## Manual Commands

\`\`\`bash
ai-boilerplate-refresh --root "$ROOT"
ai-index-refresh --root "$ROOT"
ai-ignore-nested-git-repos --root "$ROOT" --extra sloy-KT
systemctl status ai-boilerplate-refresh.timer --no-pager
\`\`\`
EOF
  if [[ -n "$TARGET_USER" && "$(id -u)" -eq 0 ]]; then
    chown "$TARGET_USER:$TARGET_USER" "$instructions_file" 2>/dev/null || true
  fi
}

ROOT="${GIT_ROOT:-$HOME/GIT}"
REPO_URL="${CODEX_CLAUDE_SET_REPO_URL:-https://github.com/andreyputinktt/codex-claude-set.git}"
TARGET_USER="${SETUP_USER:-}"
REPO_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT="${2:-}"
      shift 2
      ;;
    --repo-url)
      REPO_URL="${2:-}"
      shift 2
      ;;
    --user)
      TARGET_USER="${2:-}"
      shift 2
      ;;
    --repo-dir)
      REPO_DIR="${2:-}"
      shift 2
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

[[ -n "$ROOT" ]] || die "--root cannot be empty"
ROOT="$(mkdir -p "$ROOT" && cd "$ROOT" && pwd)"
REPO_DIR="${REPO_DIR:-$ROOT/codex-claude-set}"

if [[ -z "$TARGET_USER" && "$(id -u)" -eq 0 ]]; then
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
    TARGET_USER="$SUDO_USER"
  elif [[ -n "${USER:-}" && "$USER" != "root" ]]; then
    TARGET_USER="$USER"
  fi
fi

log "Refreshing boilerplate repo: $REPO_DIR"
if [[ -d "$REPO_DIR/.git" ]]; then
  run_as_target_user "git -C $(shell_quote "$REPO_DIR") pull --ff-only --autostash"
elif [[ -e "$REPO_DIR" && -n "$(find "$REPO_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  log "Existing non-git boilerplate dir found; leaving it in place: $REPO_DIR"
else
  mkdir -p "$(dirname "$REPO_DIR")"
  if ! run_as_target_user "git clone $(shell_quote "$REPO_URL") $(shell_quote "$REPO_DIR")"; then
    log "Could not clone $REPO_URL; keeping current installed scripts"
  fi
fi

if [[ -d "$REPO_DIR/scripts" ]]; then
  log "Reinstalling bundled helper scripts when allowed"
  install_helper "$REPO_DIR/scripts/set-secret.sh" \
    /usr/local/bin/ai-set-secret /usr/local/bin/set-secret.sh
  install_helper "$REPO_DIR/scripts/first-run.sh" \
    /usr/local/bin/ai-first-run /usr/local/bin/first-run.sh
  install_helper "$REPO_DIR/scripts/install-local-prereqs.sh" \
    /usr/local/bin/ai-install-local-prereqs /usr/local/bin/install-local-prereqs.sh
  install_helper "$REPO_DIR/scripts/prepare-server-access.sh" \
    /usr/local/bin/ai-prepare-server-access /usr/local/bin/prepare-server-access.sh
  install_helper "$REPO_DIR/scripts/refresh-llm-wiki-index.sh" \
    /usr/local/bin/ai-index-refresh /usr/local/bin/refresh-llm-wiki-index.sh
  install_helper "$REPO_DIR/scripts/ignore-nested-git-repos.sh" \
    /usr/local/bin/ai-ignore-nested-git-repos /usr/local/bin/ignore-nested-git-repos.sh
  install_helper "$REPO_DIR/scripts/mirror-workspace.sh" \
    /usr/local/bin/ai-mirror-workspace /usr/local/bin/mirror-workspace.sh
  install_helper "$REPO_DIR/scripts/beginner-onboarding.sh" \
    /usr/local/bin/ai-beginner-onboarding /usr/local/bin/beginner-onboarding.sh
  install_helper "$REPO_DIR/scripts/update-boilerplate-instructions.sh" \
    /usr/local/bin/ai-boilerplate-refresh /usr/local/bin/update-boilerplate-instructions.sh
fi

log "Refreshing workspace index and nested Git ignores"
if command -v ai-index-refresh >/dev/null 2>&1; then
  run_as_target_user "ai-index-refresh --root $(shell_quote "$ROOT")"
elif [[ -x "$REPO_DIR/scripts/refresh-llm-wiki-index.sh" ]]; then
  run_as_target_user "$(shell_quote "$REPO_DIR/scripts/refresh-llm-wiki-index.sh") --root $(shell_quote "$ROOT")"
fi

if command -v ai-ignore-nested-git-repos >/dev/null 2>&1; then
  run_as_target_user "ai-ignore-nested-git-repos --root $(shell_quote "$ROOT") --extra sloy-KT"
elif [[ -x "$REPO_DIR/scripts/ignore-nested-git-repos.sh" ]]; then
  run_as_target_user "$(shell_quote "$REPO_DIR/scripts/ignore-nested-git-repos.sh") --root $(shell_quote "$ROOT") --extra sloy-KT"
fi

write_upstream_instructions
log "Boilerplate refresh complete"

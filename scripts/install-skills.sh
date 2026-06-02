#!/usr/bin/env bash
set -euo pipefail

GIT_ROOT="${GIT_ROOT:-$HOME/GIT}"
TARGET_HOME="${HOME}"
OWNER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --git-root)
      GIT_ROOT="$2"
      shift 2
      ;;
    --home)
      TARGET_HOME="$2"
      shift 2
      ;;
    --owner)
      OWNER="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS_DIR="$REPO_DIR/skills"

if [[ ! -d "$SKILLS_DIR" ]]; then
  echo "No bundled skills found: $SKILLS_DIR" >&2
  exit 1
fi

install -d "$GIT_ROOT/.agents/skills" "$TARGET_HOME/.agents/skills"
rsync -a --delete "$SKILLS_DIR/telegram-send/" "$GIT_ROOT/.agents/skills/telegram-send/"
rsync -a --delete "$SKILLS_DIR/telegram-send/" "$TARGET_HOME/.agents/skills/telegram-send/"

for dir in "$GIT_ROOT/.codex/skills/telegram-send" "$GIT_ROOT/.claude/skills/telegram-send" "$GIT_ROOT/.github/skills/telegram-send" "$GIT_ROOT/.hermes/skills/telegram-send"; do
  install -d "$dir"
  cat > "$dir/SKILL.md" <<EOF
---
name: telegram-send
description: Send Telegram messages through the canonical .agents telegram-send skill.
compatibility: Read .agents/skills/telegram-send/SKILL.md.
---

# Telegram Send

Read the canonical skill:

${GIT_ROOT}/.agents/skills/telegram-send/SKILL.md
EOF
done

install -d "$GIT_ROOT/.cursor/rules"
cat > "$GIT_ROOT/.cursor/rules/telegram-send.mdc" <<EOF
---
description: Telegram outbound messaging through the canonical telegram-send skill
globs:
alwaysApply: false
---

For Telegram outbound messages, read:

${GIT_ROOT}/.agents/skills/telegram-send/SKILL.md
EOF

if [[ -n "$OWNER" ]]; then
  chown -R "$OWNER" \
    "$GIT_ROOT/.agents" "$TARGET_HOME/.agents" \
    "$GIT_ROOT/.codex" "$GIT_ROOT/.claude" "$GIT_ROOT/.github" "$GIT_ROOT/.hermes" "$GIT_ROOT/.cursor" \
    2>/dev/null || true
fi

echo "Installed telegram-send skill into $GIT_ROOT and $TARGET_HOME"

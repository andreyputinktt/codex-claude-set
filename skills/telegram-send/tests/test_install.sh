#!/usr/bin/env bash
set -euo pipefail

test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT

skill_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
project_root="$test_dir/project"
mkdir -p "$project_root"

printf '\n' | CODEX_HOME="$test_dir/codex" "$skill_root/scripts/install.sh" --yes
test -f "$test_dir/codex/skills/telegram-send/SKILL.md"
test -f "$test_dir/codex/skills/telegram-send/scripts/telegram_send.py"

"$skill_root/scripts/install.sh" --local --project "$project_root" --yes
test -f "$project_root/.codex/skills/telegram-send/SKILL.md"
test -f "$project_root/.codex/skills/telegram-send/scripts/telegram_send.py"

printf 'install tests passed\n'

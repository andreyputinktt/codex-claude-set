#!/usr/bin/env bash
# Copy this repository's skill payload into its mirrors.
#
# This repository is the source of truth. Every other copy of telegram-send is
# generated from it: `codex-claude-set/skills/telegram-send` (bootstrap kit for
# machines without GitLab access) and `<workspace>/.agents/skills/telegram-send`
# (what agents and the server actually run). Editing a mirror by hand is how the
# three lineages drifted apart in the first place.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/sync-mirrors.sh [--workspace DIR] [--check]

  --workspace DIR  Workspace root holding the mirrors (default: $GIT_ROOT, else
                   the third parent of this repository).
  --check          Report drift and exit non-zero instead of copying.
EOF
}

workspace="${GIT_ROOT:-}"
check=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) workspace="${2:?--workspace requires a directory}"; shift 2 ;;
    --check) check=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

skill_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "$workspace" ]]; then
  workspace="$(CDPATH= cd -- "$skill_dir/../../.." && pwd)"
fi

mirrors=(
  "$workspace/codex-claude-set/skills/telegram-send"
  "$workspace/.agents/skills/telegram-send"
)

payload=(SKILL.md contacts.json scripts tests agents)

status=0

report() {
  printf '%s: %s\n' "$1" "$2"
  [[ "$check" -eq 1 ]] && status=1
  return 0
}

for mirror in "${mirrors[@]}"; do
  if [[ ! -d "$mirror" ]]; then
    printf 'skip: %s does not exist\n' "$mirror"
    continue
  fi
  for item in "${payload[@]}"; do
    source="$skill_dir/$item"
    target="$mirror/$item"
    [[ -e "$source" ]] || continue
    if [[ -d "$source" ]]; then
      opts=(-a --delete --exclude __pycache__ --exclude '*.pyc' --exclude '.venv')
      [[ "$check" -eq 1 ]] && opts+=(--dry-run --itemize-changes --checksum)
      mkdir -p "$target"
      changes="$(rsync "${opts[@]}" "$source/" "$target/")"
      [[ -n "$changes" ]] && report "$mirror" "$item"$'\n'"$changes"
    elif ! cmp -s "$source" "$target"; then
      report "$mirror" "$item"
      [[ "$check" -eq 1 ]] || cp "$source" "$target"
    fi
  done
done

if [[ "$check" -eq 1 && "$status" -eq 0 ]]; then
  printf 'mirrors are up to date\n'
fi
exit "$status"

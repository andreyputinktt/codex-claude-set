#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/install.sh [--global|--local] [--project DIR] [--yes]

Install telegram-send for Codex.

Without a scope flag the script asks where to install and defaults to global.
  global  ${CODEX_HOME:-~/.codex}/skills/telegram-send
  local   <project>/.codex/skills/telegram-send

Options:
  --global         Install globally (the default).
  --local          Install into a project's .codex/skills directory.
  --project DIR    Project root for --local; defaults to the current directory.
  --yes            Replace an existing installation without asking.
  -h, --help       Show this help.
EOF
}

scope=""
project_dir="$PWD"
assume_yes=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --global) scope="global"; shift ;;
    --local) scope="local"; shift ;;
    --project) project_dir="${2:?--project requires a directory}"; shift 2 ;;
    --yes) assume_yes=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$scope" ]]; then
  printf 'Install scope [global/local] (global): '
  IFS= read -r scope || scope=""
  scope="${scope:-global}"
fi

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(CDPATH= cd -- "$script_dir/.." && pwd)"

case "$scope" in
  global)
    codex_root="${CODEX_HOME:-$HOME/.codex}"
    destination="$codex_root/skills/telegram-send"
    ;;
  local)
    project_dir="$(CDPATH= cd -- "$project_dir" && pwd)"
    destination="$project_dir/.codex/skills/telegram-send"
    ;;
  *)
    printf 'Scope must be global or local, got: %s\n' "$scope" >&2
    exit 2
    ;;
esac

if [[ -e "$destination" && "$assume_yes" -ne 1 ]]; then
  printf 'Replace existing installation at %s? [y/N]: ' "$destination"
  IFS= read -r confirm || confirm=""
  case "$confirm" in
    y|Y|yes|YES) ;;
    *) printf 'Installation cancelled.\n'; exit 0 ;;
  esac
fi

mkdir -p "$destination"
rsync -a --delete \
  --exclude .git \
  --exclude .gitignore \
  --exclude README.md \
  --exclude __pycache__ \
  --exclude '*.pyc' \
  "$skill_dir/" "$destination/"

printf 'Installed telegram-send (%s) at %s\n' "$scope" "$destination"

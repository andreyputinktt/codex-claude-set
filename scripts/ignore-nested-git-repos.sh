#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/ignore-nested-git-repos.sh [--root DIR] [--dry-run] [--check]
                                      [--max-depth N] [--extra PATH]

Adds nested Git repositories to the workspace root .gitignore so their contents
are not tracked twice by the parent workspace index.

Options:
  --root DIR      Workspace root. Default: $GIT_ROOT or $HOME/GIT.
  --dry-run       Print entries that would be appended.
  --check         Fail if .gitignore is missing entries.
  --max-depth N   Find depth for nested .git markers. Default: 6.
  --extra PATH    Also ensure this path is ignored. Can be repeated.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

normalize_rel() {
  local rel="$1"
  rel="${rel#./}"
  rel="${rel#/}"
  rel="${rel%/}"
  [[ -n "$rel" ]] || return 1
  case "$rel" in
    .git|.git/*|../*|*/../*|*/..)
      return 1
      ;;
  esac
  printf "%s" "$rel"
}

ignore_line_for() {
  local rel
  rel="$(normalize_rel "$1")" || return 1
  printf "/%s/" "$rel"
}

line_exists() {
  local gitignore="$1"
  local line="$2"
  local bare="${line#/}"
  [[ -f "$gitignore" ]] || return 1
  grep -Fxq "$line" "$gitignore" && return 0
  grep -Fxq "$bare" "$gitignore" && return 0
  return 1
}

covered_by_existing_parent() {
  local gitignore="$1"
  local line="$2"
  local rel top prefix rest next
  [[ -f "$gitignore" ]] || return 1
  rel="${line#/}"
  rel="${rel%/}"
  top="${rel%%/*}"

  grep -Fxq "/$top/*" "$gitignore" && return 0
  grep -Fxq "$top/*" "$gitignore" && return 0

  prefix=""
  rest="$rel"
  while [[ "$rest" == */* ]]; do
    next="${rest%%/*}"
    prefix="${prefix}${next}/"
    grep -Fxq "/$prefix" "$gitignore" && return 0
    grep -Fxq "$prefix" "$gitignore" && return 0
    rest="${rest#*/}"
  done
  return 1
}

covered_by_planned_parent() {
  local line="$1"
  local planned rel top
  rel="${line#/}"
  rel="${rel%/}"
  top="${rel%%/*}"
  for planned in "${MISSING[@]+"${MISSING[@]}"}"; do
    [[ "$planned" == "/$top/*" || "$planned" == "$top/*" ]] && return 0
    case "$line" in
      "$planned"*) return 0 ;;
    esac
  done
  return 1
}

tracked_warning() {
  local root="$1"
  local rel="$2"
  [[ -d "$root/.git" ]] || return 0
  if [[ -n "$(git -C "$root" ls-files "$rel" 2>/dev/null | head -n 1)" ]]; then
    echo "warning: $rel is already tracked by parent git; .gitignore will not untrack it" >&2
  fi
}

ROOT="${GIT_ROOT:-$HOME/GIT}"
DRY_RUN=0
CHECK_ONLY=0
MAX_DEPTH=6
EXTRAS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --check)
      CHECK_ONLY=1
      shift
      ;;
    --max-depth)
      MAX_DEPTH="${2:-}"
      shift 2
      ;;
    --extra)
      EXTRAS+=("${2:-}")
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
[[ "$MAX_DEPTH" =~ ^[0-9]+$ ]] || die "--max-depth must be a number"
ROOT="$(mkdir -p "$ROOT" && cd "$ROOT" && pwd)"
GITIGNORE="$ROOT/.gitignore"

ENTRIES=()

add_entry() {
  local rel line
  rel="$(normalize_rel "$1")" || return 0
  line="$(ignore_line_for "$rel")" || return 0
  ENTRIES+=("$line")
}

while IFS= read -r -d '' marker; do
  repo="$(dirname "$marker")"
  [[ "$repo" == "$ROOT" ]] && continue
  rel="${repo#"$ROOT"/}"
  [[ "$rel" == "$repo" ]] && continue
  case "$rel" in
    .git|.git/*|.codex|.codex/*|.claude|.claude/*|node_modules|node_modules/*|.cache|.cache/*|tmp|tmp/*|logs|logs/*)
      continue
      ;;
  esac
  add_entry "$rel"
done < <(
  find "$ROOT" -mindepth 2 -maxdepth "$MAX_DEPTH" \
    \( -type d \( -name node_modules -o -name .cache -o -name tmp -o -name logs \) -prune \) -o \
    \( -type d -name .git -o -type f -name .git \) -print0 2>/dev/null \
    | sort -z
)

for extra in "${EXTRAS[@]+"${EXTRAS[@]}"}"; do
  add_entry "$extra"
done

UNIQUE_ENTRIES=()
if [[ "${#ENTRIES[@]}" -gt 0 ]]; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    UNIQUE_ENTRIES+=("$line")
  done < <(printf "%s\n" "${ENTRIES[@]}" | sort -u)
fi
ENTRIES=("${UNIQUE_ENTRIES[@]+"${UNIQUE_ENTRIES[@]}"}")

MISSING=()
for line in "${ENTRIES[@]+"${ENTRIES[@]}"}"; do
  if ! line_exists "$GITIGNORE" "$line" \
    && ! covered_by_existing_parent "$GITIGNORE" "$line" \
    && ! covered_by_planned_parent "$line"; then
    MISSING+=("$line")
  fi
done

if [[ "${#MISSING[@]}" -eq 0 ]]; then
  echo "nested git ignore: ok"
  exit 0
fi

if [[ "$CHECK_ONLY" -eq 1 || "$DRY_RUN" -eq 1 ]]; then
  for line in "${MISSING[@]}"; do
    echo "would add to .gitignore: $line"
  done
  [[ "$CHECK_ONLY" -eq 0 ]] || exit 1
  exit 0
fi

touch "$GITIGNORE"
for line in "${MISSING[@]}"; do
  rel="${line#/}"
  rel="${rel%/}"
  tracked_warning "$ROOT" "$rel"
  printf "%s\n" "$line" >> "$GITIGNORE"
done

echo "nested git ignore: added ${#MISSING[@]} entr$( [[ "${#MISSING[@]}" -eq 1 ]] && printf 'y' || printf 'ies' )"

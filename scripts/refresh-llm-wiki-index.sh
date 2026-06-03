#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/refresh-llm-wiki-index.sh [--root DIR] [--dry-run] [--check]

Maintains a llm-wiki workspace:
- creates missing root README/DEV/AGENTS/CLAUDE/llm-wiki/.gitignore files;
- creates standard top-level starter folders and folder README files;
- creates missing repo README/DEV/AGENTS/CLAUDE/.gitignore files;
- updates only the marker-managed index block in root README.md.

Options:
  --root DIR              Workspace root. Default: $GIT_ROOT or $HOME/GIT.
  --dry-run               Print planned writes without changing files.
  --check                 Fail if changes would be needed.
  --no-standard-folders   Do not create starter folders.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

note_change() {
  CHANGES=$((CHANGES + 1))
  if [[ "$DRY_RUN" -eq 1 || "$CHECK_ONLY" -eq 1 ]]; then
    echo "would update: $1"
  fi
}

write_file_if_missing() {
  local path="$1"
  shift
  if [[ -f "$path" ]]; then
    return
  fi
  note_change "$path"
  if [[ "$DRY_RUN" -eq 1 || "$CHECK_ONLY" -eq 1 ]]; then
    return
  fi
  mkdir -p "$(dirname "$path")"
  printf "%s\n" "$@" > "$path"
}

first_heading() {
  local path="$1"
  if [[ -f "$path" ]]; then
    awk '
      /^#[[:space:]]+/ {
        sub(/^#[[:space:]]+/, "")
        print
        exit
      }
    ' "$path"
  fi
}

safe_table_text() {
  local value="$1"
  value="${value//$'\n'/ }"
  value="${value//|/\\|}"
  printf "%s" "$value"
}

ensure_root_files() {
  mkdir -p "$ROOT"

  write_file_if_missing "$ROOT/README.md" \
    "# Repository Index" \
    "" \
    "Root workspace for AI-assisted work. Start here, then read DEV.md, then the target repo README."

  write_file_if_missing "$ROOT/DEV.md" \
    "# Development And Server Rules" \
    "" \
    "Use README files as indexes. Use OpenSpec for code, behavior, deploy, integration, prompt, and workflow changes. Keep secrets in ignored .env files."

  write_file_if_missing "$ROOT/AGENTS.md" \
    "# Agent guide" \
    "@README.md" \
    "" \
    "Dev rules: [DEV.md](DEV.md)."

  write_file_if_missing "$ROOT/CLAUDE.md" \
    "@README.md"

  write_file_if_missing "$ROOT/llm-wiki.md" \
    "# LLM Wiki" \
    "" \
    "Read root README, then DEV, then the target repo README. One fact lives in one place. Keep README files as indexes, not diaries."

  write_file_if_missing "$ROOT/.gitignore" \
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
}

ensure_standard_folders() {
  [[ "$CREATE_STANDARD_FOLDERS" -eq 1 ]] || return
  local folder
  for folder in assistants projects services sites contexts outputs archives docs; do
    mkdir -p "$ROOT/$folder"
    write_file_if_missing "$ROOT/$folder/README.md" \
      "# $folder" \
      "" \
      "Index for $folder. Link to child repos or important files instead of duplicating details."
  done
}

is_ignored_top_level_dir() {
  case "$1" in
    .git|.codex|.claude|node_modules|venv|.venv|__pycache__|tmp|logs|.cache|dist|build)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

collect_top_folders() {
  TOP_FOLDERS=()
  local path name
  while IFS= read -r -d '' path; do
    name="$(basename "$path")"
    is_ignored_top_level_dir "$name" && continue
    [[ "$name" == .* ]] && continue
    TOP_FOLDERS+=("$name")
  done < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
}

collect_repos() {
  REPOS=()
  local gitdir repo rel
  while IFS= read -r -d '' gitdir; do
    repo="$(dirname "$gitdir")"
    [[ "$repo" == "$ROOT" ]] && continue
    rel="${repo#"$ROOT"/}"
    [[ "$rel" == "$repo" ]] && continue
    case "$rel" in
      .git|.git/*|node_modules/*|.cache/*|tmp/*|logs/*)
        continue
        ;;
    esac
    REPOS+=("$rel")
  done < <(find "$ROOT" -mindepth 2 -maxdepth 4 -type d -name .git -print0 2>/dev/null | sort -z)
}

ensure_repo_files() {
  local rel repo name
  [[ "${#REPOS[@]}" -gt 0 ]] || return 0
  for rel in "${REPOS[@]}"; do
    repo="$ROOT/$rel"
    name="$(basename "$repo")"
    write_file_if_missing "$repo/README.md" \
      "# $name" \
      "" \
      "Repository index. Document purpose, run commands, dependencies, and links to deeper docs."
    write_file_if_missing "$repo/AGENTS.md" \
      "# Agent guide" \
      "@README.md" \
      "" \
      "Dev rules: [DEV.md](DEV.md)."
    write_file_if_missing "$repo/CLAUDE.md" \
      "@README.md"
    write_file_if_missing "$repo/DEV.md" \
      "# Development" \
      "" \
      "Use OpenSpec for behavior/code/deploy changes. Keep secrets out of git."
    write_file_if_missing "$repo/.gitignore" \
      ".env" \
      ".env-*" \
      "!.env.example" \
      ".venv/" \
      "venv/" \
      "node_modules/" \
      "__pycache__/" \
      "*.log"
  done
}

write_managed_block() {
  local block_file="$1"
  local folder rel title

  {
    echo "<!-- ai-index:start -->"
    echo "## Workspace Index"
    echo
    echo "Managed by \`ai-index-refresh\`. Edit descriptions in child README files; rerun the command to refresh this block."
    echo
    echo "### Folders"
    echo
    echo "| Folder | Description |"
    echo "| --- | --- |"
    if [[ "${#TOP_FOLDERS[@]}" -gt 0 ]]; then
      for folder in "${TOP_FOLDERS[@]}"; do
        title="$(first_heading "$ROOT/$folder/README.md")"
        [[ -n "$title" ]] || title="$folder"
        printf '| `%s/` | %s |\n' "$folder" "$(safe_table_text "$title")"
      done
    fi
    echo
    echo "### Repositories"
    echo
    echo "| Repository | Description |"
    echo "| --- | --- |"
    if [[ "${#REPOS[@]}" -gt 0 ]]; then
      for rel in "${REPOS[@]}"; do
        title="$(first_heading "$ROOT/$rel/README.md")"
        [[ -n "$title" ]] || title="$(basename "$rel")"
        printf '| `%s/` | %s |\n' "$rel" "$(safe_table_text "$title")"
      done
    fi
    echo "<!-- ai-index:end -->"
  } > "$block_file"
}

update_root_readme_block() {
  local readme="$ROOT/README.md"
  local block tmp
  block="$(mktemp)"
  tmp="$(mktemp)"
  write_managed_block "$block"

  awk -v block_file="$block" '
    BEGIN {
      while ((getline line < block_file) > 0) {
        block = block line ORS
      }
      in_block = 0
      replaced = 0
    }
    /<!-- ai-index:start -->/ {
      printf "%s", block
      in_block = 1
      replaced = 1
      next
    }
    /<!-- ai-index:end -->/ {
      in_block = 0
      next
    }
    in_block == 0 {
      print
    }
    END {
      if (replaced == 0) {
        print ""
        printf "%s", block
      }
    }
  ' "$readme" > "$tmp"

  if ! cmp -s "$readme" "$tmp"; then
    note_change "$readme"
    if [[ "$DRY_RUN" -eq 0 && "$CHECK_ONLY" -eq 0 ]]; then
      mv "$tmp" "$readme"
    fi
  fi
  rm -f "$block" "$tmp"
}

ROOT="${GIT_ROOT:-$HOME/GIT}"
DRY_RUN=0
CHECK_ONLY=0
CREATE_STANDARD_FOLDERS=1
CHANGES=0
TOP_FOLDERS=()
REPOS=()

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
    --no-standard-folders)
      CREATE_STANDARD_FOLDERS=0
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

[[ -n "$ROOT" ]] || die "--root is required"
ROOT="$(mkdir -p "$ROOT" && cd "$ROOT" && pwd)"

ensure_root_files
ensure_standard_folders
collect_top_folders
collect_repos
ensure_repo_files
collect_top_folders
collect_repos
update_root_readme_block

if [[ "$CHECK_ONLY" -eq 1 && "$CHANGES" -gt 0 ]]; then
  die "$CHANGES llm-wiki update(s) needed"
fi

if [[ "$CHANGES" -eq 0 ]]; then
  info "llm-wiki index is current: $ROOT"
else
  info "llm-wiki updates: $CHANGES"
fi

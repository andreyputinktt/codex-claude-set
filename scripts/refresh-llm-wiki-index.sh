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
- updates one marker-managed folder index table in root README.md.

Options:
  --root DIR              Workspace root. Default: $GIT_ROOT or $HOME/GIT.
  --dry-run               Print planned writes without changing files.
  --check                 Fail if changes would be needed.
  --no-standard-folders   Do not create starter folders.
  --no-ignore-nested-git  Do not update root .gitignore for nested Git repos.
  --codex-session-limit N Latest Codex session logs to scan for folder hints.
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
    "Root workspace for AI-assisted work. Start here, then read DEV.md when relevant, then the target folder README."

  write_file_if_missing "$ROOT/DEV.md" \
    "# Development And Server Rules" \
    "" \
    "Use README files as indexes. Root README chooses the folder; child README files own details and dependencies. Use OpenSpec for code, behavior, deploy, integration, prompt, and workflow changes. Keep secrets in ignored .env files." \
    "" \
    "If git status shows uncommitted changes, run ./deploy-server.py immediately. If the script is missing, report that the workspace is missing its deploy boundary."

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
    "Read root README, then DEV when relevant, then the target folder README. Root README chooses the folder and does not duplicate child internals or cross-repo dependency graphs. One fact lives in one place. Keep README files as indexes, not diaries. Keep AGENTS.md and CLAUDE.md as thin pointers."

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
    ".DS_Store" \
    "sloy-KT/"
}

ensure_nested_git_ignores() {
  [[ "$IGNORE_NESTED_GIT" -eq 1 ]] || return 0
  local helper_args=("--root" "$ROOT" "--extra" "sloy-KT")
  if [[ "$DRY_RUN" -eq 1 ]]; then
    helper_args+=("--dry-run")
  fi
  if [[ "$CHECK_ONLY" -eq 1 ]]; then
    helper_args+=("--check")
  fi

  if [[ -x "$IGNORE_NESTED_GIT_SCRIPT" ]]; then
    "$IGNORE_NESTED_GIT_SCRIPT" "${helper_args[@]}"
  elif [[ -f "$IGNORE_NESTED_GIT_SCRIPT" ]]; then
    bash "$IGNORE_NESTED_GIT_SCRIPT" "${helper_args[@]}"
  elif [[ "$CHECK_ONLY" -eq 1 ]]; then
    die "nested git ignore helper not found: $IGNORE_NESTED_GIT_SCRIPT"
  fi
}

ensure_standard_folders() {
  [[ "$CREATE_STANDARD_FOLDERS" -eq 1 ]] || return 0
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

is_readonly_workspace_dir() {
  case "$1" in
    sloy-KT|sloy-KT/*)
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
    is_readonly_workspace_dir "$rel" && continue
    case "$rel" in
      .git|.git/*|node_modules/*|.cache/*|tmp/*|logs/*)
        continue
        ;;
    esac
    REPOS+=("$rel")
  done < <(find "$ROOT" -mindepth 2 -maxdepth 4 -type d -name .git -print0 2>/dev/null | sort -z)
}

collect_index_entries() {
  INDEX_ENTRIES=()
  local folder
  for folder in "${TOP_FOLDERS[@]+"${TOP_FOLDERS[@]}"}"; do
    INDEX_ENTRIES+=("$folder")
  done
}

ensure_repo_files() {
  local rel repo name
  for rel in "${REPOS[@]+"${REPOS[@]}"}"; do
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

entry_is_repo() {
  local entry="$1"
  local rel
  [[ -d "$ROOT/$entry/.git" ]] && return 0
  for rel in "${REPOS[@]+"${REPOS[@]}"}"; do
    [[ "$rel" == "$entry" ]] && return 0
  done
  return 1
}

entry_cases() {
  local entry="$1"
  if entry_is_repo "$entry"; then
    printf 'Code, behavior, deploy, or repo-specific docs -> `%s/README.md`.' "$entry"
  else
    printf 'Folder-level navigation, data, or generated artifacts -> `%s/README.md`.' "$entry"
  fi
}

collect_recent_codex_sessions() {
  RECENT_CODEX_SESSIONS=()
  CODEX_SESSIONS_DIR_RESOLVED="${CODEX_SESSIONS_DIR:-$HOME/.codex/sessions}"
  [[ "$CODEX_SESSION_LIMIT" =~ ^[0-9]+$ ]] || die "--codex-session-limit must be a number"
  [[ "$CODEX_SESSION_LIMIT" -gt 0 ]] || return 0
  [[ -d "$CODEX_SESSIONS_DIR_RESOLVED" ]] || return 0

  local file
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    RECENT_CODEX_SESSIONS+=("$file")
  done < <(find "$CODEX_SESSIONS_DIR_RESOLVED" -type f -name '*.jsonl' -print 2>/dev/null | sort | tail -n "$CODEX_SESSION_LIMIT")
}

codex_session_hint_for() {
  local entry="$1"
  local file label count idx shown out
  local labels=()
  count=0
  for file in "${RECENT_CODEX_SESSIONS[@]+"${RECENT_CODEX_SESSIONS[@]}"}"; do
    if grep -Fq "$ROOT/$entry" "$file" 2>/dev/null || grep -Fq "$entry/" "$file" 2>/dev/null; then
      label="${file#"$CODEX_SESSIONS_DIR_RESOLVED"/}"
      label="${label%.jsonl}"
      labels+=("$label")
      count=$((count + 1))
    fi
  done

  [[ "$count" -gt 0 ]] || {
    printf '%s' '-'
    return 0
  }

  out="$count chat"
  [[ "$count" -eq 1 ]] || out="${out}s"
  out="${out}: "
  shown=0
  for ((idx=${#labels[@]} - 1; idx >= 0 && shown < 2; idx--)); do
    [[ "$shown" -eq 0 ]] || out="${out}, "
    out="${out}${labels[$idx]}"
    shown=$((shown + 1))
  done
  [[ "$count" -le "$shown" ]] || out="${out}, ..."
  printf '%s' "$out"
}

write_managed_block() {
  local block_file="$1"
  local entry title cases codex_hint

  {
    echo "<!-- ai-index:start -->"
    echo "## Workspace Index"
    echo
    echo "Managed by \`ai-index-refresh\`. Root README chooses the folder; child README files own details and dependencies. Rerun the command to refresh this block."
    echo "Use the cases column as search hints. Codex hints scan the latest ${CODEX_SESSION_LIMIT} session logs and show only session paths where a folder was already mentioned."
    echo
    echo "| Folder | Description | Cases | Codex hints |"
    echo "| --- | --- | --- | --- |"
    for entry in "${INDEX_ENTRIES[@]+"${INDEX_ENTRIES[@]}"}"; do
      title="$(first_heading "$ROOT/$entry/README.md")"
      [[ -n "$title" ]] || title="$(basename "$entry")"
      cases="$(entry_cases "$entry")"
      codex_hint="$(codex_session_hint_for "$entry")"
      printf '| `%s/` | %s | %s | %s |\n' \
        "$entry" \
        "$(safe_table_text "$title")" \
        "$(safe_table_text "$cases")" \
        "$(safe_table_text "$codex_hint")"
    done
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IGNORE_NESTED_GIT_SCRIPT="${AI_IGNORE_NESTED_GIT_SCRIPT:-$SCRIPT_DIR/ignore-nested-git-repos.sh}"
DRY_RUN=0
CHECK_ONLY=0
CREATE_STANDARD_FOLDERS=1
IGNORE_NESTED_GIT=1
CODEX_SESSION_LIMIT=30
CHANGES=0
TOP_FOLDERS=()
REPOS=()
INDEX_ENTRIES=()
RECENT_CODEX_SESSIONS=()
CODEX_SESSIONS_DIR_RESOLVED=""

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
    --no-ignore-nested-git)
      IGNORE_NESTED_GIT=0
      shift
      ;;
    --codex-session-limit)
      CODEX_SESSION_LIMIT="${2:-}"
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

[[ -n "$ROOT" ]] || die "--root is required"
ROOT="$(mkdir -p "$ROOT" && cd "$ROOT" && pwd)"

ensure_root_files
ensure_nested_git_ignores
ensure_standard_folders
collect_top_folders
collect_repos
ensure_repo_files
collect_top_folders
collect_repos
collect_index_entries
collect_recent_codex_sessions
update_root_readme_block

if [[ "$CHECK_ONLY" -eq 1 && "$CHANGES" -gt 0 ]]; then
  die "$CHANGES llm-wiki update(s) needed"
fi

if [[ "$CHANGES" -eq 0 ]]; then
  info "llm-wiki index is current: $ROOT"
else
  info "llm-wiki updates: $CHANGES"
fi

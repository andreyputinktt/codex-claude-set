#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/install-local-prereqs.sh [--yes] [--agent-tools] [--dry-run]

Installs or checks local tools needed before beginner onboarding:
git, ssh, rsync, curl, jq, ripgrep, gh, node/npm, OpenSpec, and skills.

Options:
  --yes          Do not ask before installing packages.
  --agent-tools  Also install Codex, Claude Code, OpenClaw, and OpenCode via npm.
  --dry-run      Print actions without changing the system.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

ask_yes_no() {
  local prompt="$1"
  local default="${2:-yes}"
  local value

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi

  read -r -p "$prompt [$default]: " value || true
  value="${value:-$default}"
  [[ "$value" =~ ^[YyДд] ]]
}

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'DRY RUN:'
    printf ' %q' "$@"
    printf '\n'
    return
  fi
  "$@"
}

install_macos() {
  if ! have brew; then
    cat <<'EOF'
Homebrew is not installed.
Open this link and follow the install command, then rerun this script:
https://brew.sh/
EOF
    return
  fi

  local packages=(git jq ripgrep fd gh node)
  if ask_yes_no "Install/update macOS packages with Homebrew?" "yes"; then
    run_cmd brew install "${packages[@]}" || true
  fi
}

install_linux_apt() {
  local packages=(
    ca-certificates curl git jq openssh-client rsync ripgrep
    nodejs npm python3 python3-venv python3-pip
  )
  if apt-cache show gh >/dev/null 2>&1; then
    packages+=(gh)
  fi
  if ask_yes_no "Install Linux packages with apt?" "yes"; then
    run_cmd sudo apt-get update
    run_cmd sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
  fi
}

install_linux_dnf() {
  local packages=(ca-certificates curl git jq openssh-clients rsync ripgrep nodejs npm python3 python3-pip gh)
  if ask_yes_no "Install Linux packages with dnf?" "yes"; then
    run_cmd sudo dnf install -y "${packages[@]}"
  fi
}

install_linux_pacman() {
  local packages=(ca-certificates curl git jq openssh rsync ripgrep fd github-cli nodejs npm python python-pip)
  if ask_yes_no "Install Linux packages with pacman?" "yes"; then
    run_cmd sudo pacman -Sy --needed --noconfirm "${packages[@]}"
  fi
}

install_npm_tools() {
  if ! have npm; then
    info "npm is not available; skipping npm global tools"
    return
  fi

  local packages=("@fission-ai/openspec" "skills")
  if [[ "$INSTALL_AGENT_TOOLS" -eq 1 ]]; then
    packages+=("@openai/codex" "@anthropic-ai/claude-code" "openclaw" "opencode-ai")
  fi

  if ask_yes_no "Install/update npm global AI tools: ${packages[*]}?" "yes"; then
    run_cmd npm install -g "${packages[@]}"
  fi
}

print_status() {
  local cmd
  echo
  echo "== Tool status =="
  for cmd in git ssh rsync curl jq rg gh node npm openspec skills codex claude openclaw opencode; do
    if have "$cmd"; then
      printf "%-12s %s\n" "$cmd" "$(command -v "$cmd")"
    else
      printf "%-12s %s\n" "$cmd" "missing"
    fi
  done
}

ASSUME_YES=0
INSTALL_AGENT_TOOLS=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y)
      ASSUME_YES=1
      shift
      ;;
    --agent-tools)
      INSTALL_AGENT_TOOLS=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
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

case "$(uname -s)" in
  Darwin)
    install_macos
    ;;
  Linux)
    if have apt-get; then
      install_linux_apt
    elif have dnf; then
      install_linux_dnf
    elif have pacman; then
      install_linux_pacman
    else
      info "Unsupported Linux package manager. Install git, ssh, rsync, curl, jq, rg, gh, node, and npm manually."
    fi
    ;;
  *)
    die "unsupported OS for this script; use windows/onboarding.ps1 on Windows"
    ;;
esac

install_npm_tools
print_status

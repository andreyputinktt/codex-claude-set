#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/prepare-server-access.sh [--host HOST] [--user USER] [--kind kt|personal]
                                   [--key PATH] [--install-key] [--disable-password]

Prepares SSH access for an AI server:
- creates/reuses a local Ed25519 key;
- prints the public key and admin-ready access request;
- can install the key when password SSH already works;
- can disable password SSH after key login is verified.

Examples:
  scripts/prepare-server-access.sh --host ai4u.kt.team --user ivan --kind kt
  scripts/prepare-server-access.sh --host 1.2.3.4 --user root --kind personal --install-key
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

ask() {
  local name="$1"
  local prompt="$2"
  local default="${3:-}"
  local value
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " value || true
    value="${value:-$default}"
  else
    read -r -p "$prompt: " value || true
  fi
  printf -v "$name" "%s" "$value"
}

ask_yes_no() {
  local name="$1"
  local prompt="$2"
  local default="${3:-yes}"
  local value
  read -r -p "$prompt [$default]: " value || true
  value="${value:-$default}"
  if [[ "$value" =~ ^[YyДд] ]]; then
    printf -v "$name" "yes"
  else
    printf -v "$name" "no"
  fi
}

shell_quote() {
  printf "%q" "$1"
}

ensure_key() {
  mkdir -p "$(dirname "$KEY_PATH")"
  chmod 700 "$(dirname "$KEY_PATH")"
  if [[ ! -f "$KEY_PATH" ]]; then
    info "Creating SSH key: $KEY_PATH"
    ssh-keygen -t ed25519 -N "" -C "ai-server-access@$HOST" -f "$KEY_PATH"
  elif [[ ! -f "$KEY_PATH.pub" ]]; then
    info "Restoring missing public key: $KEY_PATH.pub"
    ssh-keygen -y -f "$KEY_PATH" > "$KEY_PATH.pub"
  fi
  [[ -f "$KEY_PATH.pub" ]] || die "public key missing: $KEY_PATH.pub"
}

print_access_message() {
  local public_key
  public_key="$(cat "$KEY_PATH.pub")"
  echo
  echo "=== Public SSH key ==="
  echo "$public_key"
  echo
  echo "=== Server access request ==="
  cat <<EOF
Дима, привет! Нужен доступ к серверу для рабочего AI/Codex окружения.

Сервер: $HOST
Пользователь: $USER_NAME
Нужны права: sudo, доступ по SSH.
Публичный ключ:
$public_key

После добавления я подключусь и сам разверну Codex/Claude/OpenSpec/Git/Telegram.
EOF
}

install_key_with_password() {
  local target="$USER_NAME@$HOST"
  local public_key quoted_key
  public_key="$(cat "$KEY_PATH.pub")"
  quoted_key="$(shell_quote "$public_key")"

  info "Installing public key on $target. Enter the server password if SSH asks."
  if command -v ssh-copy-id >/dev/null 2>&1; then
    ssh-copy-id -i "$KEY_PATH.pub" "$target"
    return
  fi

  ssh "$target" "set -e
umask 077
mkdir -p ~/.ssh
touch ~/.ssh/authorized_keys
grep -qxF $quoted_key ~/.ssh/authorized_keys || printf '%s\n' $quoted_key >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys"
}

verify_key_login() {
  local target="$USER_NAME@$HOST"
  info "Verifying key-based SSH login to $target"
  ssh -i "$KEY_PATH" -o IdentitiesOnly=yes -o BatchMode=yes "$target" \
    "echo SSH_KEY_OK && hostname && whoami"
}

disable_password_auth() {
  local target="$USER_NAME@$HOST"
  info "Disabling password SSH on $target after verified key login"
  ssh -t -i "$KEY_PATH" -o IdentitiesOnly=yes "$target" "set -e
if [ \"\$(id -u)\" = 0 ]; then SUDO=''; else SUDO='sudo'; fi
printf '%s\n' \
  'PasswordAuthentication no' \
  'KbdInteractiveAuthentication no' \
  'ChallengeResponseAuthentication no' \
  | \$SUDO tee /etc/ssh/sshd_config.d/60-codex-key-only.conf >/dev/null
\$SUDO sshd -t
(\$SUDO systemctl reload ssh || \$SUDO systemctl reload sshd)"
  verify_key_login
}

HOST=""
USER_NAME=""
KIND=""
KEY_PATH="${HOME}/.ssh/ai_server_ed25519"
INSTALL_KEY="ask"
DISABLE_PASSWORD="ask"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --user)
      USER_NAME="${2:-}"
      shift 2
      ;;
    --kind)
      KIND="${2:-}"
      shift 2
      ;;
    --key)
      KEY_PATH="${2:-}"
      shift 2
      ;;
    --install-key)
      INSTALL_KEY="yes"
      shift
      ;;
    --no-install-key)
      INSTALL_KEY="no"
      shift
      ;;
    --disable-password)
      DISABLE_PASSWORD="yes"
      shift
      ;;
    --keep-password)
      DISABLE_PASSWORD="no"
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

if [[ -z "$HOST" ]]; then
  ask HOST "Server IP or hostname"
fi
if [[ -z "$USER_NAME" ]]; then
  ask USER_NAME "Linux username on the server"
fi
if [[ -z "$KIND" ]]; then
  ask KIND "Server kind: kt or personal" "personal"
fi
[[ "$KIND" == "kt" || "$KIND" == "personal" ]] || die "--kind must be kt or personal"
[[ -n "$HOST" && -n "$USER_NAME" ]] || die "host and user are required"

ensure_key
print_access_message

if [[ "$KIND" == "kt" ]]; then
  cat <<EOF

For a KT-managed server, send the access request above to the server admin.
After access is added, verify with:

ssh -i $(shell_quote "$KEY_PATH") -o IdentitiesOnly=yes $USER_NAME@$HOST "echo SSH_OK"
EOF
  exit 0
fi

if [[ "$INSTALL_KEY" == "ask" ]]; then
  ask_yes_no INSTALL_KEY "Do you already have password SSH and want to install this key now?" "yes"
fi
if [[ "$INSTALL_KEY" == "yes" ]]; then
  install_key_with_password
fi

if verify_key_login; then
  if [[ "$DISABLE_PASSWORD" == "ask" ]]; then
    ask_yes_no DISABLE_PASSWORD "Disable password SSH and use key-only login?" "no"
  fi
  if [[ "$DISABLE_PASSWORD" == "yes" ]]; then
    disable_password_auth
  fi
else
  cat <<EOF

Key login is not working yet. Keep password SSH enabled and ask the server
admin/provider to add this public key:

$(cat "$KEY_PATH.pub")
EOF
  exit 1
fi

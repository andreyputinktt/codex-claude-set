#!/usr/bin/env bash

# KT-specific onboarding defaults. Keep corporate URLs and employee-only prompts
# here so generic onboarding scripts do not hard-code the same values. Simple
# scalar values live in kt.env so bash and PowerShell can share them.

KT_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KT_ENV_FILE="${KT_ENV_FILE:-$KT_CONFIG_DIR/kt.env}"

kt_config_value() {
  local key="$1"
  local default="$2"
  local value=""
  if [[ -f "$KT_ENV_FILE" ]]; then
    value="$(awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$KT_ENV_FILE")"
  fi
  printf "%s" "${value:-$default}"
}

KT_AI_SERVER_HOST="${KT_AI_SERVER_HOST:-$(kt_config_value KT_AI_SERVER_HOST "ai4u.kt.team")}"
KT_GITLAB_URL="${KT_GITLAB_URL:-$(kt_config_value KT_GITLAB_URL "https://gitlab.kt-team.de/")}"
KT_SYNC_SERVICE_URL="${KT_SYNC_SERVICE_URL:-$(kt_config_value KT_SYNC_SERVICE_URL "https://sync-service.osno-va.com/")}"
KT_SYNC_AGENT_BUTTON="${KT_SYNC_AGENT_BUTTON:-$(kt_config_value KT_SYNC_AGENT_BUTTON "Подключить агента")}"
KT_SERVER_ADMIN_NAME="${KT_SERVER_ADMIN_NAME:-$(kt_config_value KT_SERVER_ADMIN_NAME "Дима")}"

KT_SYNC_AGENT_CHAT_REQUEST="${KT_SYNC_AGENT_CHAT_REQUEST:-Сходите в ${KT_SYNC_SERVICE_URL} и нажмите кнопку \"${KT_SYNC_AGENT_BUTTON}\" и дайте последнюю инструкцию установки в этот чат.}"

kt_print_sync_agent_request() {
  cat <<EOF
$KT_SYNC_AGENT_CHAT_REQUEST
EOF
}

kt_print_server_access_message() {
  local host="$1"
  local user_name="$2"
  local public_key="$3"

  cat <<EOF
$KT_SERVER_ADMIN_NAME, привет! Нужен доступ к серверу для рабочего AI/Codex окружения.

Сервер: $host
Пользователь: $user_name
Нужны права: sudo, доступ по SSH.
Публичный ключ:
$public_key

После добавления я подключусь и сам разверну Codex/Claude/OpenSpec/Git/Telegram.
EOF
}

#!/usr/bin/env bash
# FireWallBot - Bash interactive command audit (source this file)
# Records executed commands to JSONL with timestamp, user, ip, cwd, tty, rc.

# Usage:
#   source /path/to/scripts/cmd_audit.sh
# To make it system-wide for bash, place it under /etc/profile.d/ (requires root).

set -o errexit -o pipefail

if [[ $- != *i* ]]; then
  # Non-interactive shell: do nothing
  return 0 2>/dev/null || exit 0
fi

# Determine repo-root relative log dir based on this script location
_FWBOT_THIS_FILE="${BASH_SOURCE[0]}"
_FWBOT_DIR="$(cd -- "$(dirname -- "${_FWBOT_THIS_FILE}")" >/dev/null 2>&1 && pwd)"
_FWBOT_REPO_ROOT="$(cd -- "${_FWBOT_DIR}/.." && pwd)"
_FWBOT_LOG_DIR_DEFAULT="${_FWBOT_REPO_ROOT}/log"
FIREWALLBOT_LOG_DIR="${FIREWALLBOT_LOG_DIR:-${_FWBOT_LOG_DIR_DEFAULT}}"
mkdir -p -- "${FIREWALLBOT_LOG_DIR}"
_FWBOT_CMD_LOG_FILE="${FIREWALLBOT_CMD_LOG:-${FIREWALLBOT_LOG_DIR}/commands.jsonl}"

# Guard against recursion
__FWBOT_LOGGING=0

fwbot__json_escape() {
  # Escapes JSON special characters in a single line
  local s=${1//\/\\}
  s=${s//"/\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

fwbot_log_last_command() {
  local rc=$?  # exit status of last command
  [[ $__FWBOT_LOGGING -eq 1 ]] && return 0
  __FWBOT_LOGGING=1

  # Skip if command is empty
  local cmd="${FWBOT_LAST_CMD:-}"
  if [[ -z "$cmd" ]]; then
    __FWBOT_LOGGING=0; return 0
  fi

  # Filter out our internal commands
  case "$cmd" in
    fwbot_log_last_command*|history\ *|history)
      __FWBOT_LOGGING=0; return 0 ;;
  esac

  local now epoch_iso user uid gid cwd host tty ip port
  now=$(date -u +%s)
  epoch_iso=$(date -u -Iseconds | sed 's/+00:00/Z/')
  user=${USER:-$(id -un)}
  uid=${UID:-$(id -u)}
  gid=${GID:-$(id -g)}
  cwd=${PWD}
  host=$(hostname -s 2>/dev/null || hostname)
  tty=$(tty 2>/dev/null || echo "unknown")

  if [[ -n "$SSH_CONNECTION" ]]; then
    # SSH_CONNECTION="client_ip client_port server_ip server_port"
    ip=$(awk '{print $1}' <<<"$SSH_CONNECTION")
    port=$(awk '{print $2}' <<<"$SSH_CONNECTION")
  else
    ip="local"
    port=""
  fi

  local cmd_json
  cmd_json=$(fwbot__json_escape "$cmd")

  printf '{"type":"exec","ts":"%s","user":"%s","uid":%s,"gid":%s,"ip":"%s","port":"%s","tty":"%s","cwd":"%s","rc":%s,"cmd":"%s","host":"%s"}\n' \
    "$epoch_iso" "$user" "$uid" "$gid" "$ip" "$port" "$tty" "$cwd" "$rc" "$cmd_json" "$host" \
      >> "${_FWBOT_CMD_LOG_FILE}" 2>/dev/null || true

  __FWBOT_LOGGING=0
}

# Capture the command about to run
trap 'FWBOT_LAST_CMD=$BASH_COMMAND' DEBUG

# Chain with existing PROMPT_COMMAND if present
if [[ -n "$PROMPT_COMMAND" ]]; then
  PROMPT_COMMAND="fwbot_log_last_command; ${PROMPT_COMMAND}"
else
  PROMPT_COMMAND="fwbot_log_last_command"
fi

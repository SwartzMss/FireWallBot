#!/usr/bin/env bash
# FireWallBot - cmdwatcher (bash interactive command logging)
# Install via: sudo bash ./service.sh install cmdwatcher
# This file is symlinked into /etc/profile.d by service.sh.

set -o errtrace

if [[ $- != *i* ]]; then
  return 0 2>/dev/null || exit 0
fi

_FWBOT_THIS_FILE="${BASH_SOURCE[0]}"
# Try to resolve repo root from symlink target if possible
if [[ -L "${_FWBOT_THIS_FILE}" ]]; then
  _FWBOT_SRC="$(readlink -f "${_FWBOT_THIS_FILE}")"
else
  _FWBOT_SRC="${_FWBOT_THIS_FILE}"
fi
_FWBOT_DIR="$(cd -- "$(dirname -- "${_FWBOT_SRC}")" >/dev/null 2>&1 && pwd)"
# scripts/cmdwatcher/profile.sh -> repo root is two levels up
_FWBOT_REPO_ROOT="$(cd -- "${_FWBOT_DIR}/../../" && pwd)"

FIREWALLBOT_LOG_DIR="${FIREWALLBOT_LOG_DIR:-${_FWBOT_REPO_ROOT}/log}"
mkdir -p -- "${FIREWALLBOT_LOG_DIR}" 2>/dev/null || true
_FWBOT_CMD_LOG_FILE="${FIREWALLBOT_CMD_LOG:-${FIREWALLBOT_LOG_DIR}/commands.jsonl}"

__FWBOT_LOGGING=0

fwbot__json_escape() {
  local s=${1//\/\\}
  local dq='"' escdq='\\"'
  s=${s//${dq}/${escdq}}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

fwbot__capture_last_command() {
  local current="$BASH_COMMAND"
  case "$current" in
    fwbot_log_last_command*|'') return ;;
  esac
  if fwbot__should_ignore_command "$current"; then
    return
  fi
  FWBOT_LAST_CMD="$current"
}

fwbot__should_ignore_command() {
  local cmd="$1"
  case "$cmd" in
    '. "$HOME/.cargo/env"'|\
    'source "$HOME/.cargo/env"'|\
    '. $HOME/.cargo/env'|\
    'source $HOME/.cargo/env')
      return 0 ;;
  esac
  return 1
}

# Emit one-time session_start when a new interactive shell begins
fwbot__maybe_session_start() {
  if [[ -n "${FIREWALLBOT_SESSION_STARTED:-}" ]]; then
    return 0
  fi
  # Generate a lightweight session id and export it so subshells inherit
  local rnd ts
  ts=$(date -u +%s)
  rnd=$(( (RANDOM<<16) ^ RANDOM ))
  export FIREWALLBOT_SESSION_ID="${ts}-${PPID:-0}-${rnd}"
  export FIREWALLBOT_SESSION_STARTED=1

  local epoch_iso user uid gid cwd host tty ip port tz_offset tz_name tz_json
  epoch_iso=$(date -u -Iseconds | sed 's/+00:00/Z/')
  tz_offset=$(date +%z)
  tz_name=$(date +%Z)
  tz_json=$(fwbot__json_escape "$tz_name")
  user=${USER:-$(id -un)}
  uid=${UID:-$(id -u)}
  gid=${GID:-$(id -g)}
  cwd=${PWD}
  host=$(hostname -s 2>/dev/null || hostname)
  tty=$(tty 2>/dev/null || echo "unknown")
  if [[ -n "$SSH_CONNECTION" ]]; then
    ip=$(awk '{print $1}' <<<"$SSH_CONNECTION"); port=$(awk '{print $2}' <<<"$SSH_CONNECTION")
  else
    ip="local"; port=""
  fi
  printf '{"type":"session_start","ts":"%s","tz_offset":"%s","tz_name":"%s","sid":"%s","user":"%s","uid":%s,"gid":%s,"ip":"%s","port":"%s","tty":"%s","cwd":"%s","ppid":%s,"pid":%s,"host":"%s"}\n' \
    "$epoch_iso" "$tz_offset" "$tz_json" "$FIREWALLBOT_SESSION_ID" "$user" "$uid" "$gid" "$ip" "$port" "$tty" "$cwd" "${PPID:-0}" "$$" "$host" >> "${_FWBOT_CMD_LOG_FILE}" 2>/dev/null || true
}

fwbot__log_session_stop() {
  local rc=$?
  if [[ -n "${FIREWALLBOT_SESSION_STOPPED:-}" ]]; then
    return 0
  fi
  export FIREWALLBOT_SESSION_STOPPED=1
  if [[ -z "${FIREWALLBOT_SESSION_ID:-}" ]]; then
    return 0
  fi

  local epoch_iso user uid gid cwd host tty ip port tz_offset tz_name tz_json
  epoch_iso=$(date -u -Iseconds | sed 's/+00:00/Z/')
  tz_offset=$(date +%z)
  tz_name=$(date +%Z)
  tz_json=$(fwbot__json_escape "$tz_name")
  user=${USER:-$(id -un)}
  uid=${UID:-$(id -u)}
  gid=${GID:-$(id -g)}
  cwd=${PWD}
  host=$(hostname -s 2>/dev/null || hostname)
  tty=$(tty 2>/dev/null || echo "unknown")
  if [[ -n "$SSH_CONNECTION" ]]; then
    ip=$(awk '{print $1}' <<<"$SSH_CONNECTION"); port=$(awk '{print $2}' <<<"$SSH_CONNECTION")
  else
    ip="local"; port=""
  fi

  printf '{"type":"session_stop","ts":"%s","tz_offset":"%s","tz_name":"%s","sid":"%s","user":"%s","uid":%s,"gid":%s,"ip":"%s","port":"%s","tty":"%s","cwd":"%s","rc":%s,"host":"%s"}\n' \
    "$epoch_iso" "$tz_offset" "$tz_json" "$FIREWALLBOT_SESSION_ID" "$user" "$uid" "$gid" "$ip" "$port" "$tty" "$cwd" "$rc" "$host" >> "${_FWBOT_CMD_LOG_FILE}" 2>/dev/null || true
}

fwbot__install_exit_trap() {
  local existing trap_body
  existing=$(trap -p EXIT 2>/dev/null)
  trap_body='fwbot__log_session_stop'
  if [[ -n "$existing" ]]; then
    existing=${existing#trap -- '}
    existing=${existing%' EXIT}
    if [[ "$existing" == *fwbot__log_session_stop* ]]; then
      return 0
    fi
    trap_body+="; ${existing}"
  fi
  trap "$trap_body" EXIT
}

fwbot_log_last_command() {
  local rc=$?
  [[ $__FWBOT_LOGGING -eq 1 ]] && return 0
  __FWBOT_LOGGING=1
  local cmd="${FWBOT_LAST_CMD:-}"
  if [[ -z "$cmd" ]]; then __FWBOT_LOGGING=0; return 0; fi

  case "$cmd" in
    fwbot_log_last_command*|history\ *|history) __FWBOT_LOGGING=0; return 0 ;;
  esac

  local epoch_iso user uid gid cwd host tty ip port tz_offset tz_name tz_json
  epoch_iso=$(date -u -Iseconds | sed 's/+00:00/Z/')
  tz_offset=$(date +%z)
  tz_name=$(date +%Z)
  tz_json=$(fwbot__json_escape "$tz_name")
  user=${USER:-$(id -un)}
  uid=${UID:-$(id -u)}
  gid=${GID:-$(id -g)}
  cwd=${PWD}
  host=$(hostname -s 2>/dev/null || hostname)
  tty=$(tty 2>/dev/null || echo "unknown")
  if [[ -n "$SSH_CONNECTION" ]]; then
    ip=$(awk '{print $1}' <<<"$SSH_CONNECTION"); port=$(awk '{print $2}' <<<"$SSH_CONNECTION")
  else
    ip="local"; port=""
  fi
  local cmd_json; cmd_json=$(fwbot__json_escape "$cmd")
  if [[ -n "${FIREWALLBOT_SESSION_ID:-}" ]]; then
    printf '{"type":"exec","ts":"%s","tz_offset":"%s","tz_name":"%s","sid":"%s","user":"%s","uid":%s,"gid":%s,"ip":"%s","port":"%s","tty":"%s","cwd":"%s","rc":%s,"cmd":"%s","host":"%s"}\n' \
      "$epoch_iso" "$tz_offset" "$tz_json" "$FIREWALLBOT_SESSION_ID" "$user" "$uid" "$gid" "$ip" "$port" "$tty" "$cwd" "$rc" "$cmd_json" "$host" >> "${_FWBOT_CMD_LOG_FILE}" 2>/dev/null || true
  else
    printf '{"type":"exec","ts":"%s","tz_offset":"%s","tz_name":"%s","user":"%s","uid":%s,"gid":%s,"ip":"%s","port":"%s","tty":"%s","cwd":"%s","rc":%s,"cmd":"%s","host":"%s"}\n' \
      "$epoch_iso" "$tz_offset" "$tz_json" "$user" "$uid" "$gid" "$ip" "$port" "$tty" "$cwd" "$rc" "$cmd_json" "$host" >> "${_FWBOT_CMD_LOG_FILE}" 2>/dev/null || true
  fi
  FWBOT_LAST_CMD=''
  __FWBOT_LOGGING=0
}

trap 'fwbot__capture_last_command' DEBUG
if [[ -n "$PROMPT_COMMAND" ]]; then
  case ";$PROMPT_COMMAND;" in
    *";fwbot_log_last_command;"*) ;;
    *) PROMPT_COMMAND="fwbot_log_last_command; ${PROMPT_COMMAND}" ;;
  esac
else
  PROMPT_COMMAND="fwbot_log_last_command"
fi

# Trigger session_start once per interactive shell
fwbot__maybe_session_start
fwbot__install_exit_trap

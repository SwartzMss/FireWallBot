#!/usr/bin/env bash
# FireWallBot systemd manager
# Usage:
#   bash ./service.sh install [unit ...|all]
#   bash ./service.sh status  [unit ...|all]
#   bash ./service.sh uninstall [unit ...|all]
#   bash ./service.sh list
#
# Units are discovered from systemd/*.service in this repo. If no unit is
# specified, the command applies to all discovered units.

set -euo pipefail

THIS_FILE="${BASH_SOURCE[0]}"
REPO_ROOT="$(cd -- "$(dirname -- "${THIS_FILE}")" >/dev/null 2>&1 && pwd)"
UNIT_DIR_SRC="${REPO_ROOT}/systemd"
UNIT_DIR_DST="/etc/systemd/system"

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Please run as root (sudo)." >&2
    exit 1
  fi
}

discover_units() {
  shopt -s nullglob
  local files=("${UNIT_DIR_SRC}"/*.service)
  shopt -u nullglob
  local names=()
  for f in "${files[@]}"; do
    names+=("$(basename "$f")")
  done
  printf '%s\n' "${names[@]}"
}

resolve_units() {
  local -a args=("$@")
  if (( ${#args[@]} == 0 )) || [[ ${args[0]} == "all" ]]; then
    discover_units
    return 0
  fi
  for u in "${args[@]}"; do
    case "$u" in
      *.service) echo "$u" ;;
      *) echo "$u.service" ;;
    esac
  done
}

cmd_list() {
  local found=0
  while IFS= read -r u; do
    found=1
    echo "$u"
  done < <(discover_units)
  (( found )) || echo "(no .service templates in systemd/)"
}

cmd_install() {
  require_root
  local -a units
  mapfile -t units < <(resolve_units "$@")
  (( ${#units[@]} )) || { echo "No units to install"; exit 2; }
  for u in "${units[@]}"; do
    local src="${UNIT_DIR_SRC}/${u}"
    local dst="${UNIT_DIR_DST}/${u}"
    if [[ ! -f "$src" ]]; then
      echo "Template not found: $src" >&2; continue
    fi
    echo "Installing $u -> $dst"
    local tmp
    tmp=$(mktemp)
    sed "s#@REPO@#${REPO_ROOT}#g" "$src" >"$tmp"
    install -m 0644 "$tmp" "$dst"
    rm -f "$tmp"
    systemctl daemon-reload
    systemctl enable --now "$u"
  done
}

cmd_uninstall() {
  require_root
  local -a units
  mapfile -t units < <(resolve_units "$@")
  (( ${#units[@]} )) || { echo "No units to uninstall"; exit 2; }
  for u in "${units[@]}"; do
    local dst="${UNIT_DIR_DST}/${u}"
    echo "Uninstalling $u"
    systemctl disable --now "$u" 2>/dev/null || true
    rm -f "$dst" || true
  done
  systemctl daemon-reload
}

cmd_status() {
  local -a units
  mapfile -t units < <(resolve_units "$@")
  (( ${#units[@]} )) || { echo "No units to query"; exit 2; }
  for u in "${units[@]}"; do
    local active enabled unit_path
    unit_path="${UNIT_DIR_DST}/${u}"
    if systemctl list-unit-files | grep -q "^${u}\\s"; then
      enabled=$(systemctl is-enabled "$u" 2>/dev/null || echo "unknown")
    else
      enabled="not-installed"
    fi
    active=$(systemctl is-active "$u" 2>/dev/null || echo "inactive")
    printf '%-28s enabled=%-14s active=%s\n' "$u" "$enabled" "$active"
  done
}

usage() {
  cat <<EOF
Usage: $0 <install|status|uninstall|list> [unit ...|all]

Examples:
  sudo bash $0 install            # install all units under systemd/
  sudo bash $0 uninstall          # uninstall all units
  bash $0 status                  # show status for all units
  sudo bash $0 install firewallbot.service  # operate specific unit
EOF
}

main() {
  local sub=${1:-}
  shift || true
  case "$sub" in
    install)   cmd_install "$@" ;;
    uninstall) cmd_uninstall "$@" ;;
    status)    cmd_status "$@" ;;
    list)      cmd_list ;; 
    -h|--help|help|"") usage ;;
    *) echo "Unknown subcommand: $sub" >&2; usage; exit 2 ;;
  esac
}

main "$@"


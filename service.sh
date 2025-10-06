#!/usr/bin/env bash
# FireWallBot systemd manager
# Usage:
#   bash ./service.sh install [module ...|all]
#   bash ./service.sh status  [module ...|all]
#   bash ./service.sh uninstall [module ...|all]
#   bash ./service.sh list
#
# Modules live under scripts/<ModuleName>/ with a <ModuleName>.service.tmpl.
# Installed unit name will be firewallbot-<modulename-lower>.service

set -euo pipefail

THIS_FILE="${BASH_SOURCE[0]}"
REPO_ROOT="$(cd -- "$(dirname -- "${THIS_FILE}")" >/dev/null 2>&1 && pwd)"
MODULES_DIR="${REPO_ROOT}/scripts"
UNIT_DIR_DST="/etc/systemd/system"

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Please run as root (sudo)." >&2
    exit 1
  fi
}

discover_modules() {
  shopt -s nullglob
  local files=("${MODULES_DIR}"/*/*.service.tmpl)
  shopt -u nullglob
  local names=()
  local f
  for f in "${files[@]}"; do
    local d
    d=$(basename "$(dirname "$f")")
    names+=("${d}")
  done
  printf '%s\n' "${names[@]}" | sort -u
}

resolve_modules() {
  local -a args=("$@")
  if (( ${#args[@]} == 0 )) || [[ ${args[0]} == "all" ]]; then
    discover_modules
    return 0
  fi
  printf '%s\n' "${args[@]}"
}

module_template() {
  local mod="$1"
  echo "${MODULES_DIR}/${mod}/${mod}.service.tmpl"
}

module_unit_name() {
  local mod="$1"
  local lower
  lower=$(echo "$mod" | tr '[:upper:]' '[:lower:]')
  echo "firewallbot-${lower}.service"
}

cmd_list() {
  local found=0
  while IFS= read -r m; do
    found=1
    echo "$m"
  done < <(discover_modules)
  (( found )) || echo "(no modules under scripts/* with .service.tmpl)"
}

cmd_install() {
  require_root
  local -a mods
  mapfile -t mods < <(resolve_modules "$@")
  (( ${#mods[@]} )) || { echo "No modules to install"; exit 2; }
  for m in "${mods[@]}"; do
    local src dst unit
    unit=$(module_unit_name "$m")
    src=$(module_template "$m")
    dst="${UNIT_DIR_DST}/${unit}"
    if [[ ! -f "$src" ]]; then
      echo "Template not found: $src" >&2; continue
    fi
    echo "Installing ${m} -> ${unit}"
    local tmp
    tmp=$(mktemp)
    sed "s#@REPO@#${REPO_ROOT}#g" "$src" >"$tmp"
    install -m 0644 "$tmp" "$dst"
    rm -f "$tmp"
    systemctl daemon-reload
    systemctl enable --now "$unit"
  done
}

cmd_uninstall() {
  require_root
  local -a mods
  mapfile -t mods < <(resolve_modules "$@")
  (( ${#mods[@]} )) || { echo "No modules to uninstall"; exit 2; }
  for m in "${mods[@]}"; do
    local unit dst
    unit=$(module_unit_name "$m")
    dst="${UNIT_DIR_DST}/${unit}"
    echo "Uninstalling ${m} (${unit})"
    systemctl disable --now "$unit" 2>/dev/null || true
    rm -f "$dst" || true
  done
  systemctl daemon-reload
}

cmd_status() {
  local -a mods
  mapfile -t mods < <(resolve_modules "$@")
  (( ${#mods[@]} )) || { echo "No modules to query"; exit 2; }
  for m in "${mods[@]}"; do
    local active enabled unit u
    u=$(module_unit_name "$m")
    if systemctl list-unit-files | grep -q "^${u}\\s"; then
      enabled=$(systemctl is-enabled "$u" 2>/dev/null || echo "unknown")
    else
      enabled="not-installed"
    fi
    active=$(systemctl is-active "$u" 2>/dev/null || echo "inactive")
    printf '%-18s unit=%-30s enabled=%-14s active=%s\n' "$m" "$u" "$enabled" "$active"
  done
}

usage() {
  cat <<EOF
Usage: $0 <install|status|uninstall|list> [module ...|all]

Examples:
  sudo bash $0 install            # install all modules under scripts/
  sudo bash $0 uninstall          # uninstall all units
  bash $0 status                  # show status for all units
  sudo bash $0 install LoginWatcher         # operate specific module
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

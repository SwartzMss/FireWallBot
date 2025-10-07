#!/usr/bin/env bash
# FireWallBot systemd manager
# Usage:
#   bash ./service.sh install [module ...|all]
#   bash ./service.sh status  [module ...|all]
#   bash ./service.sh uninstall [module ...|all]
#   bash ./service.sh list
#
# Modules live under scripts/<module>/
# - Service module: <module>.service.tmpl -> installs firewallbot-<module>.service
# - Profile module: profile.sh -> installs /etc/profile.d/99-firewallbot-<module>.sh

set -euo pipefail

if [[ -t 1 ]]; then
  COLOR_RED=$'\033[31m'
  COLOR_GREEN=$'\033[32m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_BLUE=$'\033[34m'
  COLOR_MAGENTA=$'\033[35m'
  COLOR_CYAN=$'\033[36m'
  COLOR_RESET=$'\033[0m'
else
  COLOR_RED=''
  COLOR_GREEN=''
  COLOR_YELLOW=''
  COLOR_BLUE=''
  COLOR_MAGENTA=''
  COLOR_CYAN=''
  COLOR_RESET=''
fi

log_color() {
  local color="$1"; shift
  printf '%b%s%b\n' "${color}" "$*" "${COLOR_RESET}"
}

log_step() { log_color "${COLOR_CYAN}" "[STEP] $*"; }
log_info() { log_color "${COLOR_BLUE}" "[INFO] $*"; }
log_warn() { log_color "${COLOR_YELLOW}" "[WARN] $*" 1>&2; }
log_ok() { log_color "${COLOR_GREEN}" "[ OK ] $*"; }
log_error() { log_color "${COLOR_RED}" "[FAIL] $*" 1>&2; }

run_with_proxy() {
  local -a env_args=()
  if [[ -n ${http_proxy:-} ]]; then
    log_info "检测到 http_proxy=${http_proxy}"
    env_args+=("http_proxy=${http_proxy}" "HTTP_PROXY=${http_proxy}")
  fi
  if [[ -n ${https_proxy:-} ]]; then
    log_info "检测到 https_proxy=${https_proxy}"
    env_args+=("https_proxy=${https_proxy}" "HTTPS_PROXY=${https_proxy}")
  fi
  env "${env_args[@]}" "$@"
}

THIS_FILE="${BASH_SOURCE[0]}"
REPO_ROOT="$(cd -- "$(dirname -- "${THIS_FILE}")" >/dev/null 2>&1 && pwd)"
MODULES_DIR="${REPO_ROOT}/scripts"
UNIT_DIR_DST="/etc/systemd/system"

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    log_error "需要 root 权限，请使用 sudo 执行。"
    exit 1
  fi
}

discover_modules() {
  shopt -s nullglob
  local services=("${MODULES_DIR}"/*/*.service.tmpl)
  local profiles=("${MODULES_DIR}"/*/profile.sh)
  shopt -u nullglob
  local names=()
  local f d
  for f in "${services[@]}"; do d=$(basename "$(dirname "$f")"); names+=("${d}"); done
  for f in "${profiles[@]}"; do d=$(basename "$(dirname "$f")"); names+=("${d}"); done
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

module_requirements_file() {
  local mod="$1"
  echo "${MODULES_DIR}/${mod}/requirements.txt"
}

module_virtualenv_path() {
  local mod="$1"
  local lower
  lower=$(echo "$mod" | tr '[:upper:]' '[:lower:]')
  echo "${REPO_ROOT}/.venv/${lower}"
}

install_module_dependencies() {
  local mod="$1"
  local req venv pip_bin
  req=$(module_requirements_file "$mod")
  if [[ -f "$req" ]]; then
    log_step "安装 ${mod} 依赖 (${req})"
    if ! command -v python3 >/dev/null 2>&1; then
      log_warn "系统未找到 python3，跳过 ${mod} 的依赖安装"
      return
    fi
    venv=$(module_virtualenv_path "$mod")
    if ! python3 -m venv --help >/dev/null 2>&1; then
      log_error "缺少 python3-venv 模块，请先安装 python3-venv"
      exit 1
    fi
    if [[ ! -d "$venv" ]]; then
      log_step "创建虚拟环境 ${venv}"
      python3 -m venv "$venv"
    fi
    pip_bin="${venv}/bin/pip"
    if [[ ! -x "$pip_bin" ]]; then
      log_error "虚拟环境缺少 pip: ${pip_bin}"
      exit 1
    fi
    log_info "升级虚拟环境基础包"
    run_with_proxy "$pip_bin" install --upgrade pip setuptools wheel >/dev/null
    log_info "安装 ${mod} 依赖集合"
    run_with_proxy "$pip_bin" install --upgrade -r "$req"
  fi
}

check_service_status() {
  local unit="$1"
  if systemctl is-active --quiet "$unit"; then
    log_ok "服务 ${unit} 已启动"
  else
    log_error "服务 ${unit} 未处于运行状态"
    systemctl status "$unit" --no-pager --lines 15 || true
  fi
}

module_profile_src() {
  local mod="$1"
  echo "${MODULES_DIR}/${mod}/profile.sh"
}

module_type() {
  local mod="$1"
  if [[ -f "$(module_template "$mod")" ]]; then
    echo service; return
  fi
  if [[ -f "$(module_profile_src "$mod")" ]]; then
    echo profile; return
  fi
  echo unknown
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
    case "$(module_type "$m")" in
      service)
        local src dst unit tmp
        unit=$(module_unit_name "$m")
        src=$(module_template "$m")
        dst="${UNIT_DIR_DST}/${unit}"
        log_step "部署 systemd 服务 ${m} -> ${unit}"
        install_module_dependencies "$m"
        tmp=$(mktemp)
        sed "s#@REPO@#${REPO_ROOT}#g" "$src" >"$tmp"
        install -m 0644 "$tmp" "$dst"
        rm -f "$tmp"
        log_info "刷新 systemd 守护进程"
        systemctl daemon-reload
        log_info "启用并启动 ${unit}"
        systemctl enable --now "$unit"
        check_service_status "$unit"
        ;;
      profile)
        local src dest ts lower
        src=$(module_profile_src "$m")
        lower=$(echo "$m" | tr '[:upper:]' '[:lower:]')
        dest="/etc/profile.d/99-firewallbot-${lower}.sh"
        log_step "部署 profile 模块 ${m} -> ${dest}"
        install_module_dependencies "$m"
        if [[ ! -f "$src" ]]; then
          log_warn "未找到 profile 源文件：$src"
          continue
        fi
        ts=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
        cat >"$dest" <<EOF
#!/usr/bin/env bash
# FireWallBot profile hook (module: ${m})
# Generated by service.sh at ${ts}
# This file sources the module script from the repository; do not edit.
REPO_DIR="${REPO_ROOT}"
SRC="\${REPO_DIR}/scripts/${m}/profile.sh"
if [[ -f "\${SRC}" ]]; then
  # shellcheck disable=SC1090
  . "\${SRC}"
else
  echo "[FireWallBot:${m}] profile source missing: \${SRC}" >&2
fi
EOF
        chmod 0644 "$dest"
        # Also install hook for non-login interactive shells (GUI terminals)
        local bashrcd="/etc/bash.bashrc.d"
        local dest_brcd="${bashrcd}/99-firewallbot-${lower}.sh"
        if [[ -d "$bashrcd" ]] || grep -q "bashrc\.d" /etc/bash.bashrc 2>/dev/null; then
          mkdir -p "$bashrcd" 2>/dev/null || true
          cat >"$dest_brcd" <<EOF
#!/usr/bin/env bash
# FireWallBot bashrc.d hook (module: ${m})
# Generated by service.sh at ${ts}
# This file sources the module script from the repository; do not edit.
REPO_DIR="${REPO_ROOT}"
SRC="\${REPO_DIR}/scripts/${m}/profile.sh"
if [[ -f "\${SRC}" ]]; then
  # shellcheck disable=SC1090
  . "\${SRC}"
fi
EOF
          chmod 0644 "$dest_brcd"
          log_ok "已安装 bashrc.d 钩子：$dest_brcd"
        else
          # Append an annotated block into /etc/bash.bashrc
          local bashrc="/etc/bash.bashrc"
          local marker_begin="# >>> FireWallBot:${m} >>>"
          local marker_end="# <<< FireWallBot:${m} <<<"
          if ! grep -q "$marker_begin" "$bashrc" 2>/dev/null; then
            cat >>"$bashrc" <<EOF

${marker_begin}
# Generated by FireWallBot service.sh at ${ts}
REPO_DIR="${REPO_ROOT}"
SRC="\${REPO_DIR}/scripts/${m}/profile.sh"
if [[ -f "\${SRC}" ]]; then
  # shellcheck disable=SC1090
  . "\${SRC}"
fi
${marker_end}
EOF
            log_ok "已向 ${bashrc} 追加 ${m} 钩子"
          else
            log_info "检测到 ${bashrc} 已存在 ${m} 钩子，跳过"
          fi
        fi
        # Detection and hints
        if grep -q "/etc/profile.d" /etc/profile 2>/dev/null; then
          log_info "登录 Shell 会自动加载 /etc/profile.d/*.sh"
        else
          log_warn "/etc/profile 似乎未加载 /etc/profile.d，需手动确认"
        fi
        if [[ -f /etc/bash.bashrc ]]; then
          log_info "非登录 Shell 通常不加载 /etc/profile.d，可使用 bash -l 测试"
        fi
        ;;
      *) echo "Skipping unknown module: $m" ;;
    esac
  done
}

cmd_uninstall() {
  require_root
  local -a mods
  mapfile -t mods < <(resolve_modules "$@")
  (( ${#mods[@]} )) || { echo "No modules to uninstall"; exit 2; }
  for m in "${mods[@]}"; do
    case "$(module_type "$m")" in
      service)
        local unit dst
        unit=$(module_unit_name "$m")
        dst="${UNIT_DIR_DST}/${unit}"
        log_step "卸载 systemd 服务 ${m} (${unit})"
        systemctl disable --now "$unit" 2>/dev/null || true
        rm -f "$dst" || true
        ;;
      profile)
        local lower dest dest_brcd bashrc marker_begin marker_end
        lower=$(echo "$m" | tr '[:upper:]' '[:lower:]')
        dest="/etc/profile.d/99-firewallbot-${lower}.sh"
        dest_brcd="/etc/bash.bashrc.d/99-firewallbot-${lower}.sh"
        log_step "移除 profile 模块 ${m}"
        rm -f "$dest" "$dest_brcd" || true
        bashrc="/etc/bash.bashrc"
        marker_begin="# >>> FireWallBot:${m} >>>"
        marker_end="# <<< FireWallBot:${m} <<<"
        if [[ -f "$bashrc" ]] && grep -q "$marker_begin" "$bashrc"; then
          # Delete the annotated block
          sed -i "/$marker_begin/,/$marker_end/d" "$bashrc" || true
          log_ok "已移除 ${bashrc} 中的 ${m} 钩子"
        fi
        ;;
      *) echo "Skipping unknown module: $m" ;;
    esac
  done
  systemctl daemon-reload
}

cmd_status() {
  local -a mods
  mapfile -t mods < <(resolve_modules "$@")
  (( ${#mods[@]} )) || { echo "No modules to query"; exit 2; }
  for m in "${mods[@]}"; do
    case "$(module_type "$m")" in
      service)
        local u unit_path enabled active
        local enabled_rc=0 active_rc=0
        local enabled_out="" active_out=""
        u=$(module_unit_name "$m")
        unit_path="${UNIT_DIR_DST}/${u}"
        enabled="not-installed"
        active="not-installed"
        if command -v systemctl >/dev/null 2>&1; then
          enabled_out=$(systemctl is-enabled "$u" 2>/dev/null) || enabled_rc=$?
          if [[ -n "$enabled_out" ]]; then
            enabled="$enabled_out"
          else
            case "$enabled_rc" in
              0) enabled="enabled" ;;
              1) if [[ -e "$unit_path" ]]; then enabled="disabled"; else enabled="not-installed"; fi ;;
              3) enabled="static" ;;
              4) enabled="not-installed" ;;
              5) enabled="masked" ;;
              *) if [[ -e "$unit_path" ]]; then enabled="installed"; else enabled="not-installed"; fi ;;
            esac
          fi
          active_out=$(systemctl is-active "$u" 2>/dev/null) || active_rc=$?
          if [[ -n "$active_out" ]]; then
            active="$active_out"
          else
            case "$active_rc" in
              0) active="active" ;;
              3) active="inactive" ;;
              4) active="not-installed" ;;
              *) if [[ -e "$unit_path" ]]; then active="unknown"; else active="not-installed"; fi ;;
            esac
          fi
        else
          if [[ -e "$unit_path" ]]; then
            enabled="installed"
            active="unknown"
          fi
        fi
        printf '%-18s kind=service unit=%-30s enabled=%-14s active=%s\n' "$m" "$u" "$enabled" "$active"
        ;;
      profile)
        local dest state
        dest="/etc/profile.d/99-firewallbot-$(echo "$m" | tr '[:upper:]' '[:lower:]').sh"
        if [[ -e "$dest" || -L "$dest" ]]; then state="installed"; else state="not-installed"; fi
        printf '%-18s kind=profile path=%-44s state=%s\n' "$m" "$dest" "$state"
        ;;
      *) printf '%-18s kind=unknown\n' "$m" ;;
    esac
  done
}

usage() {
  cat <<EOF
Usage: $0 <install|status|uninstall|list> [module ...|all]

Examples:
  sudo bash $0 install            # install all modules under scripts/
  sudo bash $0 uninstall          # uninstall all units
  bash $0 status                  # show status for all units
  sudo bash $0 install cmdwatcher           # operate specific module
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

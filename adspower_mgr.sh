#!/usr/bin/env bash

# AdsPower Global 管理脚本 v5.0 - 稳健重构版（单文件）

set -Eeuo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
if [[ "$SCRIPT_PATH" == /dev/fd/* || "$SCRIPT_PATH" == /proc/*/fd/* || "$SCRIPT_DIR" == /proc/* ]]; then
  # For process substitution (bash <(curl ...)), avoid writing under ephemeral /proc paths.
  SCRIPT_DIR="${PWD:-$HOME}"
  SCRIPT_PATH="${SCRIPT_DIR}/adspower_mgr.sh"
fi
ADS_MGR_SHORTCUT_NAME="${ADS_MGR_SHORTCUT_NAME:-ads}"
ADS_MGR_SHORTCUT_PATH="${ADS_MGR_SHORTCUT_PATH:-/usr/local/bin/${ADS_MGR_SHORTCUT_NAME}}"

ADSPOWER_INSTALL_PREFIX="${ADSPOWER_INSTALL_PREFIX:-/opt}"
ADSPOWER_EXEC="${ADSPOWER_EXEC:-${ADSPOWER_INSTALL_PREFIX}/AdsPower Global/adspower_global}"
CONFIG_FILE="${ADSPOWER_CONFIG_FILE:-$SCRIPT_DIR/adspower.env}"
SERVICE_FILE="${ADSPOWER_SERVICE_FILE:-/etc/systemd/system/adspower.service}"
PATCH_DIR="${ADSPOWER_PATCH_DIR:-$SCRIPT_DIR/patches}"
PATCH_LIST="${ADSPOWER_PATCH_LIST:-$SCRIPT_DIR/patches.list}"
ACTIVE_PATCH_FILE="${ADSPOWER_ACTIVE_PATCH_FILE:-$SCRIPT_DIR/.active_patch}"
TARGET_JS="${ADSPOWER_TARGET_JS:-$HOME/.config/adspower_global/cwd_global/lib/main.min.js}"
ADSPOWER_DEFAULT_VERSION="${ADSPOWER_DEFAULT_VERSION:-7.12.29}"
ADSPOWER_DEB_BASE="${ADSPOWER_DEB_BASE:-https://version.adspower.net/software/linux-x64-global}"
ADSPOWER_DEB_PATH="${ADSPOWER_DEB_PATH:-}"
ADSPOWER_BIN_LINK_DIR="${ADSPOWER_BIN_LINK_DIR:-/usr/local/bin}"
ADSPOWER_BIN_LINK_NAME="${ADSPOWER_BIN_LINK_NAME:-adspower_global}"
ADSPOWER_MAIN_MIN_JS_URL="${ADSPOWER_MAIN_MIN_JS_URL:-https://version.adspower.net/software/lib_production/v2.8.4.5_main.min.js72fe93ad5adf15026d67f1c2e4137378}"
ADSPOWER_MAIN_MIN_JS_DEST="${ADSPOWER_MAIN_MIN_JS_DEST:-${ADSPOWER_INSTALL_PREFIX}/AdsPower Global/adspower_global/cwd_global/lib/main.min.js}"
ADSPOWER_SYNC_MAIN_MIN_JS_ON_INSTALL="${ADSPOWER_SYNC_MAIN_MIN_JS_ON_INSTALL:-1}"
KEJILION_BOOTSTRAP_URL="${KEJILION_BOOTSTRAP_URL:-https://kejilion.sh}"
SKILLHUB_INSTALL_SCRIPT_URL="${SKILLHUB_INSTALL_SCRIPT_URL:-https://skillhub-1388575217.cos.ap-guangzhou.myqcloud.com/install/install.sh}"
SKILLHUB_DEFAULT_SKILL="${SKILLHUB_DEFAULT_SKILL:-adspower-browser}"
OPENCODE_INSTALL_URL="${OPENCODE_INSTALL_URL:-https://opencode.ai/install}"
OPENCODE_CONFIG_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
OPENCODE_CONFIG_FILE="${OPENCODE_CONFIG_FILE:-$OPENCODE_CONFIG_DIR/opencode.json}"
OPENCODE_BIN_LINK="${OPENCODE_BIN_LINK:-/usr/local/bin/opencode}"
PATCH_AUTO_UPDATE_ON_START="${PATCH_AUTO_UPDATE_ON_START:-1}"
PATCH_DOWNLOAD_TIMEOUT="${PATCH_DOWNLOAD_TIMEOUT:-20}"
PATCH_DOWNLOAD_RETRIES="${PATCH_DOWNLOAD_RETRIES:-2}"
PATCH_RETRY_DELAY="${PATCH_RETRY_DELAY:-2}"

if [[ -d "/root/.config/adspower_global/cwd_global" ]]; then
  KERNEL_ROOT="${ADSPOWER_KERNEL_ROOT:-/root/.config/adspower_global/cwd_global}"
else
  KERNEL_ROOT="${ADSPOWER_KERNEL_ROOT:-$HOME/.config/adspower_global/cwd_global}"
fi

API_KEY=""
API_PORT=50325
TMP_DIRS=()

mkdir -p "$PATCH_DIR"

on_error() {
  local exit_code=$?
  echo -e "${RED}[ERROR]${NC} 第 ${BASH_LINENO[0]} 行执行失败：${BASH_COMMAND} (exit=${exit_code})"
}
trap on_error ERR

cleanup_tmp_dirs() {
  local d
  for d in "${TMP_DIRS[@]}"; do
    [[ -n "$d" && -d "$d" ]] && rm -rf "$d" 2>/dev/null || true
  done
}
trap cleanup_tmp_dirs EXIT

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }

ensure_ads_shortcut() {
  local target="$SCRIPT_PATH"
  local shortcut_path="$ADS_MGR_SHORTCUT_PATH"
  local shortcut_dir

  # Skip shortcut creation for ephemeral paths (e.g. bash <(curl ...)).
  if [[ "$target" == /dev/fd/* || "$target" == /proc/*/fd/* ]]; then
    return 0
  fi
  [[ -f "$target" ]] || return 0

  # Guard against invalid runtime-injected paths (e.g. /proc/* from ephemeral shells).
  if [[ -z "$shortcut_path" ]]; then
    return 0
  fi
  if [[ "$shortcut_path" == /proc/* || "$shortcut_path" == /dev/fd/* ]]; then
    warn "检测到临时路径环境，已跳过快捷命令创建: $shortcut_path"
    return 0
  fi

  shortcut_dir="$(dirname "$shortcut_path")"
  if [[ "$shortcut_dir" == /proc/* || "$shortcut_dir" == /dev/fd/* ]]; then
    warn "检测到临时目录环境，已跳过快捷命令创建: $shortcut_dir"
    return 0
  fi

  mkdir -p "$shortcut_dir"
  chmod +x "$target" 2>/dev/null || true

  local current_target=""
  if [[ -e "$shortcut_path" || -L "$shortcut_path" ]]; then
    current_target="$(readlink -f "$shortcut_path" 2>/dev/null || true)"
    if [[ "$current_target" == "$target" ]]; then
      return 0
    fi
  fi

  ln -sf "$target" "$shortcut_path"
  success "已启用快捷命令: ${ADS_MGR_SHORTCUT_NAME} -> ${target}"
}

pause_any_key() {
  # Non-interactive context: skip pause to avoid read failures under set -e.
  if [[ ! -t 0 || ! -t 1 ]]; then
    return 0
  fi
  echo ""
  if ! read -r -n 1 -p "按任意键继续..." _; then
    echo ""
    return 0
  fi
  echo ""
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

is_valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( port >= 1 && port <= 65535 ))
}

is_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

is_yes() {
  local ans="${1,,}"
  [[ "$ans" == "y" || "$ans" == "yes" ]]
}

confirm_action() {
  local prompt="$1"
  local ans
  read -r -p "$prompt [y/N]: " ans
  is_yes "$ans"
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    error "缺少命令: $cmd"
    return 1
  }
}

download_to_file() {
  local url="$1"
  local out="$2"
  local timeout="${3:-$PATCH_DOWNLOAD_TIMEOUT}"
  local retries="${4:-$PATCH_DOWNLOAD_RETRIES}"
  local attempt=1

  while (( attempt <= retries )); do
    if command -v curl >/dev/null 2>&1; then
      if curl -fSL --connect-timeout "$timeout" --max-time "$timeout" --progress-bar -o "$out" "$url"; then
        return 0
      fi
    elif command -v wget >/dev/null 2>&1; then
      if wget -q --show-progress --timeout="$timeout" -O "$out" "$url"; then
        return 0
      fi
    else
      error "未找到 curl/wget，无法下载: $url"
      return 1
    fi

    warn "下载失败（第 ${attempt}/${retries} 次）: $url"
    if (( attempt < retries )); then
      sleep "$PATCH_RETRY_DELAY"
    fi
    ((attempt++))
  done

  return 1
}

make_temp_dir() {
  local d
  d="$(mktemp -d)"
  TMP_DIRS+=("$d")
  echo "$d"
}

ensure_bin_link() {
  local link_path="${ADSPOWER_BIN_LINK_DIR}/${ADSPOWER_BIN_LINK_NAME}"
  mkdir -p "$ADSPOWER_BIN_LINK_DIR"
  ln -sf "$ADSPOWER_EXEC" "$link_path"
  info "已创建命令软链接: ${link_path} -> ${ADSPOWER_EXEC}"
}

update_main_min_js_from_url() {
  local dest="${ADSPOWER_MAIN_MIN_JS_DEST}"
  local dest_dir
  dest_dir="$(dirname "$dest")"
  local tmp_file
  tmp_file="$(mktemp /tmp/main.min.js.XXXXXX)"

  if [[ ! -d "$dest_dir" ]]; then
    warn "目标目录不存在，跳过 main.min.js 更新: $dest_dir"
    rm -f "$tmp_file" 2>/dev/null || true
    return 1
  fi

  info "正在同步 main.min.js: ${ADSPOWER_MAIN_MIN_JS_URL}"
  if ! download_to_file "$ADSPOWER_MAIN_MIN_JS_URL" "$tmp_file" "$PATCH_DOWNLOAD_TIMEOUT" "$PATCH_DOWNLOAD_RETRIES"; then
    warn "main.min.js 下载失败，跳过替换。"
    rm -f "$tmp_file" 2>/dev/null || true
    return 1
  fi

  if [[ ! -s "$tmp_file" ]]; then
    warn "main.min.js 文件为空，跳过替换。"
    rm -f "$tmp_file" 2>/dev/null || true
    return 1
  fi

  [[ -f "$dest" ]] && cp "$dest" "${dest}.bak" 2>/dev/null || true
  if cp "$tmp_file" "$dest"; then
    success "main.min.js 已更新: $dest"
    rm -f "$tmp_file" 2>/dev/null || true
    return 0
  fi

  warn "main.min.js 替换失败，尝试回滚。"
  [[ -f "${dest}.bak" ]] && cp "${dest}.bak" "$dest" 2>/dev/null || true
  rm -f "$tmp_file" 2>/dev/null || true
  return 1
}

install_adspower_from_deb() {
  local deb_file="$1"
  [[ -f "$deb_file" ]] || {
    error "未找到 .deb 安装包: $deb_file"
    return 1
  }

  info "正在安装 AdsPower 包: $deb_file"
  if command -v dpkg >/dev/null 2>&1 && is_debian_like; then
    if ! dpkg -i "$deb_file"; then
      warn "dpkg 安装失败，尝试修复依赖后重试..."
      apt-get -f install -y
      dpkg -i "$deb_file"
    fi
  else
    local ext_dir
    ext_dir="$(make_temp_dir)"
    if command -v ar >/dev/null 2>&1; then
      (cd "$ext_dir" && ar x "$deb_file")
      if [[ -f "$ext_dir/data.tar.xz" ]]; then
        tar -xJf "$ext_dir/data.tar.xz" -C /
      elif [[ -f "$ext_dir/data.tar.gz" ]]; then
        tar -xzf "$ext_dir/data.tar.gz" -C /
      elif [[ -f "$ext_dir/data.tar" ]]; then
        tar -xf "$ext_dir/data.tar" -C /
      else
        error "无法识别 .deb 数据内容（data.tar.* 缺失）。"
        return 1
      fi
    elif command -v dpkg-deb >/dev/null 2>&1; then
      dpkg-deb -x "$deb_file" /
    else
      error "缺少 ar 或 dpkg-deb，无法解包安装 .deb。"
      return 1
    fi
  fi

  [[ -f "$ADSPOWER_EXEC" ]] || {
    error "安装完成但未找到可执行文件: $ADSPOWER_EXEC"
    return 1
  }
  chmod +x "$ADSPOWER_EXEC"
  ensure_bin_link

  if [[ "$ADSPOWER_SYNC_MAIN_MIN_JS_ON_INSTALL" == "1" ]]; then
    update_main_min_js_from_url || true
  fi

  success "AdsPower 安装完成。"
  return 0
}

is_adspower_running() {
  pgrep -f "[a]dspower_global" >/dev/null 2>&1
}

is_port_listening() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lnt "( sport = :$port )" 2>/dev/null | grep -q ":$port"
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | grep -q ":$port[[:space:]]"
    return $?
  fi
  return 1
}

get_api_raw_status() {
  curl -s --max-time 2 "http://127.0.0.1:${API_PORT}/status" 2>/dev/null || true
}

load_config() {
  API_KEY=""
  API_PORT=50325

  [[ -f "$CONFIG_FILE" ]] || return 0

  while IFS= read -r line; do
    line="$(trim "$line")"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

    case "$line" in
      API_KEY=*)
        local raw="${line#API_KEY=}"
        raw="${raw%\"}"
        raw="${raw#\"}"
        API_KEY="$raw"
        ;;
      API_PORT=*)
        local raw_port="${line#API_PORT=}"
        raw_port="$(trim "$raw_port")"
        if is_valid_port "$raw_port"; then
          API_PORT="$raw_port"
        else
          warn "配置文件中的 API_PORT 非法，使用默认端口 50325: $raw_port"
        fi
        ;;
    esac
  done < "$CONFIG_FILE"
}

save_config() {
  if ! is_valid_port "$API_PORT"; then
    error "端口非法，无法保存配置: $API_PORT"
    return 1
  fi

  umask 077
  cat > "$CONFIG_FILE" <<EOF
API_KEY="$API_KEY"
API_PORT=$API_PORT
EOF
  chmod 600 "$CONFIG_FILE"
  success "配置已保存: $CONFIG_FILE"
}

get_service_status() {
  if is_adspower_running; then
    echo -e "${GREEN}正在运行${NC}"
  else
    echo -e "${RED}已停止${NC}"
  fi
}

get_api_status() {
  local res
  res="$(get_api_raw_status)"
  if [[ "$res" == *"success"* ]]; then
    echo -e "${GREEN}在线${NC}"
  elif is_port_listening "$API_PORT"; then
    echo -e "${YELLOW}端口在线/API异常${NC}"
  else
    echo -e "${RED}离线${NC}"
  fi
}

get_patch_info() {
  if [[ ! -f "$TARGET_JS" ]]; then
    echo -e "${RED}未安装${NC}"
    return
  fi

  local v="已应用"
  [[ -f "$ACTIVE_PATCH_FILE" ]] && v="$(cat "$ACTIVE_PATCH_FILE")"
  echo -e "${GREEN}${v}${NC}"
}

get_autostart_info() {
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo -e "${RED}未配置${NC}"
    return
  fi

  if systemctl is-enabled adspower >/dev/null 2>&1; then
    echo -e "${GREEN}已开启${NC}"
  else
    echo -e "${YELLOW}已创建未启用${NC}"
  fi
}

get_resource_usage() {
  local cpu="N/A"
  local mem="N/A"

  if command -v top >/dev/null 2>&1; then
    cpu="$(top -bn1 2>/dev/null | awk -F',' '/Cpu\(s\)|%Cpu/{for(i=1;i<=NF;i++) if($i~/%?id/){gsub(/[^0-9.]/,"",$i); printf "%.1f", 100-$i; exit}}')"
    [[ -z "$cpu" ]] && cpu="N/A"
  fi

  if command -v free >/dev/null 2>&1; then
    mem="$(free 2>/dev/null | awk '/Mem:/ { if ($2 > 0) printf "%.1f", ($3/$2)*100; else print "N/A" }')"
    [[ -z "$mem" ]] && mem="N/A"
  fi

  echo -e "CPU ${CYAN}${cpu}%${NC} / MEM ${CYAN}${mem}%${NC}"
}

get_masked_key() {
  if [[ -z "$API_KEY" ]]; then
    echo -e "${RED}未设置${NC}"
    return
  fi

  local len=${#API_KEY}
  if (( len <= 8 )); then
    echo -e "${YELLOW}${API_KEY:0:1}****${API_KEY: -1}${NC}"
  else
    echo -e "${YELLOW}${API_KEY:0:4}****${API_KEY: -3}${NC}"
  fi
}

check_kernel_installed() {
  local v="$1"
  if [[ -d "$KERNEL_ROOT/chrome_$v" ]]; then
    echo -e "${GREEN}[已安装]${NC}"
  else
    echo -e "${RED}[未安装]${NC}"
  fi
}

ensure_default_patch_list() {
  if [[ -f "$PATCH_LIST" ]]; then
    return
  fi

  write_default_patch_list
}

write_default_patch_list() {
  cat > "$PATCH_LIST" <<EOF
v2.8.4.5|https://version.adspower.net/software/lib_production/v2.8.4.5_main.min.js72fe93ad5adf15026d67f1c2e4137378
v2.8.4.4|https://version.adspower.net/software/lib_production/v2.8.4.4_main.min.js11bff97aadb92fc16a9abd79e1939518
v2.8.4.3|https://version.adspower.net/software/lib_production/v2.8.4.3_main.min.js07075aa4da52fd3c9f297b01a103cacb
EOF
}

ensure_patch_list_healthy() {
  if [[ ! -f "$PATCH_LIST" || ! -s "$PATCH_LIST" ]]; then
    warn "补丁列表不存在或为空，已自动重建默认列表。"
    write_default_patch_list
  elif ! tr -d '\r' < "$PATCH_LIST" | grep -qE '^[^|]+\|https?://'; then
    warn "补丁列表格式异常，已恢复默认列表。"
    write_default_patch_list
  fi

  local required_entries=(
    "v2.8.4.5|https://version.adspower.net/software/lib_production/v2.8.4.5_main.min.js72fe93ad5adf15026d67f1c2e4137378"
    "v2.8.4.4|https://version.adspower.net/software/lib_production/v2.8.4.4_main.min.js11bff97aadb92fc16a9abd79e1939518"
    "v2.8.4.3|https://version.adspower.net/software/lib_production/v2.8.4.3_main.min.js07075aa4da52fd3c9f297b01a103cacb"
  )
  local entry ver
  for entry in "${required_entries[@]}"; do
    ver="${entry%%|*}"
    if ! tr -d '\r' < "$PATCH_LIST" | grep -q "^${ver}|"; then
      echo "$entry" >> "$PATCH_LIST"
      info "已补充默认补丁版本: $ver"
    fi
  done
}

prompt_api_key_if_needed() {
  if [[ -n "$API_KEY" ]]; then
    return 0
  fi

  if ! read -r -p "请输入 AdsPower API Key: " API_KEY; then
    API_KEY=""
    error "未读取到 API Key 输入。"
    return 1
  fi
  API_KEY="$(trim "$API_KEY")"
  if [[ -z "$API_KEY" ]]; then
    error "API Key 不能为空。"
    return 1
  fi
  return 0
}

wait_api_ready() {
  local timeout="${1:-20}"
  local i=0
  while (( i < timeout )); do
    local res
    res="$(get_api_raw_status)"
    [[ "$res" == *"success"* ]] && return 0
    sleep 1
    ((++i))
  done
  return 1
}

start_adspower() {
  load_config
  prompt_api_key_if_needed || return 1
  if ! ensure_adspower_runtime_ready; then
    if [[ -t 0 && -t 1 ]]; then
      if confirm_action "检测到运行依赖缺失，是否立即自动安装？"; then
        install_runtime_deps "0" || return 1
        ensure_adspower_runtime_ready || return 1
      else
        warn "已取消依赖安装，启动中止。"
        return 1
      fi
    else
      return 1
    fi
  fi
  auto_update_latest_patch_before_start

  if ! is_valid_port "$API_PORT"; then
    error "API 端口非法: $API_PORT"
    return 1
  fi

  if [[ ! -x "$ADSPOWER_EXEC" ]]; then
    if [[ -f "$ADSPOWER_EXEC" ]]; then
      chmod +x "$ADSPOWER_EXEC"
    else
      error "未找到 AdsPower 可执行文件: $ADSPOWER_EXEC"
      return 1
    fi
  fi
  ensure_bin_link || true

  if is_adspower_running; then
    info "AdsPower 进程已在运行，检查 API 状态..."
    if wait_api_ready 20; then
      success "API 已在线，无需重复启动。"
      return 0
    fi
    if is_port_listening "$API_PORT"; then
      warn "检测到端口已监听但 API 仍未就绪，额外等待 15 秒..."
      if wait_api_ready 15; then
        success "API 已恢复在线。"
        return 0
      fi
    fi
    warn "进程存在但 API 仍未响应，建议重启服务。"
    return 1
  fi

  require_cmd xvfb-run || return 1
  info "正在启动 AdsPower..."
  nohup xvfb-run -a "$ADSPOWER_EXEC" --headless=true --api-key="$API_KEY" --api-port="$API_PORT" --no-sandbox --disable-gpu >/tmp/adspower_mgr_start.log 2>&1 &

  if wait_api_ready 20; then
    success "AdsPower 启动成功，API 在线: 127.0.0.1:$API_PORT"
    return 0
  fi

  error "启动超时，API 未就绪。日志: /tmp/adspower_mgr_start.log"
  tail -n 20 /tmp/adspower_mgr_start.log 2>/dev/null || true
  return 1
}

stop_adspower() {
  info "正在停止 AdsPower..."
  systemctl stop adspower >/dev/null 2>&1 || true
  pkill -f "[a]dspower_global" >/dev/null 2>&1 || true
  pkill -f "xvfb-run.*adspower_global" >/dev/null 2>&1 || true

  local i=0
  while is_adspower_running && (( i < 10 )); do
    sleep 1
    ((++i))
  done

  if is_adspower_running; then
    warn "进程仍在运行，请手动检查: pgrep -af adspower_global"
  else
    success "服务已停止"
  fi
}

restart_adspower() {
  stop_adspower
  sleep 1
  start_adspower
}

write_systemd_service() {
  local esc_exec="$ADSPOWER_EXEC"
  local esc_key="$API_KEY"
  esc_exec="${esc_exec//\\/\\\\}"
  esc_exec="${esc_exec//\"/\\\"}"
  esc_key="${esc_key//\\/\\\\}"
  esc_key="${esc_key//\"/\\\"}"

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=AdsPower API
After=network.target

[Service]
Type=simple
User=root
Environment="DISPLAY=:99"
Environment="API_KEY=${esc_key}"
Environment="API_PORT=${API_PORT}"
ExecStart=/usr/bin/xvfb-run -a "${esc_exec}" --headless=true --api-key=\${API_KEY} --api-port=\${API_PORT} --no-sandbox --disable-gpu
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
}

toggle_autostart() {
  if [[ -f "$SERVICE_FILE" ]]; then
    info "正在关闭开机自启..."
    systemctl stop adspower >/dev/null 2>&1 || true
    systemctl disable adspower >/dev/null 2>&1 || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    success "已关闭开机自启并移除服务文件。"
    return 0
  fi

  load_config
  prompt_api_key_if_needed || return 1
  if ! is_valid_port "$API_PORT"; then
    error "端口非法，无法创建 systemd 服务: $API_PORT"
    return 1
  fi
  [[ -f "$ADSPOWER_EXEC" ]] || {
    error "未找到可执行文件: $ADSPOWER_EXEC"
    return 1
  }

  write_systemd_service
  systemctl daemon-reload
  systemctl enable adspower >/dev/null
  systemctl start adspower
  success "已开启开机自启。"
}

download_kernel_api() {
  local version="$1"
  load_config

  prompt_api_key_if_needed || return 1
  if ! is_valid_port "$API_PORT"; then
    error "API 端口非法: $API_PORT"
    return 1
  fi

  info "正在请求 Chrome $version ..."
  local url="http://127.0.0.1:${API_PORT}/api/v2/browser-profile/download-kernel"
  local json="{\"kernel_type\": \"Chrome\", \"kernel_version\": \"$version\"}"
  local res
  res="$(curl -s --location -g "$url" --header "Authorization: $API_KEY" --header "Content-Type: application/json" --data "$json")"

  if [[ "$res" != *"\"code\":0"* ]]; then
    error "请求失败: $res"
    return 1
  fi

  while true; do
    sleep 2
    local r s p
    r="$(curl -s --location -g "$url" --header "Authorization: $API_KEY" --header "Content-Type: application/json" --data "$json")"
    s="$(echo "$r" | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || true)"
    p="$(echo "$r" | grep -o '"progress":[0-9]*' | cut -d':' -f2 || true)"
    [[ -z "$p" ]] && p=0

    echo -ne "\r\033[K状态 [Chrome $version]: ${YELLOW}${s:-unknown} (${p}%)${NC}"

    if [[ "$s" == "completed" ]]; then
      echo -e "\r\033[K${GREEN}✅ Chrome $version 安装成功！${NC}"
      break
    fi
    if [[ -z "$s" ]]; then
      echo -e "\n${RED}API 无响应${NC}"
      return 1
    fi
  done
}

kernel_menu() {
  if [[ ! -f "$TARGET_JS" ]]; then
    error "请先应用补丁！"
    return
  fi

  while true; do
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "      AdsPower 内核管理 v5.0"
    echo -e "${GREEN}========================================${NC}"
    echo -e "内核根目录: ${CYAN}${KERNEL_ROOT}${NC}"
    echo "----------------------------------------"

    local vs=("145" "144" "143" "142" "141" "140" "139" "138" "137" "136")
    local i
    for i in "${!vs[@]}"; do
      echo -e "$((i + 1)). 下载 Chrome ${YELLOW}${vs[$i]}${NC} $(check_kernel_installed "${vs[$i]}")"
    done

    echo "11. 自定义版本号"
    echo "0. 返回主菜单"
    echo "----------------------------------------"

    local k_in
    if ! read -r -p "请输入选项 (支持多选 1,2): " k_in; then
      k_in=""
    fi
    [[ -z "$k_in" || "$k_in" == "0" ]] && return

    local sels
    sels="$(echo "$k_in" | tr ',' ' ')"
    for opt in $sels; do
      if ! is_number "$opt"; then
        warn "忽略无效选项: $opt"
        continue
      fi

      if (( opt >= 1 && opt <= 10 )); then
        download_kernel_api "${vs[$((opt - 1))]}"
      elif (( opt == 11 )); then
        local cv
        if ! read -r -p "版本号: " cv; then
          cv=""
        fi
        cv="$(trim "$cv")"
        [[ -n "$cv" ]] && download_kernel_api "$cv" || warn "版本号为空，已跳过。"
      else
        warn "超出范围的选项: $opt"
      fi
    done

    pause_any_key
  done
}

patch_add_url() {
  local url v tmp_file
  if ! read -r -p "地址: " url; then
    url=""
  fi
  url="$(trim "$url")"
  [[ "$url" =~ ^https?:// ]] || {
    error "补丁地址必须以 http:// 或 https:// 开头。"
    return 1
  }

  v="$(echo "$url" | sed -n 's/.*\/\(v[0-9.]*\)_main.*/\1/p')"
  if [[ -z "$v" ]]; then
    if ! read -r -p "版本 (例如 v2.8.4.4): " v; then
      v=""
    fi
    v="$(trim "$v")"
  fi
  [[ "$v" =~ ^v[0-9.]+$ ]] || {
    error "版本格式非法: $v"
    return 1
  }

  tmp_file="${PATCH_LIST}.tmp"
  touch "$PATCH_LIST"
  grep -v "^${v}|" "$PATCH_LIST" > "$tmp_file" || true
  echo "${v}|${url}" >> "$tmp_file"
  mv "$tmp_file" "$PATCH_LIST"

  if download_to_file "$url" "$PATCH_DIR/main.min.js.$v"; then
    success "补丁已添加并下载: $v"
  else
    warn "已添加补丁记录，但下载失败。可稍后重试应用。"
  fi
}

patch_update_latest_api() {
  local version_type="${1:-stable}"
  load_config
  prompt_api_key_if_needed || return 1

  if ! is_valid_port "$API_PORT"; then
    error "API 端口非法: $API_PORT"
    return 1
  fi

  if [[ "$version_type" != "stable" && "$version_type" != "beta" ]]; then
    error "版本类型非法: $version_type（仅支持 stable 或 beta）"
    return 1
  fi

  if ! is_adspower_running; then
    error "AdsPower 服务未运行，无法调用补丁更新接口。请先启动服务。"
    return 1
  fi

  local url payload res code msg
  url="http://127.0.0.1:${API_PORT}/api/v2/browser-profile/update-patch"
  payload="{\"version_type\":\"${version_type}\"}"

  info "正在调用官方补丁更新接口（${version_type}）..."
  res="$(curl -sS --max-time 30 --location -g "$url" \
    --header "Authorization: Bearer $API_KEY" \
    --header "Content-Type: application/json" \
    --data "$payload" 2>/dev/null || true)"

  if [[ -z "$res" ]]; then
    error "接口无响应: $url"
    return 1
  fi

  code="$(echo "$res" | grep -o '"code":[0-9-]*' | head -1 | cut -d':' -f2 || true)"
  msg="$(echo "$res" | sed -n 's/.*"msg":"\([^"]*\)".*/\1/p' | head -1 || true)"
  [[ -z "$msg" ]] && msg="unknown"

  if [[ "$code" == "0" ]]; then
    success "补丁更新任务提交成功（${version_type}）：${msg}"
    info "若当前有打开中的环境，服务端可能拒绝更新，请先关闭全部环境后重试。"
    return 0
  fi

  error "补丁更新失败（${version_type}）：${msg}"
  if [[ "$msg" == *"open"* || "$msg" == *"opened"* || "$msg" == *"running"* ]]; then
    warn "请先关闭所有已打开环境，再执行补丁更新。"
  fi
  return 1
}

patch_apply() {
  ensure_patch_list_healthy

  local entries=()
  while IFS='|' read -r v url; do
    v="${v//$'\r'/}"
    url="${url//$'\r'/}"
    [[ -z "$v" || -z "$url" ]] && continue
    entries+=("$v|$url")
  done < "$PATCH_LIST"

  if (( ${#entries[@]} == 0 )); then
    warn "未读取到有效补丁，已回退到默认列表。"
    write_default_patch_list
    while IFS='|' read -r v url; do
      v="${v//$'\r'/}"
      url="${url//$'\r'/}"
      [[ -z "$v" || -z "$url" ]] && continue
      entries+=("$v|$url")
    done < "$PATCH_LIST"
  fi

  if (( ${#entries[@]} == 0 )); then
    error "补丁列表为空。"
    return 1
  fi

  local i=1
  local item vshow
  for item in "${entries[@]}"; do
    vshow="${item%%|*}"
    echo "$i. $vshow"
    ((++i))
  done

  local p_c
  if ! read -r -p "编号 (0 返回): " p_c; then
    p_c=""
  fi
  [[ -z "$p_c" || "$p_c" == "0" ]] && return 0

  if ! is_number "$p_c" || (( p_c < 1 || p_c > ${#entries[@]} )); then
    error "编号无效: $p_c"
    return 1
  fi

  local sel vs us patch_file
  sel="${entries[$((p_c - 1))]}"
  vs="${sel%%|*}"
  us="${sel#*|}"
  patch_file="$PATCH_DIR/main.min.js.$vs"

  if [[ ! -f "$patch_file" ]]; then
    info "本地不存在补丁文件，正在下载..."
    download_to_file "$us" "$patch_file" || {
      error "下载失败，已取消应用。"
      return 1
    }
  fi

  mkdir -p "$(dirname "$TARGET_JS")"

  if [[ -f "$TARGET_JS" ]]; then
    cp "$TARGET_JS" "$TARGET_JS.bak"
  fi

  if cp "$patch_file" "$TARGET_JS"; then
    echo "$vs" > "$ACTIVE_PATCH_FILE"
    success "补丁已应用: $vs"
    restart_adspower || true
  else
    error "补丁替换失败。"
    if [[ -f "$TARGET_JS.bak" ]]; then
      cp "$TARGET_JS.bak" "$TARGET_JS" || true
      warn "已尝试回滚至备份文件。"
    fi
    return 1
  fi
}

patch_menu() {
  clear
  echo -e "${GREEN}补丁管理 v5.0${NC}"
  echo "1. 更新到稳定版补丁（stable，推荐）"
  echo "2. 更新到预览版补丁（beta）"
  echo "3. 应用本地补丁 (需重启)"
  echo "说明: stable 稳定性更高；beta 功能更新但可能不稳定。"
  echo "0. 返回主菜单"

  local o
  if ! read -r -p "选项: " o; then
    o=""
  fi
  case "$o" in
    "") return ;;
    1)
      if ! patch_update_latest_api "stable"; then
        warn "稳定版补丁更新未完成，请处理提示后重试。"
      fi
      ;;
    2)
      if ! patch_update_latest_api "beta"; then
        warn "预览版补丁更新未完成，请处理提示后重试。"
      fi
      ;;
    3)
      if ! patch_apply; then
        warn "本地补丁应用未完成，请检查后重试。"
      fi
      ;;
    0) return ;;
    *) warn "无效选项: $o" ;;
  esac
}

get_latest_patch_entry() {
  ensure_patch_list_healthy

  local lines=()
  while IFS='|' read -r v url; do
    v="${v//$'\r'/}"
    url="${url//$'\r'/}"
    [[ -z "$v" || -z "$url" ]] && continue
    [[ "$v" =~ ^v[0-9.]+$ ]] || continue
    [[ "$url" =~ ^https?:// ]] || continue
    lines+=("$v|$url")
  done < "$PATCH_LIST"

  (( ${#lines[@]} > 0 )) || return 1

  local latest_ver
  latest_ver="$(printf '%s\n' "${lines[@]}" | cut -d'|' -f1 | sort -V | tail -1)"
  [[ -n "$latest_ver" ]] || return 1

  local line
  for line in "${lines[@]}"; do
    if [[ "${line%%|*}" == "$latest_ver" ]]; then
      echo "$line"
      return 0
    fi
  done

  return 1
}

apply_patch_noninteractive() {
  local version="$1"
  local url="$2"
  local patch_file="$PATCH_DIR/main.min.js.$version"
  local tmp_file="${patch_file}.download"

  mkdir -p "$PATCH_DIR"

  info "正在拉取最新补丁: $version"
  if ! download_to_file "$url" "$tmp_file" "$PATCH_DOWNLOAD_TIMEOUT" "$PATCH_DOWNLOAD_RETRIES"; then
    warn "补丁拉取失败（网络异常或超时），将继续使用当前本地补丁。"
    rm -f "$tmp_file" 2>/dev/null || true
    return 1
  fi

  if [[ ! -s "$tmp_file" ]]; then
    warn "补丁文件为空，忽略本次更新。"
    rm -f "$tmp_file" 2>/dev/null || true
    return 1
  fi

  mv -f "$tmp_file" "$patch_file"
  mkdir -p "$(dirname "$TARGET_JS")"

  if [[ -f "$TARGET_JS" ]]; then
    cp "$TARGET_JS" "$TARGET_JS.bak" 2>/dev/null || true
  fi

  if cp "$patch_file" "$TARGET_JS"; then
    echo "$version" > "$ACTIVE_PATCH_FILE"
    success "已自动应用最新补丁: $version"
    return 0
  fi

  warn "补丁复制失败，尝试回滚。"
  if [[ -f "$TARGET_JS.bak" ]]; then
    cp "$TARGET_JS.bak" "$TARGET_JS" 2>/dev/null || true
  fi
  return 1
}

auto_update_latest_patch_before_start() {
  [[ "$PATCH_AUTO_UPDATE_ON_START" == "1" ]] || return 0

  local latest version url current
  if ! latest="$(get_latest_patch_entry)"; then
    warn "未找到可用补丁条目，跳过自动更新。"
    return 0
  fi

  version="${latest%%|*}"
  url="${latest#*|}"
  current=""
  [[ -f "$ACTIVE_PATCH_FILE" ]] && current="$(cat "$ACTIVE_PATCH_FILE" 2>/dev/null || true)"

  if [[ "$current" == "$version" && -f "$TARGET_JS" ]]; then
    info "当前已是最新补丁版本: $version"
    return 0
  fi

  apply_patch_noninteractive "$version" "$url" || true
}

run_kejilion_openclaw() {
  local mode="${1:-app-openclaw}"
  require_cmd bash || return 1
  require_cmd curl || return 1

  info "即将进入 Kejilion 上游 OpenClaw 菜单（始终拉取最新版本）..."
  case "$mode" in
    app-openclaw)
      bash <(curl -fsSL "$KEJILION_BOOTSTRAP_URL") app openclaw
      ;;
    claw)
      bash <(curl -fsSL "$KEJILION_BOOTSTRAP_URL") claw
      ;;
    *)
      error "未知模式: $mode"
      return 1
      ;;
  esac
}

show_local_openclaw_status() {
  echo ""
  echo "OpenClaw 本地状态"
  echo "----------------------------------------"
  if command -v openclaw >/dev/null 2>&1; then
    echo -e "命令安装 : ${GREEN}已安装${NC}"
    echo -n "版本信息 : "
    openclaw --version 2>/dev/null || echo "无法读取"
    echo -n "Gateway  : "
    openclaw gateway status 2>/dev/null || echo "未运行或不可用"
  else
    echo -e "命令安装 : ${RED}未安装${NC}"
  fi
  echo "----------------------------------------"
}

openclaw_menu() {
  while true; do
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "      OpenClaw（上游同步）"
    echo -e "${GREEN}========================================${NC}"
    echo "说明: 该菜单仅作为入口壳，具体 OpenClaw 功能全部由 Kejilion 上游脚本提供。"
    echo "      每次进入都会拉取最新脚本，确保与你要求的上游同步。"
    echo "----------------------------------------"
    echo "1. 进入 Kejilion OpenClaw 完整菜单 (app openclaw)"
    echo "2. 进入 Kejilion OpenClaw 菜单 (claw 别名)"
    echo "3. 查看本地 OpenClaw 状态"
    echo "0. 返回主菜单"
    echo "----------------------------------------"

    local oc_choice
    if ! read -r -p "请输入选项: " oc_choice; then
      oc_choice=""
    fi
    case "$oc_choice" in
      "") return ;;
      1)
        run_kejilion_openclaw "app-openclaw"
        pause_any_key
        ;;
      2)
        run_kejilion_openclaw "claw"
        pause_any_key
        ;;
      3)
        show_local_openclaw_status
        pause_any_key
        ;;
      0)
        return
        ;;
      *)
        warn "无效选项: $oc_choice"
        pause_any_key
        ;;
    esac
  done
}

check_openclaw_ready() {
  if ! command -v openclaw >/dev/null 2>&1; then
    error "未检测到 openclaw 命令，请先完成 OpenClaw 安装。"
    return 1
  fi

  if ! openclaw --version >/dev/null 2>&1; then
    error "openclaw 命令异常，无法获取版本信息。"
    return 1
  fi

  if ! openclaw gateway status >/dev/null 2>&1; then
    warn "OpenClaw Gateway 状态异常，请先确认 OpenClaw 正常运行后再安装技能。"
    return 1
  fi

  return 0
}

find_skillhub_binary() {
  if command -v skillhub >/dev/null 2>&1; then
    command -v skillhub
    return 0
  fi

  local candidates=(
    "$HOME/.local/bin/skillhub"
    "/root/.local/bin/skillhub"
    "/usr/local/bin/skillhub"
  )
  local p
  for p in "${candidates[@]}"; do
    if [[ -x "$p" ]]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

is_skillhub_installed() {
  find_skillhub_binary >/dev/null 2>&1
}

ensure_skillhub_link() {
  local bin_path
  bin_path="$(find_skillhub_binary)" || return 1

  if command -v skillhub >/dev/null 2>&1; then
    return 0
  fi

  ln -sf "$bin_path" /usr/local/bin/skillhub
  info "已创建 SkillHub 命令软链接: /usr/local/bin/skillhub -> ${bin_path}"
}

install_skillhub_cli_if_needed() {
  if is_skillhub_installed; then
    success "已检测到 SkillHub CLI。"
    ensure_skillhub_link || true
    return 0
  fi

  require_cmd bash || return 1
  require_cmd curl || return 1
  info "未检测到 SkillHub CLI，开始按 CLI-only 模式安装..."

  if ! bash -c "curl -fsSL \"$SKILLHUB_INSTALL_SCRIPT_URL\" | bash -s -- --cli-only"; then
    error "SkillHub CLI 安装失败。"
    return 1
  fi

  ensure_skillhub_link || true
  if ! is_skillhub_installed; then
    error "SkillHub CLI 安装后仍不可用。"
    return 1
  fi

  success "SkillHub CLI 安装完成。"
  return 0
}

install_adspower_browser_skill() {
  local skillhub_bin
  check_openclaw_ready || return 1
  install_skillhub_cli_if_needed || return 1
  skillhub_bin="$(find_skillhub_binary)" || {
    error "未找到 SkillHub CLI 可执行文件。"
    return 1
  }

  info "开始安装 Skill: ${SKILLHUB_DEFAULT_SKILL}"
  if (cd "$SCRIPT_DIR" && "$skillhub_bin" install "$SKILLHUB_DEFAULT_SKILL"); then
    success "Skill 安装成功: ${SKILLHUB_DEFAULT_SKILL}"
    return 0
  fi

  error "Skill 安装失败: ${SKILLHUB_DEFAULT_SKILL}"
  return 1
}

show_skillhub_status() {
  echo ""
  echo "SkillHub 状态"
  echo "----------------------------------------"
  if is_skillhub_installed; then
    local skillhub_bin
    skillhub_bin="$(find_skillhub_binary)"
    echo -e "CLI 状态 : ${GREEN}已安装${NC}"
    echo "CLI 路径 : ${skillhub_bin}"
    echo -n "CLI 版本 : "
    "$skillhub_bin" --version 2>/dev/null || echo "无法读取"
  else
    echo -e "CLI 状态 : ${RED}未安装${NC}"
  fi
  if command -v openclaw >/dev/null 2>&1; then
    echo -e "OpenClaw : ${GREEN}已安装${NC}"
    openclaw gateway status >/dev/null 2>&1 && echo -e "Gateway  : ${GREEN}正常${NC}" || echo -e "Gateway  : ${YELLOW}异常${NC}"
  else
    echo -e "OpenClaw : ${RED}未安装${NC}"
  fi
  echo "----------------------------------------"
}

skillhub_menu() {
  while true; do
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "      SkillHub 技能菜单"
    echo -e "${GREEN}========================================${NC}"
    echo "说明: 先检查 OpenClaw，再安装 SkillHub CLI（仅 CLI），最后安装 adspower-browser。"
    echo "----------------------------------------"
    echo "1. 一键安装 adspower-browser 技能"
    echo "2. 检查 SkillHub / OpenClaw 状态"
    echo "0. 返回主菜单"
    echo "----------------------------------------"

    local s_choice
    if ! read -r -p "请输入选项: " s_choice; then
      s_choice=""
    fi
    case "$s_choice" in
      "") return ;;
      1)
        install_adspower_browser_skill
        pause_any_key
        ;;
      2)
        show_skillhub_status
        pause_any_key
        ;;
      0)
        return
        ;;
      *)
        warn "无效选项: $s_choice"
        pause_any_key
        ;;
    esac
  done
}

find_opencode_binary() {
  if command -v opencode >/dev/null 2>&1; then
    command -v opencode
    return 0
  fi

  local candidates=(
    "$HOME/.opencode/bin/opencode"
    "/root/.opencode/bin/opencode"
    "/usr/local/bin/opencode"
  )
  local p
  for p in "${candidates[@]}"; do
    if [[ -x "$p" ]]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

is_opencode_installed() {
  find_opencode_binary >/dev/null 2>&1
}

ensure_opencode_link() {
  local bin_path
  bin_path="$(find_opencode_binary)" || return 1

  if command -v opencode >/dev/null 2>&1; then
    return 0
  fi

  ln -sf "$bin_path" "$OPENCODE_BIN_LINK"
  info "已创建 OpenCode 命令软链接: ${OPENCODE_BIN_LINK} -> ${bin_path}"
}

install_opencode_cli() {
  local force_reinstall="${1:-0}"
  require_cmd bash || return 1
  require_cmd curl || return 1

  if is_opencode_installed && [[ "$force_reinstall" != "1" ]]; then
    success "已检测到 OpenCode CLI。"
    ensure_opencode_link || true
    return 0
  fi

  if is_opencode_installed && [[ "$force_reinstall" == "1" ]]; then
    warn "检测到 OpenCode 已安装，开始重复安装 OpenCode CLI..."
  else
    info "开始安装 OpenCode CLI..."
  fi

  if ! bash -c "curl -fsSL \"$OPENCODE_INSTALL_URL\" | bash"; then
    error "OpenCode CLI 安装失败。"
    return 1
  fi

  ensure_opencode_link || true
  if ! is_opencode_installed; then
    error "OpenCode CLI 安装后仍不可用。"
    return 1
  fi

  success "OpenCode CLI 安装完成。"
  return 0
}

write_default_opencode_permission_config() {
  local out_file="$1"
  cat > "$out_file" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "*": "allow",
    "edit": "allow",
    "bash": {
      "*": "allow",
      "rm *": "ask",
      "rmdir *": "ask",
      "unlink *": "ask",
      "find * -delete*": "ask",
      "git clean *": "ask",
      "shred *": "ask",
      "srm *": "ask"
    }
  }
}
EOF
}

configure_opencode_default_permissions() {
  local reuse_existing="${1:-0}"
  mkdir -p "$OPENCODE_CONFIG_DIR"

  local tmp_cfg
  tmp_cfg="$(mktemp)"
  write_default_opencode_permission_config "$tmp_cfg"

  if [[ -f "$OPENCODE_CONFIG_FILE" ]]; then
    local backup_file
    backup_file="${OPENCODE_CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$OPENCODE_CONFIG_FILE" "$backup_file"
    info "已备份 OpenCode 配置: $backup_file"
  fi

  if [[ -f "$OPENCODE_CONFIG_FILE" ]] && command -v jq >/dev/null 2>&1 && jq -e . "$OPENCODE_CONFIG_FILE" >/dev/null 2>&1; then
    local merged_cfg
    merged_cfg="$(mktemp)"
    if jq '
      .["$schema"] = "https://opencode.ai/config.json" |
      .permission = (.permission // {}) |
      .permission."*" = "allow" |
      .permission.edit = "allow" |
      .permission.bash = (.permission.bash // {}) |
      .permission.bash."*" = "allow" |
      .permission.bash."rm *" = "ask" |
      .permission.bash."rmdir *" = "ask" |
      .permission.bash."unlink *" = "ask" |
      .permission.bash."find * -delete*" = "ask" |
      .permission.bash."git clean *" = "ask" |
      .permission.bash."shred *" = "ask" |
      .permission.bash."srm *" = "ask"
    ' "$OPENCODE_CONFIG_FILE" > "$merged_cfg"; then
      mv -f "$merged_cfg" "$OPENCODE_CONFIG_FILE"
      chmod 600 "$OPENCODE_CONFIG_FILE" 2>/dev/null || true
      success "OpenCode 授权模式已更新（非删除操作默认放行，删除类命令需确认）。"
      rm -f "$tmp_cfg" 2>/dev/null || true
      return 0
    fi
    warn "检测到 jq 合并失败，将改为写入默认授权模板。"
    rm -f "$merged_cfg" 2>/dev/null || true
  fi

  if [[ -f "$OPENCODE_CONFIG_FILE" && "$reuse_existing" == "1" ]]; then
    warn "检测到现有配置无法安全合并，按复用策略保留原配置不覆盖。"
    rm -f "$tmp_cfg" 2>/dev/null || true
    success "已复用现有 OpenCode 配置。"
    return 0
  fi

  mv -f "$tmp_cfg" "$OPENCODE_CONFIG_FILE"
  chmod 600 "$OPENCODE_CONFIG_FILE" 2>/dev/null || true
  success "OpenCode 授权模式已写入: $OPENCODE_CONFIG_FILE"
  return 0
}

show_opencode_status() {
  echo ""
  echo "OpenCode 状态"
  echo "----------------------------------------"
  if is_opencode_installed; then
    echo -e "CLI 状态 : ${GREEN}已安装${NC}"
    echo -n "CLI 路径 : "
    find_opencode_binary 2>/dev/null || echo "未知"
    echo -n "CLI 版本 : "
    opencode --version 2>/dev/null || echo "无法读取"
  else
    echo -e "CLI 状态 : ${RED}未安装${NC}"
  fi

  if [[ -f "$OPENCODE_CONFIG_FILE" ]]; then
    echo -e "配置文件 : ${GREEN}${OPENCODE_CONFIG_FILE}${NC}"
    if grep -q '"rm \*"[[:space:]]*:[[:space:]]*"ask"' "$OPENCODE_CONFIG_FILE" 2>/dev/null; then
      echo -e "删除确认 : ${GREEN}已启用${NC}"
    else
      echo -e "删除确认 : ${YELLOW}未检测到 rm 规则${NC}"
    fi
  else
    echo -e "配置文件 : ${YELLOW}未生成${NC}"
  fi
  echo "----------------------------------------"
}

opencode_menu() {
  while true; do
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "      OpenCode 安装与授权"
    echo -e "${GREEN}========================================${NC}"
    if is_opencode_installed; then
      echo -e "当前状态 : ${GREEN}已安装${NC}"
    else
      echo -e "当前状态 : ${RED}未安装${NC}"
    fi
    echo "说明: 默认策略为非删除操作自动放行；删除类命令（rm/rmdir/unlink 等）保留确认。"
    echo "----------------------------------------"
    echo "1. 安装 OpenCode 并应用默认授权策略"
    echo "2. 仅应用默认授权策略"
    echo "3. 查看 OpenCode 状态"
    echo "0. 返回主菜单"
    echo "----------------------------------------"

    local ocd_choice
    if ! read -r -p "请输入选项: " ocd_choice; then
      ocd_choice=""
    fi
    case "$ocd_choice" in
      "") return ;;
      1)
        local reuse_existing_cfg="0"
        local reinstall_requested="0"

        if is_opencode_installed; then
          success "OpenCode 当前已安装。"
          if confirm_action "是否执行重复安装 OpenCode CLI？"; then
            reinstall_requested="1"
          else
            info "已跳过重复安装。"
          fi

          if confirm_action "检测到已有 OpenCode 配置，是否复用现有配置（不重置）？"; then
            reuse_existing_cfg="1"
          fi
        fi

        if [[ "$reinstall_requested" == "1" ]]; then
          install_opencode_cli "1" || {
            pause_any_key
            continue
          }
        else
          install_opencode_cli || {
            pause_any_key
            continue
          }
        fi

        configure_opencode_default_permissions "$reuse_existing_cfg"
        pause_any_key
        ;;
      2)
        configure_opencode_default_permissions "0"
        pause_any_key
        ;;
      3)
        show_opencode_status
        pause_any_key
        ;;
      0)
        return
        ;;
      *)
        warn "无效选项: $ocd_choice"
        pause_any_key
        ;;
    esac
  done
}

is_debian_like() {
  command -v apt-get >/dev/null 2>&1
}

is_rhel_like() {
  [[ -f /etc/redhat-release ]] && (command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1)
}

DEBIAN_ADSPOWER_DEPS_BASE=(
  xvfb
  xz-utils
  ca-certificates
  fonts-liberation
  libatk-bridge2.0-0
  libatk1.0-0
  libatspi2.0-0
  libdbus-1-3
  libdrm2
  libgbm1
  libgtk-3-0
  libnspr4
  libnss3
  libxcomposite1
  libxdamage1
  libxfixes3
  libxkbcommon0
  libxrandr2
  libxss1
  curl
  wget
)

RHEL_ADSPOWER_DEPS_BASE=(
  xz
  ca-certificates
  liberation-fonts-common
  alsa-lib
  atk
  at-spi2-atk
  at-spi2-core
  cups-libs
  dbus-libs
  libdrm
  mesa-libgbm
  gtk3
  nspr
  nss
  nss-util
  libXcomposite
  libXdamage
  libXfixes
  libxkbcommon
  libXrandr
  curl
  wget
)

print_debian_dep_install_cmd() {
  local debian_deps=()
  mapfile -t debian_deps < <(get_debian_ads_deps)
  local joined
  joined="$(printf '%s ' "${debian_deps[@]}")"
  echo "sudo apt-get update && sudo apt-get install -y --no-install-recommends ${joined}"
}

resolve_debian_pkg_variant() {
  local preferred="$1"
  shift
  local candidate
  for candidate in "$preferred" "$@"; do
    if dpkg -s "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
    if command -v apt-cache >/dev/null 2>&1; then
      local cand_ver
      cand_ver="$(apt-cache policy "$candidate" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
      if [[ -n "$cand_ver" && "$cand_ver" != "(none)" ]]; then
        echo "$candidate"
        return 0
      fi
    fi
  done
  echo "$preferred"
  return 0
}

get_debian_ads_deps() {
  local deps=()
  local p
  for p in "${DEBIAN_ADSPOWER_DEPS_BASE[@]}"; do
    case "$p" in
      libatk-bridge2.0-0|libatk1.0-0|libatspi2.0-0|libgtk-3-0) continue ;;
      *) deps+=("$p") ;;
    esac
  done

  deps+=(
    "$(resolve_debian_pkg_variant "libatk-bridge2.0-0" "libatk-bridge2.0-0t64")"
    "$(resolve_debian_pkg_variant "libatk1.0-0" "libatk1.0-0t64")"
    "$(resolve_debian_pkg_variant "libatspi2.0-0" "libatspi2.0-0t64")"
    "$(resolve_debian_pkg_variant "libgtk-3-0" "libgtk-3-0t64")"
    "$(resolve_debian_pkg_variant "libasound2" "libasound2t64")"
    "$(resolve_debian_pkg_variant "libcups2" "libcups2t64")"
  )
  printf '%s\n' "${deps[@]}"
}

check_missing_debian_deps() {
  local deps=()
  mapfile -t deps < <(get_debian_ads_deps)
  local missing=()
  local p
  for p in "${deps[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  printf '%s\n' "${missing[@]}"
}

get_rhel_major() {
  local v
  v="$(rpm -E '%{rhel}' 2>/dev/null || echo "")"
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    echo "$v"
  else
    echo "0"
  fi
}

get_rhel_virtual_display_pkg() {
  local major
  major="$(get_rhel_major)"
  if (( major >= 10 )); then
    echo "tigervnc-server"
  else
    echo "xorg-x11-server-Xvfb"
  fi
}

get_rhel_ads_deps() {
  local deps=("${RHEL_ADSPOWER_DEPS_BASE[@]}")
  deps+=("$(get_rhel_virtual_display_pkg)")
  printf '%s\n' "${deps[@]}"
}

prepare_rhel_repos() {
  if ! command -v dnf >/dev/null 2>&1; then
    return 0
  fi

  rpm -q dnf-plugins-core >/dev/null 2>&1 || dnf install -y dnf-plugins-core >/dev/null 2>&1 || true
  dnf config-manager --set-enabled appstream baseos >/dev/null 2>&1 || true

  local major
  major="$(get_rhel_major)"
  if (( major >= 10 )); then
    dnf config-manager --set-enabled crb >/dev/null 2>&1 || true
  fi

  if ! rpm -q epel-release >/dev/null 2>&1; then
    dnf install -y epel-release >/dev/null 2>&1 || true
  fi
  dnf makecache >/dev/null 2>&1 || true
}

check_missing_rhel_deps() {
  local deps=()
  mapfile -t deps < <(get_rhel_ads_deps)
  local missing=()
  local p
  for p in "${deps[@]}"; do
    rpm -q "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  printf '%s\n' "${missing[@]}"
}

ensure_adspower_runtime_ready() {
  if is_debian_like; then
    local missing=()
    mapfile -t missing < <(check_missing_debian_deps)
    if (( ${#missing[@]} > 0 )); then
      error "检测到 AdsPower 运行依赖缺失 (${#missing[@]} 个): ${missing[*]}"
      warn "可选择由脚本自动安装依赖后继续。"
      return 1
    fi
    return 0
  fi

  if is_rhel_like; then
    local missing=()
    mapfile -t missing < <(check_missing_rhel_deps)
    if (( ${#missing[@]} > 0 )); then
      error "检测到 RHEL 运行依赖缺失 (${#missing[@]} 个): ${missing[*]}"
      warn "可选择由脚本自动安装依赖后继续。"
      return 1
    fi
    return 0
  fi

  warn "未知发行版，无法自动校验全部运行依赖。"
  return 0
}

install_runtime_deps() {
  local ask_confirm="${1:-1}"

  if is_debian_like; then
    info "检测到 Debian/Ubuntu，安装 AdsPower 运行依赖..."
    local missing=()
    mapfile -t missing < <(check_missing_debian_deps)
    local tools=(iproute2 procps grep sed gawk)
    local t
    for t in "${tools[@]}"; do
      dpkg -s "$t" >/dev/null 2>&1 || missing+=("$t")
    done

    apt-get update
    if (( ${#missing[@]} > 0 )); then
      if [[ "$ask_confirm" == "1" ]]; then
        warn "检测到缺失依赖 (${#missing[@]} 个): ${missing[*]}"
        if ! confirm_action "是否立即自动安装这些依赖？"; then
          warn "已取消自动安装依赖。"
          return 1
        fi
      fi
      info "将安装缺失包 (${#missing[@]} 个): ${missing[*]}"
      apt-get install -y --no-install-recommends "${missing[@]}"
    else
      info "依赖已齐全，跳过安装。"
    fi
    return 0
  fi

  if is_rhel_like; then
    info "检测到 RHEL 系，安装 AdsPower 运行依赖..."
    prepare_rhel_repos
    local pkg_mgr="dnf"
    command -v dnf >/dev/null 2>&1 || pkg_mgr="yum"
    local missing=()
    mapfile -t missing < <(check_missing_rhel_deps)
    local tools=(iproute procps-ng grep sed gawk)
    local t
    for t in "${tools[@]}"; do
      rpm -q "$t" >/dev/null 2>&1 || missing+=("$t")
    done

    if (( ${#missing[@]} > 0 )); then
      if [[ "$ask_confirm" == "1" ]]; then
        warn "检测到缺失依赖 (${#missing[@]} 个): ${missing[*]}"
        if ! confirm_action "是否立即自动安装这些依赖？"; then
          warn "已取消自动安装依赖。"
          return 1
        fi
      fi
      info "将安装缺失包 (${#missing[@]} 个): ${missing[*]}"
      "$pkg_mgr" install -y "${missing[@]}"
    else
      info "依赖已齐全，跳过安装。"
    fi
    return 0
  fi

  warn "未知发行版：仅支持 Debian/Ubuntu 与 RHEL 系。"
  return 1
}

install_or_fix_adspower() {
  load_config
  install_runtime_deps || return 1
  prompt_api_key_if_needed || return 1

  if [[ -f "$ADSPOWER_EXEC" ]]; then
    chmod +x "$ADSPOWER_EXEC"
    ensure_bin_link
    if [[ "$ADSPOWER_SYNC_MAIN_MIN_JS_ON_INSTALL" == "1" ]]; then
      update_main_min_js_from_url || true
    fi
    info "检测到 AdsPower 已安装，执行启动检查..."
    save_config
    start_adspower || true
    return 0
  fi

  local deb_file=""
  if [[ -n "$ADSPOWER_DEB_PATH" ]]; then
    if [[ -f "$ADSPOWER_DEB_PATH" ]]; then
      deb_file="$ADSPOWER_DEB_PATH"
      info "使用本地 .deb 安装包: $deb_file"
    else
      error "指定的 ADSPOWER_DEB_PATH 不存在: $ADSPOWER_DEB_PATH"
      return 1
    fi
  else
    local deb_url tmp_dir
    deb_url="${ADSPOWER_DEB_BASE}/${ADSPOWER_DEFAULT_VERSION}/AdsPower-Global-${ADSPOWER_DEFAULT_VERSION}-x64.deb"
    tmp_dir="$(make_temp_dir)"
    deb_file="${tmp_dir}/AdsPower-Global-${ADSPOWER_DEFAULT_VERSION}-x64.deb"
    info "未检测到 AdsPower，开始下载: $deb_url"
    download_to_file "$deb_url" "$deb_file" || {
      error "下载失败，请手动下载安装包，或设置 ADSPOWER_DEB_PATH。"
      return 1
    }
  fi

  install_adspower_from_deb "$deb_file" || return 1
  save_config
  start_adspower || true
  return 0
}

show_api_detail() {
  load_config
  if ! is_valid_port "$API_PORT"; then
    error "端口非法: $API_PORT"
    return 1
  fi

  local detail
  detail="$(get_api_raw_status)"
  if [[ -z "$detail" ]]; then
    error "API 不可达: http://127.0.0.1:${API_PORT}/status"
    return 1
  fi

  local code msg
  code="$(echo "$detail" | grep -o '"code":[0-9-]*' | head -1 | cut -d':' -f2 || true)"
  msg="$(echo "$detail" | sed -n 's/.*"msg":"\([^"]*\)".*/\1/p' | head -1 || true)"
  [[ -z "$msg" ]] && msg="unknown"

  echo ""
  echo "API 检查结果"
  echo "----------------------------------------"
  if [[ "$code" == "0" || "$detail" == *"success"* ]]; then
    echo -e "接口状态 : ${GREEN}在线${NC}"
  else
    echo -e "接口状态 : ${RED}异常${NC}"
  fi
  echo -e "服务进程 : $(get_service_status)"
  if is_port_listening "$API_PORT"; then
    echo -e "端口监听 : ${GREEN}127.0.0.1:${API_PORT}${NC}"
  else
    echo -e "端口监听 : ${RED}未监听${NC}"
  fi
  echo "状态消息 : $msg"
  echo "----------------------------------------"
}

change_api_key() {
  local new_key
  if ! read -r -p "输入新 Key: " new_key; then
    new_key=""
  fi
  new_key="$(trim "$new_key")"
  [[ -n "$new_key" ]] || {
    error "Key 不能为空。"
    return 1
  }
  API_KEY="$new_key"
  save_config
}

check_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    error "此脚本需要 root 权限运行。"
    exit 1
  fi
}

main_menu() {
  while true; do
    load_config
    ensure_patch_list_healthy

    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "      AdsPower Global 管理仪表盘 v5.0"
    echo -e "      ${CYAN}稳健版 - 单文件 Bash${NC}"
    echo -e "${GREEN}========================================${NC}"

    printf "服务状态 : %b\n" "$(get_service_status)"
    printf "API 状态 : %b\n" "$(get_api_status)"
    printf "当前补丁 : %b\n" "$(get_patch_info)"
    printf "开机自启 : %b\n" "$(get_autostart_info)"
    printf "当前端口 : ${YELLOW}%s${NC}\n" "$API_PORT"
    printf "系统资源 : %b\n" "$(get_resource_usage)"
    printf "当前 Key : %b\n" "$(get_masked_key)"

    echo -e "${GREEN}----------------------------------------${NC}"
    echo -e "1. ${CYAN}安装/修复 AdsPower${NC}"
    echo -e "2. ${GREEN}启动服务 (Start)${NC}"
    echo -e "3. ${RED}停止服务 (Stop)${NC}"
    echo -e "4. ${YELLOW}重启服务 (Restart)${NC}"
    echo "5. 检查 API 详情"
    echo "6. 切换开机自启"
    echo "7. 更换 API Key"
    echo "8. 补丁管理菜单"
    echo "9. 内核管理菜单"
    echo -e "10. ${CYAN}OpenClaw（上游同步）${NC}"
    echo -e "11. ${CYAN}SkillHub 技能安装${NC}"
    echo -e "12. ${CYAN}OpenCode 安装与授权${NC}"
    echo "0. 退出脚本"
    echo "----------------------------------------"

    local choice
    if ! read -r -p "请输入选项: " choice; then
      choice=""
    fi
    case "$choice" in
      "") continue ;;
      1) install_or_fix_adspower ;;
      2) start_adspower ;;
      3) stop_adspower ;;
      4) restart_adspower ;;
      5) show_api_detail ;;
      6) toggle_autostart ;;
      7) change_api_key ;;
      8) patch_menu ;;
      9) kernel_menu ;;
      10) openclaw_menu ;;
      11) skillhub_menu ;;
      12) opencode_menu ;;
      0) exit 0 ;;
      *) warn "无效选项: $choice" ;;
    esac

    pause_any_key
  done
}

check_root
ensure_ads_shortcut
main_menu

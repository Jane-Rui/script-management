#!/usr/bin/env bash

# AdsPower Global 管理脚本 v5.0 - 稳健重构版（单文件）

set -Eeuo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

ADSPOWER_EXEC="${ADSPOWER_EXEC:-/opt/AdsPower Global/adspower_global}"
CONFIG_FILE="${ADSPOWER_CONFIG_FILE:-$SCRIPT_DIR/adspower.env}"
SERVICE_FILE="${ADSPOWER_SERVICE_FILE:-/etc/systemd/system/adspower.service}"
PATCH_DIR="${ADSPOWER_PATCH_DIR:-$SCRIPT_DIR/patches}"
PATCH_LIST="${ADSPOWER_PATCH_LIST:-$SCRIPT_DIR/patches.list}"
ACTIVE_PATCH_FILE="${ADSPOWER_ACTIVE_PATCH_FILE:-$SCRIPT_DIR/.active_patch}"
TARGET_JS="${ADSPOWER_TARGET_JS:-$HOME/.config/adspower_global/cwd_global/lib/main.min.js}"
ADSPOWER_DEFAULT_VERSION="${ADSPOWER_DEFAULT_VERSION:-7.12.29}"
ADSPOWER_DEB_BASE="${ADSPOWER_DEB_BASE:-https://version.adspower.net/software/linux-x64-global}"
KEJILION_BOOTSTRAP_URL="${KEJILION_BOOTSTRAP_URL:-https://kejilion.sh}"

if [[ -d "/root/.config/adspower_global/cwd_global" ]]; then
  KERNEL_ROOT="${ADSPOWER_KERNEL_ROOT:-/root/.config/adspower_global/cwd_global}"
else
  KERNEL_ROOT="${ADSPOWER_KERNEL_ROOT:-$HOME/.config/adspower_global/cwd_global}"
fi

API_KEY=""
API_PORT=50325

mkdir -p "$PATCH_DIR"

on_error() {
  local exit_code=$?
  echo -e "${RED}[ERROR]${NC} 第 ${BASH_LINENO[0]} 行执行失败：${BASH_COMMAND} (exit=${exit_code})"
}
trap on_error ERR

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }

pause_any_key() {
  echo ""
  read -r -n 1 -p "按任意键继续..." _
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

  if command -v curl >/dev/null 2>&1; then
    curl -fSL --progress-bar -o "$out" "$url"
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q --show-progress -O "$out" "$url"
    return 0
  fi

  error "未找到 curl/wget，无法下载: $url"
  return 1
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

get_vtok_status() {
  local cfg="$HOME/.openclaw/openclaw.json"
  if [[ ! -f "$cfg" ]]; then
    echo -e "${RED}未安装${NC}"
    return
  fi

  if grep -q '"vtok-claude"' "$cfg" 2>/dev/null; then
    local key
    key="$(grep -A 2 '"vtok-claude"' "$cfg" | grep 'apiKey' | sed 's/.*"\([^"]*\)".*/\1/' | head -c 8)"
    echo -e "${GREEN}已配置 (${key}****)${NC}"
  else
    echo -e "${RED}未配置${NC}"
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
v2.8.4.4|https://version.adspower.net/software/lib_production/v2.8.4.4_main.min.js11bff97aadb92fc16a9abd79e1939518
v2.8.4.3|https://version.adspower.net/software/lib_production/v2.8.4.3_main.min.js07075aa4da52fd3c9f297b01a103cacb
EOF
}

ensure_patch_list_healthy() {
  if [[ ! -f "$PATCH_LIST" || ! -s "$PATCH_LIST" ]]; then
    warn "补丁列表不存在或为空，已自动重建默认列表。"
    write_default_patch_list
    return
  fi

  if ! tr -d '\r' < "$PATCH_LIST" | grep -qE '^[^|]+\|https?://'; then
    warn "补丁列表格式异常，已恢复默认列表。"
    write_default_patch_list
  fi
}

json_escape() {
  local str="$1"
  echo "$str" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g'
}

build_vtok_config() {
  local token="$1"
  local cfg_file="$2"

  [[ -f "$cfg_file" ]] && cp "$cfg_file" "${cfg_file}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true

  cat > "$cfg_file" <<'EOFCONFIG'
{
  "meta": {
    "lastTouchedVersion": "2026.3.24",
    "lastTouchedAt": "TIMESTAMP"
  },
  "models": {
    "mode": "merge",
    "providers": {
      "vtok-claude": {
        "baseUrl": "https://vtok.ai",
        "apiKey": "VTOK_TOKEN_PLACEHOLDER",
        "auth": "token",
        "api": "anthropic-messages",
        "authHeader": true,
        "models": [
          {
            "id": "claude-opus-4-6",
            "name": "claude-opus-4-6",
            "api": "anthropic-messages",
            "reasoning": false,
            "input": ["text"],
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "contextWindow": 200000,
            "maxTokens": 8192
          },
          {
            "id": "claude-haiku-4-5",
            "name": "claude-haiku",
            "api": "anthropic-messages",
            "reasoning": false,
            "input": ["text"],
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "contextWindow": 200000,
            "maxTokens": 8192
          },
          {
            "id": "claude-sonnet-4-6",
            "name": "claude-sonnet",
            "api": "anthropic-messages",
            "reasoning": false,
            "input": ["text"],
            "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            "contextWindow": 200000,
            "maxTokens": 8192
          }
        ]
      },
      "vtok-openai": {
        "baseUrl": "https://vtok.ai/v1",
        "apiKey": "VTOK_TOKEN_PLACEHOLDER",
        "auth": "token",
        "api": "openai-responses",
        "authHeader": true,
        "models": [
          {"id": "gpt-5.4", "name": "gpt-5.4", "api": "openai-responses", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}, "contextWindow": 128000, "maxTokens": 16384},
          {"id": "gpt-5.3", "name": "gpt-5.3", "api": "openai-responses", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}, "contextWindow": 128000, "maxTokens": 16384},
          {"id": "gpt-5.2", "name": "gpt-5.2", "api": "openai-responses", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}, "contextWindow": 128000, "maxTokens": 16384}
        ]
      },
      "vtok-gemini": {
        "baseUrl": "https://vtok.ai/v1beta",
        "apiKey": "VTOK_TOKEN_PLACEHOLDER",
        "auth": "token",
        "api": "google-generative-ai",
        "authHeader": true,
        "models": [
          {"id": "gemini-3.1-pro-preview", "name": "Gemini 3.1 Pro Preview", "api": "google-generative-ai", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}, "contextWindow": 1000000, "maxTokens": 8192},
          {"id": "gemini-3-pro-preview", "name": "Gemini 3 Pro Preview", "api": "google-generative-ai", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}, "contextWindow": 1000000, "maxTokens": 8192},
          {"id": "gemini-3-flash-preview", "name": "Gemini 3 Flash Preview", "api": "google-generative-ai", "reasoning": false, "input": ["text"], "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0}, "contextWindow": 1000000, "maxTokens": 8192}
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "maxConcurrent": 4,
      "model": {
        "primary": "vtok-claude/claude-sonnet-4-6",
        "fallbacks": ["vtok-claude/claude-opus-4-6", "vtok-openai/gpt-5.4", "vtok-gemini/gemini-3.1-pro-preview"]
      },
      "models": {
        "vtok-claude/claude-opus-4-6": {"alias": "opus"},
        "vtok-claude/claude-sonnet-4-6": {"alias": "sonnet"},
        "vtok-claude/claude-haiku-4-5": {"alias": "haiku"},
        "vtok-openai/gpt-5.3": {"alias": "gpt53"},
        "vtok-openai/gpt-5.2": {"alias": "gpt52"},
        "vtok-openai/gpt-5.4": {"alias": "gpt54"},
        "vtok-gemini/gemini-3.1-pro-preview": {"alias": "gemini31"},
        "vtok-gemini/gemini-3-pro-preview": {"alias": "gemini3"},
        "vtok-gemini/gemini-3-flash-preview": {"alias": "flash"}
      }
    }
  }
}
EOFCONFIG

  sed -i "s/VTOK_TOKEN_PLACEHOLDER/$(json_escape "$token")/g" "$cfg_file"
  sed -i "s/TIMESTAMP/$(date -u +%Y-%m-%dT%H:%M:%S.000Z)/g" "$cfg_file"
}

prompt_api_key_if_needed() {
  if [[ -n "$API_KEY" ]]; then
    return 0
  fi

  read -r -p "请输入 AdsPower API Key: " API_KEY
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
    ((i++))
  done
  return 1
}

start_adspower() {
  load_config
  prompt_api_key_if_needed || return 1

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

  if is_adspower_running; then
    info "AdsPower 进程已在运行，检查 API 状态..."
    if wait_api_ready 5; then
      success "API 已在线，无需重复启动。"
      return 0
    fi
    warn "进程存在但 API 未响应，建议重启服务。"
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
    ((i++))
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
  read -r -p "请输入选项 (支持多选 1,2): " k_in
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
      read -r -p "版本号: " cv
      cv="$(trim "$cv")"
      [[ -n "$cv" ]] && download_kernel_api "$cv" || warn "版本号为空，已跳过。"
    else
      warn "超出范围的选项: $opt"
    fi
  done
}

patch_add_url() {
  local url v tmp_file
  read -r -p "地址: " url
  url="$(trim "$url")"
  [[ "$url" =~ ^https?:// ]] || {
    error "补丁地址必须以 http:// 或 https:// 开头。"
    return 1
  }

  v="$(echo "$url" | sed -n 's/.*\/\(v[0-9.]*\)_main.*/\1/p')"
  if [[ -z "$v" ]]; then
    read -r -p "版本 (例如 v2.8.4.4): " v
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
    ((i++))
  done

  local p_c
  read -r -p "编号 (0 返回): " p_c
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
  echo "1. 添加补丁链接"
  echo "2. 应用补丁 (需重启)"
  echo "0. 返回主菜单"

  local o
  read -r -p "选项: " o
  case "$o" in
    1) patch_add_url ;;
    2) patch_apply ;;
    0) return ;;
    *) warn "无效选项: $o" ;;
  esac
}

vtok_setup() {
  local cfg="$HOME/.openclaw/openclaw.json"
  if [[ ! -f "$cfg" ]]; then
    error "未找到 OpenClaw 配置文件: $cfg"
    return 1
  fi

  echo -e "${YELLOW}请输入您的 VTok Token:${NC}"
  local vtok_token
  read -r vtok_token
  vtok_token="$(trim "$vtok_token")"
  [[ -n "$vtok_token" ]] || {
    error "Token 不能为空"
    return 1
  }

  info "正在写入 VTok 配置..."
  build_vtok_config "$vtok_token" "$cfg"

  success "VTok 配置成功。"
  echo -e "${YELLOW}默认模型: vtok-claude/claude-sonnet-4-6${NC}"

  if command -v openclaw >/dev/null 2>&1; then
    if openclaw gateway restart; then
      success "OpenClaw Gateway 已重启"
    else
      warn "Gateway 自动重启失败，请手动执行: openclaw gateway restart"
    fi
  else
    warn "未检测到 openclaw 命令，请手动重启 Gateway。"
  fi
}

vtok_show() {
  local cfg="$HOME/.openclaw/openclaw.json"
  if [[ ! -f "$cfg" ]]; then
    error "无法读取配置: $cfg"
    return
  fi

  echo ""
  echo -e "${CYAN}当前已配置的 VTok 模型:${NC}"

  if grep -q '"vtok-claude"' "$cfg"; then
    echo -e "  ${GREEN}vtok-claude:${NC}"
    grep -A 50 '"vtok-claude"' "$cfg" | grep '"id"' | sed 's/.*"\([^"]*\)".*/    - \1/'
  fi
  if grep -q '"vtok-openai"' "$cfg"; then
    echo -e "  ${GREEN}vtok-openai:${NC}"
    grep -A 50 '"vtok-openai"' "$cfg" | grep '"id"' | sed 's/.*"\([^"]*\)".*/    - \1/'
  fi
  if grep -q '"vtok-gemini"' "$cfg"; then
    echo -e "  ${GREEN}vtok-gemini:${NC}"
    grep -A 50 '"vtok-gemini"' "$cfg" | grep '"id"' | sed 's/.*"\([^"]*\)".*/    - \1/'
  fi

  echo ""
  echo -e "${CYAN}默认模型:${NC}"
  grep '"primary"' "$cfg" | sed 's/.*"\([^"]*\)".*/  \1/' | head -1
}

vtok_menu() {
  clear
  echo -e "${GREEN}========================================${NC}"
  echo -e "      VTok 模型配置 v5.0"
  echo -e "${GREEN}========================================${NC}"
  printf "当前状态 : %b\n" "$(get_vtok_status)"
  echo -e "${GREEN}----------------------------------------${NC}"
  echo "1. 配置 VTok Token（Claude + GPT + Gemini）"
  echo "2. 查看当前已配置的模型"
  echo "0. 返回主菜单"
  echo "----------------------------------------"

  local v_choice
  read -r -p "请输入选项: " v_choice
  case "$v_choice" in
    1) vtok_setup ;;
    2) vtok_show ;;
    0) return ;;
    *) warn "无效选项: $v_choice" ;;
  esac
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
    read -r -p "请输入选项: " oc_choice
    case "$oc_choice" in
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

is_debian_like() {
  command -v apt-get >/dev/null 2>&1
}

is_rhel_like() {
  [[ -f /etc/redhat-release ]] && (command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1)
}

install_runtime_deps() {
  if is_debian_like; then
    info "检测到 Debian/Ubuntu，安装依赖..."
    apt-get update
    apt-get install -y --no-install-recommends wget xvfb curl iproute2 procps grep sed gawk
    return 0
  fi

  if is_rhel_like; then
    info "检测到 RHEL 系，安装依赖..."
    local pkg_mgr="dnf"
    command -v dnf >/dev/null 2>&1 || pkg_mgr="yum"
    "$pkg_mgr" install -y wget xorg-x11-server-Xvfb curl iproute procps-ng grep sed gawk
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
    info "检测到 AdsPower 已安装，执行启动检查..."
    save_config
    start_adspower || true
    return 0
  fi

  if is_debian_like; then
    local deb_file="/tmp/AdsPower-Global-${ADSPOWER_DEFAULT_VERSION}-x64.deb"
    local deb_url="${ADSPOWER_DEB_BASE}/${ADSPOWER_DEFAULT_VERSION}/AdsPower-Global-${ADSPOWER_DEFAULT_VERSION}-x64.deb"

    info "未检测到 AdsPower，开始下载: $deb_url"
    download_to_file "$deb_url" "$deb_file" || {
      error "下载失败，请手动下载安装包。"
      return 1
    }

    if ! dpkg -i "$deb_file"; then
      warn "dpkg 安装失败，尝试修复依赖..."
      apt-get -f install -y
      dpkg -i "$deb_file"
    fi

    [[ -f "$ADSPOWER_EXEC" ]] || {
      error "安装后仍未找到: $ADSPOWER_EXEC"
      return 1
    }

    chmod +x "$ADSPOWER_EXEC"
    save_config
    start_adspower || true
    return 0
  fi

  warn "当前非 Debian/Ubuntu，未自动安装 AdsPower 包。请手动安装后再使用启动功能。"
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
  read -r -p "输入新 Key: " new_key
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
    ensure_default_patch_list

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
    printf "VTok 状态 : %b\n" "$(get_vtok_status)"

    echo -e "${GREEN}----------------------------------------${NC}"
    echo -e "1. ${CYAN}环境安装/修复${NC}"
    echo -e "2. ${GREEN}启动服务 (Start)${NC}"
    echo -e "3. ${RED}停止服务 (Stop)${NC}"
    echo -e "4. ${YELLOW}重启服务 (Restart)${NC}"
    echo "5. 检查 API 详情"
    echo "6. 切换开机自启"
    echo "7. 更换 API Key"
    echo "8. 补丁管理菜单"
    echo "9. 内核管理菜单"
    echo -e "10. ${CYAN}VTok 模型配置${NC}"
    echo -e "11. ${CYAN}OpenClaw（上游同步）${NC}"
    echo "0. 退出脚本"
    echo "----------------------------------------"

    local choice
    read -r -p "请输入选项: " choice
    case "$choice" in
      1) install_or_fix_adspower ;;
      2) start_adspower ;;
      3) stop_adspower ;;
      4) restart_adspower ;;
      5) show_api_detail ;;
      6) toggle_autostart ;;
      7) change_api_key ;;
      8) patch_menu ;;
      9) kernel_menu ;;
      10) vtok_menu ;;
      11) openclaw_menu ;;
      0) exit 0 ;;
      *) warn "无效选项: $choice" ;;
    esac

    pause_any_key
  done
}

check_root
main_menu

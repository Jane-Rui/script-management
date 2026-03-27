#!/bin/bash

# AdsPower Global 管理脚本 v4.2 - 独立版
# 无外部依赖，纯 bash 实现所有功能

RED=$(echo -e "\033[0;31m")
GREEN=$(echo -e "\033[0;32m")
YELLOW=$(echo -e "\033[1;33m")
CYAN=$(echo -e "\033[0;36m")
NC=$(echo -e "\033[0m")

SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
ADSPOWER_EXEC="/opt/AdsPower Global/adspower_global"
CONFIG_FILE="$SCRIPT_DIR/adspower.env"
SERVICE_FILE="/etc/systemd/system/adspower.service"
PATCH_DIR="$SCRIPT_DIR/patches"
PATCH_LIST="$SCRIPT_DIR/patches.list"
ACTIVE_PATCH_FILE="$SCRIPT_DIR/.active_patch"
TARGET_JS="/root/.config/adspower_global/cwd_global/lib/main.min.js"

if [ -d "/root/.config/adspower_global/cwd_global" ]; then
    KERNEL_ROOT="/root/.config/adspower_global/cwd_global"
else
    KERNEL_ROOT="$HOME/.config/adspower_global/cwd_global"
fi

mkdir -p "$PATCH_DIR"

# === 纯 bash JSON 解析器 ===
json_get() {
    local json="$1"
    local key="$2"
    echo "$json" | grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*"\([^"]*\)".*/\1/' | head -1
}

json_escape() {
    local str="$1"
    echo "$str" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g'
}

# === 纯 bash JSON 构建器 ===
build_vtok_config() {
    local token="$1"
    local cfg_file="$2"
    
    # 读取现有配置
    local existing=$(cat "$cfg_file" 2>/dev/null || echo "{}")
    
    # 备份
    cp "$cfg_file" "${cfg_file}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null
    
    # 构建新配置（使用 sed 和 awk 替代 jq）
    cat > "$cfg_file" << 'EOFCONFIG'
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
    
    # 替换 token 和时间戳
    sed -i "s/VTOK_TOKEN_PLACEHOLDER/$(json_escape "$token")/g" "$cfg_file"
    sed -i "s/TIMESTAMP/$(date -u +%Y-%m-%dT%H:%M:%S.000Z)/g" "$cfg_file"
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        API_KEY=$(grep 'API_KEY=' "$CONFIG_FILE" | cut -d'"' -f2)
        API_PORT=$(grep 'API_PORT=' "$CONFIG_FILE" | sed 's/API_PORT=//')
    fi
    : "${API_KEY:=""}"; : "${API_PORT:=50325}"
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
API_KEY="$API_KEY"
API_PORT=$API_PORT
EOF
    chmod 644 "$CONFIG_FILE"
}

get_service_status() { 
    pgrep -f "adspower_global" >/dev/null && echo -e "${GREEN}正在运行${NC}" || echo -e "${RED}已停止${NC}"
}

get_api_status() { 
    local res=$(curl -s --max-time 1 http://127.0.0.1:$API_PORT/status 2>/dev/null)
    [[ "$res" == *"success"* ]] && echo -e "${GREEN}在线${NC}" || echo -e "${RED}离线${NC}"
}

get_patch_info() { 
    if [ ! -f "$TARGET_JS" ]; then 
        echo -e "${RED}未安装${NC}"
    else
        local v="已应用"
        [ -f "$ACTIVE_PATCH_FILE" ] && v=$(cat "$ACTIVE_PATCH_FILE")
        echo -e "${GREEN}$v${NC}"
    fi
}

get_autostart_info() { 
    if [ -f "$SERVICE_FILE" ]; then
        systemctl is-enabled adspower >/dev/null 2>&1 && echo -e "${GREEN}已开启${NC}" || echo -e "${YELLOW}已创建未启用${NC}"
    else 
        echo -e "${RED}未配置${NC}"
    fi
}

get_resource_usage() {
    local cpu=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    local mem=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    echo -e "CPU ${CYAN}${cpu}%${NC} / MEM ${CYAN}${mem}%${NC}"
}

get_masked_key() { 
    if [ -z "$API_KEY" ]; then 
        echo -e "${RED}未设置${NC}"
    else
        local len=${#API_KEY}
        local visible=$((len - 5))
        [ $visible -lt 0 ] && visible=0
        echo -e "${YELLOW}${API_KEY:0:$visible}*****${NC}"
    fi
}

check_kernel_installed() {
    local v=$1
    if [ -d "$KERNEL_ROOT/chrome_$v" ]; then
        echo -e "${GREEN}[已安装]${NC}"
    else
        echo -e "${RED}[未安装]${NC}"
    fi
}

get_vtok_status() {
    local cfg="$HOME/.openclaw/openclaw.json"
    if [ ! -f "$cfg" ]; then 
        echo -e "${RED}未安装${NC}"
        return
    fi
    
    if grep -q '"vtok-claude"' "$cfg" 2>/dev/null; then
        local key=$(grep -A 2 '"vtok-claude"' "$cfg" | grep 'apiKey' | sed 's/.*"\([^"]*\)".*/\1/' | head -c 8)
        echo -e "${GREEN}已配置 (${key}*****)${NC}"
    else
        echo -e "${RED}未配置${NC}"
    fi
}

download_kernel_api() {
    local version=$1
    echo -e "${YELLOW}>>> 正在请求 Chrome $version ...${NC}"
    local url="http://127.0.0.1:$API_PORT/api/v2/browser-profile/download-kernel"
    local json="{\"kernel_type\": \"Chrome\", \"kernel_version\": \"$version\"}"
    local RES=$(curl -s --location -g "$url" --header "Authorization: $API_KEY" --header "Content-Type: application/json" --data "$json")
    
    if [[ "$RES" != *"\"code\":0"* ]]; then 
        echo -e "${RED}请求失败: $RES${NC}"
        return
    fi
    
    while true; do
        sleep 2
        local r=$(curl -s --location -g "$url" --header "Authorization: $API_KEY" --header "Content-Type: application/json" --data "$json")
        local s=$(echo "$r" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        local p=$(echo "$r" | grep -o '"progress":[0-9]*' | cut -d':' -f2)
        [ -z "$p" ] && p=0
        
        echo -ne "\r\033[K状态 [Chrome $version]: ${YELLOW}$s ($p%)${NC}"
        
        [[ "$s" == "completed" ]] && {
            echo -e "\r\033[K${GREEN}✅ Chrome $version 安装成功！${NC}"
            break
        }
        
        [[ "$s" == "" ]] && {
            echo -e "\n${RED}API 无响应${NC}"
            break
        }
    done
}

kernel_menu() {
    if [ ! -f "$TARGET_JS" ]; then 
        echo -e "${RED}请先应用补丁！${NC}"
        return
    fi
    
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "      AdsPower 内核管理 v4.2"
    echo -e "${GREEN}========================================${NC}"
    echo -e "内核根目录: ${CYAN}$KERNEL_ROOT${NC}"
    echo "----------------------------------------"
    
    local vs=("145" "144" "143" "142" "141" "140" "139" "138" "137" "136")
    for i in "${!vs[@]}"; do 
        echo -e "$((i+1)). 下载 Chrome ${YELLOW}${vs[$i]}${NC} $(check_kernel_installed ${vs[$i]})"
    done
    
    echo -e "11. 自定义版本号"
    echo -e "0. 返回主菜单"
    echo -e "----------------------------------------"
    read -p "请输入选项 (支持多选 1,2): " k_in
    
    [[ -z "$k_in" || "$k_in" == "0" ]] && return
    
    local sels=$(echo "$k_in" | tr ',' ' ')
    for opt in $sels; do 
        if [[ "$opt" -ge 1 && "$opt" -le 10 ]]; then 
            download_kernel_api "${vs[$((opt-1))]}"
        elif [ "$opt" == "11" ]; then 
            read -p "版本号: " cv
            [ -n "$cv" ] && download_kernel_api "$cv"
        fi
    done
}

stop_adspower() { 
    systemctl stop adspower >/dev/null 2>&1
    pkill -f "adspower_global" || true
    pkill -f "xvfb-run" || true
    echo -e "${GREEN}服务已停止${NC}"
}

restart_adspower() { 
    stop_adspower
    sleep 2
    start_adspower
}

start_adspower() {
    load_config
    
    [ -z "$API_KEY" ] && {
        echo -e "${RED}未设置 Key${NC}"
        return
    }
    
    if ! pgrep -f "adspower_global" >/dev/null; then
        nohup xvfb-run -a "$ADSPOWER_EXEC" --headless=true --api-key="$API_KEY" --api-port=$API_PORT --no-sandbox --disable-gpu > /dev/null 2>&1 &
        echo -e "${YELLOW}正在启动...${NC}"
        sleep 8
    fi
}

toggle_autostart() {
    if [ -f "$SERVICE_FILE" ]; then 
        systemctl stop adspower
        systemctl disable adspower
        rm -f "$SERVICE_FILE"
        systemctl daemon-reload
    else
        load_config
        [ -z "$API_KEY" ] && return
        
        cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=AdsPower API
After=network.target
[Service]
Type=simple
User=root
Environment=DISPLAY=:99
ExecStart=/usr/bin/xvfb-run -a "$ADSPOWER_EXEC" --headless=true --api-key=$API_KEY --api-port=$API_PORT --no-sandbox --disable-gpu
Restart=always
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable adspower
        systemctl start adspower
    fi
}

patch_menu() {
    clear
    echo -e "${GREEN}补丁管理 v4.2${NC}"
    echo -e "1. 添加补丁链接"
    echo -e "2. 应用补丁 (需重启)"
    echo -e "0. 返回主菜单"
    
    read -p "选项: " o
    
    [ "$o" == "1" ] && {
        read -p "地址: " url
        v=$(echo "$url" | sed -n 's/.*\/\(v[0-9.]*\)_main.*/\1/p')
        [ -z "$v" ] && read -p "版本: " v
        [ -z "$v" ] && return
        
        grep -v "^$v|" "$PATCH_LIST" > "${PATCH_LIST}.tmp" 2>/dev/null
        echo "$v|$url" >> "${PATCH_LIST}.tmp"
        mv "${PATCH_LIST}.tmp" "$PATCH_LIST"
        wget -q --show-progress -O "$PATCH_DIR/main.min.js.$v" "$url"
    }
    
    [ "$o" == "2" ] && {
        i=1
        v_arr=()
        while IFS='|' read -r v url; do 
            v_arr+=("$v|$url")
            echo -e "$i. $v"
            ((i++))
        done < "$PATCH_LIST"
        
        read -p "编号: " p_c
        [ -z "$p_c" ] || [ "$p_c" == "0" ] && return
        
        sel="${v_arr[$((p_c-1))]}"
        vs=$(echo "$sel" | cut -d'|' -f1)
        us=$(echo "$sel" | cut -d'|' -f2)
        
        wget -q -nc -O "$PATCH_DIR/main.min.js.$vs" "$us"
        mkdir -p "$(dirname "$TARGET_JS")"
        [ -f "$TARGET_JS" ] && cp "$TARGET_JS" "$TARGET_JS.bak"
        cp "$PATCH_DIR/main.min.js.$vs" "$TARGET_JS"
        echo "$vs" > "$ACTIVE_PATCH_FILE"
        restart_adspower
    }
    
    [ "$o" != "0" ] && {
        echo "返回..."
        read -n 1
        patch_menu
    }
}

vtok_menu() {
    local cfg="$HOME/.openclaw/openclaw.json"
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "      VTok 模型配置 v4.2"
    echo -e "${GREEN}========================================${NC}"
    printf "当前状态 : %b\n" "$(get_vtok_status)"
    echo -e "${GREEN}----------------------------------------${NC}"
    echo -e "1. 配置 VTok Token（Claude + GPT + Gemini）"
    echo -e "2. 查看当前已配置的模型"
    echo -e "0. 返回主菜单"
    echo -e "----------------------------------------"
    
    read -p "请输入选项: " v_choice
    
    case $v_choice in
        1) vtok_setup ;;
        2) vtok_show ;;
        0) return ;;
    esac
    
    echo -e "\n按任意键继续..."
    read -n 1
    vtok_menu
}

vtok_setup() {
    local cfg="$HOME/.openclaw/openclaw.json"
    
    if [ ! -f "$cfg" ]; then
        echo -e "${RED}错误: 未找到 OpenClaw 配置文件${NC}"
        echo -e "${RED}路径: $cfg${NC}"
        return
    fi
    
    echo -e "${YELLOW}请输入您的 VTok Token:${NC}"
    read -r VTOK_TOKEN
    
    [ -z "$VTOK_TOKEN" ] && {
        echo -e "${RED}Token 不能为空${NC}"
        return
    }
    
    echo ""
    echo -e "${YELLOW}正在配置 VTok 模型...${NC}"
    
    # 使用纯 bash 构建配置
    build_vtok_config "$VTOK_TOKEN" "$cfg"
    
    echo -e "${GREEN}✅ VTok 配置成功！${NC}"
    echo ""
    echo -e "${YELLOW}已配置的模型:${NC}"
    echo -e "  • vtok-claude (opus, sonnet, haiku)"
    echo -e "  • vtok-openai (gpt-5.4, gpt-5.3, gpt-5.2)"
    echo -e "  • vtok-gemini (gemini-3.1-pro, gemini-3-pro, gemini-3-flash)"
    echo ""
    echo -e "${YELLOW}默认模型: vtok-claude/claude-sonnet-4-6${NC}"
    echo ""
    echo -e "${YELLOW}正在重启 OpenClaw Gateway...${NC}"
    
    if command -v openclaw &>/dev/null; then
        openclaw gateway restart && echo -e "${GREEN}✅ Gateway 已重启${NC}"
    else
        echo -e "${YELLOW}请手动重启 OpenClaw Gateway 以应用配置${NC}"
        echo -e "${CYAN}命令: openclaw gateway restart${NC}"
    fi
}

vtok_show() {
    local cfg="$HOME/.openclaw/openclaw.json"
    
    if [ ! -f "$cfg" ]; then
        echo -e "${RED}无法读取配置${NC}"
        return
    fi
    
    echo ""
    echo -e "${CYAN}当前已配置的 VTok 模型:${NC}"
    
    # 纯 bash 解析 JSON
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

openclaw_install() {
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "      OpenClaw 一键安装"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    if command -v openclaw &>/dev/null; then
        echo -e "${YELLOW}检测到 OpenClaw 已安装${NC}"
        openclaw --version 2>/dev/null || echo "版本信息获取失败"
        echo ""
        read -p "是否重新安装？(y/n): " reinstall
        [[ "$reinstall" != "y" ]] && return
    fi
    
    echo -e "${YELLOW}正在安装 OpenClaw...${NC}"
    echo ""
    
    bash <(curl -sL kejilion.sh) app openclaw
    
    echo ""
    if command -v openclaw &>/dev/null; then
        echo -e "${GREEN}✅ OpenClaw 安装成功！${NC}"
        openclaw --version
    else
        echo -e "${RED}❌ OpenClaw 安装失败${NC}"
    fi
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：此脚本需要 root 权限运行。${NC}"
        exit 1
    fi
}

main_menu() {
    load_config
    
    [ ! -f "$PATCH_LIST" ] && cat > "$PATCH_LIST" <<EOF
v2.8.4.4|https://version.adspower.net/software/lib_production/v2.8.4.4_main.min.js11bff97aadb92fc16a9abd79e1939518
v2.8.4.3|https://version.adspower.net/software/lib_production/v2.8.4.3_main.min.js07075aa4da52fd3c9f297b01a103cacb
EOF
    
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "      AdsPower Global 管理仪表盘 v4.2"
    echo -e "      ${CYAN}独立版 - 无外部依赖${NC}"
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
    echo -e "5. 检查 API 详情"
    echo -e "6. 切换开机自启"
    echo -e "7. 更换 API Key"
    echo -e "8. 补丁管理菜单"
    echo -e "9. 内核管理菜单"
    echo -e "10. ${CYAN}VTok 模型配置${NC}"
    echo -e "11. ${CYAN}安装 OpenClaw${NC}"
    echo -e "0. 退出脚本"
    echo -e "----------------------------------------"
    
    read -p "请输入选项: " choice
    
    case $choice in
        1) 
            apt update && apt install -y wget xvfb curl ss grep
            [ -z "$API_KEY" ] && read -p "Key: " API_KEY
            
            if [ ! -f "$ADSPOWER_EXEC" ]; then
                wget -P /tmp https://version.adspower.net/software/linux-x64-global/7.12.29/AdsPower-Global-7.12.29-x64.deb
                dpkg -i /tmp/AdsPower-Global-7.12.29-x64.deb || apt --fix-broken install -y
            fi
            
            chmod +x "$ADSPOWER_EXEC"
            start_adspower
            ;;
        2) start_adspower ;;
        3) stop_adspower ;;
        4) restart_adspower ;;
        5) 
            echo ""
            curl -s http://127.0.0.1:$API_PORT/status
            echo ""
            ;;
        6) toggle_autostart ;;
        7) 
            read -p "输入新 Key: " API_KEY
            save_config
            ;;
        8) patch_menu ;;
        9) kernel_menu ;;
        10) vtok_menu ;;
        11) openclaw_install ;;
        0) exit 0 ;;
    esac
    
    echo -e "\n按任意键继续..."
    read -n 1
    main_menu
}

check_root
main_menu

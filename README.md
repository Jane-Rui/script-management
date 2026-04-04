# 脚本管理

用于管理和维护 AdsPower 相关自动化脚本。

## 内容
- `adspower_mgr.sh`: AdsPower 管理主脚本（单文件 Bash）

## 功能
- 启动、停止、重启 AdsPower 服务
- 查看 API 状态与运行信息（摘要展示，不回显原始接口参数）
- 开机自启（systemd）开关
- 补丁管理（官方 API 更新最新补丁：stable/beta；本地补丁应用与失败回滚）
- Chrome 内核下载菜单
- 环境安装/修复（跨 Debian/RHEL，仅安装缺失依赖）
- 支持本地 `.deb` 或自动下载安装 AdsPower
- 自动创建命令软链接：`/usr/local/bin/adspower_global`
- 安装阶段支持同步更新 `main.min.js`（可开关）
- OpenClaw 上游菜单融合（通过 Kejilion 最新脚本实时进入）
- SkillHub 技能菜单（先检查 OpenClaw，再按 CLI-only 安装 SkillHub，并安装 `adspower-browser`）
- OpenCode 菜单：安装 OpenCode CLI，并设置“非删除操作默认放行、删除类命令需确认”授权策略

## 运行要求
- Linux 环境
- `root` 权限运行（脚本会检查）
- 常见命令：`curl`/`wget`、`xvfb-run`、`systemctl`
- OpenClaw 上游融合需要 `bash` + `curl` 可用

## 使用方式
```bash
chmod +x ./adspower_mgr.sh
sudo ./adspower_mgr.sh
```

## 快捷启动方式
- 本地仓库启动（已 clone 到服务器）：

```bash
cd /path/to/script-management
sudo bash ./adspower_mgr.sh
```

首次运行后会自动创建快捷命令（默认 `/usr/local/bin/ads`），后续可直接执行：

```bash
ads
```

- 远程一键启动（不落地文件，直接运行最新脚本）：

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/Jane-Rui/script-management/main/adspower_mgr.sh)
```

## 一键执行
适用于服务器快速拉取并启动脚本（默认从 `main` 分支获取最新版本，下载到当前目录）：

```bash
curl -fsSL https://raw.githubusercontent.com/Jane-Rui/script-management/main/adspower_mgr.sh -o ./adspower_mgr.sh && bash ./adspower_mgr.sh
```

如服务器未安装 `curl`，可使用：

```bash
wget -qO ./adspower_mgr.sh https://raw.githubusercontent.com/Jane-Rui/script-management/main/adspower_mgr.sh && bash ./adspower_mgr.sh
```

## 配置说明
脚本会在同目录生成配置文件 `adspower.env`：

```env
API_KEY="your_api_key"
API_PORT=50325
```

也支持通过环境变量覆盖关键路径（可选）：
- `ADSPOWER_INSTALL_PREFIX`
- `ADSPOWER_EXEC`
- `ADSPOWER_CONFIG_FILE`
- `ADSPOWER_SERVICE_FILE`
- `ADSPOWER_PATCH_DIR`
- `ADSPOWER_TARGET_JS`
- `ADSPOWER_DEB_PATH`
- `ADSPOWER_BIN_LINK_DIR`
- `ADSPOWER_MAIN_MIN_JS_URL`
- `ADSPOWER_MAIN_MIN_JS_DEST`
- `ADSPOWER_SYNC_MAIN_MIN_JS_ON_INSTALL`
- `SKILLHUB_INSTALL_SCRIPT_URL`
- `SKILLHUB_DEFAULT_SKILL`
- `OPENCODE_INSTALL_URL`
- `OPENCODE_CONFIG_DIR`
- `OPENCODE_CONFIG_FILE`
- `OPENCODE_BIN_LINK`

## 常见排障
- 启动后 API 不在线：
1. 检查 `API_KEY` 和 `API_PORT` 是否正确。
2. 检查 `xvfb-run` 是否已安装。
3. 查看日志 `/tmp/adspower_mgr_start.log`。

- systemd 无法启动：
1. 执行 `systemctl status adspower` 查看报错。
2. 确认 `ADSPOWER_EXEC` 路径是否存在且可执行。

- 补丁应用失败：
1. 检查补丁地址可访问性。
2. 检查目标文件路径和权限（`TARGET_JS`）。

- OpenClaw 菜单无法进入：
1. 检查服务器外网访问和 DNS。
2. 检查 `bash` 与 `curl` 是否可用。
3. 如果拉取地址受限，可通过环境变量覆盖：
   `KEJILION_BOOTSTRAP_URL=https://kejilion.sh`

- OpenCode 安装后命令不可用：
1. 重新进入菜单执行一次“安装 OpenCode 并应用默认授权策略”。
2. 检查 `OPENCODE_BIN_LINK` 是否在 `PATH` 中（默认 `/usr/local/bin/opencode`）。

# 脚本管理

用于管理和维护 AdsPower 相关自动化脚本。

## 内容
- `adspower_mgr.sh`: AdsPower 管理主脚本（单文件 Bash）

## 菜单功能
- 安装/修复 AdsPower
- 启动、停止、重启 AdsPower 服务
- 检查 API 详情
- 切换开机自启（systemd）
- 更换 API Key
- 补丁管理（显示当前补丁；官方 API 更新 stable/beta；本地补丁应用与失败回滚）
- Chrome 内核下载菜单
- OpenClaw 上游菜单融合（通过 Kejilion 最新脚本实时进入）
- OpenCode 安装与授权

## 内置行为
- 环境安装/修复支持 Debian/RHEL，仅安装缺失依赖，并带 apt 锁等待与重试
- 支持本地 `.deb` 或自动下载安装 AdsPower
- 自动创建命令软链接：`/usr/local/bin/adspower_global`
- 首次运行后自动创建快捷命令：`ads`
- 安装阶段支持同步更新 `main.min.js`（可开关）

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

- 远程一键启动（下载到当前目录后立即执行；若当前目录已存在 `adspower_mgr.sh`，会直接覆盖）：

```bash
curl -fsSL https://raw.githubusercontent.com/Jane-Rui/script-management/main/adspower_mgr.sh -o ./adspower_mgr.sh && bash ./adspower_mgr.sh
```

## 一键执行
适用于服务器快速拉取并启动脚本（默认从 `main` 分支获取最新版本，下载到当前目录；若已存在同名脚本会直接覆盖）：

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
- `OPENCODE_INSTALL_URL`
- `OPENCODE_CONFIG_DIR`
- `OPENCODE_CONFIG_FILE`
- `OPENCODE_BIN_LINK`
- `APT_LOCK_WAIT_SECONDS`
- `APT_RETRIES`
- `APT_HTTP_TIMEOUT`

## 常见排障
- 启动后 API 不在线：
1. 检查 `API_KEY` 和 `API_PORT` 是否正确。
2. 检查 `xvfb-run` 是否已安装。
3. 查看日志 `/tmp/adspower_mgr_start.log`。

- systemd 无法启动：
1. 执行 `systemctl status adspower` 查看报错。
2. 确认 `ADSPOWER_EXEC` 路径是否存在且可执行。

- 补丁应用失败：
1. 使用官方补丁 API 时需确保 AdsPower 服务已启动。
2. 若返回 `404 Not Found`，请先确认本机 AdsPower 版本与接口可用性。
3. 本地补丁应用失败时检查目标文件路径和权限（`TARGET_JS`）。

- 安装依赖时卡在 apt 锁：
1. 脚本会自动等待锁释放（默认 180 秒）并重试。
2. 可通过环境变量调节：`APT_LOCK_WAIT_SECONDS`、`APT_RETRIES`、`APT_HTTP_TIMEOUT`。

- OpenClaw 菜单无法进入：
1. 检查服务器外网访问和 DNS。
2. 检查 `bash` 与 `curl` 是否可用。
3. 如果拉取地址受限，可通过环境变量覆盖：
   `KEJILION_BOOTSTRAP_URL=https://kejilion.sh`

- OpenCode 安装后命令不可用：
1. 重新进入菜单执行一次“安装 OpenCode 并应用默认授权策略”。
2. 检查 `OPENCODE_BIN_LINK` 是否在 `PATH` 中（默认 `/usr/local/bin/opencode`）。

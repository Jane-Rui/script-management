# 脚本管理

用于管理和维护 AdsPower 相关自动化脚本。

## 内容
- `adspower_mgr.sh`: AdsPower 管理主脚本（单文件 Bash）

## 功能
- 启动、停止、重启 AdsPower 服务
- 查看 API 状态与运行信息（摘要展示，不回显原始接口参数）
- 开机自启（systemd）开关
- 补丁管理（添加补丁地址、应用补丁、失败回滚）
- Chrome 内核下载菜单
- 环境安装/修复（按系统自动安装基础依赖）
- OpenClaw 上游菜单融合（通过 Kejilion 最新脚本实时进入）

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

## 配置说明
脚本会在同目录生成配置文件 `adspower.env`：

```env
API_KEY="your_api_key"
API_PORT=50325
```

也支持通过环境变量覆盖关键路径（可选）：
- `ADSPOWER_EXEC`
- `ADSPOWER_CONFIG_FILE`
- `ADSPOWER_SERVICE_FILE`
- `ADSPOWER_PATCH_DIR`
- `ADSPOWER_TARGET_JS`

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

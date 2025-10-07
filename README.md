# FireWallBot

FireWallBot 是一个面向 Linux 主机的轻量化审计/观测工具集，通过可插拔的脚本模块采集安全相关事件。

## 模块概览

- **cmdwatcher** — 记录交互式 Bash 会话的命令轨迹（会话起止 + 每条命令）。详见 `scripts/cmdwatcher/README.md`。
- **syswatcher** — 审计 CPU 高占用与新的网络连接，输出到 JSONL。详见 `scripts/syswatcher/README.md`。
- **logkeeper** — 自动轮转 `log/*.jsonl`，压缩并保留历史归档。详见 `scripts/logkeeper/README.md`。

## 基本操作

- 安装或更新模块（需 root）：`sudo bash ./service.sh install [module]`
  - 不带模块名时安装全部可用模块。
- 查看模块状态：`bash ./service.sh status [module]`
- 卸载模块（需 root）：`sudo bash ./service.sh uninstall [module]`
- 默认日志目录：`log/`

## 日志滚动

- 推荐启用 **logkeeper** 服务：`sudo bash ./service.sh install logkeeper`。它会常驻监控 `log/*.jsonl`，单文件超过 20 MiB 即压缩为 `*.jsonl.gz` 并保留最近 10 个归档。
- 如果你想沿用系统级 `logrotate`，仓库也提供了示例配置 `packaging/logrotate/firewallbot`：
  ```bash
  sudo install -m 0644 packaging/logrotate/firewallbot /etc/logrotate.d/firewallbot
  sudo logrotate -f /etc/logrotate.d/firewallbot   # 可选：立即触发一次
  ```
  配置使用 `size 20M`、`rotate 10`、`compress`、`copytruncate` 等规则，可按需修改阈值或保留数量。

## 更多资料

- 模块说明：`scripts/<module>/README.md`
- 许可：参见 `LICENSE`

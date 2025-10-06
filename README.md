# FireWallBot

FireWallBot 是一个面向 Linux 主机的轻量化审计/观测工具集，通过可插拔的脚本模块采集安全相关事件。

## 模块概览

- **cmdwatcher** — 记录交互式 Bash 会话的命令轨迹（会话起止 + 每条命令）。详见 `scripts/cmdwatcher/README.md`。

## 基本操作

- 安装或更新模块（需 root）：`sudo bash ./service.sh install [module]`
  - 不带模块名时安装全部可用模块。
- 查看模块状态：`bash ./service.sh status [module]`
- 卸载模块（需 root）：`sudo bash ./service.sh uninstall [module]`
- 默认日志目录：`log/`

## 更多资料

- 模块说明：`scripts/<module>/README.md`
- 许可：参见 `LICENSE`

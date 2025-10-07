# FireWallBot

FireWallBot 是一个面向 Linux 主机的轻量化审计/观测工具集，通过可插拔的脚本模块采集安全相关事件。

## 模块概览

- **cmdwatcher** — 记录交互式 Bash 会话的命令轨迹（会话起止 + 每条命令）。详见 [README.md](scripts/cmdwatcher/README.md)。
- **syswatcher** — 审计 CPU 高占用与新的网络连接，输出到 JSONL。详见 [README.md](scripts/syswatcher/README.md)。
- **filewatcher** — 监控文件系统变化，记录文件创建、修改、删除等事件。详见 [README.md](scripts/filewatcher/README.md)。
- **logkeeper** — 自动轮转 `log/*.jsonl`，压缩并保留历史归档。详见 [README.md](scripts/logkeeper/README.md)。

## 基本操作

- 安装或更新模块（需 root）：`sudo bash ./service.sh install [module]`
  - 不带模块名时安装全部可用模块。
- 查看模块状态：`bash ./service.sh status [module]`
- 卸载模块（需 root）：`sudo bash ./service.sh uninstall [module]`
- 默认日志目录：`log/`

### 代理环境提示

- 如果主机需经由 HTTP/HTTPS 代理访问外网（例如安装 Python 依赖），请在执行安装命令前让代理环境变量对 `sudo` 可见，例如：
  - 临时方式：`export http_proxy=...; export https_proxy=...; sudo -E bash ./service.sh install filewatcher`
  - 永久方式：在 `/root/.bashrc` 或 `/etc/environment` 内设置 `http_proxy`/`https_proxy`，或在 `sudo visudo` 中添加 `Defaults env_keep += "http_proxy https_proxy"`。
  - 也可以直接在命令前显式传入：`sudo env "http_proxy=$http_proxy" "https_proxy=$https_proxy" bash ./service.sh install ...`

## 日志滚动

- 推荐启用 **logkeeper** 服务：`sudo bash ./service.sh install logkeeper`。它会常驻监控 `log/*.jsonl`，单文件超过 20 MiB 即压缩为 `*.jsonl.gz` 并保留最近 10 个归档。若需其他策略，可自行编写 systemd/timer 或 logrotate 规则。

## 更多资料

- 模块说明：[`scripts/<module>/README.md`](scripts)
- 许可：参见 `LICENSE`

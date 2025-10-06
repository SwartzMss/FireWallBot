# FireWallBot

用于在 Linux 服务器上“监听关键系统事件与基础资源状态”的轻量项目，面向安全审计与运维观测的常见需求。

## 能力范围

- 登录审计：用户何时从哪里以何种方式登录/登出、成功或失败
- 命令审计：谁在什么时间执行了哪些命令（按需启用）
- 资源监控：CPU/内存/负载等基础指标与热点进程概览
- 服务状态：systemd 单元的状态变化与失败重启情况
- 网络概览：常见监听端口与连接信息（按需启用）

## 数据来源

- 日志：journald/syslog（如 sshd、systemd-logind、sudo 等）
- 账户记录：wtmp/utmp/lastlog
- 命令审计：auditd 或 Shell 钩子（可选）
- 资源与网络：/proc 及常见系统工具
- 服务状态：systemd 提供的状态信息

## 部署形态

- 以脚本为主，便于审计与按需裁剪
- 可作为常驻守护（service）或定时任务（timer/cron）运行
- 输出为结构化本地日志，便于接入现有日志/监控系统

## 快速使用（systemd）

- 安装并启动（需 root）：`sudo bash ./service.sh install`
- 查看状态：`bash ./service.sh status`
- 卸载（需 root）：`sudo bash ./service.sh uninstall`
- 本地事件输出目录：`log/`

### 命令审计（cmdwatcher）说明

- `service.sh install` 会把 cmdwatcher 钩子写入 `/etc/profile.d/99-firewallbot-cmdwatcher.sh`，新开的 **登录型** Bash 会自动加载。
- 重新打开终端或执行 `bash -l` 以启用最新脚本；非登录 shell 若需启用，可在 `~/.bashrc` 末尾手动 `source /etc/profile.d/99-firewallbot-cmdwatcher.sh`。
- 日志写入 `log/commands.jsonl`（JSON Lines）。默认忽略 shell 自启动的 `. "$HOME/.cargo/env"` 等噪声命令，可在 `scripts/cmdwatcher/profile.sh` 的 `fwbot__should_ignore_command` 中按需扩展。
- 查看命令日志示例：`tail -f log/commands.jsonl`。
- 每条记录包含 `type=exec`、`cmd`、工作目录、退出码等字段，可直接被日志系统消费。

## 使用建议

- 先在测试环境启用，确认事件与指标满足诉求
- 按需启用模块，减少不必要的采集
- 注意最小权限与隐私合规，必要时对敏感字段做脱敏

## 路线图（摘要）

- 初版：登录/资源基础采集
- 进阶：命令审计与服务状态
- 对接：与常见日志/监控系统的简易集成说明

## 许可

参见 LICENSE。

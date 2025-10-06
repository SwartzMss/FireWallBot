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
- 查看日志：`journalctl -u firewallbot.service -f`
- 本地事件输出目录：`log/`

注：也可用脚本后台模式（适合临时测试）：`bash ./firewallbot.sh`

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

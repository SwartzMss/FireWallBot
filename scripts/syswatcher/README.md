syswatcher

功能
- 定时采样 `ps`，记录 CPU 占用超过阈值（默认 20%）的进程。
- 解析 `ss -tunapH` 的输出，捕获新的 TCP/UDP 连接（默认仅记录 ESTAB/SYN 状态且排除回环地址）。
- 所有事件写入仓库 `log/syswatcher.jsonl`，便于后续分析。

运行方式
- 通过 systemd unit `firewallbot-syswatcher.service` 常驻运行。
- 轮询间隔默认为 10 秒，可通过环境变量覆盖：
  - `FIREWALLBOT_POLL_INTERVAL`：采样间隔（秒）。
  - `FIREWALLBOT_CPU_THRESHOLD`：CPU 告警阈值（百分比）。
  - `FIREWALLBOT_CPU_COOLDOWN`：同一进程重复告警的冷却时间（秒）。
  - `FIREWALLBOT_NET_STATES`：需要记录的连接状态（逗号分隔，默认 `ESTAB,SYN-SENT,SYN-RECV`）。
  - `FIREWALLBOT_NET_INCLUDE_LOOPBACK`：设为 `1`/`true` 可记录回环连接。
  - `FIREWALLBOT_LOG_DIR` / `FIREWALLBOT_SYSWATCH_LOG`：自定义日志目录或文件。

事件格式
- CPU 告警：`{"kind":"cpu_high","pid":123,"cpu":34.5,"cwd":"/work",...}`（若可读取 `/proc/<pid>` 会附带 `cwd`、`cmdline`、`exe`；`ts` 已直接使用本地时区的 ISO8601）。
- 网络连接：`{"kind":"network_connection","remote_addr":"1.2.3.4","pid":234,...}`（同样尽量补充进程上下文）。
- 脚本启动/错误也会写入 `syswatcher_start` / `error` 事件便于排错。

安装
```
sudo bash ./service.sh install syswatcher
bash ./service.sh status syswatcher
```

卸载
```
sudo bash ./service.sh uninstall syswatcher
```

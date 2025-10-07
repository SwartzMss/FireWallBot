logkeeper

功能
- 轮询 `log/` 目录，检测匹配的日志文件（默认 `*.jsonl`）。
- 当文件大小超过 20 MiB 时，复制+压缩为 `*.jsonl.gz` 归档，并截断原文件。
- 仅保留最新 10 个归档，淘汰更早的历史。

运行方式
- 通过 systemd unit `firewallbot-logkeeper.service` 常驻运行。
- 可调环境变量：
  - `FIREWALLBOT_LOG_DIR`：日志目录（默认仓库 `log/`）。
  - `FIREWALLBOT_LOG_PATTERNS`：以逗号分隔的 glob 模式（默认 `*.jsonl`）。
  - `FIREWALLBOT_ROTATE_MAX_MB`：单文件阈值（MiB，默认 `20`）。
  - `FIREWALLBOT_ROTATE_KEEP`：归档保留数量（默认 `10`）。
  - `FIREWALLBOT_ROTATE_INTERVAL`：轮询间隔秒数（默认 `60`）。

安装
```
sudo bash ./service.sh install logkeeper
bash ./service.sh status logkeeper
```

卸载
```
sudo bash ./service.sh uninstall logkeeper
```

备注
- 归档名包含 UTC 时间戳，便于排序。例如：`commands-20250110T120000Z.jsonl.gz`。
- `syswatcher` 持续写入同一文件不会受影响，因为脚本采用“复制 + 截断”的方式，不需要重新打开文件。

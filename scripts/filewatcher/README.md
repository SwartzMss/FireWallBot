filewatcher

功能
- 实时监控文件系统变化，记录文件创建、修改、删除、移动和权限变更事件。
- 支持监控多个目录，可配置监控事件类型和排除模式。
- 所有事件写入仓库 `log/filewatcher.jsonl`，便于后续安全分析。

运行方式
- 通过 systemd unit `firewallbot-filewatcher.service` 常驻运行。
- 优先使用 Linux inotify 机制，备用 fswatch 工具。
- 可调环境变量：
  - `FIREWALLBOT_WATCH_DIRS`：监控目录列表（逗号分隔，默认 `/etc/,/root/,/usr/bin/,/usr/sbin/,/var/log/`）。
  - `FIREWALLBOT_WATCH_EVENTS`：监控事件类型（逗号分隔，默认 `IN_CREATE,IN_MODIFY,IN_DELETE,IN_MOVED_FROM,IN_MOVED_TO,IN_ATTRIB`）。
  - `FIREWALLBOT_EXCLUDE_PATTERNS`：排除文件模式（逗号分隔，默认 `*.tmp,*.log,*.swp,*.pid`）。
  - `FIREWALLBOT_LOG_DIR` / `FIREWALLBOT_FILEWATCH_LOG`：自定义日志目录或文件。

事件格式
- 文件事件：`{"kind":"file_event","event_type":"IN_CREATE","path":"/etc/newfile","size":1024,"mode":"644","user":"root",...}`
- 包含文件详细信息：大小、权限、所有者、修改时间等。
- `ts` 字段使用本地时区的 ISO8601 格式。
- 脚本启动/错误也会写入 `filewatcher_start` / `error` 事件便于排错。

监控事件类型
- `IN_CREATE`：文件/目录创建
- `IN_MODIFY`：文件内容修改
- `IN_DELETE`：文件/目录删除
- `IN_MOVED_FROM`：文件移动源
- `IN_MOVED_TO`：文件移动目标
- `IN_ATTRIB`：文件属性/权限变更

安装
```bash
sudo bash ./service.sh install filewatcher
bash ./service.sh status filewatcher
```

卸载
```bash
sudo bash ./service.sh uninstall filewatcher
```

依赖要求
- Python 3.6+
- inotify Python 包：`pip install inotify`
- 或 fswatch 工具：`apt install fswatch` (Ubuntu) / `brew install fswatch` (macOS)

安全注意事项
- 该模块需要 root 权限访问系统目录。
- 会记录敏感目录的文件变化，请确保符合组织合规要求。
- 建议在生产环境中配置适当的排除模式以减少日志噪音。

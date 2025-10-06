cmdwatcher

功能
- 记录交互式 Bash 会话中执行的每条命令（含时间、用户、IP、TTY、CWD、退出码、完整命令行）。
- 新会话开始时写入一条 `session_start` 事件（带会话 `sid`、pid/ppid 等），便于串联后续命令。

实现机制
- 通过 /etc/profile.d 注入一个 profile 钩子（profile.sh），为登录 shell 配置 DEBUG trap 和 PROMPT_COMMAND。
- 新打开的 Bash 登录会话会自动生效；已打开的会话不会补录。

输出
- JSON Lines 到仓库根目录的 `log/commands.jsonl`：
  - `session_start`：会话开始标记，字段含 `sid` 用于关联
  - `session_stop`：会话结束，附带退出码、最后工作目录等
  - `exec`：每条命令记录；若存在 `sid` 字段，与会话关联
- 可通过 `FIREWALLBOT_LOG_DIR`/`FIREWALLBOT_CMD_LOG` 环境变量覆盖目录或文件名。
- 默认忽略 shell 自启动的 `. "$HOME/.cargo/env"` 等噪声命令，可在 `profile.sh` 的 `fwbot__should_ignore_command` 中扩展模式。

安装与管理
- 安装（需要 root）：`sudo bash ./service.sh install cmdwatcher`
- 查看状态：`bash ./service.sh status cmdwatcher`
- 卸载（需要 root）：`sudo bash ./service.sh uninstall cmdwatcher`
- 修改脚本后需重新打开登录型 shell（或执行 `bash -l`）以加载最新钩子。

使用提示（WSL/常规 Bash）
- 登录 shell（例如新开 WSL 终端或执行 `bash -l`）会加载 `/etc/profile.d/*.sh`，命令记录生效。
- 非登录的交互式 Bash 通常不加载 `/etc/profile.d`。如需强制，可在个人 `~/.bashrc` 手动 source 模块脚本，或联系维护者调整为写入 `/etc/bash.bashrc`。

隐私与合规
- 该模块会记录完整命令行参数，可能包含敏感信息。请在符合组织合规的前提下启用，必要时进行脱敏或限制范围。

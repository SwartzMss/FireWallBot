loginwatcher

功能
- 监听 sshd 登录事件（成功/失败），记录时间、用户、来源 IP、方式。

数据来源
- 优先解析 journald（journalctl -u sshd -o json -f）
- 回退解析 /var/log/auth.log（tail -F）

输出
- JSON Lines，默认写入仓库根目录下的 `log/logins.jsonl`
- 可通过环境变量 `FIREWALLBOT_LOG_DIR` 覆盖输出目录

部署（借助仓库根的 service.sh）
- 安装并启动：`sudo bash ./service.sh install loginwatcher`
- 查看状态：`bash ./service.sh status loginwatcher`
- 卸载：`sudo bash ./service.sh uninstall loginwatcher`

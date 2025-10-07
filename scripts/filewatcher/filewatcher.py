#!/usr/bin/env python3
"""FireWallBot file system watcher for monitoring file changes."""
from __future__ import annotations

import datetime as _dt
import json
import os
import pathlib
import re
import subprocess
import sys
import time
from typing import Dict, List, Optional, Set

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
LOG_DIR = pathlib.Path(os.getenv("FIREWALLBOT_LOG_DIR", str(REPO_ROOT / "log")))
LOG_FILE = pathlib.Path(os.getenv("FIREWALLBOT_FILEWATCH_LOG", str(LOG_DIR / "filewatcher.jsonl")))

# 默认监控目录
DEFAULT_WATCH_DIRS = [
    "/etc/",
    "/root/",
    "/usr/bin/",
    "/usr/sbin/",
    "/var/log/"
]

# 默认监控事件
DEFAULT_EVENTS = [
    "IN_CREATE",
    "IN_MODIFY", 
    "IN_DELETE",
    "IN_MOVED_FROM",
    "IN_MOVED_TO",
    "IN_ATTRIB"
]

# 配置参数
WATCH_DIRS = os.getenv("FIREWALLBOT_WATCH_DIRS", ",".join(DEFAULT_WATCH_DIRS)).split(",")
WATCH_DIRS = [d.strip() for d in WATCH_DIRS if d.strip()]
WATCH_EVENTS = os.getenv("FIREWALLBOT_WATCH_EVENTS", ",".join(DEFAULT_EVENTS)).split(",")
WATCH_EVENTS = [e.strip() for e in WATCH_EVENTS if e.strip()]
EXCLUDE_PATTERNS = os.getenv("FIREWALLBOT_EXCLUDE_PATTERNS", "*.tmp,*.log,*.swp").split(",")
EXCLUDE_PATTERNS = [p.strip() for p in EXCLUDE_PATTERNS if p.strip()]

LOG_DIR.mkdir(parents=True, exist_ok=True)


def iso_local(ts: Optional[float] = None) -> str:
    """生成本地时区的 ISO8601 时间戳"""
    moment = _dt.datetime.fromtimestamp(ts or time.time(), tz=_dt.timezone.utc).astimezone()
    return moment.replace(microsecond=0).isoformat()


def write_event(handle, event: Dict) -> None:
    """写入事件到日志文件"""
    line = json.dumps(event, ensure_ascii=False)
    handle.write(line + "\n")
    handle.flush()


def should_exclude_file(filepath: str) -> bool:
    """检查文件是否应该被排除"""
    filename = os.path.basename(filepath)
    for pattern in EXCLUDE_PATTERNS:
        if pattern.startswith("*") and pattern.endswith("*"):
            # 包含匹配
            if pattern[1:-1] in filename:
                return True
        elif pattern.startswith("*"):
            # 后缀匹配
            if filename.endswith(pattern[1:]):
                return True
        elif pattern.endswith("*"):
            # 前缀匹配
            if filename.startswith(pattern[:-1]):
                return True
        else:
            # 精确匹配
            if filename == pattern:
                return True
    return False


def get_file_info(filepath: str) -> Dict:
    """获取文件详细信息"""
    info = {}
    try:
        stat = os.stat(filepath)
        info.update({
            "size": stat.st_size,
            "mode": oct(stat.st_mode)[-3:],
            "uid": stat.st_uid,
            "gid": stat.st_gid,
            "mtime": iso_local(stat.st_mtime),
            "ctime": iso_local(stat.st_ctime)
        })
        
        # 获取用户名和组名
        try:
            import pwd
            info["user"] = pwd.getpwuid(stat.st_uid).pw_name
        except (ImportError, KeyError):
            pass
            
        try:
            import grp
            info["group"] = grp.getgrgid(stat.st_gid).gr_name
        except (ImportError, KeyError):
            pass
            
    except (OSError, IOError):
        pass
        
    return info


def monitor_with_inotify() -> None:
    """使用 inotify 监控文件系统"""
    try:
        import inotify.adapters
    except ImportError:
        write_event(sys.stderr, {
            "ts": iso_local(),
            "kind": "error",
            "message": "inotify module not available. Install with: pip install inotify"
        })
        return
    
    # 验证监控目录
    valid_dirs = []
    for watch_dir in WATCH_DIRS:
        if os.path.exists(watch_dir) and os.path.isdir(watch_dir):
            valid_dirs.append(watch_dir)
        else:
            print(f"Warning: Directory {watch_dir} does not exist or is not a directory", file=sys.stderr)
    
    if not valid_dirs:
        write_event(sys.stderr, {
            "ts": iso_local(),
            "kind": "error", 
            "message": "No valid directories to monitor"
        })
        return
    
    # 创建 inotify 监控器
    try:
        i = inotify.adapters.InotifyTree(valid_dirs)
    except Exception as e:
        write_event(sys.stderr, {
            "ts": iso_local(),
            "kind": "error",
            "message": f"Failed to create inotify watcher: {e}"
        })
        return
    
    with LOG_FILE.open("a", encoding="utf-8") as handle:
        write_event(handle, {
            "ts": iso_local(),
            "kind": "filewatcher_start",
            "watch_dirs": valid_dirs,
            "watch_events": WATCH_EVENTS,
            "exclude_patterns": EXCLUDE_PATTERNS
        })
        
        for event in i.event_gen():
            if event is not None:
                (header, type_names, watch_path, filename) = event
                
                # 构建完整文件路径
                if filename:
                    full_path = os.path.join(watch_path, filename)
                else:
                    full_path = watch_path
                
                # 检查是否应该排除
                if should_exclude_file(full_path):
                    continue
                
                # 获取文件信息
                file_info = get_file_info(full_path)
                
                # 构建事件记录
                event_record = {
                    "ts": iso_local(),
                    "kind": "file_event",
                    "event_type": type_names[0] if type_names else "UNKNOWN",
                    "path": full_path,
                    "watch_path": watch_path,
                    "filename": filename,
                    "mask": header.mask,
                    "cookie": header.cookie if hasattr(header, 'cookie') else None
                }
                
                # 添加文件信息
                event_record.update(file_info)
                
                # 特殊处理移动事件
                if "IN_MOVED_FROM" in type_names:
                    event_record["event_type"] = "MOVED_FROM"
                elif "IN_MOVED_TO" in type_names:
                    event_record["event_type"] = "MOVED_TO"
                
                write_event(handle, event_record)


def monitor_with_fswatch() -> None:
    """使用 fswatch 作为备用方案"""
    try:
        # 检查 fswatch 是否可用
        subprocess.run(["fswatch", "--version"], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        write_event(sys.stderr, {
            "ts": iso_local(),
            "kind": "error",
            "message": "fswatch not available. Install with: brew install fswatch (macOS) or apt install fswatch (Ubuntu)"
        })
        return
    
    # 构建 fswatch 命令
    cmd = ["fswatch", "-o", "--event-flags"]
    cmd.extend(WATCH_DIRS)
    
    with LOG_FILE.open("a", encoding="utf-8") as handle:
        write_event(handle, {
            "ts": iso_local(),
            "kind": "filewatcher_start",
            "method": "fswatch",
            "watch_dirs": WATCH_DIRS
        })
        
        try:
            process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            
            for line in process.stdout:
                line = line.strip()
                if line:
                    parts = line.split()
                    if len(parts) >= 2:
                        filepath = parts[0]
                        flags = parts[1]
                        
                        if should_exclude_file(filepath):
                            continue
                        
                        file_info = get_file_info(filepath)
                        
                        event_record = {
                            "ts": iso_local(),
                            "kind": "file_event",
                            "event_type": flags,
                            "path": filepath,
                            "method": "fswatch"
                        }
                        event_record.update(file_info)
                        
                        write_event(handle, event_record)
                        
        except Exception as e:
            write_event(handle, {
                "ts": iso_local(),
                "kind": "error",
                "message": f"fswatch error: {e}"
            })


def main() -> int:
    """主函数"""
    print(f"FireWallBot FileWatcher starting...")
    print(f"Watch directories: {WATCH_DIRS}")
    print(f"Watch events: {WATCH_EVENTS}")
    print(f"Exclude patterns: {EXCLUDE_PATTERNS}")
    print(f"Log file: {LOG_FILE}")
    
    try:
        # 优先使用 inotify
        monitor_with_inotify()
    except KeyboardInterrupt:
        print("\nFileWatcher stopped by user")
        return 0
    except Exception as e:
        print(f"Error in inotify monitoring: {e}")
        print("Falling back to fswatch...")
        try:
            monitor_with_fswatch()
        except Exception as e2:
            print(f"Error in fswatch monitoring: {e2}")
            return 1
    
    return 0


if __name__ == "__main__":
    sys.exit(main())

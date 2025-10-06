#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
Login watcher: follow sshd logs and emit JSONL records with time, user, and IP.

Primary source: journald (journalctl -u sshd -o json -f)
Fallback: tail -F /var/log/auth.log (parse plain text)

Output: log/logins.jsonl (relative to repo) unless FIREWALLBOT_LOG_DIR is set.
"""

import datetime as _dt
import json
import os
import re
import signal
import subprocess
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
DEFAULT_LOG_DIR = Path(os.environ.get("FIREWALLBOT_LOG_DIR", REPO_ROOT / "log"))
DEFAULT_LOG_DIR.mkdir(parents=True, exist_ok=True)
OUT_FILE = DEFAULT_LOG_DIR / "logins.jsonl"


ACCEPTED_RE = re.compile(
    r"Accepted\s+(?P<method>password|publickey|keyboard-interactive(?:/pam)?)\s+for\s+(?P<user>\S+)\s+from\s+(?P<ip>[0-9a-fA-F\.:]+)\s+port\s+(?P<port>\d+)",
    re.IGNORECASE,
)
FAILED_RE = re.compile(
    r"Failed\s+(?:password|publickey|keyboard-interactive(?:/pam)?)\s+for\s+(?:invalid user\s+)?(?P<user>\S+)\s+from\s+(?P<ip>[0-9a-fA-F\.:]+)\s+port\s+(?P<port>\d+)",
    re.IGNORECASE,
)


def _iso_utc(ts: float) -> str:
    return _dt.datetime.utcfromtimestamp(ts).replace(tzinfo=_dt.timezone.utc).isoformat().replace("+00:00", "Z")


def _write_jsonl(obj: dict) -> None:
    with OUT_FILE.open("a", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def _from_journald() -> int:
    """Follow journald for sshd and parse events. Returns exit code or raises."""
    cmd = [
        "journalctl",
        "-u",
        "sshd",
        "-o",
        "json",
        "-n",
        "0",
        "-f",
        "--no-pager",
    ]
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    except FileNotFoundError:
        return 127

    assert proc.stdout is not None

    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue

        msg = rec.get("MESSAGE", "")
        if not msg:
            continue

        # Real-time timestamp in usec
        ts_usec = rec.get("__REALTIME_TIMESTAMP")
        if ts_usec is not None:
            try:
                ts = int(ts_usec) / 1_000_000.0
            except Exception:
                ts = _dt.datetime.utcnow().timestamp()
        else:
            ts = _dt.datetime.utcnow().timestamp()

        m = ACCEPTED_RE.search(msg)
        if m:
            d = m.groupdict()
            _write_jsonl({
                "type": "login",
                "ts": _iso_utc(ts),
                "user": d.get("user"),
                "from_ip": d.get("ip"),
                "method": f"ssh:{d.get('method')}",
                "result": "success",
            })
            continue

        m = FAILED_RE.search(msg)
        if m:
            d = m.groupdict()
            _write_jsonl({
                "type": "login",
                "ts": _iso_utc(ts),
                "user": d.get("user"),
                "from_ip": d.get("ip"),
                "method": "ssh",
                "result": "failure",
            })
            continue

    return proc.wait()


def _from_auth_log() -> int:
    auth_path = os.environ.get("FIREWALLBOT_AUTH_LOG", "/var/log/auth.log")
    if not os.path.exists(auth_path):
        return 2
    cmd = ["tail", "-n", "0", "-F", auth_path]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    assert proc.stdout is not None
    for line in proc.stdout:
        msg = line.strip()
        if not msg:
            continue
        now_ts = _dt.datetime.utcnow().timestamp()
        m = ACCEPTED_RE.search(msg)
        if m:
            d = m.groupdict()
            _write_jsonl({
                "type": "login",
                "ts": _iso_utc(now_ts),
                "user": d.get("user"),
                "from_ip": d.get("ip"),
                "method": f"ssh:{d.get('method')}",
                "result": "success",
            })
            continue
        m = FAILED_RE.search(msg)
        if m:
            d = m.groupdict()
            _write_jsonl({
                "type": "login",
                "ts": _iso_utc(now_ts),
                "user": d.get("user"),
                "from_ip": d.get("ip"),
                "method": "ssh",
                "result": "failure",
            })
            continue
    return proc.wait()


def main() -> int:
    # Graceful shutdown
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: sys.exit(0))

    rc = _from_journald()
    if rc in (0, None):
        return 0
    # Fallback
    return _from_auth_log()


if __name__ == "__main__":
    sys.exit(main())

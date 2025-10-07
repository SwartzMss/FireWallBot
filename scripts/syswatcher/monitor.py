#!/usr/bin/env python3
"""FireWallBot system watcher for CPU and network activity."""
from __future__ import annotations

import datetime as _dt
import json
import os
import pathlib
import re
import subprocess
import sys
import time
from typing import Dict, List, Optional, Sequence, Set, Tuple

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
LOG_DIR = pathlib.Path(os.getenv("FIREWALLBOT_LOG_DIR", str(REPO_ROOT / "log")))
LOG_FILE = pathlib.Path(os.getenv("FIREWALLBOT_SYSWATCH_LOG", str(LOG_DIR / "syswatcher.jsonl")))
POLL_INTERVAL = float(os.getenv("FIREWALLBOT_POLL_INTERVAL", "10"))
CPU_THRESHOLD = float(os.getenv("FIREWALLBOT_CPU_THRESHOLD", "20"))
CPU_COOLDOWN = float(os.getenv("FIREWALLBOT_CPU_COOLDOWN", "60"))
NET_STATE_FILTER: Set[str] = {
    state.strip().upper()
    for state in os.getenv("FIREWALLBOT_NET_STATES", "ESTAB,SYN-SENT,SYN-RECV").split(",")
    if state.strip()
}
INCLUDE_LOOPBACK = os.getenv("FIREWALLBOT_NET_INCLUDE_LOOPBACK", "0").lower() in {"1", "true", "yes"}

LOG_DIR.mkdir(parents=True, exist_ok=True)

PS_CMD: Sequence[str] = (
    "ps",
    "-eo",
    "pid=,ppid=,%cpu=,%mem=,command=",
)
SS_CMD: Sequence[str] = (
    "ss",
    "-tunapH",
)
USERS_RE = re.compile(r"users:\(\(([^\)]+)\)\)")
PROCESS_RE = re.compile(r"\"(?P<name>[^\"]+)\",pid=(?P<pid>\d+)")


def iso_utc(ts: Optional[float] = None) -> str:
    return _dt.datetime.utcfromtimestamp(ts or time.time()).replace(microsecond=0).isoformat() + "Z"


def write_event(handle, event: Dict) -> None:
    line = json.dumps(event, ensure_ascii=False)
    handle.write(line + "\n")
    handle.flush()
    print(line, flush=True)


def run_command(cmd: Sequence[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def tz_context(ts: Optional[float] = None) -> Dict[str, Optional[str]]:
    moment = _dt.datetime.fromtimestamp(ts or time.time(), tz=_dt.timezone.utc).astimezone()
    return {
        "ts_local": moment.isoformat(),
        "tz_offset": moment.strftime("%z"),
        "tz_name": moment.tzname(),
    }


def proc_context(pid: int) -> Dict[str, Optional[str]]:
    ctx: Dict[str, Optional[str]] = {"cwd": None, "cmdline": None, "exe": None}
    base = pathlib.Path("/proc") / str(pid)
    try:
        ctx["cwd"] = os.readlink(base / "cwd")
    except OSError:
        pass
    try:
        raw = (base / "cmdline").read_bytes()
    except OSError:
        pass
    else:
        parts = [seg.decode("utf-8", "replace") for seg in raw.split(b"\0") if seg]
        if parts:
            ctx["cmdline"] = " ".join(parts)
    try:
        ctx["exe"] = os.readlink(base / "exe")
    except OSError:
        pass
    return ctx


def sample_cpu(threshold: float) -> List[Dict]:
    proc = run_command(PS_CMD)
    if proc.returncode != 0:
        raise RuntimeError(f"ps failed rc={proc.returncode}: {proc.stderr.strip()}")
    findings: List[Dict] = []
    for line in proc.stdout.splitlines():
        if not line.strip():
            continue
        parts = line.strip().split(None, 4)
        if len(parts) < 5:
            continue
        try:
            pid = int(parts[0])
            ppid = int(parts[1])
            cpu = float(parts[2])
            mem = float(parts[3])
        except ValueError:
            continue
        if cpu < threshold:
            continue
        cmdline = parts[4]
        findings.append(
            {
                "pid": pid,
                "ppid": ppid,
                "cpu": round(cpu, 2),
                "mem": round(mem, 2),
                "cmd": cmdline,
            }
        )
    return findings


def split_host_port(value: str) -> Tuple[str, str]:
    value = value.strip()
    if not value:
        return "", ""
    if value.startswith("["):
        host, _, rest = value.partition("]")
        host = host.lstrip("[")
        port = rest[1:] if rest.startswith(":") else ""
        return host, port
    if value.count(":") > 1:
        host, _, port = value.rpartition(":")
        return host, port
    host, _, port = value.partition(":")
    return host, port


def is_loopback(addr: str) -> bool:
    if addr in {"::", "::1", "0.0.0.0"}:
        return True
    return addr.startswith("127.")


def parse_ss_line(line: str) -> Optional[Dict]:
    if not line or " " not in line or line.startswith("Cannot open"):
        return None
    parts = line.split()
    if len(parts) < 6:
        return None
    proto = parts[0].lower()
    state = parts[1].upper()
    local = parts[4]
    remote = parts[5]
    host_local, port_local = split_host_port(local)
    host_remote, port_remote = split_host_port(remote)
    if not host_remote or port_remote in {"*", ""}:
        return None
    if not INCLUDE_LOOPBACK and is_loopback(host_remote):
        return None
    if NET_STATE_FILTER and state not in NET_STATE_FILTER:
        return None
    match = USERS_RE.search(line)
    proc_name = None
    proc_pid: Optional[int] = None
    if match:
        proc_block = match.group(1)
        proc_match = PROCESS_RE.search(proc_block)
        if proc_match:
            proc_name = proc_match.group("name")
            proc_pid = int(proc_match.group("pid"))
    return {
        "proto": proto,
        "state": state,
        "local_addr": host_local,
        "local_port": port_local,
        "remote_addr": host_remote,
        "remote_port": port_remote,
        "process": proc_name,
        "pid": proc_pid,
    }


def sample_connections() -> List[Dict]:
    proc = run_command(SS_CMD)
    if proc.returncode != 0:
        raise RuntimeError(f"ss failed rc={proc.returncode}: {proc.stderr.strip()}")
    findings: List[Dict] = []
    for raw in proc.stdout.splitlines():
        parsed = parse_ss_line(raw)
        if parsed is None:
            continue
        findings.append(parsed)
    return findings


def main() -> int:
    last_cpu_alert: Dict[Tuple[int, str], float] = {}
    known_connections: Set[Tuple[str, str, str, str, str, Optional[int]]] = set()
    cooldown_cleanup_interval = max(CPU_COOLDOWN * 3, POLL_INTERVAL * 6)
    last_cleanup = time.time()
    with LOG_FILE.open("a", encoding="utf-8") as handle:
        start_info = {"ts": iso_utc(), "kind": "syswatcher_start", "poll_interval": POLL_INTERVAL}
        start_info.update({k: v for k, v in tz_context().items() if v})
        write_event(handle, start_info)
        while True:
            loop_started = time.time()
            ts = iso_utc(loop_started)
            tz_info = {k: v for k, v in tz_context(loop_started).items() if v}
            try:
                cpu_findings = sample_cpu(CPU_THRESHOLD)
            except Exception as exc:  # noqa: BLE001
                err_event = {"ts": ts, "kind": "error", "source": "cpu", "message": str(exc)}
                err_event.update(tz_info)
                write_event(handle, err_event)
                cpu_findings = []
            active_keys: Set[Tuple[int, str]] = set()
            for item in cpu_findings:
                key = (item["pid"], item["cmd"])
                active_keys.add(key)
                last = last_cpu_alert.get(key, 0.0)
                if loop_started - last < CPU_COOLDOWN:
                    continue
                context = proc_context(item["pid"])
                event = {
                    "ts": ts,
                    "kind": "cpu_high",
                    "pid": item["pid"],
                    "ppid": item["ppid"],
                    "process": item["cmd"],
                    "cpu": item["cpu"],
                    "mem": item["mem"],
                    "threshold": CPU_THRESHOLD,
                }
                if context["cwd"]:
                    event["cwd"] = context["cwd"]
                if context["cmdline"]:
                    event["cmdline"] = context["cmdline"]
                if context["exe"]:
                    event["exe"] = context["exe"]
                event.update(tz_info)
                write_event(handle, event)
                last_cpu_alert[key] = loop_started
            if loop_started - last_cleanup >= cooldown_cleanup_interval:
                for key in list(last_cpu_alert):
                    if key not in active_keys and loop_started - last_cpu_alert[key] > cooldown_cleanup_interval:
                        del last_cpu_alert[key]
                last_cleanup = loop_started
            try:
                conn_findings = sample_connections()
            except Exception as exc:  # noqa: BLE001
                err_event = {"ts": ts, "kind": "error", "source": "network", "message": str(exc)}
                err_event.update(tz_info)
                write_event(handle, err_event)
                conn_findings = []
            current_keys: Set[Tuple[str, str, str, str, str, Optional[int]]] = set()
            for conn in conn_findings:
                key = (
                    conn["proto"],
                    conn["local_addr"],
                    conn["local_port"],
                    conn["remote_addr"],
                    conn["remote_port"],
                    conn["pid"],
                )
                current_keys.add(key)
                if key in known_connections:
                    continue
                event = {
                    "ts": ts,
                    "kind": "network_connection",
                    "proto": conn["proto"],
                    "state": conn["state"],
                    "local_addr": conn["local_addr"],
                    "local_port": conn["local_port"],
                    "remote_addr": conn["remote_addr"],
                    "remote_port": conn["remote_port"],
                }
                if conn["pid"] is not None:
                    event["pid"] = conn["pid"]
                    context = proc_context(conn["pid"])
                    if context["cwd"]:
                        event["cwd"] = context["cwd"]
                    if context["cmdline"]:
                        event["cmdline"] = context["cmdline"]
                    if context["exe"]:
                        event["exe"] = context["exe"]
                if conn["process"]:
                    event["process"] = conn["process"]
                event.update(tz_info)
                write_event(handle, event)
            known_connections = current_keys
            elapsed = time.time() - loop_started
            sleep_for = max(0.0, POLL_INTERVAL - elapsed)
            time.sleep(sleep_for)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        pass

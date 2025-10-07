#!/usr/bin/env python3
"""FireWallBot log rotation helper."""
from __future__ import annotations

import datetime as _dt
import gzip
import os
import pathlib
import shutil
import time
from typing import Iterable, List, Sequence

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
LOG_DIR = pathlib.Path(os.getenv("FIREWALLBOT_LOG_DIR", str(REPO_ROOT / "log")))
PATTERNS: Sequence[str] = [p.strip() for p in os.getenv("FIREWALLBOT_LOG_PATTERNS", "*.jsonl").split(",") if p.strip()]
MAX_BYTES = int(float(os.getenv("FIREWALLBOT_ROTATE_MAX_MB", "20")) * 1024 * 1024)
MAX_ARCHIVES = int(os.getenv("FIREWALLBOT_ROTATE_KEEP", "10"))
POLL_INTERVAL = float(os.getenv("FIREWALLBOT_ROTATE_INTERVAL", "60"))

LOG_DIR.mkdir(parents=True, exist_ok=True)


def iter_targets() -> Iterable[pathlib.Path]:
    if not PATTERNS:
        return []
    for pattern in PATTERNS:
        yield from LOG_DIR.glob(pattern)


def archive_name(path: pathlib.Path) -> pathlib.Path:
    timestamp = _dt.datetime.utcnow().strftime("%Y%m%dT%H%M%S%fZ")
    candidate = path.with_name(f"{path.stem}-{timestamp}{path.suffix}.gz")
    counter = 1
    while candidate.exists():
        candidate = path.with_name(f"{path.stem}-{timestamp}-{counter}{path.suffix}.gz")
        counter += 1
    return candidate


def rotate_file(path: pathlib.Path) -> None:
    try:
        stat = path.stat()
    except FileNotFoundError:
        return
    if stat.st_size < MAX_BYTES:
        return
    archive_path = archive_name(path)
    tmp_archive = archive_path.with_suffix(archive_path.suffix + ".tmp")
    try:
        with path.open("rb") as src, gzip.open(tmp_archive, "wb") as dst:
            shutil.copyfileobj(src, dst)
        tmp_archive.rename(archive_path)
    finally:
        if tmp_archive.exists():
            tmp_archive.unlink(missing_ok=True)
    with path.open("wb"):
        pass
    print(f"[logkeeper] rotated {path.name} -> {archive_path.name}")
    enforce_retention(path)


def enforce_retention(path: pathlib.Path) -> None:
    pattern = f"{path.stem}-*{path.suffix}.gz"
    archives: List[pathlib.Path] = sorted(LOG_DIR.glob(pattern))
    excess = len(archives) - MAX_ARCHIVES
    for victim in archives[:max(0, excess)]:
        try:
            victim.unlink()
            print(f"[logkeeper] removed old archive {victim.name}")
        except FileNotFoundError:
            continue


def main() -> int:
    print(
        "[logkeeper] starting:"
        f" dir={LOG_DIR} patterns={','.join(PATTERNS) or '<none>'} max_bytes={MAX_BYTES}"
        f" keep={MAX_ARCHIVES} interval={POLL_INTERVAL}s"
    )
    while True:
        for target in iter_targets():
            if target.is_file():
                rotate_file(target)
        time.sleep(POLL_INTERVAL)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

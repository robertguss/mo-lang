"""Lead acceptance runner; retain statuses and contain each owned process group."""
from datetime import datetime
import json
import os
from pathlib import Path
import signal
import subprocess
import time
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent / "attempt-03"
HERE.mkdir(exist_ok=False)
GUARD = ["python3", str(ROOT / "toolchain/bench/step36/guard.py")]


def members(pgid):
    rows = subprocess.check_output(["ps", "-axo", "pid=,pgid=,command="], text=True).splitlines()
    return [r.strip() for r in rows if len(r.split(None, 2)) == 3 and r.split(None, 2)[1] == str(pgid)]


def now():
    return datetime.now(ZoneInfo("America/New_York")).isoformat()


commands = [
    ("build", 300, ROOT / "toolchain", ["zig", "build", "-j2"]),
    ("native-suite", 1200, ROOT / "toolchain", ["zig", "build", "test", "-j2", "--summary", "all"]),
]

identity = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
(HERE / "integrated-commit.txt").write_text(identity + "\n")
failed = False
for name, limit, cwd, command in commands:
    started = now()
    argv = GUARD + [str(limit), "--"] + command
    with (HERE / (name + ".stdout.txt")).open("w") as out, (HERE / (name + ".stderr.txt")).open("w") as err:
        process = subprocess.Popen(argv, cwd=cwd, stdout=out, stderr=err, start_new_session=True)
        forced = False
        try:
            code = process.wait(timeout=limit + 15)
        except subprocess.TimeoutExpired:
            forced = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                code = process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                code = process.wait(timeout=3)
        before = members(process.pid)
        if before:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            time.sleep(1)
            if members(process.pid):
                os.killpg(process.pid, signal.SIGKILL)
                time.sleep(1)
        after = members(process.pid)
    record = dict(command=argv, cwd=str(cwd), commit=identity, started_et=started,
                  finished_et=now(), exit_code=code, outer_timeout=forced,
                  cleanup_before=before, cleanup_after=after)
    (HERE / (name + ".status.json")).write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps({"check": name, **record}), flush=True)
    if code != 0 or forced or before or after:
        failed = True
        break
raise SystemExit(failed)

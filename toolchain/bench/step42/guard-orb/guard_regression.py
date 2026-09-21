#!/usr/bin/env python3
"""Bounded regression controls for step 42's process-group guard recovery."""

import argparse
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


CASE_TIMEOUT = 8.0
POLL_INTERVAL = 0.02


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    state = subprocess.run(
        ["ps", "-o", "stat=", "-p", str(pid)],
        capture_output=True,
        text=True,
        timeout=1,
    ).stdout.strip()
    return bool(state) and not state.startswith("Z")


def wait_for_pid(path, deadline):
    while time.monotonic() < deadline:
        try:
            value = path.read_text().strip()
            if value:
                return int(value)
        except FileNotFoundError:
            pass
        time.sleep(POLL_INTERVAL)
    raise TimeoutError(f"no pid appeared in {path}")


def stop_pid(pid):
    if pid is None:
        return
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline and alive(pid):
        time.sleep(POLL_INTERVAL)


def payload(child_path, descendant_path, group_path, outcome):
    descendant = subprocess.Popen(
        [
            sys.executable,
            "-c",
            "import signal,time; "
            "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
            "signal.signal(signal.SIGINT, signal.SIG_IGN); "
            "time.sleep(300)",
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    Path(descendant_path).write_text(f"{descendant.pid}\n")
    Path(child_path).write_text(f"{os.getpid()}\n")
    Path(group_path).write_text(f"{os.getpgrp()}\n")
    if outcome == "natural":
        time.sleep(0.1)
        return 7
    if outcome == "signal":
        time.sleep(0.1)
        os.kill(os.getpid(), signal.SIGUSR1)
        raise AssertionError("SIGUSR1 did not terminate payload")
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    time.sleep(300)
    return 0


def make_fake_ps(folder):
    real_ps = shutil.which("ps")
    fake_bin = folder / "fake-bin"
    fake_bin.mkdir()
    script = fake_bin / "ps"
    script.write_text(
        "#!/bin/sh\n"
        "case \" $* \" in\n"
        "  *' rss= '*) sleep 0.2; echo 4194305 ;;\n"
        f"  *) exec {real_ps} \"$@\" ;;\n"
        "esac\n"
    )
    script.chmod(0o755)
    return f"{fake_bin}{os.pathsep}{os.environ.get('PATH', '')}"


def run_case(guard, name, outcome, expected, forwarded=None, fake_rss=False):
    started = time.monotonic()
    child = descendant = None
    child_group = None
    guard_process = None
    with tempfile.TemporaryDirectory(prefix=f"guard-{name}-") as raw_folder:
        folder = Path(raw_folder)
        child_path = folder / "child.pid"
        descendant_path = folder / "descendant.pid"
        group_path = folder / "group.pid"
        stderr_path = folder / "guard.stderr"
        environment = os.environ.copy()
        if fake_rss:
            environment["PATH"] = make_fake_ps(folder)
        command = [
            sys.executable,
            str(guard),
            "0.6" if name == "timeout" else "60",
            "--",
            sys.executable,
            str(Path(__file__).resolve()),
            "--payload",
            str(child_path),
            str(descendant_path),
            str(group_path),
            outcome,
        ]
        try:
            with stderr_path.open("w") as stderr_file:
                guard_process = subprocess.Popen(
                    command,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=stderr_file,
                    env=environment,
                )
            ready_deadline = time.monotonic() + 3
            child = wait_for_pid(child_path, ready_deadline)
            descendant = wait_for_pid(descendant_path, ready_deadline)
            child_group = wait_for_pid(group_path, ready_deadline)
            if forwarded is not None:
                guard_process.send_signal(forwarded)
            rc = guard_process.wait(timeout=CASE_TIMEOUT)
        except (subprocess.TimeoutExpired, TimeoutError) as error:
            rc = f"bounded-failure:{type(error).__name__}"
        finally:
            if guard_process is not None and guard_process.poll() is None:
                guard_process.kill()
                guard_process.wait(timeout=2)

        deadline = time.monotonic() + 1
        while time.monotonic() < deadline and any(
            pid is not None and alive(pid) for pid in (child, descendant)
        ):
            time.sleep(POLL_INTERVAL)
        child_alive = child is not None and alive(child)
        descendant_alive = descendant is not None and alive(descendant)
        stderr = stderr_path.read_text().strip()
        elapsed = time.monotonic() - started
        rss_message = not fake_rss or "rss 4096 MB" in stderr
        ok = (
            rc == expected
            and child_group == child
            and not child_alive
            and not descendant_alive
            and elapsed <= CASE_TIMEOUT
            and rss_message
        )

        # This cleanup is deliberately independent of guard behavior so the
        # RED control against the old direct-child guard is bounded too.
        stop_pid(child)
        stop_pid(descendant)
        details = (
            f"{name}: exit={rc} expected={expected}; "
            f"child={'alive' if child_alive else 'gone'}; "
            f"descendant={'alive' if descendant_alive else 'gone'}; "
            f"dedicated-group={'yes' if child_group == child else 'no'}; "
            f"unrelated={{unrelated}}; elapsed={elapsed:.2f}s; "
            f"stderr={stderr!r}; {'PASS' if ok else 'FAIL'}"
        )
        return ok, details


def regression(guard):
    unrelated = subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(300)"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    results = []
    try:
        cases = [
            ("natural", "natural", 7, None, False),
            ("signal", "signal", 128 + signal.SIGUSR1, None, False),
            ("timeout", "wait", 128 + signal.SIGKILL, None, False),
            ("term", "wait", 128 + signal.SIGTERM, signal.SIGTERM, False),
            ("int", "wait", 128 + signal.SIGINT, signal.SIGINT, False),
            ("rss", "wait", 128 + signal.SIGKILL, None, True),
        ]
        for case in cases:
            ok, details = run_case(guard, *case)
            unrelated_alive = alive(unrelated.pid)
            ok = ok and unrelated_alive
            print(
                details.format(
                    unrelated="alive" if unrelated_alive else "gone"
                ).rsplit("; ", 1)[0]
                + f"; {'PASS' if ok else 'FAIL'}"
            )
            results.append(ok)
    finally:
        stop_pid(unrelated.pid)
        try:
            unrelated.wait(timeout=2)
        except subprocess.TimeoutExpired:
            unrelated.kill()
            unrelated.wait(timeout=2)
    print(f"guard_regression: {sum(results)}/{len(results)} passed")
    return 0 if all(results) else 1


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--payload":
        return payload(*sys.argv[2:])
    parser = argparse.ArgumentParser()
    parser.add_argument("--guard", required=True, type=Path)
    arguments = parser.parse_args()
    return regression(arguments.guard.resolve())


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Bounded, synchronized controls for step 42's process-group guard."""

import argparse
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


CASE_SECONDS = 8.0
POLL_SECONDS = 0.02


def remaining(deadline):
    return max(0.01, deadline - time.monotonic())


def alive(pid, ps="ps", timeout=1.0):
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    state = subprocess.run(
        [ps, "-o", "stat=", "-p", str(pid)],
        capture_output=True,
        text=True,
        timeout=timeout,
    ).stdout.strip()
    return bool(state) and not state.startswith("Z")


def read_pid(path):
    try:
        value = path.read_text().strip()
        return int(value) if value else None
    except (FileNotFoundError, ValueError):
        return None


def wait_for_file(path, deadline):
    while time.monotonic() < deadline:
        if path.exists():
            return
        time.sleep(POLL_SECONDS)
    raise TimeoutError(f"readiness did not appear: {path}")


def kill_pid(pid):
    if pid is None:
        return
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def wait_not_live(pids, deadline):
    while time.monotonic() < deadline:
        if not any(alive(pid) for pid in pids):
            return
        time.sleep(POLL_SECONDS)


def descendant(ready_path):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    Path(ready_path).write_text("ready\n")
    time.sleep(300)


def payload(child_path, descendant_path, group_path, ready_path, outcome):
    descendant_ready = Path(ready_path).with_name("descendant.ready")
    child = subprocess.Popen(
        [
            sys.executable,
            str(Path(__file__).resolve()),
            "--descendant-ready",
            str(descendant_ready),
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    Path(descendant_path).write_text(f"{child.pid}\n")
    Path(child_path).write_text(f"{os.getpid()}\n")
    wait_for_file(descendant_ready, time.monotonic() + 3)
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    Path(group_path).write_text(f"{os.getpgrp()}\n")
    Path(ready_path).write_text("ready\n")
    if outcome == "natural":
        time.sleep(0.1)
        return 7
    if outcome == "signal":
        time.sleep(0.1)
        os.kill(os.getpid(), signal.SIGUSR1)
        raise AssertionError("SIGUSR1 did not terminate payload")
    time.sleep(300)
    return 0


def make_fake_ps(folder, ready_path):
    real_ps = shutil.which("ps")
    fake_bin = folder / "fake-bin"
    fake_bin.mkdir()
    script = fake_bin / "ps"
    script.write_text(
        "#!/bin/sh\n"
        "case \" $* \" in\n"
        "  *' rss= '*)\n"
        "    count=0\n"
        f"    while [ ! -f {str(ready_path)!r} ] && [ $count -lt 100 ]; do\n"
        "      sleep 0.02; count=$((count + 1))\n"
        "    done\n"
        f"    if [ -f {str(ready_path)!r} ]; then echo 4194305; else echo 0; fi ;;\n"
        f"  *) exec {real_ps} \"$@\" ;;\n"
        "esac\n"
    )
    script.chmod(0o755)
    return f"{fake_bin}{os.pathsep}{os.environ.get('PATH', '')}"


def install_startup_interposer(folder, ready_path, spawned_path, release_path):
    interposer = folder / "interposer"
    interposer.mkdir()
    (interposer / "sitecustomize.py").write_text(
        "import os\n"
        "from pathlib import Path\n"
        "import subprocess\n"
        "import time\n"
        "original = subprocess.Popen\n"
        "def held(*args, **kwargs):\n"
        "    process = original(*args, **kwargs)\n"
        "    command = args[0] if args else kwargs.get('args', [])\n"
        "    if '--payload' in command:\n"
        f"        ready = Path({str(ready_path)!r})\n"
        f"        spawned = Path({str(spawned_path)!r})\n"
        f"        release = Path({str(release_path)!r})\n"
        "        deadline = time.monotonic() + 5\n"
        "        while not ready.exists() and time.monotonic() < deadline:\n"
        "            time.sleep(0.01)\n"
        "        spawned.write_text(str(process.pid) + '\\n')\n"
        "        while not release.exists() and time.monotonic() < deadline:\n"
        "            time.sleep(0.01)\n"
        "    return process\n"
        "subprocess.Popen = held\n"
    )
    return f"{interposer}{os.pathsep}{os.environ.get('PYTHONPATH', '')}"


def make_hanging_ps(folder):
    script = folder / "hanging-ps"
    script.write_text("#!/bin/sh\nexec sleep 2\n")
    script.chmod(0o755)
    return script


def run_case(
    guard,
    name,
    outcome,
    expected,
    forwarded=None,
    fake_rss=False,
    startup=False,
    force_probe_failure=False,
):
    started = time.monotonic()
    deadline = started + CASE_SECONDS
    child = descendant_pid = child_group = None
    guard_process = None
    rc = None
    issue = None
    child_live = descendant_live = True
    stderr = ""
    with tempfile.TemporaryDirectory(prefix=f"guard-{name}-") as raw_folder:
        folder = Path(raw_folder)
        child_path = folder / "child.pid"
        descendant_path = folder / "descendant.pid"
        group_path = folder / "group.pid"
        ready_path = folder / "payload.ready"
        spawned_path = folder / "popen-return-held"
        release_path = folder / "release-popen"
        stderr_path = folder / "guard.stderr"
        environment = os.environ.copy()
        if fake_rss:
            environment["PATH"] = make_fake_ps(folder, ready_path)
        if startup:
            environment["PYTHONPATH"] = install_startup_interposer(
                folder, ready_path, spawned_path, release_path
            )
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
            str(ready_path),
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
            wait_for_file(spawned_path if startup else ready_path, deadline)
            child = read_pid(child_path)
            descendant_pid = read_pid(descendant_path)
            child_group = read_pid(group_path)
            if startup:
                guard_process.send_signal(forwarded)
                release_path.write_text("release\n")
            elif forwarded is not None:
                guard_process.send_signal(forwarded)
            if force_probe_failure:
                probe_target = child
                child = descendant_pid = child_group = None
                alive(probe_target, ps=str(make_hanging_ps(folder)), timeout=0.05)
                raise AssertionError("forced ps timeout did not occur")
            rc = guard_process.wait(timeout=remaining(deadline))
            observation_deadline = min(deadline, time.monotonic() + 1)
            wait_not_live((child, descendant_pid), observation_deadline)
            child_live = alive(child)
            descendant_live = alive(descendant_pid)
            stderr = stderr_path.read_text().strip()
        except Exception as error:
            issue = f"{type(error).__name__}:{error}"
        finally:
            release_path.touch()
            child = child or read_pid(child_path)
            descendant_pid = descendant_pid or read_pid(descendant_path)
            child_group = child_group or read_pid(group_path)
            if guard_process is not None and guard_process.poll() is None:
                guard_process.kill()
            kill_pid(child)
            kill_pid(descendant_pid)
            if guard_process is not None:
                try:
                    guard_process.wait(timeout=remaining(deadline))
                except subprocess.TimeoutExpired:
                    guard_process.kill()
            try:
                wait_not_live((child, descendant_pid), deadline)
            except (subprocess.TimeoutExpired, TimeoutError):
                pass

        elapsed = time.monotonic() - started
        if force_probe_failure:
            child_live = alive(child)
            descendant_live = alive(descendant_pid)
            ok = (
                issue is not None
                and issue.startswith("TimeoutExpired:")
                and not child_live
                and not descendant_live
                and elapsed <= CASE_SECONDS
            )
        else:
            rss_message = not fake_rss or "rss 4096 MB" in stderr
            ok = (
                issue is None
                and rc == expected
                and child_group == child
                and not child_live
                and not descendant_live
                and elapsed <= CASE_SECONDS
                and rss_message
            )
        details = (
            f"{name}: exit={rc} expected={expected}; "
            f"child={'live' if child_live else 'not-live'}; "
            f"descendant={'live' if descendant_live else 'not-live'}; "
            f"dedicated-group={'yes' if child_group == child else 'no'}; "
            f"unrelated={{unrelated}}; elapsed={elapsed:.2f}s; "
            f"issue={issue!r}; stderr={stderr!r}"
        )
        return ok, details


def run_suite(guard, mode):
    unrelated = subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(300)"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    if mode == "core":
        cases = [
            ("natural", "natural", 7, None, False, False, False),
            ("signal", "signal", 128 + signal.SIGUSR1, None, False, False, False),
            ("timeout", "wait", 128 + signal.SIGKILL, None, False, False, False),
            ("term", "wait", 128 + signal.SIGTERM, signal.SIGTERM, False, False, False),
            ("int", "wait", 128 + signal.SIGINT, signal.SIGINT, False, False, False),
            ("rss", "wait", 128 + signal.SIGKILL, None, True, False, False),
        ]
    elif mode == "startup":
        cases = [
            ("startup-term", "wait", 128 + signal.SIGTERM, signal.SIGTERM, False, True, False),
            ("startup-int", "wait", 128 + signal.SIGINT, signal.SIGINT, False, True, False),
        ]
    else:
        cases = [
            ("forced-ps-timeout", "wait", None, None, False, False, True),
        ]
    results = []
    try:
        for case in cases:
            ok, details = run_case(guard, *case)
            unrelated_live = alive(unrelated.pid)
            ok = ok and unrelated_live
            print(
                details.format(unrelated="live" if unrelated_live else "not-live")
                + f"; {'PASS' if ok else 'FAIL'}"
            )
            results.append(ok)
    finally:
        kill_pid(unrelated.pid)
        try:
            unrelated.wait(timeout=2)
        except subprocess.TimeoutExpired:
            unrelated.kill()
            unrelated.wait(timeout=2)
    print(f"guard_regression[{mode}]: {sum(results)}/{len(results)} passed")
    return 0 if all(results) else 1


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--descendant-ready":
        descendant(sys.argv[2])
        return 0
    if len(sys.argv) >= 2 and sys.argv[1] == "--payload":
        return payload(*sys.argv[2:])
    parser = argparse.ArgumentParser()
    parser.add_argument("--guard", required=True, type=Path)
    parser.add_argument(
        "--mode", choices=("core", "startup", "harness-failure"), default="core"
    )
    arguments = parser.parse_args()
    return run_suite(arguments.guard.resolve(), arguments.mode)


if __name__ == "__main__":
    sys.exit(main())

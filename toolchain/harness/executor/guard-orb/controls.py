#!/usr/bin/env python3
"""Readiness-synchronized, independently bounded guarded-wrapper controls."""

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


CASE_SECONDS = 12.0
POLL_SECONDS = 0.02
BUDGET = 16 * 1024 * 1024


def wait_file(path, deadline):
    while time.monotonic() < deadline:
        if path.exists():
            return
        time.sleep(POLL_SECONDS)
    raise TimeoutError(f"readiness missing: {path}")


def pid(path):
    try:
        return int(path.read_text().strip())
    except (FileNotFoundError, ValueError):
        return None


def live(process_id):
    if process_id is None:
        return False
    try:
        os.kill(process_id, 0)
    except ProcessLookupError:
        return False
    probe = subprocess.run(
        ["/usr/bin/ps", "-o", "stat=", "-p", str(process_id)],
        capture_output=True,
        text=True,
        timeout=0.5,
    )
    state = probe.stdout.strip()
    return bool(state) and not state.startswith("Z")


def kill_owned(process_id, group=False):
    if process_id is None:
        return
    try:
        (os.killpg if group else os.kill)(process_id, signal.SIGKILL)
    except ProcessLookupError:
        pass


def descendant(ready):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    Path(ready).write_text("ready\n")
    while True:
        os.write(1, b"descendant-output\n")
        time.sleep(0.01)


def payload(folder, mode):
    folder = Path(folder)
    child_path = folder / "child.pid"
    group_path = folder / "group.pid"
    descendant_path = folder / "descendant.pid"
    descendant_ready = folder / "descendant.ready"
    child_path.write_text(f"{os.getpid()}\n")
    group_path.write_text(f"{os.getpgrp()}\n")
    child = None
    if mode not in ("plain", "fast-overflow"):
        child = subprocess.Popen(
            [sys.executable, __file__, "--descendant", str(descendant_ready)],
            stdin=subprocess.DEVNULL,
        )
        descendant_path.write_text(f"{child.pid}\n")
        wait_file(descendant_ready, time.monotonic() + 3)
    if mode == "ignore":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
    (folder / "ready").write_text("ready\n")
    if mode == "natural":
        return 0
    if mode == "nonzero":
        return 23
    if mode == "explicit137":
        return 137
    if mode == "signal":
        os.kill(os.getpid(), signal.SIGUSR1)
    if mode in ("overflow", "fast-overflow"):
        block = bytes(range(256)) * 4096
        for _ in range(17):
            os.write(1, block)
        if mode == "fast-overflow":
            return 0
    if mode == "plain":
        print(f"cwd={Path.cwd()} home={os.environ.get('HOME')}", flush=True)
        return 0
    time.sleep(300)
    return 0


def fake_ps(folder, mode):
    fake_bin = folder / "fake-bin"
    fake_bin.mkdir()
    script = fake_bin / "ps"
    script.write_text(
        "#!/bin/sh\n"
        "case \" $* \" in\n"
        "  *' rss= '*)\n"
        "    if [ \"$FAKE_PS_MODE\" = rss-hang ]; then sleep 5; exit 0; fi\n"
        "    exec /usr/bin/ps \"$@\" ;;\n"
        "  *' -axo '*)\n"
        "    case \"$FAKE_PS_MODE\" in\n"
        "      cleanup-hang) sleep 5; exit 0 ;;\n"
        "      cleanup-nonzero) exit 9 ;;\n"
        "      cleanup-live) value=$(cat \"$FAKE_PGID_PATH\"); echo \"$value 999 S fake-live\"; exit 0 ;;\n"
        "      cleanup-zombie) value=$(cat \"$FAKE_PGID_PATH\"); echo \"$value 999 Z fake-zombie\"; exit 0 ;;\n"
        "    esac ;;\n"
        "esac\n"
        "exec /usr/bin/ps \"$@\"\n"
    )
    script.chmod(0o755)
    return f"{fake_bin}{os.pathsep}{os.environ['PATH']}"


def popen_interposer(folder, jump_time=False):
    interposer = folder / "interposer"
    interposer.mkdir()
    (interposer / "sitecustomize.py").write_text(
        "from pathlib import Path\n"
        "import os, subprocess, time\n"
        "original = subprocess.Popen\n"
        "original_monotonic = time.monotonic\n"
        "def held(*args, **kwargs):\n"
        "    process = original(*args, **kwargs)\n"
        "    command = args[0] if args else kwargs.get('args', [])\n"
        "    if '--payload' in command:\n"
        "        folder = Path(command[command.index('--payload') + 1])\n"
        "        deadline = time.monotonic() + 5\n"
        "        while not (folder / 'ready').exists() and time.monotonic() < deadline: time.sleep(.01)\n"
        "        (folder / 'popen-held').write_text(str(process.pid) + '\\n')\n"
        "        if os.environ.get('JUMP_TIME_AFTER_POPEN') == '1':\n"
        "            time.monotonic = lambda: original_monotonic() + 100\n"
        "        else:\n"
        "            while not (folder / 'release').exists() and time.monotonic() < deadline: time.sleep(.01)\n"
        "    return process\n"
        "subprocess.Popen = held\n"
    )
    if jump_time:
        return f"{interposer}{os.pathsep}{os.environ.get('PYTHONPATH', '')}", "1"
    return f"{interposer}{os.pathsep}{os.environ.get('PYTHONPATH', '')}"


def run_case(wrapper, root, name, mode, expected, *, sent=None, repeated=False,
             startup=False, outer=False, fake=None, home=False, harness_failure=False):
    started = time.monotonic()
    deadline = started + CASE_SECONDS
    folder = root / name
    payload_folder = folder / "payload"
    payload_folder.mkdir(parents=True)
    attempt = folder / "attempt"
    cwd = folder / "cwd"
    cwd.mkdir()
    home_path = folder / "home"
    environment = os.environ.copy()
    if fake:
        environment["PATH"] = fake_ps(folder, fake)
        environment["FAKE_PS_MODE"] = fake
        environment["FAKE_PGID_PATH"] = str(payload_folder / "group.pid")
    if startup:
        environment["PYTHONPATH"] = popen_interposer(folder)
    if outer:
        environment["PYTHONPATH"], environment["JUMP_TIME_AFTER_POPEN"] = popen_interposer(folder, True)
    command = [
        sys.executable,
        str(wrapper),
        "3" if mode in ("ignore", "overflow") else "6",
        str(attempt),
        "--cwd",
        str(cwd),
    ]
    if home:
        command.extend(["--home", str(home_path)])
    command.extend([
        "--",
        sys.executable,
        str(Path(__file__).resolve()),
        "--payload",
        str(payload_folder),
        mode,
    ])
    wrapper_process = child = descendant_pid = group = None
    issue = None
    rc = None
    result = {}
    stable = None
    observed_child_live = observed_descendant_live = None
    try:
        wrapper_process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=environment,
        )
        wait_file(payload_folder / ("popen-held" if startup else "ready"), deadline)
        child = pid(payload_folder / "child.pid")
        descendant_pid = pid(payload_folder / "descendant.pid")
        group = pid(payload_folder / "group.pid")
        if harness_failure:
            subprocess.run([sys.executable, "-c", "import time; time.sleep(5)"], timeout=0.05)
        if sent:
            wrapper_process.send_signal(sent)
            if repeated:
                time.sleep(0.3)
                wrapper_process.send_signal(sent)
        (payload_folder / "release").touch()
        rc = wrapper_process.wait(timeout=max(0.01, deadline - time.monotonic()))
        wrapper_output = wrapper_process.stdout.read()
        result = json.loads((attempt / "exit.json").read_text())
        size = (attempt / "output.log").stat().st_size
        time.sleep(0.25)
        stable = size == (attempt / "output.log").stat().st_size
        observed_child_live = live(child)
        observed_descendant_live = live(descendant_pid)
    except Exception as error:
        issue = f"{type(error).__name__}: {error}"
        wrapper_output = ""
        size = (attempt / "output.log").stat().st_size if (attempt / "output.log").exists() else 0
    finally:
        (payload_folder / "release").touch()
        child = child or pid(payload_folder / "child.pid")
        descendant_pid = descendant_pid or pid(payload_folder / "descendant.pid")
        group = group or pid(payload_folder / "group.pid")
        if wrapper_process is not None and wrapper_process.poll() is None:
            wrapper_process.kill()
        kill_owned(group, group=True)
        kill_owned(child)
        kill_owned(descendant_pid)
        if wrapper_process is not None:
            try:
                wrapper_process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                wrapper_process.kill()

    elapsed = time.monotonic() - started
    no_live = not live(child) and not live(descendant_pid)
    dedicated = child is not None and group == child
    if harness_failure:
        ok = issue is not None and issue.startswith("TimeoutExpired:")
        ok = ok and no_live and dedicated and elapsed <= CASE_SECONDS
    else:
        ok = issue is None and rc == expected and result.get("exit") == expected
        ok = ok and observed_child_live is False and observed_descendant_live is False
        ok = ok and no_live and dedicated and elapsed <= CASE_SECONDS and stable
    if mode in ("overflow", "fast-overflow"):
        ok = ok and size > BUDGET and result.get("reason") == "output_overflow"
    if outer:
        ok = ok and result.get("reason") == "outer_deadline"
    if fake in ("rss-hang", "cleanup-hang", "cleanup-nonzero", "cleanup-live"):
        ok = ok and expected == 125
    if fake == "cleanup-zombie":
        ok = ok and result.get("group_state") == "not_live" and result.get("group_absent") is False
    if home:
        command_record = json.loads((attempt / "command.json").read_text())
        ok = ok and command_record["cwd"] == str(cwd.resolve()) and command_record["environment"]["HOME"] == str(home_path.resolve())
    detail = (
        f"{name}: exit={rc} expected={expected}; reason={result.get('reason')}; "
        f"group={result.get('group_state')}; child={'live' if live(child) else 'not-live'}; "
        f"descendant={'live' if live(descendant_pid) else 'not-live'}; dedicated={dedicated}; "
        f"observed-before-fallback=child:{observed_child_live},descendant:{observed_descendant_live}; "
        f"bytes={size}; stable={stable}; elapsed={elapsed:.2f}s; issue={issue!r}; "
        f"wrapper={wrapper_output.strip()!r}; {'PASS' if ok else 'FAIL'}"
    )
    return ok, detail


def suite(wrapper, output, selected):
    if output.exists():
        raise FileExistsError(output)
    output.mkdir(parents=True)
    sentinel = subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(300)"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    cases = [
        ("natural-descendant", "natural", 0, {}),
        ("nonzero23", "nonzero", 23, {}),
        ("explicit137", "explicit137", 137, {}),
        ("signal-exit", "signal", 128 + signal.SIGUSR1, {}),
        ("term-responsive", "sleep", 128 + signal.SIGTERM, {"sent": signal.SIGTERM}),
        ("int-responsive", "sleep", 128 + signal.SIGINT, {"sent": signal.SIGINT}),
        ("term-ignoring-repeated", "ignore", 137, {"sent": signal.SIGTERM, "repeated": True}),
        ("startup-term", "sleep", 128 + signal.SIGTERM, {"sent": signal.SIGTERM, "startup": True}),
        ("startup-int", "sleep", 128 + signal.SIGINT, {"sent": signal.SIGINT, "startup": True}),
        ("outer-deadline", "sleep", 124, {"outer": True}),
        ("overflow-sleep", "overflow", 124, {}),
        ("fast-binary-overflow", "fast-overflow", 124, {}),
        ("rss-probe-hang", "sleep", 125, {"fake": "rss-hang"}),
        ("cleanup-probe-hang", "plain", 125, {"fake": "cleanup-hang"}),
        ("cleanup-probe-nonzero", "plain", 125, {"fake": "cleanup-nonzero"}),
        ("cleanup-persistent", "plain", 125, {"fake": "cleanup-live"}),
        ("cleanup-zombie", "plain", 0, {"fake": "cleanup-zombie"}),
        ("cwd-home", "plain", 0, {"home": True}),
        ("harness-probe-failure", "sleep", None, {"harness_failure": True}),
    ]
    if selected:
        unknown = set(selected) - {case[0] for case in cases}
        if unknown:
            raise ValueError(f"unknown controls: {sorted(unknown)}")
        cases = [case for case in cases if case[0] in selected]
    passed = []
    try:
        for name, mode, expected, options in cases:
            ok, detail = run_case(wrapper, output, name, mode, expected, **options)
            sentinel_live = live(sentinel.pid)
            ok = ok and sentinel_live
            print(f"{detail}; sentinel={'live' if sentinel_live else 'not-live'}")
            passed.append(ok)
    finally:
        kill_owned(sentinel.pid)
        sentinel.wait(timeout=2)
    print(f"guarded_controls: {sum(passed)}/{len(passed)} passed")
    return 0 if all(passed) else 1


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "--descendant":
        descendant(sys.argv[2])
        return 0
    if len(sys.argv) >= 2 and sys.argv[1] == "--payload":
        return payload(sys.argv[2], sys.argv[3])
    parser = argparse.ArgumentParser()
    parser.add_argument("--wrapper", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--controls", nargs="*")
    args = parser.parse_args()
    return suite(args.wrapper.resolve(), args.output.resolve(), args.controls)


if __name__ == "__main__":
    sys.exit(main())

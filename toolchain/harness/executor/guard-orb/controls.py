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
WRAPPER_OUTPUT_LIMIT = 64 * 1024


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


def live(process_id, ps="/usr/bin/ps", timeout=0.5):
    if process_id is None:
        return False
    try:
        os.kill(process_id, 0)
    except ProcessLookupError:
        return False
    probe = subprocess.run(
        [ps, "-o", "stat=", "-p", str(process_id)],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if probe.returncode not in (0, 1):
        raise RuntimeError(f"liveness probe exited {probe.returncode}")
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
    deadline = time.monotonic() + 9
    while time.monotonic() < deadline:
        os.write(1, b"descendant-output\n")
        time.sleep(0.02)
    return 0


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
    time.sleep(9)
    return 0


def fake_ps(folder, mode):
    fake_bin = folder / "fake-bin"
    fake_bin.mkdir()
    script = fake_bin / "ps"
    script.write_text(
        "#!/bin/sh\n"
        "case \" $* \" in\n"
        "  *' rss= '*)\n"
        "    case \"$FAKE_PS_MODE\" in\n"
        "      rss-hang) exec sleep 5 ;;\n"
        "      rss-empty-live)\n"
        "        count=0; while [ ! -f \"$FAKE_READY_PATH\" ] && [ $count -lt 100 ]; do sleep .01; count=$((count + 1)); done\n"
        "        exit 0 ;;\n"
        "      rss-empty-complete)\n"
        "        count=0; while [ ! -f \"$FAKE_READY_PATH\" ] && [ $count -lt 100 ]; do sleep .01; count=$((count + 1)); done\n"
        "        sleep .1; exit 0 ;;\n"
        "      rss-no-selection-complete)\n"
        "        count=0; while [ ! -f \"$FAKE_READY_PATH\" ] && [ $count -lt 100 ]; do sleep .01; count=$((count + 1)); done\n"
        "        sleep .1; exit 1 ;;\n"
        "      rss-malformed-complete)\n"
        "        count=0; while [ ! -f \"$FAKE_READY_PATH\" ] && [ $count -lt 100 ]; do sleep .01; count=$((count + 1)); done\n"
        "        sleep .1; echo broken; exit 0 ;;\n"
        "      rss-nonzero-complete)\n"
        "        count=0; while [ ! -f \"$FAKE_READY_PATH\" ] && [ $count -lt 100 ]; do sleep .01; count=$((count + 1)); done\n"
        "        sleep .1; exit 9 ;;\n"
        "    esac\n"
        "    exec /usr/bin/ps \"$@\" ;;\n"
        "  *' -axo '*)\n"
        "    case \"$FAKE_PS_MODE\" in\n"
        "      cleanup-hang) exec sleep 5 ;;\n"
        "      cleanup-nonzero) exit 9 ;;\n"
        "      cleanup-empty) touch \"$FAKE_BRANCH_MARKER\"; exit 0 ;;\n"
        "      cleanup-malformed) echo 'broken snapshot'; exit 0 ;;\n"
        "      cleanup-truncated) echo '123 456'; exit 0 ;;\n"
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


def hanging_probe(folder):
    script = folder / "hanging-probe"
    script.write_text("#!/bin/sh\nexec sleep 5\n")
    script.chmod(0o755)
    return str(script)


def cleanup_owned(wrapper_process, payload_folder, known):
    errors = []
    try:
        (payload_folder / "release").touch()
    except Exception as error:
        errors.append(f"release:{type(error).__name__}:{error}")
    if wrapper_process is not None:
        try:
            if wrapper_process.poll() is None:
                wrapper_process.kill()
            wrapper_process.wait(timeout=1)
        except Exception as error:
            errors.append(f"wrapper:{type(error).__name__}:{error}")
            try:
                wrapper_process.kill()
                wrapper_process.wait(timeout=1)
            except Exception as retry_error:
                errors.append(f"wrapper-retry:{type(retry_error).__name__}:{retry_error}")

    recorded_child = pid(payload_folder / "child.pid")
    recorded_descendant = pid(payload_folder / "descendant.pid")
    recorded_group = pid(payload_folder / "group.pid")
    child = recorded_child or known[0]
    descendant_pid = recorded_descendant or known[1]
    group = recorded_group or known[2]
    for label, process_id, is_group in (
        ("group", group, True),
        ("child", child, False),
        ("descendant", descendant_pid, False),
    ):
        try:
            kill_owned(process_id, group=is_group)
        except Exception as error:
            errors.append(f"{label}:{type(error).__name__}:{error}")
    deadline = time.monotonic() + 1
    while time.monotonic() < deadline:
        try:
            if not live(child) and not live(descendant_pid):
                break
        except Exception as error:
            errors.append(f"cleanup-observe:{type(error).__name__}:{error}")
            break
        time.sleep(POLL_SECONDS)
    return child, descendant_pid, group, errors


def run_case(
    wrapper,
    root,
    name,
    mode,
    expected,
    *,
    sent=None,
    repeated=False,
    startup=False,
    startup_hold=0,
    outer=False,
    fake=None,
    home=False,
    harness_failure=None,
    expected_reason="child_exit",
    expected_group="absent",
    expected_child_exit=0,
    expected_returncode=0,
    expected_error=None,
    expected_reason_source="supervision",
    expected_supervision_reason=None,
    elapsed_min=0,
    elapsed_max=CASE_SECONDS,
):
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
        environment["FAKE_READY_PATH"] = str(payload_folder / "ready")
        environment["FAKE_BRANCH_MARKER"] = str(folder / "fake-branch.marker")
    if startup:
        environment["PYTHONPATH"] = popen_interposer(folder)
    if outer:
        environment["PYTHONPATH"], environment["JUMP_TIME_AFTER_POPEN"] = popen_interposer(folder, True)
    command = [
        sys.executable,
        str(wrapper),
        "30" if mode == "ignore" else "6",
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
    cleanup_errors = []
    rc = None
    result = {}
    stable = None
    observed_child_live = observed_descendant_live = None
    repeated_after_grace = None
    wrapper_output_path = folder / "wrapper-output.log"
    wrapper_output_file = wrapper_output_path.open("wb")
    try:
        wrapper_process = subprocess.Popen(
            command,
            stdout=wrapper_output_file,
            stderr=subprocess.STDOUT,
            env=environment,
        )
        wait_file(payload_folder / ("popen-held" if startup else "ready"), deadline)
        if harness_failure == "before-ownership":
            subprocess.run([sys.executable, "-c", "import time; time.sleep(5)"], timeout=0.05)
        child = pid(payload_folder / "child.pid")
        descendant_pid = pid(payload_folder / "descendant.pid")
        group = pid(payload_folder / "group.pid")
        if harness_failure == "observation":
            live(child, ps=hanging_probe(folder), timeout=0.05)
            raise AssertionError("hanging observation unexpectedly completed")
        if sent:
            wrapper_process.send_signal(sent)
            if repeated:
                time.sleep(1.5)
                wrapper_process.send_signal(sent)
                time.sleep(0.7)
                try:
                    wrapper_process.send_signal(sent)
                    repeated_after_grace = "delivered"
                except ProcessLookupError:
                    repeated_after_grace = "wrapper-exited"
        if startup_hold:
            time.sleep(startup_hold)
        (payload_folder / "release").touch()
        rc = wrapper_process.wait(timeout=max(0.01, deadline - time.monotonic()))
        wrapper_output_file.close()
        if wrapper_output_path.stat().st_size > WRAPPER_OUTPUT_LIMIT:
            raise RuntimeError("wrapper output exceeded collection bound")
        wrapper_output = wrapper_output_path.read_bytes()[:WRAPPER_OUTPUT_LIMIT].decode(errors="replace")
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
        if not wrapper_output_file.closed:
            wrapper_output_file.close()
        child, descendant_pid, group, cleanup_errors = cleanup_owned(
            wrapper_process, payload_folder, (child, descendant_pid, group)
        )

    elapsed = time.monotonic() - started
    final_observation_error = None
    try:
        child_live = live(child)
        descendant_live = live(descendant_pid)
    except Exception as error:
        final_observation_error = f"{type(error).__name__}: {error}"
        child_live = descendant_live = True
    no_live = not child_live and not descendant_live
    dedicated = child is not None and group == child
    if harness_failure:
        ok = issue is not None and issue.startswith("TimeoutExpired:")
        ok = ok and no_live and dedicated and elapsed <= elapsed_max and not cleanup_errors
    else:
        ok = issue is None and rc == expected and result.get("exit") == expected
        ok = ok and observed_child_live is False and observed_descendant_live is False
        ok = ok and no_live and dedicated and elapsed_min <= elapsed <= elapsed_max
        ok = ok and stable and not cleanup_errors
        ok = ok and result.get("child_exit") == expected_child_exit
        ok = ok and result.get("child_returncode") == expected_returncode
        ok = ok and result.get("process_group") == group
        ok = ok and result.get("reason") == expected_reason
        ok = ok and result.get("reason_source") == expected_reason_source
        ok = ok and result.get("supervision_reason") == (
            expected_reason if expected_supervision_reason is None else expected_supervision_reason
        )
        ok = ok and result.get("group_state") == expected_group
        if expected_error:
            errors = f"{result.get('cleanup_error')} {result.get('supervision_error')}"
            ok = ok and expected_error in errors
    if mode in ("overflow", "fast-overflow"):
        ok = ok and size > BUDGET and result.get("reason") == "output_overflow"
    if fake == "cleanup-zombie":
        ok = ok and result.get("group_state") == "not_live" and result.get("group_absent") is False
    if home:
        command_record = json.loads((attempt / "command.json").read_text())
        ok = ok and command_record["cwd"] == str(cwd.resolve()) and command_record["environment"]["HOME"] == str(home_path.resolve())
    detail = (
        f"{name}: exit={rc} expected={expected}; reason={result.get('reason')}; "
        f"source={result.get('reason_source')}; supervision={result.get('supervision_reason')}; "
        f"child-status={result.get('child_returncode')}/"
        f"{result.get('child_exit')}; receipt-pgid={result.get('process_group')}; "
        f"group={result.get('group_state')}; child={'live' if child_live else 'not-live'}; "
        f"descendant={'live' if descendant_live else 'not-live'}; dedicated={dedicated}; "
        f"observed-before-fallback=child:{observed_child_live},descendant:{observed_descendant_live}; "
        f"repeated-after-grace={repeated_after_grace}; "
        f"bytes={size}; stable={stable}; elapsed={elapsed:.2f}s; issue={issue!r}; "
        f"cleanup-errors={cleanup_errors!r}; final-observation-error={final_observation_error!r}; "
        f"wrapper={wrapper_output.strip()!r}; {'PASS' if ok else 'FAIL'}"
    )
    return ok, detail


def run_standalone_cleanup_failure(wrapper, root):
    name = "standalone-cleanup-unknown"
    started = time.monotonic()
    deadline = started + CASE_SECONDS
    folder = root / name
    payload_folder = folder / "payload"
    payload_folder.mkdir(parents=True)
    output_path = folder / "guard-output.log"
    environment = os.environ.copy()
    environment["PATH"] = fake_ps(folder, "cleanup-empty")
    environment["FAKE_PS_MODE"] = "cleanup-empty"
    environment["FAKE_PGID_PATH"] = str(payload_folder / "group.pid")
    environment["FAKE_READY_PATH"] = str(payload_folder / "ready")
    marker = folder / "fake-branch.marker"
    environment["FAKE_BRANCH_MARKER"] = str(marker)
    guard = wrapper.parents[3] / "toolchain/bench/step36/guard.py"
    command = [
        sys.executable,
        str(guard),
        "6",
        "--",
        sys.executable,
        str(Path(__file__).resolve()),
        "--payload",
        str(payload_folder),
        "plain",
    ]
    process = None
    child = descendant_pid = group = None
    issue = None
    rc = None
    cleanup_errors = []
    with output_path.open("wb") as output:
        try:
            process = subprocess.Popen(
                command,
                stdout=output,
                stderr=subprocess.STDOUT,
                env=environment,
            )
            wait_file(payload_folder / "ready", deadline)
            child = pid(payload_folder / "child.pid")
            group = pid(payload_folder / "group.pid")
            rc = process.wait(timeout=max(0.01, deadline - time.monotonic()))
        except Exception as error:
            issue = f"{type(error).__name__}: {error}"
        finally:
            child, descendant_pid, group, cleanup_errors = cleanup_owned(
                process, payload_folder, (child, descendant_pid, group)
            )
    try:
        no_live = not live(child) and not live(descendant_pid)
    except Exception as error:
        issue = issue or f"{type(error).__name__}: {error}"
        no_live = False
    output_size = output_path.stat().st_size
    ok = (
        issue is None
        and rc == 125
        and marker.exists()
        and child == group
        and no_live
        and not cleanup_errors
        and output_size <= WRAPPER_OUTPUT_LIMIT
        and time.monotonic() <= deadline
    )
    detail = (
        f"{name}: exit={rc} expected=125; injected-cleanup-empty={marker.exists()}; "
        f"dedicated={child == group}; owned-not-live={no_live}; bytes={output_size}; "
        f"elapsed={time.monotonic()-started:.2f}s; issue={issue!r}; "
        f"cleanup-errors={cleanup_errors!r}; {'PASS' if ok else 'FAIL'}"
    )
    return ok, detail


def suite(wrapper, output, selected):
    if output.exists():
        raise FileExistsError(output)
    output.mkdir(parents=True)
    sentinel = subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(60)"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    cases = [
        ("natural-descendant", "natural", 0, {}),
        ("nonzero23", "nonzero", 23, {"expected_child_exit": 23, "expected_returncode": 23}),
        ("explicit137", "explicit137", 137, {"expected_child_exit": 137, "expected_returncode": 137}),
        ("signal-exit", "signal", 128 + signal.SIGUSR1,
         {"expected_child_exit": 128 + signal.SIGUSR1, "expected_returncode": -signal.SIGUSR1}),
        ("term-responsive", "sleep", 128 + signal.SIGTERM,
         {"sent": signal.SIGTERM, "expected_child_exit": 128 + signal.SIGTERM,
          "expected_returncode": -signal.SIGTERM}),
        ("int-responsive", "sleep", 128 + signal.SIGINT,
         {"sent": signal.SIGINT, "expected_child_exit": 128 + signal.SIGINT,
          "expected_returncode": -signal.SIGINT}),
        ("term-ignoring-repeated", "ignore", 137,
         {"sent": signal.SIGTERM, "repeated": True, "expected_reason": "signal_grace",
          "expected_child_exit": 137, "expected_returncode": -signal.SIGKILL,
          "elapsed_min": 2.0, "elapsed_max": 3.0}),
        ("int-ignoring", "ignore", 137,
         {"sent": signal.SIGINT, "expected_reason": "signal_grace",
          "expected_child_exit": 137, "expected_returncode": -signal.SIGKILL,
          "elapsed_min": 2.0, "elapsed_max": 3.0}),
        ("startup-term", "sleep", 128 + signal.SIGTERM,
         {"sent": signal.SIGTERM, "startup": True,
          "expected_child_exit": 128 + signal.SIGTERM, "expected_returncode": -signal.SIGTERM}),
        ("startup-int", "sleep", 128 + signal.SIGINT,
         {"sent": signal.SIGINT, "startup": True,
          "expected_child_exit": 128 + signal.SIGINT, "expected_returncode": -signal.SIGINT}),
        ("startup-held-beyond-grace", "ignore", 137,
         {"sent": signal.SIGTERM, "startup": True, "startup_hold": 2.3,
          "expected_reason": "signal_grace", "expected_child_exit": 137,
          "expected_returncode": -signal.SIGKILL, "elapsed_min": 2.3,
          "elapsed_max": 3.2}),
        ("outer-deadline", "sleep", 124,
         {"outer": True, "expected_reason": "outer_deadline", "expected_child_exit": 137,
          "expected_returncode": -signal.SIGKILL}),
        ("overflow-sleep", "overflow", 124,
         {"expected_reason": "output_overflow", "expected_child_exit": 137,
          "expected_returncode": -signal.SIGKILL}),
        ("fast-binary-overflow", "fast-overflow", 124,
         {"expected_reason": "output_overflow", "expected_reason_source": "after_cleanup",
          "expected_supervision_reason": "child_exit"}),
        ("rss-probe-hang", "sleep", 125,
         {"fake": "rss-hang", "expected_reason": "rss_probe_failed",
          "expected_child_exit": 137, "expected_returncode": -signal.SIGKILL,
          "expected_error": "TimeoutExpired"}),
        ("rss-empty-live", "sleep", 125,
         {"fake": "rss-empty-live", "expected_reason": "rss_probe_failed",
          "expected_child_exit": 137, "expected_returncode": -signal.SIGKILL,
          "expected_error": "selected no process"}),
        ("rss-empty-completed", "plain", 0, {"fake": "rss-empty-complete"}),
        ("rss-no-selection-completed", "plain", 0,
         {"fake": "rss-no-selection-complete"}),
        ("rss-malformed-completed", "plain", 125,
         {"fake": "rss-malformed-complete", "expected_reason": "rss_probe_failed",
          "expected_error": "malformed rss sample"}),
        ("rss-nonzero-completed", "plain", 125,
         {"fake": "rss-nonzero-complete", "expected_reason": "rss_probe_failed",
          "expected_error": "rss probe exited 9"}),
        ("cleanup-probe-hang", "plain", 125,
         {"fake": "cleanup-hang", "expected_group": "unknown", "expected_error": "TimeoutExpired"}),
        ("cleanup-probe-nonzero", "plain", 125,
         {"fake": "cleanup-nonzero", "expected_group": "unknown", "expected_error": "ps exited 9"}),
        ("cleanup-empty", "plain", 125,
         {"fake": "cleanup-empty", "expected_group": "unknown", "expected_error": "empty process snapshot"}),
        ("cleanup-malformed", "plain", 125,
         {"fake": "cleanup-malformed", "expected_group": "unknown", "expected_error": "malformed process row"}),
        ("cleanup-truncated", "plain", 125,
         {"fake": "cleanup-truncated", "expected_group": "unknown", "expected_error": "malformed process row"}),
        ("cleanup-persistent", "plain", 125,
         {"fake": "cleanup-live", "expected_group": "live"}),
        ("cleanup-zombie", "plain", 0,
         {"fake": "cleanup-zombie", "expected_group": "not_live"}),
        ("overflow-cleanup-unknown", "overflow", 125,
         {"fake": "cleanup-empty", "expected_reason": "output_overflow",
          "expected_group": "unknown", "expected_child_exit": 137,
          "expected_returncode": -signal.SIGKILL, "expected_error": "empty process snapshot"}),
        ("overflow-cleanup-live", "overflow", 125,
         {"fake": "cleanup-live", "expected_reason": "output_overflow",
          "expected_group": "live", "expected_child_exit": 137,
          "expected_returncode": -signal.SIGKILL}),
        ("cwd-home", "plain", 0, {"home": True}),
        ("harness-before-ownership", "sleep", None,
         {"startup": True, "harness_failure": "before-ownership"}),
        ("harness-observation-failure", "sleep", None,
         {"harness_failure": "observation"}),
    ]
    standalone_name = "standalone-cleanup-unknown"
    if selected:
        unknown = set(selected) - ({case[0] for case in cases} | {standalone_name})
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
        if not selected or standalone_name in selected:
            ok, detail = run_standalone_cleanup_failure(wrapper, output)
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

#!/usr/bin/env python3
"""Bounded direct-child RSS and process-group supervision.

The CLI is ``guard.py SECONDS -- cmd...``.  It normally exits as the normalized
direct child status, but exceptionally exits 125 when supervision or final
cleanup is failed or unknown.  ``supervise`` is also the shared in-process entry
point for recording wrappers that must own the payload group themselves rather
than supervise a second guard process.
"""

from dataclasses import dataclass
import os
import signal
import subprocess
import sys
import time


RSS_LIMIT = 4 << 30
POLL_SECONDS = 0.1
PROBE_SECONDS = 0.5
REAP_SECONDS = 2.0
CLEANUP_SECONDS = 3.0


@dataclass
class GroupObservation:
    state: str
    rows: list[str]
    error: str | None = None


@dataclass
class Result:
    process_group: int
    child_returncode: int | None
    reason: str
    rss_bytes: int
    elapsed_seconds: float
    group: GroupObservation
    supervision_error: str | None = None

    @property
    def child_exit(self):
        if self.child_returncode is None:
            return None
        if self.child_returncode < 0:
            return 128 - self.child_returncode
        return self.child_returncode

    @property
    def cleanup_confirmed(self):
        return self.group.state in ("absent", "not_live")


def _signal_group(pid, sig):
    try:
        os.killpg(pid, sig)
    except ProcessLookupError:
        pass


def _rss(pid):
    probe = subprocess.run(
        ["ps", "-o", "rss=", "-p", str(pid)],
        capture_output=True,
        text=True,
        timeout=PROBE_SECONDS,
        check=False,
    )
    value = probe.stdout.strip()
    if probe.returncode:
        return None, f"rss probe exited {probe.returncode}"
    if not value:
        return None, "rss probe selected no process"
    try:
        return int(value) * 1024, None
    except ValueError:
        return None, f"malformed rss sample: {value!r}"


def _observe_group(pgid):
    try:
        probe = subprocess.run(
            ["ps", "-axo", "pgid=,pid=,stat=,command="],
            capture_output=True,
            text=True,
            timeout=PROBE_SECONDS,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return GroupObservation("unknown", [], f"{type(error).__name__}: {error}")
    if probe.returncode:
        return GroupObservation("unknown", [], f"ps exited {probe.returncode}")
    rows = []
    live = False
    snapshot = probe.stdout.splitlines()
    if not snapshot:
        return GroupObservation("unknown", [], "empty process snapshot")
    for row in snapshot:
        fields = row.split(None, 3)
        if (
            len(fields) < 3
            or not fields[0].isdigit()
            or not fields[1].isdigit()
            or not fields[2]
            or fields[2][0] not in "DIRSTtWXxZOU"
        ):
            return GroupObservation("unknown", rows, f"malformed process row: {row!r}")
        if fields[0] == str(pgid):
            rows.append(row.strip())
            live = live or not fields[2].startswith("Z")
    if not rows:
        return GroupObservation("absent", [])
    return GroupObservation("live" if live else "not_live", rows)


def supervise(
    limit,
    command,
    *,
    cwd=None,
    env=None,
    stdout=None,
    stderr=None,
    policy=None,
    forwarded_signal_grace=None,
    outer_deadline=None,
):
    """Run one payload group and return its status plus bounded cleanup proof.

    ``policy`` may return a reason string such as ``output_overflow``.  Signals
    arriving during synchronous ``Popen`` are queued: cleanup cannot act on the
    new group until ``Popen`` returns its handle.  With a forwarding grace, the
    first TERM/INT receipt starts one escalation clock; repeated or queued
    signals never extend it.
    """
    started = time.monotonic()
    payload = None
    pending = []
    forwarded_deadline = None
    reason = "child_exit"
    rss = 0
    supervision_error = None

    def forward(sig, _frame=None):
        nonlocal forwarded_deadline
        if forwarded_signal_grace is not None and forwarded_deadline is None:
            forwarded_deadline = time.monotonic() + forwarded_signal_grace
        if payload is None:
            pending.append(sig)
            return
        _signal_group(payload.pid, sig)

    previous = {sig: signal.getsignal(sig) for sig in (signal.SIGTERM, signal.SIGINT)}
    for sig in previous:
        signal.signal(sig, forward)
    try:
        payload = subprocess.Popen(
            command,
            cwd=cwd,
            env=env,
            stdout=stdout,
            stderr=stderr,
            start_new_session=True,
        )
        for sig in pending:
            _signal_group(payload.pid, sig)
        if forwarded_deadline is not None and time.monotonic() >= forwarded_deadline:
            reason = "signal_grace"
            _signal_group(payload.pid, signal.SIGKILL)
        next_rss = started
        while True:
            now = time.monotonic()
            child_done = payload.poll() is not None
            policy_reason = policy(payload, now) if policy is not None else None
            if policy_reason:
                reason = policy_reason
                _signal_group(payload.pid, signal.SIGKILL)
                break
            if outer_deadline is not None and now >= outer_deadline:
                reason = "outer_deadline"
                _signal_group(payload.pid, signal.SIGKILL)
                break
            if child_done:
                break
            if forwarded_deadline is not None and now >= forwarded_deadline:
                reason = "signal_grace"
                _signal_group(payload.pid, signal.SIGKILL)
                break
            if now - started > limit:
                reason = "deadline"
                sys.stderr.write(
                    f"guard: killed {payload.pid} (rss {rss >> 20} MB, {now-started:.0f} s)\n"
                )
                _signal_group(payload.pid, signal.SIGKILL)
                break
            if now >= next_rss:
                try:
                    sample, probe_error = _rss(payload.pid)
                except (OSError, subprocess.TimeoutExpired) as error:
                    reason = "rss_probe_failed"
                    supervision_error = f"{type(error).__name__}: {error}"
                    _signal_group(payload.pid, signal.SIGKILL)
                    break
                if sample is None:
                    if payload.poll() is not None:
                        continue
                    reason = "rss_probe_failed"
                    supervision_error = probe_error
                    _signal_group(payload.pid, signal.SIGKILL)
                    break
                rss = sample
                if rss > RSS_LIMIT:
                    reason = "rss"
                    sys.stderr.write(
                        f"guard: killed {payload.pid} (rss {rss >> 20} MB, {now-started:.0f} s)\n"
                    )
                    _signal_group(payload.pid, signal.SIGKILL)
                    break
                next_rss = now + 0.5
            time.sleep(POLL_SECONDS)

        reap_deadline = time.monotonic() + REAP_SECONDS
        while payload.poll() is None and time.monotonic() < reap_deadline:
            time.sleep(POLL_SECONDS)
        if payload.poll() is None:
            _signal_group(payload.pid, signal.SIGKILL)
            supervision_error = supervision_error or "payload reap deadline expired"

        _signal_group(payload.pid, signal.SIGKILL)
        cleanup_deadline = time.monotonic() + CLEANUP_SECONDS
        observation = GroupObservation("unknown", [], "cleanup not observed")
        while time.monotonic() < cleanup_deadline:
            observation = _observe_group(payload.pid)
            if observation.state in ("absent", "not_live", "unknown"):
                break
            time.sleep(POLL_SECONDS)
        return Result(
            payload.pid,
            payload.poll(),
            reason,
            rss,
            time.monotonic() - started,
            observation,
            supervision_error,
        )
    finally:
        if payload is not None:
            _signal_group(payload.pid, signal.SIGKILL)
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    limit = float(argv[0])
    command = argv[argv.index("--") + 1 :]
    result = supervise(limit, command)
    if result.child_exit is None or result.supervision_error or not result.cleanup_confirmed:
        return 125
    return result.child_exit


if __name__ == "__main__":
    sys.exit(main())

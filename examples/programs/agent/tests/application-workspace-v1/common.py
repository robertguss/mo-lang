"""Shared paths, guarded invocation and proportionate evidence for application workspace v1."""
import contextlib
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
AGENT = ROOT / 'examples/programs/agent'
EVIDENCE = HERE / 'evidence'
MO = os.environ.get('MO_BIN', str(ROOT / 'toolchain/zig-out/bin/mo'))
GUARD = ROOT / 'toolchain/bench/step36/guard.py'

def invoke(args, seconds, cwd=ROOT, env=None, keep=4 << 20):
    """A guarded child in its own process group, killed with the group on every path.

    exit_code is only ever the return code actually observed from the guard process; the
    wrapper's own outcome (exited, outer_timeout, launch_error) and its reason are separate
    fields, so an outer interruption never substitutes a synthetic code for an observed one.
    At most `keep` bytes of each stream are read back."""
    command = [sys.executable, str(GUARD), str(seconds), '--'] + [str(a) for a in args]
    outcome, reason, code = 'exited', None, None
    started = time.monotonic()
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        try:
            proc = subprocess.Popen(command, cwd=cwd, env=env, stdout=out, stderr=err,
                                    start_new_session=True)
        except OSError as exc:
            return dict(command=command, exit_code=None, outcome='launch_error', reason=repr(exc),
                        elapsed_s=0.0, stdout='', stderr='')
        try:
            proc.wait(timeout=seconds + 5)
        except subprocess.TimeoutExpired:
            outcome, reason = 'outer_timeout', f'guard did not exit within {seconds + 5}s'
        finally:
            with contextlib.suppress(ProcessLookupError, PermissionError):
                os.killpg(proc.pid, signal.SIGKILL)
            code = proc.wait()
        out.seek(0)
        err.seek(0)
        stdout, stderr = out.read(keep), err.read(keep)
    stderr = stderr.decode(errors='replace')
    return dict(command=command, exit_code=code, outcome=outcome, reason=reason,
                guard_killed='guard: killed' in stderr, elapsed_s=round(time.monotonic() - started, 3),
                stdout=stdout.decode(errors='replace'), stderr=stderr)


def retain_source(path, directory):
    """Keep a source copy as a non-.mo artifact, with its repository path and SHA-256."""
    path = Path(path).resolve()
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    target = directory / (path.name + '.' + digest[:12] + '.txt')
    target.write_bytes(data)
    return dict(path=str(path.relative_to(ROOT)), retained=str(target), sha256=digest)


class Attempt:
    """One retained attempt: a JSONL file of commands, real exit codes, summaries and failures."""

    def __init__(self, name):
        EVIDENCE.mkdir(exist_ok=True)
        self.path = EVIDENCE / (name + '.jsonl')
        if self.path.exists():
            raise SystemExit(f'{self.path} exists; attempts are never overwritten')
        self.failed = False

    def record(self, row):
        self.failed |= not row.get('passed', False)
        with self.path.open('a') as out:
            out.write(json.dumps(row) + '\n')
        print(json.dumps({k: row[k] for k in row if k not in ('stdout', 'stderr', 'output')}), flush=True)
        return row


def summary(text):
    """A test runner's count line when it printed one, else the last non-empty line."""
    lines = [line for line in text.splitlines() if line.strip()]
    counts = [line for line in lines if ' passed, ' in line and ' failed' in line]
    return (counts or lines or [''])[-1][:400]


def trimmed(row, passed):
    """Keep the command, exit, summary; full output only when something failed."""
    row = dict(row)
    row['summary'] = summary(row.get('stdout', '')) or summary(row.get('stderr', ''))
    row['passed'] = passed
    if passed:
        row.pop('stdout', None)
        row.pop('stderr', None)
    else:
        row['stdout'] = row.get('stdout', '')[-8192:]
        row['stderr'] = row.get('stderr', '')[-8192:]
    return row

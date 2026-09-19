"""Shared paths, guarded invocation and proportionate evidence for application workspace v1."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
AGENT = ROOT / 'examples/programs/agent'
EVIDENCE = HERE / 'evidence'
MO = os.environ.get('MO_BIN', str(ROOT / 'toolchain/zig-out/bin/mo'))
GUARD = ROOT / 'toolchain/bench/step36/guard.py'

# RED baseline: the inherited coding-fixture-v1 wrapper, imported read-only.
sys.path.insert(0, str(AGENT / 'tests/coding-fixture-v1'))
from run import invoke  # noqa: E402,F401


def retain_source(path, directory):
    """RED baseline: keep a source copy under evidence."""
    path = Path(path)
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / path.name
    shutil.copy2(path, target)
    return dict(path=str(path), retained=str(target), sha256=hashlib.sha256(path.read_bytes()).hexdigest())


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
    """The last non-empty line a tool printed: its own count or verdict."""
    lines = [line for line in text.splitlines() if line.strip()]
    return lines[-1] if lines else ''


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

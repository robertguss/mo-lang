"""Paths, the scripted model, guarded invocation and small evidence for the end-to-end run.

The scripted loopback model, the guarded child wrapper and the Book readers are the accepted
application-workspace-v1 test helpers, imported read-only from the sibling directory."""
import json
import os
from pathlib import Path
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
AGENT = ROOT / 'examples/programs/agent'
EXECUTOR = ROOT / 'toolchain/harness/executor'
EVIDENCE = HERE / 'evidence'
MO = os.environ.get('MO_BIN', str(ROOT / 'toolchain/zig-out/bin/mo'))
# Prepared trees, service directories and native builds live outside examples/.
WORK = Path(os.environ.get('MO_E2E_WORK', Path(tempfile.gettempdir()) / 'mo-e2e-v1'))

sys.path.insert(0, str(EXECUTOR))
sys.path.insert(0, str(HERE.parent / 'application-workspace-v1'))
from common import invoke, summary  # noqa: E402,F401  (application-workspace-v1 helpers)
import fake_bridge  # noqa: E402
from matrix import done, steps_in, tool  # noqa: E402,F401

Model = fake_bridge.Model
SCHEMA = 'mo-application-workspace-v1'


class Attempt:
    """One retained attempt: JSONL rows with commands, real exit codes, summaries, failures."""

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
        brief = {k: row[k] for k in ('part', 'case', 'runtime', 'passed', 'exit_code', 'elapsed_s', 'summary') if k in row}
        brief['failed_checks'] = [k for k, v in row.get('checks', {}).items() if not v]
        print(json.dumps(brief), flush=True)
        return row

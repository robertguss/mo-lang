"""Bounded source-only local tests; all scratch and logs stay beside this file."""
import os
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
SOURCE = REPO / 'toolchain/harness/executor'

def main():
    scratch = HERE / 'tmp'
    scratch.mkdir(exist_ok=True)
    env = dict(os.environ, TMPDIR=str(scratch), PYTHONDONTWRITEBYTECODE='1', PYTHONPATH=str(SOURCE))
    # Exclude test_exact_mount_policy: it consumes an archived evidence fixture.
    core = "import unittest,test_workspace; s=unittest.defaultTestLoader.loadTestsFromModule(test_workspace); flat=[t for group in s for t in group if t._testMethodName!='test_exact_mount_policy']; r=unittest.TextTestRunner(verbosity=2).run(unittest.TestSuite(flat)); raise SystemExit(not r.wasSuccessful())"
    commands = [('workspace', [sys.executable, '-B', '-c', core], 40),
                ('http', [sys.executable, '-B', '-m', 'workspace_http.local'], 100)]
    for label, command, seconds in commands:
        result = subprocess.run(command, cwd=SOURCE, env=env, capture_output=True, timeout=seconds)
        (HERE / (label + '-tests.log')).write_bytes(result.stdout + result.stderr)
        print(label, 'exit=', result.returncode)
        print((result.stdout + result.stderr).decode(errors='replace'))
        if result.returncode:
            raise SystemExit(result.returncode)

if __name__ == '__main__':
    main()

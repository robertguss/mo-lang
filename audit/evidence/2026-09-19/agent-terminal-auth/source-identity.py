"""Compare integrated auth files with the reviewed worker tip without history-scope assumptions."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[4]
OUT = Path(__file__).resolve().parent
WORKER = 'ebbf86c7361131aca58e936b7e3e994544fe49ec'
BASE = 'ff669fd52e93ccf6aa970b05082d842c471cb1c9'
paths = subprocess.check_output(['git', 'diff', '--name-only', BASE, WORKER], cwd=ROOT, text=True).splitlines()
rows = {}
for path in paths:
    expected = subprocess.check_output(['git', 'show', WORKER + ':' + path], cwd=ROOT)
    actual = (ROOT / path).read_bytes()
    assert expected == actual, path
    rows[path] = hashlib.sha256(actual).hexdigest()
generic = 'examples/recipes/model-client.mo'
assert (ROOT / generic).read_bytes() == subprocess.check_output(['git', 'show', BASE + ':' + generic], cwd=ROOT)
status = json.loads((OUT / 'attempt-03/native-suite.status.json').read_text())
assert status['exit_code'] == 0 and not status['cleanup_before'] and not status['cleanup_after']
receipt = {'lead_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
           'worker_tip': WORKER, 'base': BASE, 'matching_changed_files': rows,
           'generic_recipe_byte_identical': True, 'full_suite_status': status}
with (OUT / 'final-source-identity.json').open('x') as output:
    output.write(json.dumps(receipt, indent=2) + '\n')
print(len(rows), 'files exactly match reviewed worker tip; generic unchanged')

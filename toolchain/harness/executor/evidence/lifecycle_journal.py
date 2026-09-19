import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from adapter import remote
root = Path(__file__).parent / 'lifecycle-live-01'
name = json.loads((root / 'collector-gap/manifest.json').read_text())['name']
raw = remote(['journalctl', '--no-pager', '-n', '30', '-o', 'cat', '-u', name + '.service'])
print(raw.decode())
assert b'status=1/FAILURE' in raw, 'ExecStopPost failure was not observed'

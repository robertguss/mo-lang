"""Independent live control: explicit shell exit 137 is not a proven SIGKILL."""
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'toolchain/harness/executor'))
from adapter import Run

run = Run("printf 'explicit-exit\\n'; exit 137", [
    {'id': 'stimulus', 'stream': 'stdout', 'mode': 'exact', 'expected': 'explicit-exit\n'},
], Path(sys.argv[1]), seconds=5)
try:
    run.start()
finally:
    try:
        result = run.collect()
    finally:
        run.dispose()
observation = result['observation']
assert result['checks'][0]['passed']
assert observation['exit_code'] == 137
assert observation['signal'] is None
assert not observation['timed_out'] and not observation['cancelled']
assert observation['cleanup']['host_confirmed'] and observation['cleanup']['host_cgroup_absent']
assert not result['passed']
print(json.dumps({'controls': 1, 'passed': True, 'exit_code': observation['exit_code'],
                  'signal': observation['signal'], 'signal_hint': observation.get('signal_hint'),
                  'status': observation['status']}, indent=2))

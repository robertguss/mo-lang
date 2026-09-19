"""Independent multi-execution response ordering and identity controls."""
import copy
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'toolchain/harness/executor'))
from recovery import validate_response

out = Path(sys.argv[1])
out.mkdir(exist_ok=False)
ids = ['1' * 32, '2' * 32, '3' * 32]
receipt = {'run_id': 'a' * 32, 'workspace_id': 'b' * 32,
           'executions': [{'execution_id': eid} for eid in ids]}
base = {'run_id': receipt['run_id'], 'workspace_id': receipt['workspace_id'],
        'cleanup': 'confirmed', 'execution': 'unknown',
        'completed': ['terminal_barrier', *ids, 'workspace_deleted'], 'unresolved': []}
records = []


def check(name, response, valid):
    try:
        result = validate_response(json.dumps(response).encode(), receipt)
    except ValueError:
        accepted = False
    else:
        assert result == response
        accepted = True
    records.append({'case': name, 'expected_valid': valid, 'accepted': accepted, 'response': response})
    (out / 'results.json').write_text(json.dumps(records, indent=2))
    assert accepted == valid, name


check('complete-ordered-three', base, True)
for count in range(4):
    value = {**base, 'cleanup': 'unresolved', 'error': 'cleanup_unknown',
             'completed': ['terminal_barrier', *ids[:count]], 'unresolved': ids[count:]}
    check('valid-prefix-' + str(count), value, True)
    if count < 3:
        check('omitted-unresolved-' + str(count), {**value, 'unresolved': ids[count + 1:]}, False)
    if count:
        check('duplicate-completed-' + str(count), {**value, 'completed': value['completed'] + [ids[count - 1]]}, False)
check('before-terminal', {**base, 'cleanup': 'unresolved', 'error': 'cleanup_unknown',
                         'completed': [], 'unresolved': ids}, True)
for name, key, replacement in [
    ('foreign-run', 'run_id', 'c' * 32), ('foreign-workspace', 'workspace_id', 'd' * 32),
    ('reordered-completed', 'completed', ['terminal_barrier', ids[1], ids[0], ids[2], 'workspace_deleted']),
    ('duplicate-completed-final', 'completed', ['terminal_barrier', ids[0], ids[0], ids[2], 'workspace_deleted']),
    ('foreign-completed', 'completed', ['terminal_barrier', ids[0], ids[1], 'f' * 32, 'workspace_deleted']),
    ('premature-delete', 'completed', ['terminal_barrier', ids[0], 'workspace_deleted']),
    ('unresolved-on-confirmation', 'unresolved', [ids[2]]),
    ('execution-success', 'execution', 'success'), ('error-on-confirmation', 'error', 'cleanup_unknown')]:
    value = copy.deepcopy(base)
    value[key] = replacement
    check(name, value, False)
print(json.dumps({'passed': len(records), 'expected': 21}), flush=True)
assert len(records) == 21

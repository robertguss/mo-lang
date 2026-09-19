"""Lose the reply after real cleanup, then explicitly recover the same ownership."""
import json
from pathlib import Path
import sys
import time
import uuid
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'toolchain/harness/executor'))
import adapter
from recovery import recover
from workspace import Workspace

out = Path(sys.argv[1])
out.mkdir(exist_ok=False)
ws = Workspace(uuid.uuid4().hex, out / 'workspace')
receipt_path = ws.directory / 'ownership.json'
try:
    ws.create({'answer.txt': b'unchanged\n'})
    run = ws.start_command('echo lead-recovery; sleep 30 & wait', seconds=10)
    end = time.monotonic() + 5
    registration = None
    while time.monotonic() < end:
        value = json.loads(adapter.py('''import json,pathlib,subprocess,sys
root=pathlib.Path(sys.argv[1]); p=root/'registration.json'
q=subprocess.run(['docker','inspect',root.name],capture_output=True,timeout=3)
print(json.dumps({'registration':json.loads(p.read_text()) if p.exists() else None,
 'running':bool(q.returncode==0 and json.loads(q.stdout)[0]['State']['Running'])}))
''', run.root))
        if value['registration'] and value['running']:
            registration = value
            break
        time.sleep(.1)
    assert registration, 'candidate did not reach running state'
    (out / 'running.json').write_text(json.dumps(registration, indent=2))
    before = receipt_path.read_bytes()
    original_remote = adapter.remote
    observed = []

    def lose_reply(*args, **kwargs):
        raw = original_remote(*args, **kwargs)
        response = json.loads(raw)
        observed.append(response)
        (out / 'remote-completed-before-reply-loss.json').write_text(json.dumps(response, indent=2))
        assert response['cleanup'] == 'confirmed' and response['execution'] == 'unknown'
        assert response['unresolved'] == []
        raise TimeoutError('lead injected lost reply after actual cleanup')

    # Explicit owner-object loss; this is not a claim of process-death injection.
    ws.__del__()
    with patch.object(adapter, 'remote', side_effect=lose_reply):
        lost = recover(receipt_path, seconds=30)
    assert len(observed) == 1
    assert observed[0]['cleanup'] == 'confirmed' and observed[0]['execution'] == 'unknown', observed
    assert observed[0]['unresolved'] == [], observed
    assert lost['cleanup'] == 'unresolved' and lost['execution'] == 'unknown', lost
    repeated = recover(receipt_path, seconds=30)
    assert repeated['cleanup'] == 'confirmed' and repeated['execution'] == 'unknown', repeated
    assert repeated['unresolved'] == []
    assert receipt_path.read_bytes() == before
    assert len(list(ws.directory.glob('execution-*'))) == 1
    (out / 'results.json').write_text(json.dumps({'lost': lost, 'repeated': repeated,
        'ownership_unchanged': True, 'execution_directories': 1, 'original_execution': 'unknown'}, indent=2))
    print(json.dumps({'passed': 1, 'expected': 1, 'fault_after_actual_cleanup': True}), flush=True)
finally:
    ws.__del__()
    cleanup = recover(receipt_path, seconds=30)
    (out / 'final-cleanup.json').write_text(json.dumps(cleanup, indent=2))
    assert cleanup['cleanup'] == 'confirmed', cleanup

"""The accepted Bridge frontend, local only: its framing, admission and projection with the
accepted test_owner subprocess double (as workspace_http/local.py starts it), never the machine.
Usage: real_bridge.py interpreter|native ATTEMPT

four-files: read_file, search, write_file and exact_edit through the real frontend, then an
answer (exit 0). The double's own outcomes are not all ones the real producer makes, and the
adapter refuses those as invalid (unknown) and stops: double-list, whose rows lack the core's
length/sha256/mode, and double-command, a success with exit code 7. The trailing owner event
'delete' is the double's cleanup at close."""
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

from common import ROOT, Attempt, invoke, trimmed
import fake_bridge as fb
from matrix import MAIN, NATIVE, SCHEMA, done, steps_in, tool

sys.path.insert(0, str(ROOT / 'toolchain/harness/executor'))
from workspace_http import Bridge  # noqa: E402
import workspace_http.bridge as bridge_module  # noqa: E402
from remote import IMAGE, WORKSPACE_POLICY  # noqa: E402

CASES = {
    'four-files': ([tool('read_file', path='a'), tool('search', query='q'), tool('write_file', path='a', text='t'),
                    tool('exact_edit', path='a', old_text='o', new_text='n'), done('four')], 0),
    'double-list': ([tool('list_files', path='.'), done()], 3),
    'double-command': ([tool('command', command='make'), done()], 3),
}


def started(tmp):
    bridge = Bridge('r_1', Path(tmp) / 'bridge', {'scenario': b''},
                    selection={'policy': WORKSPACE_POLICY, 'image': IMAGE, 'toolchain': None},
                    verifier={'script': 'protected', 'checks': [{'id': 'protected', 'stream': 'stdout', 'mode': 'exact', 'expected': 'ok'}], 'seconds': 1})
    real = bridge_module.subprocess.Popen

    def launch(argv, **options):
        argv = list(argv)
        argv[argv.index('workspace_http.owner')] = 'workspace_http.test_owner'
        return real(argv, **options)
    with patch('workspace_http.bridge.subprocess.Popen', side_effect=launch):
        bridge.start()
    return bridge


def run_case(name, runtime):
    replies, expected = CASES[name]
    with tempfile.TemporaryDirectory(prefix='mo-app-real-') as tmp:
        tmp = Path(tmp)
        root = tmp / 'root'
        (root / 'work').mkdir(parents=True)
        log = root / 'runs/r_1.log'
        bridge = started(tmp)
        model = fb.Model(replies, observe=lambda: steps_in(log))
        config = tmp / 'private/bridge.json'
        config.parent.mkdir(mode=0o700)
        config.write_text(json.dumps(dict(version='mo-workspace-http-v1', port=bridge.port, run_id='r_1',
                                          workspace_id=bridge.workspace_id, token=bridge.token)))
        config.chmod(0o600)
        prefix = [MO_RUN, 'run', str(MAIN), '--'] if runtime == 'interpreter' else [str(NATIVE)]
        row = invoke(prefix + ['application-workspace', str(root), '--model', f'127.0.0.1:{model.port}',
                               '--config', str(config), 'use', 'the', 'real', 'frontend'], 120, cwd=tmp)
        model.close()
        closed = bridge.close(seconds=5)
        if not closed:
            bridge.stop_owner()
        events = (Path(tmp) / 'bridge/workspace/events')
        ops = events.read_text().split() if events.exists() else []
        lines = [json.loads(l) for l in row['stdout'].splitlines() if l.startswith('{')]
        terminal = [l['payload'] for l in lines if l.get('event') == 'terminal']
        tools_out = [l['payload']['result'] for l in lines if l.get('event') == 'tool']
        token = bridge.token
        checks = dict(exit_code=row['exit_code'] == expected, schema=bool(lines) and all(l.get('schema') == SCHEMA for l in lines),
                      token_absent=token not in row['stdout'] + row['stderr'] + (log.read_text() if log.exists() else ''),
                      owner_closed=closed)
        if name == 'four-files':
            checks.update(remote_ops=ops == ['create', 'read_file', 'search', 'write_file', 'exact_edit', 'delete'],
                          all_accepted=all(isinstance(t, dict) and t.get('accepted') is True and t.get('state') == 'success' for t in tools_out),
                          done=[t.get('state') for t in terminal] == ['done'])
        else:
            checks.update(remote_ops=ops == ['create', 'list_files' if name == 'double-list' else 'command', 'delete'],
                          refused_invalid=tools_out == [dict(adapter=SCHEMA, state='failure', execution='unknown', error='invalid_response')],
                          stopped=[t.get('error') for t in terminal] == ['uncertain_or_terminal_tool'],
                          model_once=len(model.requests) == 1)
        row = dict(row, case=name, runtime=runtime, checks=checks, owner_events=ops)
        return trimmed(row, all(checks.values()))


def main():
    runtime, attempt_name = sys.argv[1], sys.argv[2]
    if runtime not in ('interpreter', 'native'):
        raise SystemExit('runtime')
    attempt = Attempt(attempt_name)
    if runtime == 'native' and not NATIVE.is_file():
        attempt.record(dict(check='native-executable', passed=False, error='build it with matrix.py native first'))
        sys.exit(1)
    for name in CASES:
        attempt.record(run_case(name, runtime))
    sys.exit(int(attempt.failed))


from common import MO as MO_RUN  # noqa: E402

if __name__ == '__main__':
    main()

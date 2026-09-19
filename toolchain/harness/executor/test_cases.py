"""The live-suite runner and tables, locally. The suites run end to end against a
stand-in `orbctl` (an empty machine: inventories and cleanup-only recovery answer,
everything else fails) and `docker` (a fixed Mac baseline), so no case can pass;
what is tested is the table, the records, cleanup and the summary line."""
import argparse
from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

import cases

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]

# Every live case, by name and in order, as the suites had them before step 2.
LIVE = {
    'selftest.py': ['completion-descendants', 'wrong-output', 'nonzero', 'forged-success', 'overwrite-authority',
                    'fault-stimulus-control', 'absent-fault-stimulus', 'timeout-descendants', 'cancel-descendants',
                    'output-overflow', 'cpu-enforcement', 'memory-enforcement', 'pid-enforcement', 'scratch-enforcement',
                    'network-filesystem-denial', 'controller-death', 'supervisor-death'],
    'test_workspace_live.py': ['invalid-import-never-ready', 'real-failure-inspection-repair-success',
                               'duplicate-foreign-calls', 'invalid-paths-utf8-overlap', 'freeze-independent-positive',
                               'closed-dispatch-and-empty-checks', 'missing-stimulus-and-result-overwrite',
                               'wrong-candidate-forged-success', 'final-symlink', 'intermediate-symlink', 'hardlink',
                               'fifo', 'unsupported-mode', 'tmpfs-byte-quota', 'tmpfs-inode-quota', 'timeout-descendants',
                               'cancel-descendants', 'exit-descendants', 'supervisor-death-mounted',
                               'controller-death-mounted', 'stale-mutated-snapshot', 'snapshot-permission-drift'],
    'recovery/live.py': ['create-before', 'create-response', 'reserve-response', 'registration-before-reaper',
                         'active-owner-death', 'finalize-gap', 'complete-gap', 'dispose-gap', 'repeated-cleanup',
                         'foreign-identity', 'malformed-linked', 'lock-contention', 'unknown-transport',
                         'late-bootstrap', 'application-active', 'application-snapshot'],
    'workspace_http/live.py': ['six-tools', 'output-encoding', 'schema', 'framing', 'byte-bounds',
                               'identities-capability', 'duplicate-calls', 'concurrent-admission', 'file-refusals',
                               'deadlines', 'disconnect', 'frontend-death', 'owner-death', 'lost-response',
                               'owner-stall', 'startup-failure', 'shutdown', 'protected-verifier',
                               'application-binding', 'cleanup-outcome', 'invalid-selection', 'journal-order-bound'],
    'application/controls.py': ['hello-cold-build', 'logstat-cold-build', 'snapshot-rebuild', 'failed-build-no-stale',
                                'scratch-fresh', 'source-noexec', 'image-root-immutable', 'snapshot-immutable',
                                'output-bound', 'timeout-descendants', 'cancel-descendants', 'exit-descendants',
                                'supervisor-death', 'controller-death', 'build-quota', 'tmp-quota',
                                'effective-resources', 'empty-checks', 'policy-rebind', 'forged-verdict',
                                'cpu-enforcement', 'pids-enforcement', 'memory-enforcement'],
}
APPLICATION = ['--image', cases.APPLICATION_IMAGE, '--toolchain', cases.APPLICATION_TOOLCHAIN]

ORBCTL = r'''#!/usr/bin/env python3
import json, sys
argv = sys.argv[1:]
cmd = argv[argv.index('root') + 1:] if 'root' in argv else argv
def done(value): print(value); sys.exit(0)
if cmd[:1] in (['docker'], ['systemctl']): done('')
if cmd[:2] == ['python3', '-c']:
    src, args = cmd[2], cmd[3:]
    if "r={'directories'" in src:
        r = {k: {'exit': 0, 'stdout': ''} for k in ('containers', 'units')}
        r.update(directories=[], mounts={'exit': 0, 'stdout': '{}'})
        if args[1:] == ['1']: r['application_tasks'] = {'exit': 0, 'stdout': ''}
        done(json.dumps(r))
    if 'rows=json.load(sys.stdin)' in src:
        done(json.dumps([{'workspace_id': r['workspace_id'], 'root_exists': False, 'mounts': [], 'executions': [
            {'id': e['execution_id'], 'root_exists': False, 'containers': '', 'units': '', 'cgroup': None,
             'cgroup_exists': False} for e in r['executions']]} for r in json.load(sys.stdin)]))
    if "sys.modules['recovery_machine'].recover" in src:
        r = json.load(sys.stdin)['receipt']
        done(json.dumps({'run_id': r['run_id'], 'workspace_id': r['workspace_id'], 'cleanup': 'confirmed',
                         'execution': 'unknown', 'unresolved': [], 'completed': ['terminal_barrier',
                         *[e['execution_id'] for e in r['executions']], 'workspace_deleted']}))
print('stand-in: no machine', file=sys.stderr)
sys.exit(1)
'''
DOCKER = '''#!/bin/sh
if [ "$1" = ps ]; then printf 'a1 running\\na2 running\\na3 exited\\na4 running\\na5 exited\\n'; exit 0; fi
exit 1
'''


class Runner(unittest.TestCase):
    def test_records_stop_and_after(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'records.json'
            ran = []
            def fails():
                raise ValueError('boom')
            table = [('a', lambda: {'extra': 1}), ('b', fails), ('c', lambda: None)]
            run = cases.Cases(path, key='group', stop=True)
            with redirect_stdout(io.StringIO()):
                run.run(table, cases.names(table), after=lambda: ran.append('after'))
            self.assertEqual([(r['group'], r['ok']) for r in run.records], [('a', True), ('b', False)])
            self.assertEqual((run.records[0]['extra'], ran), (1, ['after']))
            self.assertIn('ValueError: boom', run.records[1]['error'])
            self.assertEqual(json.loads(path.read_text()), run.records)
            self.assertFalse(run.complete(['a', 'b']))

    def test_choose_refuses_before_anything(self):
        parser = argparse.ArgumentParser()
        for selected in ([], ['a', 'a'], ['z']):
            with self.subTest(selected=selected), self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
                cases.choose(parser, ('a', 'b'), selected)
        self.assertEqual(cases.choose(parser, ('a', 'b'), ['b', 'a']), ['b', 'a'])

    def test_cleanup_failure_never_hides_the_case_failure(self):
        def cleanup():
            raise OSError('cleanup')
        with self.assertRaises(ValueError) as caught:
            with cases.then(cleanup):
                raise ValueError('case')
        self.assertIn('OSError: cleanup', caught.exception.__notes__[0])
        with self.assertRaises(OSError), cases.then(cleanup):
            pass

    def test_shared_creation_failure_is_kept(self):
        made = []
        def make(name):
            made.append(name)
            raise OSError('first')
        shared = cases.Shared(make)
        with self.assertRaises(OSError):
            shared('w')
        with self.assertRaisesRegex(RuntimeError, "'w' was not created"):
            shared('w')
        self.assertEqual(made, ['w'])


class Tables(unittest.TestCase):
    def table(self, suite):
        sys.path.insert(0, str(HERE / 'application'))
        import selftest, test_workspace_live, controls
        from recovery import live as recovery_live
        from workspace_http import live as http_live, local
        tables = {'selftest.py': cases.names(selftest.CASES), 'test_workspace_live.py': cases.names(test_workspace_live.CONTROLS),
                  'recovery/live.py': recovery_live.GROUPS, 'workspace_http/live.py': tuple(http_live.TABLE),
                  'application/controls.py': controls.CONTROLS}
        self.assertEqual(local.GROUPS, tables['workspace_http/live.py'])
        return list(tables[suite])

    def test_no_case_lost_or_reordered(self):
        for suite, names in LIVE.items():
            with self.subTest(suite=suite):
                self.assertEqual(self.table(suite), names)

    def test_selection_refused_before_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / 'never'
            for script, flag, bad in (('workspace_http/live.py', '--groups', ['six-tools,six-tools']),
                                      ('application/controls.py', '--controls', ['unknown']),
                                      ('recovery/live.py', '--groups', ['create-before', 'create-before'])):
                with self.subTest(script=script):
                    extra = APPLICATION if script.startswith('application') else []
                    p = subprocess.run([sys.executable, '-B', str(HERE / script), str(output), *extra, flag, *bad],
                                       capture_output=True, timeout=10)
                    self.assertEqual((p.returncode, p.stdout, output.exists()), (2, b'', False))


class Offline(unittest.TestCase):
    """Each suite's own command line against the stand-in machine: every case fails
    fast and is recorded, cleanup runs, and the summary keeps its shape."""

    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        root = Path(cls.temp.name)
        (root / 'bin').mkdir()
        for name, text in (('orbctl', ORBCTL), ('docker', DOCKER)):
            (root / 'bin' / name).write_text(text)
            (root / 'bin' / name).chmod(0o755)
        cls.env = dict(os.environ, PATH=str(root / 'bin') + os.pathsep + os.environ['PATH'])

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def suite(self, script, *extra):
        output = Path(self.temp.name) / ('out-' + script.replace('/', '-'))
        p = subprocess.run([sys.executable, '-B', str(HERE / script), str(output), *extra],
                           capture_output=True, text=True, timeout=120, env=self.env, cwd=REPO)
        self.assertEqual(p.returncode, 1, p.stderr[-2000:])
        return output, [json.loads(line) for line in p.stdout.splitlines() if line.startswith('{"')], p.stdout

    def failed_offline(self, record):
        self.assertFalse(record['ok'])
        self.assertRegex(record['error'].strip().splitlines()[-1],
                         r"stand-in: no machine|was not created|^EOFError$")

    def test_selftest(self):
        output, _, stdout = self.suite('selftest.py')
        summary = json.loads((output / 'summary.json').read_text())
        self.assertEqual((summary['count'], summary['passed']), (17, 0))
        self.assertEqual([r['case'] for r in summary['cases']], LIVE['selftest.py'])
        self.assertIn('"count": 17,', stdout)
        for record in summary['cases']:
            self.failed_offline(record)

    def test_workspace_live(self):
        _, lines, _ = self.suite('test_workspace_live.py')
        records, summary = lines[:-1], lines[-1]
        self.assertEqual([r['case'] for r in records], LIVE['test_workspace_live.py'])
        self.assertEqual((summary['controls'], summary['passed']), (22, 0))
        for record in records:
            self.failed_offline(record)

    def test_application(self):
        try:
            output, lines, _ = self.suite('application/controls.py', *APPLICATION)
        finally:
            # The fixture cache is named after the output directory.
            shutil.rmtree(HERE / 'application/.cache/out-application-controls.py', ignore_errors=True)
        records, summary = lines[:-1], lines[-1]
        self.assertEqual([r['case'] for r in records], LIVE['application/controls.py'])
        self.assertEqual((summary['controls'], summary['passed']), (23, 0))
        for record in records:
            self.failed_offline(record)

    def test_stopping_suites(self):
        for script, first in (('recovery/live.py', 'create-before'), ('workspace_http/live.py', 'six-tools')):
            with self.subTest(script=script):
                output, lines, _ = self.suite(script)
                self.assertEqual(lines[0]['group'], first)
                self.failed_offline(lines[0])
                if script == 'recovery/live.py':
                    self.assertEqual(lines[1], {'groups': 1, 'passed': 0})
                else:
                    self.assertEqual(len(lines), 1)  # the summary line prints only when every group passed
                    self.assertTrue((output / 'failure.json').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)

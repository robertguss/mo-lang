"""Tests for Fable's receiver and publisher. Explicit fixtures only; no GitHub calls."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

import fable_poll as fp

SHA = 'a' * 40


def record(**over):
    m = {'id': 'step-36-reading-filed-001', 'subject': 'step-36', 'from': 'auditor', 'to': 'fable',
         'kind': 'reading-filed', 'in_reply_to': 'step-36-ready-001', 'evidence_commit': SHA,
         'paths': ['audit/mo-audit-2026-09-18-step-36.md'], 'request': 'Reading filed; pointers only.'}
    m.update(over)
    return m


class ToFable(unittest.TestCase):
    def path(self, m):
        return f"audit/handoffs/{m['subject']}/{m['id']}.json"

    def test_valid_auditor_record(self):
        m = record()
        self.assertIs(fp.validate(m, self.path(m), 'to-fable'), m)

    def test_evidence_needed_is_accepted(self):
        m = record(kind='evidence-needed', id='step-36-evidence-needed-001', paths=['audit/evidence/2026-09-18/step-36/run.log'])
        fp.validate(m, self.path(m), 'to-fable')

    def test_fable_kinds_are_not_auditor_kinds(self):
        m = record(kind='ready')
        with self.assertRaises(ValueError):
            fp.validate(m, self.path(m), 'to-fable')

    def test_wrong_recipient(self):
        m = record(to='auditor')
        with self.assertRaises(ValueError):
            fp.validate(m, self.path(m), 'to-fable')

    def test_wrong_sender(self):
        m = record(**{'from': 'fable'})
        with self.assertRaises(ValueError):
            fp.validate(m, self.path(m), 'to-fable')

    def test_extra_field_rejected(self):
        m = record(verdict='fit to ship')
        with self.assertRaises(ValueError):
            fp.validate(m, self.path(m), 'to-fable')

    def test_path_id_mismatch(self):
        m = record()
        with self.assertRaises(ValueError):
            fp.validate(m, 'audit/handoffs/step-36/other.json', 'to-fable')

    def test_short_sha_rejected(self):
        m = record(evidence_commit='abc123')
        with self.assertRaises(ValueError):
            fp.validate(m, self.path(m), 'to-fable')

    def test_traversing_path_rejected(self):
        m = record(paths=['audit/../HANDOFF.md'])
        with self.assertRaises(ValueError):
            fp.validate(m, self.path(m), 'to-fable')

    def test_uppercase_id_rejected(self):
        m = record(id='Step-36-001')
        with self.assertRaises(ValueError):
            fp.validate(m, self.path(m), 'to-fable')

    def test_canary_only_with_canary_direction(self):
        m = record(kind='transport-test', to='auditor', subject='automation-transport-test', id='canary-001',
                   in_reply_to=None, paths=['audit/WORKFLOW.md'])
        with self.assertRaises(ValueError):
            fp.validate(m, self.path(m), 'to-fable')
        fp.validate(m, self.path(m), 'canary')


class FromFable(unittest.TestCase):
    def path(self, m):
        return f"audit/handoffs/{m['subject']}/{m['id']}.json"

    def ready(self, **over):
        m = record(**{'from': 'fable'}, to='auditor', kind='ready', id='step-36-ready-001', in_reply_to=None,
                   paths=['audit/evidence/2026-09-18/step-36/run.log', 'mo-wiki/plans/interpreter-step-36.md'],
                   request='Scope: the TLS server brick; the sealed brief and the raw outputs.')
        m.update(over)
        return m

    def test_valid_ready(self):
        m = self.ready()
        fp.validate(m, self.path(m), 'from-fable')

    def test_synthesis_pointer_forbidden(self):
        for bad in ('toolchain/bench/step36/RESULTS.md', 'mo-wiki/decisions/decision-log.md', 'audit/fable-reading-2026-09-18-step-36.md'):
            m = self.ready(paths=[bad])
            with self.assertRaises(ValueError):
                fp.validate(m, self.path(m), 'from-fable')

    def test_evidence_updated_needs_reply(self):
        m = self.ready(kind='evidence-updated', id='step-36-evidence-updated-001')
        with self.assertRaises(ValueError):
            fp.validate(m, self.path(m), 'from-fable')
        m['in_reply_to'] = 'step-36-evidence-needed-001'
        fp.validate(m, self.path(m), 'from-fable')

    def test_parallel_filed_needs_both_readings(self):
        m = self.ready(kind='parallel-filed', id='step-36-parallel-filed-001', paths=['audit/mo-audit-2026-09-18-step-36.md'])
        with self.assertRaises(ValueError):
            fp.validate(m, self.path(m), 'from-fable')
        m['paths'].append('audit/fable-reading-2026-09-18-step-36.md')
        fp.validate(m, self.path(m), 'from-fable')
        m['paths'].append('audit/evidence/2026-09-18/step-36/run.log')
        with self.assertRaises(ValueError):
            fp.validate(m, self.path(m), 'from-fable')

    def test_request_bounded(self):
        m = self.ready(request='x' * 2001)
        with self.assertRaises(ValueError):
            fp.validate(m, self.path(m), 'from-fable')


class Publish(unittest.TestCase):
    def test_publish_checks_paths_at_commit_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as d:
            subprocess.run(['git', 'init', '-q', d], check=True)
            subprocess.run(['git', '-C', d, 'config', 'user.email', 't@t'], check=True)
            subprocess.run(['git', '-C', d, 'config', 'user.name', 't'], check=True)
            (Path(d) / 'audit' / 'evidence').mkdir(parents=True)
            (Path(d) / 'audit' / 'evidence' / 'raw.log').write_text('1\n')
            subprocess.run(['git', '-C', d, 'add', '-A'], check=True)
            subprocess.run(['git', '-C', d, 'commit', '-q', '-m', 'e'], check=True)
            sha = subprocess.run(['git', '-C', d, 'rev-parse', 'HEAD'], capture_output=True, text=True, check=True).stdout.strip()
            argv = ['publish', '--kind', 'working', '--subject', 'transport-test', '--id', 'transport-test-working-001',
                    '--commit', sha, '--path', 'audit/evidence/raw.log', '--request', 'TEST', '--repo', d]
            self.assertEqual(fp.main(argv), 0)
            written = json.loads((Path(d) / 'audit/handoffs/transport-test/transport-test-working-001.json').read_text())
            self.assertEqual(written['from'], 'fable')
            self.assertEqual(written['evidence_commit'], sha)
            with self.assertRaises(SystemExit):
                fp.main(argv)  # the same id is never rewritten
            with self.assertRaises(SystemExit):
                fp.main(argv[:-4] + ['--id', 'transport-test-working-002', '--path', 'audit/evidence/missing.log', '--request', 'TEST', '--repo', d])


class Ledger(unittest.TestCase):
    def test_ledger_round_trip(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'sub' / 'ledger.json'
            self.assertEqual(fp.load_ledger(p), {'seen': {}})
            fp.save_ledger(p, {'seen': {'a': {'status': 'announced'}}})
            self.assertEqual(fp.load_ledger(p)['seen']['a']['status'], 'announced')


if __name__ == '__main__':
    unittest.main()

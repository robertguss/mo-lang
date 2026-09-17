"""Unit fixtures only; live transport is checked separately against GitHub/Hermes."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('poll', Path(__file__).with_name('poll.py'))
poll = importlib.util.module_from_spec(spec)
spec.loader.exec_module(poll)


class IntakeTests(unittest.TestCase):
    def setUp(self):
        self.m = dict(id='test-ready', subject='test-subject', **{'from': 'fable', 'to': 'auditor'},
                      kind='ready', in_reply_to=None, evidence_commit='a'*40,
                      paths=['audit/evidence/example/raw.log'], request='Inspect raw evidence.')
        self.path = 'audit/handoffs/test-subject/test-ready.json'

    def test_valid_raw_handoff(self):
        self.assertEqual(poll.validate(self.m, self.path), self.m)

    def test_bad_inputs_fail_closed(self):
        cases = [dict(evidence_commit='main'), dict(evidence_commit='A'*40),
                 dict(paths=['../private']), dict(paths=['/tmp/raw']),
                 dict(paths=['audit//evidence/raw']), dict(paths=['audit/evidence/../reading']),
                 dict(paths=['audit/fable-reading-test.md']),
                 dict(paths=['mo-wiki/decisions/decision-log.md']),
                 dict(paths=['audit/evidence/RESULTS.md']), dict(paths=[]),
                 dict(kind='run-command'), dict(kind='evidence-updated'),
                 dict(kind='transport-test'), {'from': 'auditor'}, {'to': 'fable'},
                 dict(id='x;touch'), dict(request='x'*2001), dict(extra='surprise')]
        for changes in cases:
            with self.subTest(changes=changes):
                m = copy.deepcopy(self.m)
                m.update(changes)
                with self.assertRaises(ValueError):
                    poll.validate(m, self.path)

    def test_id_path_mismatch(self):
        with self.assertRaises(ValueError):
            poll.validate(self.m, 'audit/handoffs/other/test-ready.json')

    def test_canary_is_separate(self):
        m = dict(self.m, kind='transport-test', **{'from': 'auditor'})
        poll.validate(m, self.path, canary=True)
        with self.assertRaises(ValueError):
            poll.validate(self.m, self.path, canary=True)

    def test_free_text_not_in_prompt(self):
        self.m['request'] = 'UNTRUSTED_VERDICT_MARKER'
        p = poll.make_prompt(self.m, 'b'*40, '/tmp/record', '/tmp/checkout', False)
        self.assertNotIn('UNTRUSTED_VERDICT_MARKER', p)
        self.assertIn('a'*40, p)
        self.assertIn('Do not open Fable', p)

    def test_comparison_requires_both_filed_readings(self):
        m = dict(self.m, kind='parallel-filed', paths=['audit/mo-audit-example.md', 'audit/fable-reading-example.md'])
        poll.validate(m, self.path)
        prompt = poll.make_prompt(m, 'b'*40, '/tmp/record', '/tmp/checkout', False)
        self.assertIn('NOT a new cold technical audit', prompt)
        for paths in [['audit/fable-reading-example.md'], ['audit/mo-audit-example.md'], ['audit/mo-audit-example.md', 'audit/fable-reading-example.md', 'mo-wiki/decisions/decision-log.md']]:
            with self.assertRaises(ValueError):
                poll.validate(dict(m, paths=paths), self.path)

    def test_canary_cannot_start_an_audit(self):
        p = poll.make_prompt(self.m, 'b'*40, '/tmp/record', '/tmp/checkout', True)
        self.assertIn('NOT an audit', p)
        self.assertNotIn(self.m['paths'][0], p)


if __name__ == '__main__':
    unittest.main()

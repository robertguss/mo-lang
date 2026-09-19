"""Run existing local controls and recovery tests without machine activity."""
import sys
from pathlib import Path
import unittest
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root))
suite = unittest.TestSuite()
for name in ('test_executor', 'test_workspace'):
    suite.addTests(unittest.defaultTestLoader.loadTestsFromName(name))
sys.path.insert(0, str(root / 'application'))
import test_policy
for cls in (test_policy.Policy, test_policy.Registration):
    for name in cls.__dict__:
        if name.startswith('test_'):
            suite.addTest(cls(name))
suite.addTests(unittest.defaultTestLoader.loadTestsFromName('test_package'))
suite.addTests(unittest.defaultTestLoader.discover(str(root / 'recovery'), pattern='test_recovery.py'))
sys.path.insert(0, str(root / 'recovery'))
from test_edges import Edges
suite.addTests(Edges(name) for name in Edges.__dict__ if name.startswith('test_'))
result = unittest.TextTestRunner(verbosity=2).run(suite)
sys.exit(not result.wasSuccessful())

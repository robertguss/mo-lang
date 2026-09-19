"""Run existing local controls and recovery tests without machine activity."""
import sys
from pathlib import Path
import unittest
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root))
suite = unittest.TestSuite()
for name in ('test_executor', 'test_workspace'):
    suite.addTests(unittest.defaultTestLoader.loadTestsFromName(name))
suite.addTests(unittest.defaultTestLoader.discover(str(root / 'recovery'), pattern='test_recovery.py'))
result = unittest.TextTestRunner(verbosity=2).run(suite)
sys.exit(not result.wasSuccessful())

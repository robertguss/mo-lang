"""Pre-fix control: a request-owned subprocess loses cleanup on disconnect.

This deliberately deficient baseline is retained, never used by the bridge.
Both failures assert the required lifecycle property after actual parent death.
"""
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

class RequestLifetime(unittest.TestCase):
    def test_disconnect_retains_cleanup(self):
        self.control('disconnect')

    def test_frontend_death_retains_cleanup(self):
        self.control('frontend-death')

    def control(self, reason):
        with tempfile.TemporaryDirectory() as tmp:
            effect, cleanup = Path(tmp, 'effect'), Path(tmp, 'cleanup')
            program = ('import pathlib,time; '
                       f'pathlib.Path({str(effect)!r}).touch(); '
                       'time.sleep(.3); '
                       f'pathlib.Path({str(cleanup)!r}).touch()')
            child = subprocess.Popen([sys.executable, '-c', program])
            deadline = time.monotonic() + 2
            while not effect.exists() and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertTrue(effect.exists())
            # The deficient request owner cancels its child when delivery ends.
            child.kill()
            self.assertEqual(child.wait(timeout=2), -signal.SIGKILL)
            time.sleep(.4)
            self.assertTrue(cleanup.exists(), reason + ': cleanup abandoned after effect')

if __name__ == '__main__':
    unittest.main(verbosity=2)

"""Live-test frontend process, killed by the operator only after registration."""
import json
from pathlib import Path
import sys
import time
from .bridge import Bridge

config = json.loads(Path(sys.argv[1]).read_bytes())
bridge = Bridge(config['run_id'], config['directory'], {'answer': b'before\n'},
                selection=config['selection'], verifier=config['verifier']).start()
try:
    while bridge.process.poll() is None:
        time.sleep(.1)
finally:
    bridge.close()

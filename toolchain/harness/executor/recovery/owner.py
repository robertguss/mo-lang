"""Live fault child; parent owns and kills this exact local process group."""
import json
from pathlib import Path
import sys
import time
import uuid
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from workspace import Workspace
import cases
ws = Workspace(uuid.uuid4().hex, sys.argv[1])
ws.create({'answer':b'owner death\n'})
run = ws.start_command('echo READY; sleep 100 & wait', seconds=10)
registered = cases.until(lambda: cases.registration(run.name), 8, 'candidate never registered')
(ws.directory / 'ready.json').write_text(json.dumps(registered))
time.sleep(60)

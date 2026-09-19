"""Live fault child; parent owns and kills this exact local process group."""
import json
from pathlib import Path
import sys
import time
import uuid
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from workspace import Workspace
from adapter import py
ws = Workspace(uuid.uuid4().hex, sys.argv[1])
ws.create({'answer':b'owner death\n'})
run = ws.start_command('echo READY; sleep 100 & wait', seconds=10)
end = time.monotonic()+8
while time.monotonic() < end:
    raw = py("import pathlib,sys; p=pathlib.Path(sys.argv[1], 'registration.json'); print(p.read_text() if p.exists() else '{}')", run.root)
    if json.loads(raw):
        (ws.directory / 'ready.json').write_bytes(raw)
        time.sleep(60)
        break
    time.sleep(.1)
else:
    raise RuntimeError('candidate never registered')

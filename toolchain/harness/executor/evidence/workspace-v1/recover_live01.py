"""Recover only the retained live-01 registration rejected before manifest write."""
import json
from pathlib import Path
import sys
import uuid
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from adapter import py
from workspace import Workspace
from test_workspace_live import resume_workspace_run

root = Path(__file__).parent / 'live-01/controls/repair'
request = next(json.loads(p.read_text()) for p in root.glob('call-*/request.json') if json.loads(p.read_text())['operation'] == 'create')
w = Workspace.__new__(Workspace)
w.directory = Path(sys.argv[1]); w.directory.mkdir()
w.run_id = request['run_id']; w.workspace_id = request['workspace_id']; w._calls = set(); w.snapshot = None
state = json.loads(py('import pathlib,json,sys; print(pathlib.Path(sys.argv[1],"state.json").read_text())', '/var/lib/mo-harness/mo-workspace-' + w.workspace_id))
execution_id = state['active']['execution_id']
manifest_file = next(p for p in root.glob('execution-*/manifest.json') if json.loads(p.read_text())['run_id'] == execution_id)
w.active = resume_workspace_run(manifest_file.parent)
# Preserve failed attempt files: new recovery evidence with the same identity.
w.active.directory = w.directory / 'execution'; w.active.directory.mkdir()
w.active.persist()
source = Path(__file__).resolve().parents[2] / 'remote.py'
print(py('import json,pathlib,sys; p=json.load(sys.stdin); root=pathlib.Path(sys.argv[1]); assert root.name==p["manifest"]["name"]; (root/"manifest.json").write_text(json.dumps(p["manifest"])); (root/"remote.py").write_text(p["source"])', w.active.root, data=json.dumps({'manifest': w.active.manifest, 'source': source.read_text()}).encode()))
result = w.collect()
print(json.dumps({'execution': result['execution'], 'cleanup': result['observation']['cleanup']}))
print(json.dumps(w.delete()))
print(py('import pathlib,sys; print(pathlib.Path(sys.argv[1]).exists())', '/var/lib/mo-harness/mo-workspace-' + w.workspace_id))

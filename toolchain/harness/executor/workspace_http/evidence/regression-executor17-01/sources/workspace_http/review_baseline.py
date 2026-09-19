"""Run new review controls against immutable checkpoint bridge bytes."""
import hashlib
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from workspace_http import bridge, local
source = Path(__file__).parent / 'evidence/local-03/sources/workspace_http/bridge.py'
raw = source.read_bytes()
print('immutable bridge sha256=' + hashlib.sha256(raw).hexdigest(), flush=True)
exec(compile(raw, str(source), 'exec'), bridge.__dict__)
local.Bridge = bridge.Bridge
local.main()

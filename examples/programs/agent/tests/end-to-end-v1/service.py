"""The real workspace service for one candidate: the accepted Bridge frontend and production
owner over the application policy, as workspace_http/live.py --application selects it.

The only addition is a test-side subclass that notes, for each admitted dispatch, when it arrived,
how many steps the agent's Book held on disk at that moment, what status and body it produced and
how long it took. Nothing in the frontend's behaviour changes."""
import json
from pathlib import Path
import threading
import time

import e2e  # noqa: F401  (puts the executor on sys.path)
from cases import APPLICATION_IMAGE, APPLICATION_TOOLCHAIN
from workspace_http import Bridge
from workspace_http import protocol

SELECTION = {'policy': 'application-build-v1', 'image': APPLICATION_IMAGE, 'toolchain': APPLICATION_TOOLCHAIN}


class ObservedBridge(Bridge):
    observe = staticmethod(lambda: None)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.dispatches = []
        self.arrivals = threading.Event()

    def _dispatch(self, conn, req):
        row = dict(call_id=req['call_id'], operation=req['operation'], arrived=time.monotonic(),
                   observed=self.observe(), args_keys=sorted(req['args']),
                   timeout_ms=req['args'].get('timeout_ms'))
        self.dispatches.append(row)
        self.arrivals.set()
        status, response = super()._dispatch(conn, req)
        row.update(status=status, produced=response, returned=time.monotonic())
        row['service_ms'] = round((row['returned'] - row['arrived']) * 1000)
        return status, response


def start(directory, source, verifier, observe, run_id='r_1'):
    bridge = ObservedBridge(run_id, directory, source, selection=dict(SELECTION), verifier=verifier)
    bridge.observe = observe
    started = time.monotonic()
    bridge.start()
    bridge.startup_ms = round((time.monotonic() - started) * 1000)
    return bridge


def write_config(bridge, path):
    """The private bridge configuration: 0600 in a 0700 directory, outside Book and candidate."""
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=False)
    path.parent.chmod(0o700)
    path.write_text(json.dumps(dict(version=protocol.VERSION, port=bridge.port, run_id=bridge.run_id,
                                    workspace_id=bridge.workspace_id, token=bridge.token)))
    path.chmod(0o600)
    return path


def journal(bridge):
    try:
        return json.loads((bridge.directory / 'owner.json').read_bytes())
    except (OSError, ValueError):
        return None


def core(bridge, core_id):
    path = bridge.directory / f'core-{core_id}.json'
    return json.loads(path.read_bytes()) if path.exists() else None

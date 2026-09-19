"""Positive-token cancellation report control; one synthetic real HTTP request."""
import http.server, json, tempfile, threading, sys, time
from pathlib import Path
from run import ROOT, HERE, MO, invoke
mode = sys.argv[1]
requests=[]
class Handler(http.server.BaseHTTPRequestHandler):
    def setup(self):
        super().setup(); self.connection.settimeout(3)
    def log_message(self,*_): pass
    def do_POST(self):
        requests.append(json.loads(self.rfile.read(int(self.headers['Content-Length']))))
        time.sleep(0.4)
        data=json.dumps({'done':'cancelled in flight','tokens':17}).encode()
        self.send_response(200); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
thread=threading.Thread(target=server.serve_forever);thread.start()
try:
    with tempfile.TemporaryDirectory(prefix='mo-cancel-report-') as tmp:
        (Path(tmp)/'work').mkdir()
        prefix=[MO,'run',str(HERE/'boundaries.mo'),'--'] if mode=='interpreter' else [str(ROOT/'zig-out/mo-build/coding-fixture-cancel/coding-fixture-cancel')]
        evidence=invoke(prefix+[tmp,str(server.server_port)])
        evidence['stored_logs']={p.name:p.read_text() for p in (Path(tmp)/'runs').glob('*.log')}
finally:
    server.shutdown();server.server_close();thread.join()
try:
    events=[json.loads(l) for l in evidence['stdout'].splitlines()]
    terminal=events[-1]['payload']
    assert evidence['exit_code']==0 and len(requests)==1
    assert len(events)==2 and events[0]['event']=='model' and events[0]['payload']['tokens']==17
    assert terminal['state']=='cancelled' and terminal['usage']=='unknown' and terminal['tokens'] is None
    evidence['passed']=True
except Exception as error:
    evidence.update(passed=False,assertion=repr(error))
evidence.update(mode=mode,requests=requests,declared_tokens=17,listener_closed=server.fileno()==-1)
print(json.dumps(evidence),flush=True)
raise SystemExit(0 if evidence['passed'] else 1)

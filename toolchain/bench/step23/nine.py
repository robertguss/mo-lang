import subprocess, sys, time, re, json, urllib.request, os, signal, shutil
SP = sys.argv[1]; R = sys.argv[2]; label = sys.argv[3]; cmd_prefix = json.loads(sys.argv[4]); env_extra = json.loads(sys.argv[5])
data = f'{SP}/load/data-{label}'
shutil.rmtree(data, ignore_errors=True); shutil.copytree(f'{R}/examples/programs/jobq/data/demo', data)
port = 7931 if label == 'run' else 7932
env = dict(os.environ); env.update(env_extra)
p = subprocess.Popen(cmd_prefix + ['serve', data, '--port', str(port)], stderr=subprocess.PIPE, stdout=subprocess.PIPE, env=env, text=True)
sport = None
while sport is None:
    line = p.stderr.readline()
    if not line: break
    m = re.search(r'http://127.0.0.1:(\d+)', line)
    if m: sport = int(m.group(1))
print(label, 'surface', sport, flush=True)
time.sleep(1.5)
def get(path, method='GET', body=None, limit=600):
    t0 = time.time()
    req = urllib.request.Request(f'http://127.0.0.1:{sport}{path}', data=body.encode() if body is not None else None, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as r: status, text = r.status, r.read().decode()
    except urllib.error.HTTPError as e: status, text = e.code, e.read().decode()
    ms = (time.time() - t0) * 1000
    return status, text, ms
def show(tag, path, limit=700):
    status, text, ms = get(path)
    print(f'{label} {tag} GET {path} -> {status} in {ms:.1f} ms: {text[:limit].strip()}', flush=True)
    return text
procs = json.loads(get('/processes')[1])
service = [x['id'] for x in procs if x['name'] == 'Service'][0]
acceptor = [x['id'] for x in procs if x['name'] == 'Acceptor'][0]
print(label, 'service', service, 'acceptor', acceptor)
# Load: 60,000 jobs made, then 32 workers lease and ack for 10 s, with 600 silent connections held;
# the samples are taken while the workers run.
load = subprocess.Popen([f'{SP}/load/jqload', str(port), '32', '10', '60000', '600'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
while True:
    line = load.stderr.readline()
    if not line or 'holding' in line: break
time.sleep(3)
for i in range(3):
    text = get('/processes')[1]
    ps = json.loads(text)
    workers = [x for x in ps if x['name'] == 'Worker']
    in_ask = [x for x in workers if x['waiting_in'] == 'ask']
    svc = [x for x in ps if x['id'] == service][0]
    acc = [x for x in ps if x['id'] == acceptor][0]
    print(f'{label} Q2 sample {i}: workers alive {len(workers)}, waiting in ask {len(in_ask)}, service mailbox {svc["mailbox"]}/{svc["bound"]} waiting_in {svc["waiting_in"]}, acceptor mailbox {acc["mailbox"]}/{acc["bound"]}', flush=True)
    show('Q5', '/sources')
    time.sleep(0.5)
out, err = load.communicate(timeout=120)
print(label, 'load:', err.strip().replace('\n', ' | '), '|', out.strip(), flush=True)
show('Q1', f'/state/{service}', 900)
show('Q3', f'/recent/{service}?n=3', 1200)
show('Q4', f'/recent/{service}?n=10', 2500)
show('Q6', '/crashes?n=5')
print(label, 'Q6 restarts', [ (x['name'], x['restarts']) for x in json.loads(get('/processes')[1]) if x['name'] in ('Service','Acceptor')])
show('Q7', '/memory', 900)
# Q8 and Q9: 10,000 jobs leased for 100 ms and never acked; the listener's Idle after 5 s sweeps them.
subprocess.run([f'{SP}/load/jqload', str(port), '32', '4', '10000', '0', 'leaseonly'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
show('Q8', f'/state/{service}', 400)
time.sleep(7)
show('Q9', '/slowest?n=3', 1500)
st, text, ms = get('/events?n=100000')
evs = json.loads(text)
kinds = {}
for e in evs:
    k = list(e.keys())[0]; kinds[k] = kinds.get(k, 0) + 1
print(label, 'ring holds', len(evs), 'events by kind', kinds, f'(GET in {ms:.1f} ms)', flush=True)
p.send_signal(signal.SIGTERM)
try: p.wait(timeout=10)
except subprocess.TimeoutExpired: p.kill()

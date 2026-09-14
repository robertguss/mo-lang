# The ring's resident memory: kv takes 100,000 GETs over one socket with the ring at 0, 4,096, and
# 65,536 events; the program's resident memory after, and what /memory says the ring holds.
import sys, os, socket, time, json, shutil
sys.path.insert(0, os.path.dirname(__file__))
from common import *
SP, R = sys.argv[1], sys.argv[2]
GETS = 100_000
def run(label, cmd, env, port):
    data = f'{SP}/d/kv-ring-{label.replace(" ", "-")}'
    shutil.rmtree(data, ignore_errors=True); os.makedirs(data)
    open(f'{data}/kv.log', 'w').write('SET greeting hello wide world\n')
    p, sport = start(cmd + ['serve', data, '--port', str(port)], env)
    wait_port(port)
    s = socket.create_connection(('127.0.0.1', port)); f = s.makefile('rb')
    t0 = time.perf_counter()
    for _ in range(GETS):
        s.sendall(b'GET greeting\n'); f.readline()
    took = time.perf_counter() - t0
    body, _ = get(sport, '/memory')
    m = json.loads(body)
    events = json.loads(get(sport, '/events?n=1000000')[0])
    print(f'{label}: rss {rss_kib(p.pid)} KiB, resident_bytes {m["resident_bytes"]//1024} KiB, event_bytes {m["event_bytes"]//1024} KiB, ring holds {len(events)}, {GETS} GETs in {took:.2f} s', flush=True)
    s.close(); stop(p)
mo = f'{R}/toolchain/zig-out/bin/mo'
kv = f'{R}/examples/programs/kv/main.mo'
for cap in (0, 4096, 65536):
    run(f'mo run --events {cap}', [mo, 'run', '--surface', '0', '--events', str(cap), kv, '--'], {}, 7961)
for cap in (0, 4096, 65536):
    run(f'binary MO_EVENTS={cap}', [sys.argv[3]], {'MO_SURFACE': '0', 'MO_EVENTS': str(cap)}, 7962)

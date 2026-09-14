# GET /processes with 10,000 live processes: hold/main.mo reads each connection into a process of its own; 10,000 idle
# connections are held open, then the surface's /processes is timed, best of five.
import sys, os, socket, time, json, shutil
sys.path.insert(0, os.path.dirname(__file__))
from common import *
SP, R = sys.argv[1], sys.argv[2]
N = 10_000
def run(label, cmd, env, port):
    data = f'{SP}/d/kv-many-{label}'
    shutil.rmtree(data, ignore_errors=True); os.makedirs(data); open(f'{data}/kv.log', 'w').close()
    p, sport = start(cmd + [str(port)], env)
    wait_port(port)
    socks = []
    for i in range(N):
        s = socket.create_connection(('127.0.0.1', port)); socks.append(s)
    live = 0
    for _ in range(120):
        body, _ = get(sport, '/processes')
        live = len(json.loads(body))
        if live >= N: break
        time.sleep(0.5)
    times = []
    size = 0
    for _ in range(5):
        body, ms = get(sport, '/processes'); times.append(ms); size = len(body)
    print(f'{label}: {live} live processes, GET /processes best {min(times):.1f} ms, median {sorted(times)[2]:.1f} ms, {size} bytes, rss {rss_kib(p.pid)} KiB', flush=True)
    for s in socks: s.close()
    stop(p)
mo = f'{R}/toolchain/zig-out/bin/mo'
run('mo run', [mo, 'run', '--surface', '0', f'{SP}/hold/main.mo', '--'], {}, 7951)
run('binary', [sys.argv[3]], {'MO_SURFACE': '0'}, 7952)

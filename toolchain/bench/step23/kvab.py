# kv-10k-get-c, interleaved: 10,000 GETs over one socket to kv binaries, best of N rounds each.
# usage: kvab.py SP ROUNDS label=binary[,ENV=VAL] ...
import sys, os, socket, time, shutil, subprocess
sys.path.insert(0, os.path.dirname(__file__))
from common import *
SP, rounds = sys.argv[1], int(sys.argv[2])
cases = []
for arg in sys.argv[3:]:
    label, rest = arg.split('=', 1)
    parts = rest.split(',')
    env = dict(p.split('=', 1) for p in parts[1:])
    cases.append((label, parts[0], env))
best = {}
for r in range(rounds):
    for label, binary, env in cases:
        data = f'{SP}/d/kvab-{label}'
        shutil.rmtree(data, ignore_errors=True); os.makedirs(data)
        open(f'{data}/kv.log', 'w').write('SET greeting hello wide world\n')
        port = 7981
        e = dict(os.environ); e.update(env)
        p = subprocess.Popen([binary, 'serve', data, '--port', str(port)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=e)
        wait_port(port)
        s = socket.create_connection(('127.0.0.1', port)); f = s.makefile('rb')
        for _ in range(500): s.sendall(b'GET greeting\n'); f.readline()
        t0 = time.perf_counter()
        for _ in range(10_000): s.sendall(b'GET greeting\n'); f.readline()
        ms = (time.perf_counter() - t0) * 1000
        s.close(); stop(p)
        best[label] = min(best.get(label, 1e9), ms)
        print(f'round {r} {label}: {ms:.1f} ms', flush=True)
print('best', {k: round(v, 1) for k, v in best.items()})

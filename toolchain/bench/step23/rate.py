# jobq's lease-and-ack pairs a second with 32 workers, native, before and after, interleaved, best
# of three: a fresh copy of data/demo each run, 50,000 jobs made first, then 8 seconds of load.
import sys, os, subprocess, shutil
sys.path.insert(0, os.path.dirname(__file__))
from common import *
SP, R = sys.argv[1], sys.argv[2]
binaries = {'before': sys.argv[3], 'after': sys.argv[4]}
best = {}
for round_ in range(3):
    for label, binary in binaries.items():
        data = f'{SP}/d/jobq-{label}'
        shutil.rmtree(data, ignore_errors=True); shutil.copytree(f'{R}/examples/programs/jobq/data/demo', data)
        port = 7971
        p = subprocess.Popen([binary, 'serve', data, '--port', str(port)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wait_port(port)
        out = subprocess.run([f'{SP}/load/jqload', str(port), '32', '8', '50000'], capture_output=True, text=True, timeout=300)
        rate = float(out.stdout.split('pairs_per_s ')[1].split()[0])
        print(f'round {round_} {label}: {out.stdout.strip()}', flush=True)
        best[label] = max(best.get(label, 0), rate)
        stop(p)
print('best', best, 'after/before', best['after'] / best['before'])

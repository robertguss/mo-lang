"""Read-only release inventory; run only after explicit lead release."""
import json
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=False)
commands = {
    'dedicated': ['orbctl', 'run', '-m', 'mo-executor-r01', '-u', 'root', 'sh', '-c',
        'ls -la /opt/mo-harness; docker ps -a --no-trunc; docker image ls --no-trunc; '
        'systemctl show mo-application.slice mo-executor.slice -p ControlGroup -p MemoryMax -p MemorySwapMax -p CPUQuotaPerSecUSec -p TasksMax; '
        'cat /sys/fs/cgroup/mo.slice/mo-application.slice/memory.peak'],
    'shared-mac': ['docker', 'ps', '-a', '--no-trunc', '--format', '{{.ID}} {{.State}}'],
}
for name, command in commands.items():
    p = subprocess.run(command, capture_output=True, timeout=15)
    (root / (name + '.json')).write_text(json.dumps({'argv': command, 'exit': p.returncode,
        'stdout': p.stdout.decode(), 'stderr': p.stderr.decode()}, indent=2))
    print(name, p.returncode, p.stdout.decode(), p.stderr.decode(), flush=True)

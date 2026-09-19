"""Explicit released-machine offline build, with independent service deadline."""
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
PREFIX = ['orbctl', 'run', '-m', 'mo-executor-r01', '-u', 'root']
STAGE = '/opt/mo-harness/application-build-v1'


def main(attempt, archive):
    attempt = Path(attempt)
    attempt.mkdir(parents=True, exist_ok=False)
    unit = 'mo-appv1-package-' + attempt.name
    stage = STAGE + '/' + attempt.name
    payload = {name: (HERE / name).read_text() for name in ('package.py', 'Dockerfile', 'validate_image.py')}
    upload = '''import json,pathlib,sys
p=pathlib.Path(sys.argv[1]); p.mkdir(parents=True,exist_ok=False)
for name,text in json.load(sys.stdin).items(): (p/name).write_text(text)
'''
    p = subprocess.run(PREFIX + ['python3', '-c', upload, stage], input=json.dumps(payload).encode(), capture_output=True, timeout=10)
    (attempt / 'upload.json').write_text(json.dumps({'exit': p.returncode, 'stderr': p.stderr.decode()}))
    p.check_returncode()
    pushed = subprocess.run(['orbctl', 'push', '-m', 'mo-executor-r01', archive, stage + '/zig.tar.xz'],
                            capture_output=True, timeout=60)
    (attempt / 'push.json').write_text(json.dumps({'exit': pushed.returncode,
        'stdout': pushed.stdout.decode(), 'stderr': pushed.stderr.decode()}))
    pushed.check_returncode()
    archive = stage + '/zig.tar.xz'
    script = '''set -eu
python3 -B "$1/package.py" --mo /opt/mo-harness/bin/mo-e3a01bb-aarch64-linux-musl --zig /opt/mo-harness/zig-aarch64-linux-0.16.0 --archive "$2" --output "$1/package"
DOCKER_BUILDKIT=0 docker build --network=none --pull=false --memory=1536m --memory-swap=1536m --cpu-period=100000 --cpu-quota=100000 --cgroup-parent=mo-application.slice --iidfile "$1/image.id" "$1/package/context"
docker image inspect "$(cat "$1/image.id")" > "$1/image-inspect.json"
python3 -B "$1/validate_image.py" "$(cat "$1/image.id")" "$1/package/manifest.json" "$3" > "$1/image-content.json"
'''
    command = PREFIX + ['systemd-run', '--quiet', '--wait', '--pipe', '--unit=' + unit,
        '--property=RuntimeMaxSec=600', '--property=MemoryMax=1536M', '--property=MemorySwapMax=0',
        '--property=CPUQuota=100%', '--property=TasksMax=192', '--property=KillMode=control-group',
        '--property=ExecStopPost=-/usr/bin/docker rm -f ' + unit + '-content',
        '--property=TimeoutStopSec=5', '--slice=mo-application.slice',
        '/bin/sh', '-c', script, 'application-package', stage, archive, unit + '-content']
    (attempt / 'command.json').write_text(json.dumps(command))
    try:
        p = subprocess.run(command, capture_output=True, timeout=615)
        (attempt / 'output.txt').write_bytes(p.stdout + p.stderr)
        (attempt / 'exit.txt').write_text(str(p.returncode))
        print((p.stdout + p.stderr).decode(errors='replace'), flush=True)
    finally:
        state = subprocess.run(PREFIX + ['systemctl', 'show', unit, '-p', 'Result', '-p', 'ExecMainStatus',
            '-p', 'MemoryPeak', '-p', 'ControlGroup', '-p', 'ActiveState'], capture_output=True, timeout=10)
        (attempt / 'service.txt').write_bytes(state.stdout + state.stderr)
        stopped = subprocess.run(PREFIX + ['systemctl', 'stop', unit], capture_output=True, timeout=10)
        subprocess.run(PREFIX + ['systemctl', 'reset-failed', unit], capture_output=True, timeout=10)
        (attempt / 'stop.json').write_text(json.dumps({'exit': stopped.returncode, 'stderr': stopped.stderr.decode()}))
    for name in ('image.id', 'image-inspect.json', 'image-content.json', 'package/manifest.json', 'package/toolchain.sha256'):
        r = subprocess.run(PREFIX + ['cat', stage + '/' + name], capture_output=True, timeout=10)
        (attempt / name.replace('/', '-')).write_bytes(r.stdout if r.returncode == 0 else r.stderr)
    p.check_returncode()


if __name__ == '__main__':
    main(*sys.argv[1:])

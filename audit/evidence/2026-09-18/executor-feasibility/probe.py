import json
import pathlib
import subprocess
import time

ROOT = pathlib.Path('/tmp/mo-executor-feasibility')
D = ['sudo', '-n', 'docker', '--host', f'unix://{ROOT}/docker.sock']
BASE = ['--pull=never', '--network=none', '--read-only', '--user=65534:65534',
        '--cap-drop=ALL', '--security-opt=no-new-privileges', '--cpus=.25',
        '--memory=32m', '--memory-swap=32m', '--pids-limit=16',
        '--log-driver=none', '--ulimit=nofile=64:64', '--shm-size=1m',
        '--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=8m,mode=1777',
        '--tmpfs=/work:rw,nosuid,nodev,size=128m,mode=1777',
        '--mount', f'type=bind,src={ROOT}/reference,dst=/reference/data,readonly']
names = []

def docker(*args, timeout=15):
    return subprocess.run(D + list(args), text=True, capture_output=True, timeout=timeout)

def start(name, script):
    name = 'mo-probe-' + name
    names.append(name)
    p = docker('run', '-d', '--name', name, *BASE, 'mo-executor-fixture:local',
               '/bin/busybox', 'sh', '-c', script)
    assert p.returncode == 0, p.stderr
    return name

def state(name):
    p = docker('inspect', name)
    assert p.returncode == 0, p.stderr
    return json.loads(p.stdout)[0]['State']

def group(name):
    pid = state(name)['Pid']
    path = pathlib.Path(f'/proc/{pid}/cgroup').read_text().split('0::', 1)[1].strip()
    return pathlib.Path('/sys/fs/cgroup' + path)

def finish(name, expected=0):
    p = docker('wait', name)
    assert p.returncode == 0 and int(p.stdout.strip()) == expected, (name, p.stdout, p.stderr)
    return state(name)

def result(name, details):
    print(json.dumps({'check': name, 'result': 'PASS', 'details': details}), flush=True)

try:
    n = start('preflight', '/bin/busybox sleep 12')
    g = group(n)
    limits = {f: (g / f).read_text().strip() for f in ['cpu.max', 'memory.max', 'memory.swap.max', 'pids.max']}
    assert limits == {'cpu.max': '25000 100000', 'memory.max': '33554432', 'memory.swap.max': '0', 'pids.max': '16'}, limits
    result('effective-kernel-limits', limits)
    docker('kill', n)

    script = '''set -eu
b=/bin/busybox
test "$($b id -u)" = 65534
test "$($b cat /reference/data)" = DUMMY-REFERENCE
test ! -e /tmp/mo-executor-feasibility/sentinel
test ! -e /tmp/mo-executor-feasibility/docker.sock
test ! -e /home/user
if echo forged > /reference/data; then exit 31; fi
if echo forged > /root-write; then exit 32; fi
echo writable > /work/probe
test "$($b cat /work/probe)" = writable
$b grep -q 'NoNewPrivs:.*1' /proc/self/status
$b grep -q 'Seccomp:.*2' /proc/self/status
$b grep -q 'CapEff:.*0000000000000000' /proc/self/status
'''
    n = start('filesystem', script)
    finish(n)
    assert (ROOT / 'reference').read_text() == 'DUMMY-REFERENCE\n'
    assert (ROOT / 'sentinel').read_text() == 'DUMMY-SECRET\n'
    result('filesystem-and-process-restrictions', 'nonroot; read-only root/reference; writable work; dummy sentinel/socket absent; seccomp=2; no-new-privileges=1; effective capabilities=0')

    n = start('network', '''set -eu
b=/bin/busybox
test "$($b ls /sys/class/net)" = lo
test "$($b wc -l < /proc/net/route)" = 1
if $b nc -w 1 192.0.2.1 9; then exit 41; fi
''')
    finish(n)
    result('network-denial', 'loopback only; no IPv4 routes; connection to TEST-NET address fails')

    n = start('cpu', 'while :; do :; done')
    g = group(n)
    time.sleep(2)
    counters = dict(line.split() for line in (g / 'cpu.stat').read_text().splitlines())
    assert int(counters['nr_throttled']) > 0, counters
    assert 0 < int(counters['usage_usec']) < 1500000, counters
    result('cpu-throttling', counters)
    docker('kill', n)

    n = start('memory', '/bin/busybox dd if=/dev/zero of=/work/memory bs=1048576 count=64')
    s = finish(n, 137)
    assert s['OOMKilled'], s
    result('memory-enforcement', '64 MiB finite write under 32 MiB memory limit: exit 137, OOMKilled=true')

    n = start('pids', "/bin/busybox sh -c '/bin/busybox sleep .5; i=0; while [ \"$i\" -lt 24 ]; do /bin/busybox sleep 6 & i=$((i+1)); done; wait' & /bin/busybox sleep 6; wait")
    g = group(n)
    time.sleep(1)
    events = dict(line.split() for line in (g / 'pids.events').read_text().splitlines())
    count = int((g / 'pids.current').read_text())
    assert int(events['max']) > 0 and count <= 16, (events, count)
    result('pids-enforcement', {'pids.current': count, 'pids.events': events})
    docker('kill', n)

    n = start('scratch', 'if /bin/busybox dd if=/dev/zero of=/tmp/full bs=1048576 count=12; then exit 51; fi; test "$(/bin/busybox stat -c %s /tmp/full)" = 8388608')
    finish(n)
    result('scratch-bound', 'finite 12 MiB write stops at 8 MiB tmpfs capacity')

    n = start('cleanup', '/bin/busybox setsid /bin/busybox sleep 20 & /bin/busybox sleep 20 & wait')
    g = group(n)
    time.sleep(.3)
    pids = (g / 'cgroup.procs').read_text().split()
    assert len(pids) >= 3, pids
    before = time.monotonic()
    try:
        docker('wait', n, timeout=.5)
        raise AssertionError('20-second fixture finished before deadline')
    except subprocess.TimeoutExpired:
        pass
    p = docker('stop', '--time=0', n)
    assert p.returncode == 0, p.stderr
    assert time.monotonic() - before < 5
    assert not state(n)['Running']
    assert not g.exists() or not (g / 'cgroup.procs').read_text().strip()
    assert all(not pathlib.Path('/proc', pid).exists() for pid in pids), pids
    result('deadline-and-descendant-cleanup', {'processes_removed': len(pids), 'cgroup_empty_or_removed': True})

    n = start('output', '/bin/busybox sleep 1; /bin/busybox dd if=/dev/zero bs=1024 count=1024; /bin/busybox sleep 5')
    reader = subprocess.Popen(D + ['attach', '--sig-proxy=false', n], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    import selectors
    import os
    selector = selectors.DefaultSelector()
    selector.register(reader.stdout, selectors.EVENT_READ)
    captured = bytearray()
    seen = 0
    deadline = time.monotonic() + 4
    try:
        while seen <= 4096 and time.monotonic() < deadline:
            if selector.select(.1):
                chunk = os.read(reader.stdout.fileno(), 4096)
                if not chunk:
                    break
                seen += len(chunk)
                captured.extend(chunk[:max(0, 4096-len(captured))])
        assert seen > 4096 and len(captured) == 4096, (seen, len(captured))
        assert docker('stop', '--time=0', n).returncode == 0
        # A stopped producer can leave the attach client blocked on a full pipe.
        # Drain bounded-size chunks without retaining them before joining it.
        drain_deadline = time.monotonic() + 5
        eof = False
        while time.monotonic() < drain_deadline:
            if selector.select(.1):
                if not os.read(reader.stdout.fileno(), 4096):
                    eof = True
                    break
        assert eof, 'attach did not close after bounded drain'
        reader.wait(timeout=5)
        assert not state(n)['Running']
        result('output-cap-controller-probe', {'retained_bytes': len(captured), 'overflow_detected': True, 'container_stopped': True})
    finally:
        selector.close()
        reader.stdout.close()
        if reader.poll() is None:
            docker('stop', '--time=0', n)
            reader.wait(timeout=5)
finally:
    for n in names:
        p = docker('rm', '-f', n)
        if p.returncode:
            print(json.dumps({'cleanup_failure': n, 'error': p.stderr}), flush=True)

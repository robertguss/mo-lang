import subprocess, time, re, json, urllib.request, os, signal, socket
def start(cmd, env_extra=None, cwd=None):
    env = dict(os.environ); env.update(env_extra or {})
    p = subprocess.Popen(cmd, stderr=subprocess.PIPE, stdout=subprocess.DEVNULL, env=env, cwd=cwd, text=True)
    sport = None; t0 = time.time()
    while time.time() - t0 < 60:
        line = p.stderr.readline()
        if not line:
            if p.poll() is not None: break
            continue
        m = re.search(r'http://127.0.0.1:(\d+)', line)
        if m: sport = int(m.group(1)); break
    return p, sport
def get(sport, path, timeout=60):
    t0 = time.perf_counter()
    with urllib.request.urlopen(f'http://127.0.0.1:{sport}{path}', timeout=timeout) as r: body = r.read()
    return body, (time.perf_counter() - t0) * 1000
def rss_kib(pid):
    return int(subprocess.run(['ps', '-o', 'rss=', '-p', str(pid)], capture_output=True, text=True).stdout.strip() or 0)
def stop(p):
    p.send_signal(signal.SIGTERM)
    try: p.wait(timeout=10)
    except subprocess.TimeoutExpired: p.kill(); p.wait()
def wait_port(port, t=30):
    t0 = time.time()
    while time.time() - t0 < t:
        try:
            s = socket.create_connection(('127.0.0.1', port), timeout=1); s.close(); return True
        except OSError: time.sleep(0.1)
    return False

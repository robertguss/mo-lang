"""Run an owned command with a process-group deadline shorter than outer guard."""
import os, pathlib, signal, subprocess, sys, shutil, json
root = pathlib.Path(__file__).resolve().parent
cache = root / '.cache'
(cache / 'home').mkdir(parents=True, exist_ok=True)
for name in ('user.npmrc', 'global.npmrc'): (cache / name).write_text('')
resolved = {name: shutil.which(name) for name in ('node', 'npm')}
assert all(resolved.values()), 'node and npm must be on PATH'
search_path = os.pathsep.join(dict.fromkeys([str(pathlib.Path(p).parent) for p in resolved.values()] + ['/usr/bin', '/bin']))
print('resolved executables: ' + json.dumps(resolved), flush=True)
env = {'PATH': search_path, 'HOME': str(cache / 'home'), 'npm_config_cache': str(cache / 'npm'), 'npm_config_userconfig': str(cache / 'user.npmrc'), 'npm_config_globalconfig': str(cache / 'global.npmrc'), 'npm_config_registry': 'https://registry.npmjs.org', 'NO_COLOR': '1'}
for name, executable in resolved.items():
    version = subprocess.run([executable, '--version'], env=env, text=True, capture_output=True, timeout=10, check=True).stdout.strip()
    print(name + '=' + version, flush=True)
p = subprocess.Popen(sys.argv[2:], cwd=root, env=env, start_new_session=True)
def stop(*_):
    os.killpg(p.pid, signal.SIGKILL)
for sig in (signal.SIGTERM, signal.SIGINT): signal.signal(sig, stop)
try:
    rc = p.wait(timeout=float(sys.argv[1]))
except subprocess.TimeoutExpired:
    stop(); p.wait(); rc = 124
finally:
    try: os.killpg(p.pid, signal.SIGKILL)
    except ProcessLookupError: pass
print('owned-command-exit=' + str(rc), flush=True)
sys.exit(rc)

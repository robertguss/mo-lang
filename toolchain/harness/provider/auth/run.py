"""Bounded command, sterile environment, owned process group, immutable evidence."""
import json, os, pathlib, shutil, signal, subprocess, sys
root = pathlib.Path(__file__).resolve().parent
attempt = root/'evidence'/sys.argv[1]
attempt.mkdir(parents=True, exist_ok=False)
node = shutil.which('node')
home = root/'.cache'/('home-'+sys.argv[1])
home.mkdir(parents=True, exist_ok=False)
env = {'HOME': str(home), 'PATH': os.pathsep.join([str(pathlib.Path(node).parent), '/usr/bin', '/bin']), 'NO_COLOR': '1'}
command = sys.argv[2:]
(attempt/'command.json').write_text(json.dumps({'command':command, 'cwd':str(root), 'node':node, 'deadline_seconds':550, 'environment_keys':sorted(env)}, indent=2)+'\n')
with (attempt/'output.log').open('xb') as log:
    p = subprocess.Popen(command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    def stop(*_):
        try: os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError: pass
    for sig in (signal.SIGINT, signal.SIGTERM): signal.signal(sig, stop)
    try: rc = p.wait(timeout=550)
    except subprocess.TimeoutExpired: stop(); p.wait(); rc = 124
    finally: stop()
(attempt/'exit').write_text(str(rc)+'\n')
try: os.killpg(p.pid, 0); gone = False
except ProcessLookupError: gone = True
(attempt/'cleanup.json').write_text(json.dumps({'process_group':p.pid, 'absent':gone})+'\n')
assert sum(p.stat().st_size for p in (root/'evidence').rglob('*') if p.is_file()) <= 16*1024*1024
print('attempt',sys.argv[1],'exit',rc,'process_group_absent',gone,flush=True)
sys.exit(rc if gone else 1)

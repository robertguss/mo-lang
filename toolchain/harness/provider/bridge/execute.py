"""Empty-home Node command with owned group cleanup and a finite deadline."""
import json, os, pathlib, shutil, signal, subprocess, sys
copy = pathlib.Path(__file__).resolve().parent.parent
node = shutil.which('node')
assert node
home = copy / 'bridge/.home'
home.mkdir(exist_ok=True)
env = {'PATH':os.pathsep.join([str(pathlib.Path(node).parent), '/opt/homebrew/bin', '/usr/bin', '/bin']), 'HOME':str(home), 'NO_COLOR':'1'}
print('node='+node, flush=True)
print(subprocess.check_output([node,'--version'],env=env,text=True,timeout=10).strip(),flush=True)
guard = copy / 'bridge/mo-project/guard.py'
print('zig='+subprocess.check_output(['/opt/homebrew/bin/zig','version'],env=env,text=True,timeout=10).strip(),flush=True)
p = subprocess.Popen(['python3',str(guard),'540','--',node]+sys.argv[1:],cwd=copy,env=env,start_new_session=True)
def stop(*_):
    try: os.killpg(p.pid, signal.SIGKILL)
    except ProcessLookupError: pass
for sig in (signal.SIGINT,signal.SIGTERM): signal.signal(sig,stop)
try: rc=p.wait(timeout=550)
except subprocess.TimeoutExpired: stop();p.wait();rc=124
finally: stop()
print('owned-node-group-cleaned; exit='+str(rc),flush=True)
sys.exit(rc)

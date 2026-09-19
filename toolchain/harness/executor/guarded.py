"""guarded.py SECONDS ATTEMPT [--cwd DIR] [--home DIR] -- COMMAND...

Runs COMMAND under toolchain/bench/step36/guard.py in its own process group and
records, in the new directory ATTEMPT: command.json (argv, cwd, git head and
dirty paths), output.log, and exit.json with the child's real return code.
--home gives the child an empty HOME and a minimal PATH (node, npm, zig, /usr/bin,
/bin) with npm configuration kept inside that home. Exits with the child's code
(guard.py reports its own kill as 137), 124 if the guard outlives SECONDS+5 or
output passes 16 MiB, or 125 if the process group survives a SIGKILL.
"""
import argparse, json, os, shutil, signal, subprocess, sys, time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
BUDGET = 16 * 1024 * 1024
parser = argparse.ArgumentParser(usage=__doc__.splitlines()[0])
parser.add_argument('seconds', type=int)
parser.add_argument('attempt', type=Path)
parser.add_argument('--cwd', type=Path, default=Path.cwd())
parser.add_argument('--home', type=Path)
parser.add_argument('command', nargs='+')
args = parser.parse_args()
if not 1 <= args.seconds <= 1800: parser.error('SECONDS must be 1..1800')
args.attempt.mkdir(parents=True, exist_ok=False)
git = lambda *a: subprocess.run(['git', '-C', str(REPO), *a], capture_output=True, text=True).stdout
record = {'argv': args.command, 'cwd': str(args.cwd.resolve()), 'seconds': args.seconds,
          'head': git('rev-parse', 'HEAD').strip(), 'dirty': git('status', '--porcelain').splitlines()[:200]}
env = None
if args.home:
    home = args.home.resolve(); home.mkdir(parents=True, exist_ok=True)
    for name in ('user.npmrc', 'global.npmrc'): (home / name).touch()
    tools = {name: shutil.which(name) for name in ('node', 'npm', 'zig')}
    path = list(dict.fromkeys([str(Path(t).parent) for t in tools.values() if t] + ['/usr/bin', '/bin']))
    env = {'PATH': os.pathsep.join(path), 'HOME': str(home), 'NO_COLOR': '1',
           'npm_config_cache': str(home / 'npm'), 'npm_config_userconfig': str(home / 'user.npmrc'),
           'npm_config_globalconfig': str(home / 'global.npmrc'), 'npm_config_registry': 'https://registry.npmjs.org'}
    record.update(tools=tools, environment=env)
(args.attempt / 'command.json').write_text(json.dumps(record, indent=2) + '\n')
start = time.monotonic()
with (args.attempt / 'output.log').open('xb') as log:
    p = subprocess.Popen([sys.executable, str(REPO / 'toolchain/bench/step36/guard.py'), str(args.seconds), '--', *args.command],
                         cwd=args.cwd, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    def stop(*_):
        try: os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError: pass
    for sig in (signal.SIGINT, signal.SIGTERM): signal.signal(sig, stop)
    timed_out = False
    while p.poll() is None:
        if time.monotonic() - start > args.seconds + 5 or log.tell() > BUDGET:
            timed_out = True; stop(); break
        time.sleep(.1)
    child_exit = p.wait()
stop()
end, remaining = time.monotonic() + 3, True
while remaining and time.monotonic() < end:
    rows = subprocess.run(['ps', '-axo', 'pgid=,pid=,command='], capture_output=True, text=True).stdout.splitlines()
    remaining = [row for row in rows if row.split(None, 1)[0] == str(p.pid)]
    if remaining: time.sleep(.1)
size = (args.attempt / 'output.log').stat().st_size
code = 124 if timed_out else 125 if remaining else child_exit
result = {'child_exit': child_exit, 'exit': code, 'timed_out': timed_out, 'process_group': p.pid,
          'group_absent': not remaining, 'remaining': remaining, 'output_bytes': size,
          'elapsed_seconds': round(time.monotonic() - start, 3)}
(args.attempt / 'exit.json').write_text(json.dumps(result, indent=2) + '\n')
print(f'guarded {args.attempt} child_exit={child_exit} exit={code} group_absent={not remaining}', flush=True)
sys.exit(code)

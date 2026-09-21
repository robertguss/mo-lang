"""guarded.py SECONDS ATTEMPT [--cwd DIR] [--home DIR] -- COMMAND...

Runs COMMAND through toolchain/bench/step36/guard.py's in-process supervisor and
records, in the new directory ATTEMPT: command.json (argv, cwd, git head and
dirty paths), output.log, and exit.json with the child's real return code.
--home gives the child an empty HOME and a minimal PATH (node, npm, zig, /usr/bin,
/bin) with npm configuration kept inside that home. Exits with the child's code
(guard.py reports its own kill as 137), 124 if supervision exceeds SECONDS+5 or
the final retained output passes 16 MiB, or 125 if supervision or cleanup is
unknown/failed. Cleanup failure wins over 124 without replacing its policy reason.
"""
import argparse, importlib.util, json, os, shutil, subprocess, sys, time
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
spec = importlib.util.spec_from_file_location('mo_process_guard', REPO / 'toolchain/bench/step36/guard.py')
guard = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = guard
spec.loader.exec_module(guard)
with (args.attempt / 'output.log').open('xb') as log:
    def policy(_payload, _now):
        return 'output_overflow' if _payload.poll() is None and log.tell() > BUDGET else None
    outcome = guard.supervise(
        args.seconds,
        args.command,
        cwd=args.cwd,
        env=env,
        stdout=log,
        stderr=subprocess.STDOUT,
        policy=policy,
        forwarded_signal_grace=2.0,
        outer_deadline=start + args.seconds + 5,
    )
size = (args.attempt / 'output.log').stat().st_size
reason = outcome.reason
supervision_reason = outcome.reason
reason_source = 'supervision'
if size > BUDGET and reason != 'output_overflow':
    reason = 'output_overflow'
    reason_source = 'after_cleanup'
policy_timeout = reason in ('output_overflow', 'outer_deadline')
if not outcome.cleanup_confirmed or outcome.supervision_error or outcome.reason == 'rss_probe_failed':
    code = 125
elif policy_timeout:
    code = 124
elif outcome.child_exit is None:
    code = 125
else:
    code = outcome.child_exit
result = {'child_exit': outcome.child_exit, 'child_returncode': outcome.child_returncode,
          'exit': code, 'reason': reason, 'reason_source': reason_source,
          'supervision_reason': supervision_reason,
          'timed_out': policy_timeout,
          'process_group': outcome.process_group,
          'cleanup_confirmed': outcome.cleanup_confirmed,
          'group_state': outcome.group.state, 'group_absent': outcome.group.state == 'absent',
          'remaining': outcome.group.rows, 'cleanup_error': outcome.group.error,
          'supervision_error': outcome.supervision_error, 'output_bytes': size,
          'elapsed_seconds': round(time.monotonic() - start, 3)}
(args.attempt / 'exit.json').write_text(json.dumps(result, indent=2) + '\n')
print(f"guarded {args.attempt} child_exit={outcome.child_exit} exit={code} "
      f"group_state={outcome.group.state} reason={reason}", flush=True)
sys.exit(code)

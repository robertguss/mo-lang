#!/usr/bin/env python3
"""Bounded audit command recorder; invoke with label timeout cwd argv..."""
import json, os, pathlib, shutil, subprocess, sys, time
HERE = pathlib.Path(__file__).resolve().parent
label, seconds, cwd, *command = sys.argv[1:]
env = os.environ.copy()
zig = env.get('AUDIT_ZIG') or shutil.which('zig')
if not zig:
    raise SystemExit('Put Zig 0.16.0 on PATH or set AUDIT_ZIG to its executable')
env['PATH'] = str(pathlib.Path(zig).parent) + os.pathsep + env['PATH']
env['ZIG_GLOBAL_CACHE_DIR'] = str(HERE / 'cache-global')
env['ZIG_LOCAL_CACHE_DIR'] = str(HERE / 'cache-local')
start = time.monotonic()
with (HERE / (label + '.log')).open('wb') as log:
    result = subprocess.run(['timeout', '-k', '5', seconds, *command], cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
record = dict(command=command, cwd=cwd, timeout_seconds=seconds, returncode=result.returncode, elapsed_seconds=time.monotonic()-start)
(HERE / (label + '.json')).write_text(json.dumps(record, indent=2)+'\n')
print(json.dumps(record))
print((HERE / (label + '.log')).read_text(errors='replace')[-12000:])

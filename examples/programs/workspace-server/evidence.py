"""evidence.py NAME SECONDS -- cmd...: runs cmd under the step-36 guard from the repository
root, tees its output into evidence/NAME/output.log and leaves its real exit in
evidence/NAME/exit, beside the command in evidence/NAME/command.json. NAME must be new."""
import json
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def main():
    name, seconds = sys.argv[1], sys.argv[2]
    command = sys.argv[sys.argv.index('--') + 1:]
    folder = HERE / 'evidence' / name
    folder.mkdir(parents=True)
    argv = ['python3', 'toolchain/bench/step36/guard.py', seconds, '--', *command]
    (folder / 'command.json').write_text(json.dumps({'argv': argv, 'cwd': 'repository root'}, indent=1) + '\n')
    started = time.monotonic()
    with (folder / 'output.log').open('wb') as log:
        child = subprocess.Popen(argv, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        for line in child.stdout:
            sys.stdout.buffer.write(line)
            sys.stdout.buffer.flush()
            log.write(line)
        code = child.wait()
    (folder / 'exit').write_text(f'{code}\n')
    print(f'evidence {name}: exit {code} in {time.monotonic() - started:.1f} s', flush=True)
    raise SystemExit(code)


if __name__ == '__main__':
    main()

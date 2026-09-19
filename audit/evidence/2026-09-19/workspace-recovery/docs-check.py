import json, os, signal, subprocess, time
from pathlib import Path
root=Path(__file__).resolve().parents[4]
out=Path(__file__).parent/'docs-check-01'
out.mkdir()
rows=[]
for name,cmd in [('lint',['python3','mo-wiki/tools/lint.py']),('diff',['git','diff','--check'])]:
    argv=['python3','toolchain/bench/step36/guard.py','60','--',*cmd]
    p=subprocess.Popen(argv,cwd=root,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    try:
        stdout,stderr=p.communicate(timeout=70)
    finally:
        try: os.killpg(p.pid,signal.SIGKILL)
        except ProcessLookupError: pass
        p.wait()
    (out/(name+'.stdout.txt')).write_bytes(stdout)
    (out/(name+'.stderr.txt')).write_bytes(stderr)
    try: os.killpg(p.pid,0); remaining=True
    except ProcessLookupError: remaining=False
    row={'argv':argv,'exit':p.returncode,'group':p.pid,'group_remaining':remaining}
    rows.append(row)
    print(json.dumps(row),flush=True)
(out/'receipts.json').write_text(json.dumps(rows,indent=2))
raise SystemExit(any(r['exit'] or r['group_remaining'] for r in rows))

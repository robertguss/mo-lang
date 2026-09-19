"""Unchanged regression bodies with bounded test-only raw transport capture."""
import argparse
import base64
import gzip
import hashlib
import json
from pathlib import Path
import runpy
import subprocess
import sys
import time
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
parser=argparse.ArgumentParser()
parser.add_argument('suite',choices=('workspace22','executor17','lifecycle1','application23'))
parser.add_argument('output',type=Path)
args=parser.parse_args()
args.output.mkdir(parents=True,exist_ok=False)
original=subprocess.run
counter=0
LIMIT=1024*1024

def data(value):
    if value is None:return None
    raw=value.encode() if isinstance(value,str) else value
    return {'length':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),
            'base64':base64.b64encode(raw[:LIMIT]).decode(),'truncated':len(raw)>LIMIT}

with gzip.open(args.output/'transport.jsonl.gz','xb') as trace:
    def observed(argv,*pos,**kwargs):
        global counter
        if not isinstance(argv,(list,tuple)) or not argv or argv[0]!='orbctl':
            return original(argv,*pos,**kwargs)
        start=time.time()
        row={'sequence':counter,'argv':argv,'input':data(kwargs.get('input')),'start':start}
        counter+=1
        try:
            result=original(argv,*pos,**kwargs)
            row.update(rc=result.returncode,stdout=data(result.stdout),stderr=data(result.stderr))
            return result
        except subprocess.TimeoutExpired as exc:
            row.update(error='TimeoutExpired',stdout=data(exc.stdout),stderr=data(exc.stderr))
            raise
        finally:
            row['finish']=time.time()
            trace.write((json.dumps(row)+'\n').encode())
            trace.flush()
            if (args.output/'transport.jsonl.gz').stat().st_size>4*1024*1024:
                raise RuntimeError('test transport evidence budget exceeded')
    with patch.object(subprocess,'run',side_effect=observed):
        if args.suite=='application23':
            sys.path.insert(0,str(HERE.parent/'application'))
            import controls
            original_load=controls.load
            controls.load=lambda _:original_load(args.output/'source-cache')
            from live import IMAGE,TOOLCHAIN
            controls.run(str(args.output/'controls'),IMAGE,TOOLCHAIN,list(controls.CONTROLS))
        else:
            script={'workspace22':'test_workspace_live.py','executor17':'selftest.py','lifecycle1':'test_lifecycle_live.py'}[args.suite]
            sys.argv=[str(HERE.parent/script),str(args.output/'controls')]
            runpy.run_path(str(HERE.parent/script),run_name='__main__')
print(json.dumps({'suite':args.suite,'transport_calls':counter,'no_retries':True}))

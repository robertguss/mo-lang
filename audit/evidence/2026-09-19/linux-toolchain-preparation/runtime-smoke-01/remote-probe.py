import hashlib,json,os,pathlib,signal,subprocess,time
root=pathlib.Path.cwd();mo=os.environ['MO_BIN'];guard=root/'toolchain/bench/step36/guard.py'
def hashes():
 return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for top in ['examples','toolchain/src'] for p in (root/top).rglob('*') if p.is_file() and (p.suffix in ['.mo','.zig'] or p.name=='.mo.ids')}
before=hashes();failed=False
cases=[('model-tests',[mo,'test','examples/programs/agent/model.mo']),('model-conformance',[mo,'check','examples/programs/agent/model.mo']),('generic-conformance',[mo,'check','--recipe','Recipes.ModelClient.ModelClient','examples/programs/agent/model.mo']),('driver-check',[mo,'check','examples/programs/agent/tests/terminal-auth/driver.mo']),('driver-build',[mo,'build','examples/programs/agent/tests/terminal-auth/driver.mo','-o','terminal-auth']),('http-interpreter',['python3','examples/programs/agent/tests/terminal-auth/run.py','interpreter']),('http-compiled',['python3','examples/programs/agent/tests/terminal-auth/run.py','compiled'])]
for name,args in cases:
 command=['python3',str(guard),'180','--',*args];t=time.monotonic()
 p=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
 try:out,err=p.communicate(timeout=185)
 except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate(timeout=5)
 rows=subprocess.check_output(['ps','-eo','pid=,pgid=,args='],text=True).splitlines()
 left=[r for r in rows if len(r.split(None,2))==3 and r.split(None,2)[1]==str(p.pid)]
 if left:os.killpg(p.pid,signal.SIGKILL)
 print(json.dumps({'check':name,'command':command,'exit_code':p.returncode,'seconds':time.monotonic()-t,'stdout':out,'stderr':err,'remaining_group':left}),flush=True)
 failed|=p.returncode!=0 or bool(left)
 if failed:break
after=hashes();same=before==after
print(json.dumps({'source_files':len(before),'source_bytes_unchanged':same,'changed':[p for p in set(before)|set(after) if before.get(p)!=after.get(p)]}),flush=True)
raise SystemExit(int(failed or not same))

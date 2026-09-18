"""Isolated MOCK control-flow checks; no Mo execution/network/process killing."""
import ast, hashlib, json, pathlib, subprocess, tempfile, types, sys
R=pathlib.Path(__file__).resolve().parents[4]
T=pathlib.Path(tempfile.mkdtemp(prefix='mo-harness-current-'))
results={'scratch':str(T),'scope':'MOCK harness control flow, not real Mo/TLS behavior'}
p=R/'mo-wiki/plans/erosion-round-suite/e6-suites-mac.sh'
s=p.read_text(); digest=hashlib.sha256((p.parent/'defects6.py').read_bytes()).hexdigest()
results['seal']={'actual16':digest[:16], 'expected_literal':'d4dab05cc331b7fa','matches':digest[:16]=='d4dab05cc331b7fa'}
results['runners']=[]
for fname in ['e6-suites.sh','e6-suites-mac.sh']:
 lines=(p.parent/fname).read_text().splitlines(); start=next(i for i,l in enumerate(lines) if l.startswith('suite()')); end=next(i for i in range(start+1,len(lines)) if lines[i]=='}')
 fn='\n'.join(lines[start:end+1])
 for status in [1,124]:
  out=T/(fname+str(status));out.mkdir()
  script=f'''OUT={out}; LOG=$OUT/summary; L=mock; GEN=6
say() {{ printf '%s\\n' "$*" | tee -a "$LOG"; }}
timeout() {{ printf '%s\\n' 'MOCK suite failure'; return {status}; }}
pkill() {{ :; }}
drain() {{ :; }}
sysctl() {{ printf mock; }}
{fn}
suite injected true
rc=$?
printf 'SUITE_FUNCTION_RC=%s\\n' "$rc"
say done
'''
  ran=subprocess.run(['bash','-c',script],capture_output=True,text=True,timeout=5)
  results['runners'].append({'file':fname,'injected_exit':status,'wrapper_exit':ran.returncode,'stdout':ran.stdout})
# Import definitions only: module main guard does not run.
sys.dont_write_bytecode=True
ns={'__name__':'mock_abuse','__file__':str(R/'toolchain/bench/step38/abuse.py')}
exec(compile((R/'toolchain/bench/step38/abuse.py').read_text(),ns['__file__'],'exec'),ns)
ns['WORK']=T
class Proc:
 returncode=0
 def poll(self): return None
 def wait(self,timeout): return 0
 def terminate(self): pass
cells=[(s,a) for s in ns['SERVER_STATES'] for a in ns['ACTS']]
def popen(*a,**kw):
 kw['stdout'].write(''.join(ns['SERVER_EXPECTED'][c]+'\n'+ns['PROBE_SERVER']+'\n' for c in cells));kw['stdout'].flush();return Proc()
ns['subprocess']=types.SimpleNamespace(Popen=popen,STDOUT=-2,TimeoutExpired=subprocess.TimeoutExpired)
ns['wait_for_port']=lambda *a:None; ns['free_port']=lambda:12345;ns['probe_server']=lambda p:True
ns['client_cell']=lambda *a: (_ for _ in ()).throw(OSError('MOCK act never delivered'))
rows=ns['server_rows']('run',T/'unused')
results['abuse_injection']={'injected':'every client_cell throws OSError; mocked expected Mo logs and healthy probes','cells':len(rows),'passes':sum(r[-1]=='pass' for r in rows),'first_row':rows[0]}
# Main selection: unknown runtime reaches binary branches (source); demonstrate unvalidated label via main with mocked row runners/builds.
ns['subprocess']=subprocess
ns['build']=lambda x:T/'unused';ns['stamp']=lambda:'MOCK stamp\n'
ns['server_rows']=lambda runtime,b:[(runtime,'server','mock','','','','','yes','pass')]
ns['client_rows']=lambda runtime,b:[(runtime,'client','mock','','','','','yes','pass')]
sys.argv=['abuse.py','--runtimes','typo','--out','mock-abuse.txt']
try:ns['main']()
except SystemExit as e:results['invalid_runtime_mock_exit']=e.code
# Real invocation with invalid selection: no categories or cleanup execute.
ran=subprocess.run([sys.executable,'-B',str(p.parent/'defects6b.py'),'--serve','unused','--verify','unused','--compact','unused','--prune','unused','--bench','unused','--only','typo'],capture_output=True,text=True,timeout=5)
results['empty_selection_real']={'exit':ran.returncode,'stdout':ran.stdout,'stderr':ran.stderr}
(T/'results.json').write_text(json.dumps(results,indent=2)); print(json.dumps(results,indent=2))

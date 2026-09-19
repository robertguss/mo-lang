import subprocess, sys, os, json
root='/Users/robertguss/Projects/startups/mo-lang'
mo=root+'/toolchain/zig-out/bin/mo'; guard=root+'/toolchain/bench/step36/guard.py'
here=os.path.dirname(os.path.abspath(__file__)); os.chdir(here)
src=open('mailbox-overflow.mo').read()
for name,val in (('mailbox-zero','0'),('mailbox-u32max','4294967295'),('mailbox-huge','99999999999999999999999999')):
    open(name+'.mo','w').write(src.replace('4294967296',val))
rows=[]
def go(label,cmd):
    p=subprocess.run(['python3',guard,'120','--']+cmd,capture_output=True,text=True)
    out=(p.stdout+p.stderr).strip().split('\n')
    rows.append({'probe':label,'cmd':cmd,'exit':p.returncode,'first_lines':out[:3]})
    print(f"{label:34} exit={p.returncode:4}  {' | '.join(l.strip()[:110] for l in out[:2])}")
for f in sys.argv[1:]:
    go('check '+f,[mo,'check',f+'.mo']); go('run '+f,[mo,'run',f+'.mo'])
    go('build '+f,[mo,'build',f+'.mo','-o',f])
    b=f'zig-out/mo-build/{f}/{f}'
    if os.path.exists(b): go('native '+f,['./'+b])
json.dump(rows,open('results.json','w'),indent=1)

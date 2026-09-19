import json,pathlib,subprocess,sys,shutil
receipts=json.load(sys.stdin);base=pathlib.Path('/var/lib/mo-harness')
def cmd(argv):
 p=subprocess.run(argv,capture_output=True,text=True,timeout=5)
 if p.returncode:raise RuntimeError((argv,p.returncode,p.stderr))
 return p.stdout
mounts=pathlib.Path('/proc/self/mountinfo').read_text().splitlines()
parents={}
for name in ('mo-executor.slice','mo-application.slice'):
 props=dict(line.split('=',1) for line in cmd(['systemctl','show',name,'-p','ControlGroup','-p','ActiveState']).splitlines())
 group=props['ControlGroup']
 expected='/mo.slice/'+name
 if group and group!=expected:raise RuntimeError('parent identity')
 path=pathlib.Path('/sys/fs/cgroup'+expected)
 if not group and not (props['ActiveState']=='inactive' and not path.exists()):raise RuntimeError('inactive parent proof missing')
 if group and not path.is_dir():raise RuntimeError('active parent missing')
 tasks={str(p):p.read_text() for p in path.rglob('cgroup.procs')}
 children=[str(p) for p in path.rglob('docker-*.scope')]
 if any(v.strip() for v in tasks.values()) or children:raise RuntimeError('parent runtime remains')
 parents[name]={'group':group,'active_state':props['ActiveState'],'expected_path':str(path),'exists':path.exists(),'tasks':tasks,'candidate_cgroups':children}
rows=[]
for r in receipts:
 wid=r['workspace_id'];root=base/('mo-workspace-'+wid)
 owner=base/('.owner-'+wid)
 if not owner.is_file() or owner.is_symlink():raise RuntimeError('missing operator ownership')
 owned=json.loads(owner.read_text())
 selected={} if r['selection']['toolchain'] is None else r['selection']
 if owned!={'run_id':r['run_id'],'workspace_id':wid,'selection':selected}:raise RuntimeError('foreign owner')
 if root.is_symlink():raise RuntimeError('linked workspace')
 state=json.loads((root/'state.json').read_text()) if (root/'state.json').exists() else None
 if state and (state['run_id']!=r['run_id'] or state['workspace_id']!=wid):raise RuntimeError('foreign state')
 relevant=[line for line in mounts if line.split()[4]==str(root) or line.split()[4].startswith(str(root)+'/')]
 if relevant:raise RuntimeError('owned mounts still present; no recursive/lazy unmount')
 row={'workspace_id':wid,'owner':owned,'state':state,'mounts':relevant,'executions':[]}
 for e in r['executions']:
  name='mo-executor-'+e['execution_id'];eroot=pathlib.Path('/tmp')/name
  containers=cmd(['docker','ps','-aq','--no-trunc','--filter','name=^/'+name+'$'])
  units=cmd(['systemctl','list-units','--all','--no-legend',name+'*'])
  if containers.strip() or units.strip():raise RuntimeError('owned runtime remains')
  if eroot.is_symlink():raise RuntimeError('linked execution')
  manifest=json.loads((eroot/'manifest.json').read_text()) if (eroot/'manifest.json').exists() else None
  if eroot.exists() and (not manifest or manifest.get('run_id')!=e['execution_id'] or manifest.get('workspace',{}).get('workspace_id')!=wid):raise RuntimeError('unproven execution storage')
  row['executions'].append({'execution_id':e['execution_id'],'containers':containers,'units':units,'manifest':manifest,'root_existed':eroot.exists()})
 rows.append(row)
# Every identity and positive absence check passes before the first deletion.
for r in receipts:
 for e in r['executions']:
  path=pathlib.Path('/tmp/mo-executor-'+e['execution_id'])
  if path.exists():shutil.rmtree(path)
 root=base/('mo-workspace-'+r['workspace_id'])
 if root.exists():shutil.rmtree(root)
for r in receipts:
 if (base/('mo-workspace-'+r['workspace_id'])).exists():raise RuntimeError('workspace remains')
 for e in r['executions']:
  if pathlib.Path('/tmp/mo-executor-'+e['execution_id']).exists():raise RuntimeError('execution remains')
print(json.dumps({'operator_cleanup':True,'api_confirmation':False,'boot':pathlib.Path('/proc/sys/kernel/random/boot_id').read_text(),'parents':parents,'before':rows,'after_roots_absent':True}))

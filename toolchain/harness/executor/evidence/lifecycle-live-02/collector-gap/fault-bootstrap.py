import fcntl,json,pathlib,subprocess,sys,time
p=json.load(sys.stdin); m=p['manifest']; root=pathlib.Path(sys.argv[1])
with open('/tmp/mo-executor-registration.lock','w') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 units=subprocess.run(['systemctl','list-units','--all','--no-legend','mo-executor-*.timer'],capture_output=True,check=True).stdout
 containers=subprocess.run(['docker','ps','-aq','--filter','name=^/mo-executor-'],capture_output=True,check=True).stdout
 if units.strip() or containers.strip(): raise RuntimeError('another candidate is registered')
 root.mkdir(mode=0o700)
 (root/'remote.py').write_text(p['source'])
 m['deadline']=time.time()+m['seconds']
 (root/'manifest.json').write_text(json.dumps(m))
 name=m['name']
 subprocess.run(['systemd-run','--quiet','--collect','--unit='+name+'-deadline','--on-active='+str(m['seconds']+2)+'s','--timer-property=AccuracySec=100ms','--property=TimeoutStartSec=8s','/usr/bin/python3',str(root/'remote.py'),'reap',str(root)],check=True)
 if time.time() >= m['deadline']: raise RuntimeError('registration deadline expired before supervisor dispatch')
 subprocess.run(['systemd-run','--quiet','--collect','--unit='+name,'--property=RuntimeMaxSec='+str(m['seconds']+2)+'s','--property=TimeoutStopSec=2s','--property=KillMode=control-group','--property=ExecStopPost=/usr/bin/false','/usr/bin/python3',str(root/'remote.py'),'supervise',str(root)],check=True)
 print(json.dumps(m))

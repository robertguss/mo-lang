"""Read-only diagnostic for the retained package-01 distribution mismatch."""
import subprocess

source = '''import hashlib,json,pathlib,sys,tarfile
sys.path.insert(0,'/opt/mo-harness/application-build-v1/package-01')
import package
root=pathlib.Path('/opt/mo-harness/zig-aarch64-linux-0.16.0')
actual={row['path']:row for row in package.inventory(root)}; expected={}
with tarfile.open('/opt/mo-harness/application-build-v1/package-01/zig.tar.xz','r:xz') as archive:
 for member in archive:
  if not member.isfile(): continue
  path='/'.join(pathlib.PurePosixPath(member.name).parts[1:])
  expected[path]={'path':path,'length':member.size,'mode':member.mode,'sha256':hashlib.file_digest(archive.extractfile(member),'sha256').hexdigest()}
missing=sorted(set(expected)-set(actual)); extra=sorted(set(actual)-set(expected))
changed=[{'path':p,'expected':expected[p],'actual':actual[p]} for p in sorted(set(actual)&set(expected)) if actual[p]!=expected[p]]
print(json.dumps({'expected_count':len(expected),'actual_count':len(actual),'missing':missing[:30],'extra':extra[:30],'changed_count':len(changed),'changed':changed[:10]},indent=2))
'''
command = ['orbctl', 'run', '-m', 'mo-executor-r01', '-u', 'root', 'systemd-run',
    '--quiet', '--collect', '--wait', '--pipe', '--unit=mo-appv1-distribution-diff-01',
    '--property=RuntimeMaxSec=60', '--property=MemoryMax=512M', '--property=MemorySwapMax=0',
    '--property=CPUQuota=100%', '--property=TasksMax=32', '--property=KillMode=control-group',
    '--slice=mo-application.slice', '/usr/bin/python3', '-B', '-c', source]
print(repr(command), flush=True)
result = subprocess.run(command, timeout=70)
raise SystemExit(result.returncode)

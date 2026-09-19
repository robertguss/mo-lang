"""Read-only base/foundation comparison, written only to fresh owned evidence."""
import hashlib, json, pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parent
repo = root.parents[3]
base = '54c3dcd8617c8d693fddee8efda99e03ac05e879'
names = subprocess.check_output(['git','ls-tree','-r','--name-only',base,'toolchain/harness/provider'],cwd=repo,text=True).splitlines()
rows = {}
for name in names:
    original = subprocess.check_output(['git','show',base+':'+name],cwd=repo)
    current = (repo/name).read_bytes()
    rows[name] = {'base':hashlib.sha256(original).hexdigest(),'current':hashlib.sha256(current).hexdigest()}
assert all(row['base']==row['current'] for row in rows.values())
changed = subprocess.check_output(['git','diff',base,'--name-only'],cwd=repo,text=True).splitlines()
assert all(name.startswith('toolchain/harness/provider/auth/') for name in changed)
output = root/'evidence'/sys.argv[1]
with output.open('x') as f: json.dump({'base':base,'foundation_files':rows,'changed_tracked_paths':changed},f,indent=2)
print('unchanged foundation files',len(rows))

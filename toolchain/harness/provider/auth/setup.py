"""Fresh offline preparation from explicit previously downloaded dependency material."""
import hashlib, json, pathlib, shutil, subprocess, sys
root = pathlib.Path(__file__).resolve().parent
foundation = root.parent
source = pathlib.Path(sys.argv[1]).resolve()
target = root / '.cache' / sys.argv[2]
target.mkdir(parents=True, exist_ok=False)
for p in foundation.iterdir():
    if p.is_file(): shutil.copy2(p, target/p.name)
shutil.copytree(foundation/'evidence', target/'evidence')
(target/'.cache').mkdir()
for name in ('source.tgz', 'artifact.tgz'):
    shutil.copy2(source/'.cache'/name, target/'.cache'/name)
for name in ('source', 'artifact'):
    shutil.copytree(source/'.cache'/name, target/'.cache'/name)
shutil.copytree(source/'node_modules', target/'node_modules', symlinks=True)
for args in ([sys.executable, 'prepare.py'], [sys.executable, 'run.py', '100', 'node', 'catalog.mjs'], [sys.executable, 'verify.py']):
    subprocess.run(args, cwd=target, check=True, timeout=150)
names = ['pin.json', 'catalog.json', 'upstream.patch', 'evidence/runtime-hashes.json', 'evidence/dependencies.json']
for name in names:
    assert (target/name).read_bytes() == (foundation/name).read_bytes(), name
print(json.dumps({'copy': str(target), 'records_identical': names, 'network_requests': 0}))

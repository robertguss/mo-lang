"""Reproduce setup in a new owned copy; never regenerate historical evidence in place."""
import hashlib, json, pathlib, shutil, subprocess, sys, tempfile

root = pathlib.Path(__file__).resolve().parent
repo = root.parents[2]
guard = repo / 'toolchain/bench/step36/guard.py'
guarded = str(repo / 'toolchain/harness/executor/guarded.py')
# Snapshot tracked bytes, including historical evidence, before any verification.
tracked = subprocess.check_output(['git', 'ls-files', '-z', '--', str(root)], cwd=repo).decode().split('\0')
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
before = {name: digest(repo/name) for name in tracked if name}
output = root / sys.argv[1]
output.mkdir(parents=True, exist_ok=False)  # Refuse to overwrite an earlier attempt.
(root/'.cache').mkdir(exist_ok=True)
copy = pathlib.Path(tempfile.mkdtemp(prefix='clean-setup-', dir=root/'.cache'))
for path in root.iterdir():
    if path.is_file(): shutil.copy2(path, copy/path.name)
(copy/'evidence').mkdir()
assert not (copy/'.cache').exists() and not (copy/'node_modules').exists()
runner = copy/'cold-runner'
runner.mkdir()
def sterile(name, cwd, *command):
    # Node and npm get an empty home and a 100-second process-group bound.
    return [sys.executable, guarded, '100', str(output/(name + '-run')), '--cwd', str(cwd),
            '--home', str(cwd/'.cache/home'), '--', *command]
steps = [
    ('cold-runner', sterile('cold-runner', runner, 'node', '--version')),
    ('setup', [sys.executable, 'setup.py']),
    ('install', sterile('install', copy, 'npm', 'ci', '--ignore-scripts', '--no-audit', '--no-fund')),
    ('provenance', [sys.executable, 'provenance.py']),
    ('prepare', [sys.executable, 'prepare.py']),
    ('catalog', sterile('catalog', copy, 'node', 'catalog.mjs')),
    ('verify', [sys.executable, 'verify.py']),
]
results = []
try:
    for name, args in steps:
        command = [sys.executable, str(guard), '150', '--', *args]
        with (output/f'{name}.log').open('xb') as log:
            result = subprocess.run(command, cwd=copy, stdout=log, stderr=subprocess.STDOUT)
        (output/f'{name}.exit').write_text(str(result.returncode)+'\n')
        results.append({'step': name, 'command': command, 'cwd': str(copy), 'exit': result.returncode})
        print(name, 'exit', result.returncode, flush=True)
        if result.returncode: raise RuntimeError(f'{name} failed; see retained log')
    names = ['pin.json', 'upstream.patch', 'catalog.json', 'evidence/artifact-source.diff',
             'evidence/catalog-comparison.json', 'evidence/runtime-hashes.json', 'evidence/dependencies.json']
    comparison = {name: {'expected': digest(root/name), 'generated': digest(copy/name)} for name in names}
    assert all(row['expected'] == row['generated'] for row in comparison.values())
    assert before == {name: digest(repo/name) for name in before}
    (output/'comparison.json').write_text(json.dumps(comparison, indent=2)+'\n')
    print('PASS: cold runner, clean setup sequence, 7 byte-identical generated records; tracked bytes unchanged', flush=True)
finally:
    (output/'commands.json').write_text(json.dumps(results, indent=2)+'\n')
    (output/'tracked-after.json').write_text(json.dumps({name: digest(repo/name) for name in before}, indent=2)+'\n')
    (output/'tracked-before.json').write_text(json.dumps(before, indent=2)+'\n')

"""Owned offline attempt: fresh prepared copy and receipts; executor/guarded.py runs Node."""
import hashlib, json, pathlib, shutil, subprocess, sys, tarfile, io
root = pathlib.Path(__file__).resolve().parent
repo = root.parents[3]
name, selection = sys.argv[1:3]
assert name and '/' not in name and name not in ('.', '..')
out = root / 'evidence' / name
out.mkdir()
registered = json.loads((root/'controls.json').read_text())
selected = registered[:-1] if selection == 'independent' else selection.split(',')
if selection != 'foundation' and (not selection or len(set(selected)) != len(selected) or any(n not in registered for n in selected)):
    rejected = {'selection':selection,'exit':2,'cases':0,'provider_calls':0,'node_started':False,'dependency_copy_started':False,'reason':'unknown, empty or duplicate explicit control selection','outer_command':['python3','toolchain/bench/step36/guard.py','600','--','python3','toolchain/harness/provider/bridge/run.py',name,selection]}
    (out/'receipt.json').write_text(json.dumps(rejected,indent=2)+'\n')
    (out/'output.log').write_text('REJECTED selection before dependency copy or Node startup; cases=0 provider_calls=0 exit=2\n')
    print('BRIDGE selection rejected; cases=0 provider_calls=0 exit=2',flush=True)
    sys.exit(2)
source = pathlib.Path('/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/provider/.cache/clean-setup-8f3xpo0r')
cache = root / '.cache' / name
cache.parent.mkdir(exist_ok=True)
shutil.copytree(source, cache, ignore=shutil.ignore_patterns('cold-runner'))
shutil.copytree(root, cache / 'bridge', ignore=shutil.ignore_patterns('.cache', 'evidence'))
(cache / 'bridge' / 'evidence').mkdir()
# Original foundation bytes and all prepared runtime files must match the committed receipts.
for file in ('turn.mjs', 'test.mjs', 'catalog.json', 'package-lock.json', 'upstream.patch'):
    assert (cache / file).read_bytes() == (root.parent / file).read_bytes(), file
hashes = json.loads((root.parent / 'evidence/runtime-hashes.json').read_text())
for file, digest in hashes.items():
    assert hashlib.sha256((cache / '.cache/runtime' / file).read_bytes()).hexdigest() == digest, file
receipt = {'source': str(source), 'copy': str(cache), 'base': subprocess.check_output(['git','rev-parse','HEAD'], text=True).strip(), 'selection': selection, 'runtime_files_verified': len(hashes), 'source_revision': json.loads((cache/'pin.json').read_text())['source_revision'], 'hashes': {f: hashlib.sha256((cache/f).read_bytes()).hexdigest() for f in ('turn.mjs','catalog.json','package-lock.json','upstream.patch')}, 'outer_command':['python3','toolchain/bench/step36/guard.py','600','--','python3','toolchain/harness/provider/bridge/run.py',name,selection], 'bridge_hashes': {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in root.iterdir() if p.is_file()}}
if selection != 'foundation' and 'mo' in selected:
    main = pathlib.Path('/Users/robertguss/Projects/startups/mo-lang')
    accepted = 'e6f04ce6358c85f22a86f26be0b5b388495fcc6e'
    project = cache / 'bridge/mo-project'
    project.mkdir()
    archive = subprocess.check_output(['git','-C',str(main),'archive',accepted,'examples'])
    with tarfile.open(fileobj=io.BytesIO(archive)) as bundle: bundle.extractall(project,filter='data')
    binary = main / 'toolchain/zig-out/bin/mo'
    shutil.copy2(binary,project/'mo')
    shutil.copy2(repo/'toolchain/bench/step36/guard.py',project/'guard.py')
    release = {'explicitLeadRelease':True,'acceptedCommit':accepted,'sourceArchiveSha256':hashlib.sha256(archive).hexdigest(),'compilerSource':str(binary),'compilerSha256':hashlib.sha256((project/'mo').read_bytes()).hexdigest(),'ownedProject':str(project),'zig':'/opt/homebrew/bin/zig','release':'Lead explicit release after integrated coding fixture acceptance; 2026-09-19'}
    (cache/'bridge/release.json').write_text(json.dumps(release,indent=2)+'\n')
    receipt['moRelease']=release
(out / 'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
# One guarded runner: empty home, minimal PATH (node, npm, zig), owned process group.
node = ['bridge/test.mjs', selection, str(out/'observations.json')] if selection != 'foundation' else ['test.mjs', str(out/'outbound.json')]
command = ['python3', str(repo/'toolchain/harness/executor/guarded.py'), '550', str(out/'run'),
           '--cwd', str(cache), '--home', str(cache/'bridge/.home'), '--', 'node', *node]
receipt['command'] = command
with (out/'output.log').open('wb') as log:
    rc = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=590).returncode
receipt['runner'] = json.loads((out/'run'/'exit.json').read_text())
receipt.update(exit=rc, evidence_bytes=sum(p.stat().st_size for p in out.rglob('*') if p.is_file()))
assert receipt['evidence_bytes'] < 16 * 1024 * 1024
(out/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
print(f'BRIDGE ATTEMPT {name} exit={rc}', flush=True)
sys.exit(rc)

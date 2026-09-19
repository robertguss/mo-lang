"""Verify retained bytes and dependency metadata without executing upstream code."""
import base64, hashlib, json, pathlib, tarfile
root = pathlib.Path(__file__).resolve().parent
receipt = json.loads((root/'evidence/downloads.json').read_text())
for name in ('source', 'artifact'):
    data = (root/'.cache'/f'{name}.tgz').read_bytes()
    assert len(data) == receipt[name]['bytes']
    assert hashlib.sha256(data).hexdigest() == receipt[name]['sha256']
assert receipt['registry']['dist']['integrity'] == 'sha512-' + base64.b64encode(hashlib.sha512((root/'.cache/artifact.tgz').read_bytes()).digest()).decode()
for relative, digest in json.loads((root/'evidence/runtime-hashes.json').read_text()).items():
    assert hashlib.sha256((root/'.cache/runtime'/relative).read_bytes()).hexdigest() == digest, relative
assert (root/'catalog.json').read_bytes() == (root/'.cache/runtime/providers/data/openai-codex.json').read_bytes()
lock = json.loads((root/'package-lock.json').read_text())
rows = []
for path, package in lock['packages'].items():
    if not path: continue
    assert package['resolved'].startswith('https://registry.npmjs.org/'), path
    installed = json.loads((root/path/'package.json').read_text())
    assert installed['version'] == package['version'], path
    rows.append({'path':path,'version':package['version'],'integrity':package['integrity'],'url':package['resolved'],'license':installed.get('license',package.get('license','not declared'))})
(root/'evidence/dependencies.json').write_text(json.dumps(rows,indent=2)+'\n')
print('source/artifact integrity verified; runtime file hashes verified; dependencies',len(rows))
print('source license', receipt['registry']['license'])
print('catalog sha256',hashlib.sha256((root/'catalog.json').read_bytes()).hexdigest())

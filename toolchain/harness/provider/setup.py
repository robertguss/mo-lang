"""Bounded official downloads; no ambient npm configuration or lifecycle scripts."""
import hashlib, json, pathlib, urllib.request, tarfile, base64
root = pathlib.Path(__file__).resolve().parent
cache = root / '.cache'
cache.mkdir(parents=True, exist_ok=True)
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
pin = '36b60d2e8985899743c4cf5bd5f8929832a3f05d'
def download(url, name):
    data = opener.open(url, timeout=60).read()
    (cache / name).write_bytes(data)
    return {'url': url, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
metadata = json.load(opener.open('https://registry.npmjs.org/@earendil-works%2fpi-ai/0.85.1', timeout=60))
receipt = {'source_revision': pin, 'source': download(f'https://codeload.github.com/earendil-works/pi/tar.gz/{pin}', 'source.tgz'), 'artifact': download(metadata['dist']['tarball'], 'artifact.tgz'), 'registry': metadata}
assert receipt['source']['sha256'] == 'c2a574794f1fc26510729f2341c4c4990cfa385caf47b011bdca19afa3d22903'
assert receipt['artifact']['sha256'] == 'af7d11986179445ce6fe88b37d57de22f823c0ffd3a65cae31c555b7f5e99253'
assert metadata['dist']['integrity'] == 'sha512-' + base64.b64encode(hashlib.sha512((cache/'artifact.tgz').read_bytes()).digest()).decode()
for name, dest in [('source', 'source'), ('artifact', 'artifact')]:
    with tarfile.open(cache / (name + '.tgz')) as archive:
        archive.extractall(cache / dest, filter='data')
(root / 'evidence/downloads.json').write_text(json.dumps(receipt, indent=2)+'\n')
print(json.dumps({k:v for k,v in receipt.items() if k != 'registry'}, indent=2))

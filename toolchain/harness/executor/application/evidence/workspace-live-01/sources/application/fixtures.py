"""Exact archived source bytes and selected, unchanged generated ID records."""
import hashlib
import json
from pathlib import Path
import subprocess

SOURCE = 'e6f04ce6358c85f22a86f26be0b5b388495fcc6e'
PATHS = ['mo.root', 'hello.mo', 'logstat/main.mo', 'logstat/parse.mo',
         'logstat/report.mo', 'logstat/stats.mo', 'logstat/fixture/a.log',
         'logstat/fixture/b.log', 'logstat/fixture/c.log', 'logstat/fixture/notes.txt']


def archived(path):
    return subprocess.check_output(['git', 'show', SOURCE + ':examples/programs/' + path])


def load(cache):
    cache = Path(cache)
    cache.mkdir(parents=True, exist_ok=False)
    mapping = {path: archived(path) for path in PATHS}
    original = archived('.mo.ids')
    ids = json.loads(original)
    selected = [row for row in ids['files'] if row['path'] in PATHS]
    if {row['path'] for row in selected} != {path for path in PATHS if path.endswith('.mo')}:
        raise ValueError('missing source ID record')
    mapping['.mo.ids'] = json.dumps({**ids, 'files': selected}, indent=2).encode() + b'\n'
    if any(len(data) > 65536 for data in mapping.values()):
        raise ValueError('archived import exceeds file limit')
    for path, data in mapping.items():
        target = cache / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    goldens = {name: archived('logstat/' + name).decode() for name in ('logstat.expected', 'logstat-2.expected')}
    receipt = {'source': SOURCE, 'original_ids_sha256': hashlib.sha256(original).hexdigest(),
               'id_scope': [row['path'] for row in selected],
               'files': [{'path': path, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
                         for path, data in sorted(mapping.items())],
               'goldens': {name: hashlib.sha256(data.encode()).hexdigest() for name, data in goldens.items()}}
    return mapping, goldens, receipt

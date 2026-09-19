"""Finding 6 control: retained evidence never adds a .mo file under examples/, which the corpus
would collect and run. A retained source copy is a non-.mo artifact with a path/SHA mapping,
and the owned test directory holds .mo files only for positive corpus drivers."""
import hashlib
import json
from pathlib import Path
import tempfile

import common

POSITIVE = {'driver.mo', 'boundaries.mo'}
checks = {}
with tempfile.TemporaryDirectory(prefix='mo-app-evidence-') as tmp:
    source = common.AGENT / 'workspace-adapter.mo'
    mapping = common.retain_source(source, Path(tmp) / 'evidence')
    retained = Path(mapping['retained'])
    checks['retained_not_mo'] = not retained.name.endswith('.mo')
    checks['bytes_identical'] = retained.read_bytes() == source.read_bytes()
    checks['sha_mapping'] = mapping['sha256'] == hashlib.sha256(source.read_bytes()).hexdigest() and mapping['path'] == str(source.relative_to(common.ROOT))
owned = [p for p in common.HERE.rglob('*.mo')]
checks['no_mo_in_evidence'] = not any('evidence' in p.relative_to(common.HERE).parts for p in owned)
checks['only_positive_drivers'] = all(p.name in POSITIVE and p.parent == common.HERE for p in owned)
print(json.dumps(dict(checks=checks, owned_mo=[str(p.relative_to(common.ROOT)) for p in owned])))
raise SystemExit(0 if all(checks.values()) else 1)

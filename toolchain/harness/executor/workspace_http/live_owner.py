"""Real owner with test-only bounded raw transport recording, no work retry."""
import base64
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
from unittest.mock import patch
from . import owner

config = json.loads(Path(sys.argv[2]).read_bytes())
path = Path(config['directory']) / 'transport.jsonl.gz'
original = subprocess.run
sequence = 0


def capture(value):
    if value is None:
        return None
    raw = value.encode() if isinstance(value, str) else value
    return {'length': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
            'base64': base64.b64encode(raw[:1048576]).decode(), 'truncated': len(raw) > 1048576}

with gzip.open(path, 'xb') as stream:
    def recorded(argv, *args, **kwargs):
        global sequence
        if not isinstance(argv, (list, tuple)) or not argv or argv[0] != 'orbctl':
            return original(argv, *args, **kwargs)
        row = dict(sequence=sequence, argv=argv, input=capture(kwargs.get('input')), started=time.time())
        sequence += 1
        try:
            result = original(argv, *args, **kwargs)
            row.update(exit=result.returncode, stdout=capture(result.stdout), stderr=capture(result.stderr))
            return result
        except subprocess.TimeoutExpired as exc:
            row.update(error='TimeoutExpired', stdout=capture(exc.stdout), stderr=capture(exc.stderr))
            raise
        finally:
            row['finished'] = time.time()
            stream.write((json.dumps(row) + '\n').encode())
            stream.flush()
            if path.stat().st_size > 4 * 1024 * 1024:
                raise RuntimeError('raw transport capture budget')
    with patch.object(subprocess, 'run', side_effect=recorded):
        if (Path(config['directory']) / 'test-lost-create').exists():
            import workspace
            remote = workspace.remote
            def lost_create(*args, **kwargs):
                result = remote(*args, **kwargs)
                if json.loads(kwargs['data'])['request']['operation'] == 'create':
                    raise TimeoutError('test lost create response after actual effect')
                return result
            with patch.object(workspace, 'remote', side_effect=lost_create):
                owner.main()
        else:
            owner.main()

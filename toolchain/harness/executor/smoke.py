from pathlib import Path
import json
import sys
from adapter import Run
from test_executor import check
r = Run('echo ok', [check()], Path(sys.argv[1]) / 'positive', 5)
try:
    r.start()
    result = r.collect()
    print(json.dumps(result, indent=2), flush=True)
    assert result['passed']
finally:
    r.dispose()

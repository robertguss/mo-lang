"""size.py: non-blank non-comment lines of the Python this program replaces, against
the Mo sources. Test lines separately. One committed script, so the size table is
reproduced, not estimated."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
HTTP = ROOT / 'toolchain/harness/executor/workspace_http'
EXEC = ROOT / 'toolchain/harness/executor'


def lines(path, *, tests=False):
    text = path.read_text()
    count = 0
    in_test = False
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith('#') or line.startswith('//'):
            continue
        if path.suffix == '.py':
            if line.startswith('def test_') or line.startswith('class ') and 'Test' in line:
                in_test = True
            if tests == in_test:
                count += 1
            if in_test and line.startswith('def ') and not line.startswith('def test_'):
                in_test = False
                if not tests:
                    count += 1
        else:
            if line.startswith('test ') or line.startswith('property '):
                in_test = True
            if line == 'end' and in_test:
                if tests:
                    count += 1
                in_test = False
                continue
            if tests == in_test:
                count += 1
    return count


def main():
    python = {
        'bridge.py': HTTP / 'bridge.py',
        'owner.py': HTTP / 'owner.py',
        'protocol.py': HTTP / 'protocol.py',
        'workspace_files.py (all five file tools)': EXEC / 'workspace_files.py',
        'workspace_controller.py (file dispatch only; command/container left for part B)':
            EXEC / 'workspace_controller.py',
    }
    # controller: count only rows that mention file tools / inventory / exact_edit /
    # search / read_file / write_file / list_files, not docker or command.
    controller = (EXEC / 'workspace_controller.py').read_text().splitlines()
    file_marks = ('list_files', 'read_file', 'search', 'write_file', 'exact_edit',
                  'inventory', 'workspace_files', 'truncated', 'result_too_large')
    controller_file = 0
    for raw in controller:
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if any(m in line for m in file_marks):
            controller_file += 1

    mo_src = sorted(HERE.glob('*.mo'))
    rows = []
    py_src = py_test = 0
    for name, path in python.items():
        if 'controller' in name:
            src, test = controller_file, 0
        else:
            src, test = lines(path, tests=False), lines(path, tests=True)
        rows.append({'side': 'python', 'name': name, 'source': src, 'test': test})
        py_src += src
        py_test += test

    mo_s = mo_t = 0
    for path in mo_src:
        src, test = lines(path, tests=False), lines(path, tests=True)
        rows.append({'side': 'mo', 'name': path.name, 'source': src, 'test': test})
        mo_s += src
        mo_t += test

    extra = HERE / 'behaviour.py'
    if extra.exists():
        src, test = lines(extra, tests=False), lines(extra, tests=True)
        rows.append({'side': 'mo-harness', 'name': 'behaviour.py', 'source': src, 'test': test})

    summary = {
        'python_source': py_src,
        'python_test': py_test,
        'mo_source': mo_s,
        'mo_test': mo_t,
        'features_dropped': [
            'command through Exec / the real controller (part B)',
            'container policy and cleanup proofs on the machine (part B)',
            'Python owner subprocess, orbctl, workspace_controller HTTP to the machine',
        ],
        'features_added': [
            'four separate journal observations (admission, execution, reply produced, delivery)',
            'operator path on its own listener and token (D2)',
            'binding hashes for source and verifier configuration',
            'H1–H6 held in the Mo processes (one deadline, half-close is not pipelining, '
            'one process per connection, truncated not output_encoding, invalid_result, '
            'disconnect is delivery unknown)',
        ],
        'rows': rows,
    }
    print(json.dumps(summary, indent=2))
    print(f"python source {py_src} test {py_test}")
    print(f"mo source {mo_s} test {mo_t}")


if __name__ == '__main__':
    main()

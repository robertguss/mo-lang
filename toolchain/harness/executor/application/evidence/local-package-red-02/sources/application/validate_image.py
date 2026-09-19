"""Inspect a stopped image container and hash its actual exported toolchain."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile


def validate(image, manifest, name):
    expected = json.loads(Path(manifest).read_text())['image_files']
    info = json.loads(subprocess.check_output(['docker', 'image', 'inspect', image]))[0]
    if info['Id'] != image or info['Architecture'] != 'arm64' or info['Os'] != 'linux':
        raise ValueError('image identity/platform mismatch')
    if info['Config']['User'] != '65534:65534' or info['Config']['WorkingDir'] != '/workspace':
        raise ValueError('image user/cwd mismatch')
    if not name.startswith('mo-appv1-') or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in name):
        raise ValueError('invalid owned container name')
    p = None
    try:
        subprocess.run(['docker', 'create', '--name', name, '--pull=never', '--network=none',
                        image, '/bin/true'], check=True, capture_output=True, timeout=10)
        p = subprocess.Popen(['docker', 'export', name], stdout=subprocess.PIPE)
        rows = []
        with tarfile.open(fileobj=p.stdout, mode='r|') as archive:
            for member in archive:
                name_in_image = member.name.removeprefix('./')
                if not name_in_image.startswith('opt/mo/') or member.isdir():
                    continue
                if not member.isfile() or member.uid != 0 or member.gid != 0:
                    raise ValueError('nonregular/nonroot toolchain file')
                stream = archive.extractfile(member)
                rows.append({'path': name_in_image.removeprefix('opt/mo/'), 'mode': member.mode,
                             'length': member.size, 'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()})
        if p.wait(timeout=10) != 0:
            raise ValueError('image export failed')
        if sorted(rows, key=lambda row: row['path']) != expected:
            raise ValueError('image toolchain content mismatch')
        return {'image': image, 'files_verified': len(rows), 'toolchain': hashlib.sha256(Path(manifest).read_bytes()).hexdigest()}
    finally:
        if p:
            if p.poll() is None:
                p.kill()
            p.wait(timeout=3)
            p.stdout.close()
        subprocess.run(['docker', 'rm', '-f', name], check=True, capture_output=True, timeout=10)
        remaining = subprocess.check_output(['docker', 'ps', '-aq', '--filter', 'name=^/' + name + '$'])
        if remaining.strip():
            raise RuntimeError('image inspection container remains')


if __name__ == '__main__':
    print(json.dumps(validate(*sys.argv[1:])), flush=True)

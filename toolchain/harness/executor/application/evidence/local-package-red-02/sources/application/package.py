"""Offline context from exact trusted compiler and verified Zig archive contents."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import stat
import tarfile

MO_SOURCE = 'e3a01bbf613c1f130955b6e123d5987a4c559d18'
MO_SHA = '4d14520aaf25403396e14501efbab2f5cd3d7f29bba4ad7c124155c06c806c72'
MO_SIZE = 15923616
ZIG_SHA = 'ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17'
ZIG_ROOT = 'zig-aarch64-linux-0.16.0'


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def inventory(root):
    rows = []
    for path in sorted(root.rglob('*')):
        mode = path.lstat().st_mode
        if stat.S_ISDIR(mode):
            continue
        if not stat.S_ISREG(mode) or path.stat().st_nlink != 1:
            raise ValueError('nonregular or linked package input: ' + str(path))
        rows.append({'path': path.relative_to(root).as_posix(), 'length': path.stat().st_size,
                     'mode': stat.S_IMODE(mode), 'sha256': sha(path)})
    if not rows:
        raise ValueError('empty package inventory')
    return rows


def verify_distribution(archive, installed):
    if sha(archive) != ZIG_SHA:
        raise ValueError('Zig archive hash mismatch')
    rows = {}
    with tarfile.open(archive, 'r:xz') as source:
        for member in source:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or path.parts[0] != ZIG_ROOT:
                raise ValueError('invalid archive path')
            if member.isdir():
                continue
            if not member.isfile():
                raise ValueError('nonregular archive entry')
            relative = PurePosixPath(*path.parts[1:]).as_posix()
            if relative in rows:
                raise ValueError('duplicate archive entry')
            stream = source.extractfile(member)
            rows[relative] = {'path': relative, 'length': member.size,
                              'mode': member.mode, 'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}
    actual = inventory(installed)
    if actual != [rows[key] for key in sorted(rows)]:
        raise ValueError('installed Zig differs from original archive')
    return actual


def package(mo, zig, archive, output):
    if mo.is_symlink() or mo.stat().st_size != MO_SIZE or sha(mo) != MO_SHA:
        raise ValueError('Mo executable identity mismatch')
    distribution = verify_distribution(archive, zig)
    output.mkdir(parents=True, exist_ok=False)
    context = output / 'context'
    target = context / 'toolchain'
    target.mkdir(parents=True)
    shutil.copyfile(mo, target / 'mo')
    shutil.copyfile(zig / 'zig', target / 'zig')
    for name in ('mo', 'zig'):
        (target / name).chmod(0o755)
    shutil.copytree(zig / 'lib', target / 'lib')
    recipe = Path(__file__).with_name('Dockerfile')
    shutil.copyfile(recipe, context / 'Dockerfile')
    manifest = {'policy': 'application-build-v1', 'mo_source': MO_SOURCE,
                'mo_sha256': MO_SHA, 'mo_bytes': MO_SIZE, 'zig_archive_sha256': ZIG_SHA,
                'zig_distribution': distribution, 'image_files': inventory(target),
                'recipe_sha256': sha(recipe), 'package_source_sha256': sha(Path(__file__))}
    raw = json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode()
    (output / 'manifest.json').write_bytes(raw)
    identity = hashlib.sha256(raw).hexdigest()
    (output / 'toolchain.sha256').write_text(identity + '\n')
    print(json.dumps({'toolchain': identity, 'files': len(manifest['image_files'])}), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--mo', type=Path, required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    package(args.mo, args.zig, args.archive, args.output)

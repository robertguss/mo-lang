"""Descriptor-only file tools. Caller holds the workspace lock; no writers run."""
from contextlib import contextmanager
import hashlib
import json
import os
import stat
import uuid

CAP = 65536
MAX_FILES = 1000
MAX_BYTES = 64 * 1024 * 1024


class Refusal(ValueError):
    pass


def path_parts(path, root=False):
    if root and path == '.':
        return []
    if not isinstance(path, str) or not path or '\0' in path:
        raise Refusal('invalid_path')
    try:
        encoded = path.encode('utf-8')
    except UnicodeError:
        raise Refusal('invalid_utf8') from None
    parts = path.split('/')
    if len(encoded) > 4096 or any(p in ('', '.', '..') or len(p.encode()) > 255 for p in parts):
        raise Refusal('invalid_path')
    return parts


def text_bytes(text):
    if not isinstance(text, str):
        raise Refusal('invalid_utf8')
    try:
        data = text.encode('utf-8')
    except UnicodeError:
        raise Refusal('invalid_utf8') from None
    if len(data) > CAP:
        raise Refusal('oversized')
    return data


@contextmanager
def directory(root_fd, parts, create=False):
    fd = os.dup(root_fd)
    try:
        for part in parts:
            if create:
                try:
                    os.mkdir(part, 0o755, dir_fd=fd)
                except FileExistsError:
                    pass
            nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
            os.close(fd)
            fd = nxt
        yield fd
    finally:
        os.close(fd)


def read_at(fd, name):
    child = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
    try:
        info = os.fstat(child)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
            raise Refusal('unsupported_entry')
        if info.st_mode & 0o7000:
            raise Refusal('unsupported_mode')
        if info.st_size > CAP:
            raise Refusal('oversized')
        data = bytearray()
        while len(data) <= CAP:
            chunk = os.read(child, min(8192, CAP + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        if len(data) > CAP:
            raise Refusal('oversized')
        return bytes(data), (0o755 if info.st_mode & 0o111 else 0o644)
    finally:
        os.close(child)


def read_file(root_fd, path):
    parts = path_parts(path)
    with directory(root_fd, parts[:-1]) as fd:
        data, _ = read_at(fd, parts[-1])
    try:
        return data.decode('utf-8')
    except UnicodeError:
        raise Refusal('invalid_utf8') from None


def replace_file(root_fd, path, data, create=False, mode=None, owner=None):
    parts = path_parts(path)
    if not isinstance(data, bytes) or len(data) > CAP:
        raise Refusal('oversized')
    with directory(root_fd, parts[:-1], create=create) as fd:
        try:
            _, previous_mode = read_at(fd, parts[-1])
        except FileNotFoundError:
            previous_mode = 0o644
        temp = '.mo-write-' + uuid.uuid4().hex
        child = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=fd)
        try:
            with os.fdopen(child, 'wb') as output:
                output.write(data)
                os.fchmod(output.fileno(), mode or previous_mode)
                if owner is not None:
                    os.fchown(output.fileno(), *owner)
            os.rename(temp, parts[-1], src_dir_fd=fd, dst_dir_fd=fd)
        finally:
            try:
                os.unlink(temp, dir_fd=fd)
            except FileNotFoundError:
                pass


def write_file(root_fd, path, text, owner=None):
    replace_file(root_fd, path, text_bytes(text), owner=owner)
    return {'written': True}


def exact_edit(root_fd, path, old, new, owner=None):
    before = read_file(root_fd, path).encode('utf-8')
    needle, replacement = text_bytes(old), text_bytes(new)
    if not needle:
        raise Refusal('empty_old')
    positions = []
    start = 0
    while True:
        pos = before.find(needle, start)
        if pos < 0:
            break
        positions.append(pos)
        if len(positions) > 1:
            raise Refusal('multiple_matches')
        start = pos + 1
    if not positions:
        raise Refusal('missing_match')
    pos = positions[0]
    after = before[:pos] + replacement + before[pos + len(needle):]
    if len(after) > CAP:
        raise Refusal('oversized')
    replace_file(root_fd, path, after, owner=owner)
    return {'edited': True}


def inventory(root_fd, root='.'):
    """Validate the complete tree; empty directories are not snapshot content."""
    parts = path_parts(root, root=True)
    rows = []
    total = 0
    entries = 0

    def walk(fd, prefix):
        nonlocal total, entries
        for name in sorted(os.listdir(fd)):
            entries += 1
            if entries > 4096:
                raise Refusal('too_many_entries')
            path = '/'.join(prefix + [name])
            path_parts(path)
            info = os.stat(name, dir_fd=fd, follow_symlinks=False)
            if stat.S_ISDIR(info.st_mode):
                if info.st_mode & 0o7000:
                    raise Refusal('unsupported_mode')
                with directory(fd, [name]) as child:
                    walk(child, prefix + [name])
            else:
                data, mode = read_at(fd, name)
                total += len(data)
                if len(rows) >= MAX_FILES or total > MAX_BYTES:
                    raise Refusal('quota')
                rows.append({'path': path, 'length': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'mode': mode})
    with directory(root_fd, parts) as fd:
        walk(fd, parts)
    return sorted(rows, key=lambda row: row['path'])


def bounded(items, limit):
    result = {'items': [], 'truncated': False}
    for item in items:
        result['items'].append(item)
        if len(result['items']) > limit or len(json.dumps(result).encode()) > CAP - 1024:
            result['items'].pop()
            result['truncated'] = True
            break
    return result


def list_files(root_fd, root='.'):
    return bounded(inventory(root_fd, root), MAX_FILES)


def search(root_fd, text, root='.'):
    needle = text_bytes(text)
    if not needle:
        raise Refusal('empty_search')
    hits = []
    # Validate all text even if earlier files already fill the result budget.
    for row in inventory(root_fd, root):
        data = read_file(root_fd, row['path']).encode()
        offset = 0
        while len(hits) <= 200:
            pos = data.find(needle, offset)
            if pos < 0:
                break
            hits.append({'path': row['path'], 'offset': pos})
            offset = pos + 1
    return bounded(hits, 200)


def validate_import(files):
    if not isinstance(files, list) or len(files) > MAX_FILES:
        raise Refusal('invalid_import')
    seen = set()
    total = 0
    for pair in files:
        if not isinstance(pair, (list, tuple)) or len(pair) != 2:
            raise Refusal('invalid_import')
        path, data = pair
        path_parts(path)
        if path in seen or not isinstance(data, bytes) or len(data) > CAP:
            raise Refusal('invalid_import')
        seen.add(path)
        total += len(data)
    if total > MAX_BYTES:
        raise Refusal('quota')
    if any('/'.join(path.split('/')[:i]) in seen for path in seen for i in range(1, len(path.split('/')))):
        raise Refusal('path_conflict')
    return files

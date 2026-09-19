"""Download and hash the official Linux compiler archive; do not install it."""
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from zoneinfo import ZoneInfo

HERE = Path(__file__).resolve().parent
cache = Path(tempfile.mkdtemp(prefix="mo-linux-toolchain-", dir="/private/tmp"))
index_url = "https://ziglang.org/download/index.json"
archive_url = "https://ziglang.org/download/0.16.0/zig-aarch64-linux-0.16.0.tar.xz"
expected = "ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17"
commands = []
for name, url in (("index.json", index_url), ("zig-aarch64-linux-0.16.0.tar.xz", archive_url)):
    path = cache / name
    argv = ["curl", "--fail", "--location", "--connect-timeout", "10", "--max-time", "120", "--max-filesize", "60000000", "--output", str(path), url]
    result = subprocess.run(argv, capture_output=True, text=True, timeout=125)
    commands.append({"argv": argv, "exit_code": result.returncode, "stderr": result.stderr})
    (HERE / "download-commands.json").write_text(json.dumps(commands, indent=2) + "\n")
    result.check_returncode()
index = json.loads((cache / "index.json").read_text())["0.16.0"]["aarch64-linux"]
assert index["tarball"] == archive_url and index["shasum"] == expected
archive = cache / "zig-aarch64-linux-0.16.0.tar.xz"
digest = hashlib.file_digest(archive.open("rb"), "sha256").hexdigest()
assert digest == expected and archive.stat().st_size == int(index["size"])
record = {"at_et": datetime.now(ZoneInfo("America/New_York")).isoformat(),
          "source": index_url, "entry": index, "archive": str(archive),
          "sha256": digest, "bytes": archive.stat().st_size,
          "hash_verified": True, "installed": False, "executed": False}
(HERE / "archive.json").write_text(json.dumps(record, indent=2) + "\n")
print(json.dumps(record), flush=True)

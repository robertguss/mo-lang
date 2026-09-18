"""Change 6's sequence, through real `jobq serve` processes on one folder, with every step's
expected answer written here: create keyed jobs into two queues; lease and ack some; wait
past `retain_ms` so they archive, in two batches a second apart; stop; `compact`, and a
second `compact` killed between the rename of the compacted log and the directory's fsync;
rename one queue; create into the old name; prune with an age between the two batches;
stop; `verify`; create again with a freed key and with a used key; lease, ack, list,
`/queues`, `/archive`, `/health`; stop; `verify`.

usage: python checks/sequence.py <dir>

The folder may be fresh or one an earlier program wrote (check.sh runs both): the script
reads its starting counts first, uses queues of its own (`seq-*`), and expects the folder's
own jobs to be where they were, its archived ones pruned with the first batch (they are
older). Exit 0 and one `ok` line per step, or exit 1 at the first answer that differs.
"""

import http.client
import json
import os
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

HOST = "127.0.0.1"
TIMEOUT_S = 60  # within: every socket and process wait (chosen)
RETAIN_MS = 1_000
PAST_RETAIN_S = 1.4  # past `--retain-ms 1000`, with room for a slow look (chosen)
KILL_CODE = 137
SERVE = (sys.executable, "-m", "jobq", "serve")

# The kill: a compaction whose directory fsync after the log's rename never runs.
KILLED_COMPACT = """
import os, sys
from pathlib import Path
import jobq.store as store
real_rename, renamed = os.rename, []
def rename(src, dst, **kw):
    real_rename(src, dst, **kw)
    renamed.append(dst)
real_fsync = os.fsync
def fsync(fd):
    if renamed and renamed[-1] == store.LOG_NAME and os.path.isdir(f"/proc/self/fd/{fd}"):
        os._exit(137)
    real_fsync(fd)
os.rename, os.fsync = rename, fsync
store.compact(Path(sys.argv[1]))
"""


class Mismatch(Exception):
    pass


def expect(what: str, got: object, want: object) -> None:
    if got != want:
        raise Mismatch(f"{what}: got {got!r}, expected {want!r}")
    print(f"ok: {what}")


def ms(iso: object) -> int:
    assert isinstance(iso, str)
    return int(datetime.fromisoformat(iso).timestamp() * 1000)


def jobq(*argv: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "jobq", *argv],
        capture_output=True,
        text=True,
        timeout=TIMEOUT_S,
        check=False,
    )


class Served:
    """`jobq serve <dir> --port 0 --retain-ms 1000` in its own process."""

    def __init__(self, directory: Path) -> None:
        self.process = subprocess.Popen(
            [*SERVE, str(directory), "--port", "0", "--retain-ms", str(RETAIN_MS)],
            stderr=subprocess.PIPE,
            text=True,
        )
        assert self.process.stderr is not None
        line = self.process.stderr.readline()
        if ":" not in line:
            raise Mismatch(f"serve did not start: {line.strip()!r}")
        self.port = int(line.rsplit(":", 1)[1])

    def call(self, method: str, path: str, body: object = None) -> tuple[int, Any]:
        connection = http.client.HTTPConnection(HOST, self.port, timeout=TIMEOUT_S)
        try:
            data = None if body is None else json.dumps(body).encode()
            connection.request(method, path, data, {"authorization": "Bearer seq"})
            response = connection.getresponse()
            raw = response.read()
            return response.status, json.loads(raw) if raw else None
        finally:
            connection.close()

    def stop(self) -> None:
        self.process.send_signal(signal.SIGTERM)
        code = self.process.wait(TIMEOUT_S)
        if self.process.stderr is not None:
            self.process.stderr.close()
        expect("serve exits 0 on SIGTERM", code, 0)


def create(served: Served, queue: str, key: str) -> tuple[int, str]:
    status, job = served.call(
        "POST", "/jobs", {"queue": queue, "payload": "p", "max_tries": 1} | {"key": key}
    )
    return status, job["id"]


def job_id(number: int) -> str:
    return f"j_{number}"


def lease_and_ack(served: Served, queue: str, want: str) -> None:
    status, job = served.call("POST", f"/queues/{queue}/lease", {"lease_ms": 60_000})
    expect(f"lease {queue}", (status, job["id"]), (200, want))
    status, job = served.call("POST", f"/jobs/{want}/ack")
    expect(f"ack {want}", (status, job["state"]), (200, "done"))


def sequence(directory: Path) -> None:  # noqa: PLR0915 - the spec's sequence, one step a line
    # Session 1: two queues, keyed creates, two batches archived a second and more apart.
    served = Served(directory)
    status, start = served.call("GET", "/health")
    expect("the folder opens", status, 200)
    base_queues = {q["name"]: q for q in served.call("GET", "/queues")[1]["queues"]}
    base_archived = served.call("GET", "/archive")[1]["archived"]
    status, first = create(served, "seq-a", "ka1")
    n = int(first[2:])
    expect("create seq-a ka1", status, 201)
    expect("create seq-a ka2", create(served, "seq-a", "ka2"), (201, job_id(n + 1)))
    expect("create seq-a ka3", create(served, "seq-a", "ka3"), (201, job_id(n + 2)))
    expect("create seq-b kb1", create(served, "seq-b", "kb1"), (201, job_id(n + 3)))
    expect("create seq-b kb2", create(served, "seq-b", "kb2"), (201, job_id(n + 4)))
    lease_and_ack(served, "seq-a", job_id(n))
    lease_and_ack(served, "seq-b", job_id(n + 3))
    time.sleep(PAST_RETAIN_S)
    expect(
        "the first batch archives", served.call("GET", "/health")[1]["archived"], base_archived + 2
    )
    first_at = ms(served.call("GET", f"/jobs/{job_id(n)}")[1]["archived_at"])
    lease_and_ack(served, "seq-a", job_id(n + 1))
    time.sleep(PAST_RETAIN_S)
    expect(
        "the second batch archives", served.call("GET", "/health")[1]["archived"], base_archived + 3
    )
    second_at = ms(served.call("GET", f"/jobs/{job_id(n + 1)}")[1]["archived_at"])
    served.stop()

    # The compaction, and one killed after the log's rename before the directory's fsync.
    expect("compact", jobq("compact", str(directory)).returncode, 0)
    killed = subprocess.run(
        [sys.executable, "-c", KILLED_COMPACT, str(directory)], timeout=TIMEOUT_S, check=False
    )
    expect("a compaction killed before the directory's fsync", killed.returncode, KILL_CODE)
    expect("verify after the kill", jobq("verify", str(directory)).returncode, 0)

    # Session 2: rename, a create into the old name, a prune between the batches.
    served = Served(directory)
    status, renamed = served.call("POST", "/queues/seq-a/rename", {"to": "seq-c"})
    expect("rename seq-a to seq-c", (status, renamed), (200, {"queue": "seq-c", "moved": 3}))
    expect(
        "create into the old name, key ka1", create(served, "seq-a", "ka1"), (201, job_id(n + 5))
    )
    older_than = int(time.time() * 1000) - (first_at + second_at) // 2
    status, pruned = served.call("POST", "/archive/prune", {"older_than_ms": older_than})
    expect(
        "prune between the batches",
        (status, pruned),
        (200, {"pruned": base_archived + 2, "remaining": 1}),
    )
    expect("a pruned job is 404", served.call("GET", f"/jobs/{job_id(n)}")[0], 404)
    expect("so is the other", served.call("GET", f"/jobs/{job_id(n + 3)}")[0], 404)
    status, kept = served.call("GET", f"/jobs/{job_id(n + 1)}")
    expect("the younger one is kept, renamed", (status, kept["queue"]), (200, "seq-c"))
    served.stop()

    verified = jobq("verify", str(directory))
    expect("verify", verified.returncode, 0)
    expect("verify counts one archived job", verified.stdout.rstrip().endswith("archived 1"), True)

    # Session 3: the freed key, the used key, lease, ack, list, /queues, /archive, /health.
    served = Served(directory)
    expect("create with the freed key kb1", create(served, "seq-b", "kb1"), (201, job_id(n + 6)))
    expect("create with the used key ka2", create(served, "seq-c", "ka2"), (200, job_id(n + 1)))
    expect(
        "create with the old name's key ka1", create(served, "seq-a", "ka1"), (200, job_id(n + 5))
    )
    expect("the pruned ka1 in seq-c is free", create(served, "seq-c", "ka1"), (201, job_id(n + 7)))
    lease_and_ack(served, "seq-c", job_id(n + 2))
    status, listed = served.call("GET", "/jobs?queue=seq-a")
    expect("list seq-a", (status, [j["id"] for j in listed["jobs"]]), (200, [job_id(n + 5)]))
    status, listed = served.call("GET", "/jobs?queue=seq-c&key=ka2")
    expect("list seq-c by key ka2", [j["id"] for j in listed["jobs"]], [job_id(n + 1)])
    status, queues = served.call("GET", "/queues")
    by_name = {q["name"]: q for q in queues["queues"]}
    zero = {"queued": 0, "scheduled": 0, "leased": 0, "done": 0, "dead": 0}
    expect("/queues seq-a", by_name.pop("seq-a"), {"name": "seq-a"} | zero | {"queued": 1})
    expect("/queues seq-b", by_name.pop("seq-b"), {"name": "seq-b"} | zero | {"queued": 2})
    expect(
        "/queues seq-c", by_name.pop("seq-c"), {"name": "seq-c"} | zero | {"queued": 1, "done": 1}
    )
    expect("/queues, the folder's own", by_name, base_queues)
    status, archive = served.call("GET", "/archive")
    size = (directory / "jobq.archive").stat().st_size
    expect(
        "/archive",
        (status, archive["archived"], ms(archive["oldest_archived_at"]), archive["bytes"]),
        (200, 1, second_at, size),
    )
    status, health = served.call("GET", "/health")
    counts = {k: health[k] for k in ("queued", "scheduled", "leased", "done", "dead", "archived")}
    want = {k: start[k] for k in counts} | {"archived": 1}
    want["queued"] += 4
    want["done"] += 1
    expect("/health", (status, counts), (200, want))
    served.stop()
    expect("verify at the end", jobq("verify", str(directory)).returncode, 0)


def main() -> int:
    directory = Path(sys.argv[1])
    try:
        sequence(directory)
    except Mismatch as mismatch:
        print(f"sequence.py: {directory}: {mismatch}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    os.environ.setdefault("PYTHONUNBUFFERED", "1")
    sys.exit(main())

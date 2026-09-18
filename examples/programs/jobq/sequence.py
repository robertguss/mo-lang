"""jobq's change-6 sequence end to end, over a real socket: the program-level check the change asks for.

Run from examples/programs/jobq with the command that runs jobq:

    python3 sequence.py mo run main.mo --
    python3 sequence.py zig-out/mo-build/main/main

It runs the same sequence twice: on a fresh folder, and on a copy of data/change5, a folder the
change-5 program wrote (made with `python3 sequence.py --fixture <change-5 jobq>`): jobs created with
keys in two queues, some leased and acked, archived a second later, the folder compacted, a queue
renamed, the old name used again, and, in data/change5, one more rename after the compaction, the
state the change-5 program then refused to open ("the rename count is below rename_2").

The sequence: create keyed jobs in two queues; lease and ack two of each, the first queue's a few
seconds before the second's, so each pair is archived at its own time; stop, compact, verify, serve;
rename the first queue; create into its old name with a key its archived jobs used; prune with an age
between the two archive times (the first pair and any older archived job go, the second pair stays);
kill the service at once and find the prune's one record on disk; reopen, verify; create with a freed
key (201, a new job) and a used key (200, the first job); lease, ack, list, /queues, /archive, /health.
Every step's expected answer is here.

Persistence is named twice. The file's contents: each change is in the log before the response that
reports it, checked by killing the service right after the prune's 200 and reading the log. The
directory entry: compact writes jobq.log.new and renames it over jobq.log, and the check finds the
folder holding jobq.log and no jobq.log.new; a kill between the rename and a sync of the folder cannot
be placed, because the program cannot sync a folder (no Fs row does; TOOLCHAIN-BUGS.md, 6), so that
one is reported as not placed. Every server is killed past 300 seconds or 4 GB.
"""

import http.client
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time

LIMIT_BYTES = 4 * 1024 * 1024 * 1024
HERE = os.path.dirname(os.path.abspath(__file__))


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def request(port, method, path, token="p", body=None):
    try:
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
        headers = {"authorization": f"Bearer {token}"} if token else {}
        conn.request(method, path, body=json.dumps(body) if body is not None else None, headers=headers)
        response = conn.getresponse()
        text = response.read().decode()
        conn.close()
        return response.status, (json.loads(text) if text else None)
    except (OSError, http.client.HTTPException):
        return 0, None


class Server:
    def __init__(self, command, folder, *flags):
        self.port = free_port()
        self.proc = subprocess.Popen(command + ["serve", folder, "--port", str(self.port), *flags],
                                     stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        self.started = time.monotonic()
        threading.Thread(target=self._guard, daemon=True).start()
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if self.proc.poll() is not None:
                raise AssertionError(f"serve exited {self.proc.returncode}: {self.proc.stderr.read()}")
            if request(self.port, "GET", "/health", None)[0] == 200:
                return
            time.sleep(0.05)
        raise AssertionError("serve did not answer within 60 seconds")

    def _guard(self):
        while self.proc.poll() is None:
            out = subprocess.run(["ps", "-o", "rss=", "-p", str(self.proc.pid)], capture_output=True, text=True).stdout.strip()
            if (out and int(out) * 1024 > LIMIT_BYTES) or time.monotonic() - self.started > 300:
                self.proc.kill()
                return
            time.sleep(0.5)

    def stop(self):
        if self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
            try:
                self.proc.wait(10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()

    def kill(self):
        self.proc.kill()
        self.proc.wait()


def run(command, *args):
    return subprocess.run(command + list(args), capture_output=True, text=True, timeout=300)


def check(condition, what):
    if not condition:
        raise AssertionError(what)
    print(f"ok  {what}")


def expect(got, status, what):
    check(got[0] == status, f"{what}: {status} (got {got[0]} {json.dumps(got[1])[:160] if got[1] is not None else ''})")
    return got[1]


def make(port, queue, key):
    return expect(request(port, "POST", "/jobs", "p", {"queue": queue, "payload": key, "max_tries": 2, "key": key}),
                  201, f"create {key} in {queue}")["id"]


def finish(port, queue, worker):
    job = expect(request(port, "POST", f"/queues/{queue}/lease", worker, {"lease_ms": 3600000}), 200, f"lease from {queue}")
    done = expect(request(port, "POST", f"/jobs/{job['id']}/ack", worker), 200, f"ack {job['id']}")
    check(done["state"] == "done", f"{job['id']} is done")
    return job["id"]


def archived_after(port, jobs, wait):
    time.sleep(wait)
    expect(request(port, "GET", "/health", None), 200, "a look")
    for job in jobs:
        body = expect(request(port, "GET", f"/jobs/{job}"), 200, f"read {job}")
        check("archived_at" in body, f"{job} is archived a second after its ack")
    return time.time()


def sequence(command, folder, label):
    print(f"-- the sequence on {label}")
    result = run(command, "verify", folder)
    check(result.returncode == 0, f"verify opens the folder first: {result.stdout.strip()} {result.stderr.strip()}")
    server = Server(command, folder, "--retain-ms", "1000")
    port = server.port
    before = expect(request(port, "GET", "/archive"), 200, "GET /archive before")
    old_archived = before["archived"]
    health0 = expect(request(port, "GET", "/health", None), 200, "health before")
    keys = {"s1": ["s1-k1", "s1-k2", "s1-k3"], "s2": ["s2-k1", "s2-k2", "s2-k3"]}
    made = {key: make(port, queue, key) for queue, names in keys.items() for key in names}
    first = [finish(port, "s1", "w1") for _ in range(2)]
    first_at = archived_after(port, first, 1.3)
    time.sleep(2.5)
    second = [finish(port, "s2", "w2") for _ in range(2)]
    second_at = archived_after(port, second, 1.3)
    shelf = expect(request(port, "GET", "/archive"), 200, "GET /archive after both moves")
    check(shelf["archived"] == old_archived + 4, f"the archive holds the {old_archived} it had and the 4 just moved")
    server.stop()

    compacted = run(command, "compact", folder)
    check(compacted.returncode == 0, f"compact: {compacted.stdout.strip()}")
    names = sorted(os.listdir(folder))
    check("jobq.log" in names and "jobq.log.new" not in names and "jobq.archive.new" not in names,
          f"the compacted log is renamed into place, and no .new file is left: {names}")
    print("--  not placed: a kill between compact's rename and a sync of the folder (no Fs row syncs a folder)")
    check(run(command, "verify", folder).returncode == 0, "verify opens the compacted folder")

    server = Server(command, folder, "--retain-ms", "1000")
    port = server.port
    renamed = expect(request(port, "POST", "/queues/s1/rename", "op", {"to": "s3"}), 200, "rename s1 to s3")
    check(renamed == {"queue": "s3", "moved": 3}, f"the rename moved s1's 3 jobs, archived ones included: {renamed}")
    reused = make(port, "s1", "s1-k1")
    check(reused not in made.values(), "a create into the old name with a key its archived job used is a new job in a fresh queue")
    in_s3 = expect(request(port, "GET", f"/jobs?queue=s3&key=s1-k1"), 200, "the archived job's key is in s3")
    check([j["id"] for j in in_s3["jobs"]] == [made["s1-k1"]], "s3's s1-k1 is the first job")
    now = time.time()
    age = int(((now - first_at) + (now - second_at)) / 2 * 1000)
    check(age >= 1000, f"the prune's age, {age} ms, lies between the two archive times")
    cut = expect(request(port, "POST", "/archive/prune", "op", {"older_than_ms": age}), 200, "prune")
    server.kill()
    check(cut == {"pruned": old_archived + 2, "remaining": 2},
          f"the prune removed the first pair and the {old_archived} older, and kept the second pair: {cut}")
    log = open(os.path.join(folder, "jobq.log")).read()
    check(log.count("SET prune_") == 1 and log.endswith("\n"),
          "killed right after the 200, the log holds the prune as one whole record")

    result = run(command, "verify", folder)
    check(result.returncode == 0, f"verify opens the folder after the kill: {result.stdout.strip()}")
    check(result.stdout.strip().endswith("; archived 2"), "verify counts the archive with the prune applied")
    server = Server(command, folder, "--retain-ms", "1000")
    port = server.port
    for job in first:
        expect(request(port, "GET", f"/jobs/{job}"), 404, f"pruned {job} never comes back")
    for job in second:
        body = expect(request(port, "GET", f"/jobs/{job}"), 200, f"archived {job} is kept")
        check(body["queue"] == "s2" and "archived_at" in body, f"{job} is in s2, archived")
    freed = expect(request(port, "POST", "/jobs", "p", {"queue": "s3", "payload": "again", "max_tries": 2, "key": "s1-k1"}),
                   201, "a create with a freed key")
    check(freed["id"] not in made.values(), "the freed key makes a new job")
    used = expect(request(port, "POST", "/jobs", "p", {"queue": "s2", "payload": "again", "max_tries": 2, "key": "s2-k1"}),
                  200, "a create with a used key")
    check(used["id"] == made["s2-k1"], "the used key answers the first job")
    kept = expect(request(port, "POST", "/jobs", "p", {"queue": "s1", "payload": "x", "max_tries": 2, "key": "s1-k1"}),
                  200, "the old name's key still names its new job")
    check(kept["id"] == reused, "s1's s1-k1 is the job made after the rename")
    job = finish(port, "s3", "w3")
    check(job == made["s1-k3"], "the lease in s3 hands out the oldest queued job, s1-k3's")
    listed = expect(request(port, "GET", "/jobs?queue=s3"), 200, "list s3")
    check(sorted(j["id"] for j in listed["jobs"]) == sorted([made["s1-k3"], freed["id"]]), f"s3 lists its live jobs: {[j['id'] for j in listed['jobs']]}")
    queues = {q["name"]: q for q in expect(request(port, "GET", "/queues"), 200, "GET /queues")["queues"]}
    check(queues["s1"]["queued"] == 1 and queues["s2"]["queued"] == 1 and queues["s3"]["queued"] == 1 and queues["s3"]["done"] == 1,
          f"/queues: s1 {queues['s1']}, s2 {queues['s2']}, s3 {queues['s3']}")
    shelf = expect(request(port, "GET", "/archive"), 200, "GET /archive at the end")
    check(shelf["archived"] == 2 and shelf["oldest_archived_at"] is not None and shelf["bytes"] > 0, f"/archive: {shelf}")
    health = expect(request(port, "GET", "/health", None), 200, "health at the end")
    live = sum(health[k] for k in ("queued", "scheduled", "leased", "done", "dead"))
    before_live = sum(health0[k] for k in ("queued", "scheduled", "leased", "done", "dead"))
    check(health["archived"] == 2 and live == before_live + 6 - 4 + 2, f"/health: {health}")
    check(sum(q["queued"] + q["scheduled"] + q["leased"] + q["done"] + q["dead"] for q in queues.values()) == live,
          "/queues sums to /health")
    server.stop()
    check(run(command, "verify", folder).returncode == 0, "verify opens the folder at the end")


def fixture(old):
    """The change-5 folder, written by the change-5 program: data/change5."""
    target = os.path.join(HERE, "data", "change5")
    shutil.rmtree(target, ignore_errors=True)
    os.makedirs(target)
    server = Server(old, target, "--retain-ms", "1000")
    port = server.port
    for key in ("a1", "a2", "a3"):
        make(port, "old-a", key)
    for key in ("b1", "b2"):
        make(port, "old-b", key)
    finish(port, "old-a", "w")
    finish(port, "old-b", "w")
    archived_after(port, [], 1.3)
    expect(request(port, "POST", "/queues/old-a/rename", "op", {"to": "old-c"}), 200, "rename old-a to old-c")
    server.stop()
    check(run(old, "compact", target).returncode == 0, "the change-5 program compacts")
    server = Server(old, target)
    expect(request(server.port, "POST", "/queues/old-c/rename", "op", {"to": "old-d"}), 200, "rename old-c to old-d")
    make(server.port, "old-c", "c1")
    server.stop()
    refused = run(old, "verify", target)
    print(f"the change-5 program's verify on its own folder: exit {refused.returncode}: {refused.stderr.strip()}")


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(2)
    if args[0] == "--fixture":
        fixture(args[1:])
        return
    root = tempfile.mkdtemp(prefix="jobq-sequence-")
    started = time.monotonic()
    try:
        fresh = os.path.join(root, "fresh")
        os.mkdir(fresh)
        sequence(args, fresh, "a fresh folder")
        written = os.path.join(root, "change5")
        shutil.copytree(os.path.join(HERE, "data", "change5"), written)
        sequence(args, written, "a folder the change-5 program wrote")
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print(f"the sequence held on both folders in {time.monotonic() - started:.1f} s")


if __name__ == "__main__":
    main()

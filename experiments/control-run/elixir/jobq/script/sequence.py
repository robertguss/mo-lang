"""Change 6's sequence, with every step's expected answer, on a folder.

usage: sequence.py <jobq> <dir> fresh|change5

Create jobs with keys into two queues; lease and ack some; wait past
retain_ms so some archive; compact (killed once right after the log's rename,
before the directory's fsync); rename one queue; create into the old name;
prune with an age that removes some archived jobs and not others; stop with
kill -9; reopen; verify; create again with a freed key and with a used key;
lease, ack, list, /queues, /archive, /health; and compact again, killed after
each of its steps once.

`change5` is a copy of test/fixtures/change5/data, a folder the change-5
program wrote: three live jobs (j_2, j_3 in `eldest`, j_5 in `older`) and two
archived (j_1 in `eldest`, j_4 in `old`), with a rename record that has no
next_id. The sequence's own queues are `alpha`, `beta`, and `gamma`, so the
fixture shifts its ids and adds to its counts, and its archived jobs, archived
long before, are pruned with the sequence's.
"""

import http.client
import json
import os
import signal
import socket
import subprocess
import sys
import time
from datetime import datetime

JOBQ, DIR, LABEL = sys.argv[1], sys.argv[2], sys.argv[3]

BASE = {
    "fresh": {"first": 1, "archived": 0, "queued": 0, "rows": []},
    "change5": {
        "first": 6,
        "archived": 2,
        "queued": 3,
        "rows": [
            {"name": "eldest", "queued": 2, "scheduled": 0, "leased": 0, "done": 0, "dead": 0},
            {"name": "older", "queued": 1, "scheduled": 0, "leased": 0, "done": 0, "dead": 0},
        ],
    },
}[LABEL]


def jid(i):
    return f"j_{BASE['first'] + i - 1}"


def fail(step, message):
    print(f"sequence {LABEL}: {step}: {message}", file=sys.stderr)
    sys.exit(1)


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


PORT = free_port()
server = None


def request(method, path, body=None, token="t"):
    conn = http.client.HTTPConnection("127.0.0.1", PORT, timeout=30)
    headers = {"authorization": f"Bearer {token}"} if token else {}
    conn.request(method, path, body=json.dumps(body) if body is not None else None, headers=headers)
    response = conn.getresponse()
    raw = response.read()
    conn.close()
    return response.status, (json.loads(raw) if raw else None)


def expect(step, method, path, body=None, status=200, has=None, token="t"):
    got, answer = request(method, path, body, token)
    if got != status:
        fail(step, f"{method} {path}: expected {status}, got {got} {answer}")
    for field, value in (has or {}).items():
        if answer is None or answer.get(field) != value:
            fail(step, f"{method} {path}: expected {field}={value!r} in {answer}")
    return answer


def serve():
    global server
    server = subprocess.Popen(
        [JOBQ, "serve", DIR, "--port", str(PORT), "--retain-ms", "1000"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    deadline = time.time() + 20
    while time.time() < deadline:
        try:
            if request("GET", "/health", token=None)[0] == 200:
                return
        except OSError:
            time.sleep(0.05)
    fail("serve", "the service did not come up")


def stop(sig):
    global server
    server.send_signal(sig)
    server.wait(timeout=30)
    server = None


def command(step, argv, status=0, out=None, env=None):
    done = subprocess.run(
        [JOBQ] + argv,
        capture_output=True,
        text=True,
        timeout=120,
        env=dict(os.environ, **(env or {})),
    )
    if done.returncode != status:
        fail(step, f"jobq {' '.join(argv)}: expected exit {status}, got {done.returncode}: {done.stderr}")
    if out is not None and done.stdout.strip() != out:
        fail(step, f"jobq {' '.join(argv)}: expected {out!r}, got {done.stdout.strip()!r}")


def verify_line(live, next_i, archived):
    return (
        f"{live} jobs: queued {live}, scheduled 0, leased 0, done 0, dead 0; "
        f"next id {jid(next_i)}; archived {archived}"
    )


def job(queue, key=None, payload="p"):
    body = {"queue": queue, "payload": payload, "max_tries": 2}
    if key:
        body["key"] = key
    return body


def work(step, queue, want):
    expect(step, "POST", f"/queues/{queue}/lease", {"lease_ms": 60000}, has={"id": want}, token="w")
    expect(step, "POST", f"/jobs/{want}/ack", has={"state": "done"}, token="w")


def main():
    fa, fq = BASE["archived"], BASE["queued"]

    # One: jobs with keys into two queues; some leased and acked; archived.
    serve()
    expect("1", "POST", "/jobs", job("alpha", "ka1"), 201, {"id": jid(1)})
    expect("1", "POST", "/jobs", job("alpha", "ka2"), 201, {"id": jid(2)})
    expect("1", "POST", "/jobs", job("alpha", "ka3"), 201, {"id": jid(3)})
    expect("1", "POST", "/jobs", job("beta", "kb1"), 201, {"id": jid(4)})
    expect("1", "POST", "/jobs", job("beta"), 201, {"id": jid(5)})
    expect("1", "POST", "/jobs", job("alpha", "ka1"), 200, {"id": jid(1)})
    work("1", "alpha", jid(1))
    work("1", "beta", jid(4))
    time.sleep(1.5)
    expect("1", "GET", "/health", has={"archived": 2 + fa, "done": 0, "queued": 3 + fq}, token=None)
    expect("1", "GET", "/archive", has={"archived": 2 + fa})
    stop(signal.SIGTERM)

    # Two: compact, killed once after the log's rename and before the
    # directory's fsync; the folder opens the same either way.
    line = verify_line(3 + fq, 6, 2 + fa)
    command("2", ["verify", DIR], out=line)
    command("2", ["compact", DIR], status=137, env={"JOBQ_COMPACT_STOP_AT": "log"})
    command("2", ["verify", DIR], out=line)
    command("2", ["compact", DIR])
    command("2", ["verify", DIR], out=line)

    # Three: rename a queue; its old name is a fresh queue.
    serve()
    expect("3", "POST", "/queues/alpha/rename", {"to": "gamma"}, has={"queue": "gamma", "moved": 3})
    expect("3", "POST", "/jobs", job("alpha", "ka1"), 201, {"id": jid(6), "queue": "alpha"})
    expect("3", "POST", "/jobs", job("gamma", "ka1"), 200, {"id": jid(1), "queue": "gamma"})
    work("3", "alpha", jid(6))
    work("3", "gamma", jid(2))
    time.sleep(1.5)
    expect("3", "GET", "/health", has={"archived": 4 + fa}, token=None)
    first = expect("3", "GET", f"/jobs/{jid(1)}", has={"queue": "gamma"})
    later = expect("3", "GET", f"/jobs/{jid(6)}", has={"queue": "alpha"})
    expect("3", "GET", f"/jobs/{jid(2)}", has={"queue": "gamma"})

    # Four: a prune whose age falls between the two archive moves.
    def ms(iso):
        return round(datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp() * 1000)

    t1, t2 = ms(first["archived_at"]), ms(later["archived_at"])
    if t2 - t1 < 2000:
        fail("4", f"the two moves are too close to split: {t2 - t1} ms")
    age = max(1000, int(time.time() * 1000) - (t1 + t2) // 2)
    expect("4", "POST", "/archive/prune", {"older_than_ms": age}, has={"pruned": 2 + fa, "remaining": 2})
    expect("4", "GET", f"/jobs/{jid(1)}", status=404)
    expect("4", "GET", f"/jobs/{jid(4)}", status=404)
    expect("4", "GET", f"/jobs/{jid(6)}", has={"queue": "alpha"})
    expect("4", "GET", "/archive", has={"archived": 2})
    expect("4", "GET", "/health", has={"archived": 2}, token=None)
    stop(signal.SIGKILL)

    # Five: reopen and verify.
    command("5", ["verify", DIR], out=verify_line(2 + fq, 7, 2))
    serve()

    # Six: freed keys make new jobs; used keys answer their jobs.
    expect("6", "POST", "/jobs", job("gamma", "ka1"), 201, {"id": jid(7)})
    expect("6", "POST", "/jobs", job("beta", "kb1"), 201, {"id": jid(8)})
    expect("6", "POST", "/jobs", job("gamma", "ka2"), 200, {"id": jid(2)})
    expect("6", "POST", "/jobs", job("alpha", "ka1"), 200, {"id": jid(6)})
    expect("6", "POST", "/jobs", job("gamma", "ka3"), 200, {"id": jid(3)})
    if LABEL == "change5":
        # The fixture's archived jobs were pruned too, and their keys freed.
        expect("6", "POST", "/jobs", job("eldest", "k1"), 201, {"id": jid(9)})
        expect("6", "POST", "/jobs", job("eldest", "k2"), 200, {"id": "j_2"})
        expect("6", "POST", "/jobs", job("older", "k2"), 200, {"id": "j_5"})
        expect("6", "DELETE", f"/jobs/{jid(9)}", status=204)

    # Seven: lease, ack, list, /queues, /archive, /health.
    work("7", "gamma", jid(3))
    listed = expect("7", "GET", "/jobs?queue=gamma")
    if [j["id"] for j in listed["jobs"]] != [jid(3), jid(7)]:
        fail("7", f"gamma lists {listed}")
    rows = expect("7", "GET", "/queues")["queues"]
    want = sorted(
        BASE["rows"]
        + [
            {"name": "beta", "queued": 2, "scheduled": 0, "leased": 0, "done": 0, "dead": 0},
            {"name": "gamma", "queued": 1, "scheduled": 0, "leased": 0, "done": 1, "dead": 0},
        ],
        key=lambda row: row["name"],
    )
    if rows != want:
        fail("7", f"/queues: expected {want}, got {rows}")
    expect("7", "GET", "/archive", has={"archived": 2})
    expect("7", "GET", "/health", has={"queued": 3 + fq, "done": 1, "archived": 2}, token=None)
    stop(signal.SIGTERM)

    # Eight: a compaction killed after each step leaves the same folder.
    line = f"{4 + fq} jobs: queued {3 + fq}, scheduled 0, leased 0, done 1, dead 0; next id {jid(9 if LABEL == 'fresh' else 10)}; archived 2"
    command("8", ["verify", DIR], out=line)
    for step in ["tombstones", "log", "archive"]:
        command("8", ["compact", DIR], status=137, env={"JOBQ_COMPACT_STOP_AT": step})
        command("8", ["verify", DIR], out=line)
    command("8", ["compact", DIR])
    command("8", ["verify", DIR], out=line)
    with open(os.path.join(DIR, "jobq.log")) as log:
        text = log.read()
    if '"rename"' in text or '"prune"' in text:
        fail("8", "compaction left a rename or a prune record")

    print(f"sequence {LABEL}: ok")


try:
    main()
finally:
    if server is not None:
        server.kill()
        server.wait()

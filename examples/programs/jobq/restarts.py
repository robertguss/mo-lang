"""jobq's restarts end to end, over a real socket (change 3).

Run from examples/programs/jobq with the command that runs jobq:

    python3 restarts.py mo run main.mo --
    python3 restarts.py zig-out/mo-build/jobq/jobq

A process test cannot hold its asserts past a crash (queue.mo, server.mo), so the restart itself is
held here: the chaos switch fails the queue under load and every answer is 2xx, 4xx, or 503, /health
answers 200 within a second of each failure, every job a 2xx answer reported is on the board after
the restarts and again after serve is stopped and started; failures faster than the budget allows
end the service with exit 70 and a folder verify opens; and failures further apart than the window
start a fresh count. Change 4 adds the archive under kills: with a small --retain-ms, serve is killed
at random under a load of short-lived keyed jobs, and after each start no acked job is lost, none is
counted twice, a retried create with a used key is 200 with the first job, and verify opens the
folder. Change 5 adds renames and handoffs under kills: serve is killed at random while workers make
keyed jobs, lease them, hand them to each other, and ack them, and an operator renames the busy queue
to a fresh name again and again; after the kills every job is in exactly one queue, the first rename
after it that took place, every key names its job once in that queue, every acknowledged write is
there, and no job is held by two workers or by any but the last worker it was handed to. Every
server is killed past 300 seconds or 4 GB.
"""

import http.client
import json
import os
import random
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time

COMMAND = sys.argv[1:]
LIMIT_BYTES = 4 * 1024 * 1024 * 1024


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Server:
    def __init__(self, folder, *flags):
        self.port = free_port()
        args = COMMAND + ["serve", folder, "--port", str(self.port), *flags]
        self.proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.started = time.monotonic()
        self.stderr = []
        threading.Thread(target=self._drain, daemon=True).start()
        threading.Thread(target=self._guard, daemon=True).start()
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if self.proc.poll() is not None:
                raise AssertionError(f"serve exited {self.proc.returncode}: {''.join(self.stderr)}")
            if request(self.port, "GET", "/health")[0] == 200:
                return
            time.sleep(0.05)
        raise AssertionError("serve did not answer within 60 seconds")

    def _drain(self):
        for line in self.proc.stderr:
            self.stderr.append(line)

    def _guard(self):
        while self.proc.poll() is None:
            rss = 0
            ps = subprocess.run(["ps", "-o", "rss=", "-p", str(self.proc.pid)], capture_output=True, text=True)
            if ps.stdout.strip():
                rss = int(ps.stdout.strip()) * 1024
            if rss > LIMIT_BYTES or time.monotonic() - self.started > 300:
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


def request(port, method, path, token=None, body=None):
    """The status and the JSON body, or (0, None) when the connection failed."""
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


def verify(folder):
    return subprocess.run(COMMAND + ["verify", folder], capture_output=True, text=True, timeout=300)


def check(condition, what):
    if not condition:
        raise AssertionError(what)
    print(f"ok  {what}")


def load(port, rounds, made, acked, statuses):
    for i in range(rounds):
        status, body = request(port, "POST", "/jobs", "p", {"queue": "q", "payload": f"job {i}", "max_tries": 3})
        statuses.append(status)
        if status == 201:
            made.append(body["id"])
        worker = f"w{i % 3}"
        status, body = request(port, "POST", "/queues/q/lease", worker, {"lease_ms": 3600000})
        statuses.append(status)
        if status == 200:
            status, done = request(port, "POST", f"/jobs/{body['id']}/ack", worker)
            statuses.append(status)
            if status == 200:
                acked.append(done["id"])


def poll_health(port, stop, seen):
    while not stop.is_set():
        status, body = request(port, "GET", "/health")
        seen.append((time.monotonic(), status, body))
        time.sleep(0.02)


def longest_outage(seen):
    """The longest time /health went without a 200, from its first other answer to the next 200."""
    longest, since = 0.0, None
    for at, status, _ in seen:
        if status != 200 and since is None:
            since = at
        if status == 200 and since is not None:
            longest = max(longest, at - since)
            since = None
    return longest


def board_holds(port, made, acked):
    for job in made:
        status, body = request(port, "GET", f"/jobs/{job}", "p")
        if status != 200:
            return f"{job} answered {status}"
        if job in acked and body["state"] != "done":
            return f"{job} was acked but is {body['state']}"
    return None


def restart_under_load(root):
    folder = os.path.join(root, "load")
    os.mkdir(folder)
    server = Server(folder, "--crash-every", "7", "--max-restarts", "1000", "--restart-window", "60")
    made, acked, statuses, seen = [], [], [], []
    stop = threading.Event()
    poller = threading.Thread(target=poll_health, args=(server.port, stop, seen))
    poller.start()
    workers = [threading.Thread(target=load, args=(server.port, 60, made, acked, statuses)) for _ in range(4)]
    for w in workers:
        w.start()
    for w in workers:
        w.join()
    time.sleep(0.3)
    stop.set()
    poller.join()
    check(server.proc.poll() is None, "with a budget of 1000 the service is still serving after the load")
    check(set(statuses) <= {200, 201, 204, 404, 409, 503, 0},
          f"every answer under the chaos switch is 2xx, 4xx, 503, or a closed connection: {sorted(set(statuses))}")
    check(503 in statuses or 0 in statuses, "the chaos switch failed some requests")
    health = request(server.port, "GET", "/health")
    check(health[0] == 200 and health[1]["restarts"] >= 1, f"/health counts the restarts: {health[1]}")
    counts = [body["restarts"] for _, status, body in seen if status == 200]
    check(counts == sorted(counts), "/health's restarts never goes down")
    check(longest_outage(seen) <= 1.0, f"/health answered 200 within a second of each failure (longest {longest_outage(seen):.3f} s)")
    check(len(made) > 0 and board_holds(server.port, made, acked) is None,
          f"every one of {len(made)} jobs answered 201 and {len(acked)} acks answered 200 are on the board after the restarts")
    ids = [int(j[2:]) for j in made]
    check(len(ids) == len(set(ids)), "no job number was handed out twice")
    server.stop()
    check(verify(folder).returncode == 0, "verify opens the folder after the service is stopped")
    again = Server(folder)
    check(board_holds(again.port, made, acked) is None, "every acknowledged write is on the board after serve is stopped and started")
    status, body = request(again.port, "POST", "/jobs", "p", {"queue": "q", "payload": "after", "max_tries": 1})
    check(status == 201 and int(body["id"][2:]) not in ids, "ids go on after the restarts and the stop")
    check(request(again.port, "GET", "/health")[1]["restarts"] == 0, "a stopped and started service counts from 0")
    again.stop()


def budget_spent(root):
    folder = os.path.join(root, "budget")
    os.mkdir(folder)
    server = Server(folder, "--crash-every", "1", "--max-restarts", "2", "--restart-window", "60")
    made = []
    answers = []
    deadline = time.monotonic() + 60
    while server.proc.poll() is None and time.monotonic() < deadline:
        status, body = request(server.port, "POST", "/jobs", "p", {"queue": "q", "payload": "x", "max_tries": 1})
        answers.append(status)
        if status == 201:
            made.append(body["id"])
        time.sleep(0.05)
    try:
        code = server.proc.wait(10)
    except subprocess.TimeoutExpired:
        server.stop()
        code = None
    check(code == 70, f"failures faster than the budget allows end the service with exit 70 (got {code})")
    check(answers.count(201) == 0, "with the switch at every write, no create is answered 201")
    log = open(os.path.join(folder, "jobq.log")).read()
    written = log.count("\nSET j_") + log.startswith("SET j_")
    check(written == 3, f"the service wrote nothing after its third failure: {written} jobs in the log")
    result = verify(folder)
    check(result.returncode == 0, f"verify opens the folder the service left: {result.stdout.strip()}")
    again = Server(folder)
    status, body = request(again.port, "GET", "/jobs", "p")
    check(status == 200 and len(body["jobs"]) == 3, "the folder serves again, with the three writes on disk before the failures")
    again.stop()


def replayed(path):
    """The keys a jobq log or archive holds, replayed as the store does, a torn last line left out."""
    held = {}
    if not os.path.exists(path):
        return held
    text = open(path).read()
    lines = text.split("\n")
    for line in lines[:-1]:
        if line.startswith("SET "):
            key, _, value = line[4:].partition(" ")
            held[key] = value
        elif line.startswith("DEL "):
            held.pop(line[4:], None)
    return held


def short_lived(port, stop, acked, keys, statuses):
    i = 0
    while not stop.is_set():
        key = f"k{threading.get_ident() % 1000}-{i}"
        i += 1
        status, body = request(port, "POST", "/jobs", "p", {"queue": "q", "payload": key, "max_tries": 1, "key": key})
        statuses.append(status)
        if status == 201:
            keys[key] = body["id"]
        status, body = request(port, "POST", "/queues/q/lease", "w", {"lease_ms": 3600000})
        statuses.append(status)
        if status == 200:
            status, done = request(port, "POST", f"/jobs/{body['id']}/ack", "w")
            statuses.append(status)
            if status == 200:
                acked.add(done["id"])


def archive_under_kills(root):
    folder = os.path.join(root, "archive")
    os.mkdir(folder)
    acked, keys, statuses = set(), {}, []
    rng = random.Random(4)
    for round_ in range(6):
        server = Server(folder, "--retain-ms", "1000")
        stop = threading.Event()
        workers = [threading.Thread(target=short_lived, args=(server.port, stop, acked, keys, statuses)) for _ in range(3)]
        for w in workers:
            w.start()
        time.sleep(1.2 + rng.random() * 1.5)
        server.proc.kill()
        server.proc.wait()
        stop.set()
        for w in workers:
            w.join()
        result = verify(folder)
        check(result.returncode == 0, f"kill {round_ + 1}: verify opens the folder: {result.stdout.strip()} {result.stderr.strip()}")
    live = {k for k, v in replayed(os.path.join(folder, "jobq.log")).items() if k.startswith("j_")}
    shelf = {k for k, v in replayed(os.path.join(folder, "jobq.archive")).items() if v != "deleted"}
    check(len(shelf) > 0, f"the kills left {len(shelf)} jobs in the archive and {len(live)} in the log")
    server = Server(folder, "--retain-ms", "1000")
    status, health = request(server.port, "GET", "/health")
    check(status == 200, f"/health answers after the kills: {health}")
    missing = [j for j in acked if request(server.port, "GET", f"/jobs/{j}", "p")[0] != 200]
    check(not missing, f"every one of {len(acked)} acked jobs reads by id after the kills: missing {missing[:5]}")
    listed = request(server.port, "GET", "/jobs?state=done", "p")[1]["jobs"]
    both = [j["id"] for j in listed if j["id"] in shelf]
    check(not both, f"no job listed on the board is in the archive after an open: {both[:5]}")
    ended = health["done"] + health["archived"] + health["queued"] + health["leased"]
    everything = live | shelf
    check(ended == len(everything),
          f"each job is counted once: /health's {ended} against {len(everything)} ids across both files, {len(live & shelf)} in both")
    check(health["archived"] >= len(shelf),
          f"/health's archived {health['archived']} holds the archive's {len(shelf)} jobs, and any the first look moved since")
    retried = []
    for key, job in list(keys.items())[:50]:
        status, body = request(server.port, "POST", "/jobs", "p", {"queue": "q", "payload": "again", "max_tries": 1, "key": key})
        if status != 200 or body["id"] != job:
            retried.append((key, status))
    check(not retried, f"a create with a used key answers the first job after the kills: {retried[:5]}")
    time.sleep(1.2)
    status, later = request(server.port, "GET", "/health")
    check(status == 200 and later["done"] == 0 and later["archived"] == len(everything) - later["queued"] - later["leased"],
          f"a look after the retention archives every done job: {later}")
    server.stop()
    check(set(statuses) <= {200, 201, 204, 409, 503, 0}, f"every answer under the kills is expected: {sorted(set(statuses))}")


def handing_worker(port, stop, me, other, log, lock, statuses):
    i = 0
    while not stop.is_set():
        key = f"{me}-{i}"
        i += 1
        sent = time.monotonic()
        status, body = request(port, "POST", "/jobs", "p", {"queue": "q", "payload": key, "max_tries": 3, "key": key})
        statuses.append(status)
        if status == 201:
            with lock:
                log["made"][body["id"]] = (key, sent, time.monotonic())
        status, body = request(port, "POST", "/queues/q/lease", me, {"lease_ms": 3600000})
        statuses.append(status)
        if status != 200:
            continue
        job = body["id"]
        holder = me
        if i % 2 == 0:
            status, body = request(port, "POST", f"/jobs/{job}/handoff", me, {"to": other})
            statuses.append(status)
            if status == 200:
                if body["worker"] != other:
                    with lock:
                        log["wrong"].append((job, "handed to", other, "names", body["worker"]))
                holder = other
                with lock:
                    log["holder"][job] = other
                late = request(port, "POST", f"/jobs/{job}/ack", me)[0]
                statuses.append(late)
                if late not in (409, 503, 0):
                    with lock:
                        log["wrong"].append((job, "old worker's ack", late))
            elif status in (503, 0):
                continue
        if i % 3 == 0:
            with lock:
                log["holder"].setdefault(job, holder)
            continue
        status, body = request(port, "POST", f"/jobs/{job}/ack", holder)
        statuses.append(status)
        if status == 200:
            with lock:
                log["acked"].add(job)


def renamer(port, stop, log, lock, statuses, rng):
    n = 0
    while not stop.is_set():
        time.sleep(0.05 + rng.random() * 0.15)
        n += 1
        name = f"r{len(log['renames'])}-{n}"
        sent = time.monotonic()
        status, body = request(port, "POST", "/queues/q/rename", "op", {"to": name})
        statuses.append(status)
        with lock:
            log["renames"].append((sent, time.monotonic(), name, status))
        if status == 200 and body["queue"] != name:
            with lock:
                log["wrong"].append(("rename", name, body))


def rename_under_kills(root):
    folder = os.path.join(root, "rename")
    os.mkdir(folder)
    log = {"made": {}, "acked": set(), "holder": {}, "renames": [], "wrong": []}
    lock = threading.Lock()
    statuses = []
    rng = random.Random(5)
    for round_ in range(5):
        server = Server(folder)
        stop = threading.Event()
        threads = [threading.Thread(target=handing_worker, args=(server.port, stop, f"w{k}", f"w{(k + 1) % 3}", log, lock, statuses)) for k in range(3)]
        threads.append(threading.Thread(target=renamer, args=(server.port, stop, log, lock, statuses, rng)))
        for t in threads:
            t.start()
        time.sleep(1.0 + rng.random() * 1.5)
        server.proc.kill()
        server.proc.wait()
        stop.set()
        for t in threads:
            t.join()
        result = verify(folder)
        check(result.returncode == 0, f"rename kill {round_ + 1}: verify opens the folder: {result.stdout.strip()} {result.stderr.strip()}")
    check(not log["wrong"], f"no old worker acked a job it handed off, and every rename answered its name: {log['wrong'][:5]}")
    done_renames = [r for r in log["renames"] if r[3] == 200]
    check(len(done_renames) >= 3 and len(log["made"]) > 0,
          f"the kills came among {len(done_renames)} renames answered 200 of {len(log['renames'])}, {len(log['made'])} creates, {len(log['acked'])} acks")
    server = Server(folder)
    port = server.port
    wrong = []
    queues = {}
    for job, (key, made_sent, made_at) in log["made"].items():
        status, body = request(port, "GET", f"/jobs/{job}", "p")
        if status != 200:
            wrong.append((job, "not found", status))
            continue
        queue = body["queue"]
        queues[job] = queue
        # A rename answered before the create was sent came before it; one sent after the create was
        # answered came after it; the renamer sends one at a time, so the rest are in order between.
        later = [r for r in log["renames"] if r[1] >= made_sent]
        first_done = next((i for i, r in enumerate(later) if r[3] == 200 and r[0] > made_at), None)
        allowed = {r[2] for r in (later if first_done is None else later[: first_done + 1])}
        if first_done is None:
            allowed.add("q")
        if queue not in allowed:
            wrong.append((job, "in", queue, "not one of", sorted(allowed)[:4]))
        status, found = request(port, "GET", f"/jobs?queue={queue}&key={key}", "p")
        if status != 200 or [j["id"] for j in found["jobs"]] != [job]:
            wrong.append((job, "key", key, "in", queue, status, found))
        if job in log["acked"] and body["state"] != "done":
            wrong.append((job, "acked but", body["state"]))
        if body["state"] == "leased" and job in log["holder"] and body["worker"] != log["holder"][job]:
            wrong.append((job, "held by", body["worker"], "not", log["holder"][job]))
    check(not wrong, f"each of {len(log['made'])} jobs is in one queue, the first rename after it that took place, its key names it there, acks and handoffs held: {wrong[:5]}")
    by_queue = {}
    for job, queue in queues.items():
        by_queue.setdefault(queue, []).append(job)
    status, listed = request(port, "GET", "/queues", "p")
    status_h, health = request(port, "GET", "/health")
    total = sum(q["queued"] + q["scheduled"] + q["leased"] + q["done"] + q["dead"] for q in listed["queues"])
    live = health["queued"] + health["scheduled"] + health["leased"] + health["done"] + health["dead"]
    check(status == 200 and total == live, f"/queues' {len(listed['queues'])} queues hold {total} jobs, /health's total {live}")
    names = [q["name"] for q in listed["queues"]]
    check(len(names) == len(set(names)) and all(name in names for name in by_queue),
          "every queue a job is in is listed once")
    leased = request(port, "GET", "/jobs?state=leased", "p")[1]["jobs"]
    check(all(isinstance(j.get("worker"), str) for j in leased), f"each of {len(leased)} leased jobs names one worker")
    request(port, "POST", "/jobs", "p", {"queue": "q", "payload": "last", "max_tries": 1})
    moved = request(port, "POST", "/queues/q/rename", "op", {"to": "final"})
    back = request(port, "POST", "/queues/final/rename", "op", {"to": "q"})
    check(moved[0] == 200 and back[0] == 200 and back[1]["moved"] == moved[1]["moved"],
          f"a rename is undone by a rename after the kills: {moved} {back}")
    server.stop()
    check(verify(folder).returncode == 0, "verify opens the folder after the renames")
    before = open(os.path.join(folder, "jobq.log")).read().count("SET rename_")
    compacted = subprocess.run(COMMAND + ["compact", folder], capture_output=True, text=True, timeout=300)
    after = open(os.path.join(folder, "jobq.log")).read().count("SET rename_")
    check(compacted.returncode == 0 and after == 0, f"compact folds all {before} rename records away: {compacted.stdout.strip()}")
    again = Server(folder)
    still = [job for job, queue in queues.items() if request(again.port, "GET", f"/jobs/{job}", "p")[1]["queue"] != queue]
    check(not still, f"every job is in the same queue after compact: {still[:5]}")
    again.stop()
    check(set(statuses) <= {200, 201, 204, 404, 409, 503, 0}, f"every answer under the kills is expected: {sorted(set(statuses))}")


def window_passes(root):
    folder = os.path.join(root, "window")
    os.mkdir(folder)
    server = Server(folder, "--crash-every", "1", "--max-restarts", "1", "--restart-window", "1")
    for i in range(3):
        request(server.port, "POST", "/jobs", "p", {"queue": "q", "payload": f"spaced {i}", "max_tries": 1})
        deadline = time.monotonic() + 1.5
        while time.monotonic() < deadline:
            time.sleep(0.1)
        check(server.proc.poll() is None, f"failure {i + 1}, more than the window after the last, starts a fresh count")
    health = request(server.port, "GET", "/health")
    check(health[0] == 200 and health[1]["restarts"] == 3, f"/health counts all three restarts: {health[1]}")
    request(server.port, "POST", "/jobs", "p", {"queue": "q", "payload": "fast 1", "max_tries": 1})
    time.sleep(0.2)
    request(server.port, "POST", "/jobs", "p", {"queue": "q", "payload": "fast 2", "max_tries": 1})
    try:
        code = server.proc.wait(10)
    except subprocess.TimeoutExpired:
        server.stop()
        code = None
    check(code == 70, f"a second failure inside the window with a budget of 1 ends the service with exit 70 (got {code})")
    check(verify(folder).returncode == 0, "verify opens that folder too")


def main():
    if not COMMAND:
        print(__doc__)
        sys.exit(2)
    root = tempfile.mkdtemp(prefix="jobq-restarts-")
    started = time.monotonic()
    try:
        restart_under_load(root)
        budget_spent(root)
        window_passes(root)
        archive_under_kills(root)
        rename_under_kills(root)
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print(f"all restarts checks held in {time.monotonic() - started:.1f} s")


if __name__ == "__main__":
    main()

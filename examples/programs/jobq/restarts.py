"""jobq's restarts end to end, over a real socket (change 3).

Run from examples/programs/jobq with the command that runs jobq:

    python3 restarts.py mo run main.mo --
    python3 restarts.py zig-out/mo-build/jobq/jobq

A process test cannot hold its asserts past a crash (queue.mo, server.mo), so the restart itself is
held here: the chaos switch fails the queue under load and every answer is 2xx, 4xx, or 503, /health
answers 200 within a second of each failure, every job a 2xx answer reported is on the board after
the restarts and again after serve is stopped and started; failures faster than the budget allows
end the service with exit 70 and a folder verify opens; and failures further apart than the window
start a fresh count. Every server is killed past 300 seconds or 4 GB.
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
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print(f"all restarts checks held in {time.monotonic() - started:.1f} s")


if __name__ == "__main__":
    main()

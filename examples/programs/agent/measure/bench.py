#!/usr/bin/env python3
"""Load for agent's measurements.

rate PORT CONC SECS TOOLS  -- CONC threads, each makes a run and polls it to its end, again and
                              again for SECS; prints runs completed a second, and the harness's
                              own time per step from a sample of transcripts.
hold PORT N BODY_BUDGET    -- makes N runs as fast as 32 threads can, and prints when all are made.
view PORT PATH             -- one GET, printed.
"""
import json, sys, threading, time, urllib.request, urllib.error
from datetime import datetime


def call(method, url, body=None, token="bench"):
    data = body.encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method,
                                     headers={"authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def when(text):
    return datetime.fromisoformat(text.replace("Z", "+00:00")).timestamp()


def rate(port, conc, secs, tools):
    base = f"http://127.0.0.1:{port}"
    order = json.dumps({"goal": "five steps", "folder": "work", "tools": tools.split(",")})
    done, failed, ids = [], [], []
    lock = threading.Lock()
    stop_at = time.time() + secs

    def worker():
        while time.time() < stop_at:
            status, body = call("POST", base + "/runs", order)
            if status != 201:
                with lock:
                    failed.append(status)
                continue
            rid = json.loads(body)["id"]
            while True:
                status, body = call("GET", f"{base}/runs/{rid}")
                run = json.loads(body)
                if run["state"] != "running":
                    break
                time.sleep(0.002)
            with lock:
                (done if run["state"] == "done" else failed).append(run["state"])
                ids.append(rid)

    started = time.time()
    threads = [threading.Thread(target=worker) for _ in range(conc)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    elapsed = time.time() - started
    harness, model, tool, turns = [], [], [], 0
    for rid in ids[-200:]:
        _, body = call("GET", f"{base}/runs/{rid}")
        run = json.loads(body)
        _, steps_body = call("GET", f"{base}/runs/{rid}/transcript")
        steps = json.loads(steps_body)["steps"]
        took = sum(s["took_ms"] for s in steps)
        span = (when(run["updated_at"]) - when(run["created_at"])) * 1000
        n = run["steps_taken"]
        turns += n
        harness.append((span - took) / n)
        model.append(sum(s["took_ms"] for s in steps if s["kind"] == "model") / n)
        tool.append(sum(s["took_ms"] for s in steps if s["kind"] == "tool") / max(1, n - 1))
    avg = lambda xs: sum(xs) / len(xs) if xs else 0
    print(json.dumps({"runs_done": len(done), "not_done": len(failed), "seconds": round(elapsed, 2),
                      "runs_per_second": round(len(done) / elapsed, 1),
                      "harness_ms_per_step": round(avg(harness), 2),
                      "model_ms_per_call": round(avg(model), 2), "tool_ms_per_call": round(avg(tool), 2),
                      "sampled_runs": len(harness), "not_done_states": sorted(set(map(str, failed)))}))


def hold(port, n, budget):
    base = f"http://127.0.0.1:{port}"
    order = json.dumps({"goal": "held", "folder": "work", "tools": ["now"], "budget": json.loads(budget)})
    made = []
    lock = threading.Lock()
    todo = list(range(n))

    def worker():
        while True:
            with lock:
                if not todo:
                    return
                todo.pop()
            status, body = call("POST", base + "/runs", order)
            with lock:
                made.append(status)

    started = time.time()
    threads = [threading.Thread(target=worker) for _ in range(32)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    print(json.dumps({"made": made.count(201), "other": sorted(set(made) - {201}),
                      "seconds": round(time.time() - started, 2)}))


def view(port, path):
    status, body = call("GET", f"http://127.0.0.1:{port}{path}")
    print(status, body[:4000])


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "rate":
        rate(int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4]), sys.argv[5])
    elif mode == "hold":
        hold(int(sys.argv[2]), int(sys.argv[3]), sys.argv[4])
    else:
        view(int(sys.argv[2]), sys.argv[3])

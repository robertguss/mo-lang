#!/usr/bin/env python3
"""guard_test.py: step 42's check of bench/step36/guard.py (part E).

The child under the guard is a shell that starts a grandchild ignoring TERM, writes the
grandchild's pid to a file, and sleeps. Three cases, each of which must leave no survivor:
  timeout  the guard's own limit passes (it kills);
  term     the guard is sent TERM, which it forwards;
  int      the guard is sent INT, which it forwards.
Each case checks the guard's exit status (137 for its kill, 143 for TERM, 130 for INT, as
before the change), and that both the child and the grandchild are gone within 10 s.
Exit 0 when every case holds, 1 otherwise; one line per case on stdout.
"""
import os, signal, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.join(HERE, "..", "step36", "guard.py")

CHILD = r"""
trap '' TERM
( trap '' TERM INT; exec sleep 300 ) </dev/null >/dev/null 2>&1 &
echo $! > "$1"
echo $$ > "$2"
trap - TERM
sleep 300
"""


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    # A zombie still answers kill 0: ask ps for its state.
    state = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    return bool(state) and not state.startswith("Z")


def read_pid(path, within=10.0):
    t0 = time.time()
    while time.time() - t0 < within:
        try:
            text = open(path).read().strip()
            if text:
                return int(text)
        except FileNotFoundError:
            pass
        time.sleep(0.05)
    raise RuntimeError(f"no pid in {path}")


def case(name, limit, send, want):
    folder = tempfile.mkdtemp(prefix="guard-test-")
    grand_file = os.path.join(folder, "grandchild")
    child_file = os.path.join(folder, "child")
    # The guard's stderr goes to a file: a pipe would stay open while a survivor holds it.
    err_path = os.path.join(folder, "stderr")
    with open(err_path, "w") as err_file:
        g = subprocess.Popen([sys.executable, GUARD, str(limit), "--", "/bin/sh", "-c", CHILD, "sh", grand_file, child_file], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=err_file)
    grand = read_pid(grand_file)
    child = read_pid(child_file)
    if send is not None:
        time.sleep(0.5)
        g.send_signal(send)
    try:
        rc = g.wait(timeout=limit + 30)
    except subprocess.TimeoutExpired:
        g.kill()
        rc = "hung"
    err = open(err_path).read().strip()
    t0 = time.time()
    while time.time() - t0 < 10 and (alive(grand) or alive(child)):
        time.sleep(0.1)
    left = [p for p in (child, grand) if alive(p)]
    for p in left:
        try:
            os.kill(p, signal.SIGKILL)
        except ProcessLookupError:
            pass
    ok = rc == want and not left
    print(f"{name}: guard exit {rc} (want {want}); child {child} {'alive' if child in left else 'gone'}; grandchild {grand} {'alive' if grand in left else 'gone'}; stderr {err!r}: {'ok' if ok else 'FAIL'}")
    return ok


def main():
    results = [
        case("timeout", 2, None, 137),
        case("term", 60, signal.SIGTERM, 143),
        case("int", 60, signal.SIGINT, 130),
    ]
    print("guard_test: " + ("all held" if all(results) else "FAILED"))
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()

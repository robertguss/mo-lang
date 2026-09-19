#!/usr/bin/env python3
"""Step 40's file numbers: each Fs row step 40 changed, timed under `mo run` and as a `mo build`
binary, for two `mo` executables (before and after), best of five, load average beside each row.

    python3 measure.py OUT_DIR NAME=MO_EXE [NAME=MO_EXE ...]

Every mo, build and binary runs under bench/step36/guard.py with a timeout. Each row is timed as a
whole process; the same process with no calls (`none`) is subtracted, so a row's number is the cost
of its calls alone. `deep` reads a file sixteen folders down and `read` one in the scope's folder,
so (deep - read) / 16 is what one more path component costs a call. Runs of the executables are
interleaved, one of each in turn, so a change in the machine's load falls on both.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.join(HERE, "..", "step36", "guard.py")
PROGRAM = os.path.join(HERE, "files.mo")
REPS = 5
# mode, calls: enough calls that a row takes well over the process's own start.
ROWS = [("none", 0), ("read", 2000), ("deep", 2000), ("size", 2000), ("write", 300), ("append", 300),
        ("fold", 1), ("list", 30), ("list_kinds", 30)]
BIG_LINES = 200_000
MANY = 10_000


def tree(root):
    """The tree every run reads: made once, before the first run; write and append change only
    out.txt and log.txt, which every run of theirs rewrites or grows the same way."""
    work = os.path.join(root, "work")
    deep = os.path.join(work, *(["d"] * 16))
    os.makedirs(deep, exist_ok=True)
    os.makedirs(os.path.join(work, "many"), exist_ok=True)
    line = "2026-09-19T10:00:00Z info a line of a large log, sixty bytes\n"
    for p in (os.path.join(work, "small.txt"), os.path.join(deep, "small.txt")):
        with open(p, "w") as f:
            f.write("a small file\n" * 8)
    with open(os.path.join(work, "big.txt"), "w") as f:
        f.write(line * BIG_LINES)
    for i in range(MANY):
        with open(os.path.join(work, "many", f"f{i:05d}.txt"), "w") as f:
            f.write("x")


def guarded(seconds, argv, cwd):
    t0 = time.perf_counter()
    ran = subprocess.run(["python3", GUARD, str(seconds), "--"] + argv, cwd=cwd, capture_output=True, text=True)
    took = time.perf_counter() - t0
    return ran, took


def main():
    out_dir = os.path.abspath(sys.argv[1])
    exes = [a.split("=", 1) for a in sys.argv[2:]]
    os.makedirs(out_dir, exist_ok=True)
    tree(out_dir)
    runners = {}
    for name, exe in exes:
        ran, _ = guarded(600, [exe, "build", PROGRAM, "-o", f"files-{name}"], out_dir)
        if ran.returncode != 0:
            sys.exit(f"{name}: mo build exit {ran.returncode}: {ran.stderr}")
        runners[(name, "mo run")] = [exe, "run", PROGRAM, "--"]
        runners[(name, "binary")] = [os.path.join(out_dir, "zig-out", "mo-build", f"files-{name}", f"files-{name}")]
    best = {}
    load = {}
    for mode, n in ROWS:
        for rep in range(REPS):
            for key, argv in runners.items():
                ran, took = guarded(600, argv + [mode, str(n)], out_dir)
                want = f"{n} of {n}\n"
                if ran.returncode != 0 or ran.stdout != want:
                    sys.exit(f"{key} {mode}: exit {ran.returncode}, said {ran.stdout!r}, {ran.stderr}")
                k = key + (mode,)
                best[k] = min(best.get(k, took), took)
                load.setdefault(k, []).append(os.getloadavg()[0])
    lines = ["exe\truntime\trow\tcalls\tbest_process_ms\tper_call_us\tload_1m_min\tload_1m_max"]
    for (name, runtime) in runners:
        base = best[(name, runtime, "none")]
        for mode, n in ROWS:
            k = (name, runtime, mode)
            per = (best[k] - base) / n * 1e6 if n else 0.0
            lines.append(f"{name}\t{runtime}\t{mode}\t{n}\t{best[k] * 1e3:.1f}\t{per:.2f}\t{min(load[k]):.2f}\t{max(load[k]):.2f}")
    text = "\n".join(lines) + "\n"
    with open(os.path.join(out_dir, "numbers.tsv"), "w") as f:
        f.write(text)
    sys.stdout.write(text)


if __name__ == "__main__":
    main()

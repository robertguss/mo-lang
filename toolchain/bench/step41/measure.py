#!/usr/bin/env python3
"""Step 41's numbers: what one Command.run costs under `mo run` and as a `mo build` binary, against
a C posix_spawn loop (floor.c) as the floor, best of five, load average beside each row.

    python3 measure.py OUT_DIR MO_EXE

Every mo, build and binary runs under bench/step36/guard.py with a timeout. Each row is timed as a
whole process; the same process with no runs (`none`) is subtracted, so a row's number is the cost
of its runs alone. `true` runs /usr/bin/true; `mib` runs /usr/bin/head -c 1048576 /dev/zero, whose
MiB the run keeps. Runs of the three are interleaved, one of each in turn, so a change in the
machine's load falls on all three.
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.path.join(HERE, "..", "step36", "guard.py")
PROGRAM = os.path.join(HERE, "runs.mo")
FLOOR = os.path.join(HERE, "floor.c")
REPS = 5
ROWS = [("none", 0), ("true", 300), ("mib", 30)]


def guarded(seconds, argv, cwd):
    t0 = time.perf_counter()
    ran = subprocess.run(["python3", GUARD, str(seconds), "--"] + argv, cwd=cwd, capture_output=True, text=True)
    return ran, time.perf_counter() - t0


def main():
    out_dir = os.path.abspath(sys.argv[1])
    exe = sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    ran, _ = guarded(600, [exe, "build", PROGRAM, "-o", "runs"], out_dir)
    if ran.returncode != 0:
        sys.exit(f"mo build exit {ran.returncode}: {ran.stderr}")
    floor = os.path.join(out_dir, "floor")
    ran, _ = guarded(120, ["cc", "-O2", "-o", floor, FLOOR], out_dir)
    if ran.returncode != 0:
        sys.exit(f"cc exit {ran.returncode}: {ran.stderr}")
    runners = {
        "mo run": [exe, "run", PROGRAM, "--"],
        "binary": [os.path.join(out_dir, "zig-out", "mo-build", "runs", "runs")],
        "C posix_spawn": [floor],
    }
    best, load = {}, {}
    for mode, n in ROWS:
        for _ in range(REPS):
            for key, argv in runners.items():
                ran, took = guarded(600, argv + [mode, str(n)], out_dir)
                want = f"{n} of {n}\n"
                if ran.returncode != 0 or ran.stdout != want:
                    sys.exit(f"{key} {mode}: exit {ran.returncode}, said {ran.stdout!r}, {ran.stderr}")
                k = (key, mode)
                best[k] = min(best.get(k, took), took)
                load.setdefault(k, []).append(os.getloadavg()[0])
    lines = ["runtime\trow\truns\tbest_process_ms\tper_run_us\tload_1m_min\tload_1m_max"]
    for key in runners:
        base = best[(key, "none")]
        for mode, n in ROWS:
            k = (key, mode)
            per = (best[k] - base) / n * 1e6 if n else 0.0
            lines.append(f"{key}\t{mode}\t{n}\t{best[k] * 1e3:.1f}\t{per:.1f}\t{min(load[k]):.2f}\t{max(load[k]):.2f}")
    text = "\n".join(lines) + "\n"
    with open(os.path.join(out_dir, "numbers.tsv"), "w") as f:
        f.write(text)
    sys.stdout.write(text)


if __name__ == "__main__":
    main()

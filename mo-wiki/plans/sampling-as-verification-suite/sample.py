#!/usr/bin/env python3
"""The driver for sampling as verification (mo-wiki/plans/sampling-as-verification.md).

  sample.py gen --out DIR [--seeds 1000] [--ops 40]
      write one script per seed, DIR/<seed>.txt, in the harness's format (_harness.md)
  sample.py run --name NAME --scripts DIR --jobq DIR --mo PATH --out DIR
      play every script through `mo run sampler.mo -- <script>` in the jobq folder, save DIR/NAME/<seed>.out
  sample.py compare --out DIR --variants a,b,c,d,e [--original orig]
      for each seed, the first line where a variant differs from the majority of the variants;
      groups by (command, majority outcome head, minority outcome head); prints the groups with a seed each
"""
import argparse, collections, os, random, subprocess, sys

QUEUES = ["a", "b"]
WORKERS = ["w1", "w2", "w3"]
STATES = ["queued", "leased", "done", "dead"]

def gen(seed, ops):
    r = random.Random(seed)
    now = 0
    lines = []
    made = 0
    for _ in range(ops):
        now += r.choice([0, 0, 50, 100, 250, 600])
        w = r.choice(WORKERS)
        kind = r.choices(["create", "fetch", "list", "remove", "lease", "ack", "fail", "health"],
                         weights=[14, 8, 6, 6, 24, 16, 14, 4])[0]
        jid = f"j_{r.randint(1, max(1, min(made + 1, 8)))}"
        if kind == "create":
            made += 1
            payload = r.choice(["x", "hello world", "", "é ü", "a\\nb", "quote \" here"])
            lines.append(f"{now} {w} create {r.choice(QUEUES)} {r.randint(1, 3)} {payload}")
        elif kind == "fetch": lines.append(f"{now} {w} fetch {jid}")
        elif kind == "list": lines.append(f"{now} {w} list {r.choice(QUEUES + ['-'])} {r.choice(STATES + ['-'])}")
        elif kind == "remove": lines.append(f"{now} {w} remove {jid}")
        elif kind == "lease": lines.append(f"{now} {w} lease {r.choice(QUEUES)} {r.choice([100, 100, 250, 500, 1000])}")
        elif kind == "ack": lines.append(f"{now} {w} ack {jid}")
        elif kind == "fail": lines.append(f"{now} {w} fail {jid} {r.choice(['smtp down', 'timeout', ''])}".rstrip())
        else: lines.append(f"{now} {w} health")
    return "\n".join(lines) + "\n"

def cmd_gen(a):
    os.makedirs(a.out, exist_ok=True)
    for s in range(a.seeds):
        open(os.path.join(a.out, f"{s}.txt"), "w").write(gen(s, a.ops))
    print(f"{a.seeds} scripts in {a.out}")

def cmd_run(a):
    out = os.path.join(a.out, a.name); os.makedirs(out, exist_ok=True)
    scripts = sorted(os.listdir(a.scripts), key=lambda n: int(n.split(".")[0]))
    failed = 0
    for n in scripts:
        script = os.path.abspath(os.path.join(a.scripts, n))
        try:
            p = subprocess.run([a.mo, "run", "sampler.mo", "--", script], cwd=a.jobq, capture_output=True, text=True, timeout=120)
            text = p.stdout if p.returncode == 0 else p.stdout + f"\nEXIT {p.returncode}\n{p.stderr}"
        except subprocess.TimeoutExpired:
            text = "TIMEOUT\n"; failed += 1
        open(os.path.join(out, n.replace(".txt", ".out")), "w").write(text)
    print(f"{a.name}: {len(scripts)} scripts played, {failed} timed out")

def outcomes(text):
    """The transcript as a list of (lineno, outcome head, canonical block) per script line. The block is
    the outcome line, the listed jobs in order, then the writes as the store would end up: one line per
    key, the last write to that key, keys sorted. The order of writes to different keys is not observable
    once the batch is on disk, so it does not count; two writes to one key in a different order do."""
    blocks = []
    for ln in text.split("\n"):
        if not ln: continue
        if ln.startswith("  "):
            if blocks: blocks[-1][2].append(ln)
            continue
        parts = ln.split(" ", 2)
        blocks.append((parts[0], parts[1] if len(parts) > 1 else "", [ln]))
    out = []
    for no, head, lines in blocks:
        jobs = [l for l in lines[1:] if l.startswith("  J ")]
        writes = {}
        for l in lines[1:]:
            if l.startswith("  W "):
                key = l[4:].split(" ", 1)[0]; writes[key] = l
        canon = [lines[0]] + jobs + [writes[k] for k in sorted(writes)]
        out.append((no, head, canon))
    return out

def cmd_compare(a):
    variants = a.variants.split(",")
    seeds = sorted(int(n.split(".")[0]) for n in os.listdir(os.path.join(a.out, variants[0])))
    scripts_dir = a.scripts
    groups = collections.defaultdict(list)
    agree = 0
    for s in seeds:
        texts = {v: open(os.path.join(a.out, v, f"{s}.out")).read() for v in variants}
        if a.original:
            texts[a.original] = open(os.path.join(a.out, a.original, f"{s}.out")).read()
        script = open(os.path.join(scripts_dir, f"{s}.txt")).read().split("\n")
        parsed = {v: outcomes(t) for v, t in texts.items()}
        n = max(len(p) for p in parsed.values())
        found = False
        for i in range(n):
            blocks = {v: ("\n".join(p[i][2]) if i < len(p) else "<none>") for v, p in parsed.items()}
            votes = collections.Counter(blocks[v] for v in variants)
            majority, count = votes.most_common(1)[0]
            minority = {v: b for v, b in blocks.items() if b != majority}
            if minority:
                cmd = script[i].split(" ", 2)[2].split(" ")[0] if i < len(script) and script[i] else "?"
                head = lambda b: b.split("\n")[0].split(" ", 2)[1] if " " in b.split("\n")[0] else b[:20]
                for v, b in minority.items():
                    groups[(cmd, head(majority), head(b), v)].append((s, i + 1, count))
                found = True
                break
        if not found: agree += 1
    print(f"{len(seeds)} seeds; {agree} with every variant agreeing on every line; {len(seeds) - agree} with a first disagreement")
    print("\ngroups (command, majority, minority, variant): seeds, first seed and line, majority size")
    for key, hits in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        s, line, count = hits[0]
        print(f"  {key}: {len(hits)} seeds; e.g. seed {s} line {line}, majority {count} of {len(variants)}")

def main():
    ap = argparse.ArgumentParser(); sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("gen"); g.add_argument("--out", required=True); g.add_argument("--seeds", type=int, default=1000); g.add_argument("--ops", type=int, default=40)
    r = sub.add_parser("run"); r.add_argument("--name", required=True); r.add_argument("--scripts", required=True); r.add_argument("--jobq", required=True); r.add_argument("--mo", required=True); r.add_argument("--out", required=True)
    c = sub.add_parser("compare"); c.add_argument("--out", required=True); c.add_argument("--scripts", required=True); c.add_argument("--variants", required=True); c.add_argument("--original")
    a = ap.parse_args()
    {"gen": cmd_gen, "run": cmd_run, "compare": cmd_compare}[a.cmd](a)

if __name__ == "__main__":
    main()

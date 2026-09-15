#!/usr/bin/env bash
# The Mac scaling run for step 30 (mo-wiki/plans/interpreter-step-30.md, decision log 15 Sep 19:30):
# the suite, then the bench and the two native services at MO_CORES 1, 4, 10, 14, best of five,
# on Robert's M3 Max. The question is scaling against one core on the same machine, not the VM.
#
# usage, from the repo root on the Mac, with Zig 0.16 on PATH:
#   mo-wiki/plans/interpreter-step-30-suite/mac-run.sh [cores...]     default: 1 4 10 14
# results land in ../step30-mac/ as text files plus driver.log; paste driver.log into the decision log.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
S=$R/../step30-mac
MO=$R/toolchain/zig-out/bin/mo
SUITE=$R/mo-wiki/plans/interpreter-step-30-suite
CORES=${*:-1 4 10 14}
mkdir -p "$S/bin" "$S/data"
log() { echo "$(date +%H:%M:%S) $*" | tee -a "$S/driver.log"; }

log "start on $(uname -m), $(sysctl -n hw.ncpu 2>/dev/null || nproc) cores, cores to run: $CORES"

# 1. build and the suite (cold zig build test takes minutes; it is silent on success)
(cd "$R/toolchain" && zig build 2>&1 | tail -3 && time zig build test 2>&1 | tail -5) 2>&1 | tee "$S/suite.txt"
log "suite: $(tail -1 "$S/suite.txt")"

# 2. native binaries of the two services from the corpus
(cd "$R/examples/programs/jobq" && "$MO" build main.mo -o jobq-mac && cp zig-out/mo-build/jobq-mac/jobq-mac "$S/bin/jobq")
(cd "$R/examples/programs/ledger" && "$MO" build main.mo -o ledger-mac && cp zig-out/mo-build/ledger-mac/ledger-mac "$S/bin/ledger")
log "built $(ls "$S/bin")"

# 3. the bench, best of five, per core count
for c in $CORES; do
    (cd "$R/toolchain" && MO_CORES=$c MO_EXE=$MO ./zig-out/bin/mo-bench ../examples 5 > "$S/bench-c$c.txt" 2>&1)
    log "bench c$c: $(grep -E '^(echo-1k|kv-10k-get|http-1k|logstat-4k|replay-1m)' "$S/bench-c$c.txt" | python3 -c 'import sys; print(" | ".join(" ".join(l.split()[:3]) for l in sys.stdin))')"
done

# 4. the queue: 100k creates, then lease-and-ack pairs at 1 and 32 workers, five runs per core count
for c in $CORES; do
    for n in 1 2 3 4 5; do
        MO_CORES=$c python3 "$R/mo-wiki/plans/control-run-7-suite/measure.py" --serve "$S/bin/jobq serve {dir} --port {port}" > "$S/jobq-c$c-$n.txt" 2>&1
        log "jobq c$c run $n: $(grep -E 'creates|pairs|restart' "$S/jobq-c$c-$n.txt" | python3 -c 'import sys; print(" | ".join(l.strip() for l in sys.stdin))')"
    done
done

# 5. the ledger: 100k transfers from 32 clients, five runs per core count
for c in $CORES; do
    for n in 1 2 3 4 5; do
        d="$S/data/ledger-c$c-$n"; rm -rf "$d"; mkdir -p "$d"
        python3 "$SUITE/ledger_load.py" "$S/bin/ledger" "$d" 100000 18700 --cores $c > "$S/ledger-c$c-$n.txt" 2>&1
        log "ledger c$c run $n: $(grep -E 'transfers' "$S/ledger-c$c-$n.txt" | head -1)"
    done
done
log "done"

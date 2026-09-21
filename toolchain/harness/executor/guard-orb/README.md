# Guarded wrapper controls

`controls.py` exercises the local recording wrapper and its shared process-group
supervisor. Run from the repository root with a fresh output directory:

```sh
python3 -B toolchain/harness/executor/guard-orb/controls.py \
  --wrapper toolchain/harness/executor/guarded.py \
  --output /tmp/mo-guarded-controls-unique
```

Every case has a 12-second harness deadline and independently finite payloads,
descendants, fake probes, and unrelated sentinel. Wrapper output goes to a file
with a 64 KiB collection bound rather than an unbounded pipe. Controls publish
readiness before a signal or fault, record payload PID/group independently, and
observe liveness before fallback cleanup. `finally` first stops and reaps the
wrapper, then rereads ownership files and independently attempts every known
group/PID cleanup even if another cleanup operation fails. Observation errors
fail the control rather than meaning not-live. `--controls NAME...` selects
named cases.

The output directory contains disposable per-attempt logs, including two logs
larger than 16 MiB. The concise committed `.log` and `.exit` files beside this
README are the raw summaries and real pipeline statuses. `REPORT.md` records the
exact runs, coverage, and limitations.

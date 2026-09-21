# Guarded wrapper controls

`controls.py` exercises the local recording wrapper and its shared process-group
supervisor. Run from the repository root with a fresh output directory:

```sh
python3 -B toolchain/harness/executor/guard-orb/controls.py \
  --wrapper toolchain/harness/executor/guarded.py \
  --output /tmp/mo-guarded-controls-unique
```

Every case has a 12-second harness deadline, publishes readiness before a signal
or fault is injected, records the payload PID and group independently, observes
child and descendant liveness before fallback cleanup, and then cleans all known
owned processes in `finally`. A separately sessioned sentinel must survive every
case. `--controls NAME...` selects named cases.

The output directory contains disposable per-attempt logs, including two logs
larger than 16 MiB. The concise committed `.log` and `.exit` files beside this
README are the raw summaries and real pipeline statuses. `REPORT.md` records the
exact runs, coverage, and limitations.

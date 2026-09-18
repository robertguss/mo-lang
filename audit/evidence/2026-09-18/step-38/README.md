# Evidence: step 38 (a full-duplex Conn, TCP_NODELAY, the handshake abuse cells), 18 Sep 2026

Raw pointers and outputs, in the charter's form. Fable's readings are named at the end: open after your own.

- The brief as the worker got it: `mo-wiki/plans/interpreter-step-38.md` as of `504add8` (everything above `## Result`).
- The commits: `ebf59b3` (part A), `1bb5612` (part B), `26610d6` (part C), on `main`.
- The worker's pane as read at its end (synthesis by the party under test, not evidence of correctness): `worker-pane.txt`.
- The worker's raw outputs: `toolchain/bench/step38/` (`abuse.py`, `work/abuse.txt`, `RESULTS.md` is the worker's synthesis, `window-dial.mo`).
- The lead's expected answer per abuse cell, committed at `90cbc2f` before the worker's table was seen: `expected-cells.md`.
- The lead's suite run: `fable-probe/zig-build-test.log` (date, uptime, commit, summary line, exit).
- The mutant: `fable-probe/mutant-old-runtime.txt` (`mo test` on main's `duplex.mo` by the runtime of `b0b2ac4`: green, its two tests are fixture tests), `mutant-run-transcript.txt` (one run of the transcript: equal, by luck), `mutant-old-runtime-ten-runs.txt` (ten runs on each runtime, at 1 and 14 cores).
- The pipelining probe: `fable-probe/pipeline_probe.py`, its outputs `pipeline-run-OLD-runtime-b0b2ac4.txt`, `pipeline-run.txt`, `pipeline-binary.txt`; the first attempt and what was wrong with it under `fable-probe/first-attempt/`.
- Conditions: Robert's Mac (M3 Max), in use by him all morning, load 4 to 8; the worker's Linux numbers come from an OrbStack container on the same machine.

Fable's readings (open after your own): the decision-log rows of 18 Sep on step 38; the `## Result` of the plan page; `audit/fable-reading-2026-09-18-step-38-plan.md`.

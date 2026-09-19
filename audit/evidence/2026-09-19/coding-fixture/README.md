# Coding fixture independent acceptance — 19 Sep 2026

Lead reading: open after your own source reading. Worker branch
harness/coding-fixture-v1, base 5f87021, commits 84d442e and 3964f1f integrated as
9bae779 and e6f04ce. Scope: trusted inert-command orchestration and reports.

attempt-01 retains the cold-runner failure: native legacy execution occurred
before build; all six failed to launch, and three expected-exit 1 cases falsely
passed. Original accept-source.py is preserved. The correction builds first,
requires a native executable and compares exact stderr/stdout/exit status.

attempt-02 started with the prior lead-generated native CLI executable absent,
then passed 49/49 verification commands, seven cancellation controls,22 HTTP
cases each runtime plus two boundary groups, all 12 legacy goldens and six extra
HTTP controls. Full build/test exit 0:243/243 tests,5/5 steps at 2:05 AM ET.
114 worker files and 19 owned aggregate ID records match; 64 other main records
are preserved. All 3307 tracked examples/toolchain files remained unchanged.
Per-step status records prove guard exits and no remaining process-group members.

lead-controls.py adds failure-with-zero-exit, boolean-exit and string-elapsed
responses in both runtimes: one provider plus one command dispatch, unknown
terminal usage and preserved per-call 11. Worker evidence under examples retains
the positive 17 cancellation RED, native post-report append RED, own faults0
full-suite failure and all correction attempts. No historical evidence rewritten.

Reproduce in an owned Herdr run pane with a new output name:

```sh
python3 toolchain/bench/step36/guard.py 1800 -- python3 audit/evidence/2026-09-19/coding-fixture/accept.py fresh-01
```

accept.py and per-step command records give exact commands. It preserves the
previous generated native executable in a private temporary directory before a
cold build; it does not remove tracked source. Synthetic HTTP fixtures close.
This proves neither actual candidate execution nor live provider integration,
Darwin full-sync, Step 39 acceptance, language value or the Pi comparison.

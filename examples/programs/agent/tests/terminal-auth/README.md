# Agent terminal authentication policy v1 evidence

Base: `ff669fd52e93ccf6aa970b05082d842c471cb1c9`.
Implementation worker: GPT-6-Astra, Herdr `w4:pR`; owned run pane `w4:pS`.
No providers, credentials, compiler changes, or executor integration are involved.
Lead acceptance follows integration.

## Results

| Case | Requests, interpreter / compiled | Outcome in both |
|---|---|---|
| 401, then valid response | 1 / 1 | Status(401) |
| 503, 401, then valid response | 2 / 2 | Status(401) |
| malformed 200, 401, then valid response | 2 / 2 | Status(401) |
| 503, valid response | 2 / 2 | Answer(7,5) |
| three 503s, then valid response | 3 / 3 | Status(503) |
| valid response | 1 / 1 | Answer(7,5) |
| exhausted deadline | 0 / 0 | Late |
| response delayed past deadline | 1 / 1 | Late |
| no retries, 401 | 1 / 1 | Status(401) |

Final behavioral evidence: `evidence/green-interpreter-3.jsonl` and
`evidence/green-compiled-2.jsonl`: 18/18 pass, command exits 0, outer exits 0,
all fixture listeners closed. Earlier successful matrices remain retained.
`evidence/checks-1.jsonl`: local model tests 3/3; versioned recipe conformance
16/16 (3 signatures); unchanged generic recipe regression tests 9/9
(3 signatures); driver check and native build pass. The generic regression
command is evidence of preserving existing tests, not a claim that Agent still
implements the generic recipe's prose policy.

`mo test --write` on the abstract recipe runs its reject-contract test and skips
15 bodyless tests; these same tests actually execute in versioned conformance,
with zero skips. Generated metadata is not itself conformance evidence.

## Red-to-green history

- `red-1`: driver syntax failure before requests (exit 1).
- `red-2`: pattern/supervision failures before requests (exit 1).
- `red-3`: genuine policy failure against unchanged Agent.Model: process exit 0,
  received statuses `[401, 200]`, returned `Answer(7,5)` instead of terminal
  `Status(401)`; independent test runner exit 1.
- `conformance-1`: helper case-arm syntax failure; retained exit 1.
- `green-interpreter-1`: same helper syntax failure in nine cases; retained exit 1.
- `conformance-2`: stale generated verification metadata; retained exit 1.
- `checks-1`: regenerated owned metadata, then all checks and build passed.
- `green-interpreter-2` / `green-compiled-1`: first successful 18-case matrix.
- Final matrix above additionally waits for HTTP handler threads and records
  explicit listener cleanup. The Agent implementation and driver did not change.

Each JSONL row retains the exact command, real child exit code, stdout, stderr,
expected result and independent HTTP requests. Matching `.exit` files hold the
outer command's real exit code. No failed run is presented as policy evidence.

## Reproduce

Run from this worktree in a task-owned Herdr run pane. Both Python runners
default to this checkout's `toolchain/zig-out/bin/mo`. To use a verified compiler
from another checkout, explicitly set `MO_BIN` to its executable path, for example
`export MO_BIN=/path/to/main-checkout/toolchain/zig-out/bin/mo`. The compiled
driver still runs from this worktree's `zig-out/`; `MO_BIN` selects the compiler,
not the driver. Every nested Mo/driver operation has a numeric guard timeout.

```sh
python3 toolchain/bench/step36/guard.py 600 -- python3 examples/programs/agent/tests/terminal-auth/checks.py
python3 toolchain/bench/step36/guard.py 600 -- python3 examples/programs/agent/tests/terminal-auth/run.py interpreter
python3 toolchain/bench/step36/guard.py 600 -- python3 examples/programs/agent/tests/terminal-auth/run.py compiled
python3 toolchain/bench/step36/guard.py 60 -- python3 examples/programs/agent/tests/terminal-auth/verify.py
```

`checks.py` records the explicit `mo test --write`, `mo check`, generic recipe
regression, driver check, and `mo build ... -o terminal-auth` commands. Build
outputs and brick caches are local to this worktree's ignored `zig-out/`.
`verify.py` checks retained evidence, source allowlist, byte identity of the
shared recipe, verbatim preservation of its test blocks, and exact ID diffs.
`evidence/generated-ids.diff` contains the record-level generated-ID changes.

The red run used `run.py interpreter --only immediate-401` before changing
Agent.Model. Running that command now should pass; the retained baseline result
is the red evidence. `--only` accepts only the nine defined case names
(as listed by `run.py --help`); an unknown name exits 2 instead of silently
running no tests.

## Decisions and limitations

1. The production change adds only `outcome is Error(Status(401))` to the
   existing terminal condition. No request/parser/deadline code changes.
   Versioned intent and binding explicitly describe the specialization.
2. Recipe conformance injects tests into the implementation, so a small
   `StatusFake`/supervisor pair is defined beside the existing Fake in both
   recipe and implementation. It sends real Response status fields and counts
   accepted requests. The separate Python HTTP fixture provides independent
   socket-level status/count evidence in both runtimes.
3. The driver obtains `reply_by` from a caller's bounded ask and narrows it with
   `at_most(budget.ms)`; zero narrows it to an already exhausted deadline. The
   outer caller waits an extra 1,000 ms to observe the model's own Late result.
   Normal model budget is 2,000 ms; the delayed case uses 200 ms against a
   600 ms response delay. Agent.Model never manufactures or extends a deadline.
4. Each fixture binds only `127.0.0.1` on an ephemeral port. Socket reads have a
   3-second timeout, drivers a 20-second guard, and each full matrix a 600-second
   guard. A finally block shuts down and closes the server, joining listener
   and handler threads. No persistent server or task writer is needed.
5. Scope is focused application policy verification, not a full compiler,
   application, simulation, live-provider, or untrusted-executor acceptance run.
   Recipe conformance runs in the interpreter; the compiled driver exercises
   all nine real HTTP cases. Lead supplies integration acceptance and a control
   not chosen by this worker.
6. Generated IDs live in shared sidecar files, but only `agent/model.mo` in
   `examples/programs/.mo.ids` and the new recipe record in
   `examples/recipes/.mo.ids` change. This exact scope was confirmed by lead.

## Review correction verification

`review-checks.py` checks compiler selection in both runners (default and explicit
`MO_BIN`, with compiler subprocesses stubbed), rejects an unknown `--only` in
both modes (exit 2), and runs only interpreter `immediate-401` against the real
HTTP fixture using the selected compiler. It also checks all 28 prior evidence
files byte-for-byte against the original implementation commit. Run with the
same optional `MO_BIN` setting described above:

```sh
python3 toolchain/bench/step36/guard.py 120 -- python3 examples/programs/agent/tests/terminal-auth/review-checks.py
```

`evidence/review-corrections-1.jsonl` and its `.exit` record the passing focused
run. The entire 18-case matrix was not rerun for these runner-only corrections;
lead will repeat it after integration.

## Generated dependency closure v2

After integration, lead's native suite reported MO0317 in the eight dependent
Agent modules and a missing verified line in the new driver (241/243 overall).
Lead authorized this exact generated-only closure on the existing worker tip
`bc784d87cc9c98f8c5a4978316c324129a69b1de`, without rebasing or behavioral edits.
The earlier scope/evidence above describes the initial implementation; v2 extends
that scope only as follows:

- `tools.mo`, `steps.mo`, `run.mo`, `registry.mo`, `server.mo`, `check.mo`,
  `main.mo`, `runs.mo`: actual `mo test --write` refreshed their aggregate
  records. All eight source files remain byte-identical. In each record, only
  the verified dependency hash for Agent.Model changed; declaration IDs/hashes
  and every other verified field are unchanged.
- `tests/terminal-auth/driver.mo`: actual `mo test --write --sim 100` appended
  the generated verified/proven lines and added its aggregate record. It has
  zero tests, so the compiler truthfully records `sim (not run)`.
- The existing sim100 records in tools/run/server/runs were preserved by actual
  `--sim 100` runs: 2 + 2 + 2 + 8 tests, each under 100 seeds with 5% faults;
  all 14 held under faults. Run's invariant evidence remains kept 2 / tripped 2.

With `MO_BIN` set as above, the exact orchestration commands were:

```sh
python3 toolchain/bench/step36/guard.py 600 -- python3 examples/programs/agent/tests/terminal-auth/dependency-checks-v2.py
python3 toolchain/bench/step36/guard.py 60 -- python3 examples/programs/agent/tests/terminal-auth/verify.py
```

`evidence/dependency-checks-v2-1.jsonl` records 38 passing commands: nine actual
regenerations (29 tests total), nine module checks, Agent and driver builds,
nine compiled test builds and nine compiled test executions (29 tests total).
Every nested command has a 180-second guard. Native test executions do not run
simulation and do not rewrite the sim100 metadata preserved by the interpreter.
No full compiler suite or HTTP matrix was repeated; lead owns full-suite rerun.

`evidence/generated-ids-v2.diff` is the exact aggregate-ID delta from the previous
worker tip. The original `generated-ids.diff` is unchanged. The extended
`verify.py` validates both stages separately, enforces this exact closure and
unchanged dependent behavior, and verifies all 32 earlier evidence files against
that prior tip. Its passing result is `evidence/verification-v2-1.json`.
No additional dependency or write-scope expansion was needed.

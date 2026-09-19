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

Run from this worktree in a task-owned Herdr run pane. Use the verified native
compiler at `/Users/robertguss/Projects/startups/mo-lang/toolchain/zig-out/bin/mo`.
Every nested Mo/driver operation also has a numeric guard timeout.

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
is the red evidence.

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

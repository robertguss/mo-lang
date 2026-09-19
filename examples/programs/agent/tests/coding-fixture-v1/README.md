# Coding fixture v1

Implementation worker: GPT-6-Astra. Base:
`5f87021a754474b8d742f39b0965b3e10d777573`, branch
`harness/coding-fixture-v1`. Worker pane `w4:p15`; owned right/no-focus run pane
`w4:p16`. Local commits only. Lead owns integration and wiki documentation.

This is trusted fixture orchestration, not candidate containment, live inference,
a real build verdict, or proof that a remote command was killed. The Python
fixture treats `command` as an inert key. No command text is executed on the Mac.

## Interface

Prepare a disposable directory containing `work/`, separate from the harness,
compiler and evidence. The Book writes its existing logs in the sibling `runs/`.
The operator fixes both loopback endpoints and the opaque workspace identity:

```sh
mo run examples/programs/agent/main.mo -- coding-fixture /tmp/disposable-root \
  --model 127.0.0.1:MODEL_PORT --command 127.0.0.1:COMMAND_PORT \
  --workspace opaque-id repair the fixture
```

The opt-in catalog grants list_files/read_file/search/write_file/exact_edit/command.
Legacy catalogs, CLI usage strings, output/exit conventions and stored transcript
schemas are unchanged. Fixture stdout is JSONL. A recorded successful terminal
result exits 0; other fixture terminations/reporting errors exit 3. CLI validation
continues to use the legacy usage-error exit 2 and stderr.

The command response error-code allowlist is `none`, `refused`, `command_failed`,
`timeout`, `cancelled`, `internal`. State/execution/code consistency is checked,
as are all fields, identities, integer/null fields and truncation booleans.
HTTP-200 success with nonzero exit becomes failure. Malformed or mismatched
responses and transport failures have unknown execution and stop subsequent work.
The serialized response is limited to 400,000 bytes and stdout+stderr to 65,536
UTF-8 bytes. Each dispatched command is sent once.

Exact edit checks nonempty literal old_text and counts overlapping byte matches.
Both old and resulting files are limited to 64 KiB. It performs read/check/write
inside the existing Writer on one caller-derived deadline. Only UTF-8 text is
accepted by the existing Fs API. Refusals do not write; write timeout is uncertain
and is never retried. This is not an atomic filesystem transaction and does not
protect against an outside concurrent writer or establish a symlink sandbox.

The fixture caps recorded steps at 16, declared synthetic tokens at 4,096,
serialized model requests at 64 KiB, run deadline at 30 seconds and each
model/tool call at 2 seconds, with zero model retries. Before each model dispatch
its exact serialized request is measured. Recording waits consume a single
15-second allowance measured by the shared deadline remaining before/after each wait; final retrieval receives a deadline for only its remainder,
inside the overall 45-second controller deadline. Book.Write acknowledgement
precedes subsequent dispatch. A recording failure stops dispatch without replay.
Cancellation is observed at existing recording boundaries. Final reporting waits
for Run.Stopped, then reads the stable Book record and transcript; a terminal
Book state alone is not enough.

JSONL includes recorded model/tool steps, a decoded structured result, usage
classification and one recorded terminal result. Failed model-call usage is
unknown, tool usage is not applicable, and declared synthetic zero is reported.
An unknown call makes total usage unknown. Cancelled terminal totals are always
unknown/null, conservatively including an in-flight call that may not be recorded;
any recorded call keeps its own declared synthetic usage. Transcript retrieval/sequence/count
failures produce a reporting_error, never an empty successful substitute.
Timing captures the start before fixture call execution. Tokens are synthetic
reported usage; overshoot stops subsequent work and is not an exact billing cap.

## Final focused evidence

- `interpreter-review-final.jsonl` and `compiled-review-final.jsonl`: 22/22 independent HTTP
  cases in each runtime, outer exit 0. Each case has real child exit codes,
  exact commands, stdout/stderr, independently observed request order, retained
  request identities and transcript counts. Fixture listeners and handler threads
  close after every case. The repair case records nine steps, two command
  requests, expected edited bytes and a final answer. Every later HTTP request
  is checked against the log already written on disk.
- `verify-review-1.jsonl`: 49/49 guarded commands, outer exit 0; 66 interpreter tests,
  39 native tests, 16 recipe conformance tests (three signatures, zero skips),
  native application/test builds, owned formatting and generated dependency
  closure. Embedded legacy output verifies all six golden CLI fixtures in each
  runtime. `legacy-1.jsonl` also retains their direct 12/12 evidence.
- Two focused Mo groups in `boundaries.mo`, included in those counts, cover
  empty-match refusal and reporting errors, plus grant denial, cancellation,
  exhausted deadline and recording failure without subsequent dispatch. Together
  with the 22 HTTP cases there are 24 named new behavioral groups per runtime.
  The final boundary process group ran 100 seeds with 5% faults and held under
  faults. Unavailable setup/observations are explicitly distinguished from a
  successful run; assertions cover bounded requests, unchanged bytes and report
  usage when records are observable. Earlier zero-fault evidence is historical.
- Existing Book/Tools/Run/Server/Runs simulation coverage was actually rerun at
  100 seeds with the existing 5% fault setting. Native tests do not simulate and
  do not overwrite that interpreter-generated simulation evidence.
- `scope-review-final.json` checks exact ownership, byte-identical generated-only
  dependency sources, unchanged unrelated aggregate records and frozen source
  hashes. `generated-ids.diff` retains the exact aggregate record delta.

`cancel-review-1.jsonl` retains seven passing correction checks, including the
actual production watcher with a 400 ms delayed, positive-token model response
in both runtimes. The driver checks a 300 ms post-report log-stability window;
the report retains the model's 17 tokens and emits terminal unknown/null. The
same existing boundary group also covers empty cancelled records, recording
failure totals, declared zero, incomplete transcript rejection and consumed
grace. No new named behavioral group was added.

The source is frozen after `verify-review-1` / `cancel-review-1`, before the two
review-final HTTP matrices. Lead integration/full-suite acceptance remains
separate, as requested after review corrections.

## Dependency closure and scope

Behavioral files: main.mo, record.mo, registry.mo, run.mo, tools.mo and the four
new modules coding-fixture.mo, command-adapter.mo, exact-edit.mo, report.mo.
steps.mo was verified but remains byte-identical. The owned test directory is
new. No compiler, model, shared recipe, provider, executor or wiki source changed.

Generated-only aggregate records refreshed for api.mo, book.mo, check.mo,
filing.mo, runs.mo, server.mo, shelf.mo, transcript.mo and steps.mo. These source
files remain byte-identical; declaration IDs/hashes are unchanged. Only their
verification dependency evidence changes. New/touched owned module records and
one new boundaries.mo record account for the remaining .mo.ids delta.

The brief originally named underscore filenames. `check-4.jsonl` retains
MO0323 resolving Agent.ExactEdit to exact-edit.mo; `check-5.jsonl` retains MO0001
rejecting underscore module names. Lead explicitly authorized the three
hyphenated filename substitutions. There is no compiler workaround.

## Reproduce

Run from this checkout in an owned Herdr run pane. Select an existing compiler
with `MO_BIN=/path/to/mo`; runners default to this checkout's
`toolchain/zig-out/bin/mo`. No committed runner hardcodes another checkout.
All nested commands have numeric guard timeouts and owned process-group cleanup.
Each full attempt has a 600-second outer guard and retains less than 16 MiB.
Use fresh evidence filenames; failed attempts are never overwritten.

```sh
python3 toolchain/bench/step36/guard.py 600 -- python3 examples/programs/agent/tests/coding-fixture-v1/verify.py
python3 toolchain/bench/step36/guard.py 600 -- python3 examples/programs/agent/tests/coding-fixture-v1/cancel-checks.py
python3 toolchain/bench/step36/guard.py 600 -- python3 examples/programs/agent/tests/coding-fixture-v1/run.py interpreter
python3 toolchain/bench/step36/guard.py 600 -- python3 examples/programs/agent/tests/coding-fixture-v1/run.py compiled
python3 toolchain/bench/step36/guard.py 600 -- python3 examples/programs/agent/tests/coding-fixture-v1/full.py
python3 toolchain/bench/step36/guard.py 60 -- python3 examples/programs/agent/tests/coding-fixture-v1/scope.py
```

`run.py --only` accepts only the listed case names. `full.py` runs `zig build`
and `zig build test --summary all` in toolchain/. Test programs and the Python
runner's guard/children get their own process group, killed in cleanup even on
failure. Servers are in the guarded runner and explicitly shut down/joined.
No unrelated process or service is stopped.

## Retained failed attempts

- check-1 through check-7: parser/type/shape/module-path failures and stale
  dependency verification, all before HTTP acceptance. check-8/9 retain
  progressive closure and the ConfigureFixture/process-name collision fix.
- boundaries-1: assert/test-fixture forms placed in an ordinary function;
  boundaries-2 is fixed-order green, boundaries-3 adds explicit sim100/faults0.
- interpreter-1: 23/24 passed. Oversized replacement was correctly refused,
  then its large recorded arguments correctly exhausted context bytes. The test
  had incorrectly expected a subsequent model answer. Final expectations check
  both unchanged file and over_budget; no implementation weakening.
- verify-1: unsupported `mo test --fixtures` runner flag exited 2. Native builds
  and tests in that attempt passed. legacy.py uses the six actual CLI golden
  commands. verify-2 and verify-3 are all green.
- Earlier green repair and matrix attempts remain intact, including evidence
  before the refusal-state review correction. Only final artifacts above support
  the frozen result.

## Full branch result and review corrections

`full-1.jsonl` is the unchanged pre-review full attempt: `zig build` exit 0;
`zig build test --summary all` exit 1, **242/243 tests, 3/5 build steps**. The
failure was this worker's zero-fault boundary simulation: corpus.zig:714 compared
105 simulated tests with 104 held-under-fault tests. It was not an observed auth
formatting failure. The new boundary group now runs actual sim100/5% faults and
holds; the focused native/interpreter checks pass. Lead explicitly owns the next
full-suite run after integration. The inherited auth formatter correction was
not applied or changed in this branch.

Lead review identified two reporting issues. `cancel-red-2.jsonl` records the
actual first red: one HTTP response declared 17, Book retained its model step
after the cancellation line, and the report claimed terminal reported_synthetic
17. It did **not** reproduce the predicted zero total. Accepted conservative
policy now emits unknown/null for every Cancelled terminal, preserving per-call
17. `cancel-red-1` was only a driver declaration-order failure.

`race-before-stop-check.jsonl` reproduces the termination race in the compiled
runtime: the driver returned `log changed after report`, with the delayed model
step appended after reporting. The interpreter control passed on that schedule;
`race-red-1.jsonl` is also a passing pre-stop interpreter control, not red proof.
The watcher now explicitly waits for Run.Stopped under its existing finite
controller deadline before asking for the remaining reporting grace and final
recorded data. No Book/Transcript/Model body changed and no in-flight kill is
claimed.

The first grace assertion also failed because Clock.fixture().now did not advance
with fixture waits. Run now deducts the shared Deadline.remaining delta instead
of wall-clock Time subtraction. A delayed-book grace mode in the existing
boundary group proves consumption; all waits retain the existing deadline cap.
`cancel-green-prepare-1`, `race-prepare-1` and `race-before-stop-check` retain
parser/shape and grace-assertion failures on the way to the final green result.

## Cold verification orchestration correction

Lead integration attempt-01 exposed a test-runner defect: `legacy.py` ran before
`build-agent`, so a clean checkout had no native executable. Its exit/stdout-only
comparison falsely accepted native fixtures 3, 5 and 6 when guard.py reported a
launch exception. `cold-legacy-red-01.jsonl` reproduces this on unchanged 84d442e
in a fresh archive: six interpreter passes, six native launch failures, three
false native passes, overall exit 1. Earlier evidence remains byte-identical;
its legacy pass flags did not check stderr and cannot establish that property.

`verify.py` now builds current source before legacy execution and stops on a
failed build. `legacy.py` requires an executable regular file before running
cases and compares exact expected stderr as well as stdout goldens and exit
codes. `cold-legacy-missing-01.jsonl` retains the corrected absent-executable
failure (exit 1, explicit failed preflight, no cases counted as passed).

For a cold check without removing any previous build artifacts, archive the
correction commit into a newly created directory, then run the documented
verification there in the owned right/no-focus Herdr run pane:

```sh
cold_copy=$(mktemp -d /tmp/mo-coding-cold.XXXXXX)
git archive HEAD | tar -x -C "$cold_copy"
cd "$cold_copy"
MO_BIN=/path/to/existing/mo python3 toolchain/bench/step36/guard.py 600 -- python3 examples/programs/agent/tests/coding-fixture-v1/verify.py
```

Worker verification used `/tmp/mo-coding-cold-fixed-01`, archived from 84d442e
with only the corrected verify.py/legacy.py copied in. `cold-verify-before-01.json`
records absent zig-out/native output and source hashes before execution.
`cold-verify-01.jsonl` completed all 49 checks with exit 0, including all 12
legacy cases with exact stderr comparisons. `cold-verify-summary-01.json` records
build-before-legacy ordering, unchanged 192 Mo source files in the cold copy,
and unchanged 79 previously retained evidence files in the worker checkout.

`cold-legacy-invalid-01.jsonl` tests the second line of defense: another fresh
archive plus corrected legacy.py contained a mode-0755 native-path file with
literal bytes `invalid executable format\n`. All six interpreter cases passed;
all six native launch attempts failed with Exec format error and were marked
failed, including fixtures 3/5/6 (overall exit 1). No historical binary was
removed or overwritten. The three disposable copies remain retained under
`/tmp/mo-coding-cold-red-01`, `/tmp/mo-coding-cold-fixed-01`, and
`/tmp/mo-coding-invalid-native-01`. This corrects orchestration only; integrated
acceptance and the full compiler suite remain the lead's responsibility.

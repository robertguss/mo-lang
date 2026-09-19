# Application workspace v1

Rebuild worker: Claude Opus 5, branch `harness/application-workspace-v2`, exact
base `030290b8`. Brief: `mo-wiki/plans/mo-application-workspace-v1.md` ("Rebuild
from scratch"). Local implementation and focused interpreter and native controls
only. The machine (`mo-executor-r01`) and the full `zig build test` suite are
lead-gated and were not run.

## What it is

`agent application-workspace <fresh-root> --model 127.0.0.1:PORT --config <private.json> <goal...>`

- **Configuration.** The operator provisions a private bridge configuration: a
  `0700` directory holding a `0600` file, outside the root. Its keys are exactly
  `version` (`mo-workspace-http-v1`), `port`, `run_id`, `workspace_id` (32
  lowercase hex) and `token` (64 lowercase hex). Mo checks `fs.size` before
  reading it and `byte_size <= 4096` after. Errors name the field and never echo
  its text. No token flag exists.
- **Fresh root.** The root holds `work/` and no `runs` artifacts at all. The
  Book must open with `Ready(0,0)`, and Book.Create's id must equal the
  configured run id before any request.
- **Run.** Run is started with no writer and a read-only placeholder scope, then
  configured once, while Ready and exclusive with the fixture. All six tools go
  to the adapter before any local tool. The model's arguments are recorded
  unchanged. The call id is the next Book step number.
- **Budgets and deadlines.** Budget and order are 16 steps, 4096 tokens, wall
  900000, retries 0, tool 2000, with the six grants. One outer 900 s deadline
  covers everything: work gets the remainder less a 15 s report reserve, and the
  existing shared, diminishing grace is kept. Model and file waits are at most 2
  s. The command wait is at most 300 s, and the candidate timeout is at most 120
  s, taken from what remains after encoding. Below 500 ms nothing is sent.
- **Requests and responses.** Requests are capped at 851968 bytes. Response
  bodies are capped at 524288 bytes and must be strict JSON: no duplicate keys,
  integers only. The exact envelope, identities (null only on pre-admission
  refusals), status-for-error, per-operation shapes and command-stream rules are
  checked. An invalid response becomes the adapter's `invalid_response` with
  unknown execution.
- **Stopping.** After every successful write, a field-based decision stops
  dispatch on: unknown execution, any pre-admission refusal, systemic bridge
  errors, or `execution_valid: false`.
- **Watching and reporting.** The start's reply is kept and answered once, from
  delayed self-polls, when Run has stopped. The report deadline is asked with
  the outer deadline and shared by the final reads. Schema
  `mo-application-workspace-v1`: a profile line of fixed caps, then the steps
  and the terminal. A Book still running after Run stopped, a recording failure,
  or a transcript over 256 KiB each give a `reporting_error` with `persistence`.

## Acceptance groups (24)

| #   | Group                                                                     | Evidence (final frozen)                                                             |
| --- | ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| 1   | Carried findings 1–7, RED then GREEN                                      | `red-01`, `red-03` → `green-02`, `controls-final`                                   |
| 2   | Six remote tools, canaries, Book prefix                                   | matrix `six-tools`                                                                  |
| 3   | Failure → read → edit → command → answer                                  | matrix `repair`                                                                     |
| 4   | Distinct waits; file wait expiry stops                                    | matrix `waits`, `file-wait`                                                         |
| 5   | Near-expiry refusal, clamp, cap, largest request                          | drivers `near-*`                                                                    |
| 6   | Report reserve inside the outer deadline                                  | drivers `reserve-*`                                                                 |
| 7   | Grant, exact arguments, model timeout refused before HTTP                 | matrix `arguments`                                                                  |
| 8   | Request, response and report byte bounds                                  | matrix `request-bound`, `response-bound`, `report-bound`, `report-over`             |
| 9   | Schema, identity, status, number and command-result negatives             | matrix `schema-*`, `status-busy-500`, `success-*`                                   |
| 10  | Stopping outcomes kept verbatim                                           | matrix `unauthorized-401`, `response-timeout-504`, `owner-unknown`, `lost-response` |
| 11  | Completed refusal and output-encoding failure continue                    | matrix `completed-outcomes`                                                         |
| 12  | Configuration negatives                                                   | matrix `config-*`                                                                   |
| 13  | Run binding                                                               | matrix `run-binding`                                                                |
| 14  | Fresh-root refusal, runs left unchanged                                   | matrix `fresh-*`                                                                    |
| 15  | Lost write acknowledgement                                                | matrix `lost-ack`                                                                   |
| 16  | Token absence and unchanged placeholders                                  | shared checks on every matrix case                                                  |
| 17  | Poller answers once and stops scheduling                                  | drivers `poller-*`; `boundaries.mo` sim100/5%                                       |
| 18  | Cancellation during command collection                                    | drivers `cancel-collection`                                                         |
| 19  | Accepted Bridge frontend (local double)                                   | `real_bridge.py`                                                                    |
| 20  | 12 legacy CLI goldens                                                     | verify inherited                                                                    |
| 21  | Coding fixture 22 cases per runtime and its cancel control                | verify inherited                                                                    |
| 22  | Terminal-auth 9 per runtime                                               | verify inherited                                                                    |
| 23  | Formatter, generated closure, all agent tests, recipe, native test builds | `closure-02`, verify mo                                                             |
| 24  | Scope, records, evidence bound, manifest                                  | `scope.py` → `manifest-final.json`                                                  |

## Reproduce

From this checkout, with `toolchain/zig-out/bin/mo` built
(`cd toolchain && python3 bench/step36/guard.py 1500 -- zig build`) or `MO_BIN`
set. Each command below runs under one numeric guard. Nested commands have their
own guards and owned process groups. Use a new attempt name each time; existing
files are never overwritten.

```sh
T=examples/programs/agent/tests/application-workspace-v1
G="python3 toolchain/bench/step36/guard.py 1800 --"
$G python3 $T/controls.py NAME                 # findings 1-7, both runtimes
$G python3 $T/closure.py NAME                  # fmt, verified lines, aggregate records
$G python3 $T/matrix.py interpreter NAME       # [--only case,case]
$G python3 $T/matrix.py native NAME            # builds the agent first, rejects a bad binary
$G python3 $T/drivers.py interpreter NAME
$G python3 $T/drivers.py native NAME
$G python3 $T/real_bridge.py interpreter NAME
$G python3 $T/real_bridge.py native NAME       # after matrix.py native
$G python3 $T/verify.py mo NAME
$G python3 $T/verify.py inherited NAME
python3 $T/scope.py [MANIFEST_NAME]
```

## Decisions not covered by the brief

1. **Configuration key names.** The file holds `version`, `port`, `run_id`,
   `workspace_id` and `token`. The host is fixed at 127.0.0.1.
2. **Model-facing output.** A valid bridge body is passed to the model verbatim.
   The adapter's own outcomes have the shape
   `{"adapter": "mo-application-workspace-v1", state, execution, error}`. An
   invalid body never reaches the model.
3. **Continue versus stop.** Refusals the adapter makes before sending (grant,
   arguments, request size, deadline, call id) continue. These stop: unknown
   execution, every pre-admission refusal (`accepted: false`, kept verbatim, so
   finding 1's `not_started` survives), `execution_valid: false`, and these
   admitted errors: `closed`, `recovery_closed`, `quarantined`,
   `cleanup_required`, `journal_full`, `admission_closed`, `call_limit`,
   `owner_unknown`, `response_timeout`, `transport_unknown`,
   `controller_failure`, `invalid_result`, `duplicate_call` and
   `request_refused`. Everything else that completed continues, including
   timeout or cancellation with completed execution, `output_encoding` and
   `result_too_large`.
4. **Transport errors.** Every transport error is unknown execution and stops,
   including a refused connection.
5. **Identities and statuses.** Only the 409 admission refusals carry
   identities. All other pre-admission refusals carry nulls. The status must be
   the contract's status for the error.
6. **Success rules (finding 4).** A success must be a valid, untruncated zero
   exit. The follow-up review established both rules from the producer. No
   signal rule is added.
7. **Row shapes.** Row shapes are producer-exact: `list_files` {path, length,
   sha256, mode} and `search` {path, offset}. The accepted local test double's
   partial `list_files` rows are refused (`real_bridge.py double-list`).
8. **Finding 5 control.** The encode step takes no deadline, and `timed` samples
   it afterwards. A wall-clock RED was not reproducible, because encoding the
   largest request takes about 3–6 ms. The RED control targets that seam, and
   the drivers show `timeout_ms` taken after encoding (for example, 3000 ms
   before, 2997 ms sent).
9. **Poller timing.** It polls every 20 ms and answers `report_deadline` 500 ms
   before the outer deadline, so the answer can still arrive. It asks Run first,
   and the Book only once Run has stopped. A Run blocked in a command, which
   times out a Look, is not an end.
10. **Report cap (toolchain defect).** A report renders at most 256 KiB of
    transcript, and a larger one is a proved `transcript_too_large` error. See
    `evidence/toolchain-defect-01.md`.
11. **Persistence field.** `reporting_error` payloads carry
    `persistence: proved|uncertain`. A recording failure and a Book still
    running after Run stopped are uncertain.
12. **Exit codes.** Done exits 0. Every other terminal and every reporting error
    exits 3. Usage errors exit 2.
13. **Goal and token.** A goal containing the token is refused
    (`goal_capability`), but this is not exercised: testing it would put the
    token in argv.
14. **Finding 7 fix location.** The fix is the slice's own wrapper
    (`common.invoke`), not `toolchain/bench/step36/guard.py`, which is out of
    scope and already exits with the child's code.

## Limitations

- **Toolchain defect, not fixed.** Large application reports make native print
  raw memory and make the interpreter panic. The cap avoids that path; the root
  cause is open.
- **No machine or real core.** Local controls use a strict bridge double and the
  accepted local `test_owner` double. There is no isolation, cleanup or
  real-core claim.
- **Simulated poller group.** It covers startup error and deadline. Normal
  completion and the lost acknowledgement run through real sockets instead: in
  this unsimulated test world the Book goes Down after the first model-step
  write, in legacy mode too.
- **Freshness is an acceptance check.** The fresh-root preflight assumes
  exclusive operator ownership of the root. The configuration bound is an
  acceptance limit, not an atomic read or allocation bound.
- **Stopped is not cleanup.** `Stopped` proves that Mo dispatch ended, not
  external cleanup. A startup failure after Create leaves that run Running in
  the disposable Book, as the fixture does.

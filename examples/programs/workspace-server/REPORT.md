# Workspace server part A: worker report

Worker: Cursor Grok 4.6, not the lead. Branch `harness/workspace-server-4a`.
This report is the last commit. Worktree was clean before it.

## Commits

| SHA | What |
|---|---|
| `966d537efab3abe476f9c632b551fbc355f29beb` | RED: `local.py --target`, Python baseline green, Mo stub red |
| `ee3d032e3daf1282f916710259141628747158c6` | `wire.mo`, `schema.mo`, `envelope.mo` |
| `d679f568c60e1976e7445b78a74975551c7aeb2f` | WIP pause: processes and double, 7/13 groups green half-closed |
| `f9bc1bfb0bdc3ab65798ba22b2a52395a946e524` | Hold a request until Begin; bind an unreadable tree |
| `e7a05e3932fc96ac6ceb12987fb1285239a49b65` | `mo fmt`; journal unit test records four observations |
| `d887d81ef485af209f7a7488ce55310a9e045e77` | Verified lines, evidence, README; `WIP.md` deleted |
| `cd1b12a62bf82d6de573d4dd15157407f7343111` | First REPORT.md |

This file is the commit after `cd1b12a6`.

## Installed on this Linux VM

- `mise` 2026.9.11 (`~/.local/bin/mise`)
- Zig 0.16.0 through mise
- `mo` built from `toolchain/` (`toolchain/zig-out/bin/mo`) under `toolchain/bench/step36/guard.py`

No OrbStack, Docker, or `/opt`. The test double stands in.

## In-scope groups

Groups: six-tools, schema, framing, byte-bounds, identities-capability,
duplicate-calls, concurrent-admission, file-refusals, deadlines, disconnect,
lost-response, journal-order-bound, shutdown.

| Run | Summary | Exit | Log |
|---|---|---|---|
| Python baseline | Ran 13 tests in 22.422s **OK** | 0 | `evidence/red-01-python-baseline/` |
| Mo stub | 0/13 (RED) | 1 | `evidence/red-02-mo-stub/` |
| `mo run` double | Ran 13 tests in 21.513s **OK** | 0 | `evidence/green-01-mo-run/` |
| `mo build` double | Ran 13 tests in 21.001s **OK** | 0 | `evidence/green-02-mo-build/` |

`mo build` binaries: `zig-out/mo-build/workspace-server-double/` and
`zig-out/mo-build/workspace-server/` (`evidence/build-double/`, `evidence/build-main/`, both exit 0).

`command`: `main.mo` answers `request_refused` (this server does not serve it).
`double.mo` scripts `test_owner.py`'s commands so six-tools stays unchanged.
Part B adds `Exec`.

## `mo test --write --sim 200`

Every module, each under the step-36 guard. All exits 0.

| Module | Tests | Sim | Invariants |
|---|---|---|---|
| wire, schema, envelope, tools | 5 / 6 / 5 / 6 | not run (no processes) | — |
| journal | 4 | 200 runs | kept 1, tripped 0 |
| door | 1 | 200 runs | — |
| admission | 6 | 200 runs | kept 1, tripped 0 |
| worker | 3 | 200 runs | — |
| connection | 5 | 200 runs | kept 1, tripped 0 |
| operator, server, main, double | 1 / 0 / 0 / 0 | **not run** | — |

Admission: at most one call admitted; 16-call bound held under faults.
Journal: intent precedes every execution; a duplicate id does not execute twice.
Ask-assertions that expect `Ok(true)` pass only without faults (a dropped
message is `Ok(false)`). That is not an invariant trip.

`mo fmt --check` on every `.mo`: exit 0 (`evidence/fmt-check-2/`).

## Four observations (one admitted `read_file`, then operator close)

Raw: `evidence/observations-mo-run/` (exit 0). Call `obs-1`:

1. **Admission** — `"admission": "admitted", "intent": true` (intent journaled
   before the tool ran).
2. **Execution** — `"execution": "completed"` with the success result
   (`text: "aaa\n"`, `truncated: false`).
3. **Reply produced** — `"reply": {"status": 200, "state": "success",
   "execution": "completed"}` (what this process wrote).
4. **Delivery** — `"delivery": {"known": true, "written": true,
   "peer_ended_during_call": false}` (received, recorded separately).
5. **Cleanup** — `"cleanup": "confirmed", "method": "admission closed, no call
   in flight"` (its own record, not a fifth observation of the call).

Binding (first journal row): `source_sha256` and `observed_sha256` both
`d3bb3c610bcb95fcbe21a05e00897de7ca56fe386cb41bcdc79a36a91a6ac0e8`;
`verifier_sha256` `b0da7ecc96bfdf0b0bc61e7479a7c738cb472aeddbbf5cfff39275633b7ceb9d`.

A lost write or an observed disconnect sets `delivery.known` false and writes
`delivery.json`. The execution row is left as it was.

## Hostile filesystem (part C)

`hostile.py` against the Mo workspace, both runtimes.
`evidence/hostile-mo-run-2/` and `evidence/hostile-mo-build-2/`: **hostile: all ok**, exit 0.

Lexical escapes (`../escape`, `/etc/passwd`, `a//b`, `a/./b`, `answer/..`,
write `../outside`) are `invalid_path`. Last-component and middle-component
symlinks are `filesystem_refusal`. FIFO is `filesystem_refusal`. Hardlink is
`unsupported_entry`. A tree with a link, FIFO, hardlink or setuid refuses every
walk (`list_files`, `search`, and `write_file`, which inventories first).
`exact_edit` with missing / multiple / empty `old_text` leaves bytes unchanged.

First attempt (`evidence/hostile-mo-run/`, exit 1) expected `invalid_path` for
`write_file ../outside` on the links tree. The walk runs first, so the refusal
is `unsupported_entry` / `filesystem_refusal` / `unsupported_mode`. Lexical
writes are checked on a clean tree.

## The size question

`size.py`, after verified lines: `evidence/size-2/` (exit 0).

| Side | Source | Test |
|---|---|---|
| Python (`bridge.py` 312, `owner.py` 185, `protocol.py` 117, `workspace_files.py` 207, controller file-dispatch 19) | **840** | 0 |
| Mo (13 modules) | **1760** | **400** |

Dropped: `command` through Exec, container policy and cleanup proofs, the
Python owner / `orbctl` / controller HTTP to the machine. Added: four journal
observations, operator path (D2), binding hashes, H1–H6 in the Mo processes.
A smaller program that does less would not be a win; this one is larger and
does the journal, the operator path, and the binding the Python service does not.

## Numbers (best of five, loadavg beside)

`timings.py` (not `numbers.py`: a file of that name shadows the stdlib and
cannot `import statistics`; first attempt `evidence/numbers/` exit 1).
`evidence/timings/` exit 0. loadavg start `0.04 0.14 0.13`, end `1.22 0.42 0.23`.

seq-1000 is 1,000 sequential wire requests on one run: 16 admitted, the rest
`call_limit`. Not 1,000 admitted operations.

| Kind | Python best s | `mo run` best s | `mo build` best s |
|---|---|---|---|
| read-1k | 0.0052 | 0.0178 | 0.0126 |
| read-60k | 0.0068 | 0.0292 | 0.0143 |
| search-200 | 0.0133 | 0.0293 | 0.0228 |
| seq-16 | 0.3940 | 0.6095 | 0.3409 |
| seq-1000 | 1.0029 | 2.8608 | 0.6479 |

Python is `local.py`'s `Bridge` + `test_owner` on loopback, not the machine.

## Findings and decisions the brief did not name

**F1.** `Conn.lines` is line-only (64 KiB `LineTooLong`). A Content-Length body
with no newline is not delivered until the peer ends its side. `Http.listen`
cannot serve this wire (lowercase headers, empty 501 bodies, no request
version, joined repeated headers). `behaviour.py` does not change what any
test expects: JSON bodies get a trailing newline (legal whitespace); raw
bodies without a newline still half-close; an oversized unfinished header
gets a CRLF so the 16 KiB cap can be applied. The unchanged wire cannot see
an unfinished 16 KiB header line.

**F2.** `Json.decode` keeps the last of a repeated key. `schema.mo` counts
keys in the raw text against the decoded tree.

**F3, journal scope.** Requirement 6 asked for the journal as another `Fs`
scope written only with `Fs.replace`. `server.mo:102` does
`Journal.start(run, ...)`, so the journal process holds the whole run folder,
which includes `capability.json` with both tokens. The operator's layout
forces `owner.json`, `delivery.json` and `ready.json` to sit beside
`capability.json`; a separate scope is not possible without moving files the
existing tests read at the root. That is a deviation from requirement 6. The
journal process only ever calls `run.replace` (`owner.json` in `written`,
`delivery.json` on an unknown delivery). Grep of `run.` / `fs.` Fs calls in
`journal.mo`: `run.replace("delivery.json", ...)` (line 102),
`run.replace("owner.json", ...)` (line 126). No `read`, `list`, `scoped` or
other `Fs` call on `run` inside the Journal process. The two `fs.read` hits
are in unit tests, after the process has written, not inside it. Part B's
cutover should give the journal `journal/` as its own scope once the layout
is Mo's.

**Handles / arity.** A handle cannot sit in a struct (MO0403). A function
takes at most six parameters (MO0303). The token lives in the Gate; a
per-connection Runner holds admission, worker and journal. `Door` is its own
module so Operator does not expose it (MO0203). Every process has a
supervisor (MO0316).

**H7 vs the contract.** Missing `Host` is **400 malformed** (contract), not
Python's 403. A wrong `Host` value is 403 unbound. 413 carries `malformed`,
not the core `oversized`. `admission_closed` does not overwrite a more
specific refusal (conflict, busy, call_limit).

**Hold until Begin.** A connection that arrived whole before `Begin(me)` was
refused `admission_closed` without touching admission. The body is held
(`phase == "held"`) and dispatched on Begin. That unblocked file-refusals,
byte-bounds, concurrent-admission and journal-order-bound.

**Unreadable tree.** The operator puts `source_sha256` of regular files in
`config.json`. The server records `observed_sha256` (`null` when a walk
refuses) and still serves. File-refusals' links tree can start.

**H2 / disconnect.** A JSON body ending in newline needs no half-close, so a
later full close is visible. Reply's own close is not an observed disconnect.

**D2 / H6.** An observed disconnect journals cleanup and lets `main` exit
(the contract's owner finishes). The operator path is its own process until
then. Delivery unknown is never `owner_unknown`.

## What Python cannot pass (requirements 2–5)

These Mo tests are the measure of what changed. They are not the local.py
groups.

- Four separate journal fields plus cleanup (`journal.mo`). Python's
  `owner.json` is a different schema (nested `calls[id].result.execution`).
- Binding hashes (`source_sha256`, `observed_sha256`, `verifier_sha256`).
- H4 / H5 in `envelope.mo` (`truncated`, `invalid_result`).
- Missing `Host` is 400 (`wire.mo`); Python answers 403.
- Delivery unknown as its own record and `delivery.json` (H6).
- Operator token never flows into `Conn` or the journal (`operator.mo` `never`).

## Unmet

- `operator.mo`, `server.mo`, `main.mo`, `double.mo`: `--sim 200` prints
  `sim (not run)` because they have no process-exercising tests. The flag was
  run; the tool did not simulate.
- Production `command` is refused. Groups use the double.
- F1: the wire is line-only; the adapter completes unfinished header lines.
- F3: the journal process holds the whole run folder, not a separate scope
  (see Findings). No code change.
- Unfiltered full suite, Linux, and the machine are the lead's (part B).
- Protected verifier is part B's (`verify` answers `verified: null`).
- `proven: not run` on every module (no proof backend in this unit).

---
title: "The Mo workspace server, part A: the wire, admission, the journal and the five file tools"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, security, processes]
sources: [plans/mo-harness-in-mo.md, plans/mo-harness-end-to-end-v1.md, research/comparisons/bend2.md]
status: in-progress
---

# The Mo workspace server, part A

## Orientation

Step 4 of [[mo-harness-in-mo]]: the six-tool service written in Mo. Today a
tool call goes from the agent to a Python frontend on the Mac
(`toolchain/harness/executor/workspace_http/bridge.py`), to an owner
subprocess (`owner.py`), through `orbctl run` to a fresh
`workspace_controller.py` process on the machine for every call. The wire is
`mo-workspace-http-v1` (`workspace_http/CONTRACT.md`); its behaviour is pinned
by 22 named groups (`GROUPS.md`, `local.py`). This brief is **part A**: one Mo
program that speaks that wire and serves the five file tools itself, against a
workspace folder it holds as a narrowed `Fs`, with admission, the journal and
the operator's path. It runs on Darwin and Linux with no machine, no Docker
and no `Exec`. **Part B** (a later brief) adds `command` through `Exec`
(step 41), the container policy and cleanup proofs on the machine, and the
cutover. Nothing Python is deleted in part A. Worker: a fresh clean OMP
session using GPT Sol at high reasoning, own worktree and Herdr tab.
The lead owns the wiki, audit and acceptance. No new syntax, no toolchain change: if the
language or stdlib cannot say something, stop and report it with the smallest
example; that finding is a result, not a failure.

**Resumption authorized, 19 Sep, evening:** continue from `d679f568` on
`harness/workspace-server-4a`. Read `WIP.md` and branch history; preserve the
Opus worker's evidence. Its 7/13 figure is an unfiled scratch run with
`--half-close`, not unchanged-wire acceptance. First resolve or report F1
with a filed minimal reproduction; never require clients to add a newline
or half-close as a substitute for the original wire. Keep D2's operator
independence and report conflicting inherited tests rather than weaken them.
No machine or full-suite release. Benchmark runs require lead scheduling.

**F1 filed:** `8b0ff352`, `evidence/f1-06-exact-client/`: the unchanged client
waits without a newline/half-close, times out, then the server receives the
155-byte body after close. [[interpreter-step-44]] adds a bounded binary
source; no adoption or toolchain merge in this worktree until lead release.
Continue genuinely independent part A work. Full wire acceptance remains blocked.

### EOF and delivery decision (lead, 19 Sep, evening)

Step 44 stays unchanged. `Closed` reports input termination, not whether the
peer kept its read half open. `Conn.write` success is local completion, not
proof of client receipt (the existing wire contract already says this).
Do not require the runtime to infer a stronger distinction from TCP EOF.

- A complete admitted request continues across input EOF. Record `read_ended`
  separately; EOF alone neither closes run admission nor cancels execution.
  Reply production follows the real execution result. Attempt the bounded
  response write even after EOF; preserve the independent operator path.
- Journal execution, produced reply, local write outcome and client receipt
  separately. Client receipt is unknown on both successful and failed writes
  because this protocol has no acknowledgment. Never turn transport loss into
  `owner_unknown`, erase a known execution or retry the operation.
- An observed response write failure/timeout or the existing response timeout
  closes admission under the existing deadline policy; it does not kill the
  operator or erase an in-flight/late outcome. Input EOF alone is not such
  evidence. Events after a completed response must not close admission for a
  later call. An incomplete request at EOF is refused before effects.
- H2 control: a full request followed by `SHUT_WR` during a slow admitted
  operation still receives the response, preserves operator access and allows
  a later request if no other terminal limit was reached.
- H6/D2 controls: a graceful full-close client leaves exactly one execution
  and a retained outcome/produced reply, with receipt unknown even if write
  succeeds; the operator can still inspect, freeze and close. Separately force
  a reset/write-failure path and prove terminal admission with the same
  retained execution and operator access. The client driver knows it did not
  read the response; the server must not claim it can observe that fact.

The inherited Python `disconnect` and `lost-response` groups require owner
process exit after candidate close (`local.py:250-256,289-296`). That lifecycle
predicate conflicts with required D2 operator independence; retain those
tests unchanged as Python regression evidence, report their Mo incompatibility,
and add named Mo-specific H2/H6/D2 controls above as the acceptance oracle for
those two groups. Preserve their substantive outcome/cleanup obligations;
explicit operator close proves cleanup in part A's local scope, not machine
cleanup. Do not claim all 13 inherited groups green when two use a different
lifecycle oracle. This is an explicit lead decision, not a worker test waiver.

## Write scope

New: `examples/programs/workspace-server/**` (Mo sources, their tests,
sidecars and `verified:` lines by real tools only, a README, the behaviour
runner and evidence under 2 MiB). In `toolchain/harness/executor/workspace_http/`
only what lets the existing behaviour tests aim at another server: a target
option in `local.py`, and no change to what any test expects. No other harness
file, no toolchain, no wiki, no `audit/`, `HANDOFF.md`; no machine, Docker or
`/opt`; no push. Never use `tr`; `ls` is aliased, use `/bin/ls`.

The real `mo test --write --sim 200` module checks also update shared
`examples/programs/.mo.ids` (worker reported 397 added lines). That parent
sidecar is outside this scope: do not commit it. Restore only check-generated
changes, preserving any pre-existing edits; retain tool-generated `verified:`
lines within owned modules and file the exact commands/results in the report.
After integration, the lead regenerates the shared sidecar with real module
checks in the separate verification worktree and verifies source/ID consistency
before acceptance. That regeneration remains owed; no handwritten IDs or
acceptance based only on retained annotations.

## Design requirements (each becomes a test before its code)

1. **The wire, unchanged.** Same request and response shapes, limits, status
   codes and stable error codes as `CONTRACT.md`. Where the Python departs from
   its own contract (review finding H7: a missing `Host` answered 403; a core
   code used for an oversized body; codes no path produces;
   `admission_closed` overwriting other refusals), the Mo server follows the
   contract, and the report lists every such difference.
2. **Findings closed by design, not patched:** H1 (a slow file operation must
   not end the run: the wait and the work share one deadline); H2 (a legal
   half-close is not pipelining); H3 (no descriptor reuse race: a connection
   is owned by one process from accept to close); H4 (output past a bound is
   `truncated`, never `output_encoding`, and the bound is documented); H5 (a
   success without its required field is `invalid_result`); H6 (a client
   disconnect is recorded as delivery unknown, never as `owner_unknown`).
3. **End to end v1's D2.** The operator's path (freeze, verify, close, read
   the journal) is independent of every candidate connection: a candidate
   that disconnects, stalls or floods cannot close or starve it. Shape it as a
   separate process with its own handle, given only to `main`'s operator side.
4. **Four observations, never one success count** (research PR 14): for every
   call the journal records admission, execution, the reply produced, and
   separately whether delivery is known; cleanup is its own record. A reply
   that could not be delivered keeps its true outcome.
5. **Obligations bound by hash** ([[bend2]], idea 1): the journal's first row
   binds the run to the hashes of the source mapping and of the operator's
   verifier configuration; a verdict names those hashes. Part A only records
   and checks them; the protected verifier itself is part B's.
6. **Capabilities as the fence.** `main` narrows: the workspace folder is one
   `Fs` scope (step 40 makes it hold against links, FIFOs, hardlinks and
   setuid: reuse its refusals rather than re-deriving `workspace_files.py`);
   the journal is another scope written only with `Fs.replace`; the token never
   enters a process that holds the workspace scope's candidate-facing handler
   state longer than the comparison needs; nothing below `main` holds
   `Platform`. `flows` rules state that the token never reaches a reply or the
   journal.
7. **Processes.** One admission process (one operation admitted, no queue, 16
   calls, the 900 s lease), one journal process, one process per connection,
   the operator process; supervisors that restart a crashed connection handler
   without losing the journal. Every wait has `within:`. `mo test --sim` with
   faults must hold the invariants: at most one call admitted; the journal's
   intent precedes every effect; a duplicate call id executes once.

## Parts

A. **RED first.** Aim `local.py`'s wire-level groups at a server by address
   (`--target`), run them against the Python service (green, the baseline) and
   against a stub Mo server (red), and commit both outputs. Groups in scope for
   part A: six-tools (the five file tools; `command` answers the contract's
   refusal for an operation this server does not serve, stated in the report),
   schema, framing, byte-bounds, identities-capability, duplicate-calls,
   concurrent-admission, file-refusals, deadlines, disconnect, lost-response,
   journal-order-bound, shutdown. The rest are part B's.
B. **The server**, in `mo run` and as a `mo build` binary, until those groups
   are green in both, plus new tests for requirements 2 to 5 that the Python
   cannot pass (say which of them fail against the Python, as the measure of
   what changed).
C. **Hostile filesystem cases** from `test_workspace.py` (symlink at the last
   and a middle component, hardlink, FIFO, setuid, lexical escapes,
   `exact_edit` with missing, multiple and empty matches leaving bytes
   unchanged) against the Mo server's workspace.
D. **The size table** ("The size question" on [[mo-harness-in-mo]]): with one
   committed script, non-blank non-comment lines of `bridge.py`, `owner.py`,
   `protocol.py`, and the parts of `workspace_controller.py` and
   `workspace_files.py` this replaces, against the Mo sources; test lines
   separately; features dropped or added listed, so a smaller program that
   does less is not a win.

## Numbers

Best of five, both runtimes, load average beside them: a `read_file` of 1 KiB
and of 60 KiB, a `search` over 200 files, and 1,000 sequential small calls,
each against the same from the Python service on loopback.

## Done when

Every process under `toolchain/bench/step36/guard.py`; **every run the report
quotes is teed into a filed log with an exit file beside it**, under the
program's `evidence/`. The in-scope groups green against the Mo server in both
runtimes with real summary lines and exit codes; `mo test` and `mo test --sim
200` on every module; `mo fmt --check`. **The unfiltered full suite, Linux and
the machine are the lead's.** RED before GREEN; small commits as yourself with
a `Co-Authored-By` line naming your model. **Write your final report to
`examples/programs/workspace-server/REPORT.md` and commit it last, with a clean
worktree.** While anything runs, wait in the foreground rather than ending
your turn. Decisions the brief did not cover go in the report.

## Related

- [[mo-harness-in-mo]]
- [[mo-harness-end-to-end-v1]]
- [[interpreter-step-41]]
- [[bend2]]

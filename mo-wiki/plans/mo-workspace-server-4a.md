---
title:
  "The Mo workspace server, part A: the wire, admission, the journal and the
  five file tools"
created: 2026-09-19
updated: 2026-09-22
type: plan
tags: [agents, tooling, security, processes]
sources:
  [
    plans/mo-harness-in-mo.md,
    plans/mo-harness-end-to-end-v1.md,
    research/comparisons/bend2.md,
  ]
status: paused
---

# The Mo workspace server, part A

**Paused 22 Sep 2026** (parked, not closed; not on main). Linux correctness passed 278/278 on 21 Sep; measurements were blocked; nothing is merged. How to resume: [[HANDOFF]].

## Orb continuation — 20 Sep 2026, evening ET

This section supersedes Mac/Herdr launch and old execution grants below. A fresh
medium worker in an xxlarge Amp orb continues part A from current remote main
plus recoverable `origin/harness/workspace-server-4a`. The later 65f2eca0 Mac
candidate is unavailable in the lead checkout after unshallowing. Recover
retained patches/snapshots from the lead's server-chunks static-review-02,
formatter-review-02 and nesting-review-01 JSON records under
`audit/evidence/2026-09-20/`. Do not edit those historical records or infer that
unfiled final edits/tests exist. Record recovered versus reconstructed source.

Keep the original scope plus the explicitly granted formatter/corpus fixture
repairs; no Step42 code, new syntax, machine/container work, CI or push. Current
main includes newer performance/test-discovery changes: preserve them. Return
the recovery manifest, source diff and guarded Linux correctness plan for
lead/Oracle review before live socket matrices or measurements. Focused builds,
formatter and module tests may run with verified process-group guards and filed
raw outputs/exits. Lead review releases further execution; there is no inherited
grant09 run in this orb. Preserve unchanged-client F1, all original EOF/operator
predicates, real tool-generated metadata and historical REDs.

The lead may supply the independently accepted Step42 part-E guard alone; that
is the sole exception to the no-Step42-code boundary. Do not author a competing
guard repair. Wait for its acceptance before runtime checks. Current full-suite
acceptance and filtered native/integration checks use
`zig build test-corpus --summary all` (with the applicable filter for focused
runs), not `test`, which now skips native integration. Require actual expected
test executions and equivalent full coverage for any before/after suite timing.

### Current orb gate and explicit exception

The accepted guard is on main at `5625f4fa` (guard merge `70c07d32`). Candidate
`5f4a9aff` has source counts 15 modules and 43 tests (35 ordinary + 8 strict),
not executed results. Oracle grants only serialized build (900s),
imported-effect formatter regression via test-corpus (1800s), and
format/fmt-check all 15 modules. Stop at the first failure. Deadline capture
before admission waiting, retained outcomes after failed journal
acknowledgments, discriminating budget controls and size classification still
need correction before further grants.

Part A temporarily trusts Journal with run-folder Fs authority, including access
to capability.json, although its implementation replaces only owner.json and
delivery.json. Requirement 6's separate journal scope is **unmet**, not proved
by those literal targets. Existing Fs cannot scope two sibling files without
their directory. Preserve the comparison layout for part A; a separately scoped
journal/ directory is required at part-B cutover. This is the lead's recorded
exception after Oracle review, not a change to the frozen historical report. Do
not add a JournalStore proxy merely to relocate broad authority.

## Orientation

Step 4 of [[mo-harness-in-mo]]: the six-tool service written in Mo. Today a tool
call goes from the agent to a Python frontend on the Mac
(`toolchain/harness/executor/workspace_http/bridge.py`), to an owner subprocess
(`owner.py`), through `orbctl run` to a fresh `workspace_controller.py` process
on the machine for every call. The wire is `mo-workspace-http-v1`
(`workspace_http/CONTRACT.md`); its behaviour is pinned by 22 named groups
(`GROUPS.md`, `local.py`). This brief is **part A**: one Mo program that speaks
that wire and serves the five file tools itself, against a workspace folder it
holds as a narrowed `Fs`, with admission, the journal and the operator's path.
It runs on Darwin and Linux with no machine, no Docker and no `Exec`. **Part B**
(a later brief) adds `command` through `Exec` (step 41), the container policy
and cleanup proofs on the machine, and the cutover. Nothing Python is deleted in
part A. Worker: a fresh clean OMP session using GPT Sol at high reasoning, own
worktree and Herdr tab. The lead owns the wiki, audit and acceptance. No new
syntax, no toolchain change: if the language or stdlib cannot say something,
stop and report it with the smallest example; that finding is a result, not a
failure.

**Resumption authorized, 19 Sep, evening:** continue from `d679f568` on
`harness/workspace-server-4a`. Read `WIP.md` and branch history; preserve the
Opus worker's evidence. Its 7/13 figure is an unfiled scratch run with
`--half-close`, not unchanged-wire acceptance. First resolve or report F1 with a
filed minimal reproduction; never require clients to add a newline or half-close
as a substitute for the original wire. Keep D2's operator independence and
report conflicting inherited tests rather than weaken them. No machine or
full-suite release. Benchmark runs require lead scheduling.

**F1 filed:** `8b0ff352`, `evidence/f1-06-exact-client/`: the unchanged client
waits without a newline/half-close, times out, then the server receives the
155-byte body after close. [[interpreter-step-44]] adds a bounded binary source.
That capability is now accepted on Darwin; the adoption authorization below
supersedes this dependency hold, not the server's remaining acceptance gates.

### Fresh chunks adoption assignment — 20 Sep 2026

Accepted main contains Step44 at db515f9b (lead records through4eb0c7a2).
Preserve the completed server delivery d689b441/report and all historical
evidence. A **fresh OMP/GPT-5.6-Sol high** worker owns a new worktree/branch
combining those snapshots; do not resume the completed original session. The
lead prepares this combination only in the worker tree, never on main. Step42
remains unaccepted and must not be merged or copied into this work.

Initial authorization is **static implementation and command preparation only**:
no build, test, formatter, lint, py_compile, server, benchmark, machine, Linux,
commit or final report until the lead reviews the proposed diff and exact
guarded manifest. Worker edits remain inside the original write scope. Replace
the production connection's line dependence with bounded chunks and
byte-oriented HTTP framing, using the existing contract's exact byte limits.
Decode text only after the required complete bytes are available; reject
oversized unfinished headers before newline/EOF. Preserve absolute deadlines,
single connection ownership and all EOF/operator rules below. Do not rewrite or
erase the original F1 RED reproducer/evidence; add a separately named
unchanged-client GREEN control exercising the actual server.

Prepare complete acceptance coverage, not only the framing fix: compatible
inherited groups unchanged in both runtimes, five real file tools (not only the
scripted double), hostile filesystem cases, H1–H7/D2, module tests/sim,
metadata/formatting, size accounting and the original scheduled measurements.
The two known Python owner-exit predicates remain incompatible as recorded:
preserve their Python baseline and use the named Mo H2/H6/D2 outcomes below;
never claim thirteen unchanged inherited groups green or rerun the known
incompatibility merely to reconfirm it.

**Refusal precedence is now explicit:** busy, duplicate/conflicting call ID,
closed admission or less than500ms lease remaining,16-call limit, then journal
capacity only for an otherwise admissible request. The wire contract enumerates
these codes/limits but does not specify simultaneous-refusal priority. Preserve
the existing Mo order; test overlapping conditions through admission outcomes.
Do not write an intent merely to discover journal fullness for a request already
refused. Report this policy and Python differences, not blanket H7 equivalence.

**Corpus classification must be resolved before a full-suite grant.** The saved
report already says some module simulations pass only without faults. Do not
rerun that fact as if unknown, weaken the global all-held-under-faults gate,
silently skip controls or make a positive oracle accept errors. Statically map
the exact strict and fault-tolerant tests and propose reuse of the existing
permanent-fixture gate convention where necessary. Any toolchain/testdata or
corpus-harness edit needs a separate reviewed scope extension; no duplicate
production modules, compatibility roots or handwritten metadata.

Shared examples/programs/.mo.ids regeneration remains lead-owned. Preserve the
original evidence cap; request a concrete change before exceeding it. Keep every
failed attempt and real exit. Final report remains REPORT.md, committed last
only after all named worker work and cleanup finish; no acceptance by worker.

#### Static review and bounded fixture grant — 20 Sep

The first chunks diff and all three new drivers are reviewed statically;
`git diff --check` passed. **Correctness execution remains withheld**, as do
benchmarks, commits, final report, machine and Linux. Runtime is unassigned. Raw
diff, new-file snapshots, manifest and decisions are preserved in
`audit/evidence/2026-09-20/server-chunks-static-review-01.json`.

Authorize static edits to **examples/programs/workspace-server/strict.mo**,
**toolchain/src/corpus.zig**, and the existing owned validation matrix. Move
only the seven strict process tests, importing the real production modules. Keep
the three fault-tolerant tests in ordinary corpus coverage; do not create
faults.mo, duplicate production modules, change the loader or add a root. Any
generic simulation exclusion must name only this exact strict fixture, with a
mandatory permanent gate for its exact positive count, zero skips and failures,
zero-fault seeded simulation, successful interpreter/native parity and
formatting. Reuse checkContractFixture and preserve ordinary/Step44 gates. Keep
generic formatting/check/native coverage where feasible. Preserve every
behavioral assertion; declare any count change needed to retain private pure
checks without exporting production helpers solely for tests.

Source binding uses the existing workspace_controller.digest convention over the
base64 source mapping: SHA-256 of sorted-key, compact JSON. The operator remains
trusted; insertion-ordered protocol.encode is not a canonical mapping digest.
Require an independent known-vector journal check and key-order invariance, not
journal-versus-config self-comparison. Retain hostile-tree readiness/refusal
coverage. Drop incidental settings-field-copy and exact-error wording
assertions; keep malformed-hash rejection behavior.

The revised manifest must begin with a fresh guarded compiler build in this
worktree, with an explicit deadline and4GiB; cloned zig-out is not proof. Finish
and review classification before running mixed simulations. List exact expected
counts and fault settings; stop on failure and retain every attempt. Benchmark
preparation may retain disclosed16-call batches for1000 calls, but must check
exact read contents/search rows, not only lengths/counts. Python's test owner
does execute real file tools; its machine lifecycle remains scripted. Return the
revised static diff/manifest for review before any execution grant.

#### Correctness grant01 — 20 Sep

Review02 accepts the revised **scope**, not server behavior. Strict7 now has
fixed-order generic coverage plus the mandatory100-seed zero-fault gate; generic
load/check/format/native coverage remains. The other35 tests retain ordinary
coverage, including three fault-tolerant process tests. The known source vector
was independently checked with system SHA-256.

**server-chunks-sol owns the exclusive runtime slot for exactly24 sequential
correctness commands** in `server-chunks-correctness-grant-01.json` under
`audit/evidence/2026-09-20/`. Stop on the first nonzero exit, unexpected actual
count/classification, guard kill, scope change or other surprise; no repair or
rerun without review. Printed expected counts are not measured evidence.
Command12 uses the uniquely matching `corpus: every module` filter to avoid the
original shell command's unescaped apostrophe; it selects the same gate.

Only the approved formatters and real --write may modify source during this
batch. Generated worktree-local examples/programs/.mo.ids may remain as an
unstaged check artifact for lead review; integrated generation/staging stays
lead-owned. Historical F1/evidence and REPORT.md stay byte-preserved; stop if a
generator changes them. Retain every attempt and real exit within the2MiB cap,
then report owned-process/port/build-output clearance. Benchmarks, unfiltered
suite, Step42 execution, machine, Linux, commits and final report remain
withheld. This grant conveys no acceptance.

Grant01 stopped at command2: fresh compiler build passed0/37.9s; formatter
passed seven modules, then rejected the first of three positional HeadDone
patterns with MO0101. No guard kill, repair, retry or commands3–24 followed;
scoped clearance is recorded in correctness-result-01. Historical files and
parent metadata remained unchanged. **Grant02** permits only those three
patterns' existing head/reading labels, fresh chunks2-format-02, then
unattempted commands3–24 under the same first-surprise rule. Reuse the passing
unchanged compiler. No broader repair or benchmark permission is implied.

Grant02 also stopped at formatting: attempt02 failed MO0102/0.3s on the
assertion split after `==` at connection.mo464–465. The named-pattern repair was
applied; no later command or other manual edit ran. **Grant03** permits only
joining that assertion without changing its operands/expected refusal, then
fresh formatter attempt03 and unattempted commands3–24. Both failed logs remain;
scoped clearance and40KiB total evidence are recorded.

Grant03 joined only that assertion. Formatter03 passed all15 modules,
exit0/0.5s. Command3 fmt-check then failed strict.mo97 MO0501 after fourteen
modules passed; commands4–24 remain unattempted. Protected paths are unchanged,
no owned process/port remains, and72KiB raw evidence is retained. Runtime is
released. Source review found that `pipeline.loopFindings` checks isolated
source while the loop rule needs imported handle types. A static repair is
authorized in program/pipeline/main/corpus and existing FORMAT documentation:
load imports for typed analysis, report only the requested file, preserve global
diagnostic/fix coordinates and one-file formatting, and cover imported effects
versus genuinely pure loops. No assertion rewrite, lint suppression, runtime
grant or acceptance. A rebuilt compiler and focused regression proof must
precede any resumed batch. Exact brief and raw results:
`audit/evidence/2026-09-20/server-chunks-formatter-review-01.json`.

The first formatter patch's static review found two issues: fixture strings
lacked the canonical final newline, and skipping a stopped import load also
skipped genuine requested-file pure loops. Both are corrected in the revised
source. Existing `program.single` preserves best-effort requested-file analysis
when imports cannot load; global coordinates follow the actual checked Program.
The regression covers imported effects, pure-call location, dependency-only
isolation and both pure/clean targets after an invalid import.

**Formatter verification grant01** permits exactly four serialized guarded
attempts: compiler-build02, fmt-regression01, fmt-strict01, fmt-check02. The
last is the complete15-module matrix, not just the strict smoke. First surprise
stops; original commands4–24 remain withheld. The rejected ulimit/timeout
proposal is replaced by existing evidence.py/guard.py capture with4GiB. Exact
argv: `server-chunks-formatter-grant-01.json` under the same evidence directory.
This is verification permission, not acceptance.

Formatter grant01 passed all four checks: fresh build0/38.4s, focused2/2 in3.8s,
original strict smoke0 and full15-module fmt0/0.6s. Protected hashes matched;
runtime was released. Grant04 resumed original4–24 but command4 stopped before
wire tests: MO0317, no recorded verification line. The fresh parent sidecar had
no workspace-server entries.

Grant05 promoted only the existing dependency-ordered command7 generator. It
proved wire5/schema6/envelope5/tools6/journal1/admission2/worker2: **27** tests,
no failures/skips. Admission's one process control held under200 seeds at5%
faults. Seven parent records were generated unstaged; wire/admission/
journal/worker footer bytes changed. Connection then stopped before tests or
write at MO0304 in scanned74, head_step130 and Connection.update290. Protected
historical files stayed byte-identical; evidence652KiB and no owned
process/listener/temp remained.

Static correction is bounded to connection.mo, preserving all assertions,
framing/state transitions and the three-level language limit. Continue
generation from that module only after review; do not repeat seven unchanged
successes. Full42 and all remaining gates remain open. Exact strict counters are
tests7/simulated7, held_under_faults0/fault_free_only0 at faults0; earlier
informal “7 held” wording is not a counter requirement. Raw result04/05,
grant04/05 and nesting-review01 records are under the same evidence directory.

Nesting correction source review accepted equivalent marker cases, one
coalesced-header helper and one authenticated transition helper. A second review
removed the remaining fourth-level phase/ids expressions by guarding the Chunk
case arm; the fallback still closes only a running connection. Runtime proof
remains outstanding. Grant06 failed immediately, exit2/0.0s: the lead
incorrectly supplied fmt --write. The CLI reserves --write for test; plain fmt
writes by default. No source/footer/sidecar changed, no generator ran; seven
records/27 tests remain. Evidence664KiB and runtime clearance were reported.
Preserve this command-error RED. Grant07 corrects only the formatter invocation,
then permits the eight unrun generators under the same stop, protected-byte,
real-counter and resource rules. Server alone owns runtime.

Grant07's default formatter passed and rewrote connection.mo. The first
generator then stopped before tests at MO0303: head_transition had9 parameters,
over the limit6. Nesting diagnostics no longer appeared; no new verification
record was written. Subtotal remains27/seven records; protected hashes matched,
evidence684KiB, runtime released. The bounded static correction removes the
helper and places the existing gate Check in a HeadDone guard, followed by an
unauthorized fallback. This preserves one ask and depth3 without a context bag
or extra transition tuple. The other seven targets remain unrun.

Grant08 completed all nine commands: default formatting plus the remaining eight
generator targets. Raw remainder15/0/0 plus retained27 gives **42/0/0**: 35
production, three simulated/held at5% faults; strict7 simulated at0% faults.
All15 parent records now exist unstaged. Protected F1 source stayed identical
even as a generator target; all protected hashes matched. Evidence788KiB, no
owned process/listener/temp remained, runtime released.

Grant09 resumes exactly original4–6 and8–24, twenty commands, with fresh
standalone-test attempt02. It does not repeat generation. Actual standalone,
strict/seeded, final-format, four corpus, three-build,
inherited/unchanged-client/ hostile/EOF/direct-filesystem and size results are
still required. Server has the exclusive runtime slot, first surprise stops, and
no benchmark/full-suite/ memory-runtime/commit/report permission follows
automatically. Raw result08 and grant09 retain the evidence and exact argv.

### EOF and delivery decision (lead, 19 Sep, evening)

Step 44 stays unchanged. `Closed` reports input termination, not whether the
peer kept its read half open. `Conn.write` success is local completion, not
proof of client receipt (the existing wire contract already says this). Do not
require the runtime to infer a stronger distinction from TCP EOF.

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
  operation still receives the response, preserves operator access and allows a
  later request if no other terminal limit was reached.
- H6/D2 controls: a graceful full-close client leaves exactly one execution and
  a retained outcome/produced reply, with receipt unknown even if write
  succeeds; the operator can still inspect, freeze and close. Separately force a
  reset/write-failure path and prove terminal admission with the same retained
  execution and operator access. The client driver knows it did not read the
  response; the server must not claim it can observe that fact.

The inherited Python `disconnect` and `lost-response` groups require owner
process exit after candidate close (`local.py:250-256,289-296`). That lifecycle
predicate conflicts with required D2 operator independence; retain those tests
unchanged as Python regression evidence, report their Mo incompatibility, and
add named Mo-specific H2/H6/D2 controls above as the acceptance oracle for those
two groups. Preserve their substantive outcome/cleanup obligations; explicit
operator close proves cleanup in part A's local scope, not machine cleanup. Do
not claim all 13 inherited groups green when two use a different lifecycle
oracle. This is an explicit lead decision, not a worker test waiver.

## Write scope

New: `examples/programs/workspace-server/**` (Mo sources, their tests, sidecars
and `verified:` lines by real tools only, a README, the behaviour runner and
evidence under 2 MiB). In `toolchain/harness/executor/workspace_http/` only what
lets the existing behaviour tests aim at another server: a target option in
`local.py`, and no change to what any test expects. No other harness file, no
toolchain, no wiki, no `audit/`, `HANDOFF.md`; no machine, Docker or `/opt`; no
push. Never use `tr`; `ls` is aliased, use `/bin/ls`.

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
   code used for an oversized body; codes no path produces; `admission_closed`
   overwriting other refusals), the Mo server follows the contract, and the
   report lists every such difference.
2. **Findings closed by design, not patched:** H1 (a slow file operation must
   not end the run: the wait and the work share one deadline); H2 (a legal
   half-close is not pipelining); H3 (no descriptor reuse race: a connection is
   owned by one process from accept to close); H4 (output past a bound is
   `truncated`, never `output_encoding`, and the bound is documented); H5 (a
   success without its required field is `invalid_result`); H6 (a client
   disconnect is recorded as delivery unknown, never as `owner_unknown`).
3. **End to end v1's D2.** The operator's path (freeze, verify, close, read the
   journal) is independent of every candidate connection: a candidate that
   disconnects, stalls or floods cannot close or starve it. Shape it as a
   separate process with its own handle, given only to `main`'s operator side.
4. **Four observations, never one success count** (research PR 14): for every
   call the journal records admission, execution, the reply produced, and
   separately whether delivery is known; cleanup is its own record. A reply that
   could not be delivered keeps its true outcome.
5. **Obligations bound by hash** ([[bend2]], idea 1): the journal's first row
   binds the run to the hashes of the source mapping and of the operator's
   verifier configuration; a verdict names those hashes. Part A only records and
   checks them; the protected verifier itself is part B's.
6. **Capabilities as the fence.** `main` narrows: the workspace folder is one
   `Fs` scope (step 40 makes it hold against links, FIFOs, hardlinks and setuid:
   reuse its refusals rather than re-deriving `workspace_files.py`); the journal
   is another scope written only with `Fs.replace`; the token never enters a
   process that holds the workspace scope's candidate-facing handler state
   longer than the comparison needs; nothing below `main` holds `Platform`.
   `flows` rules state that the token never reaches a reply or the journal.
7. **Processes.** One admission process (one operation admitted, no queue, 16
   calls, the 900 s lease), one journal process, one process per connection, the
   operator process; supervisors that restart a crashed connection handler
   without losing the journal. Every wait has `within:`. `mo test --sim` with
   faults must hold the invariants: at most one call admitted; the journal's
   intent precedes every effect; a duplicate call id executes once.

## Parts

A. **RED first.** Aim `local.py`'s wire-level groups at a server by address
(`--target`), run them against the Python service (green, the baseline) and
against a stub Mo server (red), and commit both outputs. Groups in scope for
part A: six-tools (the five file tools; `command` answers the contract's refusal
for an operation this server does not serve, stated in the report), schema,
framing, byte-bounds, identities-capability, duplicate-calls,
concurrent-admission, file-refusals, deadlines, disconnect, lost-response,
journal-order-bound, shutdown. The rest are part B's. B. **The server**, in
`mo run` and as a `mo build` binary, until those groups are green in both, plus
new tests for requirements 2 to 5 that the Python cannot pass (say which of them
fail against the Python, as the measure of what changed). C. **Hostile
filesystem cases** from `test_workspace.py` (symlink at the last and a middle
component, hardlink, FIFO, setuid, lexical escapes, `exact_edit` with missing,
multiple and empty matches leaving bytes unchanged) against the Mo server's
workspace. D. **The size table** ("The size question" on [[mo-harness-in-mo]]):
with one committed script, non-blank non-comment lines of `bridge.py`,
`owner.py`, `protocol.py`, and the parts of `workspace_controller.py` and
`workspace_files.py` this replaces, against the Mo sources; test lines
separately; features dropped or added listed, so a smaller program that does
less is not a win.

## Numbers

Best of five, both runtimes, load average beside them: a `read_file` of 1 KiB
and of 60 KiB, a `search` over 200 files, and 1,000 sequential small calls, each
against the same from the Python service on loopback.

## Done when

Every process under `toolchain/bench/step36/guard.py`; **every run the report
quotes is teed into a filed log with an exit file beside it**, under the
program's `evidence/`. The in-scope groups green against the Mo server in both
runtimes with real summary lines and exit codes; `mo test` and
`mo test --sim 200` on every module; `mo fmt --check`. **The unfiltered full
suite, Linux and the machine are the lead's.** RED before GREEN; small commits
as yourself with a `Co-Authored-By` line naming your model. **Write your final
report to `examples/programs/workspace-server/REPORT.md` and commit it last,
with a clean worktree.** While anything runs, wait in the foreground rather than
ending your turn. Decisions the brief did not cover go in the report.

## Related

- [[mo-harness-in-mo]]
- [[mo-harness-end-to-end-v1]]
- [[interpreter-step-41]]
- [[bend2]]

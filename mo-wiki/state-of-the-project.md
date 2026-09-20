---
title: "The state of the project"
created: 2026-09-16
updated: 2026-09-20
type: synthesis
tags: [roadmap, research, thesis]
sources:
  [
    spec/design-v0/01-premise.md,
    spec/design-v0/08-milestone.md,
    plans/roadmap.md,
    decisions/decision-log.md,
    CHANGELOG.md,
  ]
status: living
---

# The state of the project

The forest, not the trees. This page is the lead's standing account of the whole
Mo project: where it came from, what it claims, what has been tested, what
turned out right and wrong, and what is left. It is rewritten at every pause;
the date at the top is the last one. The trees are one link away: the maps under
[[the-thesis-and-its-evidence|maps]] gather the pages behind each sentence
here, and the [[roadmap]] table is the authority on order.

**Current, 20 Sep 2026, 8:30 AM ET:** Astra leads this OMP session; every
code assignment starts a fresh Sol/high worker in a separate worktree.
[[interpreter-step-44]] is accepted on Darwin, merged locally at **db515f9b**
after independent verification of cdf1e966: build, focused5/5, **272/272**
full-suite tests (exit0,629.86s), and30 additional CLI/socket commands.

`Conn.chunks` delivers bounded owned binary messages through existing runtime
sources. Both runtimes preserve exact bytes and half-close replies, refuse
conflicting readers/late TLS, and make input progress while a write remains
blocked. The unchanged HTTP client receives200 before newline/shutdown; an
unfinished oversized header receives431. Strict TLS success and its negative
control stay separate from the seeded-fault oracle. All12 fixture controls
remain automatic in toolchain testdata; ordinary corpus fault gates are intact.
Earlier full-suite failures270/271 (classification) and271/272 (generated
catalog) remain filed, not hidden.

Twenty larger interleaved line measurements show interpreter elapsed
best/median **+3.36%/+4.83%**, native **+10.25%/-4.41%**. The interpreter is
slower in this run; native best and median disagree. All samples/load averages
and original16MiB measurements are retained. No zero-overhead or causal claim.
The existing --surface diagnostic line offset remains unfixed.

Step42 remains unaccepted. Frozen65b3dd37 is input to a provisional
accepted-main4e0bfc0e composition; source conflicts are resolved, not verified.
Revised lifetime controls expose paired counts and complete payloads. A known
enqueue error-ownership hole blocks AFTER freeze. Private patch context is
rebased; bounded ownership and native/test quality corrections are source-only.
All seven obligations remain: current normal/raw-ASan exhaustive sweeps,
small ASan and ordinary stale-answer mutants, packed lifecycle/reclamation proof,
hot-path analysis, and lead-owned best-of-five suite timings. Its60 corrected
runtime samples compare two unaccepted checkpoints, not the whole step's cost.
Independent integration and the required stress timings are still owed.

The source capability unblocks a fresh server-adoption assignment, not acceptance
of the six-tool server. Its original F1 timeout remains historical evidence;
full-wire and operator-cleanup predicates are not weakened. Linux remains
deferred. Step39, Program7, full-sync durability and catch claims are unchanged.
No live-provider/model-driven task/Pi-comparison acceptance. Nothing pushed or
published to the auditor by this acceptance.

The fresh server consumer in `harness/workspace-server-chunks` at65f2eca0
combines accepted main with saved serverd689b441. Its shared formatter repair
passed a fresh build, focused2/2, original strict smoke and full15/15 matrix.
Dependency-ordered generation now proves **42/42** tests:35 production and7
strict; production's three simulated controls held at5% faults, strict's seven
ran without faults. All15 sidecar records exist, unstaged. Connection nesting
and arity repairs passed; protected F1 bytes stayed unchanged. Earlier REDs,
including the lead's invalid fmt flag, remain. Grant09 gives the server sole
runtime ownership for the remaining20 correctness commands—not benchmarks,
an unfiltered suite or acceptance. Step42 remains source-only; composed
normal/ASan/mutant/reclamation and timing proof is still owed.
The completed Step44 pane is retired; evidence and worktrees are preserved.

The account below preserves the earlier checkpoints.

**19 Sep, the day so far.** Robert made Fable (Claude Code) the lead at 7:18 AM
ET, with Claude Opus workers, and asked for three things: review what Astra
built overnight, fix what the review found, and write as much of the coding
harness in Mo as possible "to really test Mo", leaving Python and JavaScript
only what their roles need. He also decided Mo gains a child-process capability.

The review (four Opus reviewers, sceptical by brief) found the overnight code
sounder than its records suggested and the acceptance weaker: lead, workers and
reviewers had been one model, and it had accepted five tests that cannot fail
and two that assert a defect as intended. All ten components were kept and are
being fixed. Accepted since, each after the lead's own runs: the application
workspace rebuilt from scratch (the Mo agent routes all six tools to the
workspace service); the executor's two serious defects; the Mo agent's tests
made able to fail and its budget rule made one rule; the harness's live suites
as tables; **a use-after-free in both Mo runtimes**, found by the rebuild and
fixed (any Mo program answering a kept ask after a large update could receive
freed memory); and step 40, which makes a narrowed `Fs` refuse links and adds an
atomic write. The full suite stands at 249 of 249 on the Mac; Linux runs now
happen on Robert's Linux VM, whose first use caught a Linux-only test bug.

What is not true yet: the harness has never run whole. A worker is doing that
now (the Mo agent, a scripted model, the real service and containers, then a
scripted repair of Logstat), and another is building `Exec`. The Python has not
shrunk (6,688, 6,326, then 6,643 counted lines); whether Mo needs less code for
the same features is to be measured module by module as they move, not claimed.
The plan is [[mo-harness-in-mo]]; the design of the new capabilities is
[[mo-capabilities-for-the-harness]]; `HANDOFF.md` has the working state.

**Before that, 6:38 AM ET (Astra's last update):** workspace HTTP accepted; Mo application routing next.

Robert has authorized Astra to lead continuously while he sleeps and make the
necessary decisions. Fresh Astra workers run at low reasoning in Herdr panes,
with separate implementation worktrees. The lead independently verifies results.

The terminal-401 policy, offline provider and BusyBox executor were published
at 2fc1235 with successful wiki deployment. Workspace acceptance now adds 27
unit tests, 22 live workspace controls, 17 executor controls, lifecycle and two
lead extras. Owned cleanup is empty; shared Mac Docker IDs/states stayed unchanged.

[[mo-coding-fixture-v1]] passed the full integrated suite at e6f04ce: 243/243
tests and 5/5 steps. Both runtime matrices, exact legacy CLI goldens, cancellation
controls and six lead extras pass. Real cancellation/native report-race failures
and a cold-runner false-pass defect were reproduced, corrected and retained.
Cancelled totals are unknown while recorded per-call usage is preserved.

[[mo-provider-auth-v1]] passed 28 offline auth controls, 28 provider regressions
and two lead cleanup probes. A real late-response-body cleanup defect was found
and fixed. All credentials are synthetic; live subscription login, registration,
account/model entitlement and inference remain unverified.

[[mo-provider-bridge-v1]] is independently accepted:27 protocol groups, actual
Mo in both runtimes,28 foundation regressions and two extra HTTP controls pass.
Full integrated suite 243/243 and 5/5 passed; source bytes and cleanup are checked.
Each Mo run records and replays native provider history with Book observations;
commands are still inert fixtures.

[[mo-application-build-v1]] independently passes actual image-content checks,
23 runtime groups, old workspace/executor regressions and an extra cold snapshot
build. Hello and Logstat execute within unchanged resource limits. Cleanup of
68 executions and 34 workspaces is confirmed; shared Mac containers are unchanged.
The first full suite retained a TLS echo TCP-count mismatch, 242/243; ten
focused runs and the fresh full rerun pass, 243/243 and 5/5. The originating
client is unknown; no fix is claimed. This bounded application slice is accepted.

[[mo-workspace-recovery-v1]] is independently accepted: local59/schema21,
recovery16, existing workspace/executor/application regressions and an actual
lost cleanup response control pass. Full suite243/243 and5/5; all11128 tracked
files unchanged. Cleanup proves84 executions/57 workspaces/76 cgroups absent,
parents empty and shared5 unchanged. Earlier malformed snapshot and TLS failures
remain unexplained. Two reboot-lost outcomes remain API-unresolved despite
separate authorized physical cleanup; this is not whole-machine recovery.

[[mo-workspace-http-v1]] is independently accepted atcf99cd88: local22/inherited59,
realHTTP22 per profile, existing runtime regressions, review controls and two
extras pass. Full243/243,5/5;17339 files unchanged. Cleanup rechecks100 executions,
131 recorded workspace IDs and97 cgroups absent,34 local groups gone, active
parents empty/shared5 unchanged. Drain/IPC corrections and evidence limits remain
recorded. [[mo-application-workspace-v1]] and scripted Logstat repair follow;
language value and matched Pi comparison remain unmeasured. The last published
recovery checkpoint68e50ed6 and wiki35432372898 passed.

Historical worktrees and the private transfer package are present, and the
arrival auditor pointer check found zero new records. Arrival/setup observations
are under `audit/evidence/2026-09-18/mac-arrival/` and
`audit/evidence/2026-09-19/executor-readiness/`. Older orb fixture results remain
historical; the Mac acceptance is separate. Step 39 remains unaccepted and
Program 7 suspended. Current order and worker receipts are in [[roadmap]] and
`HANDOFF.md`.

The final review labelled DeepSeek was byte-identical to the supplied Kimi body,
verified by comparison and SHA-256. Four distinct review bodies, not five; the
reason for duplicate attribution is unknown.

## Historical pause, 19 Sep 2026, afternoon (resumption authorized above)

Robert paused the project until his usage limits return. Everything accepted is
on `main`; two workers were stopped at a checkpoint with their work committed as
WIP on their own branches (nothing of theirs is on `main`).

**What the afternoon added (the Fable lead, Opus 5 workers).**

- **The Mo agent ran end to end on the machine for the first time**, in
  `mo run` and as a binary: six tools through the real service and real
  containers, the scripted Logstat repair RED then GREEN, a protected verdict
  that refuses a forged success and a rewritten test, every workspace proved
  gone. A scripted model: plumbing, not model ability.
- **`Exec`** (step 41): Mo runs child processes, narrowed in `main` to fixed
  commands. Accepted on macOS; its Linux fork path is owed a run.
- **The auditor's repository audit (PR 15)** conceded whole and fixed the same
  day (step 43): a sized literal past its type reached both runtimes, and a
  54-digit literal silently became another number. Every number read from
  source now goes through one exact reader.
- **The agent's report cap** lifted to a bound the profile derives, and a late
  command's reply is no longer lost (defect D1), seen holding on the machine.
- **TypeSafe's Jev** tried as a check of worker reports against raw logs: 73
  requests, a third of a cent. Code caught nearly everything it caught; the
  model added little on this evidence. Acceptance does not depend on it. The
  lasting change is in the briefs: every quoted run is filed as a log.
- **Research PR 16 (Bend2)** merged: obligations bound by hash and
  status-bearing receipts go into the Mo server's design.
- Full suite: 268 of 268 on Darwin. Linux: 263 of 263 on the tree before step
  41; Robert then deferred Linux runs (a "Linux owed" list is in `HANDOFF.md`).

**Stopped mid-flight, as WIP commits:** the Mo six-tool server, part A
([[mo-workspace-server-4a]]), and runtime memory safety
([[interpreter-step-42]]). Briefed and not started: the CI gate ([[ci-gate]]).
Not written: part B of the server (the machine, `command` through `Exec`,
cutover).

**Waiting on Robert, on the decision log:** whether to patch the Python
service so a verdict survives a client disconnect (D2) or wait for the Mo
server; `-128` as one literal; `in_folder` versus `in`.

**Unmet, said plainly:** no live provider and no model-driven task yet;
Python has not shrunk by measurement; step 39 (TLS) unaccepted and its corpus
test still fails about 1 run in 5; Darwin `F_FULLFSYNC` unmet; Program 7
suspended; two power-off checks on the machine owed; no CI gate.

## Agent-native direction agreed; bounded implementation now authorized

Mo is a functional, statically typed, compiled, BEAM-inspired option, not a
replacement for Elixir/Erlang. Agents are its intended code authors and readers;
humans judge requirements, behavior and evidence rather than reviewing source.
The primary product is the fast, trustworthy discover/learn/edit/check/run/
inspect/repair/verify loop. Improve that loop for existing features before
expanding the language, except where a missing capability blocks a
representative application. [[01-premise]] is the current thesis;
[[decision-log]] records Robert's decisions, and [[roadmap]] separates the
discussion queue from proposals.

**Program 7 is suspended. Its BEAM-superiority thesis and runtime-claim
retirement framing are superseded prospectively, not passed.** Sealed specs,
audit rules and evidence remain untouched historical records. Correctness and
safety obligations are not waived. The capabilities rule and generation-ten
contract-catch rule are not retired by this decision. Replacement program-7
scope and acceptance criteria remain open and must be versioned before use.

The core language remains; no wholesale syntax redesign is authorized. Plain
source plus targeted semantic tools, version-correct just-in-time guidance and
runtime inspection are the direction. Structured diagnostics, fixes and an HTTP
runtime surface already exist; the complete proposed agent interface does not.
Both cold and minimally guided onboarding should be evaluated, with broader
affordable/open-weight model evaluation later. Cheap-model reliability remains
unproven; prior cross-model failures are retained, not explained away.

The four reports are now preserved and reviewed with the oracle in
[[agent-native-research-synthesis]]. Selective primary-source checks found
overstatements; compilation gains do not establish behavioral parity, semantic
edits do not prove correctness, and implementer-authored evidence is not an
independent verdict. The evidence attachment calls itself an auditor draft and
was read in the batch before a new independent reading; this is not a cold audit
reading and its proposed gates are unratified.

Robert agreed to discuss a bounded maintenance task first. The proposed Agent
authentication-error change, onboarding comparison and small model pilot remain
open. [[agent-native-independent-review-prompt]] equips outside models with web
access to challenge everything, including whether a new language/runtime is
justified. Review evidence and reasons, not vote counts. Specific law changes,
program-7 scope, TLS strategy and acceptance thresholds remain proposals. That historical implementation pause is superseded by Robert's overnight
authority above; bounded readiness and independent acceptance still apply.

At the preceding review checkpoint, four external strategic reviews were
compared with the oracle in [[agent-native-research-synthesis]]. Robert agreed
to narrower investment: trustworthy instruments, a 401 workflow/onboarding
calibration pilot, then a useful application against one well-equipped
existing-language comparator. The pilot does not establish language value. A
versioned retry-policy approval is a prerequisite. The application is now chosen
above; the brief recommends an Agent-specific policy, with its exact recipe
binding still to be resolved. Keep requirements, implementation and trustworthy
acceptance distinct, and consider required progress and uncertain external
effects in the later workload. Extraction remains an option, not the chosen
destination. No bounded start or lead-readiness confirmation is recorded; the
execution pause remains.

Step 39 remains unaccepted and the known acceptance/durability obligations
remain. New upstream TLS and benchmark edits were fetched, not verified in this
documentation session; the checkpoint counts below must not be represented as
fresh measurements. The private environment restoration is still unverified.

## Historical account below

The earlier thesis, queue, claims and observations below retain their dates.
They do not supersede the current direction or authorize work to resume.

## PR 12 reviewed; acceptance evidence still needs repair

Robert authorized Amp as lead in the Linux Amp orb. The lead published its
reading before opening the auditor's conclusions, then merged PR 12 unchanged.
The comparison is `audit/fable-comparison-2026-09-18-current-state.md`. No
implementation or retirement rule was accepted or changed by the review.

The audit's certificate and ALPN failures predate step 39 A/B; their saved
worker outputs now pass those specific cases. **Step 39 remains unaccepted**:
Limbo is still 27 against zero, C/D are WIP, E/F unstarted, and independent
acceptance is owed. Fresh unchanged harness probes at 5:28 PM ET reproduce
false-success paths on current main: failed/timed-out suites return success,
mocked failed stimuli score 20/20, a failed fuzz batch is reported as zero
crashes, and an invalid category selection exits successfully with zero checks.
These show broken instruments, not a newly observed TLS or application failure.

**Program 7 is not ready for its binding comparison.** PR 12 adds explicit
reconciliation of R2's fault regime, RC1's timing endpoint, and R4's
hundred-edit requirement to the baseline/skip-list and auditor-seal gates.
Recommendations are in [[decision-log]], not silently applied amendments. Lead
orientation also identified binary-safe input and snapshot/log replay gaps; the
directory-sync durability boundary remains unresolved. Repair and negatively
test acceptance instruments before relying on them, and add a compiler/corpus CI
gate rather than treating a wiki deployment as one.

No worker or comparative run has restarted. The orb's private transfer and old
worktrees are not verified as restored; Herdr is not on PATH. The move
checkpoint below still holds for code, saved WIP, and Mac-only verification
obligations.

## Paused for Robert's move, 18 Sep 2026, 4:33 PM ET

Robert asked to wrap the worker up ASAP and will move the project himself.
Codex (GPT-6) ended the worker after preserving its report and checkpoint:
Step 39 parts A/B pushed, C/D as a patch, E/F unstarted. **Step 39 remains
unaccepted**: the worker's limbo count is 27 against the required zero, the
part-C abuse run is 63/64, and the lead's own acceptance has not run. Darwin
full-sync remains unimplemented and its Mac-specific proof is still owed.
The verified transfer package includes all local branch refs, local-only
files, the worktree inventory and intake ledger; `HANDOFF.md` is the entry
point. No timer or worker remains, and the queue is stopped for the move.

The completed OrbStack Linux Redis baseline is preserved and published:
22 files attempted, 909 ok, 5 err, 22 ignored, 3 exceptions and 3 timeouts.
Two exceptions show leftover background activity on the reused server;
fresh-server checks and the skip list remain owed. Program 7 still waits
on the auditor's sealing session.

## The morning of 18 Sep, in one screen (read this first)

The auditor read five subjects and the lead conceded every finding; three of
them are the lead's own errors, and one runtime finding is new.

- **The TLS brick is not complete.** Two independent auditor sessions made
  real handshakes through the brick and showed its client accepting four
  certificate chains OpenSSL rejects (a path-length violation, a CA without
  signing rights, a client-only leaf, an unknown critical extension). Also: a
  valid ALPN overlap past 64 names fails, the fuzz count can hide a failed
  batch, and `tls-client.mo`'s tests pass with the handshake replaced by a
  `Timeout`. [[interpreter-step-39]] is the correction, gated on the
  auditor's own script; it was started at noon and stopped for this pause.
  Program 7 is not blocked (`mored` verifies no chain).
- **Generation six ran and the laws were silent a sixth time.** Nothing
  eroded; Mo's generation-five defect was fixed from a ticket; Mo's lease path
  is back to its change-3 rate. Read strictly, as the auditor read it: P1 not
  met as written (Mo carries one real validation defect since generation
  three), P3 and P4 and P6 failed, P7 void (the spec named the cause), time
  and loops comparable with nothing. **The language rule's ledger: zero
  catches at six of ten generations, threshold two.**
- **The lead's instruments failed three times and an outsider or a rerun
  caught each.** The sealed seventh suite had never been run and started
  every server with an illegal flag; generation five's third-suite column was
  never measured (a usage error the runner swallowed); a round-8 fixture
  writer never wrote the illegal record for Python, so a "carried Python
  defect" was the harness's for ten generations of suites. New rules: a suite
  is smoke-run on the previous generation, and read by the auditor, before
  its seal; runners write every exit status; a mutant per new corpus test
  file, run at least five times at one core and at many.
- **On macOS, Mo's "on disk before `Ok`" is not on the disk.** Both runtimes
  call plain `fsync`; Go uses `F_FULLFSYNC`. Every Mac speed comparison with
  Go is withdrawn; the Linux ones stand; the fix is in step 39.
- **Step 38 accepted** (a `Conn` that reads while a write on it waits,
  `TCP_NODELAY`, 64 handshake abuse cells), which is program 7's pipelining
  prerequisite.
- **Program 7's spec has a revision 2** ([[07b-redis-subset-revision-2]]),
  published to the auditor. The next thing only Robert can do: open the
  auditor's sealing session on it.

## In one paragraph

Mo is a programming language for a world where agents write nearly all the code
and people read only the parts that state intent. It was started on 12 Sep 2026
by Robert Guss and Claude, designed in a day, given a working toolchain in the
next, and then put under a measuring regime that has not let up: ten control
rounds against Go, Python, and Elixir, two of five planned measurements, five
generations of a maintenance experiment, and two outside reviews. The thesis
survived being restated once, on the review of 14 Sep, and the restated form is
what is being tested now: **software written by agents can be reliable and need
no third-party code, and a runtime and process model built for that, with
capabilities and recipes on top and the language as their surface, delivers
it.** The claim under test is a conjunction, reliability at zero dependencies.
So far Mo holds the reliability column against every baseline in five of six
hidden suites and lost it by one in the sixth, holds the feedback loop every
time, holds the dependency column by construction, has lost the speed column to
Elixir and, in one generation of maintenance, to its own maintainer, has
answered the BEAM's restart row, has built the first two bricks of its shelf at
zero dependencies (crypto, 17 Sep; a TLS 1.3 brick, server and client, 18 Sep,
**whose client the auditor showed accepting certificate chains it must refuse:
not complete until step 39**) so that program 7 can be written, and has sealed program 7's spec, and has not yet shown that its laws catch a bug an agent's own
tests would miss: six generations of changes, four of them
written to press on a law, and no `never` has tripped on a wrong edit. That last
sentence is the one the project turns on.

## Where it came from

**Sessions 1 to 4, 12 Sep.** A wiki of 35 directions, 17 questions, 15 syntax
picks, and 13 language comparisons, then an eight-chapter design in prose
(`spec/design-v0/`) and a grammar. The premise at the time: agents write the
code, humans read the spec altitude, the compiler is the teacher, and every
third-party package is code nobody read. Syntax: Elixir-shaped under Ruby's
taste, `end`-closed blocks, one formatter answer, no classes, immutable values,
capabilities as parameters, contracts and `never` clauses in the source.

**Session 5, 12 to 13 Sep, about twenty hours.** The design met a compiler. In
four worker steps an Opus session built a lexer, a parser, a type and law
checker, a bytecode VM with contracts and tests, and a simulator with seeds and
faults; the interpreter milestone (chapter 8) was met the same day. Then a
formatter, `mo run` with a platform, a standard library of 118 rows, `Net` and
`Http`, a C backend giving static binaries, and processes in both runtimes. The
first real programs, a log analyzer and a key-value store, found the toolchain's
bugs and the stdlib's gaps, and the first control runs began: the same spec
written in Go and Python by the same model, timed. Mo took two to three times
longer to write and cost more loops, almost all of them the language's own
grammar and laws.

**Session 6, 13 to 15 Sep.** Programs 1, 4, 5, and 6 (a durable job queue, a
notes service, an agent harness, a double-entry ledger), each finding two to
four toolchain bugs and several gaps, each followed by a step that closed them:
the derived deadline, the runtime surface as a capability, processes as green
threads, delayed sends, handles in state, writes in place, a `never` that reads
values at rest. Rounds 3 to 6 kept measuring agent time and loops, and round 6
failed on all four of its predictions. Two outside reviews (13 and 14 Sep) and
the research agenda's seventeen "contradicts Mo" ideas were each answered on a
page. On 14 Sep Robert restated the thesis: agent time was never the point,
since no model has seen Mo; the runtime and the process model come first,
capabilities and recipes second, the language third; and the measure from round
7 on is reliability under a hidden defect suite, native speed and memory, the
feedback loop, and the dependency count. The counted shape laws became project
settings in principle. Round 7 was the first round on that measure, and it held
on all four.

**Sessions 6 and 7, 15 Sep, on the VM** (the changelog's numbering). Steps 29 to 30 made the
runtime honest (a `:never` child stays down, replay memory bounded on a real
million-entry log, a scheduler per core). Round 8, the maintenance round, handed
the finished queues to fresh agents with a changed spec: held on all five
predictions, and its fourth oracle found an outage in the Mo program. Round 10
put the BEAM in a pane at last. Measurements 1 and 2 of direction 43 ran on five
of six programs.

**Session 8, the night of 15 to 16 Sep, on the Mac.** The scaling run, P6 on
Elixir, chapter 10 (the language after the rounds) and its first change built as
step 31, the sixth program's regeneration, round 9 with four smaller models, and
generation two of the erosion round.

**Session 9, 16 Sep, on the Mac.** The wiki became a site, and the same
morning round 9's last row, Haiku 4.5, ran, and P6 was probed on Mo's change 2
program: the crash under load answers `503` within milliseconds and loses
nothing, and the restart is the program's to write, not the language's. Step
32 followed the same morning: crash reports kept apart from the event ring, so
the surface's crash row survives load, and the reopening restart in the corpus.
Then change 3 and generation three: a Mo maintainer wrote the queue that
restarts itself, and killed under load it was back in 106 ms with nothing lost,
where Elixir's takes 285 to 694 ms. The BEAM's last row is answered. Step 33
then freed the crash report both runtimes had kept for the whole run, so a
restarting store no longer grows by its own size at every restart, and fixed
an interpreter abort on opening a large log. Generation four followed in the
afternoon: idempotent creates and an archive beside the log, state a restart
must rebuild, and all four languages carried it whole; nothing has eroded in
four generations. Step 34, placement, began at 15:08, paused when Robert took
the Mac, and finished in the evening: the cross-scheduler ask, which had made
every Mac row fastest at one core, went from four seconds per 100,000 to 0.14,
and the queue's pairs and the interpreter's kv row are level across cores now.
Measuring it, the lead found generation four's Mo queue nine times slower on
the lease path than every earlier generation, an erosion the round had not
been counting; the round records speed per generation from then on. Change 5
then pressed on a law rather than on durability (a lease handed to another
worker, a queue renamed with jobs in flight as one record): all four
maintainers carried it in 11 to 25 minutes, all four found the same wrong
sentence in the spec, and Mo's shipped the first defect of the round that no
baseline shared, a folder its own `compact` leaves in a state its own `verify`
refuses; the three `never`s its maintainer wrote caught neither of its bugs.

**Session 10, the morning of 17 Sep, on the Mac.** A second lane exists beside
the build: an independent research agent (Hermes, [[hermes-research-monitoring]])
scans primary sources daily and publishes wiki-only PRs the lead reads before
merging, never code, never decisions. Its first two notes were merged this
morning ([[hermes-daily-2026-09-16]], [[hermes-daily-2026-09-17]]): a correction
to chapter 10 (the 3-in-5 restart budget that ended the Elixir node is Elixir
`Supervisor`'s default, not OTP's), the OSDI 2014 evidence that catastrophic
failures come from error handlers that exist and are wrong, the crash-consistency
distinction between a file's bytes and its directory entry that sits on the exact
path of generation five's Mo defect, and the `cap-std` line that a capability API
is not confinement. Nothing in it changes a decision; the two checklists are
queued reading for change 6. The same review found `erosion2-*` and `erosion5-*`
had never been pushed; they are now.

## What Mo is, today

- **A toolchain of about 39,000 lines of Zig and 10,500 of C**: `mo check`,
  `mo test` (contracts, properties, a seeded simulator with fault injection),
  `mo run`, `mo build` to a static binary, `mo fmt`, `mo fix`, a runtime surface
  over HTTP, 60-odd diagnostics that say what to write. A cold full test of the
  toolchain is ten minutes on the VM and two warm on the Mac.
- **A corpus of 177 Mo files**: 50-odd single-construct files, the standard
  library's tests, and six programs of 769 to 4,551 lines (a log analyzer, a job
  queue, a key-value store, a notes service, an agent harness, a ledger), every
  one with a spec page, transcripts checked byte for byte, and a hidden test
  suite or a session of the lead's own probes.
- **A wiki of 243 pages** (483 markdown files with the raw sources and the spec),
  of which this is one: 43 directions, 18 questions, 25 spec pages, 62 plans,
  32 deep dives, 56 research pages, 7 maps, 196 raw sources, a decision log of
  447 rows, and a changelog (counted 17 Sep).
- **Sixty-two worktrees beside the repo**, one per control-run session, kept
  as evidence and never merged.

## The thesis, and the hypotheses under it

Chapter 1 states three layers and what each is expected to carry.

1. **The runtime and the process model carry reliability.** Isolated processes
   as state machines, supervised; a failure model that says what a crash
   discards, what a timeout leaves, what a restart loses; a deadline on every
   wait, a bound on every mailbox; structured runtime events and a queryable
   surface.
2. **Capabilities and recipes carry zero dependencies.** Authority is a
   parameter; nothing enters a program that `main` did not hand it; a package is
   a recipe (a spec with tests whose bodies an agent generates and checks) or an
   audited brick.
3. **The language is the surface** that makes the first two visible in the
   source: contracts, `never` clauses, invariants, the `verified:` line. A law
   belongs in the language only when it removes a class of bug.

The **null hypothesis**, named in chapter 1 and now run: the BEAM with Elixir
already gives most of layer 1, and Mo's delta (static types at every boundary,
unforgeable capabilities, a deadline on every wait, one static binary, no
ecosystem to trust) does not justify a new language. The **language layer's own
null hypothesis**: agents do as well in a familiar language with Mo's checks
bolted on.

The **measure** (chapter 8, restated 14 Sep): predicted in this order,
reliability under a hidden adversarial suite, native speed and memory against Go
and Python, the loop from an edit to a verdict, the dependency count; recorded
and never predicted, agent time and loops; since round 8, tokens read per
correct change and first-fix rate per diagnostic.

Direction 43 added **five measurements** of the parts the rounds do not reach:
bodies as cache (are function bodies regenerable from the spec altitude?),
sampling as verification, the erosion round (ten changes by fresh maintainers,
does quality hold?), the incident round, and the two diagnostic columns.

## What has been tested, and how it came out

| claim                                                     | how it was tested                                                                                         | what happened                                                                                                                                                                                                                                                                                                                               | standing                                                                                                                                                                 |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Reliability under a hidden defect suite                   | rounds 7 and 8 (Mo, Go, Python), round 10 (Elixir), round 9 (four smaller models), erosion generations two to five | Mo 0 defects in rounds 7 and 8 where Go had 1 and Elixir 2; in round 9 the two open-weights models' Mo changes carried 1 and 2 defect causes (Go 1 for every cloud model, Python 0) and Haiku 4.5's change was wrong in every language (Mo 28 checks over 4 causes, Go 22 over 6, Python 18 over 2); in generation two Mo 1, Go 0, Python 1, Elixir 3; nothing new in three and four; in five Mo 1 (a folder its own `verify` refuses after a compaction and a rename), Go 1 (a reading), Python 0, Elixir 0 | **held for the frontier models, thinly, and lost once**: Mo was never worse than Go by more than one until generation five, where it carries the only defect no baseline shares; below the frontier, at Haiku's size, every language fails and Mo fails most by check count |
| Zero dependencies                                         | every round's dependency count                                                                            | Mo 0 packages and 0 tools by construction; Go 1 tool; Python 1 package and 2 tools; Elixir 0 at run time, 3 tools                                                                                                                                                                                                                           | **held, with a tie**: Elixir ties the run-time column, which chapter 1 says refutes the reliability claim only if Elixir is also as reliable; it was not (2 causes to 0) |
| The feedback loop                                         | check-and-test time over the finished program, every round                                                | Mo 0.4 to 0.8 s; Go 14 s (0.25 warm); Python 7 to 9 s; Elixir 7 s                                                                                                                                                                                                                                                                           | **held every time**, the clearest win                                                                                                                                    |
| Native speed and memory                                   | rounds 7 and 8, round 10, the Mac scaling run, step 34, generation five's speed row                       | Mo's binary 1,420 lease-and-ack pairs a second on the VM's disk against Go's 428 and Python's 325 at 32 workers, from the fsync pool; Elixir 2,870, twice Mo; on the Mac 4,040 for the round 7 queue and changes 1 to 3, and 452 for change 4 (its maintainer's design, not the toolchain's: the same on step 33's and step 34's binaries); after step 34 the queue's pairs and the interpreter's kv row level across 1 to 14 cores, CPU-bound work 7×, echo and the binary's kv still slower at 14 by the rule for what `main` starts | **mixed**: ahead of Go and Python at concurrency, behind at one client, behind Elixir, cores no longer cost on the request paths that start their own processes, and one maintainer's change cost nine times on the lease path without any suite noticing until the lead measured it |
| A crashed process with the service still answering (P6)   | round 8's outage, P6 on Elixir with kills and with a full disk, generation two                            | Mo's spec-as-written queue stopped answering when its queue process crashed (a wait hidden as a message pattern); Elixir's supervisor restored service in under 600 ms three times, and exits on the fourth kill inside two seconds or on a full disk; Mo's generation-two program answers through a full disk and now asks with a deadline | **the BEAM's row today**, with the counter-probe on Mo's change 2 program still to run                                                                                   |
| The laws catch what tests miss                            | every round's loop log read for a check that caught a change-induced bug                                  | none, in any language, in ten rounds and nine round-9 sessions; one `never` cost two loops as a false positive; round 3 had one real bug caught by a test and a `never` together                                                                                                                                                            | **not shown**; the biggest open risk                                                                                                                                     |
| Bodies are cache (measurement 1)                          | six programs regenerated twice from intent, types, signatures with contracts, and tests                   | twelve of twelve at completeness 1.0, in 11 to 47 minutes; with the tests deleted too, logstat at 1.0 under its transcripts and 0.74 under its original tests                                                                                                                                                                               | **held**, and it located where the spec's open choices live: in the tests                                                                                                |
| Sampling as verification (measurement 2)                  | five regenerations of the queue's board compared over 132,000 operations                                  | identical, except on one impossible record a random driver never sends                                                                                                                                                                                                                                                                      | **held for a spec'd module**; directed inputs from the maintainers' own decisions find what random ones do not                                                           |
| Quality holds across maintainers (erosion, measurement 3) | generations one (round 8) to five                                                                         | nothing eroded on the old suites in Mo, Go, or Python in five generations; Elixir eroded once (a torn line refused at open); under each generation's own suite the four programs came out within one defect of each other, and in generation five Mo alone carried one; generation four's Mo program lost nine times on the lease path, a performance erosion no correctness suite counts | **too early, and no longer one-sided**: the ten-generation prediction (Go and Python at least three defects, Mo at most one) is alive on both halves only if Mo's count stops at one; speed per generation is a column from now on |
| Reliability moves with the model (round 9)                | round 8's change by kimi-k3, deepseek-v4-flash, gpt-5.5, Haiku 4.5, and a local 27B                       | for the cloud models it moved on the Mo side only, and the diagnostics carried them to green (first fix right in 21 of 23 loops); gpt-5.5 matched Opus in 14 minutes; Haiku 4.5 was wrong in every language in under ten minutes, most in Mo by checks (28, 22, 18), least by cause in Python (4, 6, 2); the local 27B made no edit in any language | **held**; for the cloud models the language teaches without the laws catching; at Haiku's size the language does not change whether the change is right, only which checks are missing |
| The shelf at zero dependencies (bricks)                   | steps 35 and 36: the crypto brick and a TLS 1.3 server, each with the bricks page's audit items                | crypto 0 mismatches in 18,000 inputs per runtime against python's `cryptography`, 0 crashes in 4.5 million fuzz inputs; the TLS server 14 abuse rows as named, 22 lead probes, 1,026 handshakes a second; the cost: `List(UInt8)` at 2.9× and 6.3× the raw call, a record at 1.8× to 4× a plain write, +800 KiB per binary; two defects behind a worker's reported green found by the lead's own suite run |
| Agent time                                                | rounds 1 to 6, recorded since                                                                             | Mo 1.3 to 2.5 times Go's time and two to five times its loops, nearly all loops the grammar's and the laws'                                                                                                                                                                                                                                 | **recorded, not a prediction**: the unfamiliarity tax is real and unmeasured against the value                                                                           |

## Where we were wrong

- **Agent time was the wrong measure for four rounds.** Rounds 1 to 6 timed
  agents writing a language none had seen and read the result as the language's
  cost. The restatement of 14 Sep fixed the measure; the tax is still real, and
  direction 43 names the experiment that would size it (the same agent writing
  the same program twice).
- **Round 6 failed on all four predictions**, and the laws it cost loops on (the
  500-line file law, keywords as names, a `never` on a `var` copy) were removed
  or loosened by step 27. The counted shape laws are settings now, not laws,
  though chapter 2 still lists them as laws and a step owes the edit.
- **Two of three derived deadlines in program 1 were wrong when written by
  hand**, which is how the derived deadline (`reply_by`, step 22) came to exist.
- **The runtime was not honest about `restart: :never`** until program 6 found
  it restarting anyway (step 29), and replay memory was unbounded on a real log
  until step 29b.
- **Round 8's outage was Mo's**: the queue answered its workers by a send and a
  message back, a wait no law bounds, and when the queue crashed every
  connection hung. Chapter 10 §1 and step 31 (a deferred reply that keeps the
  ask's deadline) are the answer, used by the next maintainer the first time it
  was offered.
- **Cores do not help on the Mac.** Step 30's placement is by fewest live
  processes and every cross-scheduler ask pays a hop; on the M3 Max every row is
  fastest at one core.
- **Two predictions of the erosion round were wrong in Mo's favour**: Go and
  Python already answer through a full disk as Mo does, and Go's change 2 was
  one defect cleaner than Mo's.
- **The lead swept a worker's staged files into two commits** on 16 Sep; the
  rule is now to commit by path.
- **The erosion round counted correctness and not speed for four generations.**
  Generation four's Mo maintainer made the lease path nine times slower and the
  fifth suite, 77 checks green, could not see it. The cause, named 17 Sep on
  the VM: a postcondition on `sweep` that walks every finished job, run on
  every request; with contracts off the queue is back at generation three's
  rate, so the runtime was never the cause, and the diagnostic that would have
  shown it is a chapter 10 candidate. Chapter 8 puts native speed
  second in the measure; the round applies it per generation from five on.
- **A change written to press on a law found no law that catches.** Change 5's
  Mo maintainer wrote three `never`s and neither of its bugs tripped one; the
  one it shipped is the first Mo-only defect in six hidden suites. The laws'
  value for the second agent is still unshown after five generations, and the
  next change has to be written knowing that.

## Where we were right

- **The spec altitude is real.** Twelve regenerations from intent, types,
  signatures with contracts, and tests, all at 1.0. A reader who reads what the
  language says a reader should read has enough to rebuild the program.
- **Reliability at zero dependencies has survived every round on the frontier
  models.** Mo has never had more defects than Go under a hidden suite, and has
  never needed a package or a tool.
- **The loop is under a second**, and every baseline's is seconds to tens of
  seconds.
- **The runtime's numbers held up under measurement**: 65,530 idle connections,
  200,000 short-lived processes, a million-entry replay at the book's own size,
  a kill under load losing nothing in five of five, and after step 34 a
  cross-scheduler ask at 1.4 µs where it had been 40, so the Mac's cores stop
  costing on the paths a program's own processes start.
- **A rule at open is worth having even when it is the program's own slip that
  trips it.** Mo's change 5 folder refuses to open loudly where the same slip in
  a baseline would have replayed the log into the wrong queue in silence.
- **The diagnostics teach.** First-fix rates above 0.9 for every diagnostic with
  more than a handful of sightings, across Opus and three smaller models in a
  language none had seen.
- **Pre-registration and hidden suites kept us honest.** Every prediction is on
  its page before the sessions start, every suite is written after the
  branching, and the findings that mattered (the outage, the torn line, the
  shared scheduling miss, the full-disk death) came from inputs no suite sent
  until the lead wrote one.

## The auditor, and the rules that say when a claim retires (17 Sep)

An outside review of 17 Sep 2026 (`mo-review-2026-09-17.md`, in Robert's
project files) named the weakness in how the project has been checking itself:
pre-registration and hidden suites prove little when one agent writes the
predictions, runs the rounds, and reads the results. Fable had been doing all
three. Robert's fix, the same day, was an **auditor**: a separate Perplexity
session that he opens himself. It reads only raw evidence, never Fable's
reading, and files its own account under
[`audit/`](https://github.com/robertguss/mo-lang/blob/main/audit/README.md) at
the repo root. Fable remains the lead. For each subject, Fable writes its own
reading before opening the auditor's. Where the two disagree, a decision-log row
cites both, and Robert decides. Since the evening of 17 Sep the exchange is
automated (PR #3): Fable leaves raw evidence under `audit/evidence/<date>/`
and publishes `ready` records under `audit/handoffs/`, the auditor's intake
polls `main` hourly and answers by pull request, and Fable checks the
auditor's inbox at every session's start. The first three subjects (step 35, the
speed probe, step 36) have readings from both sides and the auditor's
comparisons of the first two are merged; step 37's `ready` record and program
7's sealed spec are published; the loop is on [[the-audit-workflow]]. The
auditor's reading of step 36 found four things the lead's had not, all
conceded and closed in step 37; the one open disagreement, what generation
four's low memory number means, had a pre-registered control probe
([[gen4-memory-control-probe]]) whose forty runs refuted both readings: the
low number is an intermittent state of generation four's code, independent
of the contract, and the rate loss is the contract's walk; the allocator's
resident set is the open question.

In that first session Robert ratified three stopping rules, before program 7
exists and before generation six runs:

| layer | what clears it | if it fails |
|---|---|---|
| Runtime (primary), on program 7 against Elixir | at least 4 of 5 reliability rows (hidden suite of 50 or more defects, time to recover, no unbounded wait, exact replay, a diagnosis from the surface alone) with no cost row red (time to write, speed, memory, dependencies) | S-A full retirement, S-B a scoped claim, S-C provisional with program 8 deciding |
| Capabilities and recipes (secondary), on program 7 | 0 dependencies; recipe drift caught; at most 1 capability escape in Mo; maintenance time at most 1.5× Elixir's | T-A, T-B (bricks without recipes), T-C (fixes follow) |
| The language's own catch claim, at generation ten | `never`/`invariant` catch at least 2 defects no test caught, false positives at most 1.5× catches, at most 5 per 1,000 lines | R-B on its own: kept as tools, dropped from the claim |

What follows from it: program 7 moves up the board, behind the bricks page,
which the capabilities rule requires before program 7's first commit, and the
probe into generation four's speed loss. The bricks page shipped the same
afternoon ([[bricks-and-the-cost-of-zero-dependencies]]): a brick is anything
whose bug is a security or data-loss event, or that implements a standard
others must interoperate with, or that needs native code; the rest is a recipe
or the program's own. Priced against Zig's standard library, which the
toolchain already trusts: about 70,000 lines to read and 12,000 to 15,000 to
write for the five bricks the review named, of which program 7 needs two,
crypto and a TLS 1.3 server. Each brick ships with five audit items and a
capped cut of its standard, written once in Zig for both runtimes. The
crypto brick landed the same evening (step 35, [[interpreter-step-35]]): the
differential run against python's `cryptography` at 0 mismatches, the fuzz at 0
crashes, SHA-256 at 532 MB/s in a binary against 1,548 for the Zig call, the
difference the `List(UInt8)` value, a later step. That probe comes
first because the runtime rule's speed row is already at its limit on today's
record: round 10's Elixir queue ran at twice Mo's rate. Fable's disagreements
are rows for Robert. Program 7 as specified (a Redis subset) needs no hex
package in Elixir, so its spec will add TLS, hashed ACL passwords, and a
metrics endpoint. The language rule's escalation to removal from the grammar
would fire on one false positive when there are no catches. Fable also
recorded how it reads the runtime rule's unclear clauses, before any evidence
exists. The auditor, not Fable, writes program 7's hidden suites.

## What is still to test, measure, and verify

0. **Program 7, waiting on the auditor's suites.** Step 37 closed the TLS
   brick (18 Sep, [[interpreter-step-37]]): the client side, the chain to a
   trusted root, ALPN, KeyUpdate either way, 1,000 sessions against OpenSSL at
   0 mismatches, a fuzz hour at 0 crashes, and the four findings of the
   auditor's step-36 reading closed; the lead's probes found two runtime
   defects behind the worker's green (a peer's alert read as the stream's end;
   a double free that crashed the binary server), both fixed the same night.
   Program 7's spec is sealed ([[07-redis-subset]]): a Redis subset against
   Redis 7.2's own tests, RESP2, an append-only file, ACL users with Argon2id,
   TLS, a metrics endpoint, four recipes, the deviations pre-registered. The
   auditor writes the hidden suites and names the P4 modification; then the Mo
   and Elixir builds. Before the build, **step 38**: a `Conn` that reads while
   a write on it waits, and `TCP_NODELAY`, both found by step 37's bench and
   both needed by a pipelining Redis client. Robert's reading before the
   evidence (17 Sep, 8:40 PM ET): parity with the BEAM at zero dependencies
   from a compiled runtime is an achievement, not a retirement; Fable's caveat
   beside it: a Redis subset is a narrow test of the BEAM.
1. **The laws' value for the second agent.** No check has caught a
   change-induced bug in any language. The erosion round's later generations,
   changes 3 to 10, are where a law either earns a row or is removed. The check
   that would have caught round 9's shared miss is a program `never`, which
   points at the spec, not the language.
2. **Generation six and on**: five generations in, Mo carries one new defect
   and one carried, Go and Python one carried each, Elixir three; the
   ten-generation prediction is alive on both halves only if Mo's count stops.
   The speed row per generation is new. The next change should be written with
   generation four's nine-times slowdown and generation five's count slip in
   view: what does a maintainer need to see to avoid both? Carried from step
   33: a restart on a 100,000-job log takes 1.45 s against the spec's one
   second, and compaction copies a string once per reference. From the
   research lane, two acceptance questions for the seventh suite: the sequence
   create, compact, rename, reopen, write again, with file and directory-entry
   persistence named separately; and whether every error path a recipe
   declares is reachable by a test ([[hermes-daily-2026-09-17]],
   [[hermes-daily-2026-09-16]]).
3. **Placement for what `main` starts**: step 34 placed a process with its
   starter and made the crossing cheap; `echo-1k` and the binary's `kv-10k-get`
   are still slower at 14 cores because their two ends are both `main`'s. A
   unit test for the step-aside, and the compaction copy now measured on the
   ledger (650 transfers a second under `mo run` against 4,800 as a binary),
   are the same step's carried rows.
4. **Round 9's Opus-in-Pi baseline**, so the harness is the same in every row,
   when Pi has an Anthropic key.
5. **Chapter 10's other sections**: the restart budget as a diagnostic, the
   counted laws into `mo.toml`, MO0317 naming the changed module.
6. **The unfamiliarity tax**, sized: the same agent writing the same program
   twice.
7. **Program 7** (third on the board, after the speed probe and the TLS
   brick; the crypto brick is done), a real open-source service reimplemented against its own
   tests, the first program built on capabilities, recipes, and the runtime
   surface together, and the one chapter 1 says answers the BEAM.
8. The compile benchmark at 5,000 modules, `mo prove`, the
   package registry, and the toolchain in Mo, in that order and all later.

## Rows waiting on Robert

In the decision log, marked "for Robert", newest first (the same list is on
the [[roadmap]] board and [[for-robert]]): the bricks page's two rows (17 Sep, afternoon); the auditor role taken up, with M-3 accepted, the bricks prerequisite, and three disagreements with the ratified rules (17 Sep, afternoon); research PR 2 read and merged, chapter 10's attribution corrected (17 Sep); generation five's reading, the first Mo-only defect, the laws still silent; the change 4 Mo queue nine times slower on the lease path, speed recorded per generation; generation four; chapter 10 §2's budget as a value; generation three, the BEAM's row answered; P6 on Mo's change 2; round 9's Haiku row and its reading; generation two; chapter 10 §1 as built (step 31); chapter 10 itself; P6 on Elixir; measurement 1's completeness row; the BEAM row after round 10; the outage, probed and read; round 8 read; the 16 lint issues from his history bundle.

## Related

- [[roadmap]]
- [[the-thesis-and-its-evidence]]
- [[the-rounds]]
- [[the-language]]
- [[the-runtime]]
- [[the-programs]]
- [[for-robert]]
- [[how-we-work]]
- [[decision-log]]

# Mo Lang — Astra lead and fresh OMP/Sol workers (read START HERE)

## START HERE: both units resumed under OMP/Sol, 19 Sep 2026

Robert's Claude Code subscription is unavailable. Astra leads in this existing
OMP session; workers use OMP with GPT Sol at high reasoning. Robert explicitly
authorized resuming both saved units below after recording the new workflow.
The afternoon pause is superseded for that work. No new code is accepted.

Load `mo-lead`, then this section and `mo-wiki/SCHEMA.md`. Run the auditor check
(`git fetch origin && python3 audit/automation/fable_poll.py check`; this
session's check at 7:36 PM ET found 0 new records). PRs 15 and 16 are merged.
The lead owns briefs, reviews, records and acceptance; it may run independent
builds/tests, but workers write all implementation and code, including probes.

### Standing instructions learned today (in force)

- **At most three Sol/high workers at once**, each in its own Herdr tab, OMP
  auto-approval within its bounded brief. Every assignment starts a fresh clean
  session, even for saved WIP; no continue/resume/fork/import. Finished means:
  agent idle, worktree clean, the final report
  committed (a worker may commit its report file early, and Herdr shows `done`
  whenever a turn ends while a background run continues).
- **Linux is deferred**: accept on macOS alone; keep the "Linux owed" list
  below. **Robert pushes `main`**, and asks the lead to commit and push when he
  wants it done (he did twice today); `main` holds accepted work and lead records
  only; verify on `lead/verify-<unit>` in **its own worktree** (it keeps the
  lead checkout free and `zig-out` unshared).
- Full suite: detached (`nohup`, `caffeinate`), `guard.py 2400`, poll for
  `.lead-done`; about 12 minutes idle, 19 to 23 under load. Write runner
  scripts as **bash files**: zsh does not split `$VAR` into words and aborts an
  `&&` chain on an unmatched glob (both cost the lead a run today).
- Every brief ends by naming a report file, and asks the worker to tee each
  quoted run into a filed log with an exit file.
- The TypeSafe key is age-encrypted in the git-ignored `fnox.toml`:
  `fnox -c <repo>/fnox.toml exec -- <command>`. Never print it.

### Authorized resumptions (saved WIP, not accepted on `main`)

| unit | branch, worktree | WIP commit | notes | brief |
|---|---|---|---|---|
| Mo six-tool server, part A | `harness/workspace-server-4a`, `.../harness-workspace-server-4a` | `d679f568` (7/13 groups reported only in an unfiled half-close scratch run; unchanged-wire blocker F1 remains) | `examples/programs/workspace-server/WIP.md` | `mo-wiki/plans/mo-workspace-server-4a.md` |
| Step 42, runtime memory safety | `toolchain/step-42-memory`, `.../toolchain-step-42-memory` | `0a4dffcd` (part E green: the guard kills the group; other parts not begun or partial) | `toolchain/WIP.md` | `mo-wiki/plans/interpreter-step-42.md` |

Resume each with a **fresh clean OMP/Sol/high session** in its saved worktree.
Read the current brief from the lead checkout, then the worker's `WIP.md`,
then its branch history. Old worktree role instructions are superseded by the
current lead skill and explicit launch brief. Keep all prior evidence.

**Live launch receipt:** workflow committed as `ef3b8796` before either
worker started. `server4a-sol` is in tab `w4:t15`, pane `w4:p36`;
`step42-sol` is in tab `w4:t16`, pane `w4:p37`. These are this launch's
pointers, not IDs to reuse for new workers. Both started from new shell tabs
with `--model openai-codex/gpt-5.6-sol --thinking high --no-prewalk
--auto-approve`, no session-resume flags, and acknowledged and began their
assignments. Exact prompts/receipts: `audit/evidence/2026-09-19/omp-resumption/launch.json`.
Herdr 0.9.0 reports OMP `idle` even during visible tool activity: inspect
output, report and process completion rather than treating that badge as done.
Full suites and benchmarks remain lead-scheduled; neither worker may use the
Linux VM or executor machine. The server first qualifies F1 without altered
clients; memory work excludes all server files. Nothing newly accepted.

**F1 update:** server worker filed `8b0ff352`; exact unchanged client, 155-byte
body, timeout before close, body delivered only after close. `f1-06-exact-client`
is a successful reproduction (exit 0), not GREEN. Lead brief:
`mo-wiki/plans/interpreter-step-44.md`, bounded binary `Conn.chunks` using
existing runtime sources; fresh `step44-sol` launched in tab `w4:t17`, pane
`w4:p38`, branch `toolchain/step-44-conn-chunks`, matching worktree basename,
exact clean base `c4462935fdbcf99d3b8b53258828d028d68594bc`. Startup showed
Sol/no recent sessions; `--thinking high --no-prewalk`, new session, and
the worker began its contract review. All three worker slots are occupied.
Server continues only independent work until lead-approved capability
integration. Step 42 stays isolated; lead reconciles overlapping runtime
files, and schedules all full suites/benchmarks. No new acceptance.

**Server H2/H6/D2 decision:** step 44 is unchanged. EOF after a complete
request does not prove lost response or close admission. Preserve the
operation, journal local write outcome separately from unknown client
receipt, and keep the operator independent. Actual write failure/response
timeout may close admission. The server brief names explicit Mo controls
instead of the two incompatible Python owner-exit predicates; do not claim
13 unchanged groups green. No client ACK or stronger runtime EOF promise.
Fixture half-close is internal model/test support only; public fixtures
still expose full close, and real sockets prove public half-close. Launch
receipt/assignment: `audit/evidence/2026-09-19/omp-resumption/step44-launch.json`.

**Server integration obligation:** real `mo test --write --sim 200` on the
server modules also updates shared `examples/programs/.mo.ids` (397 added
lines reported). Worker scope excludes this parent sidecar: restore only
its check-generated delta, preserve earlier work, retain owned modules'
tool-generated verified lines, and file exact commands. Lead must regenerate
the sidecar and verify source/ID consistency in the separate integration
verification worktree before acceptance; do not hand-edit IDs.

**Step42 slot released; acceptance blocked by lead review.** Worker branch is
clean at `be64e8a5`; runtime measured at `d3273ee2`, test-only ASan stderr
normalization at `e537abfe`. Report: `toolchain/STEP-42-REPORT.md` in
`toolchain-step-42-memory`. Worker reports normal stress exit 0 (386.74s),
normalized ASan exit 0 (417.91s), owned processes clear, temporary baseline
removed. Echo minima moved +12.90% interpreter/+8.60% native with noisy samples;
no zero-cost conclusion. Step44 explicitly released for focused checks, not
benchmarks/full suite. Server report remains `d689b441`, unaccepted behind F1.

Lead review found: blocking threads publish completion before their last
job/notification access; native custom fibers lack ASan switch notifications;
stderr normalization masks the warning rather than fixing that integration;
Part D types only pending answers, leaving other audited holders raw.
Further requirements and exact references are in the step42 brief's review
addendum. A fresh corrective worker must finish them before integration.
Unfiltered suite/timings and independent integrated acceptance remain owed.
No Linux/machine acceptance. Server continuation also needs a fresh worker.

### Next, in order

1. Resume the two units above; accept each (build, focused tests, full suite,
   one probe the brief did not name).
2. The CI gate (`mo-wiki/plans/ci-gate.md`, briefed, after step 42: both edit
   `corpus.zig`). It also brings Linux back on every pull request.
3. The Linux batch (below), then part B of the server (not written: `command`
   through `Exec`, container policy and cleanup proofs on the machine, the
   cutover, D2 closed by an independent operator path).
4. Plan steps 5 to 7 of `mo-wiki/plans/mo-harness-in-mo.md`, the provider
   blockers P1 to P5 with Robert's OpenAI login, the first model-driven task,
   the Pi comparison. A `mo guide` command (research PR 16) is a candidate
   toolchain step.

### Linux owed (one batch on the VM, or the CI gate)

Step 41: `-Dtest-filter="step 41"` and the full suite at `main` (first run, at
`0b0f494b`: build 0, focused 5 of 6, the failure a test predicate fixed in
`ba7fa7ac`; the fork child runs only on Linux). Every toolchain step accepted
after it. VM access and the clone rule are in the lead skill, step 4.

### Waiting on Robert (rows on the decision log, 19 Sep)

D2: patch the Python service so a verdict survives a client disconnect, or
wait for the Mo server (the lead's default). `-128` as one literal.
`in_folder` versus `in`. His OpenAI login, when the provider slice is reached.

### Accepted today on `main` (full suite 268 of 268 on Darwin)

Morning: the rebuilt application workspace; harness steps 1, 8 and 2; the
raw-memory runtime fix; step 40. Afternoon: PR 15 (the auditor's repository
audit, all conceded) and step 43 that fixes it; end to end v1 (the Mo agent on
the machine, the scripted Logstat repair); the claim check's calibration; the
report cap and defect D1; step 41 (`Exec`, macOS); research PRs 14 and 16.
Evidence under `audit/evidence/2026-09-19/`; `CHANGELOG.md` has an entry each.

### Owed and unmet, said plainly

No live provider and no model-driven task yet. Python has not shrunk by
measurement. Two fault-injected power-off checks on the machine. Nothing
refuses new runs after an unconfirmed cleanup. After a client disconnect no
verdict can be taken (D2). `real_bridge.py` stale since harness steps 1 and 2.
The TLS corpus test "a fatal alert where a hello belongs…" fails about 1 in 5
alone. Step 39 unaccepted; Darwin `F_FULLFSYNC` unmet; Program 7 suspended. No
CI gate.

## Earlier on 19 Sep: the 1:15 PM ET handoff and the afternoon's running notes (history)


Robert is starting a fresh lead session because the previous one's context was
full. You are the lead (Fable, Claude Code). Load the `mo-lead` skill, read this
section, then `mo-wiki/SCHEMA.md`, then run the auditor check
(`git fetch origin && python3 audit/automation/fable_poll.py check`; it was 0
new records at 7:15 AM ET). Everything below this section is history.

### How Robert works with the lead (learned today)

- Workers are **Claude Opus, bypass permissions**, each in **its own Herdr tab**
  (`herdr tab create --workspace <id> --cwd <worktree> --label <name>
  --no-focus`), never a split of the lead's tab: he talks to the lead often and
  must be able to read it. Rediscover pane and tab IDs; do not reuse the ones here.
- An idle-looking worker tab is not a finished worker. Finished means its
  report file is committed and its worktree is clean. Briefs tell workers to
  wait in the foreground while something runs. Robert may close a tab that
  looks idle; if so, preserve the worktree's uncommitted work as a WIP commit
  and start a fresh worker to finish it (this happened to step 40).
- **At most three Opus workers at once** (Robert, 19 Sep, 1:33 PM ET; he first said
  "not too many", then named the number). Queue briefs rather than exceed it.
- **Robert pushes `main` himself at any time.** So `main` holds accepted work
  and lead records only. Verify a worker's branch on a local
  `lead/verify-<unit>` branch; merge to `main` at acceptance.
- **Linux is deferred** (Robert, 19 Sep, 3:26 PM ET): accept on macOS alone for now;
  do not wait on the VM. **Linux owed** (run as one batch later, or by the CI
  gate): step 41 (focused tests and full suite; first VM run 5 of 6, the failure
  a test predicate `took > 0.ms`; the fork child only runs on Linux) and every
  toolchain step accepted after it. Part B of the Mo workspace server runs on
  the Linux machine and is gated on that batch.
- **Linux toolchain runs go on his Linux VM**, not the Mac: `ssh -o
  IdentitiesOnly=yes -i ~/.ssh/id_exe robertguss@aurora-but-gold.exe.xyz`
  (x86_64, 4 cores, Zig 0.16 via `mise`; the `dev-box` alias is broken). Use
  only the clone `~/Projects/mo-lang-lead-verify`, fetched from a pushed
  `lead/verify-<unit>` branch; never touch the VM's historical checkouts. The
  OrbStack machine `mo-executor-r01` is only for the harness's live suites.
- Run the full suite **detached** (`nohup`) under `guard.py 1500` or more and
  poll for an exit file: it now takes longer than the tool's 10-minute cap.
  `guard.py` kills only its direct child; after any kill, look for orphaned
  test binaries (`ps` for `.zig-cache/o/*/test`): an orphan's cleanup deletes
  the shared `zig-out` and breaks the next run (it happened).
- Read the clock (`TZ=America/New_York date`) in the same command that writes
  a time. Report sizes only as measured. One question per message.
- Every brief ends by naming a report file the worker must commit.

### Accepted today, all on `main` and pushed (full suite 249 of 249 on Darwin)

The rebuilt application workspace; harness steps 1 (executor defects), 8 (Mo
agent findings) and 2 (live suites as tables); a use-after-free in both
runtimes (an `answer` to a kept ask); step 40 (a narrowed `Fs` refuses links,
`Fs.replace`, `fs.kind_of`); research PR 14. Decisions are rows in
`mo-wiki/decisions/decision-log.md` (sections dated 19 Sep); evidence in
`audit/evidence/2026-09-19/fable-lead-verification/` and
`fable-overnight-review/`; `CHANGELOG.md` has three entries for today.

### In flight right now (both launched about 1:00 to 1:10 PM ET, base `853a27df`)

| worker | tab / pane then | branch, worktree | brief | report it must commit |
|---|---|---|---|---|
| `step42-memory-opus` | `w4:t14` / `w4:p35` | `toolchain/step-42-memory`, `.../toolchain-step-42-memory` (base `2f669902`) | `mo-wiki/plans/interpreter-step-42.md` (runtime memory safety) | `toolchain/STEP-42-REPORT.md` |
| `server4a-opus` | `w4:t13` / `w4:p34` | `harness/workspace-server-4a`, `.../harness-workspace-server-4a` (base `5dd6e585`) | `mo-wiki/plans/mo-workspace-server-4a.md` (the six-tool server in Mo, part A, no machine) | `examples/programs/workspace-server/REPORT.md` |

**Update, 19 Sep, 1:23 PM ET (fresh lead session).** The auditor's PR 15 (repository audit) is read, compared and merged: lead reading `audit/fable-reading-2026-09-19-repo.md` filed first, comparison beside it, all conceded (sized literals past their type reach both runtimes; an oversized `mailbox:` panics the compiler; the fuzz driver passes a run of nothing). Step 43 fixes them and is in flight. Briefs written and waiting: `interpreter-step-42.md` (runtime memory safety, after step 41 lands) and `mo-agent-report-cap.md` (after the end-to-end slice). Step 41's report file was committed early as part of its RED commit: **a committed report is not a finished worker; also require a clean worktree and an idle agent.** A CI gate is still owed (decision-log row).

**Update, 19 Sep, 2:00 PM ET.** Step 43 accepted and on `main` (Darwin full suite 263 of 263; Linux build and focused tests green; the Linux full suite at `4ad89c1a` was still running on the VM: add its result to `audit/evidence/2026-09-19/fable-lead-verification/step43/README.md`). The first x86_64 Linux full suite, on step 40's tree, was 249 of 249. Robert approved TypeSafe for the report claim check and has a key; he stored it age-encrypted with fnox in `fnox.toml` at the repo root (2:01 PM ET; untracked, his file, the lead has not committed it). Use it as `fnox -c <repo>/fnox.toml exec -- <command>`; the lead checked it decrypts (length only) and told the worker. The lead checkout's `toolchain/zig-out/bin/mo` predates step 43: rebuild before probing on `main`. Queue by slot: step 41 done, then launch step 42; end to end done, then the report cap.

**Update, 19 Sep, 2:21 PM ET.** End to end v1 accepted and on `main` (the lead reran it on the machine; inventory clean). **The machine is free and lead-owned again**; the sentence below is history. Step 43's Linux full suite: 263 of 263. PR 16 (Bend2 research) merged. Step 41's agent shows `done` in Herdr whenever its turn ends while a background corpus run continues: finished means idle, a clean tree, and `STEP-41-REPORT.md` committed after `75834c97`. When step 41 is accepted, launch step 42 in its slot (three workers is Robert's maximum). `main` is pushed through `495d7424`; later commits are local.

**Update, 19 Sep, 3:08 PM ET.** Accepted since the last note: the claim check's calibration (acceptance does not depend on it) and the report cap with defect D1 (Darwin and Linux full suites 263 of 263; the margin seen holding on the machine). **Step 41's worker is finished** (`6eafb762`, tab `w4:tZ` still open until acceptance); the lead merged it on `lead/verify-step41` (`0b0f494b`, pushed; one conflict in `root.zig`, both import lines kept), focused tests 6 of 6 on Darwin, lead probes green in both runtimes (`audit/evidence/2026-09-19/fable-lead-verification/step41/`). Running detached: its Darwin full suite (worktree `lead-verify-step41`, `.lead-exits`, `.lead-done`) and on the VM build, `-Dtest-filter="step 41"`, then the full suite (the fork child only runs on Linux: read `.lead-test.log` closely). On acceptance: decide `in_folder` versus `in`, fix the design page's `Fixed("rm")` to `Fixed(text: "rm")`, close the tab, launch step 42, then the CI gate. Briefs waiting: `interpreter-step-42.md`, `ci-gate.md`; part B of the server is not written.

**Update, 19 Sep, 3:34 PM ET.** Step 41 (`Exec`) accepted on macOS and on `main` (Darwin full suite 268 of 268; Linux owed). Two workers in flight: `server4a-opus` and `step42-memory-opus`; one slot free. Next: the CI gate (`mo-wiki/plans/ci-gate.md`, after step 42: both edit `corpus.zig`), then part B of the server (not written; gated on the Linux batch). `main` is pushed through `495d7424`; everything after is local, and Robert pushes. For Robert on the decision log today: D2 (patch Python or wait for the Mo server), `-128` as one literal, `in_folder` versus `in`.

The end-to-end worker **owns the OrbStack machine exclusively**; do not run live
suites until it is done. The step 41 worker was told to stop and ask if keeping
`Exec` and `Program` inside `main` cannot be expressed in the checker without
new syntax: a grammar change is Robert's call, asked with code options.

Also running: the **Linux full suite** on the VM at `0ab217c9` (detached;
`~/Projects/mo-lang-lead-verify/.lead-exits` gains a `full-exit` line and
`.lead-done` appears; log `.lead-full.log`). At 1:12 PM ET it had not finished.
It is informational: step 40 was accepted on Darwin's full suite plus Linux's
step 40 tests. Read failures carefully; this is the first x86_64 Linux full run
since the move to the Mac.

### When a worker finishes

Read its report, inspect the diff, merge onto `lead/verify-<unit>`, build, run
its focused tests and the full suite detached, run one probe the brief did not
name, run Linux on the VM for toolchain work, rerun the live suites on the
machine for harness work (commands and expected summary lines are in
`audit/evidence/2026-09-19/fable-lead-verification/README.md`; application
controls need `--image sha256:b9fda4ae85f369e475e0f412e15dea9044a849a64bc2ec94bb3bc5a661eab3c4
--toolchain d31b5c5e7e1912f98eba21268854d0f7b830dba7048b2de0e2c0458d10e507eb`),
then record per the skill's step 5 and merge to `main`.

### Next, in order

1. Accept the two workers above.
2. Write and launch the **runtime memory-safety** toolchain step (scope is the
   "Queued toolchain step" paragraph further down: the corpus with compaction at
   every safe point in both runtimes, poisoned freed regions, an audit of what
   the runtimes hold across a frame return, a region-value versus parcel type
   split, `guard.py` killing the process group). It edits `toolchain/src`, so
   launch it after step 41 lands or accept merge work.
3. Lift the agent's 256 KiB report cap (small; the runtime bug it worked around
   is fixed).
4. The Mo six-tool server (plan step 4 of `mo-wiki/plans/mo-harness-in-mo.md`),
   after `Exec`, so it runs `docker` itself. Its brief must: report admission,
   execution, reply (produced versus received) and cleanup as four separate
   observations (research PR 14); close review findings H1 to H7 by design;
   pass the same behaviour tests as the Python service before cutover; and
   record the like-for-like size table ("The size question" on the plan page).
5. Then plan steps 5 to 7, provider live blockers P1 to P5 with Robert's OpenAI
   login, the first real model-driven task, and the Pi comparison.

### Owed and unmet, said plainly

The Mo agent has never run end to end on the machine (the in-flight worker is
doing it). Two fault-injected power-off checks on the machine. Nothing refuses
new runs after an unconfirmed cleanup. The TLS corpus test "a fatal alert where
a hello belongs…" fails about 1 in 5 alone, unexplained. Step 39 unaccepted;
Darwin `F_FULLFSYNC` unmet; Program 7 suspended. Python has not shrunk (6,688,
then 6,326, then 6,643 counted lines): the reduction, if any, comes from moving
modules to Mo, and is to be measured, not claimed. Step 40 costs: a path 16
folders deep is 3.5 times dearer; `list_kinds` 3.3 times dearer in the
interpreter (accepted for now; decision-log row).

## Earlier on 19 Sep (the morning's running notes, newest first; superseded by the section above)


Robert's instruction: **Fable (Claude Code, Herdr pane `w4:p1`) is the lead;
workers are fresh Claude Opus sessions in Herdr panes.** This supersedes the
overnight Astra-lead/Astra-low-worker workflow below. Ownership, verification,
audit and evidence rules are unchanged. Launch details are in
`.claude/skills/mo-lead/SKILL.md`.

Astra's session ended about 7:12 AM ET with ten components accepted and the
eleventh, `mo-application-workspace-v1`, unfinished. No Astra lead, worker or
run pane remains; panes `p2E`/`p2F` named below are gone. Machine
`mo-executor-r01` is running and lead-owned. `main` equals `origin/main` at
`edb75165` before this takeover's records. Auditor check at 7:15 AM ET: zero
new records.

**State at 9:03 AM ET, 19 Sep 2026.** Accepted today by the Fable lead, all
implemented by Claude Opus 5 workers: the rebuilt application workspace
(`ddd81c06`), harness step 1 (executor defects and deletion, `97202a81`,
`ce2a3d13`) and step 8 (Mo agent findings, `d78cb017`). Lead full suite on the
combined tree: 243 of 243, exit 0. Seven live suites and a clean inventory on
`mo-executor-r01`. Evidence: `audit/evidence/2026-09-19/fable-lead-verification/`.
Source review of Astra's night: `audit/evidence/2026-09-19/fable-overnight-review/`.
In flight since 9:05 AM ET, each in its own Herdr tab, Opus 5 with bypass permissions, both based on `31ad3ba9`: `step2-tables-opus` (tab `w4:tS`, pane `w4:p2Q`, branch `harness/step-2-live-tables`, brief `mo-wiki/plans/mo-harness-step-2-live-tables.md`) and `rawmem-toolchain-opus` (tab `w4:tT`, pane `w4:p2R`, branch `toolchain/raw-memory-report`, brief `mo-wiki/plans/toolchain-raw-memory-report.md`). Each commits a report file its brief names. Neither may use the machine or run the full suite. Workers go in
their own Herdr tab, never a split of the lead's tab, with bypass permissions.

**Accepted 10:37 AM ET:** the raw-memory runtime fix and harness step 2; full suite
244 of 244 on `2a852d68`. Step 40's worker tab was closed about 10:07 AM ET
before it finished; its work is WIP commit `a687fd2f` on
`toolchain/step-40-scope` (RED tests `373d7f85`; fix across 13 files; corpus
run done; reruns, benchmarks and report not done). A fresh worker finishes it.
Run the full suite detached (`nohup`) with a 1,500 s guard: the tool's
10-minute cap is shorter than the suite now, and `guard.py` does not kill
grandchildren.

**Step 40 accepted 1:08 PM ET** and merged to `main`; the VM's Linux full suite on it was still running (see `.lead-full.log` in the VM clone). Step 41's worker launches from this `main`.

**In flight, 12:59 PM ET.** (1) Step 40 on Linux: the VM's first run built
(exit 0) and passed 5 of 6; the sixth aborted in the *test harness* (a raw
`read` on a non-blocking pipe returns `-EAGAIN` in the result on Linux). Worker
`step40-linux-fix-opus` fixed it (`3d24c001`) and audited every syscall step 40
added: product code clean. Merged on `lead/verify-step40` (`0ab217c9`, pushed);
the VM is rerunning build, step 40 tests and the **full suite**; results in the
clone's `.lead-exits`, `.lead-test.log`, `.lead-full.log`. Accept and merge to
`main` when green. (2) `e2e-logstat-opus` (own tab, pane `w4:p2Y`, branch
`harness/end-to-end-v1`, brief `mo-wiki/plans/mo-harness-end-to-end-v1.md`):
the Mo agent against the real service on the machine, then the scripted
Logstat repair; **the machine is that worker's exclusively**. (3) Step 41
(`Exec`) is briefed (`mo-wiki/plans/interpreter-step-41.md`) and launches from
`main` once step 40 is accepted. Then the runtime memory-safety brief.

**Step 40 verification, 12:47 PM ET.** Worker finished (`e2434d09`); merged on local
and pushed branch `lead/verify-step40` (`6e04e1f9`), not on `main`. Darwin:
build exit 0, step 40 tests 6 of 6, full suite 249 of 249 exit 0, and a lead
race probe (300,000 reads while a folder is swapped with a link to a secret:
39,238 inside, 260,762 refused, 0 secret). **Linux runs go on Robert's Linux VM
from now on (his instruction), not on the Mac**: clone
`~/Projects/mo-lang-lead-verify` on `aurora-but-gold` (access in the lead
skill, step 4). A build plus the step 40 tests is running there detached;
results in `.lead-exits`, `.lead-build.log`, `.lead-test.log` at the clone's
root. An earlier attempt inside `mo-executor-r01`'s `/tmp/step40` may still be
running; it is superseded, leave it to finish and ignore it. Accept step 40
when Linux is green: merge `lead/verify-step40` into `main`. Two benchmark
findings to decide: deep paths cost 3.5 times as much (one-call
`O_NOFOLLOW_ANY` / `openat2` would remove the walk); `list_kinds` in the
interpreter costs 3.3 times as much.

**Update, 9:25 AM ET.** The raw-memory defect is found and fixed by
`rawmem-toolchain-opus` (`44a4da08`, merged locally at `9304fc65`, tab closed):
an `answer` to a kept ask held a bare value into the process's region until the
update committed; a returning frame past the 1 MiB frame budget compacted the
region first, so the asker received freed memory (native: raw bytes on stdout;
interpreter: the union-field panic, really at `vm.zig:1606` in `main`). Both
runtimes now pack the answer when `answer` runs, as `send` always did. Report:
`toolchain/STEP-RAW-MEMORY-REPORT.md`; new corpus program
`examples/programs/deferred-large.mo` and a focused test with a native
`MO_STRESS` build that compacts at every safe point. Lead checks so far: build
exit 0, focused test 2 of 2 exit 0, and the reduction correct from 9 bytes to
12 MB in both runtimes at four sizes the worker did not name. **Not accepted
until the lead's full suite**, which runs once step 2 is merged too. Then lift
the agent's 256 KiB report cap (a small brief). `step40-scope-opus` launched
9:25 AM ET in its own tab (pane `w4:p2S`, branch `toolchain/step-40-scope`,
based on `9304fc65`, brief `mo-wiki/plans/interpreter-step-40.md`).
`step2-tables-opus` still running.

**Step 2 state, 9:51 AM ET.** `step2-tables-opus` finished (`699eed1d`, merged
locally at `3b599174` and `0881f927`, tab closed). The lead's first live rerun
found a regression the worker could not see offline: `application/controls.py`
`scratch-fresh` failed in the new runner, which merged any truthy action return
into the record. The worker's audit found five more rows leaking whole command
results silently; the runner now accepts `None` or `cases.Fields` only, with a
static test over all 100 actions. Lead reruns after the fix: unit 110 OK;
live on the machine selftest 17 of 17, lifecycle exit 0, workspace 22 of 22,
recovery 16 of 16, HTTP 22 of 22, HTTP `--application` 22 of 22, application
23 of 23, inventory clean. **Python rose, 6,326 to 6,643 counted lines**
(estimate was about 1,400 removed): cleaning Python does not shrink it; no more
worker time goes into polishing Python that is moving to Mo. Not accepted until
the lead's full suite, which waits for `step40-scope-opus` to leave the host
(load average was 15 to 18 at 9:50 AM ET, mostly Robert's iOS Simulator
`MediaAnalysis` process, not ours; left alone).

**Research PR 14 merged, 10:10 AM ET** (Hermes: OTP late replies, AWS idempotency).
Verified and commented on the PR. Carry into the Mo six-tool server's brief:
report admission, execution, reply (produced versus received) and cleanup as
four separate observations. **Note:** `origin/main` received pushes at 9:28,
9:33 and 10:06 AM ET that the lead did not run (the reflog says "update by
push"; no git or Claude hook pushes). So the locally merged, not yet accepted
step 2 and raw-memory fix are already on `origin/main`. Robert confirmed he pushes `main` himself. From
now on unaccepted worker merges are verified on a `lead/verify-<unit>` branch
and reach `main` only at acceptance (lead skill, step 4).

**Order changed:** the Mo six-tool server (plan step 4) now follows `Exec`
(a step 41 after step 40), so it can run `docker` itself and serve all six
tools natively; serving `command` through a Python shim first would be
throwaway work.

**Queued toolchain step, runtime memory safety (Robert asked 19 Sep how to
prevent the raw-memory class):** (1) the whole corpus run with compaction at
every safe point in both runtimes (`-DMO_STRESS` exists for C in `mo_rt.h:240`
but only one test uses it; the interpreter's budgets are settable only from Zig
unit tests, `vm.zig:2337`), as a standing part of the suite; (2) released
region memory poisoned in that mode so a stale read fails loudly, with ASan
region poisoning for the C runtime; (3) a one-time audit of everything the
runtimes hold outside the stack across a frame return (pending answers were
one; check timers, mailboxes, kept replies, the runtime surface's snapshots,
bricks' buffers), and a Zig type split between a region value and an owned
parcel so a long-lived struct cannot hold the former; (4) compaction points as
a dimension the simulator varies by seed. Brief to write after step 40 lands,
since both edit `toolchain/src`.

**Plan of record:** `mo-wiki/plans/mo-harness-in-mo.md` (the harness moved into
Mo, nine steps) and `mo-wiki/plans/mo-capabilities-for-the-harness.md` (the
design: `scoped` made to hold against symlinks, `Fs.replace`, `Exec`).

**Next, in order:**
1. Step 2: the six live suites as case tables; replace recovery's four tests
   that cannot fail (E3). Tell the worker that step 1 edited two strings in
   `recovery/live.py`. Also fix the three provider READMEs and
   `provider/auth/attempt.sh` that name deleted runners.
2. The capabilities toolchain step (strict scope first: `Fs.scoped` is lexical
   today and a symlink escapes it), brief to be written from the design page.
3. A toolchain brief for the rebuild worker's defect: native binary prints raw
   memory on application reports over about 0.35 MB, interpreter panic at
   `vm.zig:1531` over about 0.8 MB; reproduce at worker commit `5caec127`
   (`examples/programs/agent/tests/application-workspace-v1/evidence/toolchain-defect-01.md`).
4. Steps 4 to 7 of the plan (the Mo six-tool server and onward), then the
   scripted Logstat repair, whose brief must include a driver that runs the Mo
   agent against the real workspace service on the machine: that end-to-end run
   does not exist yet.

**Owed and unmet:** two fault-injected power-off checks on the machine; refusing
new runs after an unconfirmed cleanup; the TLS corpus test "a fatal alert where
a hello belongs…" fails about 1 in 5 alone, unexplained; Step 39 unaccepted;
Darwin `F_FULLFSYNC` unmet; Program 7 suspended; provider live blockers P1 to
P5 wait for the live-provider slice, which needs Robert for the login. Size
claims are reported only as measured (step 1: 6,688 to 6,326 Python lines,
against an estimate of about 1,000 removed).

## Earlier today (superseded detail, kept for the record)

**Decided with Robert (decision-log, 19 Sep 7:20 AM ET):** the unfinished
application workspace is scrapped and rebuilt from accepted base `030290b8` by
a fresh Opus worker. The Astra worktree
`~/Projects/startups/mo-lang-worktrees/harness-application-workspace-v1` is
historical evidence, never merged: checkpoint `0a74a0fc` plus WIP snapshot
`0b1404b5` on local branch `harness/application-workspace-v1`, not green. What
carries forward is the findings, as required RED-first controls in a revised
brief: null-ID preadmission refusal loses `not_started`; an unaccepted response
can accept HTTP 500/busy; a success command accepts null output; mixed-null
streams; success with exit 1; plus the four architecture findings and the JSON
decoder notes recorded below and under
`audit/evidence/2026-09-19/application-workspace/` and
`workspace-wire-readiness/`. Evidence is kept proportionate from here (third
row of the same section).

**Next, in order:** revise `mo-wiki/plans/mo-application-workspace-v1.md` for
the rebuild; fresh Opus worker in a new worktree (use a new branch name, the
old one is taken); lead acceptance; then the scripted Logstat repair slice;
then live provider integration, which needs Robert for the subscription login.
Still open from before: Step 39 unaccepted, Darwin `F_FULLFSYNC` unmet,
Program 7 suspended pending a versioned replacement scope.

**In flight, 19 Sep 2026, 7:22 AM ET:** Opus worker `app-workspace-v2-opus`
(Herdr `w4:p2K`, Claude Code, Opus 5 confirmed at startup, accept-edits with
shell allowed) on branch `harness/application-workspace-v2`, worktree
`~/Projects/startups/mo-lang-worktrees/harness-application-workspace-v2`, base
`030290b8`. Brief revised at `10a9e1a8` (seven carried findings RED first,
evidence under 2 MiB). Released for local work and focused both-runtime tests
only; machine runs and the full suite stay lead-gated. Follow with
`herdr agent get/read app-workspace-v2-opus`. Workers from here on start with bypass permissions (Robert, 7:33 AM ET).

**Overnight work reviewed, 7:42 AM ET:** four Opus source reviews are in
`audit/evidence/2026-09-19/fable-overnight-review/README.md`; four decision-log
rows. All ten components kept; recovery's machine-side `recover()` to be
rewritten and its acceptance qualified. Queue after the application workspace
worker reports: (1) executor/workspace-HTTP fix brief (E1, E2, E4, E5, H1 to
H7), a fresh Opus worker with bypass permissions; (2) recovery rewrite (E3, E7);
(3) Mo agent test fixes (M1 to M8); (4) provider live blockers (P1 to P5) with
the live-provider slice. Check the rebuilt adapter against H4 and H5 at
acceptance. The lead's own full-suite run on `main` is still owed; not run while
a worker uses the host.

**Robert, 8:08 AM ET:** fix all review findings, and refactor so the harness is
Mo wherever possible, Python/JS at their minimum, Astra's verbosity cut
(decision-log row). An Opus design map of the non-Mo code is running; its
result decides the migration briefs and replaces the plain fix queue above
where a module moves to Mo anyway. Robert answered at 8:11 AM ET: yes, Mo gains a
scoped child-process capability (decision-log row); the lead writes its design
page next, from the design map.

**Plan of record, 8:13 AM ET:** `mo-wiki/plans/mo-harness-in-mo.md` (nine steps;
replaces the plain fix queue above). Lead-verified on the way: `Fs.scoped` is
lexical only, so a symlink inside a scope escapes it; fixing that is the first
toolchain step. Next lead actions: accept the rebuilt application workspace
(merged locally at `ddd81c06`; build exit 0, full suite running), confirm the
worker's toolchain defect (raw memory printed by the native binary on reports
over about 0.35 MB), then launch steps 1, 2 and 8 in parallel and write the
design page for capabilities 1 to 3.

**Application workspace acceptance, state at 8:22 AM ET (not accepted yet):**
merged locally at `ddd81c06`. Lead build exit 0. Lead full suite: 242 of 243,
exit 1, 8:18 AM ET; the one failure is the TLS corpus test "a fatal alert where
a hello belongs is Handshake and a reset mid-hello is Closed" (found `Handshake`
where `Closed` was expected). Rerun alone five times under the guard: 4 pass, 1
fail. The slice touches no TLS or toolchain source, so this is a flake in the
TLS brick, measured at about 1 in 5, and belongs with step 39; it is not
explained. Still owed before acceptance: lead probes beyond the brief, the
machine run through `live.py --application`, and a toolchain brief for the
worker's defect (native binary prints raw memory on reports over about 0.35 MB;
interpreter panics at `vm.zig:1531` over about 0.8 MB; reproduce at worker
commit `5caec127`, before the 256 KiB cap). Robert asked at 8:20 AM ET that any
Python-to-Mo size reduction be verified and documented: the protocol is "The
size question" in `mo-wiki/plans/mo-harness-in-mo.md`.

**In flight, 8:22 AM ET:** two Opus workers with bypass permissions, both based
on `e87879a4`: `step1-executor-opus` (Herdr `w4:p2M`, branch
`harness/step-1-executor`, brief `mo-wiki/plans/mo-harness-step-1-executor.md`)
and `step8-agent-opus` (`w4:p2N`, branch `harness/step-8-agent`, brief
`mo-wiki/plans/mo-harness-step-8-agent.md`). Neither may run the full suite or
touch the machine. The finished `app-workspace-v2-opus` pane (`w4:p2K`) stays
open until its acceptance. The lead meanwhile writes the capability design page
(strict scope, `Fs.replace`, `platform.exec`). Local `main` is ahead of origin
and holds the unaccepted merge `ddd81c06`; push after acceptance.

**Step 1 worker done, 8:41 AM ET; lead verification in progress, 8:43 AM ET:**
`harness/step-1-executor` at `cf5ed57b` (3 commits, 34 files, +575/-898) merged
locally at `97202a81`. Lead reruns under the guard: executor unit tests 96 OK
exit 0 (84 before), application 25 OK, `workspace_http/local.py` 22 OK exit 0.
Python went from 6,688 to 6,326 counted lines, far less than the design map's
estimate of about 1,000 removed: the estimates on `mo-harness-in-mo.md` are
optimistic and stay unverified. Semantic change to review with Robert: the
machine no longer powers off on an unconfirmed cleanup, only on proof that the
candidate's cgroup is still populated; an unconfirmed cleanup leaves evidence
and the armed reaper but **nothing yet refuses new runs on that machine**
(follow-up for the Mo server step). The host's `orbctl stop` follows the same
rule, reversing an accepted test. Worker gaps: three provider READMEs and
`auth/attempt.sh` still name deleted runners (outside its `.py` scope);
rewired provider scripts never ran; `recovery/readiness_probes.py` already
failed to import before. It edited two strings in `recovery/live.py`, which the
step 2 worker must know. Machine reruns owed, one at a time: `selftest.py`
(lead run 8:44 AM ET: 17 of 17, exit 0, inventory unchanged), `test_lifecycle_live.py`, `test_workspace_live.py`,
`recovery/live.py`, `workspace_http/live.py`, `application/controls.py`,
`inventory.py`; plus two real-machine E1 checks (the reaper reads
`cgroup.events`; a stalled daemon leaves `cleanup_unconfirmed` without power-off).

## Historical: Astra's overnight instruction and final state, 19 Sep 2026, 12:10 AM to 7:01 AM ET

Robert clarified the workflow: **Astra remains lead in this continuing Mac
session; spawn fresh Astra workers at low reasoning in Herdr panes.** There
is no oracle on the Mac and no oracle requirement. This supersedes Amp orb
workers, medium reasoning and the prior workflow question. Launch/ownership
details live in `.claude/skills/mo-lead/SKILL.md` and `CLAUDE.md`.

Robert then asked the lead to keep working while he sleeps, make any decisions
including those needing his approval, and keep moving. **The earlier harness
implementation pause is superseded.** The lead chooses bounded setup and
implementation slices, establishes technical readiness, delegates code,
independently verifies and records checkpoints. An interactive login may need
Robert later; use provider fixtures and continue independent work meanwhile.
Do not broaden this into unrelated work or waive outstanding evidence.

Herdr 0.9.0 is running; the lead is in the `mo-lang` workspace. A fresh worker
was actually launched with `gpt-6-astra` and `model_reasoning_effort="low"`,
confirmed in its startup UI. Its read-only executor review is retained under
`audit/evidence/2026-09-19/executor-readiness/`; its pane was closed after
receipt. Rediscover pane IDs before further work.

### Active work, 19 Sep 2026, 7:01 AM ET

Ten bounded foundations have independent lead acceptance: terminal401, offline
provider, BusyBox executor, workspace, coding fixture, private auth, native-history
provider bridge, isolated application builds, cleanup-only recovery and workspace
HTTP. Recovery acceptance published at68e50ed6; wiki35432372898 succeeded. HTTP
is accepted atcf99cd88e186cf293a4112582fe2d26a0f7b69ff after independent full
compiler and cross-attempt closure. Acceptance/docs commit is030290b8918e356be5588da2b12ad4e494aeac00.
Publicationd715f13f8a4c4cf0bfcd9ae720c240abf0e72b20 and wiki35438223776 succeeded.

HTTP worker42015b73cce5f4f97d4479413354780c94b13e6c is clean; product freeze
1cf268b356a63665214ca8331bfc55828b643603. Exact6211 new owned paths,6210 manifest
entries and production/contract/seven-core-file hashes verified. No compiler,
provider or Mo source changes. Final evidence-only transfer matches exact worker
tree; all commits have actual Astra author and committer. Historical worktree
harness-workspace-http-v1 remains preserved. Former worker w4:p28 returned its final idle receipt;
its runp29 and workerp28 are closed after fresh done/process proofs. No worker machine or
compiler commands remain. Machine is explicitly lead-owned.

Lead HTTP local22/inherited59 and six invalid-selection controls pass. Actual
HTTP22/22 on BusyBox and22/22 application pass, plus real review2/2 on BusyBox
in each attempt. Inherited workspace22/executor17/lifecycle1/application23 pass
sequentially. Independent pipeline and escaped-JSON limit controls both pass:
second request executes no tool; completed result_too_large preserves later valid
admission. Positive per-attempt resource absence, exact active parents/pins and
shared5 unchanged. All17339 tracked toolchain/examples bytes remain unchanged;
local verified15763 before final evidence integration. Raw attempts and launch
receipts live at audit/evidence/2026-09-19/workspace-http/.

Full integrated build/test passed243/243,5/5,outer0 in409.32s; no machine work
concurrently. Cross-attempt closeout-01 proves100 execution resources/131 recorded
workspace IDs/97 actual cgroups absent,34 local groups gone, active exact parents/
pins/shared5 unchanged.17339 tracked files unchanged;48 capability values absent
from retained nonsecret bytes,2696 manifest entries. Largest attempt10,819,838bytes.
Lead runw4:p1D shell47832 is idle. Two owner-SIGKILL gzip streams lack final
footers; each recovers five complete JSON rows. gzip-review-01.json retains the
failed strict inspection and limitation; no claim about in-flight response bytes.

Independent immutable drain probes retained2/2 RED on75680 and2/2 GREEN on83a72.
Fragmented IPC probe retained200/success at2.413s on83a72 for2s wait; identical
probe1cf returns504/unknown at2.00343s. Corrections use absolute receive deadlines
and terminal completion check. Worker first cleanup refusal is retained: delete
now<=55s plus core transport allowance inside60s. Actual numeric60.05 rejected/
55 accepted control is recorded without a clock-skew explanation. Worker full
243/243 was pre-IPC-correction; lead full is required on final source.

Next: fresh Astra/low implementation worker for
mo-wiki/plans/mo-application-workspace-v1.md, then a separate scripted Logstat
repair/protected-verification slice. Fresh mo-application-workspace-v1 is in
w4:p2E/tabw4:tP, actual Astra/low PID19318, shell19087, exact base030290b8, branch
harness/application-workspace-v1 in the corresponding historical worktree root.
Local implementation and focused Mo I/native builds/tests released; machine/full
gates closed. It may copy the accepted lead Mo binary read-only (SHAacf1d593).
Owned runpane isw4:p2F. Adapter checkpoint0a74a0fc3a679eb98dd1c31892a32e6b41b3cbdb
passes6 interpreter/6 native tests, actual Astra author+committer; application/Run
work is separate and uncommitted. Lead raw/config review finds no scanner defect;
large-request near-expiry dispatch remains a boundary check. Fresh Astra/low
wire reviewerp2H/tabtR (PID23437, now closed after done/process proof) identified three source-backed gaps assigned
for retained RED/fixes: null-ID preadmission refusal loses not_started; unaccepted
response can accept HTTP500/busy; success command accepts null output. Follow-up
confirmed mixed-null streams and success/exit1 inconsistencies; both assigned
as additional RED controls. First12 interpreter loopback cases passed on the
pre-correction source. Worker retains five wire REDs and corrected11-test I green;
native/final integration still pending. No machine release.
Exact snapshot and reviews are at audit/evidence/2026-09-19/application-workspace/.
See application-worker-release-01.json. Lead readiness
reviews are in audit/evidence/2026-09-19/workspace-wire-readiness/; reviewerp2C
andp2D closed after done/process proofs. Four architecture findings incorporated:
fresh runs-directory preflight before Open, all-six-tool terminal classification
after recording, stopped/unsettled reporting_error, outer-deadline ReportDeadline.
JSON reviews establish existing decoder duplicate collapse and non-atomic read
bounds. Draft uses grammar decode plus raw-colon/decoded-member count and integer
lexical checks; worker must prove both runtimes.4096 config/524288 response are
acceptance limits, not runtime allocation limits. Token stays outside Book/model.

Machine mo-executor-r01 remains exclusive lead-owned, no competing workload.
Existing active parents: mo-executor.slice512MiB/CPU1/PIDs128 and
mo-application.slice1536MiB/CPU1/PIDs192; outer2GiB/CPU2/swap0. No image, resource,
configuration or /opt changes. Application image
sha256:b9fda4ae85f369e475e0f412e15dea9044a849a64bc2ec94bb3bc5a661eab3c4;
manifest d31b5c5e7e1912f98eba21268854d0f7b830dba7048b2de0e2c0458d10e507eb at
/opt/mo-harness/application-build-v1/package-02/package/manifest.json.
Trusted Linux Mo and Zig remain under /opt/mo-harness, unchanged.

Separate source-only Logstat reviewer p2G is closed after receipt. Readiness
source-review-01.md/design.md under audit/evidence/2026-09-19/logstat-readiness/
proposes defaulttop5-to1, an explicitly unverified prepared Main fixture to avoid
stale-footer MO0317, all four external goldens/eight preserved Main tests, direct
readonly-source builds and protected wrong-source/forged-output controls. This
is not released implementation or measured semantic RED; app acceptance comes first.

Keep prior failures honest: recovery malformed successful snapshot has no retained
raw response and remains unexplained; later inactive slice was a separate proven
readiness error. Two operator cases each remain14 confirmed/1 unresolved despite
separate physical cleanup. Earlier TLS ordering/TCP-count failures remain unknown;
later full passes are not fixes. Step39 unaccepted, Darwin full-sync unmet,
Program7 suspended. No live provider acceptance or matched language-value claim.
Lead w4:p1 owns wiki/HANDOFF/audit/integration; workers alone write toolchain/examples.
Continue autonomously while Robert sleeps. Do not stop at a checkpoint or publish
audit outbox records; initial pointer-only auditor check found zero new records.

## Historical checkpoint: Mac arrival, 18 Sep 2026, 11:58 PM ET

Robert asked this Codex (GPT-6) session to continue the handoff. Read-only
arrival checks are recorded in `audit/evidence/2026-09-18/mac-arrival/`.
This checkout was clean on `main` at handoff commit
`3b6c75360a1d76721be62080f6771d871d2abd40`, equal to fetched `origin/main`;
no integration or restoration was needed. All 68 registered worktree paths,
70 local branches, the private transfer package and existing auditor ledger
are present. This verifies presence, not archive integrity or historical
worktree contents. The pointer-only auditor check found zero new records.

Native Mac: M3 Max, arm64, 96 GiB, Zig 0.16.0. OrbStack 2.2.3 and its Docker
29.4.0 Linux backend are reachable through the existing `orbstack` context.
There are no named OrbStack Linux machines; no dedicated test boundary, Linux
checkout or Linux Zig binary is verified. Existing Docker containers are from
other projects. No service, container, Docker context or resource setting was
changed. Do not replay the orb probes on this shared daemon.

**Workflow clarification pending:** this Codex session has no callable Amp
oracle or native Amp thread tools. Robert has been asked whether to adapt the
lead/review workflow to Codex with a separate reviewer or preserve Amp. No
substantive design decision, worker, setup, login or experiment has started.
Continue with that workflow choice and the harness brief's bounded readiness
items. Step 39 stays unaccepted; Program 7 stays suspended.

## Prior instruction: Mac handoff, 18 Sep 2026, 11:44 PM ET

Robert confirms OrbStack works on his Mac and explicitly wants **the Astra lead
to move there too**, not merely use it as a remote executor. This supersedes the
earlier requirement to keep the lead in this orb thread. Keep one continuing
lead session after relocation; do not create a new lead for each phase. Workers
remain separate fresh `medium`, `a1.xxlarge` Amp orb threads unless Robert
changes that instruction. Do not revert to Herdr/Opus mechanics.

Source conversation:
https://ampcode.com/threads/T-01a0b649-dbdd-7299-b541-d4c48f1aecf4. This file is
the portable context if the conversation cannot be continued in a Mac-backed
session. Preparing it does not relocate a thread or select a model. No Mac
checkout, runner, Docker context or credentials have been inspected here.

### Resume in this order

1. Load `mo-lead`, then read this current section, `mo-wiki/SCHEMA.md`, the top
   of the roadmap/state page, and the latest decision/log entries. Inspect the
   Mac checkout's status and branch before syncing; preserve existing
   uncommitted work, local commits and historical worktrees. Fetch and integrate
   the handoff commit without reset, forced checkout or blindly replaying old
   patches.
2. Run the lead's pointer-only auditor check. Its private receiver ledger is
   machine-local: preserve an existing Mac ledger; do not interpret a fresh
   ledger as proof a record was never handled. Never open an auditor reading
   before the lead's own reading of that subject is on `main`.
3. Verify the Mac/OrbStack destination read-only: exact repository and revision,
   architecture, Zig 0.16, Docker context/endpoint and Linux VM availability. Do
   not assume the native Mac and VM share files, binaries or paths. Existing
   `~/Projects/startups/...` paths below are historical, not validated targets.
4. Review `audit/evidence/2026-09-18/executor-feasibility/README.md` and
   `mo-wiki/plans/mo-first-coding-harness.md`. The orb proved a bounded
   container configuration feasible, not production-safe, Mac-verified or a
   finished Mo executor. Adapt probes to a dedicated OrbStack test boundary
   before proposing another run; do not copy the Amp cgroup commands onto macOS
   or a shared daemon.
5. Continue readiness one bounded piece at a time: executor lifecycle and
   protected verdicts; provider support/client identity; exact write scopes and
   acceptance owner; versioned 401 policy and scoped budgets. Staged readiness
   is allowed, but no prerequisite is silently waived. Confirm readiness and
   obtain a bounded start before implementation workers. No OAuth login starts
   merely because this handoff is loaded.

### What completed in the orb

Robert separately approved credential-free feasibility probes, temporary rootful
Docker setup and a reversible CPU-controller adjustment. The final probe run
exited 0 with nine PASS records: effective cgroup limits, filesystem/process
restrictions, network denial, CPU throttling, memory exhaustion, PID limits,
scratch capacity, deadline/descendant cleanup and capped output. Two earlier
runs failed in the probe (PID observation race; blocked output attach); their
raw outputs are retained, not hidden. No Mo harness/compiler code changed.

The temporary daemon, containers, image and fixture files were removed; its
socket and service are gone. All three ancestor controller sets and the
workload's numeric limits were restored. Docker/runc had enabled additional
ancestor controllers, so future executor setup must own a dedicated delegated
subtree rather than silently modifying shared ancestors. No packages or images
were downloaded, no real credentials accessed, and no workers or login started.
The probe approvals are completed, not standing permission to alter the Mac.

The audit's requirements remain: Step 39 unaccepted, Program 7 suspended, no
Linux result substitutes for Darwin `F_FULLFSYNC` evidence. OAuth subscription
support/registration and real account/model entitlement are still unresolved; Pi
is a provisional provider-only adapter, not approval from OpenAI. The separate
TypeSafe report-check proposal remains unbuilt; sending logs out is unapproved.

## Earlier planning checkpoint (superseded where the Mac handoff differs)

**Worker configuration, Robert's latest instruction (18 Sep 2026, 11:01 PM
ET):** use Amp orbs, Astra as lead, and a separate fresh thread for every worker
and every new work unit/phase. Worker mode is `medium`; orb size is
`a1.xxlarge`. The lead remains in this same thread; new phases create worker
threads, not replacement lead threads. Active guidance now uses Amp's native
thread tools and separate checkouts, superseding the historical Herdr/Opus
mechanics below, not code ownership, verification or audit rules. Do not inherit
the lead's model for workers. No thread/model switch or worker launch occurred.
Transfer unpushed state explicitly between threads; never assume shared trees.
Integration and verification remain in the lead checkout.

Robert requires the Mo harness itself to use his OpenAI subscription via its own
OAuth login, not an API key or borrowed Amp credentials. Pi's pinned
provider/auth package supports device login suitable for an orb. The lead/oracle
recommend a thin provider adapter, keeping Mo's agent/tool loop; registration
support, account/model access and credential isolation are not yet verified. The
brief records details. No live login request was made; generate and relay the
actual verification link/code only when a real authorized flow starts.

Robert approved the lead's choice of a Mo-first coding harness written in Mo,
initially maintaining existing Mo applications, on 18 Sep 2026. The bounded
brief is `mo-wiki/plans/mo-first-coding-harness.md`: thin headless CLI,
machine-readable events, externally isolated execution, protected acceptance,
and actual Pi as the practical comparator. Reuse the existing Agent selectively.
No self-editing, compiler changes, full TUI or plugin ecosystem initially. The
next lead action is resolving the brief's readiness checklist, not asking Robert
to choose the application again. Provider/executor details, exact worker scope
and trial budgets still need decisions; no readiness confirmation or worker
launch is recorded. The implementation pause remains.

The final attachment labelled DeepSeek was byte-identical to the supplied Kimi
review (`cmp` and SHA-256 checked). Four distinct review bodies, not five; the
cause of duplicate attribution is unknown. No new verdict follows from it.

Robert approved an agent-native reframe: agents write and read code; humans
judge requirements, behavior and evidence. Mo is an additional functional,
statically typed, compiled, BEAM-inspired option, not a replacement. Prioritize
the fast, trustworthy discover/learn/edit/check/run/inspect/repair/verify loop
for existing features over expansion. The current premise and roadmap carry the
details; the decision log records the authority and unresolved proposals.

**Program 7 execution is suspended and its BEAM-superiority thesis and runtime
retirement framing are superseded.** Preserve sealed specs and audit evidence;
do not score the old experiment as passed, start builds or request a new seal.
Replacement scope and acceptance criteria remain open. Neither capabilities
requirements nor the separate contract-catch rule are waived by this decision.

The four research reports are received, preserved and synthesized with the
oracle in `mo-wiki/research/concepts/agent-native-research-synthesis.md`.
Selected source checks found overstatements; the reports are not new acceptance
rules. The evidence attachment labels itself an auditor draft; it was read in
the research batch before a new independent reading, so this synthesis is not a
cold audit reading. No hidden suite was opened.

Robert agreed to discuss a bounded maintenance task first. The Agent model-call
401/retry change, onboarding comparison and small model pilot are proposals, not
a locked experiment. The self-contained external review prompt is
`mo-wiki/research/prompts/agent-native-independent-review-prompt.md`: reviewers
have web access and may challenge everything, including building a language.
Robert will gather opinions; the lead should compare reasons and evidence, not
count votes. No outside review or documentation commit authorizes execution.

Robert requires oracle use for substantive lead evaluations and decisions. **No
workers, setup, experiments or implementation until Robert explicitly approves
starting and the lead confirms readiness.** Documentation maintenance is
authorized; no implementation or security strategy is accepted. We remain in
discussion and revision.

At the 18 Sep 2026, 9:36 PM ET checkpoint, four external strategic reviews have
been compared with the oracle; a fifth was pending. Robert agreed to the revised
sequence: trustworthy instruments, then the 401 workflow/onboarding pilot, then
a useful application compared with a well-equipped existing-language option. The
pilot is not proof of language value. Before it, obtain approval for a versioned
recipe-policy change (shared recipe versus Agent specialization). At that
checkpoint the application and comparator were open; the choice above now
supersedes that question. The lead records agreement with the direction, not a
bounded execution start or readiness confirmation. See the external-review
section of `mo-wiki/research/concepts/agent-native-research-synthesis.md`; the
original review packet remains unchanged. No audit obligation is amended.

Upstream changed TLS and benchmark scripts during this discussion. Those changes
were fetched and preserved, not tested or accepted here. Older statements that
C/D's patch is unapplied are historical: inspect the current tree and patch
before any future application; never apply the saved patch blindly. Step 39
remains unaccepted; the old evidence counts below are checkpoint results, not
fresh measurements of current main. Private environment restoration is still
unverified.

## Historical checkpoints below

These preserve the prior queue and evidence, not authorization to restart it.

Robert authorized Amp to take the lead role in the Linux Amp orb. Read the audit
checkpoint below first; the older move and Mac notes are historical context. The
roles, the Herdr worker loop, the acceptance checklist, and the audit exchange
live in the `mo-lead` skill (`.claude/skills/mo-lead/SKILL.md`), which
`CLAUDE.md` tells every session to load; this page holds only the state, the
queue, and what a fresh session must know that the wiki does not say in one
place.

## Previous checkpoint: lead transition and PR 12 reviewed

18 Sep 2026, after the 5:28 PM ET harness reproductions. Amp filed
`audit/fable-reading-2026-09-18-current-state.md` on main before opening the
auditor's conclusions, then merged PR 12 unchanged. The comparison is
`audit/fable-comparison-2026-09-18-current-state.md`; fresh raw controls are
under `audit/evidence/2026-09-18/current-state-lead/`. No substantive
disagreement with the audit at its anchor; no implementation accepted.

Step 39 stays first and incomplete at the exact checkpoint below. Its A/B fixes
postdate the audit's TLS reproductions; worker outputs now pass those specific
cases, but independent acceptance and Limbo's zero gate are owed. Before further
acceptance, fix false-success status propagation, empty selection, fuzz-batch
counting and abuse stimulus/state scoring, with negative controls. Preserve
sealed suites and historical evidence. A reproducible Zig/corpus CI gate is also
owed; the site deployment is not one.

Program 7 remains pre-build: fresh-server Redis checks and the lead-owned skip
list; R2/RC1/R4 reconciliation with the ratified rules (recommendations in the
comparison and decision log, **not amendments**); then the auditor's seal.
Resolve binary-safe Conn input, R5's missing snapshot/log restore path, and the
directory-sync durability boundary before briefing the builds. No hidden suite
was opened and no retirement rule triggered.

No worker or experiment started in this audit review. This orb has Zig 0.16, one
registered worktree and no Herdr executable on PATH; the private transfer and
previous worktrees are **not verified as restored**. Keep the worker role and
Mac-only acceptance obligations; do not substitute a Linux run for Darwin
full-sync evidence. C/D's patch is not applied here and passes apply-check.

## Previous checkpoint: stopped and prepared for Robert's cloud move

**18 Sep 2026, 4:33 PM ET; Codex (GPT-6).** Robert asked to wrap the worker
up ASAP and will perform the move himself. The worker stopped at its nearest
safe checkpoint and its session is ended. **Do not resume the queue on this
Mac or perform the transfer.** No wake-up timer remains.

### What is saved

- Parts **A `faec6b5` and B `18d45a6`** are pushed. Worker suite outputs:
  A 240/240, B 242/242, exit 0. These are not the lead's acceptance runs.
- **C/D are WIP**, saved in `bba9fda` as
  `toolchain/bench/step39/wip-parts-c-d.patch`, with `WIP.md` and raw outputs.
  The Mac still has those same five source edits applied; their diff is
  byte-identical to the committed patch and the reverse-apply check passed.
  **Apply the patch only to a clean clone; do not apply twice.**
- **E/F not started. Step 39 and the TLS brick remain unaccepted.**
  Limbo has 27 accepted-but-should-reject against the required zero; C's abuse
  run is 63/64. The worker's proposed explanations/defaults remain for the
  next lead to decide, with no threshold silently changed.
- **Darwin `F_FULLFSYNC` is still unimplemented**. There is no Mac call-counter
  trace or before/after measurement to carry; Mac verification will still be
  needed when F is implemented. Linux cannot satisfy that gate.
- Full worker report, suite logs, exact patch and inventory:
  `audit/evidence/2026-09-18/step-39-move-checkpoint/`. The worker's
  `toolchain/bench/step39/WIP.md` gives the continuation commands.

### What Robert should carry

The verified private transfer package is
`~/Projects/startups/mo-lang-transfer-2026-09-18/` (README and SHA256SUMS
included). It holds a Git bundle of all local branches/tags, an archive of
local-only files, the exact main WIP patch, a 68-worktree inventory,
`MOVED-2026-09-18.json`, and the private `fable-intake.json` receiver ledger.
Sixteen of the 70 local branch names have no same-name origin ref: **a fresh
GitHub clone alone does not preserve the full local state**. Use the bundle
and inventory, and preserve the old checkout/worktrees until the restored
state is verified. Rebuild native binaries and dependency environments on
Linux. The private package README explains fetching the final documentation
checkpoint after restoring its worker-checkpoint bundle.

### On the VM, when Robert resumes

Read the cross-provider note and lead skill below. Check the auditor inbox with
`git fetch origin && python3 audit/automation/fable_poll.py check` before
opening any auditor file; file the new lead's own reading first. The
`audit/2026-09-18-current-state` review is now integrated as PR 12; see the
latest checkpoint above for its acceptance prerequisites. Apply C/D's patch once
in a clean tree, resume Step 39 in a fresh Opus worker, then complete the
original lead acceptance list before marking the TLS brick complete.

Redis's OrbStack Linux baseline is preserved and published as
`program-7-spec-evidence-updated-linux-001` (`61c0614`, evidence at
`85093fa`): 22 files attempted, 909 ok, 5 err, 22 ignored, 3 exceptions and
3 timeouts. The script reuses one server; two exceptions show leftover
background activity, so fresh-server checks and `07c-mored-skip-list.md`
remain owed. After Step 39: the Linux Go 30,000-job rerun; instrument fixes
with negative controls; change 7 and its pre-seal smoke run/auditor reading.
Program 7 still cannot start before the auditor's sealing session on
`program-7-spec-ready-002`. The older queue below is historical until resumed.

## Historical Mac handoff (superseded by the checkpoint above)

The cross-provider note and standing role rules below still apply. Its old
pane IDs, active-worker status, machine description and next-work instructions
are historical; use the current checkpoint and discover the VM panes afresh.

> We're continuing the Mo language build. **This session runs on Robert's Mac**
> (M3 Max, 14 cores, 96 GB; `herdr pane list` shows the machine; the lead's pane
> is `w4:p1`; worker and run panes are split to the **right**, never below).
> Load the `mo-lead` skill first and follow it: you are the lead, Opus workers
> in Herdr (medium effort, one fresh session per piece of work) write all code;
> Robert reviews the decision log. **His standing rules:** you make the
> decisions and keep the work moving, never stop to ask him (a question is a
> decision-log row); every run or spawn goes in a fresh Herdr pane of his
> workspace, closed when its result is read; the roadmap board is his status
> view, rewritten at every acceptance and pause; **every time you give him is US
> Eastern, read from the clock (`TZ=America/New_York date`), never guessed**
> (the lead guessed four timestamps on 18 Sep and had to correct them); reports
> at a high level, the detail on the pages. The lead commits with
> `git commit -m <msg> -- <paths>` only. Every brief tells the worker to run
> every `mo`, server, bench, and test process under
> `toolchain/bench/step36/guard.py`. **Before any other work, the auditor's
> inbox:** `git fetch origin && python3 audit/automation/fable_poll.py check`
> (pointers only; the skill's Receive bullet; never open an auditor file before
> the lead's own reading of that subject is on `main`; note that the ledger is
> per machine). Then read, in order: the section "The morning of 18 Sep, in one
> screen" at the top of `mo-wiki/state-of-the-project.md`; `mo-wiki/SCHEMA.md`;
> the board at the top of `mo-wiki/plans/roadmap.md`; the last entry of
> `mo-wiki/log.md`; the last twenty-five rows of
> `mo-wiki/decisions/decision-log.md` (the morning of 18 Sep is all there, most
> rows "for Robert"); `CHANGELOG.md`'s "Session 12";
> `mo-wiki/plans/interpreter-step-39.md` whole; `toolchain/bench/step39/WIP.md`
> (the stopped worker's notes);
> `mo-wiki/spec/programs/07b-redis-subset-revision-2.md`; `audit/README.md`,
> `audit/WORKFLOW.md`.
>
> **If you are a lead from a different AI provider (added 3:06 PM ET, 18 Sep 2026).**
> Robert's Fable credits are low and he may continue with another model as
> the lead. Nothing about the role changes, but three things will not happen
> for you automatically: (1) the lead's skill does not load itself: **read
> `.claude/skills/mo-lead/SKILL.md` as a plain file, whole, before anything
> else**, then `CLAUDE.md`; it is the role, the worker loop, the acceptance
> checklist, and the audit protocol (never open an auditor's file before your
> own reading of that subject is on `main`; you sign readings as the lead,
> and say in each which model you are); (2) there is no wake-up tool: check
> the worker by hand about every 20 to 30 minutes with `herdr agent list`,
> `herdr pane read <pane> --lines 40`, and `git log origin/main`; (3) commit
> trailers name the model that did the work (the workers' stay `Claude Opus
> 5`; use your own for the lead's commits). The workers stay Claude Opus in
> Herdr as the skill says. The decision log's rows signed "Fable" are the
> previous lead's; sign yours with your own name so Robert can tell them
> apart.
>
> **Update, 18 Sep 2026, 3:05 PM ET (read this before the State below).** Robert is
> low on Fable credits: the lead checks the worker about once an hour, does no
> side work, and **pauses when step 39 is accepted**. A second step 39 worker
> (`mo-opus`, pane `w4:pA`, started 3:01 PM ET) continues from
> `toolchain/bench/step39/WIP.md` with the lead's answers (a test-only row for
> the simulator's fault count: the decision-log row of 18 Sep); it commits and
> pushes `Step 39 part X` after each part, so if this session ends first, look
> at `git log origin/main` for how far it got, read its pane or its last
> report, and run the acceptance at the foot of the brief. A Linux baseline of
> Redis's suite runs in pane `w4:pB` into
> `audit/evidence/2026-09-18/program-7-spec-r2/linux/baseline.txt` (then the
> README's table, an `evidence-updated` record, and the skip list as
> `mo-wiki/spec/programs/07c-mored-skip-list.md`). Go's 30,000-job rerun on
> Linux is still owed. The worktrees are in
> `~/Projects/startups/mo-lang-worktrees/`.
>
> **State (18 Sep 2026, 12:40 PM ET).** Everything is on `main` and pushed.
>
> 1. **Five auditor readings and one research note** (PRs 7 to 11) received,
>    Fable's readings filed first each time, **every finding conceded**, six
>    `parallel-filed` records sent. No disagreement is open.
> 2. **The TLS brick is not complete** (its client accepts four certificate
>    chains OpenSSL rejects; ALPN past 64 names; the fuzz count; a corpus test
>    that tested nothing). **Step 39** (`interpreter-step-39.md`) is the
>    correction, plus `F_FULLFSYNC` on macOS and a client that refuses plaintext
>    records once handshake keys exist. Its worker started at 12:01 PM ET and
>    was **stopped for this pause** at part A; its notes are
>    `toolchain/bench/step39/WIP.md` (and a patch beside it if part A was not
>    green). Its gate is the auditor's own `chain-checks.py`, unedited.
> 3. **Generation six run, read, and compared with the auditor's reading**
>    (`mo-wiki/plans/erosion-round.md`, the result and the correction note above
>    it): nothing eroded, Mo's generation-five defect fixed, the lease path back
>    to change 3's rate; P1 not met as written (Mo carries one real validation
>    defect, `job.mo:503`), P3, P4, P6 failed, P7 void. **The language rule's
>    ledger: zero catches at six of ten, threshold two.** Go's budget row was
>    rerun at 30,000 jobs
>    (`erosion-round-suite/results/e6-speed-go-30k-again.txt`): read it and add
>    its rows to the correction note and a row if that is not yet done.
> 4. **Step 38 accepted** (11:59 AM ET): duplex `Conn`, `TCP_NODELAY`, 64 abuse
>    cells; `step-38-ready-001` is with the auditor.
> 5. **Program 7's spec, revision 2, sealed and published**
>    (`program-7-spec-ready-002`). **Waiting on Robert:** the auditor's sealing
>    session (hidden suites, seeds, the P4 change). Before the builds the lead
>    owes: Redis 7.2.4's suite run against Redis itself in `--host` mode **on
>    Linux**, all 22 remaining files (the Mac run was partial: 649 tests in
>    eight files, one exception, one hang), then
>    `examples/programs/mored/tests/skips.txt`.
> 6. **On macOS Mo's `fsync` does not reach the disk** (Go's does): Mac speed
>    comparisons with Go are withdrawn; program 7 is measured on Linux.
>
> **The queue** (the board is the authority):
>
> 1. **Step 39**: a fresh worker continuing from `WIP.md`, the same brief and
>    the same standing instructions as the first (they are in the log of 18 Sep
>    and the brief's Done-when), plus: run `duplex.mo` and other
>    scheduling-sensitive examples at `MO_CORES=1` in the corpus step. At
>    acceptance: the lead's list at the foot of the brief, the mutant run five
>    times at one core and at fourteen.
> 2. **Program 7**: the Linux baseline and the skip list; after the auditor's
>    seal, the Mo and Elixir builds on Linux.
> 3. **A toolchain step from generation six**: the simulator bounded on a
>    perpetual timer (the 13.4 GB process), `for _ in 0..n` as a counter, an
>    `Fs` row that syncs a folder.
> 4. **The instruments before generation seven**:
>    `control-run-8-suite/ oracle4.py` (it nulls Python's worker), `measure.py`
>    (counts intended creates, loses thread exceptions, prints a restart time
>    after a timeout), the runner's exit status; each with a negative control;
>    change 7 with the `/queues` sentence settled and the Mo validation defect
>    as a ticket; the seventh generation's suite smoke-run on generation six's
>    programs and **read by the auditor before its seal**.
> 5. (Done 18 Sep: every worktree now lives in
>    `~/Projects/startups/mo-lang-worktrees/<name>`; the skill says how to
>    read older `../mo-lang-<name>` paths.)
> 6. Placement for what `main` starts; chapter 10's sections; the brick cache;
>    the compile benchmark.
>
> **Things learned on the Mac today.** A sealed suite must be run before it is
> sealed. A runner must write every exit status and stop on a failed build
> (generation five lost a whole suite to a usage error). A mutant run once can
> pass by luck: the pre-step-38 runtime passed `duplex.mo` four times in five at
> fourteen cores and never at one. A probe is suspect before the runtime is: two
> threads on one Python SSL socket, an example server that exits after 200 ms of
> idle, and a wrong relative path each looked like a runtime failure for a few
> minutes. Redis's test runner works with Homebrew's Tcl 9; several of its files
> start their own server and hang or are skipped in `--host` mode.
> `herdr agent start` fails on a pane split less than a few seconds earlier:
> wait for the shell prompt. zsh does not split `$VAR` into words: name paths
> one by one in `git commit -- ...`. Editing a running bash script in place is
> unsafe: write a new file and `os.replace` it.
>
> **Things learned earlier** (kept). `ls`, `cat`, `tr`, and `find -type` are
> aliased: python3 in scripts. `echo =====` is a zsh expansion. macOS keeps 16k
> ephemeral ports to one destination and TIME_WAIT for 30 s: suites one at a
> time with their drains. `caffeinate -dimsu` for any long run. P6 on Mo and any
> `bench` that reads memory need `mo build --surface`. `mo build -o` takes a
> name under `zig-out/mo-build/<name>/<name>` relative to the working directory;
> two `mo build`s in one directory collide on the brick cache. A worker whose
> turn ends while a shell still runs must be prompted to continue. The intake
> rejects `RESULTS.md` and readings as record paths: raw files only. Herdr:
> `herdr workspace create --cwd`,
> `herdr pane split <id> --direction right --cwd`, `herdr pane close`,
> `herdr workspace close`;
> `herdr agent start <name> --kind claude --pane <id> --timeout 60000 -- --model opus --dangerously-skip-permissions`,
> `/effort medium`, then the brief.
>
> **Style.** Ruby-nice syntax, zero new syntax where possible, concise, define a
> PL term in three lines before using it, no phones. Fable drives. Report at a
> high level against the board; say what was verified and the numbers on the
> pages; say plainly when something is unmet, and when the error was the lead's.
> Verify with probes the brief did not name, on real inputs, with your own
> client, and suspect the probe first.

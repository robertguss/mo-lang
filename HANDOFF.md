# Mo Lang — Lead handoff after PR 12, 18 Sep 2026

Robert authorized Amp to take the lead role in the Linux Amp orb. Read the audit
checkpoint below first; the older move and Mac notes are historical context. The
roles, the Herdr worker loop, the acceptance checklist, and the audit exchange
live in the `mo-lead` skill (`.claude/skills/mo-lead/SKILL.md`), which
`CLAUDE.md` tells every session to load; this page holds only the state, the
queue, and what a fresh session must know that the wiki does not say in one
place.

## Latest checkpoint: lead transition and PR 12 reviewed

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

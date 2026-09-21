---
name: mo-lead
description:
  The lead's role and loop for building Mo. Use when starting or resuming a Mo
  session, briefing an Amp orb worker, accepting a step, or recording a
  decision.
---

# Leading the Mo build

Mo is a programming language Robert Guss and Claude are designing and building
in this repo. The wiki (`mo-wiki/`) is the record; `toolchain/` (Zig) and
`examples/` (the Mo corpus) are the code. `mo-wiki/SCHEMA.md` holds the working
agreements; read it first, every session, then `HANDOFF.md` at the repo root for
the current state and queue. **Then the auditor's inbox, before any other work**
(Robert, 17 Sep 2026, 6:25 PM ET: a fresh session's onboarding is the moment to
check the auditor's work):
`git fetch origin && python3 audit/automation/fable_poll.py check`, and act on
every line per the Receive bullet below; between sessions Robert passes on
anything urgent.

## Roles

The onboarding/audit loop is lead-only. Worker threads identify themselves as
workers, follow shared safety rules and their bounded brief, and do not run the
lead's audit inbox, publication/integration or decision-recording workflow.

**Orb workflow (Robert, 20 Sep 2026, evening ET):** this persistent Amp thread
coordinates the project. Oracle consultation is mandatory for planning,
substantive reviews and acceptance decisions; calling Oracle does not change the
coordinating thread's underlying model. Workers use fresh Amp threads,
`agent_mode: medium`, `executor: orb`, `orb_size: a1.xxlarge`. This supersedes
OMP, Herdr, fixed Sol/high models and Mac-only execution instructions, not
ownership, evidence or audit requirements. `HANDOFF.md` owns current readiness.

- **The lead (Astra, this same session).** Owns planning, briefs, substantive
  review, independent verification, acceptance decisions, documentation and
  coordination. May execute builds, tests and probes for acceptance. Does not
  write implementation code, including test or probe scripts; workers author
  those from lead-owned requirements. Never writes code or prose under
  `toolchain/` or `examples/` by hand. Owns the wiki, specs and audit records.
  New phases do not create replacement lead sessions.
- **The worker (Amp medium, separate xxlarge orb).** Owns implementation and all
  code, plus prose under `toolchain/`, `examples/`, and files its brief names.
  Every assignment, new phase, review or continuation of saved WIP starts a
  fresh clean Amp thread. Never resume, fork or import a previous conversation.
  Saved code and evidence may carry forward; conversational state does not.
  Worker wiki writes are limited to spec lines its brief names. Implementation
  uses its own orb checkout. Follow-up messages may continue the same bounded
  assignment; new units get fresh threads. No nested delegation.
- **Robert.** Reviews the decision log, not the queue. The lead's recommendation
  is the decision, made without waiting and recorded with who, status, and what
  first tests it. Overturning is cheap; nothing is a mistake at this stage. One
  question per message to him, code options first, a PL term defined in three
  lines before use, no phones. Every time given to him is US Eastern (Robert, 17
  Sep 2026; the VM's clock is UTC: `TZ=America/New_York date`), labelled ET, in
  reports, wakeup reasons, and the rows and pages he reads. Frame every report:
  where the work sits in the whole against the "Where we are" table on
  `mo-wiki/plans/roadmap.md`, what was verified, the numbers, anything unmet,
  said plainly.

## The auditor (Robert, 17 Sep 2026)

An independent auditor, a Perplexity session only Robert opens, reads raw
evidence and files `audit/mo-audit-<date>-<subject>.md`. Three stopping rules
there are ratified (runtime and capabilities on program 7, the language's catch
claim at erosion generation ten); read `audit/README.md` before touching any of
those subjects. The lead writes its own reading as
`audit/fable-reading-<date>-<subject>.md` before opening the auditor's file on
the same subject, files a disagreement as a decision-log row citing both, never
changes a ratified threshold or retirement mapping except by a row with a
reason, never opens or sits in an audit session, and never writes or reads a
hidden suite the auditor seals.

The loop with the auditor, as it runs today (charter option B, manual,
Robert-driven; `mo-wiki/plans/the-audit-workflow.md` is the wiki's account):

- **Before a round or a program:** the pre-registration (predictions, suites'
  shape, the P4 change) is on its page and pushed before any session starts; the
  report to Robert says "ready for `audit: pre-registration <name>`" so he can
  open the session. For program 7 the auditor also writes the hidden suites; the
  lead's spec is sealed first and the lead never sees those suites.
- **After a round or an acceptance:** the lead's reading is a decision-log row
  (pushed), and raw pointers and outputs go under `audit/evidence/<date>/` with
  a README in the charter's form (paths, branches, commits, numbers as printed,
  scripts that produced them; lead readings marked "open after your own").
  Workers author any new probe scripts to the lead's requirements; the lead
  independently runs and reviews them. Retain those scripts and outputs in the
  evidence bundle. The report to Robert says "ready for `audit: <name>`".
- **When the auditor's file lands** (`audit/mo-audit-<date>-<subject>.md`,
  Robert pushes or pastes it): the lead first writes
  `audit/fable-reading-<date>-<subject>.md` if its reading is not already a row,
  then reads the auditor's file, then files each disagreement as a decision-log
  row citing both files, "for Robert". A ratified threshold or retirement
  mapping changes only by a row with a reason, never in place.
- **Never:** open an audit session, paste the lead's synthesis into one, read or
  write a sealed suite, or amend a pre-registration once evidence is in view
  (the charter calls that a role violation).

**Automated since 17 Sep 2026, evening (PR #3; `audit/WORKFLOW.md`,
`audit/automation/README.md`, `audit/automation/FABLE-RECEIVER.md`).** Robert
relays nothing routine. The lead's side of the exchange, every time:

- **Ready.** Raw evidence committed and pushed first (the bundle under
  `audit/evidence/<date>/<subject>/`, the sealed brief). Then
  `python3 audit/automation/fable_poll.py publish --kind ready --subject <s> --id <s>-ready-<nnn> --commit <full sha> --path <raw>... --request "<bounded scope, no verdict>"`,
  commit that one file by path, push to `main`. Paths are raw outputs, scripts,
  corpus files, the brief: never RESULTS.md, the decision log, or a reading (the
  intake rejects them). Never edit a published record; a revision is a new id.
- **Receive.** Every fresh lead session runs `check` at onboarding, and Robert
  tells the lead mid-session when the auditor has posted something (his choice,
  17 Sep 2026, 6:20 PM ET: no cron on the lead's side); the lead then runs
  `python3 audit/automation/fable_poll.py check`, which announces the auditor's
  records with pointers only. `evidence-needed` → commit the evidence, publish
  `evidence-updated --in-reply-to <id>`. `reading-filed` → file
  `audit/fable-reading-<date>-<subject>.md` first if it is not on `main`, never
  opening the auditor's file, then publish `parallel-filed` naming both files at
  a commit containing both. `compared` or `escalated` → unresolved decisions
  become rows for Robert citing both files. `transport-test` → answer with a
  `working` record. The ledger is `~/.mo-lead/fable-intake.json`.
- **Integrate.** Audit PRs are merged by the lead after both readings are filed,
  never automatically; the lead never pushes to an `audit/*` branch except its
  own integration notes.
- **Report.** Robert gets one short outcome line per exchange and the unresolved
  decisions; never a relay request.

## The loop, one step at a time

**AFK authority (Robert, 20 Sep 2026, evening ET):** follow current
`HANDOFF.md`. Robert asked the lead to keep working while he sleeps, make
decisions including those previously awaiting his approval, and keep moving. The
lead chooses and records bounded setup, implementation and verification work for
the Mo harness; the earlier implementation pause is superseded for that work.
Confirm technical readiness with evidence, not another permission request.
Continue independent work around prerequisites that inherently need Robert's
presence, such as an interactive login. Retain scope, source ownership,
independent acceptance and audit rules; do not treat unavailable evidence as
passed. Robert explicitly authorizes pushing accepted code and documentation to
`main`. No CI: do not create or restore CI workflows. Push authority is not
blanket permission for deployments, shared infrastructure changes or disclosure
of credentials.

1. **Brief.** One plan page in `mo-wiki/plans/` with Orientation, Write scope,
   Parts, Numbers, Done when. A toolchain step's write scope always includes the
   corpus's `.mo.ids` sidecars and `toolchain/PRELUDE.md` when the corpus or the
   prelude changes (step 35, 17 Sep 2026). A step is one brief; a program has a
   spec page (the lead's) and a brief. Every Done-when asks the worker to tee
   each run its report quotes into a filed log with an exit file beside it (19
   Sep 2026: the claim check's calibration found most unverifiable claims were
   runs with no raw output filed); `tools/claim-check/` may be run on a report
   as a first pass, and never accepts anything.
2. **Fresh worker.** Use `create_thread` with explicit `agent_mode: medium`,
   `executor: orb`, `orb_size: a1.xxlarge` in `robertguss/mo-lang`. Retain the
   at-most-three-worker limit; start two independent lanes when appropriate.
   Name the role, lead thread, exact base, write scope, constraints, checks and
   Done-when. A new orb starts from the remote default branch, not the lead's
   local `main`; transfer unpushed code explicitly with thread file tools. Do
   not assume shared files, local commits, caches, services or credentials.
   Require no nested delegation, named-path commits, filed raw output and real
   exit codes. Record the worker's actual mode and thread URL. Worker pushes and
   PRs require an explicit brief grant; default to returning code locally.
3. **While it works.** Keep this lead thread. Use native thread status/message
   tools for the same assignment. Choose completion by reply or by
   `wait_for_threads`, not both. Idle alone is not completion: establish the
   final report, fixed source, exit status and owned-process cleanup. Preserve
   evidence and threads for review. Queue dependent units rather than launching
   speculative workers. Independent orbs may test concurrently; do not run
   competing measurements on one host.
4. **Integrate and verify.** Robert pushes `main` himself whenever he likes (19
   Sep 2026), so `main` holds accepted work and lead records only: merge a
   worker's branch into a local `lead/verify-<unit>` branch cut from `main` in
   its own verification worktree (never share `zig-out`), run every check there,
   and merge into `main` only when accepted. Consult Oracle on the exact
   candidate and evidence before the acceptance decision. Save the report and
   evidence. Inspect its exact diff before integration; a commit ID or message
   does not transfer code. Download the worker's fixed files or Git bundle to a
   scratch location; inspect the diff and account for deletions, and reconcile
   against the recorded base and intervening lead/upstream changes without
   overwriting unrelated work. Run checks in that integrated verification
   worktree, using shell tools and tracked background commands. For code
   acceptance: `zig build` and `zig build test-corpus --summary all` from
   `toolchain/`, under explicit timeouts/watchdogs, plus probes on inputs the
   brief did not name. Use both runtimes where affected (`mo run`, a `mo build`
   binary, `mo test --sim` for process code); preserve raw outputs and real exit
   codes through pipelines. `zig build test` is a faster preflight, not the full
   acceptance suite: current main skips native integration without
   `test-corpus`. Filtered native checks must use `test-corpus` and prove actual
   execution, not only exit zero. Compare equivalent full coverage in
   before/after timings. For documentation-only work use lint and diff checks.
   Linux builds, tests and benchmarks now run in the orbs with explicit guards
   and cleanup. For durable servers use `amp orb service start` or declared
   services; never Herdr, `nohup`, `caffeinate` or tmux as service supervision.
   Preserve unrelated services. The historical OrbStack executor is not supplied
   by an Amp orb: prove access or establish a separately reviewed disposable
   boundary before running machine/container suites. Never replay host cgroup
   changes blindly. Linux checks do not satisfy Darwin full-sync obligations.
   Record platform coverage separately; do not restore CI to discharge
   outstanding checks.
5. **Record.** One commit (by path: `git commit -m <msg> -- <paths>`):
   decision-log rows in `mo-wiki/decisions/decision-log.md` (who, status, first
   tested by; a ratified worker default names the actual worker/model; rows
   touching failure, authority, equality, persistence, deadlines, or scheduling
   carry the tag `semantic`; overturn on the spot when a default contradicts the
   spec; a row Robert must see says "for Robert"), a `CHANGELOG.md` entry, a
   `mo-wiki/log.md` entry, the plan's status and a Result section, the roadmap's
   board (Now, Next in order, Waiting on Robert, Recently done; Robert reads it
   for status, so it is rewritten at every acceptance and every pause, dated)
   and its phase table and Done rows, the session page, `mo-wiki/index.md` for
   new pages, `mo-wiki/state-of-the-project.md` at every pause (the whole
   picture for Robert, who reads it on the site at
   https://robertguss.github.io/mo-lang/) and the maps under `mo-wiki/maps/`
   when a page lands that belongs on one, an evidence bundle under
   `audit/evidence/<date>/` when the step or round is one the auditor may read
   (its README in the charter's form), and `python3 mo-wiki/tools/lint.py`.
   Record actual lint results, separating inherited notices from new errors.
6. **Publish when authorized.** Inspect branch/index/status, fetch upstream and
   reconcile intervening work without force-pushing or discarding it. Reverify
   affected changes before committing by explicit paths and pushing the agreed
   branch. No hardcoded session branch or automatic merge. Robert also pushes to
   `main`; append-only log/decision conflicts retain both records. A code
   acceptance requires the lead's green checks, not just the worker's report.
7. **Report** to Robert per the framing above, naming anything now ready for an
   audit session (a pre-registration, a run round, a sealed spec), then the next
   brief.

## Rules that were learned the hard way

- A worker's "green" is a claim, not a result (step 36, 17 Sep 2026: two defects
  behind a reported green suite). Every brief's Done-when asks for
  `zig build test-corpus --summary all` under a timeout with the summary line
  and exit code in the report; the lead runs the suite itself before any
  acceptance; a test that can block on a socket has a deadline on every read and
  write.
- A historical Herdr VM memory incident motivates the retained guard, not
  host-wide process mutation. Every brief requires every `mo`, server, bench and
  test process to run under `toolchain/bench/step36/guard.py` (timeout and 4 GB
  direct-child RSS watchdog). Verify process-group cleanup before execution;
  Step42 part E's guard-only recovery is independently accepted on Linux (20 Sep
  evening, worker7939578e). Earlier snapshots lack that protection; supply the
  accepted guard when testing them. Do not describe this RSS check as aggregate
  process-tree enforcement. Do not reset unrelated processes' OOM settings.
  Avoid competing benchmarks on one host; machine capacity does not waive
  bounded execution.
- Nothing is final until measured; every step ends in a numbers table, best of
  five, both runtimes. Before any measurement read `uptime` and
  `ps -eo pid,etimes,pcpu,args --sort=-pcpu | head`, kill what is an orphan (17
  Sep 2026: a 43-hour `python3 -` from a finished session held one of the VM's
  four cores through a whole day of numbers), and write the load average on the
  page beside the numbers.
- Zero new syntax where possible; a grammar change is Robert's call, asked with
  code options.
- The laws stay unless a control run shows them costing loops; five rounds have
  shown none.
- Install what a step needs without asking: Homebrew, `mise`, `uv` (`uv init`
  for a Python project, `uv tool install` for a command), `go install`; record
  it.
- Historical experiment worktrees are evidence and are never deleted or merged.
  `HANDOFF.md` records Mac inventory and restoration limits. Preserve exact
  revisions, patches, environment details and outputs from workers before
  relying on their results; a pane message alone is not durable evidence.
  Rebuild moved dependency environments where necessary.
- A control run (`mo-wiki/plans/control-run-N.md`) is pre-registered:
  predictions and conditions before any experimental session starts, fresh
  isolated threads for each arm, recorded model/provider/budgets and measured
  token/cost data where available (unknown otherwise). Use the approved
  experiment's conditions rather than silently replacing a historical model with
  the worker default. This migration authorizes no round or amendment to sealed
  evidence.

# Mo Lang — Handoff, 17 Sep 2026, afternoon, for the VM: the next session on the Mac or the VM

Paste the block below into a fresh Claude Code session in the repo. The roles,
the Herdr worker loop, and the acceptance checklist live in the `mo-lead` skill
(`.claude/skills/mo-lead/SKILL.md`), which `CLAUDE.md` tells every session to
load; this page holds only the state, the queue, and what a fresh session must
know that the wiki does not say in one place.

> We're continuing the Mo language build. **This session runs on the VM**
> (Robert, 17 Sep, 16:10: step 35 and what follows run on the VM, not his
> laptop; `herdr pane list` shows which machine this is; the worker pane there
> is `w7:p7`, Zig 0.16 through `mise`). The evidence worktrees are on the Mac;
> recreate what a step needs with `git worktree add`, as below. Load the `mo-lead` skill
> first and follow it: you are the lead, Opus workers in Herdr (medium effort,
> one fresh session per piece of work) write all code; Robert reviews the
> decision log. **Robert's standing rule (15 Sep, 23:55, locked): you make the
> decisions and keep the work moving; never stop to ask him; a question is a
> decision-log row, not a wait.** **His rules of 16 Sep, in the skill:** every
> run or spawn (a build, `zig build test`, a suite, a bench, a probe, a worker)
> goes in a fresh Herdr pane of his workspace so he can see it, never a
> background shell of your session; close the pane when its result is read;
> close every workspace you create once its sessions are done; the roadmap
> board is his status view, rewritten at every acceptance and pause; reports to
> him at a high level, the check-by-check detail on the pages. The lead commits
> wiki files with `git commit -m <msg> -- <paths>` only. Then read, in order:
> `mo-wiki/state-of-the-project.md` (the whole picture; rewrite it at every
> pause); `mo-wiki/SCHEMA.md`; the board and the phase table at the top of
> `mo-wiki/plans/roadmap.md`; the last ten entries of `mo-wiki/log.md`; the last
> thirty rows of `mo-wiki/decisions/decision-log.md`; `CHANGELOG.md` down to
> "Session 8"; `mo-wiki/spec/design-v0/01-premise.md`, `08-milestone.md`, and
> `10-language-after-the-rounds.md`; `mo-wiki/plans/erosion-round.md` whole
> (four generations), `interpreter-step-32.md`, `-33.md`, `-34.md`,
> `control-run-9.md`, `control-run-10.md`, `mac-scaling-run.md`.
>
> **State (16 Sep 2026, 23:00 local, at the pause).** Everything is on `main`,
> pushed, and every evidence branch is pushed (`control7-*`, `control8-*`,
> `control10-elixir`, `erosion2-*` to `erosion5-*`, `r9-*`; push `erosion5-*`
> first if `git branch -r` lacks them). The worktrees for those branches exist
> only on the Mac; on the VM recreate what a step needs with `git worktree add
> ../mo-lang-<name> <branch>`, build the toolchain (`cd toolchain && zig build`;
> Zig 0.16 is on the VM through `mise`) and copy `toolchain/zig-out/bin/mo` into
> a Mo worktree's `toolchain/zig-out/bin/`, and put this untracked `mise.toml` at
> the root of an Elixir worktree: `[tools]` / `elixir = "1.18-otp-27"` /
> `erlang = "27"`. Step 34 is done, so the Mac's rows no longer need
> `MO_CORES=1`, though at one core nothing is slower and the rounds keep it.
>
> **17 Sep, morning (Fable, on the Mac).** Research PR 2 (the Hermes lane,
> branch `research/hermes-monitoring`, wiki only) merged into `main`: two daily
> notes under `research/concepts/hermes-daily-2026-09-1{6,7}.md`, the plan
> `plans/hermes-research-monitoring.md`, six raw snapshots. The branch stays
> open for the next scan; review its PR, never merge it unread. Its one
> correction is applied: chapter 10's restart-budget row now says the 3-in-5
> budget is Elixir `Supervisor`'s default, not OTP's (Erlang's `supervisor`
> defaults to 1 in 5 s). Its one gap check was right: `erosion2-*` and
> `erosion5-*` had never been pushed; all eight are on the remote now, so the
> sentence above about evidence branches is true from this morning. The rest
> of the morning was a fresh-eyes pass over the whole wiki (six commits; the
> log's entry of 17 Sep has the list and what was skipped on purpose); the
> plang syntheses under `deep-dives/` are marked contested since they describe
> a hypothetical Mo, which is why lint shows 15 review flags. Its two
> checklists are queued reading for change 6, not steps: the crash-consistency
> sequence (create, compact, rename, reopen, write again) sits on the exact
> path of generation five's Mo defect, and error-path reachability as a recipe
> acceptance question (Yuan et al., OSDI 2014).
>
> **What the evening did, in the order Robert should read it** (each has a
> `semantic` row for him; the morning and afternoon are in the changelog):
>
> 1. **Step 34 accepted** (`interpreter-step-34.md`): placement with the
>    starter; the cross-scheduler ask from 4 to 5.6 s per 100,000 to 0.14 (a
>    zero-timeout `kevent` on every poke and a lost wake, never the lock);
>    measured at 1, 4, and 14 cores: the queue's pairs and `kv-10k-get` under
>    `mo run` level across cores, the crunchers 7×; `echo-1k`, the binary's
>    `kv-10k-get`, and the queue's creates still slower at 14 by the rule for
>    what `main` starts (the follow-up). A regression of part A found and fixed
>    (a spawner that never parked). Carried: a unit test for the step-aside, the
>    crunchers' memory growth (step 33's), the interpreter ledger at 650
>    transfers a second (the compaction copy, now measured).
> 2. **Generation four's Mo queue is nine times slower on the lease path** than
>    every earlier generation (452 pairs a second at 32 workers against 4,040,
>    the same on step 33's and step 34's binaries): the round had counted
>    correctness only. The speed row is measured per generation from five on.
>    The cause in the program is not yet named (the archive scan is gated; no
>    invariant was added; the board's one new `never` and the key map are the
>    suspects): a `sample` under load on a quiet machine is the first thing to
>    do before change 6 is written.
> 3. **Change 5 and generation five** (`01f-job-queue-change-5.md`,
>    `erosion-round.md`): a lease handed to another worker, a queue renamed
>    with jobs in flight as one record, the seam a law; four maintainers in 11
>    to 25 minutes; the sixth suite Python 94, Elixir 94, Go 92, **Mo 93 of 94
>    under both runtimes: after a compaction, one more rename, and a stop, the
>    folder refuses to open** (its own `compact` leaves a count its own `verify`
>    refuses); the three `never`s the Mo maintainer wrote caught neither of its
>    bugs; all four found the spec's archive-rename sentence wrong and fixed it
>    with a position or a count; P6 55 and 99 ms, nothing lost. P1 and P5 held;
>    P2, P3, P4, P6 failed. Speed: Mo 425, Go 107, Python 4,847, Elixir 5,619.
>
> **Rows for Robert** (decision log, "for Robert"), newest first: research PR 2 read and merged, chapter 10's attribution corrected (17 Sep); generation five's reading, the first Mo-only defect, the laws still silent; the change 4 Mo queue nine times slower on the lease path, speed recorded per generation; generation four; chapter 10 §2's budget as a value; generation three, the BEAM's row answered; P6 on Mo's change 2; round 9's Haiku row and its reading; generation two; chapter 10 §1 as built (step 31); chapter 10 itself; P6 on Elixir; measurement 1's completeness row; the BEAM row after round 10; the outage, probed and read; round 8 read; the 16 lint issues from his history bundle.
>
> **17 Sep, afternoon: the auditor.** Robert installed an independent auditor
> (a Perplexity session only he opens) and ratified three stopping rules under
> `audit/`; read `audit/README.md`, `CHARTER.md`, and the three rule files
> before any work on program 7, the stopping rules, or the language's catch
> claim. Fable writes its own reading of each subject as
> `audit/fable-reading-<date>-<subject>.md` before opening the auditor's file
> on it, never opens an audit session, and changes no ratified threshold
> except by a row. M-3 is accepted; the queue below follows it.
>
> **The queue** (the roadmap board is the authority; Fable decides the order):
>
> 1. **Step 35, the crypto brick: accepted 17 Sep, 18:16 UTC** on the VM
>    (`interpreter-step-35.md` has the Result; Fable's hour of fuzzing after
>    it: 3.9 million inputs, 0 crashes). Next in the bricks lane: **the TLS brick**
>    (two steps: a TLS 1.3 server on Zig's `std.crypto.tls` client; the
>    certificate chain and the differential run against OpenSSL), the brief
>    `interpreter-step-36.md` if it exists, else Fable writes it. Both before
>    program 7's first commit (the bricks page,
>    `deep-dives/bricks-and-the-cost-of-zero-dependencies.md`).
> 2. **The probe** naming the cause of generation four's nine-times loss in the
>    Mo queue (`../mo-lang-erosion4-mo`, its binary built with this `mo`; `sample`
>    the server during `bench/step34/jobq_measure.py`'s pairs at 32 workers,
>    `MO_CORES=1`; compare with `../mo-lang-erosion3-mo`'s), and a decision row.
>    It is RC2's evidence: on today's record the speed row is at its line.
> 3. **Program 7**: Fable writes and seals its spec (a Redis subset against
>    Redis's own tests, with TLS, ACL users with SHA-256 passwords, and a
>    Prometheus metrics endpoint as the P4 target); then Robert opens the audit
>    session that seals the hidden suites (tell him when the spec is ready);
>    then the Mo and Elixir builds under matched conditions. Fable does not write
>    or read the hidden suites.
> 4. **Change 6 and generation six**, allowed while program 7 waits on the
>    auditor, never ahead of its build (the detail: `erosion-round.md`, the
>    brief `erosion-round-suite/e5-brief.sh` with the new spec path, the seven
>    suites, P6, the speed row; pre-register before any session starts).
> 5. **Step 34's follow-up**, then **chapter 10's other sections** as steps,
>    then **the compile benchmark**.
>
> **The site.** The wiki is published at https://robertguss.github.io/mo-lang/
> by `.github/workflows/site.yml` (Quartz in `site/`) on every push to `main`.
> `mo-wiki/state-of-the-project.md` is the lead's standing account, rewritten
> at every pause; the maps under `mo-wiki/maps/` are kept current.
>
> **Things learned on the Mac** (kept for the next Mac session). `ls`, `cat`,
> `tr`, and `find -type` are aliased there: python3 for listings and reads in
> scripts. `echo =====` is a zsh equals expansion. macOS keeps 16k ephemeral
> ports to one destination and a closed socket in TIME_WAIT for 30 s: suites
> that open a connection per request run Python's and Elixir's categories one
> at a time with a drain (the suites' `drain()`), never two suites at once.
> The unwritable category uses a RAM disk (`hdiutil attach -nomount
> ram://131072`, `newfs_hfs`, `mount -t hfs`, no sudo). The Mac sleeps with the
> lid and cuts every session short: `caffeinate -dimsu` for any long run. A
> Claude Code worker that shows "done · 1 shell still running" has stopped its
> turn: prompt it to continue. **Learned tonight:** never run a probe beside a
> suite: every suite ends its categories with `pkill -f 'serve /var/folders'`,
> which kills any probe's server too; `measure.py` under `timeout` needs
> `python3 -u` or its buffered output is lost; P6 on Mo needs a binary built
> with `mo build --surface`; a lease hands out the oldest queued job, so a
> suite's setup creates the job it means to lease while nothing else is queued;
> `mo build -o` takes a name under `zig-out/mo-build/<name>/<name>` relative to
> the working directory, not a path; a worker's bench wrapper must own its
> server's process group and check nothing is left (step 34's orphan spun for
> thirty minutes in compaction). Herdr: `herdr workspace create --cwd`,
> `herdr pane split <id> --direction right|down --cwd`, `herdr pane close`,
> `herdr workspace close`. Zsh does not word-split `set -- $x`: write the
> commands out.
>
> **Unmet, carried.** The cause of generation four's speed loss in the Mo
> queue. Placement for what `main` starts; a unit test for the step-aside; the
> crunchers binary's memory growth. Round 9's Opus-in-Pi baseline (no Anthropic
> key in Pi). The restart at 100,000 jobs at 1.45 s and the compaction copy per
> reference (the interpreter ledger at 650 transfers a second). The bench
> baseline gap. Python's change 2 bench regression, unmeasured by the lead. The
> Elixir old-log category (no round 10 escript kept aside). The interpreter's
> 780 KB per process at rest. The lint reports 11 issues: 8 intentional
> review flags on contested pages and 3 pages over 200 lines (the decision log,
> the erosion round, the state page); the linter was taught the spec folder
> and the map, synthesis, and research types on 17 Sep.
>
> **Style.** Ruby-nice syntax, zero new syntax where possible, concise, define
> a PL term in three lines before using it, no phones. Fable drives: proposing
> what to test and measure, deciding, recording. Report at a high level against
> the board; say what was verified and the numbers on the pages; say plainly
> when something is unmet. Verify with probes the brief did not name, on real
> inputs, with your own client.

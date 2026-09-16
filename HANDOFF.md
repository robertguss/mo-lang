# Mo Lang — Handoff, 16 Sep 2026, afternoon: the next session on the Mac (preferred) or the VM

Paste the block below into a fresh Claude Code session in the repo. The roles,
the Herdr worker loop, and the acceptance checklist live in the `mo-lead` skill
(`.claude/skills/mo-lead/SKILL.md`), which `CLAUDE.md` tells every session to
load; this page holds only the state, the queue, and what a fresh session must
know that the wiki does not say in one place.

> We're continuing the Mo language build. Robert prefers the Mac (the evidence
> worktrees and step 34's fourteen-core measurement are there); the VM works for
> everything but step 34 (`herdr pane list` shows which machine this is). Load the `mo-lead` skill
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
> **State (16 Sep 2026, 15:45 local, at the pause).** Everything is on `main`,
> pushed, and every evidence branch is pushed (`control7-*`, `control8-*`,
> `control10-elixir`, `erosion2-*`, `erosion3-*`, `erosion4-*`, `r9-*`). The
> worktrees for those branches exist only on the Mac; on the VM recreate what a
> step needs with `git worktree add ../mo-lang-<name> <branch>` (the names on
> the pages: `../mo-lang-erosion4-mo` on `erosion4-mo`, and so on), build the
> toolchain (`cd toolchain && zig build`; Zig 0.16 is on the VM through `mise`)
> and copy `toolchain/zig-out/bin/mo` into a Mo worktree's `toolchain/zig-out/bin/`,
> and put this untracked `mise.toml` at the root of an Elixir worktree:
> `[tools]` / `elixir = "1.18-otp-27"` / `erlang = "27"` (the VM has Elixir
> through `mise` since round 10). The Mac's port and RAM-disk rules below do not
> apply on Linux; the suites' drains are harmless there.
>
> **What today did, in the order Robert should read it** (each has a `semantic`
> row for him):
>
> 1. **Round 9 closed** with Haiku 4.5 (`control-run-9.md`): 7 to 9 minutes a
>    session, wrong in every language (Mo 28 of 189 over 4 causes, Go 22 over
>    6, Python 18 over 2); at that size the language decides only which checks
>    are missing.
> 2. **P6 on Mo's change 2** (`erosion-round.md`, the P6 section): the queue
>    crashed through the runtime surface under load answers `503` within 2 ms
>    from then, nothing lost, no restart by the program's `:never`; round 8's
>    outage closed by the deferred reply; the restart the program's to take.
> 3. **Step 32** (`interpreter-step-32.md`): crash reports kept apart from the
>    event ring; `restart-reopens.mo` shows a restarted process re-reading its
>    store at start (the pattern chapter 3 now names; kv replays in `main`).
> 4. **Change 3 and generation three** (`01d-job-queue-change-3.md`,
>    `erosion-round.md`): the store that restarts itself, a budget, a chaos
>    switch; four maintainers in 10 to 23 minutes; the fourth suite Mo 55 of 55
>    both runtimes, Go 55, Python 55, Elixir 53; **the Mo queue killed under
>    load back in 106 ms, nothing lost, Elixir 285 to 694: the BEAM's row is
>    answered.** Found: `max_restarts` on a `child` line takes only a literal
>    (chapter 10 §2 asks for a value); the crash report never freed.
> 5. **Step 33** (`interpreter-step-33.md`): the crash report freed in both
>    runtimes (46 MiB a restart to under 0.3); the interpreter's abort on
>    opening a log past 8,000 jobs fixed (a high-water mark); carried: a
>    restart at 100,000 jobs is 1.45 s against the spec's one second; the
>    compaction copy per reference; a bench baseline gap (`kv-50k-set-rss-kib`
>    340 MiB on the Mac against 40 in `results.tsv`).
> 6. **Change 4 and generation four** (`01e-job-queue-change-4.md`,
>    `erosion-round.md`): idempotent creates by a key, old jobs archived out of
>    the log into a second file; the fifth suite Mo 77 of 77 both runtimes,
>    Python 77, Go 76, Elixir 76; the seam held in all four; nothing new eroded
>    in four generations. The Mac slept and cut the sessions short: no honest
>    time column. Mo keeps archived jobs in memory (a row for change 5).
> 7. **Step 34, placement, paused after part A** (`interpreter-step-34.md`):
>    see the plan's status note for exactly what part A did and what parts B
>    (the crossing made cheap) and C (the measurement at 1, 4, and 14 cores)
>    still need. **Parts B and C need the Mac**: the VM has four cores. Resume
>    them the next time a session runs on the Mac; until then the rounds' Mac
>    rows keep `MO_CORES=1`.
>
> **Rows for Robert** (decision log, "for Robert"), newest first: generation
> four; generation three and the BEAM's row answered; chapter 10 §2's budget
> as a value; P6 on Mo's change 2; round 9's Haiku row; the earlier rows of
> the night (P6 and the BEAM after round 10, chapter 10 §1 as built, the
> erosion round's reading, the outage row, measurement 1's completeness, the
> 16 lint issues from his history bundle).
>
> **The queue** (the roadmap board is the authority; Fable decides the order):
>
> 1. **Change 5 and generation five** (either machine): the lead writes and seals
>    `spec/programs/01f-job-queue-change-5.md`, a seam the specs have not
>    found: archived jobs read from the disk rather than kept in memory (the
>    log stops growing and memory does not, Mo's decision of generation four),
>    or a change that cuts across the queue's own invariants (the lease's
>    holder changing hands, a queue renamed with jobs in flight); branch
>    `erosion5-*` from `erosion4-*`; four fresh maintainers in a new workspace,
>    Opus at medium effort, the brief `erosion-round-suite/e4-brief.sh` with the
>    new spec path; the sixth hidden suite after the branching; the five earlier
>    suites as the regressions (`control-run-8-suite/regressions.py` and
>    `defects.py --old-serve <control7>`, `erosion-round-suite/defects2.py`,
>    `defects3.py`, `defects4.py`); P6 (`p6-mo.py` on the Mo `--surface` binary
>    with the `Create` whose `Making` has `key: None` and the queue name
>    `"bad queue"`; `control-run-10-suite/p6.py` on Elixir). Pre-register on
>    `erosion-round.md` before any session starts.
> 2. **Chapter 10's other sections as steps**: §2 the restart budget as a
>    value and its diagnostic, §3 the counted laws to `mo.toml`, §5 MO0317
>    naming the changed module and the `--write` order (the Mo maintainers lost
>    a loop to it in every generation).
> 3. **Step 34 parts B and C** (the Mac): a fresh worker, the same brief, starting from part A's commit and the plan's status note.
> 4. Then the roadmap's order: the bricks page; the compile benchmark;
>    program 7.
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
> turn: prompt it to continue. Herdr: `herdr workspace create --cwd`,
> `herdr pane split <id> --direction right|down --cwd`, `herdr pane close`,
> `herdr workspace close`. Zsh does not word-split `set -- $x`: write the
> commands out.
>
> **Unmet, carried.** Step 34 parts B and C (the Mac). Round 9's Opus-in-Pi
> baseline (no Anthropic key in Pi). The restart at 100,000 jobs at 1.45 s.
> The compaction copy per reference. The bench baseline gap. Python's
> change 2 bench regression, unmeasured by the lead. The Elixir old-log
> category (no round 10 escript kept aside). The interpreter's 780 KB per
> process at rest. The lint reports about 90 issues: 16 Robert's, the research
> pages' type, and size warnings on the pages that grew today.
>
> **Style.** Ruby-nice syntax, zero new syntax where possible, concise, define
> a PL term in three lines before using it, no phones. Fable drives: proposing
> what to test and measure, deciding, recording. Report at a high level against
> the board; say what was verified and the numbers on the pages; say plainly
> when something is unmet. Verify with probes the brief did not name, on real
> inputs, with your own client.

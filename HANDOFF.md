# Mo Lang — Handoff, 18 Sep 2026, 8:50 AM ET, moving from the VM to Robert's Mac

Paste the block below into a fresh Claude Code session in the repo on the Mac.
The roles, the Herdr worker loop, the acceptance checklist, and the audit
exchange live in the `mo-lead` skill (`.claude/skills/mo-lead/SKILL.md`),
which `CLAUDE.md` tells every session to load; this page holds only the state,
the queue, and what a fresh session must know that the wiki does not say in
one place.

> We're continuing the Mo language build. **This session runs on Robert's
> Mac** (M3 Max, 14 cores, 96 GB; `herdr pane list` shows which machine this
> is; the worker pane is split to the **right** of the lead's, never below).
> Load the `mo-lead` skill first and follow it: you are the lead, Opus workers
> in Herdr (medium effort, one fresh session per piece of work) write all
> code; Robert reviews the decision log. **His standing rules:** you make the
> decisions and keep the work moving, never stop to ask him (a question is a
> decision-log row); every run or spawn goes in a fresh Herdr pane of his
> workspace, closed when its result is read; the roadmap board is his status
> view, rewritten at every acceptance and pause; **every time you give him is
> US Eastern**; reports at a high level, the detail on the pages. The lead
> commits wiki files with `git commit -m <msg> -- <paths>` only. **First, the
> out-of-memory rule (new, 18 Sep):** every process under Herdr inherits
> `oom_score_adj -1000` and cannot be killed when memory runs out; on Linux
> reset every process of the user but the `herdr` server to 0 at the session's
> start (on macOS there is no such knob: rely on the guard), and every brief
> tells the worker to run every `mo`, server, bench, and test process under
> `toolchain/bench/step36/guard.py` (a timeout and a 4 GB watchdog). Then,
> **before any other work, the auditor's inbox:** `git fetch origin && python3
> audit/automation/fable_poll.py check` (pointers only; the skill's Receive
> bullet says what to do with each line; never open an auditor reading before
> the lead's own is on `main`). Then read, in order:
> `mo-wiki/state-of-the-project.md`; `mo-wiki/SCHEMA.md`; the board and the
> phase table at the top of `mo-wiki/plans/roadmap.md`; the last ten entries
> of `mo-wiki/log.md`; the last fifty rows of
> `mo-wiki/decisions/decision-log.md` (the night of 17 to 18 Sep is all
> there); `CHANGELOG.md` down to "Session 10"; `audit/README.md`,
> `audit/WORKFLOW.md`; `mo-wiki/plans/interpreter-step-37.md` whole (the
> Result and the Fix); `mo-wiki/spec/programs/07-redis-subset.md` (sealed);
> `mo-wiki/plans/gen4-memory-control-probe.md` (the Result);
> `mo-wiki/spec/programs/01g-job-queue-change-6.md` and the generation-six
> section of `mo-wiki/plans/erosion-round.md`; `mo-wiki/plans/interpreter-step-38.md`.
>
> **State (18 Sep 2026, 8:50 AM ET).** Everything is on `main` and pushed
> (`2faf9b3` and after). The night on the VM, in the order Robert should read
> it (every item has a row for him):
>
> 1. **The auditor's step-36 reading received and answered** (10:16 PM ET):
>    Fable's own reading filed first, both PRs merged, `parallel-filed`
>    published; four points conceded, all closed in step 37. The auditor's two
>    retrospective comparisons (PR #6) merged; the one disagreement,
>    `AUD-COMP-GEN4-RSS-001`, answered with a row and then settled by the
>    control probe (item 4).
> 2. **Step 37, the TLS brick part two, accepted** (3:50 AM ET, `15fb2cb`):
>    the client, the chain to a trusted root, ALPN, KeyUpdate either way;
>    1,000 sessions against OpenSSL at 0 mismatches, a fuzz hour at 0 crashes,
>    the RFC 8448 client replay byte for byte; Fable's probes found two runtime
>    defects behind the worker's green (a peer's alert read as the stream's
>    end; a double free that crashed the binary server after a client's reset),
>    fixed in `b0b2ac4` with tests, 236 of 236 on Fable's own run. The cut
>    refuses RSA and P-384 chains, so the public internet is out of reach by
>    design. The `ready` record `step-37-ready-001` is published; expect the
>    auditor's `reading-filed`; write `audit/fable-reading-2026-09-18-step-37.md`
>    before opening it.
> 3. **Program 7's spec sealed** (`07-redis-subset.md`, `972c872`) and
>    published as `program-7-spec-ready-001`: the auditor writes the hidden
>    suites and names the P4 modification; the builds wait on that record.
> 4. **The generation-four memory control probe** (4:33 AM ET): forty runs;
>    none of the three hypotheses; the 46 MiB was one draw from a bimodal
>    state of generation four's code, independent of the contract; the rate
>    loss is the contract's walk; both readings retire; the allocator's
>    resident set is the open question. `gen4-speed-probe-working-002` sent.
> 5. **Change 6 sealed and generation six started** (4:44 AM ET) on the VM:
>    the archive pruned, a speed budget, the rename rule corrected, the
>    persistence sequence; the seventh suite `defects6.py` sealed by hash
>    (`48640d3`). **Interrupted:** at 5:21 AM ET a `mo` process in the Mo
>    maintainer's session reached 13.4 GB and, unkillable, wedged the VM until
>    Robert restarted it at 8:30 AM ET. The Python maintainer had finished
>    (5:43 AM ET, budget met at 1.01× and 1.03×, 361 tests). Mo, Go, and
>    Elixir were resumed briefly and then **stopped at 8:45 AM ET** with their
>    work committed as `jobq: change 6 (work in progress, the VM session
>    stopped)` and a `REPORT-change-6-wip.md` each, pushed on `erosion6-{mo,go,elixir}`;
>    `erosion6-python` is pushed complete.
> 6. **Step 38's brief queued** (`interpreter-step-38.md`): a full-duplex
>    `Conn`, `TCP_NODELAY`, the handshake abuse rows; before program 7's build.
>
> **The queue** (the roadmap board is the authority; Fable decides the order):
>
> 1. **Finish generation six on the Mac.** Worktrees
>    `../mo-lang-erosion6-{mo,go,python,elixir}` from the pushed branches; the
>    Mo one needs step 37's `mo` built there (`zig build` in its `toolchain/`
>    is the old tree: build `main`'s toolchain and copy `zig-out/bin/mo` in, the
>    runtime is embedded). Three fresh sessions continue from the WIP commits
>    with the brief `erosion-round-suite/e6-brief.sh` amended: "your
>    predecessor's work in progress and its `REPORT-change-6-wip.md` are in
>    the worktree; continue from them" (disclosed on the round's page: not a
>    fresh maintainer, a resumed one, and the wall-clock is the sum). The Mo
>    maintainer must say what the 13 GB `mo` process was. Then the suites one
>    language at a time with `e6-suites.sh` (its paths are the VM's
>    `/home/exedev/Projects`: change `R=` to the Mac's root and the control7 and
>    control10 worktrees, which exist on the Mac; `pkill -f 'serve /var/folders'`
>    and `netstat` for the Mac), the speed row with `measure.py`, the result
>    section against P1 to P7, rows, the bundle
>    `audit/evidence/2026-09-18/generation-six/`, a `ready` record.
> 2. **Step 38** (its brief is written), then program 7's build once the
>    auditor's suites are ready (a `ready`/`working` record from the auditor).
> 3. **A runtime memory probe:** what took a `mo` process to 13 GB on the
>    change-6 jobq (the Mo maintainer's report first), and the allocator's
>    resident set behind generation four's bimodal state.
> 4. The closure-capture step, step 34's follow-up, chapter 10's other
>    sections, the compile benchmark, a byte-string value, the brick cache
>    shared by source hash.
>
> **The auditor's inbox at this pause:** three records of Fable's await
> answers: `step-37-ready-001`, `program-7-spec-ready-001`,
> `gen4-speed-probe-working-002`. Nothing from the auditor unread.
>
> **Things learned on the VM tonight.** A worker's "green" is a claim: step 37
> had two runtime defects behind 234 of 234 (found by probes with a second
> OpenSSL and a raw-socket client). A worker whose turn ends while a shell
> still runs must be prompted to continue. Two `mo build`s in one directory
> collide on the brick cache. A brick change recompiles the brick once per
> corpus program (28-minute suites). A load near 3 on a one-server run is the
> run itself (D-state threads). GNU `timeout` puts its child in a new process
> group: `timeout --foreground` in harnesses. Herdr's children are
> `oom_score_adj -1000`. The intake rejects `RESULTS.md` and readings as
> record paths: raw files only.
>
> **Things learned on the Mac** (kept). `ls`, `cat`, `tr`, and `find -type`
> are aliased: python3 for listings and reads in scripts. `echo =====` is a zsh
> equals expansion (also on the VM: `$B:path` is a zsh modifier, quote
> `"${B}:path"`). macOS keeps 16k ephemeral ports to one destination and
> TIME_WAIT for 30 s: suites one at a time with their drains. The unwritable
> category uses a RAM disk. `caffeinate -dimsu` for any long run. `measure.py`
> under `timeout` needs `python3 -u`. P6 on Mo needs `mo build --surface`. A
> lease hands out the oldest queued job. `mo build -o` takes a name under
> `zig-out/mo-build/<name>/<name>` relative to the working directory. Herdr:
> `herdr workspace create --cwd`, `herdr pane split <id> --direction right
> --cwd`, `herdr pane close`, `herdr workspace close`; `herdr agent start
> <name> --kind claude --pane <id> --timeout 60000 -- --model opus
> --dangerously-skip-permissions`, `/effort medium`, then the brief.
>
> **Style.** Ruby-nice syntax, zero new syntax where possible, concise, define
> a PL term in three lines before using it, no phones. Fable drives. Report at
> a high level against the board; say what was verified and the numbers on the
> pages; say plainly when something is unmet. Verify with probes the brief did
> not name, on real inputs, with your own client.

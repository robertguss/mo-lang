# Mo Lang — Handoff, the morning of 16 Sep 2026, on Robert's Mac

Paste the block below into a fresh Claude Code session in the repo. The roles,
the Herdr worker loop, and the acceptance checklist live in the `mo-lead` skill
(`.claude/skills/mo-lead/SKILL.md`), which `CLAUDE.md` tells every session to
load; this page holds only the state, the queue, and what a fresh session must
know that the wiki does not say in one place.

> We're continuing the Mo language build on Robert's Mac. Load the `mo-lead`
> skill first and follow it: you are the lead, Opus workers in Herdr (medium
> effort, one fresh session per piece of work) write all code; Robert reviews
> the decision log. **Robert's standing rule (15 Sep, 23:55, locked; restated 15
> Sep 22:50 going to bed): you make the decisions and keep the work moving;
> never stop to ask him; a question is a decision-log row, not a wait.** The
> lead commits wiki files with `git commit -m <msg> -- <paths>` only (a bare
> `git commit` swept a worker's staged files twice this night). Then read, in
> order: `mo-wiki/SCHEMA.md`; the "Where we are" table at the top of
> `mo-wiki/plans/roadmap.md`; the last ten entries of `mo-wiki/log.md`; the last
> thirty rows of `mo-wiki/decisions/decision-log.md` (rows tagged `semantic` are
> the ones Robert reads, rows marked "for Robert" wait on him); `CHANGELOG.md`
> down to "Session 7, night"; `mo-wiki/spec/design-v0/01-premise.md`,
> `08-milestone.md`, and `10-language-after-the-rounds.md`;
> `mo-wiki/plans/control-run-9.md`, `erosion-round.md`,
> `interpreter-step-31.md`, `control-run-10.md`, `bodies-as-cache.md`, and
> `mac-scaling-run.md` whole.
>
> **State (16 Sep 2026, about 02:00 local; the Mac session ran from 22:20 on 15
> Sep).** Everything is on `main`, pushed. The Mac is set up (Zig 0.16.0, Go
> 1.27.1, Elixir 1.18 on OTP 27 pinned in the Elixir worktrees, `uv`, Pi 0.73.1,
> Ollama; 28 evidence worktrees plus tonight's: `../mo-lang-r9-<model>-<lang>`
> for kimi, deepseek, codex, qwen, gemini (unused),
> `../mo-lang-erosion2-<lang>`, `../mo-lang-cache-C`). The Herdr worker pane is
> `w44:p2`; workspaces `w45` to `w4A` hold tonight's session panes, all finished.
>
> **What the night found, in the order Robert should read it.**
>
> 1. **P6 on Elixir** (`control-run-10.md`): the queue process killed from
>    outside three times under 11,000 requests a second, `/health` back in 261
>    to 583 ms, nothing acknowledged lost. **The BEAM's row.** Four kills inside
>    2 s cross OTP's default intensity and the node exits. After round 10 the
>    null hypothesis reads: Mo has reliability and the loop; the BEAM has speed,
>    time to write, the dependency tie, and P6.
> 2. **The Mac scaling run** (`mac-scaling-run.md`, the table in step 30's
>    Result): nothing scales on the M3 Max; every row fastest at 1 core; the
>    disk eight times the VM's; `MO_CORES=1` for Mac rows until placement is
>    fixed (a step after 31).
> 3. **Chapter 10, the language after the rounds**
>    (`spec/design-v0/10-language-after-the-rounds.md`, for Robert): six
>    sections, two changes, zero syntax. §1, the deferred reply, was built the
>    same night as **step 31** (`interpreter-step-31.md`, accepted 01:15):
>    `Reply(T)`, `reply_to`, `answer`, MO0411, all three runtimes, the corpus
>    file; Fable's crash probe 8 of 8 `Down` then 8 answered.
> 4. **Measurement 1 complete**: the agent program at 1.0 twice (34 and 30 min),
>    twelve of twelve; the stronger form on logstat (tests deleted too): 1.0
>    under the transcripts, 0.74 under the original tests, the eight failures
>    being rules the tests carried that the spec never stated
>    (`bodies-as-cache.md`).
> 5. **Round 9, the small-model round** (`control-run-9.md`): kimi-k3 (Go 0/1 in
>    15 min, Python 0/0 in 35, Mo 0 regressions and 1 defect cause at 97 min,
>    not green at the 90-minute rule), deepseek-v4-flash (Go 0/1 in 11, Python
>    0/0 in 14, Mo 0/2 in 17), gpt-5.5 through Codex (Go 0/1 in 6, Python 0/0 in
>    7, Mo 0/0 in 14: it matched Opus). Every Go change carries the same
>    `delay_ms` null defect; both open-weights models' Mo changes miss the
>    run-out lease with backoff; the closed model does not. Gemini's key in Pi
>    is invalid; xAI has no key; the local qwen 27B made no edit in any language in 92 minutes (P5's floor is below Go and Python too).
> 6. **The erosion round, generation two** (`erosion-round.md`, for Robert):
>    change 2 by four Opus maintainers in 12 to 18 minutes. Under round 8's
>    suites nothing eroded in Mo, Go, or Python; Elixir refuses a torn line at
>    open now and cannot restart after a full disk. Under the third suite (66
>    checks, a 64 MB RAM disk filled under load): Mo 65, Go 66, Python 65,
>    Elixir 62. Generation one already answered through the full disk in Mo, Go,
>    and Python; Elixir's generation-one node exited on `:enospc` in a second.
>    The Mo maintainer used `Reply(T)` for the queue's answer the first time it
>    was offered. Held P1, P4, P5, P6; failed P2 (Go cleaner by one) and P3 (Go
>    and Python as contained as Mo).
>
> **Rows for Robert** (decision log, "for Robert"): P6 and the BEAM after round
> 10; chapter 10 §1 as built (step 31); the erosion round's reading; the outage
> row (program or runtime) from round 8; measurement 1's completeness row; the
> 16 lint issues from his history bundle.
>
> **The queue** (the roadmap table is the authority; Fable decides the order):
>
> 1. **Round 9's last row.** Haiku 4.5 through Claude Code (`--model haiku`) is M5, unrun: `r9-setup.sh haiku`, three panes in a new workspace, the Claude kind with `/effort medium`, `r9-brief.sh`, the suites per language from `control-run-9-suite/` (the Python one paced: `paced-python.sh`). The round is otherwise read (`control-run-9.md`, status done): qwen made no edit in 92 minutes in any language.
> 2. **P6 on Mo's change 2 program** (`../mo-lang-erosion2-mo`, the binary at
>    `examples/programs/jobq/zig-out/mo-build/jobq-e2/jobq-e2`): the queue
>    crashed under load with the service still answering. The binary's queue
>    cannot be killed from outside; find the input that trips a contract inside
>    the queue under load (a record that passes `verify` but breaks a `never` at
>    lease, or a fault under `--sim` in `server.mo`'s tests), or add a runtime
>    hook. This is the row that closes round 8's outage or does not.
> 3. **Generation three of the erosion round**: change 3 written and sealed by
>    the lead (`spec/programs/01d-...`), branched from `erosion2-*`, a fourth
>    hidden suite after the branching; the change 2 spec first gains the three
>    sentences decided at 02:00 (a record with a field its state forbids is
>    ill-formed; `verify` never writes; `verify` on a missing folder exits 1).
> 4. **The placement step** (after 31): a process placed with its asker or a
>    reply answered on the asker's scheduler; measured on `echo-1k` and the
>    queue at 1 and 14 cores on the Mac; the interpreter's parked fiber at 128
>    held asks (step 31's 0.46 row).
> 5. **Chapter 10's other sections as steps**: §2 the restart budget diagnostic,
>    §3 the counted laws to `mo.toml`, §5 MO0317 naming the changed module and
>    the `--write` order.
> 6. Then the roadmap's order: the bricks page; the compile benchmark;
>    program 7.
>
> **Things learned this night on the Mac.** `ls`, `cat`, `tr`, and `find -type`
> are aliased to other tools here: use python3 for listings and file reads in
> scripts. `echo =====` is a zsh equals expansion; use `---`. The Ollama app
> must be running for Pi's ollama provider (`open -a Ollama`); cloud models pull
> on first use. Pi has no `/exit`: close the pane. macOS keeps 16k ephemeral
> ports to one destination and a closed client socket in TIME_WAIT for 30 s: a
> suite that opens a connection per request (round 8's) runs out against a
> service that closes connections (Python's), so run its categories one at a
> time with a 35 s pause (`paced-python.sh`), and never run two suites at once.
> The unwritable-folder category uses a RAM disk
> (`hdiutil attach -nomount ram://131072`, `newfs_hfs`, `mount -t hfs`, no sudo)
> filled to `ENOSPC`, because `chmod` and `chflags uchg` do not stop writes
> through a file already open. A Claude Code worker that shows "done · 1 shell
> still running" has stopped its turn: prompt it to continue. The change spec is
> not in the round 7 or 8 branches: give it by absolute path. Herdr workspaces
> are created with `herdr workspace create --cwd` and split with
> `herdr pane split <id> --direction right|down --cwd`.
>
> **Unmet, carried.** P6 on Mo's change 2. Round 9's qwen and Haiku rows, and
> its Opus-in-Pi baseline (no Anthropic key in Pi). Python's first unwritable
> run on generation one died in the audit and passed on the rerun (a flake until
> it recurs). Python's change 2 maintainer reported its own bench regression
> (4,438 to 1,279 pairs a second, partly taken back), unmeasured by the lead.
> The Elixir old-log category (no round 10 escript kept aside). The
> interpreter's 780 KB per process at rest. `python3 mo-wiki/tools/lint.py`
> reports about 28 issues, 16 Robert's.
>
> **Style.** Ruby-nice syntax, zero new syntax where possible, concise, define a
> PL term in three lines before using it, no phones. Fable drives: proposing
> what to test and measure, deciding, recording. Report against the roadmap
> table, say what was verified and the numbers, and say plainly when something
> is unmet. Verify with probes the brief did not name, on real inputs, with your
> own client: every finding of this session that mattered came from an input no
> suite sent.

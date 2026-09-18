# Mo Lang — Handoff, 17 Sep 2026, 10:20 PM ET, at the pause on the VM

Paste the block below into a fresh Claude Code session in the repo. The roles,
the Herdr worker loop, the acceptance checklist, and the audit exchange live in
the `mo-lead` skill (`.claude/skills/mo-lead/SKILL.md`), which `CLAUDE.md`
tells every session to load; this page holds only the state, the queue, and
what a fresh session must know that the wiki does not say in one place.

> We're continuing the Mo language build. **This session runs on the VM**
> (Robert, 17 Sep: steps run here, not on his laptop; `herdr pane list` shows
> which machine this is; Zig 0.16 through `mise`; the worker pane is split to
> the **right** of the lead's, never below, Robert's rule of 17 Sep). Load the
> `mo-lead` skill first and follow it: you are the lead, Opus workers in Herdr
> (medium effort, one fresh session per piece of work) write all code; Robert
> reviews the decision log. **His standing rules:** you make the decisions and
> keep the work moving, never stop to ask him (a question is a decision-log
> row); every run or spawn goes in a fresh Herdr pane of his workspace, closed
> when its result is read; the roadmap board is his status view, rewritten at
> every acceptance and pause; **every time you give him is US Eastern**
> (`TZ=America/New_York date`); reports at a high level, the detail on the
> pages. The lead commits wiki files with `git commit -m <msg> -- <paths>`
> only, and when a worker holds the shared tree, from a detached worktree of
> `origin/main` (`git worktree add --detach ../mo-lang-lead-main origin/main`,
> commit there, `git push origin HEAD:main`, remove it). Then, **before any
> other work, the auditor's inbox:** `git fetch origin && python3
> audit/automation/fable_poll.py check` (pointers only; the skill's Receive
> bullet says what to do with each line; never open an auditor reading before
> the lead's own is on `main`). Then read, in order:
> `mo-wiki/state-of-the-project.md` (the whole picture; rewrite it at every
> pause); `mo-wiki/SCHEMA.md`; the board and the phase table at the top of
> `mo-wiki/plans/roadmap.md`; the last ten entries of `mo-wiki/log.md`; the
> last forty rows of `mo-wiki/decisions/decision-log.md`; `CHANGELOG.md` down
> to "Session 9"; `audit/README.md`, `audit/WORKFLOW.md`,
> `mo-wiki/plans/the-audit-workflow.md`;
> `mo-wiki/deep-dives/bricks-and-the-cost-of-zero-dependencies.md`;
> `mo-wiki/plans/interpreter-step-35.md` and `-36.md` whole (both Results,
> the two fixes); `mo-wiki/spec/design-v0/01-premise.md` and
> `10-language-after-the-rounds.md`; `mo-wiki/plans/erosion-round.md` (the
> speed row and the note naming generation four's cause).
>
> **State (17 Sep 2026, 10:20 PM ET, at the pause).** Everything is on `main`
> at `8e2fe01` and pushed; no worker is running; no pane but the lead's is
> open; no `mo`, `openssl`, or `zig` process is left; the Zig cache was
> cleared (the next `zig build test` is cold, about 15 minutes; warm it is 11
> on this VM's four cores). The evidence worktrees are on the Mac, plus
> `../mo-lang-erosion3-mo` and `-erosion4-mo` here (the speed probe's,
> rebuilt with step 35's `mo`); recreate others with `git worktree add`.
>
> **What today did, in the order Robert should read it** (every item has a row
> for him in the decision log; the changelog has the detail):
>
> 1. **Step 35, the crypto brick, accepted** (6:16 PM UTC, 2:16 PM ET): SHA-2,
>    HMAC, HKDF, AES-GCM, ChaCha20-Poly1305, X25519, Ed25519, Argon2id, and
>    `Random` as a capability, one Zig file for both runtimes; 0 mismatches
>    against python's `cryptography`, 0 crashes in 4.5 million fuzz inputs;
>    `List(UInt8)` at 2.9× and 6.3× the raw call, carried.
> 2. **Generation four's nine times, named:** change 4's `sweep` gained a
>    postcondition that walks every finished job and `decide` runs it on every
>    request; contracts off restores generation three's rate; the closure's
>    capture of `board` costs a structural walk per element in the binary
>    (`mo_disown_in`, 23 percent), a runtime row for a later step.
> 3. **The auditor, automated** (Robert's PR #3): handoff records under
>    `audit/handoffs/`, the auditor's hourly intake, Fable's receiver
>    (`audit/automation/fable_poll.py`), Fable's two parallel readings filed
>    against `69860b0` before the auditor's were opened, the bricks page's
>    note on shipped numbers. Robert relays the auditor's notices himself; no
>    cron on the lead's side; the inbox is checked at every session's start.
> 4. **Step 36, the TLS brick part one, accepted** (10:15 PM ET) after two
>    fixes the lead's verification forced: a hanging brick test and a wrong
>    certificate path, both behind the worker's reported green. 225 of 225;
>    1,026 and 1,196 handshakes a second; a `Conn` that stays a `Conn`.
> 5. **Robert's reading before program 7:** parity with the BEAM at zero
>    dependencies from a compiled runtime is an achievement.
> 6. **The machine:** a 43-hour orphan held one core through the day's numbers
>    (the condition is on the evidence README; read `uptime` before any
>    measurement, now in the skill); disk from 79 to 45 percent.
>
> **The queue** (the roadmap board is the authority; Fable decides the order):
>
> 1. **Step 37, the TLS brick, part two** (Fable writes the brief first: the
>    client side `Tls.connect`, the certificate chain, ALPN, a KeyUpdate
>    delivered, the differential run against OpenSSL, the fuzz of the
>    handshake parser; the carried rows of step 36 in view: the copy per byte
>    in the record path, both bricks linked into every binary, the two
>    swallowed timeouts, the missing-close_notify reading for program 7).
>    Then its worker, then the evidence bundle and a `ready` record.
> 2. **Program 7:** Fable writes and seals its spec (a Redis subset against
>    Redis's own tests, with TLS, ACL users with Argon2id passwords, a
>    Prometheus metrics endpoint as the P4 target; the request path's
>    contracts named as what the speed row reads; the truncation reading
>    decided), publishes it as a `ready` record; the auditor writes the hidden
>    suites; then the Mo and Elixir builds under matched conditions.
> 3. **Change 6 and generation six**, allowed while program 7 waits on the
>    auditor, never ahead of its build.
> 4. **The closure-capture step** (disown a closure's captures once, with a
>    micro-benchmark first), **step 34's follow-up**, **chapter 10's other
>    sections**, **the compile benchmark**, **a byte-string value** for
>    `List(UInt8)`.
>
> **The auditor's inbox at this pause:** step 35 and the speed probe have both
> sides' readings (`audit/mo-audit-2026-09-17-*.md`, `audit/fable-reading-*`);
> Robert reads the pairs and files disagreements. Step 36's `ready` record is
> `audit/handoffs/step-36/step-36-ready-001.json` at `cb61ac6`; expect a
> `reading-filed` or `evidence-needed` PR from the auditor. The transport
> test's inbound leg (a `to: fable` canary) is still unverified.
>
> **The site.** The wiki is published at https://robertguss.github.io/mo-lang/
> by `.github/workflows/site.yml` (Quartz in `site/`) on every push to `main`.
>
> **Things learned on the VM today.** `perf` for this kernel is at
> `/usr/lib/linux-tools-6.8.0-139/perf` (the wrapper refuses); `curl` in the
> lead's shell is redirected by a hook, use python's `urllib`; `pgrep -f` and
> `pkill -f` match the lead's own command line when the pattern is in it
> (exit 144 kills the lead's shell): use `pgrep -x` by name; `$c:t` in zsh is
> a path modifier, quote `"${c}:path"`; a `zig build test` of the corpus
> takes 11 minutes warm and hangs silently if a brick test blocks (`gdb -p`
> on the test binary names the test); the lead's cleanup must never `git
> worktree remove` before its push is confirmed. A worker's "green" is a
> claim: the lead's own suite run is the gate.
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
> **Unmet, carried.** Step 36's carried rows (above). Placement for what
> `main` starts; a unit test for the step-aside; the crunchers binary's memory
> growth. Round 9's Opus-in-Pi baseline. The restart at 100,000 jobs at 1.45 s
> and the compaction copy per reference. The bench baseline gap. Python's
> change 2 bench regression. The Elixir old-log category. The interpreter's
> 780 KB per process at rest. The transport test's inbound leg. Lint: 20
> findings, 15 review flags on contested pages and 5 pages over 200 lines.
>
> **Style.** Ruby-nice syntax, zero new syntax where possible, concise, define
> a PL term in three lines before using it, no phones. Fable drives: proposing
> what to test and measure, deciding, recording. Report at a high level against
> the board; say what was verified and the numbers on the pages; say plainly
> when something is unmet. Verify with probes the brief did not name, on real
> inputs, with your own client.

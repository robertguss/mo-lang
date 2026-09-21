# Mo Lang

A programming language for the AI era, designed and built by Robert Guss and
Claude. Start every session by loading the `mo-lead` skill
(`.claude/skills/mo-lead/SKILL.md`; read it directly if it is not registered):
it holds the roles, the Amp orb worker loop, and the acceptance checklist. Then
read `HANDOFF.md` for the current state and queue, then `mo-wiki/SCHEMA.md` for
the working agreements. Then, before any work, check what the auditor has posted
since the last session:
`git fetch origin && python3 audit/automation/fable_poll.py check` (pointers
only; follow the lead skill's Receive rules for each line, and never open an
auditor reading before the lead's own is on `main`). This onboarding sequence is
for the lead. Worker threads read the role and safety rules, then follow their
bounded brief; they do not check or operate the lead's audit inbox,
publish/integrate audit records, or take over lead decisions.

- This persistent Amp thread is the lead (Robert, 20 Sep 2026, evening ET).
  Oracle consultation is mandatory for planning, substantive review and
  acceptance decisions; it does not switch the thread's underlying model. The
  lead owns briefs, reviews, decisions and records, and runs independent
  acceptance builds/tests. It does not write implementation code.
- Workers use fresh Amp threads with `agent_mode: medium`, `executor: orb`,
  `orb_size: a1.xxlarge`. Every assignment, including saved WIP, starts fresh;
  no resumed, forked or imported conversations. Follow `mo-lead` for launch,
  explicit code transfer and acceptance. At most three workers, each with its
  own orb checkout. Workers own implementation, including test/probe scripts. No
  Herdr/OMP launches and no nested delegation.
- Stage and commit only named paths (`git add <paths>` and
  `git commit -m <message> -- <paths>`), never `git add -A`. Inspect existing
  staged changes; do not sweep in someone else's work.
- Robert's 20 Sep AFK instruction authorizes the lead to choose and drive setup,
  implementation and verification while he is AFK, including decisions
  previously awaiting approval. The earlier harness implementation pause is
  superseded. Record bounded decisions and verify readiness; continue
  independent work around prerequisites that require Robert's presence. The lead
  may push accepted code and documentation to `main` without asking again. No
  CI: do not create or restore CI workflows. Linux verification now runs in
  orbs; it never substitutes for Darwin-specific durability evidence.
- Robert's decisions and the lead's are rows in
  `mo-wiki/decisions/decision-log.md`; he reviews the log, not the queue.
- Never use `tr` in shell commands (aliased on this machine); use python3.
- Install any tool a step needs without asking: Homebrew, `mise`, `uv`
  (`uv init` for Python projects), `go install`.
- An independent auditor (a Perplexity session only Robert opens) reads raw
  evidence and files `audit/mo-audit-<date>-<subject>.md`; its charter and three
  ratified stopping rules are under `audit/`. Read `audit/README.md` before
  touching program 7, the stopping rules, or the language's catch claim. The
  lead never opens an audit session, never reads or writes a hidden suite the
  auditor seals, writes its own reading as
  `audit/fable-reading-<date>-<subject>.md` before opening the auditor's, files
  disagreements as decision-log rows, leaves raw pointers and outputs for the
  auditor under `audit/evidence/<date>/`, and exchanges handoffs with it through
  immutable JSON records under `audit/handoffs/` polled hourly on both sides
  (`audit/WORKFLOW.md`; the lead publishes with
  `audit/automation/fable_poll.py publish` and, when Robert says the auditor has
  posted, runs `fable_poll.py check`, which shows pointers only). Robert passes
  on the auditor's notifications himself; the lead runs no poller. The wiki page
  `mo-wiki/plans/the-audit-workflow.md` has the whole loop.

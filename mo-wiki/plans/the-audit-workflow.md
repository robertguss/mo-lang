---
title: "The audit workflow: who reads what, and when"
created: 2026-09-17
updated: 2026-09-17
type: plan
tags: [process]
sources: [SCHEMA.md, plans/roadmap.md, decisions/decision-log.md]
status: living
---

# The audit workflow: who reads what, and when

Robert installed an independent auditor on 17 Sep 2026, after an outside
review named the weakness in how the project checked itself: one agent wrote
the predictions, ran the rounds, and read the results. The charter, the three
ratified stopping rules, the auditor's readings, Fable's parallel readings, and
the evidence bundles live under [`audit/`](https://github.com/robertguss/mo-lang/blob/main/audit/README.md)
at the repo root, outside the vault, so the site does not publish them and the
repo cannot lose them. This page is the vault's account of the loop, for a
session picking the project up; the charter is the authority.

## The roles

- **The auditor** is a fresh Perplexity session in the Mo Lang project that
  only Robert opens, titled `audit: <subject>`. It reads raw evidence cold
  (pre-registration pages, branch names, suite files at the post-branching
  commit, numbers as printed) and files `audit/mo-audit-<date>-<subject>.md`.
  It designs nothing, executes nothing, accepts nothing; Fable cannot overrule
  it; only Robert amends or rejects a reading, by a decision-log row with a
  reason. It is model-generated and shares a training distribution with Fable:
  a second opinion, not final truth.
- **Fable, the lead,** writes its own reading of every subject (a decision-log
  row, or `audit/fable-reading-<date>-<subject>.md`) before it opens the
  auditor's file on the same subject, files each disagreement as a row citing
  both, never opens an audit session, never pastes its synthesis into one, and
  never reads or writes a hidden suite the auditor seals.
- **Robert** opens the sessions, pastes only raw pointers, reads both readings,
  and decides. He reviews the decision log, not the queue.

## The three ratified rules (17 Sep 2026)

| rule | claim | tested by | file |
|---|---|---|---|
| runtime | chapter 1's primary claim: the runtime and process model against the BEAM null hypothesis (rows R1 to R7, cost bounds RC1 to RC4, retirement S-A, S-B, S-C) | program 7 | `audit/mo-audit-2026-09-17-stopping-rule-runtime.md` |
| capabilities | the secondary claim: capabilities and recipes at zero third-party runtime dependencies (P1 to P4, retirement T-A, T-B, T-C) | program 7 | `audit/mo-audit-2026-09-17-stopping-rule-capabilities.md` |
| never and invariant | the residual claim: the language's checks catch a class of bug tests miss | the erosion round at generation ten | `audit/mo-audit-2026-09-17-stopping-rule-never-invariant.md` |

A threshold or a retirement mapping in these changes only by a decision-log
row with a reason. Fable's disagreements with them are rows of 17 Sep, marked
for Robert ([[decision-log]]).

## The loop, automated (Robert's amendment of 17 Sep, evening; PR #3)

Robert seated a new auditor (a Hermes profile, `mo-auditor`, with its own checkout and sessions) and approved a two-way exchange through the repository, so he relays nothing routine. The protocol is `audit/WORKFLOW.md`; the auditor's intake is `audit/automation/README.md`; Fable's receiver is `audit/automation/FABLE-RECEIVER.md`. In one paragraph: Fable commits raw evidence, then publishes an immutable JSON record on `main` at `audit/handoffs/<subject>/<id>.json` (`kind: ready`, the exact evidence commit, raw paths, a bounded request with no verdict). The auditor's hourly poll of `main` starts one fresh, isolated audit session per `ready` (`working` records status only; `evidence-updated` answers an evidence request; `parallel-filed` asks for a comparison of two committed readings). The auditor files its reading or an `evidence-needed` record on an `audit/*` branch with a pull request; Robert tells Fable it exists (his choice, 6:20 PM ET: no poller on Fable's side), and Fable's receiver script announces it with pointers only. Fable files its own reading before opening the auditor's, then publishes `parallel-filed`; the comparison files disagreements. Audit output reaches `main` by pull request that the lead integrates; nothing merges automatically. Robert gets short outcome summaries and unresolved decisions. Independence rules unchanged: no conclusions cross before both readings are filed; a contaminated session never writes a reading called cold; hidden suites and seeds never appear in a handoff.

## The loop, as it ran on 17 Sep before the amendment (manual, superseded for routine starts)

1. **Before a round or a program.** The pre-registration is on its page and
   pushed before any session starts (predictions, the suites' shape, the
   change that will be made). Fable's report says the subject is ready for
   `audit: pre-registration <name>`. For program 7 the auditor also writes
   the hidden suites (at least 50 defects, the wait probe, the abuse suite,
   the drift seeds, the P4 change) after Fable seals the spec; Fable never
   sees them.
2. **After a round, an acceptance, or a probe.** Fable's reading is a
   decision-log row, pushed. The raw pointers and outputs go under
   `audit/evidence/<date>/` with a README in the charter's form: paths,
   branches, commits, numbers as the machines printed them, the scripts that
   produced them, and Fable's own probe scripts and outputs (the worker owns
   `toolchain/`, so the lead's probes live here), with Fable's readings named
   and marked "open after your own". The report to Robert says the subject is
   ready for `audit: <name>`.
3. **Robert opens the session** and pastes only the pointers, never Fable's
   rows. The session files `audit/mo-audit-<date>-<subject>.md`.
4. **When the auditor's file lands,** Fable writes its own reading first if it
   is not already a row, then reads the auditor's, then files each
   disagreement as a row citing both files, for Robert. Robert amends the rule
   or lets the disagreement stand as a row.
5. **Standing duties of the auditor:** read pre-registrations before rounds,
   hidden suites before they run against Mo, rounds after they run; every five
   rounds a whole-project audit of which rules were set and which drifted; one
   candidate falsifier per round.

## What counts as a role violation

Fable amending a pre-registration once evidence is in view; an audit session
given Fable's reading before its own (it refuses the turn); three un-audited
rounds in a row (the next session opens with a whole-project audit).

## Where it is going

Automated by repository handoffs since 17 Sep, evening: the auditor's intake polls `main` hourly; on Fable's side Robert passes on the auditor's notifications and Fable runs its receiver script by hand. A signed webhook may later call the same intake, with polling kept for recovery. The end state the charter names is
a paid human reviewer weekly, with the session as the fallback between reviews.

## Related

- [[SCHEMA]] (agreement 12), the `mo-lead` skill in the repo, `audit/README.md`, `audit/CHARTER.md`
- [[state-of-the-project]], [[roadmap]] (the board's "Waiting on Robert"), [[for-robert]], [[how-we-work]]
- [[bricks-and-the-cost-of-zero-dependencies]] (the prerequisite the auditor named), [[erosion-round]], [[01-premise]]

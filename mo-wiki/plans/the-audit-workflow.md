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

## The loop, as it runs today

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

Manual and Robert-driven now. After two or three audit rounds, a GitHub
Actions webhook opening an audit session on every merge to `main` that touches
`mo-wiki/decisions/` or an evidence branch. The end state the charter names is
a paid human reviewer weekly, with the session as the fallback between reviews.

## Related

- [[SCHEMA]] (agreement 12), the `mo-lead` skill in the repo, `audit/README.md`, `audit/CHARTER.md`
- [[state-of-the-project]], [[roadmap]] (the board's "Waiting on Robert"), [[for-robert]], [[how-we-work]]
- [[bricks-and-the-cost-of-zero-dependencies]] (the prerequisite the auditor named), [[erosion-round]], [[01-premise]]

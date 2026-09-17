# Auditor charter for the Mo Lang project

**Accepted by Robert Guss, 17 September 2026.**
**Auditor:** a fresh, isolated, model-agnostic audit session authorized by Robert, including standing authorization through the automated handoff below.
**Not the auditor:** Fable (the project lead), workers, or any other agent that designs, executes, or accepts work in the project.

## Purpose

To restore the separation between designer, executor, and evaluator that pre-registration and hidden suites depend on for credibility. Fable is the lead and executor; the auditor reads independently. When their readings disagree, that disagreement becomes a decision-log row.

## Rules

1. **The auditor does not design, execute, or accept work.** It reads evidence, files readings, and dissents.
2. **The auditor cannot be overruled by Fable.** Only Robert can amend or reject an auditor reading, and any amendment is a decision-log row with a stated reason.
3. **The auditor reads raw evidence, not Fable's synthesis.** If an audit session is given Fable's reading before it has produced its own, the session refuses the turn and asks Robert to reopen with raw evidence only.
4. **The auditor writes its reading before seeing Fable's.** For any given round or pre-registration, the auditor's file is dated and filed before Fable's reading is read in the same audit session.
5. **Every audit reading lives in this repo.** Files are `audit/mo-audit-<YYYY-MM-DD>-<subject>.md`. Readings persist alongside the wiki so the project cannot lose them.
6. **A limit on the auditor's authority.** The auditor is model-generated and shares a training distribution with Fable. Its readings are second opinion, not final truth. The best long-term version of this role is a paid human reviewer, weekly.

## Ratified amendment: automated two-way handoff (17 September 2026)

Robert approved replacing routine Robert-driven session starts with automated, repository-based exchange between Fable and the independent auditor. Reason: remove Robert as the message relay while preserving cold readings and independent evaluation.

- Fable publishes a ready-for-audit subject with an exact evidence commit and raw evidence pointers. This is standing authorization to start a fresh, isolated audit session automatically; ordinary pushes and work-in-progress notices are not audit authorization.
- The auditor files a cold reading on a separate audit branch and submits it through a PR. Missing-evidence questions and responses travel through the repository; evidence updates may trigger another auditor pass without Robert relaying them.
- Neither side reads the other's conclusions before filing its own independent reading. Handoff messages before that point contain status and raw pointers, not verdicts. After both readings are filed, the auditor compares them and records disagreements with equal standing.
- Only Robert can amend or reject auditor readings or change ratified rules. Unresolved substantive disagreements, authorization changes, and blockers the two roles cannot resolve are escalated to him. Routine notifications are short outcome summaries, not requests for permission.
- Auditor and Fable use separate checkouts and sessions. Auditor output remains under `audit/` in this repository and reaches `main` through PR integration, not direct auditor pushes. This amendment does not grant automatic merge authority.
- Contamination still requires refusing the affected cold reading. Automation must start a clean session with raw pointers; it must not relabel an exposed session as independent. If clean recovery is unavailable, escalate to Robert.
- Three consecutive unaudited rounds still trigger the charter's whole-project audit escalation, whether caused by a missed trigger or a manual omission.

See `audit/WORKFLOW.md` for the proposed operational protocol and activation status. This amendment supersedes conflicting manual-start, direct-push, and model-specific instructions in older audit guidance. It changes no stopping-rule threshold. Approval does not mean the webhook infrastructure is deployed.

## Historical workflow (Option B — manual, superseded for routine starts)

**When a round finishes:**

1. Fable files their reading into `mo-wiki/decisions/decision-log.md` and pushes to `main`.
2. Robert opens a fresh Perplexity session in this project, titled `audit: <round-name>`.
3. Robert pastes into that session only:
   - path to the pre-registration page (e.g. `mo-wiki/plans/erosion-round.md`),
   - the branch names carrying the evidence (e.g. `erosion6-mo`, `erosion6-go`, etc.),
   - suite file paths at the post-branching commit,
   - raw defect/perf numbers as recorded, not as prose synthesis,
   - and **explicitly not** the decision-log rows Fable wrote for this round.
4. The audit session reads the repo cold, produces `audit/mo-audit-<date>-<round>.md`, submits it.
5. Robert reads the auditor's file alongside Fable's decision-log row and files any disagreements as decision-log rows with equal standing.

**When a pre-registration is being written** (before a round runs):

Same shape. Session title `audit: pre-registration <round-name>`. Auditor flags missing predictions, prediction/suite mismatches, or predictions that would confirm regardless of outcome. Files `audit/mo-audit-<date>-<subject>-preregistration.md`.

## Standing responsibilities

- Read pre-registrations before rounds run.
- Read hidden suites before they run against Mo.
- Read rounds after they run, cold, from evidence only.
- Every N rounds (default 5) do a whole-project audit: which stopping rules were set, which have been quietly relaxed, which claims are drifting.
- File one candidate falsifier per round: a specific experiment that would retire a Mo claim if it went a certain way.

## Escalation path if the workflow drifts

- If the auditor sees Fable's reading before its own: refuse the turn.
- If Robert is not invoking the auditor for rounds: after the third un-audited round in a row, the next audit session opens with a whole-project audit and flags the gap.
- If Fable is amending pre-registrations after evidence is in view: file it as a role violation.

## Migration path to something stronger

- **Now:** manual, Robert-driven (this document).
- **Once the workflow proves useful (2–3 audit rounds):** move to a GitHub Actions webhook that opens an audit session automatically on every merge to `main` touching `mo-wiki/decisions/` or an evidence branch. Removes the "Robert forgot" failure mode.
- **Ideal end state:** a paid human reviewer weekly, plus the auditor session as a fallback between reviews.

## First deliverables filed under this charter

- `audit/mo-audit-2026-09-17-stopping-rule-never-invariant.md` — the stopping rule for the language-layer claim, drafted before generation 6 runs.

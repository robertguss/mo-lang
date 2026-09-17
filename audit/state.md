# The auditor's state

Living state of the audit function: what has been ratified, what is queued, what standing concerns are open. Updated by the auditor at every reading; `audit/AUDITOR.md` describes the loop.

**Current commit anchor:** `67823dd` (this file, on top of Fable's parallel readings at `9b48c6b` and the bricks-page compounding rows at `afebaa5`, 17 Sep 2026 afternoon).

---

## Ratified rules (17 Sep 2026)

All three ratified in-session by Robert before program 7 exists and before generation 6 runs. Amendments require a decision-log row with a reason.

| Rule | File | Test | Retirement mapping |
|---|---|---|---|
| Runtime and process model vs. BEAM | `mo-audit-2026-09-17-stopping-rule-runtime.md` | Program 7 | S-A / S-B / S-C |
| Capabilities and recipes, zero deps | `mo-audit-2026-09-17-stopping-rule-capabilities.md` | Program 7 | T-A / T-B / T-C |
| `never` / `invariant` catch class | `mo-audit-2026-09-17-stopping-rule-never-invariant.md` | Erosion round at generation ten | Single-tier, R-B automatic on failure |

Ratification clarifications (from Fable's first parallel reading, 17 Sep): R6 has no token budget; RC3 amber ≤ 2× steady / ≤ 3× peak, red otherwise; R4/R7 failures narrow chapter 1's claim rather than trigger S-tier; P3 Elixir-half is expected asymmetric and binding half is Mo's absolute count; single-tier L-2 with R-B automatic on failure.

## Readings filed to date

| Date | Subject | Auditor file | Fable's parallel |
|---|---|---|---|
| 17 Sep 2026 | Runtime stopping rule | `mo-audit-2026-09-17-stopping-rule-runtime.md` | (see rule file, in-line) |
| 17 Sep 2026 | Capabilities stopping rule | `mo-audit-2026-09-17-stopping-rule-capabilities.md` | (see rule file, in-line) |
| 17 Sep 2026 | `never`/`invariant` stopping rule | `mo-audit-2026-09-17-stopping-rule-never-invariant.md` | (see rule file, in-line) |
| 17 Sep 2026 | Step 35 crypto brick | `mo-audit-2026-09-17-step-35-crypto-brick.md` | `fable-reading-2026-09-17-step-35-crypto-brick.md` |
| 17 Sep 2026 | Gen-4 speed-loss probe | `mo-audit-2026-09-17-gen4-speed-probe.md` | `fable-reading-2026-09-17-gen4-speed-probe.md` |

The successor auditor compared both pairs at `9c753e176ad70b383211eae255307bd5654d5280`; see `mo-audit-2026-09-17-auditor-handoff.md`. **Pending disagreement row:** the gen-4 auditor reading treats the lower contracts-on RSS as a memory benefit; Fable disputes that interpretation and proposes contract-triggered compaction, explicitly without having run the confirming control probe. No corresponding decision-log row was found. Neither interpretation was independently tested in the handoff. Both Fable readings also disclose receiving relayed auditor summaries before writing; retain that independence caveat. No substantive crypto-verdict disagreement identified.

**Filing instruction for this handoff:** Robert directed a separate auditor branch because Fable works on `main`. The handoff and this update are filed on `audit/2026-09-17-auditor-handoff`; integration into `main` is pending. No stopping-rule amendment.

## Standing concerns open

Raised in a reading, not yet resolved. Each has a pointer back to the reading that raised it. These do not require Fable to act; they are what the auditor will look for in the next relevant reading.

1. **`List.all?` on capability-carrying `List` in hot per-message paths** (from the gen-4 speed-probe reading). Repeatable 2-3× contracts-on throughput cliff via `mo_disown_in` under `mo_r_List_all_q`. Worth naming in the language guide before program 7 lands. (Cause named on the bricks page at `afebaa5`; still open as a language-guide item.)
2. **The "Reading" step for each brick should not default to the auditor** (from the step-35 reading). Design-vs-evaluation firewall collapses at the brick level if it does. Recommendation: a fresh session per brick reading. If crypto and TLS bricks ship before the bricks page's item 5 ("read the bricks") is done by anyone, the program-7 reading will note P1 clears technically but the shelf-audit budget the bricks page implicitly promises has not been paid.

## Standing concerns closed on 17 Sep 2026 by Fable's afternoon push

1. **`List(UInt8)` overhead in the bricks page's P4 crypto footnote** — closed by the bricks-page rows at `afebaa5`.
2. **Contracts-on cost compounding on `List(UInt8)` payloads** — closed by the bricks-page rows at `afebaa5`.
3. **Speed-probe evidence bundles should carry the source diff** — closed by the sweep diff, decide diff, emitted-lambda dump, and `mo_disown_in` source added to the gen-4 evidence bundle at `9b48c6b`. Fable's parallel reading walks the diff.

Future speed-probe bundles should continue the pattern the gen-4 bundle now sets.

## Pre-registration work queued

The auditor writes these when the bricks page lands and program 7's spec is ready. Fable never sees them.

- Runtime hidden defect suite (≥ 50 defects: 15 crash-consistency + 10 restart + 10 deadline/mailbox + 10 capability + 5 replay).
- The wait-probe of 10 shapes for R3.
- The 10-shape capability-abuse suite for P3.
- The 3 drift-bug seeds for P2a.
- The 5 regeneration-drift seeds for P2c.
- The named change-6-style modification for P4.

## Roadmap M-3, as the auditor named it and Fable accepted

1. The bricks page (**done**, at `9dce71b`).
2. The gen-4 speed-loss probe (**done**, filed at `854a815`; reading at `a507b54`).
3. TLS brick, step 36 (Fable's worker in progress at time of the step-35 reading; brief at `mo-wiki/plans/interpreter-step-36.md`).
4. Program 7's spec, sealed by Fable, then the auditor's pre-registration session that seals the hidden suites.
5. Program 7's Mo and Elixir builds under matched conditions.

## Automated handoff approval

Robert approved automated two-way repository handoffs on 17 Sep 2026: Fable's ready subject triggers an isolated auditor session; the auditor returns readings or evidence requests via audit branches/PRs; Fable's evidence responses trigger follow-up. Only unresolved decisions and blockers require Robert. See the amendment in `CHARTER.md` and `WORKFLOW.md`. **Deployment status: auditor-side GitHub polling active every two minutes in the isolated profile; real fresh-agent canary passed. Fable-side wake-up and two-way delivery remain unconfigured/unverified. No webhook endpoint deployed.** See `automation/README.md` for jobs, tests, and limitations. Stopping rules unchanged.

## Model handoffs

The auditor role is model-agnostic. When Robert moves the seat to a different model (e.g., from Perplexity to Codex, or to a human), the receiving session reads `AUDITOR.md`, this file, and the charter, and continues the loop unchanged. Standing conventions Robert established with the previous seat carry across; they are recorded in `AUDITOR.md`.

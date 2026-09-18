# The auditor's state

## Current-state review — 18 September 2026 (PR integration pending)

- `mo-audit-2026-09-18-current-state.md`: Robert-requested retrospective review anchored at `0f827a9018b1640d87ee503334f3517c8996b6d4`, with the program-7 baseline delta through `1fa19e3bd3870593ea152847e7ac9970efc3d724` checked separately. Not a cold subject reading.
- Current checks reproduce TLS certificate-authorization omissions, ALPN truncation, and labelled mocked harness false-success paths. Build and 26 native TLS tests pass; the bounded full test run remains incomplete. Program-7 measurement/coverage gates remain outstanding. See the report for exact scope, severity and evidence.
- Submitted for PR integration from `audit/2026-09-18-current-state` at Robert's request. No rule amendment, implementation edits, merge, or automatic intake. Prior concerns are not implicitly closed.

## Generation six reading filed — 18 September 2026

- Independent reading: [`mo-audit-2026-09-18-generation-six.md`](mo-audit-2026-09-18-generation-six.md), evidence `d846a4b35e7630a91ca5f608e8d46c43eef21ef6`, cold reading commit `4fbfff64466be9ee0a7dc808f8afc4ce970389db`. P1–P7 are assessed separately; raw assertion totals are not defect-cause counts. Standing concerns: format-aware fixtures and end-to-end failure propagation; full old-folder sequence and directory-sync fault-window coverage; conflicting archive-only `/queues` wording and Python's retained rename count; quiet, matched speed conditions; complete wrong-edit/catch records.
- Auditor-owned generation-six language ledger: zero unique-only catches established, zero new false positives evidenced, 14 `never` plus 2 `invariant` declarations over 8,630 physical shipped Mo lines (1.8540/1,000; denominator sensitivity in the reading). Complete test-only cause total not established. The ratified generation-ten rule is unchanged and has not fired early.
- Filed on `audit/generation-six-generation-six-ready-001` for PR integration, not merged by the auditor. No Fable comparison performed; Fable must file its independent reading of this subject before opening this one. Notification remains manual; automatic intake was not resumed. Only this subject's state is updated here; older historical transport-status paragraphs below are not a new authorization to poll.

## TLS independent code reading filed — 18 September 2026

- Reading: [`mo-audit-2026-09-18-tls-independent-code.md`](mo-audit-2026-09-18-tls-independent-code.md), code anchor `64982b23b1dfed0bd0af3430125589da43058ac0`. Open concerns: certificate restrictions/critical extensions, failed-batch fuzz accounting, and the limits of fixture-based interoperability claims. The step-36 immediate-recovery scheduling repair is independently verified; this does not close all prior shelf concerns. Findings and reproducible checks are in the reading. No stopping rule amended. Integration pending; Fable must independently file before opening the reading. Notification is manual, not evidence of an active receiver.

## Step 36 reading filed — 18 September 2026

- Independent reading: [`mo-audit-2026-09-18-step-36.md`](mo-audit-2026-09-18-step-36.md), against evidence `cb61ac625d4b2e2a07b338105fa32780cdf66272`. Standing concerns: preserve the server-half/full-shelf distinction; explicitly resolve Done-when coverage and measurement mismatches; supply synthesis-free command/output evidence instead of mixed pane transcripts. The reading contains the observations, limits and falsifier. No stopping rule, prior concern or ratification is amended.


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

The successor auditor compared both pairs at `9c753e176ad70b383211eae255307bd5654d5280`; see `mo-audit-2026-09-17-auditor-handoff.md`. **Retrospective comparisons filed 18 Sep 2026**, based on `aace4ee36516c9dc67cdb7b0d0c8cab3a5f9c024`, reading anchor `8f03d80c0856c681094bf64fe654b76c6015fa7d`: see `comparisons/2026-09-18-step-35-crypto-brick.md` and `comparisons/2026-09-18-gen4-speed-probe.md`. The previously missing gen-4 RSS disagreement is now recorded as `AUD-COMP-GEN4-RSS-001` in `mo-wiki/decisions/decision-log.md` on the comparison audit branch, pending PR integration. The auditor treats lower contracts-on RSS as a memory benefit; Fable disputes that interpretation and proposes contract-triggered compaction, explicitly without the confirming control probe. The interpretation remains unresolved for Robert; neither explanation was experimentally tested here. The supplied source snippets were inspected, not a new performance run. Both Fable readings disclose relayed-summary exposure before writing; retain that independence caveat. No substantive crypto-verdict disagreement or duplicate crypto row. Existing standing concerns and stopping rules are unchanged.

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

Robert approved automated two-way repository handoffs on 17 Sep 2026: Fable's ready subject triggers an isolated auditor session; the auditor returns readings or evidence requests via audit branches/PRs; Fable's evidence responses trigger follow-up. Only unresolved decisions and blockers require Robert. See the amendment in `CHARTER.md` and `WORKFLOW.md`. **Deployment status: auditor-side GitHub polling active once per hour in the isolated profile; real fresh-agent canary passed. Fable-side wake-up and two-way delivery remain unconfigured/unverified. No webhook endpoint deployed.** See `automation/README.md` for jobs, tests, and limitations. Stopping rules unchanged.

## Model handoffs

The auditor role is model-agnostic. When Robert moves the seat to a different model (e.g., from Perplexity to Codex, or to a human), the receiving session reads `AUDITOR.md`, this file, and the charter, and continues the loop unchanged. Standing conventions Robert established with the previous seat carry across; they are recorded in `AUDITOR.md`.

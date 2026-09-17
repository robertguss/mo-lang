# The auditor's state

Living state of the audit function: what has been ratified, what is queued, what standing concerns are open. Updated by the auditor at every reading; `audit/AUDITOR.md` describes the loop.

**Current commit anchor:** `a507b54` (the step-35 crypto brick reading + gen-4 speed probe reading, pushed 17 Sep 2026 afternoon).

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

| Date | Subject | File |
|---|---|---|
| 17 Sep 2026 | Runtime stopping rule | `mo-audit-2026-09-17-stopping-rule-runtime.md` |
| 17 Sep 2026 | Capabilities stopping rule | `mo-audit-2026-09-17-stopping-rule-capabilities.md` |
| 17 Sep 2026 | `never`/`invariant` stopping rule | `mo-audit-2026-09-17-stopping-rule-never-invariant.md` |
| 17 Sep 2026 | Step 35 crypto brick | `mo-audit-2026-09-17-step-35-crypto-brick.md` |
| 17 Sep 2026 | Gen-4 speed-loss probe | `mo-audit-2026-09-17-gen4-speed-probe.md` |

## Standing concerns open

Raised in a reading, not yet resolved. Each has a pointer back to the reading that raised it. These do not require Fable to act; they are what the auditor will look for in the next relevant reading.

1. **`List(UInt8)` overhead in the bricks page's P4 crypto footnote** (from the step-35 reading). Ratio is 6.3× under `mo run` and 2.9× under the binary on 1 MiB SHA-256 relative to raw Zig. Bricks page should name this before program 7 measures against it. Will be re-checked when the byte-string value lands or when the bricks page is next revised.
2. **`List.all?` on capability-carrying `List` in hot per-message paths** (from the gen-4 speed-probe reading). Repeatable 2-3× contracts-on throughput cliff via `mo_disown_in` under `mo_r_List_all_q`. Worth naming in the language guide before program 7 lands.
3. **Contracts-on cost compounding on `List(UInt8)` payloads** (from the gen-4 speed-probe reading). Program 7's contracts-on numbers on `List(UInt8)` payloads will be materially worse than the raw-brick numbers on the bricks page. Bricks page P4 story should be honest about this before program 7's build.
4. **The "Reading" step for each brick should not default to the auditor** (from the step-35 reading). Design-vs-evaluation firewall collapses at the brick level if it does. Recommendation: a fresh session per brick reading. If crypto and TLS bricks ship before the bricks page's item 5 ("read the bricks") is done by anyone, the program-7 reading will note P1 clears technically but the shelf-audit budget the bricks page implicitly promises has not been paid.
5. **Speed-probe evidence bundles should carry the source diff** (from the gen-4 speed-probe reading). The erosion-3 / erosion-4 board.mo diff was not in the bundle; the reading rested on the perf profile plus Fable's word for the code change. Future speed probes about a code change should include the diff snippet at the sites the report calls out.

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

## Model handoffs

The auditor role is model-agnostic. When Robert moves the seat to a different model (e.g., from Perplexity to Codex, or to a human), the receiving session reads `AUDITOR.md`, this file, and the charter, and continues the loop unchanged. Standing conventions Robert established with the previous seat carry across; they are recorded in `AUDITOR.md`.

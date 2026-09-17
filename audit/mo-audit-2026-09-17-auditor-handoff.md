# Audit handoff: prior-reading comparison

**Date:** 2026-09-17
**Author:** Mo Auditor (a Hermes-hosted model session, independent of Fable)
**Charter:** `audit/CHARTER.md`; the auditor reads evidence, files readings, and dissents. Only Robert can amend or reject a reading.
**Scope:** compare the already-filed step-35 crypto and gen-4 speed-probe readings for unlogged disagreements; record the receiving auditor's handoff. This is not a new audit of either implementation or a stopping-rule evaluation.
**Status:** handoff comparison against `9c753e176ad70b383211eae255307bd5654d5280`. The prior auditor's readings were read before Fable's parallel readings. This session did not produce those prior cold readings.
**Explicit gap in this reading:** no raw probe outputs, implementation sources, or performance experiments were independently rechecked for this comparison. Neither the RSS causal explanation nor the competing memory-benefit interpretation is adjudicated here.

## What was read

In Robert's requested order: `audit/README.md`, `audit/CHARTER.md`, `audit/AUDITOR.md`, `audit/state.md`, all three ratified stopping rules, the two prior auditor readings below, then Fable's parallel readings. The decision log was subsequently searched for corresponding disagreement rows.

- `audit/mo-audit-2026-09-17-step-35-crypto-brick.md`
- `audit/mo-audit-2026-09-17-gen4-speed-probe.md`
- `audit/fable-reading-2026-09-17-step-35-crypto-brick.md`
- `audit/fable-reading-2026-09-17-gen4-speed-probe.md`
- `mo-wiki/decisions/decision-log.md`: relevant search results and full rows at lines 498–501.

Line references below refer to the anchored commit, not to future edits.

## Finding: an RSS interpretation disagreement remains unlogged

The prior auditor calls gen-4's contracts-on RSS after pairs, **46 MiB against gen-3's 173 MiB**, a large memory reduction and describes a CPU-for-memory trade (`mo-audit-2026-09-17-gen4-speed-probe.md:55–60`).

Fable explicitly rejects counting this as a design win. Its reading points to contracts-off RSS of **169 MiB for gen 4 and 168 MiB for gen 3**, proposes contract-triggered region compaction as the explanation, and calls for a cheap-contract control probe before counting a benefit. Fable explicitly says that probe has not run (`fable-reading-2026-09-17-gen4-speed-probe.md:61–76`).

**Verified here:** the readings disagree about what the reported RSS reduction establishes. The decision log records the speed finding, the runtime's closure-capture cost, and the bricks-page cost note at lines 498–501, but the search found no row recording this RSS disagreement and citing both readings.

**Not verified here:** that region compaction explains the RSS reduction, or that the reduction establishes a general memory benefit. Those remain competing interpretations requiring evidence.

**Recommendation to Robert:** have the disagreement recorded as a decision-log row citing both readings; until it is resolved, retain the reported measurements but do not count the RSS reduction as an established design benefit. The proposed control probe remains unrun according to Fable's filed reading; this session did not run or authorize it.

## Independence caveat disclosed by Fable

Both parallel readings disclose exposure to Robert's relayed summaries before their writing:

- Crypto front matter, `fable-reading-2026-09-17-step-35-crypto-brick.md:6`: the fit-to-ship verdict and the `List(UInt8)` ratio note were relayed, although the auditor's file had not been opened.
- Speed-probe front matter, `fable-reading-2026-09-17-gen4-speed-probe.md:6`: the verdict and several findings were relayed, although the auditor's file had not been opened.

This is a documented limitation on the independence of those parallel readings, not evidence that their technical conclusions are wrong. It is also not exposure of this receiving auditor to Fable's synthesis before producing a new audit: this task is explicitly retrospective comparison of already-filed readings. No new cold technical reading is claimed.

For future parallel readings, relay raw evidence pointers rather than either side's verdict until both readings have been filed.

## Other comparison results

No substantive disagreement was identified in the crypto shipping verdict: both readings call the brick fit to ship, name the byte-list overhead, and decline to treat the brick alone as clearing a stopping-rule row. This comparison does not endorse every technical assertion in either reading.

The gen-4 runtime-cost explanation is recorded in decision-log line 500. That row does not itself settle the distinct RSS disagreement.

## Inherited state and filing arrangement

The two existing open concerns in `audit/state.md` remain open and unmodified in substance: the hot-path `List.all?` concern and the separation between brick reading and the auditor role. Their underlying technical claims were inherited, not reverified here.

Robert seated this session as the successor auditor and requested repository filing. He then directed use of a separate branch because Fable works on `main`. This handoff is therefore filed on `audit/2026-09-17-auditor-handoff`, in a separate checkout, without pushing changes to `main`. This records the current filing instruction, not a stopping-rule amendment or an assertion that the operating manual has been rewritten. Integration into `main` remains pending.

No thresholds amended, no code changed, no probes run, and no new subject begun. The auditor returns to IDLE pending Robert's next subject and raw evidence pointers.

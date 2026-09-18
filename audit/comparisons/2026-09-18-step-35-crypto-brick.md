# Retrospective comparison: step-35-crypto-brick

**Date:** 2026-09-18
**Author:** Mo Auditor (Hermes-hosted comparison session)
**Status:** comparison of already-filed readings; not a new cold audit or acceptance.
**Repository base:** `aace4ee36516c9dc67cdb7b0d0c8cab3a5f9c024`.
**Reading/evidence anchor:** `8f03d80c0856c681094bf64fe654b76c6015fa7d`, from `audit/handoffs/step-35-crypto-brick/step-35-crypto-brick-parallel-filed-001.json`.

Robert authorized this retrospective comparison after the step-36 cold reading was filed. The auditor reading was read first, then Fable's parallel. Both files are byte-identical between the handoff anchor and repository base. All reading line citations below refer to the handoff anchor. This session did not run crypto tests or independently revalidate implementation claims.

## Conclusions

No substantive shipping-verdict disagreement: the auditor calls the brick fit to ship ([auditor, lines 47–53](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/mo-audit-2026-09-17-step-35-crypto-brick.md#L47-L53)); Fable agrees ([Fable, lines 43–46](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/fable-reading-2026-09-17-step-35-crypto-brick.md#L43-L46)). Both reserve program-7/stopping-rule conclusions for their actual test ([auditor, lines 51–53](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/mo-audit-2026-09-17-step-35-crypto-brick.md#L51-L53); [Fable, lines 104–112](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/fable-reading-2026-09-17-step-35-crypto-brick.md#L104-L112)). These are the filed positions, not a new auditor acceptance of engineering work.

## Causes and costs

Both identify byte-list representation overhead rather than a crypto-brick correctness defect: the auditor names 6.3× interpreted and 2.9× compiled overhead and asks for a cost footnote ([lines 43–45](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/mo-audit-2026-09-17-step-35-crypto-brick.md#L43-L45)); Fable gives the per-byte value/copy explanation and the same ratios ([lines 55–67](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/fable-reading-2026-09-17-step-35-crypto-brick.md#L55-L67)). Fable supplies more mechanism, not a competing verdict. Decision-log rows 492 and 501 at the repository base already record the overhead and compounding-cost note; no duplicate row is warranted.

## Limitations and independence

The auditor records its checker reruns and scope ([lines 37–41](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/mo-audit-2026-09-17-step-35-crypto-brick.md#L37-L41)); Fable additionally names untested macOS/cross-compilation, constant-time measurement, CPU portability and the shared implementation boundary ([lines 69–89](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/fable-reading-2026-09-17-step-35-crypto-brick.md#L69-L89)). Those limits remain visible even though the shipping conclusions agree. This comparison does not endorse every technical assertion in either file or convert fuzz crash coverage into differential coverage.

Fable's front matter ([line 6](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/fable-reading-2026-09-17-step-35-crypto-brick.md#L6)) discloses reading Robert's relayed verdict and byte-list note before writing, despite not opening the auditor file. Agreement therefore is not fully independent corroboration. The prior auditor's filed cold status is preserved; this comparison is explicitly retrospective.

## Implications and disposition

Keep the byte-list cost visible in shipped-program comparisons; do not award stopping-rule passes from this brick. The auditor's separate brick-reading/firewall concern ([lines 55–59](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/mo-audit-2026-09-17-step-35-crypto-brick.md#L55-L59)) remains open; Fable's claim that brick audit activities are affordable is not evidence that the future shelf-reading obligation has been completed.

Decision-log duplicate check: searched the entire log narrowly for step 35, generation-four/gen-4, RSS, compaction and memory-benefit terms; read complete subject rows 487–493 and 498–501 at the base. No new crypto disagreement row is warranted. No rule or prior reading is amended. Return record: `audit/handoffs/step-35-crypto-brick/step-35-crypto-brick-compared-001.json`. Publication is an audit PR, not proof of Fable receipt or a merge; manual notification remains in force and no polling was restarted.

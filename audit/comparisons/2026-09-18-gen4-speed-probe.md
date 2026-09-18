# Retrospective comparison: gen4-speed-probe

**Date:** 2026-09-18
**Author:** Mo Auditor (Hermes-hosted comparison session)
**Status:** comparison of filed readings and bounded inspection of the supplied source supplement; not a new cold reading or performance experiment.
**Repository base:** `aace4ee36516c9dc67cdb7b0d0c8cab3a5f9c024`.
**Reading/evidence anchor:** `8f03d80c0856c681094bf64fe654b76c6015fa7d`, from `audit/handoffs/gen4-speed-probe/gen4-speed-probe-parallel-filed-001.json`.

The abbreviated supplied pointer `audit/handoffs/gen4-parallel-filed-001.json` does not exist at the base; the exact record above was discovered in the repository, not silently normalized. Likewise the literal truncated source pointer `audit/evidence/2026-09-17/giff` is not a valid evidence-file pointer here. The recovered source diff is `audit/evidence/2026-09-17/gen4-speed-probe/board-sweep.diff`; companion paths below come from the record's named parallel reading and the bundle directory.

The auditor file was read first, then Fable's. Both readings and the four source-supplement files are byte-identical between the handoff anchor and base. Line citations refer to the handoff anchor unless explicitly stated otherwise. No prior reading is rewritten.

## Conclusions: agreement on slowdown, disagreement on memory meaning

Both readings identify a contracts-on regression and near parity with contracts off ([auditor, lines 24–41 and 55–60](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/mo-audit-2026-09-17-gen4-speed-probe.md#L24-L60); [Fable, lines 18–30](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/fable-reading-2026-09-17-gen4-speed-probe.md#L18-L30)). Both prefer the surface pair, 533 versus 1,664 pairs/s, to conflating profiling and non-profiling configurations. These are inherited measurements, not reruns in this comparison.

The substantive disagreement is **what lower RSS establishes**. The auditor calls 46 MiB versus 173 MiB a memory win and CPU-for-memory trade ([lines 35, 47 and 58](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/mo-audit-2026-09-17-gen4-speed-probe.md#L35-L58)). Fable rejects treating it as a design saving, cites contracts-off 169 MiB versus 168 MiB, proposes contract-triggered compaction, and explicitly says its cheap-contract control probe has not run ([lines 61–76](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/fable-reading-2026-09-17-gen4-speed-probe.md#L61-L76)). Agreement on the reported low number does not resolve this interpretation dispute. Neither a general design benefit nor the proposed mechanism is established by this comparison.

**Filed disposition:** decision-log row `AUD-COMP-GEN4-RSS-001` preserves both positions with equal standing and refers the unresolved interpretation to Robert. Retain measured RSS, but do not treat an untested causal explanation as a finding. No rule threshold or prior reading is amended and no control probe is authorized or executed here.

## Causes: source gap supplied, runtime attribution refined

The original auditor inferred ownership-transfer work under `List.all?`, explicitly without a source diff, and entertained contention as an untested explanation ([lines 8, 39–41 and 49–53](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/mo-audit-2026-09-17-gen4-speed-probe.md#L39-L53)). Fable distinguishes the program's O(finished jobs) postcondition from the backend's repeated walk of the captured board ([lines 32–59](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/fable-reading-2026-09-17-gen4-speed-probe.md#L32-L59)). Its earlier decision-log row 498 denied runtime causation, but row 500 already records the runtime multiplier. Do not manufacture a second live disagreement by ignoring that refinement.

This comparison actually inspected the following supplied snippets:

- `audit/evidence/2026-09-17/gen4-speed-probe/board-sweep.diff:4–7`: the added `all_ends(result.board).all?` postcondition captures `board` for `old_enough?`.
- `audit/evidence/2026-09-17/gen4-speed-probe/board-decide-gen4.txt:1–10`: `decide` invokes `sweep` before dispatch, including lease and ack.
- `audit/evidence/2026-09-17/gen4-speed-probe/emitted-a27.txt:9–13`: the emitted closure calls `mo_disown_in(cap[0])` before using the capture.
- `audit/evidence/2026-09-17/gen4-speed-probe/mo_rt-disown_in.txt:1–20`: disowning traverses record fields, with map/set handling and an early return if `owned.used == 0`.

The supplement supports the source-level refinement, not a measured allocation of the slowdown between program and backend. It is a bounded snippet, not a full branch diff proving there are no other relevant changes. It does not establish shared-lock contention, nor confirm compaction as the RSS cause. The original source-availability gap is supplied retrospectively; the historical cold reading's limit remains accurate for what it had. The state already records the supplement as supplied.

## Limitations and independence

The auditor notes single trials and missing intermediate worker counts ([lines 49–53 and 67–73](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/mo-audit-2026-09-17-gen4-speed-probe.md#L49-L73)). Fable notes no isolated closure-capture benchmark, no Mac rerun and no fix ([lines 108–121](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/fable-reading-2026-09-17-gen4-speed-probe.md#L108-L121)); its compaction control is also unrun. No timings, profiles or checker outputs were regenerated here. No universal program-7 multiplier follows from these runs.

Fable discloses exposure to Robert's relayed auditor verdict and findings before writing ([line 6](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/fable-reading-2026-09-17-gen4-speed-probe.md#L6)); not opening the auditor file did not remove that exposure. This limits independent corroboration without deciding technical truth.

## Implications and duplicate check

Both retain shipped contracts-on cost as relevant. Fable distinguishes shipped-program scoring from runtime causal attribution ([lines 78–106](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/fable-reading-2026-09-17-gen4-speed-probe.md#L78-L106)); the auditor treats the profile as a warning for a future program-7 test, not that test itself ([lines 57–65](https://github.com/robertguss/mo-lang/blob/8f03d80c0856c681094bf64fe654b76c6015fa7d/audit/mo-audit-2026-09-17-gen4-speed-probe.md#L57-L65)). No RC2 reinterpretation or stopping-rule pass/failure is imposed here. Existing hot-path and brick/auditor separation concerns remain open.

The whole decision log was narrowly searched for subject names and RSS/compaction/memory-benefit terms, and full rows 498–501 were inspected at the base. Rows 498 and 500 cover causal attribution; row 501 covers compounding costs; none records the RSS disagreement with both readings. The prior handoff (`audit/mo-audit-2026-09-17-auditor-handoff.md:22–32`) likewise identified it as unlogged. Only the RSS disagreement warrants a new decision-log row.

Return record: `audit/handoffs/gen4-speed-probe/gen4-speed-probe-compared-001.json`. Records are addressed to Fable after both readings were filed; publication does not establish receipt. Main advanced to `a85d09eb70993869327a2eb295a30415d5451037` during this work (step-36 reading integration); its state addition is outside this comparison's edits. The comparison branch remains based on the requested pinned commit. No code, step-36 branch, polling, rules or lead sessions were changed.

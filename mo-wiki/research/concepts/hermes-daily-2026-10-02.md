---
title: "Hermes daily research: result limits and cancellation obligations, 2026-10-02"
created: 2026-10-02
updated: 2026-10-02
type: concept
tags: [research, runtime, processes, verification, security]
sources: [raw/articles/elixir-task-1-18-4-2026-10-02.md, raw/papers/sethi-task-cancellation-osdi-2022-2026-10-02.md]
confidence: medium
---

# Hermes daily research: result limits and cancellation obligations, 2026-10-02

## Scope and current context

**Hermes recommendation:** distinguish a result limit, an admission limit (how much work starts), a wait deadline, and confirmed cleanup. These are separate promises. This is background reading, not a new release alert or a proposal to revive the parked parallel scanner.

Research base is fetched main **3def7d41c9e88d9bef5f64be7e21c838397109e4**. Previous research PR 32 was verified merged; the clean isolated checkout now uses a fresh `research/hermes-20261002` branch from main. `HANDOFF.md:9–36` and `plans/roadmap.md:13–30` still prioritize useful small tools and moscope. No divergent active lead branch is named; remote `moscope/real-data-v2` resolves to **eff64c56d9198ff7734c0b19d3ce59d998734903**, the merged checkpoint named in the handoff.

Current [[01-premise]] is agent-native; Robert's later learning/creation/usefulness purpose remains in `decisions/decision-log.md:2295`. Lead acceptance claims were read as context, not independently reproduced. Research exposure includes those records, prior daily/weekly notes, chapter 1, chapter 3's timeout/cleanup clauses and chapters 5–6. **Not a cold audit**; manual-only audit intake stays unchanged. No experiments, implementation edits, private-data access or new acceptance requirements.

## 1. Returning fewer results need not mean doing less work

The **Elixir v1.18.4 Task manual** documents that `Task.async_stream` processes concurrently even with ordered output; ordering can require buffering results.[1] Its default concurrency follows `System.schedulers_online/0`, while its timeout is per task, with caller exit as the default timeout action and `:kill_task` as an alternative.[1]

The manual explicitly warns that placing `Enum.take` after an async stream can process more inputs than the retained result count.[1] It recommends limiting inputs before the async stage when that matches the problem, or adjusting concurrency to reduce over-processing.[1] An input cap is not equivalent to “find the first N successful matches”: limiting inputs can also limit the search coverage. That distinction is Hermes's interpretation, not a measured Mo result.

**Relevance to Mo:** a recipe that promises bounded output has not thereby promised bounded total work, memory, or external effects. Likewise, returning results in input order does not itself promise that effects occurred in that order. A future comparative workload should state which limit it needs before comparing a serial implementation with a concurrent one. No concurrency change is recommended for today's moscope queue.

## 2. Timeout, result-count completion and task termination differ

`Task.yield/2` can return `nil` on timeout while leaving the monitor active; `Task.ignore/1` leaves the task running and unlinks it.[1] `Task.shutdown/2` instead signals shutdown and escalates to killing after its grace timeout, or kills immediately with `:brutal_kill`; a result can still be returned when completion races with shutdown.[1]

A particularly useful boundary: `Task.yield_many/2` documents that reaching its `:limit` before timeout returns immediately **without triggering `:on_timeout` behavior**.[1] Therefore, choosing `on_timeout: :kill_task` should not be read as “kill every remaining task whenever this call returns.” This is a reading of the documented API, not an exercised runtime claim.[1]

Mo already makes a related distinction explicit: `03-semantics.md:54–65` says timeout means the caller stopped waiting, and an `ask` may still change state. Its local rollback and cleanup clauses (`:52`, `:75`) do not claim to undo effects that escaped the process. **Hermes recommendation:** retain that explicitness in agent-facing completion reports: “enough results,” “wait expired,” “stop requested,” and “owned work terminated” should not be interchangeable statuses. This does not identify a current implementation defect or require new syntax.

## 3. Cancellation needs more than a token or signature

Sethi and colleagues' **OSDI 2022** study examined **62 cancellation-feature requests and 156 cancellation-related bugs across 13 Java, C# and Go systems**, searching resolved issues through **June 2021**.[6] It distinguishes initiating cancellation, propagating the request and fulfilling it, including cleanup; it studies cooperative cancellation, not BEAM process termination.[6]

The study describes both missed and excessive cancellation, omitted propagation, and defective cleanup.[6] Some failures reported cancellation to users when work had not actually stopped; others cleaned up resources or shared state incorrectly.[6] Its static checkers identify useful anti-patterns but are not correctness proofs: section 7 reports false positives, and section 7.6 explains how conditions intended to reduce false positives introduce false negatives.[6]

**Capabilities/recipes connection — Hermes inference:** Mo chapter 6's recipe checks constrain signatures, capabilities and contract/test obligations (`06-packages.md:27`). A cancellation parameter, or permission to perform cleanup, does not alone establish that cancellation reaches every relevant task or that cleanup completes. For a future separately authorized recipe evaluation, specify the target set, effects already committed, cleanup ownership and permitted retry behavior; test those outcomes rather than merely checking a cancellation flag.

**Proposed controls only:** normal completion; cancellation before start; cancellation during an effect; completion racing with cancellation; cleanup failure; repeated cancellation; and a remaining task whose result is still required. Include a deliberately non-propagating or incomplete-cleanup implementation to check that the verifier rejects it. Nothing was executed, and these are not amendments to any sealed suite or standing stopping rule.

**Limitations and contrary evidence:** the study's keyword search and clear-description filter can miss issues, its feature-request search is title-limited, and its findings need not generalize beyond the sampled systems.[6] Actor isolation changes the shared-heap cleanup problem; these historical bug counts cannot rank Mo against BEAM. The Task manual also supplies explicit lifecycle controls, so the evidence is not that Elixir lacks cancellation.[1] No exact OTP pairing, underlying implementation inspection or latest-version claim was established.

## Coverage, provenance and validation

- Three Exa discovery queries: versioned Elixir task APIs, primary cancellation research, and OTP timer cancellation. **12 distinct URLs**, all new to the local URL ledger. Two material primary texts captured; the other discoveries remain snippet-only/deferred. No new timer claim is based on the third query.
- Task manual section-read: async-stream options/early stopping, await timeout, ignore, shutdown, yield and yield-many. Paper read through the complete returned extraction, including methodology, limitations and checker evaluation; PDF figures were not visually inspected. No comprehensive release/advisory sweep.
- Cached retrieval titles agree with the selected version and paper. The paper extraction is exactly 80,000 characters, contains conclusions and final references and no literal truncation marker; that does not prove every PDF element survived extraction. Immutable fetched text and separate wrapped reading copies are retained. Publication is July 2022, issue cutoff June 2021; October 2 is ingestion.
- Baseline lint: **301 pages, 29 inherited notices**, exit 0. Final lint: **302 pages, the same 29 notices**, exit 0 (15 review flags, 14 size notices); no new technical issues. All **216 exact-byte raw body hashes** pass; staged snapshots match fetched bodies. Citation/evidence validation passes; ten discovery-only URLs remain intentionally uncited.
- Authored staged whitespace and sensitive-pattern checks pass. Full staged whitespace exits **2** with **175 immutable-raw-only notices**; fetched bytes are preserved rather than normalized. `log.md` working-tree and PR-range diffs are empty. Five allowed files only: this note, index, Elixir backlink and two raw snapshots. Owner decisions, specs and implementation are unchanged; scratch and ledgers stay outside the checkout. Publication is a research-only review PR, never auto-merged.

## Related

- [[elixir]] — versioned API follow-ups, without rewriting the historical comparison.
- [[hermes-daily-2026-09-19]] — timeout and replay boundaries.
- [[capability-module-lineage]] — authority is not completion evidence.
- [[reliability-and-testing-philosophies]] — discriminating verification and fault coverage.

## Sources

[1] https://hexdocs.pm/elixir/1.18.4/Task.html — Task — Elixir v1.18.4 - Hexdocs
[6] https://www.usenix.org/system/files/osdi22-sethi.pdf — [PDF] An Empirical Study of Task Cancellation Patterns and Failures

---
title: "Hermes daily research: diagnostic loss under load, 2026-09-30"
created: 2026-09-30
updated: 2026-09-30
type: concept
tags: [research, runtime, processes, verification, tooling]
sources: [raw/articles/otp-28-logger-overload-2026-09-30.md, raw/papers/gunawi-fail-slow-fast-2018-2026-09-30.md]
confidence: medium
---

# Hermes daily research: diagnostic loss under load, 2026-09-30

## Scope and current context

**Hermes recommendation:** distinguish “the program recovered” from “the diagnostic record is complete.” A bounded diagnostic channel can be a sensible availability policy without being a complete history for an agent's verdict. Today's background reading adds overload and slow-but-functioning dependencies to the prior work on truthful failure/completeness reporting; it is not a new release or vulnerability announcement.

Mo context: fetched main **d58f67cd9df14b6f67e63527451e41a796ce18d8**; starting research HEAD **b6b0d2127cd06cf7540a1b9961e63b6447b06645**. Clean branch, main already integrated by normal merge. `HANDOFF.md:9–36` and `plans/roadmap.md:13–30` still prioritize useful small tools and moscope friction. Current [[01-premise]] is agent-native; Robert's later learning/creation/usefulness purpose remains at `decisions/decision-log.md:2295`. The acceptance and parked-work rows at `:2307–2317` are context, not independently verified results here. No divergent active lead branch is named; remote `moscope/real-data-v2` remains **eff64c56d9198ff7734c0b19d3ce59d998734903**, already integrated in main.

Research only, **not a cold audit**. Prior exposure includes lead handoff/decisions, current chapters 1, 3, 5, 6, chapter 9's Runtime section, and previous daily/weekly research. Manual-only audit intake stays unchanged. No implementation edits, experiments, runtime checks or revival of parked work. These sources neither establish Mo superiority nor displace Elixir/BEAM as a runtime comparator.

## 1. Runtime reliability: overload protection can deliberately lose evidence

The fetched **OTP 28.5.0.1 / kernel 10.6.3.1** guide describes built-in Logger handlers that switch from asynchronous to synchronous logging, drop newly issued events, or flush queued events as their queue grows.[3] In drop mode the logging call returns without sending the event.[3] The guide explicitly says synchronous mode can slow one or a few busy senders but cannot sufficiently protect the handler from many concurrent senders.[3]

This is configurable loss policy, not an allegation that OTP is unreliable. The documented queue thresholds are **10** for synchronous mode, **200** for drop mode and **1000** for flushing; burst limiting is enabled by default at **500 events per 1000 milliseconds**, while overload-triggered termination/restart is disabled by default.[3] These are defaults for the built-in handlers in this saved guide, not confirmed Elixir wrapper defaults, an installed runtime measurement, or settings observed in Mo's historical comparator.[3]

The same guide documents a separate Logger proxy, with different thresholds and burst limiting disabled by default; remote forwarding uses `erlang:send_nosuspend/2` and drops an event rather than suspend if sending would block.[3] **Hermes interpretation:** a comparison must name the actual path and configuration. “BEAM logging” is not one uniform delivery guarantee, and successful application requests are not a count of retained diagnostics.

## 2. Slow is a separate fault model, not just a late crash

Gunawi and colleagues' **FAST 2018** paper collects **101 reports from 12 institutions**, with incidents reported during **2000–2017**.[5] It describes hardware still functioning but at degraded performance, with symptoms that can be permanent, transient or partial, and cases of recurring temporary stops.[5]

The authors report that timeouts and repeated retries can consume other resources and turn one slow component into wider failure.[5] They propose fault injection and better visibility, but also warn that simply taking slow devices offline can increase re-replication load, reduce availability, or miss an external root cause.[5] **Hermes recommendation:** do not treat “restart it” or “add a timeout” as a complete slow-dependency policy; account for remaining work, retry budgets and progress after the slowdown ends.

**Limitations:** this is an anecdotal, retrospectively collected study, not a measured incidence rate or a trial of Mo/BEAM.[5] A report may stand for multiple occurrences, and the authors explicitly cannot answer population-level frequency or performance-distribution questions from these data.[5] PDF extraction interleaves some table/column text; no table percentages, figure-derived measurements or hardware-specific performance ratios are adopted here. The reading supplies candidate failure modes, not a diagnosis of Mo's open guard flake.

## 3. Capabilities, recipes and verification: authority is not completeness

Mo already specifies a bounded runtime-event ring, default **4,096** entries (`09-stdlib.md:370`), and a separate crash store retaining the last **16** reports with bounded text fields (`:437`). `Runtime.events` returns events the ring still holds (`:436`); `Runtime.read_only` limits actions (`:443`). Chapter 3 separately describes writing a whole crash report to stderr and retaining its cut copy (`03-semantics.md:73,83`). These are current specification statements, not an implementation audit or a claim that channels have been exercised.

**Hermes interpretation:** the runtime surface, crash store, stderr capture and OTP Logger are different mechanisms. Compare their actual obligations rather than equating them. In particular, a consumer holding read-only authority does not thereby receive a complete history. A recipe whose verdict relies on diagnostic evidence should state which observation window it covers and what it does when capture is incomplete. That would complement the capability/signature/test conformance described in `06-packages.md:27`, not replace it.

**Proposed follow-up only, if separately authorized:** use a synthetic producer with independently known event identities and a controlled slow consumer; distinguish normal delivery, overload loss, retention wrap, consumer recovery, and an unavailable diagnostic channel. Keep ordinary operation results separate from evidence-completeness results. Specify which losses are permitted before checking interpreter and native behavior. A correctly bounded ring discarding old history is not itself a defect, and these are not new acceptance gates or assertions that existing tests omit coverage.

## Coverage, provenance and validation

- Four Exa requests covered OTP logging overload, primary fail-slow research and Elixir logging discovery: **12 distinct URLs**, all new to the local ledger. The exact Elixir 1.19.0-path search returned no results; one broader query returned current wrapper documentation and source pointers. The empty receipt is preserved; those wrapper results remain discovery-only, not a version-matched comparison.
- Two primary bodies were retrieved from Exa's cache and read completely as extracted text: the OTP guide and FAST paper. All other results are deferred/snippet-only. No comprehensive release/advisory or ecosystem scan is claimed.
- The OTP search title and fetched body agree on **28.5.0.1 / kernel 10.6.3.1**; other returned OTP pages have different patch labels and were not substituted. The version-series URL is not an immutable source revision. The paper's publication is February 2018; September 30 is ingestion. Separate wrapped reading copies preserve immutable source bytes; no literal truncation markers were found, but diagrams were not visually inspected.
- Baseline native lint: **299 pages, 29 inherited notices**, exit 0 (15 review flags and 14 size notices). Final lint: **300 pages, the same 29 notices**, exit 0; no new technical issues. All **212** hash-bearing raw snapshots pass exact-byte body verification; both staged captures match retrieval. Citation/evidence verification passes; ten discovery-only sources remain intentionally uncited.
- Authored staged whitespace and sensitive-pattern checks pass. Full staged whitespace exits **2** with **187 immutable-raw-only notices**; source bytes are preserved, not normalized. Working-tree and PR-range `log.md` diffs are empty. Five explicitly staged allowed paths.
- Changes are limited to this dated note, an Elixir comparison backlink, index navigation and two raw sources. Scratch scripts, citation/read-status ledgers and validation receipts stay outside the checkout. `log.md`, specifications, decisions, handoff, roadmap, implementation and audit files are untouched. Review-only publication reuses PR 32; no auto-merge.

## Related

- [[elixir]] — comparator context and historical-versus-current caveats.
- [[hermes-daily-2026-09-19]] — timeout, cancellation and replay distinctions.
- [[hermes-daily-2026-09-25]] — buffered I/O, cleanup and oracle limitations.
- [[reliability-and-testing-philosophies]] — fault models and evidence quality.

## Sources

[3] https://www.erlang.org/docs/28/apps/kernel/logger_chapter.html — Logging — OTP 28.5.0.1 (kernel 10.6.3.1)
[5] https://www.usenix.org/system/files/conference/fast18/fast18-gunawi.pdf — Fail-Slow at Scale: Evidence of Hardware Performance Faults in Large Production Systems

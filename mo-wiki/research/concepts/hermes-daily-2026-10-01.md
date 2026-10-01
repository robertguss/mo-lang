---
title: "Hermes daily research: diagnostic configuration and disclosure, 2026-10-01"
created: 2026-10-01
updated: 2026-10-01
type: concept
tags: [research, runtime, security, verification, tooling]
sources: [raw/articles/elixir-logger-1-18-4-2026-10-01.md, raw/papers/lyons-sensitive-logging-security-2023-2026-10-01.md]
confidence: medium
---

# Hermes daily research: diagnostic configuration and disclosure, 2026-10-01

## Scope and current context

**Hermes recommendation:** describe diagnostic evidence along separate axes: what was generated, what was retained, and who may learn what from it. Yesterday's overload reading addressed retention; today's follow-up adds build/runtime configuration and disclosure. This is background research, not a new release or vulnerability alert.

Fetched main **d58f67cd9df14b6f67e63527451e41a796ce18d8**; starting research HEAD **1dc6f26242d3f698f3e420eca8f08cf0c12ae1f7**. The checkout started clean and main was already integrated. `HANDOFF.md:9–36` and `plans/roadmap.md:13–30` still prioritize moscope and useful small tools. Current [[01-premise]] is agent-native; Robert's later learning/creation/usefulness purpose is recorded at `decisions/decision-log.md:2295`. Acceptance and parked-work rows at `:2307–2317` are lead context, not independently verified results here. No divergent active lead branch is named; remote `moscope/real-data-v2` still resolves to **eff64c56d9198ff7734c0b19d3ce59d998734903**, already incorporated in main.

Research only, **not a cold audit**. Prior exposure includes lead handoff/decisions, previous daily/weekly research, current chapter 1, chapter 6 and chapter 9's Runtime section. Manual-only audit intake is unchanged. No experiments, implementation review, private-history access or revival of parked work. Nothing here establishes a Mo advantage over Elixir/BEAM.

## 1. Elixir logging configuration changes what a test exercises

The versioned **Elixir Logger v1.18.4** manual identifies Logger as mostly a wrapper around Erlang's logger, and separates boot, compile and runtime configuration.[10] Its documented default handler uses `:logger_std_h`; handler-specific overload configuration belongs to that handler, rather than to an undifferentiated “Elixir logging” setting.[10] This follows yesterday's wrapper-discovery gap but does not establish an exact OTP pairing or the settings used by Mo's historical comparator.

Logger macros normally evaluate their messages only when the configured level requires them; `:always_evaluate_messages` defaults to `false`.[10] The manual specifically warns that a test environment using a high minimum severity may miss errors in message construction that appear when production enables lower-severity logging.[10] `:compile_time_purge_matching` can remove matching calls altogether, and purging a dependency requires recompiling it.[10]

**Hermes interpretation:** logging is another configuration-sensitive code path, not just an output switch. A clean stderr transcript cannot alone distinguish “no error occurred” from “the relevant diagnostic path was disabled.” For a future matched comparison, record both build-time removal and runtime/handler settings before interpreting an empty diagnostic stream. This is a proposed evidence practice, not a finding that Mo's tests currently make that mistake.

## 2. Removing obvious identifiers is not the whole disclosure problem

Lyons and colleagues' **USENIX Security 2023** Android study combines stock-device testing, automated app execution, crowdsourced local log analysis, manual case studies and static analysis of log-reading apps.[6] Its field collection ran **March 2–21, 2022**; the authors report finding personal information on **1,142 of 1,214** analyzed devices (**94.1%**, their reported percentage).[6] These are historical sample results, not present-day Android prevalence or measurements of Mo/BEAM.

The paper shows that logged activity names can reveal user actions even without an explicit sensitive-value field; it also reports that object-to-string rendering and SDK logging configuration can expose data.[6] The authors' recommendation includes inspecting release-candidate logging and considering what activity names disclose, not merely checking whether an application contains deliberate password logging.[6]

A useful counterweight to “collect everything for debugging”: the field study analyzed raw logs inside participants' browsers and sent summary findings rather than raw logs to the researchers.[6] **Hermes recommendation:** where real-history debugging is separately authorized, prefer minimized local analysis and aggregate receipts over publishing raw history. This scan accessed no private logs.

**Limitations and contrary evidence:** the automated app exercise was a lower-bound screen; identifier availability varied by Android version, participant geography was uneven, and field attribution lacked a complete installed-app list.[6] The static analysis could miss native/dynamically loaded/reflection-based behavior and could flag dead code; the paper also reports Android 13 access-control changes following disclosure.[6] Do not turn these results into a current vulnerability claim, or adopt the paper's broad release-logging-disable advice as a Mo policy without weighing diagnostic usefulness. PDF columns and tables are imperfectly extracted; no table-derived breakdown or uninspected figure is used here.

## 3. Capabilities and recipe checks: distinguish mutation authority from disclosure

Mo's current `09-stdlib.md:434` describes `Runtime.state` returning process state as a crash report prints it; `:437` describes bounded crash snapshots. `Runtime.read_only` at `:443` refuses `send`, `pause` and `resume`. These are inspected specification statements, not tested implementation behavior. Chapter 6's recipe conformance checks capability/signature/contract/test obligations (`06-packages.md:27`).

**Hermes interpretation:** preventing runtime mutation is valuable but is not the same claim as concealing sensitive state from a permitted reader. Likewise, a field-length bound is not a redaction policy. A diagnostic recipe should make its intended audience and allowed data explicit; capability conformance alone should not be described as proving confidentiality.

Elixir's documentation supplies both primary filters, applying to all handlers, and handler-local filters.[10] **Proposed follow-up only:** if separately authorized, use synthetic canary values in ordinary messages, crash state and metadata; inspect every intended output path under release configuration, with both allowed and forbidden disclosures specified beforehand. Include informative event names, not just fields named “secret.” No such check was run, and no new acceptance gate or Mo defect is asserted.

## Coverage, provenance and validation

- Three Exa searches covered versioned Elixir logging, OTP filtering and primary logging/privacy research: **nine distinct discovery URLs**, all new to the local ledger, plus one directly requested versioned Logger manual URL. The exact-version query returned only the Translator page; it did not establish the main manual's semantics. Those came from the subsequently fetched main manual.
- Two cached primary texts were captured immutably. The Logger manual was **section-read** (overview, configuration, handlers/filtering/compatibility and flush); the paper was read fully as extracted text. Other discoveries remain snippet-only/deferred. No comprehensive advisory/release sweep, runtime reproduction or current Android implementation inspection.
- The manual's fetched title/body agree on **v1.18.4**; no latest-version claim or inferred OTP-version match. Paper publication is August 2023; October 1 is ingestion. Exact fetched bytes are preserved separately from wrapped reading copies; no literal truncation markers were found. Figures were not visually inspected.
- Baseline native lint: **300 pages, 29 inherited notices**, exit 0; final lint: **301 pages, the same 29 notices**, exit 0 (15 review flags, 14 size notices). No new technical issues. All **214** exact-byte raw body hashes pass, and both staged snapshots match retrieval. Citation/evidence verification passes; eight discovery-only sources remain intentionally uncited.
- Authored staged whitespace and sensitive-pattern checks pass. Full staged whitespace exits **2** on **74 immutable-raw-only notices**; source bytes are preserved rather than normalized. Working-tree and PR-range `log.md` diffs are empty. Owner history is unchanged.
- Five allowed paths: this note, the Elixir comparison backlink, index entry and two raw snapshots. Scratch scripts, citation/read-status ledgers and validation receipts remain outside the checkout. Publication is review-only through PR 32; no auto-merge.

## Related

- [[elixir]] — historical comparison and dated research follow-ups.
- [[hermes-daily-2026-09-30]] — overload loss versus service recovery.
- [[capability-module-lineage]] — authority boundaries and their limitations.
- [[reliability-and-testing-philosophies]] — coverage and evidence quality.

## Sources

[6] https://www.usenix.org/system/files/usenixsecurity23-lyons.pdf — Log: It’s Big, It’s Heavy, It’s Filled with Personal Data! Measuring the Logging of Sensitive Information in the Android Ecosystem
[10] https://hexdocs.pm/logger/1.18.4/Logger.html — Logger — Logger v1.18.4

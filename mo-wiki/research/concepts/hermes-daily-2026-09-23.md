---
title: "Hermes daily research: retained bytes and trustworthy goldens, 2026-09-23"
created: 2026-09-23
updated: 2026-09-23
type: concept
tags: [research, runtime, verification, tooling]
sources: [raw/articles/otp-27-binary-retention-2026-09-23.md, raw/articles/sqllogictest-about-2026-09-23.md, raw/articles/sqllogictest-row-count-forum-2026-09-23.md, raw/articles/sqllogictest-row-count-checkin-2026-09-23.md]
confidence: medium
---

# Hermes daily research: retained bytes and trustworthy goldens, 2026-09-23

## Current context, not a cold audit

Research pinned to `origin/main` **d58f67cd9df14b6f67e63527451e41a796ce18d8**. PR 31 was merged, so this run starts a fresh research-only branch. Current [[HANDOFF]] and [[roadmap]] prioritize using moscope on real history and fixing the language problems it exposes. The latest owner-purpose row says learning and creating a useful language matters with or without adoption (`decisions/decision-log.md:2295`). This supplements the agent-native premise in [[01-premise]]; it does not revive the historical BEAM-superiority gate or the parked harness queue.

The latest acceptance row reports moscope v2 and its JSON/allocator fixes accepted on Darwin, with no Linux replay or auditor reading (`decision-log.md:2307`). That is a **project record read for research, not an independently verified result here**. The named remote `moscope/real-data-v2` exists at `eff64c56d9198ff7734c0b19d3ce59d998734903` and is an ancestor of current main; the handoff does not name a divergent active implementation branch. No parked candidate was inspected or resumed.

Relevant prior exposure: lead handoff/decisions, specification chapters 1, 3, 5 and 7, and earlier Hermes research. This is not an unexposed cold reading. No audit intake, implementation edits, examples executed, benchmarks or acceptance tests. The local schedule record marks September 22 failed; this note does not backfill that missing scan or reset its claim.

## 1. BEAM comparison: output length is not retained storage

The OTP 27 binary manual documents `binary:referenced_byte_size/1`, which exposes the underlying binary's size rather than just the size of the selected part.[2] It describes copying a smaller binary to release a reference to a larger backing binary, while warning that copying can instead increase memory use if another process still references the original.[2] ^[raw/articles/otp-27-binary-retention-2026-09-23.md]

The manual's example distinguishes a small part that was copied from a larger part that still references its parent; do not assume every slice retains its parent.[2] Its example threshold of twice the selected data size is explicitly example-specific, not a universal tuning rule.[2] ^[raw/articles/otp-27-binary-retention-2026-09-23.md]

**Hermes interpretation:** for a future authorized streaming/excerpt comparison, separately report logical retained text, backing storage and process memory. A bounded excerpt is not, by itself, evidence that its former input buffer was released. Conversely, sharing is an optimization, not inherently a leak. Keep a case where the original remains legitimately live as a counterweight to a copy-everything policy.

**Mo relevance, not a finding:** chapter 3's reachability-based memory promise (`03-semantics.md:38`) and chapter 7's memory bets are the local context. This reading neither shows that Mo shares substring storage nor establishes a current Mo retention defect. The recent moscope allocator fix is not reverified by reading Erlang documentation. An Elixir/BEAM baseline should not be deliberately handicapped by ignoring documented memory diagnostics, and the documentation alone establishes no comparative speed or memory result.

## 2. Goldens need an origin and a checker that rejects omissions

A **golden** is saved expected output. Sqllogictest's documented completion mode generates that output from a reference engine; its validation mode compares a tested engine against the saved results.[5] The stated rationale is independently developed engines as reference producers, and completion mode ignores pre-existing expected values rather than checking them.[5] ^[raw/articles/sqllogictest-about-2026-09-23.md]

That design also names its limits: it tests computed answers, not performance, memory, transaction behavior or concurrency; the documented script format excludes Unicode testing.[5] This is a method to borrow selectively, not an off-the-shelf moscope acceptance suite.[5] ^[raw/articles/sqllogictest-about-2026-09-23.md]

A useful historical warning: on **2024-11-14**, a sqllogictest user reported a row-count mismatch passing with zero errors, including an empty-result reproducer and a proposed checker patch.[7] Richard Hipp's reply points to the **2024-11-15** fix, and the linked check-in overview explicitly says it verifies the correct number of returned rows.[7][13] This is a reported historical defect with a corroborating upstream change record, **not a bug reproduced here or a claim about today's implementation**. ^[raw/articles/sqllogictest-row-count-forum-2026-09-23.md] ^[raw/articles/sqllogictest-row-count-checkin-2026-09-23.md]

**Hermes recommendation:** retain moscope's reviewed goldens as goldens (`decision-log.md:2305`), while naming how each expected result was established. Interpreter/native agreement is valuable, but shared logic and shared expected output are not independent evidence of intended behavior. Keep expectation regeneration separate from ordinary verification. For any later authorized checker review, ask whether missing, extra, truncated and empty output are rejected, with exit status and stderr checked separately from stdout. This run did not inspect or exercise `acceptance/check.py`, so it asserts no missing control in that checker.

No need to reopen the large verifier or impose a new framework: a small understandable checker can provide strong regression evidence when its expectations and failure behavior are independently examined. Neither goldens nor backend agreement establish general memory safety.

## Coverage and provenance

- Three targeted Exa searches: OTP binary retention; sqllogictest reference-output verification; academic memory-safety testing. **Twelve distinct discovery URLs**, plus one followed upstream check-in URL. No date filter: these are new-to-this-scan background findings, not new releases.
- Fully read four extracted bodies: the OTP binary API manual, sqllogictest overview, historical forum thread and linked check-in overview. The first three are Exa cached text; the fourth is `web_extract` markdown. No raw HTML, patch diff or external runtime implementation inspection.
- The OTP search title and fetched body agree on **OTP 27.3.4.16 / stdlib 6.2.2.4**. This version-series documentation is not an exact source inspection of the earlier comparison runtime. Sqllogictest's overview is live trunk documentation with no publication date; forum/check-in dates are retained separately from ingestion on September 23. Its extraction loses some argument placeholders, so this note does not reproduce a supposedly complete script grammar.
- Four academic paper hits remain discovery-only; no paper measurements are credited. No new capability/recipe-safety deep dive today. Prior wiki coverage mentioned SQL Logic Test generally; this note adds specific golden-origin and missing-result evidence without duplicating a topic page.
- Four immutable snapshots preserve extracted body bytes and hashes. Local URL/version/read-status and citation ledgers record retrieval scope. No private session contents were read or published.

## Validation and publication record

- Native lint before: **291 pages, 29 inherited notices**, exit 0. After: **292 pages, the identical 29 notices**, exit 0 (15 review flags and 14 size notices; no schema/link failures).
- All **193** hash-bearing raw snapshots pass exact-byte body verification after the closing frontmatter delimiter. Citation/evidence verification passes; nine discovery-only ledger entries are intentionally uncited.
- Full staged whitespace check exits **2**, with **98 notices confined to immutable source snapshots**. Those extracted bytes are preserved; authored prose passes. The seven-file allowed scope and sensitive-pattern scan pass. `log.md` has no diff; no implementation or owner-history paths are staged.
- Changed files: this daily note, the index, a dated inbound link in `reliability-and-testing-philosophies.md`, and the four raw snapshots listed in frontmatter. Machine validation and publication receipts stay outside the checkout under the profile's research directory.
- Research publication is review-only, never an auto-merge. Specifications, decisions, roadmap, handoff and implementation remain read-only in this lane.

## Related

- [[reliability-and-testing-philosophies]] — existing testing traditions and harness diversity.
- [[elixir]] — runtime comparison without a superiority claim.
- [[hermes-daily-2026-09-20]] — heap limits versus whole-workload memory accounting.
- [[hermes-weekly-2026-09-21]] — earlier evidence and scope limits.
- [[moscope-v2]] — current useful-workload context, not accepted by this research.

## Sources

[2] https://www.erlang.org/docs/27/apps/stdlib/binary.html — binary — OTP 27.3.4.16 (stdlib 6.2.2.4)
[5] https://sqlite.org/sqllogictest/doc/trunk/about.wiki — sqllogictest: Documentation
[7] https://sqlite.org/forum/forumpost/115a6fedd9 — SQLite User Forum: sqllogictest row count mismatch
[13] https://sqlite.org/sqllogictest/info/c5ec0e8e41a8106c

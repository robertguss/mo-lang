---
title: "Hermes daily research: streaming Unicode and recovery policy, 2026-09-26"
created: 2026-09-26
updated: 2026-09-26
type: concept
tags: [research, runtime, security, verification]
sources: [raw/articles/otp-28-unicode-streaming-2026-09-26.md, raw/articles/unicode-17-chapter-3-2026-09-26.md, raw/papers/goodspeed-speers-exceptional-utf8-2026-09-26.md]
confidence: medium
---

# Hermes daily research: streaming Unicode and recovery policy, 2026-09-26

## Context and exposure

Research is pinned to accepted main **d58f67cd9df14b6f67e63527451e41a796ce18d8**, unchanged since yesterday, and starting research HEAD **134136a581be1d3030cd6eeb4a69203559bc8dd0**. PR 32 is open; normal merge reports already up to date. The handoff names no divergent active implementation branch. Remote `moscope/real-data-v2` remains **eff64c56d9198ff7734c0b19d3ce59d998734903**, already incorporated into main.

[[HANDOFF]] and [[roadmap]] prioritize useful small tools and friction found through moscope. Robert's learning/usefulness purpose (`decision-log.md:2295`) and current agent-native [[01-premise]] govern this reading. The BEAM comparison remains useful background, not a replacement mandate or a claim settled by the harness comparator. Program 7 and harness work remain parked.

This is **research, not a cold audit**. Exposure includes lead handoff/decisions, chapters 1 and 6, chapter 9's Files/JSON sections and earlier research notes. No private histories, implementation edits, experiments, acceptance runs or automatic audit intake. Recommendations below belong to Hermes.

## 1. Incomplete input is not invalid input

The fetched **OTP 28.5.0.4 / stdlib 7.3.0.1** manual distinguishes invalid encoding (`error`) from a trailing, potentially valid but incomplete character (`incomplete`), retaining the converted prefix and remaining input.[1] It explicitly supports a UTF character split across consecutive binaries and shows retaining the incomplete remainder for the next read.[1] Wrong argument types can instead raise `badarg`; these are not the same failure category.[1] ^[raw/articles/otp-28-unicode-streaming-2026-09-26.md]

**Hermes recommendation:** any later streaming comparison should distinguish a temporary chunk boundary, true end-of-file truncation, malformed input, and caller misuse. Proposed verification property: changing read chunk boundaries must not change the decoded text or reported invalid-input outcome, provided the same final bytes and policy are used. This is a proposed control, not an executed Mo result.

Mo's `09-stdlib.md:160–163` deliberately distinguishes strict `Fs.read`/`read_lines` (`NotText`) from `fold_lines`, which replaces malformed bytes and never returns `NotText`. Match the API contract before comparing reliability. The OTP conversion API does not by itself establish Elixir `File.stream!` behavior; that wrapper question from [[hermes-daily-2026-09-24]] remains open. No exact-runtime implementation check or benchmark was performed.

## 2. Replacement must preserve neighboring valid text; replacement counts are policy

Unicode **17.0.0 §3.9.5** requires a continuing converter not to consume valid successor bytes as part of malformed input, and explicitly notes the security implications.[8] But §3.9.6's “maximal subpart” replacement practice—replace the longest still-plausible prefix, or one byte, with U+FFFD—is **not required for Unicode conformance**.[8] Conformance alone therefore does not specify one universal replacement count.[8] ^[raw/articles/unicode-17-chapter-3-2026-09-26.md]

**Hermes recommendation:** for a future authorized check, include an invalid prefix immediately before valid punctuation, valid multibyte text split across reads, and an incomplete sequence at EOF. Check exact output against Mo's declared byte-replacement rule, not an arbitrary host decoder's default. A converter that swallows a following quote or delimiter is a different problem from two conforming converters choosing different numbers of replacements. No such Mo defect was found or tested today.

**Local contract concern, not a finding of implementation failure:** chapter 9 suggests detecting malformed lines with `line.contains?("\u{FFFD}")` (`:163`). By inspection, that predicate alone cannot distinguish an inserted replacement from a literal U+FFFD already present in valid input. Treat it as “replacement-character present,” not authoritative proof of source corruption. If a recipe needs corruption provenance or exact input identity, Hermes recommends retaining an independent byte-level validation result before lossy conversion; capability narrowing does not itself supply that information. No new API or language policy is authorized here.

## 3. Parser differentials also matter at the logging boundary

Goodspeed and Speers' *Selectively Exceptional UTF8* reports differing acceptance across eleven historical language/database targets and discusses how a service accepting text that its logging backend rejects can lose records.[9] Its proposed search-index scenario is explicitly unverified, and the extracted code/table layout is damaged.[9] These are historical examples and hypotheses, not evidence that current Python, PostgreSQL or MariaDB versions have those behaviors.[9] ^[raw/papers/goodspeed-speers-exceptional-utf8-2026-09-26.md]

**Hermes interpretation:** extend yesterday's [[hermes-daily-2026-09-25|JSON-policy checklist]] across the whole useful-tool path: source bytes, decoding, JSON parsing, matching, excerpts and output. Acceptance at one stage is not evidence that downstream text retains the intended meaning. Reviewed expected outputs should include both valid unusual characters and malformed bytes; do not turn a historical disagreement table into today's oracle. No paper harness was run and no current vulnerability is claimed.

## Coverage and limitations

- Three Exa discovery requests returned **12 distinct URLs**, all new to the local URL ledger. No date filter: this is new background reading for the wiki, not a new-release announcement. Existing research search found no dedicated treatment of these Unicode conversion APIs or this paper.
- Three cached Exa bodies captured with immutable bytes/hashes. Fully read the OTP manual and the paper's extracted text; read Unicode chapter 3 only in §3.9 through §3.9.6. The rest of that chapter remains unread.
- The paper was read through a separate wrapped copy, not silently shortened long lines. No literal truncation marker was detected in captured bodies. Extraction still loses some angle-bracket examples in the Unicode chapter and damages paper tables/code; no claims depend on reconstructing those missing examples, and no figures were visually inspected.
- Search title and fetched OTP body agree on version; this is a series documentation URL, not installed-runtime verification. Unicode version is explicit; paper publication date is not established by its extracted body. All ingestion dates are September 26, 2026.
- Runtime/BEAM and verification received targeted discovery. Recipe safety was considered at the decoding/provenance boundary; no separate capability-mechanism or recipe-ecosystem sweep. Other discovery URLs remain snippet-only. No performance, dependency-reduction or Mo-superiority measurement.

## Validation and publication

- Native lint: **294 → 295 pages**, unchanged **29 inherited notices** (15 review, 14 size), exit 0; no new schema/link failures.
- All **202** hash-bearing raw snapshots pass exact-byte body verification. The three staged new bodies match retrieved bytes. Citation/evidence validation passes; nine discovery-only entries remain intentionally uncited.
- Six explicit allowed paths, sensitive-pattern scan and authored whitespace pass. Full staged whitespace exits **2** on **63 immutable-raw-only notices**; source bytes are preserved, not normalized.
- `log.md` has no working-tree or PR-range diff against main. Changed files: this note, index, Elixir's dated inbound link and the three snapshots in frontmatter. No implementation, specification, decision or owner-history edits.
- Publication is through existing research PR 32 only, without auto-merge. Scratch scripts, citation/source ledgers and validation/publication receipts stay outside the checkout.

## Related

- [[elixir]] — runtime comparison and dated follow-ups.
- [[hermes-daily-2026-09-24]] — streaming semantics and verification controls.
- [[hermes-daily-2026-09-25]] — JSON policy and differential-oracle limitations.
- [[06-packages]] — recipe obligations and trusted bricks.
- [[moscope-v2]] — useful text-processing workload context.

## Sources

[1] https://www.erlang.org/docs/28/apps/stdlib/unicode.html — unicode — OTP 28.5.0.4 (stdlib 7.3.0.1)
[8] https://www.unicode.org/versions/Unicode17.0.0/core-spec/chapter-3 — Chapter 3 – Unicode 17.0.0
[9] https://mcfp.felk.cvut.cz/publicDatasets/pocorgtfo/contents/articles/19-06.pdf — 19:06 Selectively Exceptional UTF8; or, Carefully tossing a spanner in the works.

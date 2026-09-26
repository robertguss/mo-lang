---
title: "Hermes daily research: delayed I/O errors and JSON agreement, 2026-09-25"
created: 2026-09-25
updated: 2026-09-25
type: concept
tags: [research, runtime, security, verification]
sources: [raw/articles/otp-28-file-delayed-errors-2026-09-25.md, raw/articles/rfc-8259-json-2017-2026-09-25.md, raw/papers/crossy-json-differential-2024-2026-09-25.md]
confidence: medium
---

# Hermes daily research: delayed I/O errors and JSON agreement, 2026-09-25

## Context and exposure

Research uses main **d58f67cd9df14b6f67e63527451e41a796ce18d8**, unchanged since yesterday; starting research HEAD **77db60bc9e3056db54e5abb020dadee3a5278f54**. PR 32 remains open. The handoff names no divergent active implementation branch; the remote `moscope/real-data-v2` ref is still **eff64c56d9198ff7734c0b19d3ce59d998734903**, incorporated into main.

[[HANDOFF]] and [[roadmap]] prioritize using moscope and fixing concrete language friction. Robert's learning/usefulness purpose (`decision-log.md:2295`) and current agent-native [[01-premise]] govern the interpretation, not the preserved BEAM-superiority thesis. The parked harness and program 7 are not resumed. An Elixir/BEAM comparison is useful background, not displaced by the harness comparator and not a requirement to replace BEAM.

This is **research, not a cold audit**: exposure includes lead handoff, decisions, chapters 1 and 6, chapter 9's Files/JSON sections and previous Hermes notes. No private session data, implementation changes, experiments, acceptance runs or audit intake. Recommendations below are Hermes's, not owner decisions.

## 1. Buffered success is not a completed write or completed cleanup

The fetched **OTP 28.5.0.3 / kernel 10.6.3.3** file manual says that, with `delayed_write`, `write/2` may report success before an eventual write error is known; that error is returned by the next file operation, which is not executed.[2] In its full-disk example, `close/1` returns `enospc` and the file remains open.[2] The manual separately qualifies `sync/1` by platform and describes `open`'s `sync` flag as having platform-dependent semantics.[2] ^[raw/articles/otp-28-file-delayed-errors-2026-09-25.md]

**Hermes interpretation:** record three separate outcomes in any later authorized comparison: accepted into buffering, completed persistence operation, and resource closed. Preserve the original write failure even if cleanup also fails. The documented close behavior is an Erlang API-specific case, not a general instruction to retry arbitrary POSIX closes or uncertain writes.

Mo's declared `Fs.write`/`append` semantics already put `fsync` before `Ok` (`09-stdlib.md:172–173`); `Fs.replace` separately specifies file and directory sync (`:176`). Comparing these to a buffered BEAM acknowledgement would compare different promises. This reading establishes neither Mo's implementation compliance nor an Elixir wrapper's defaults. No runtime was installed or exercised; an OTP series documentation body is not an exact-runtime source check.

## 2. JSON agreement needs explicit policy, not just “RFC compliant”

RFC 8259 says object names **SHOULD**, not MUST, be unique; it describes last-value, error and all-pairs behavior for duplicates.[5] It permits implementation limits on numeric range/precision and nesting, and warns that unpaired UTF-16 surrogate escapes can cause unpredictable interoperability.[5] These are distinct from the requirement that generators emit grammar-conforming JSON.[5] ^[raw/articles/rfc-8259-json-2017-2026-09-25.md]

Mo has already chosen important policies: objects use `Map(String, Json)`, numbers use `Float64`, duplicate keys keep the last value in the first key's position, and depth beyond 512 is `Syntax` (`09-stdlib.md:195–237`). Do **not** reopen duplicate-key policy as if it were unspecified, or call a different parser's permitted behavior a Mo defect without checking that contract.

**Hermes recommendation:** a later authorized JSON verifier should name the expected policy for duplicates (including escaped-equivalent names), numeric boundaries, Unicode escapes and depth limits before comparing backends. Compare the parsed values as well as acceptance. An illustrative policy case is `{"role":"reader","role":"writer"}`: Mo's documented policy selects the latter value; this note did not execute it. If a future security-sensitive recipe needs duplicate rejection, enforce that requirement while original input is still available rather than expecting a decoded map to retain discarded duplicates. That is a proposed application boundary, not a change to `Json.decode` or a discovered escape.

## 3. Differential agreement is useful evidence, not a correctness oracle

Möller and colleagues' **ASIA CCS 2024** Crossy paper compares parse/serialize behavior across 22 JSON parsers in five languages, using a calibrated ensemble for normalization (putting syntactically different outputs into a comparable representation).[9] Its 24-hour, 96-instance main run produced **29,266 distinct disagreement-triggering inputs**; these are not 29,266 independent bugs or vulnerabilities.[9] The authors explicitly allow false positives and false negatives when the normalizing majority is wrong, and assume independent, non-streaming target executions.[9] ^[raw/papers/crossy-json-differential-2024-2026-09-25.md]

**Hermes recommendation:** extend yesterday's [[hermes-daily-2026-09-24|metamorphic-testing suggestion]] with three independent questions: does input conform to Mo's chosen contract, do interpreter/native values agree, and does output retain the required meaning? An external parser can help reveal disagreement but cannot vote a permitted semantic choice into correctness. Keep reviewed expected values and wrong-result controls; do not replace them with majority voting or self-generated goldens.

A useful qualification in the paper itself: its control-character discussion says parsers “should reject” raw control bytes, whereas RFC 8259 permits parsers to accept extensions while requiring generators to emit conforming grammar.[5][9]
Also, short escapes such as `\n` are legal; `\u` notation is not the only valid escaping form.[5]
Therefore separate permissive input handling, invalid generated output and application-policy violations instead of labeling every discrepancy a standards bug.[5][9] ^[raw/articles/rfc-8259-json-2017-2026-09-25.md] ^[raw/papers/crossy-json-differential-2024-2026-09-25.md]

## Coverage and limitations

- Three Exa discovery requests, **12 distinct returned URLs**. One URL was already in the local ledger as snippet-only; today's section reading upgrades it. Mirror/format variants are not independent corroboration. No date filter: this is newly read background evidence, not a claim of new releases.
- Three Exa cached bodies captured. Fully read the extracted RFC and paper; the paper's long lines were read through a separate wrapped copy. Its formulas/tables retain extraction damage and no figures were visually inspected; no visual or formula-derived claims are made. No literal truncation marker found in the stored bodies.
- OTP manual reading is section-scoped: `close`, `open`, `datasync`, `sync`, `write` and `write_file`. Full manual capture is preserved, not claimed fully read. Search title and fetched body both identify OTP 28.5.0.3; neither an exercised runtime nor a pinned source commit was checked.
- Publication dates: RFC December 2017; paper July 1–5, 2024; OTP manual publication date unstated. Retrieval/ingestion is September 25, 2026. No parser implementation inspection or reproduction, no current defect-rate claim and no experimental Mo advantage.
- Coverage spans runtime error reporting and verification, with recipe safety considered at the JSON interpretation boundary. No separate capability-mechanism search or recipe-ecosystem survey today. Other returned sources remain discovery-only.

## Validation and publication

- Native lint: **293 → 294 pages**, unchanged **29 inherited notices** (15 review, 14 size), exit 0; no new schema/link failures.
- All **199** hash-bearing raw files pass exact-byte body verification; the three staged new bodies match their retrieved extractions. Citation/evidence validation passes; nine discovery-only ledger entries are intentionally uncited.
- Six explicit allowed paths; staged scope, sensitive-pattern scan and authored whitespace checks pass. Full staged whitespace check exits **2** on **149 immutable-raw-only notices**. Source bytes are retained, not normalized.
- `log.md` has no working-tree or PR-range diff against main. Changed files: this note, index, the dated inbound Elixir comparison link, and three snapshots named in frontmatter. No owner-history or implementation edits.
- Reuse open research PR 32; never auto-merge. Scripts, citation/source ledgers and validation/publication receipts remain outside the checkout.

## Related

- [[elixir]] — runtime comparison and dated follow-ups.
- [[hermes-daily-2026-09-24]] — stream semantics and metamorphic checks.
- [[reliability-and-testing-philosophies]] — complementary verification evidence.
- [[06-packages]] — recipes and trusted bricks.
- [[moscope-v2]] — useful JSON-processing workload context.

## Sources

[2] https://www.erlang.org/docs/28/apps/kernel/file.html — file — OTP 28.5.0.3 (kernel 10.6.3.3)
[5] https://www.rfc-editor.org/rfc/rfc8259.html — Rfc8259.html
[9] https://www.mlsec.org/docs/2024b-asiaccs.pdf — Cross-Language Differential Testing of JSON Parsers

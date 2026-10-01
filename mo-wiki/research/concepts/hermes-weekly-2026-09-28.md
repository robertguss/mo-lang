---
title: "Hermes weekly research: preserve meaning and prove completion, 2026-09-28"
created: 2026-09-28
updated: 2026-09-28
type: concept
tags: [research, runtime, verification, security, tooling]
sources: [raw/articles/eef-deserialization-boundaries-2026-09-28.md, raw/articles/elixir-1-18-5-file-stream-2026-09-24.md, raw/articles/linux-man-pages-6-18-openat2-2026-09-24.md, raw/articles/otp-27-binary-retention-2026-09-23.md, raw/articles/otp-28-file-delayed-errors-2026-09-25.md, raw/articles/otp-28-re-resource-errors-2026-09-27.md, raw/articles/otp-28-unicode-streaming-2026-09-26.md, raw/articles/plug-crypto-2-1-1-decoder-2026-09-28.md, raw/articles/re2-readme-2026-09-27.md, raw/articles/rfc-8259-json-2017-2026-09-25.md, raw/articles/sqllogictest-about-2026-09-23.md, raw/articles/sqllogictest-row-count-checkin-2026-09-23.md, raw/articles/sqllogictest-row-count-forum-2026-09-23.md, raw/articles/unicode-17-chapter-3-2026-09-26.md, raw/papers/crossy-json-differential-2024-2026-09-25.md, raw/papers/davis-redos-2018-2026-09-27.md, raw/papers/donaldson-lascu-metamorphic-compilers-2016-2026-09-24.md, raw/papers/goodspeed-speers-exceptional-utf8-2026-09-26.md, raw/papers/refactorerl-secure-coding-2026-09-28.md]
confidence: medium
---

# Hermes weekly research: preserve meaning and prove completion, 2026-09-28

## Bottom line and actual coverage

**Hermes recommendation:** strengthen evidence around the useful tools already being built, rather than expand the language or restart parked projects. The common thread is preserving distinctions: a completed miss versus an interrupted search, valid text versus repaired text, accepted bytes versus durable writes, and matching implementations versus correct behavior. No comparative Mo improvement was measured.

Window: **22–28 September 2026, America/New_York**, including Monday's completed daily scan before this synthesis. **Six daily notes exist; September 22 is missing and recorded failed in the local scheduler.** No backfill or automatic retry. This is an incomplete monitoring week, not seven successful scans. The six notes cover:

- September 23: retained backing storage and golden-output provenance.
- September 24: stream semantics, path authority and metamorphic checks.
- September 25: delayed write errors and JSON interpretation.
- September 26: streaming Unicode and recovery provenance.
- September 27: search budgets and resource-safe matching.
- September 28: safe decoding and diagnostic assumptions.

The notes cite **19 distinct immutable primary snapshots, including five paper/manuscript texts**. This weekly run read all six notes and rechecked selected claim-bearing sections across those snapshots; it did not reread every manual or full paper. The short EEF guide, sqllogictest forum thread and check-in overview were read in full. Wrapped reading copies preserved long extracted paragraphs. PDF layout damage and uninspected figures remain limitations. No new discovery sweep, source-code implementation review, benchmark, acceptance run or experiment occurred. Background evidence is not release monitoring.

## Current Mo context and exposure

Fetched main is **d58f67cd9df14b6f67e63527451e41a796ce18d8**; starting research HEAD is **3d7ad143cc748289944c2b69f87234cd73497da3**. The clean branch's normal merge found main already integrated. Current `HANDOFF.md:9–36` and `plans/roadmap.md:13–30` put useful small tools and moscope friction first. Robert's learning/creation/usefulness purpose is recorded at `decisions/decision-log.md:2295`; it supplements the agent-native current [[01-premise]], not the preserved historical superiority thesis.

The latest acceptance row (`decision-log.md:2307–2308`) records moscope v2 and two runtime fixes accepted on Darwin, with Linux replay and auditor reading absent and a guard flake open. **Those are project records, not results independently verified by this research.** Step42, the harness, program 7 and Step39 remain parked (`:2315`). The handoff names no divergent active implementation branch. The named remote `moscope/real-data-v2` exists at **eff64c56d9198ff7734c0b19d3ce59d998734903**, already in main; no candidate queue was resumed.

This is **research, not an independent cold audit**. Exposure includes lead handoff/decisions, current specification chapters 1, 5, 6 and chapter 9's Files/JSON sections, earlier daily research and last week's synthesis. Manual-only audit intake is unchanged; later audits must disclose relevant exposure. Research does not resolve the operating-model/auditor-scope questions left for Robert (`decision-log.md:2317`). BEAM remains a useful runtime comparator/null hypothesis; a coding-harness comparison does not settle it, and the historical replacement mandate is not revived.

## Ranked findings by current decision impact

### 1. Verification/tooling: establish the expected answer and prove the check can fail

Sqllogictest explicitly separates completion mode, which generates expected output from a reference engine, from validation mode, which compares against saved expectations.[11] A November 2024 forum report showed omitted rows passing; the linked upstream check-in says it added verification of the correct number of rows.[13][12] These are documented historical records, not a defect reproduced here or a claim about today's checker. ^[raw/articles/sqllogictest-about-2026-09-23.md] ^[raw/articles/sqllogictest-row-count-forum-2026-09-23.md] ^[raw/articles/sqllogictest-row-count-checkin-2026-09-23.md]

**Hermes judgment:** the highest-value near-term follow-up is a bounded review of the existing moscope goldens and checker, not restoration of a large verifier. Record how expectations were established; keep blessing separate from checking; require controls for missing, extra, truncated and wrong output, plus status and stderr. This run did not inspect `acceptance/check.py` and asserts no missing control there. Interpreter/native agreement can reproduce a shared misunderstanding.

**Complement, not replacement:** metamorphic testing checks a justified relation between transformed executions. Donaldson and Lascu's MET 2016 paper provides preliminary GLSL evidence, including confirmed front-end bugs, but also permitted floating-point variation and an imperfect image-distance filter.[17] Crossy's ASIA CCS 2024 JSON method compares semantic representations, yet explicitly permits false positives and false negatives when its normalizing majority errs and assumes independent, non-streaming executions.[15] **Hermes judgment:** use relations and different implementations to challenge reviewed expectations, not to vote an intended contract into existence. ^[raw/papers/donaldson-lascu-metamorphic-compilers-2016-2026-09-24.md] ^[raw/papers/crossy-json-differential-2024-2026-09-25.md]

### 2. Runtime reliability versus BEAM: compare semantics and completion before resource totals

Elixir 1.18.5 `File.stream!` defaults to line mode with CRLF normalization, opens the file on each enumeration, and uses raw/read-ahead mode for same-node streams without an encoding.[2] OTP's binary manual exposes backing-binary size and warns that copying a slice can increase memory if another process still needs its parent.[4] **Hermes recommendation:** pin line/chunk mode, encoding, repeated enumeration and wrapper options; distinguish logical retained text, backing storage and process memory. A short excerpt alone proves neither release nor leakage. ^[raw/articles/elixir-1-18-5-file-stream-2026-09-24.md] ^[raw/articles/otp-27-binary-retention-2026-09-23.md]

OTP's delayed-write contract allows success before an eventual write error; the next operation reports the error without running, and the full-disk close example leaves the file open.[5] Its `re:run/3` contract reports exceeded match limits as `nomatch` unless `report_errors` is supplied.[6] **Hermes judgment:** buffered acceptance, persistence, closure, work exhaustion and completed negative results need distinct evidence. These are documented API behaviors, not new vulnerabilities or statements about Elixir wrapper behavior. The regex manual retains older PCRE wording despite its PCRE2 introduction, so its prose is not exact-runtime execution evidence. ^[raw/articles/otp-28-file-delayed-errors-2026-09-25.md] ^[raw/articles/otp-28-re-resource-errors-2026-09-27.md]

**Counterevidence:** BEAM offers useful diagnostics and configurable mechanisms; do not handicap its baseline. Mo's own spec already requires fsync before `Fs.write`/`append` success (`09-stdlib.md:172–176`), so comparing it with buffered acknowledgement would compare different promises. Neither documentation nor the accepted Darwin record establishes current Linux compliance, general memory safety, power-loss durability or a comparative win.

### 3. Capabilities/recipes: authority is necessary, not sufficient for preserving meaning

Linux `openat2` documents distinct confinement, symlink and mount-crossing policies, and permits dropping `RESOLVE_CACHED` on a cache-only retry—not dropping confinement.[3] The EEF guide distinguishes preventing atom creation, excluding executable terms and validating resource use of decoded values; even its non-executable Range example can request excessive later work.[1] Plug.Crypto 2.1.1 defaults to empty decoder options and requires `[:safe]` separately to prevent atom creation.[8] **Hermes judgment:** recipe signatures, filesystem authority, allowed value shapes and downstream computation are different obligations. ^[raw/articles/linux-man-pages-6-18-openat2-2026-09-24.md] ^[raw/articles/eef-deserialization-boundaries-2026-09-28.md] ^[raw/articles/plug-crypto-2-1-1-decoder-2026-09-28.md]

Mo already chooses data-only JSON, string keys, Float64 numbers, last-value duplicate handling and a depth limit (`09-stdlib.md:195–237`). RFC 8259 permits variation in duplicate handling and implementation limits.[10] **Hermes recommendation:** check Mo's chosen policy, not an arbitrary parser majority. For a future recipe needing duplicate rejection, validate before a map discards the duplicate evidence. No new JSON policy or API is proposed for automatic adoption. ^[raw/articles/rfc-8259-json-2017-2026-09-25.md]

**Strongest local concern, still not an implementation finding:** the `fold_lines` advice at `09-stdlib.md:163` suggests detecting malformed input by searching for U+FFFD. By inspection, that alone cannot distinguish a literal replacement character in valid input from one inserted during repair. OTP explicitly distinguishes incomplete from invalid input; Unicode 17 requires preserving valid successor bytes but does not mandate maximal-subpart replacement grouping.[7][14] A future check should preserve source-validity evidence and test chunk boundaries, EOF truncation and legitimate U+FFFD separately. ^[raw/articles/otp-28-unicode-streaming-2026-09-26.md] ^[raw/articles/unicode-17-chapter-3-2026-09-26.md]

## Supporting evidence and counterweights

- RE2 documents linear-input matching with syntax tradeoffs, including no backreferences or look-around.[9] Davis et al.'s 2018 study dynamically validated detector hints but did not establish attacker reachability/exploitability for every flagged use.[16] **Hermes judgment:** neither a pattern warning nor an arbitrary input cap certifies resource safety; this is not a reason to add regex to Mo now. ^[raw/articles/re2-readme-2026-09-27.md] ^[raw/papers/davis-redos-2018-2026-09-27.md]
- *Selectively Exceptional UTF8* supplies historical examples of text accepted by one stage but rejected by a logging backend, not current-version vulnerability evidence.[18] **Hermes judgment:** check bytes → decoding → parsing → matching → output as a chain, without assuming acceptance at one stage guarantees preserved meaning at the next. ^[raw/papers/goodspeed-speers-exceptional-utf8-2026-09-26.md]
- The RefactorErl manuscript treats developer-listed `safe_funs` as safe and says extensive evaluation is ongoing.[19] **Hermes judgment:** agent diagnostics should expose trusted-validator assumptions; a trusted-name annotation must not substitute for behavioral evidence. ^[raw/papers/refactorerl-secure-coding-2026-09-28.md]
- EEF explicitly recommends standard external formats instead of ETF for untrusted environments.[1] Thus ETF is not unavoidable, and this week's Plug.Crypto example is not proof that every safe BEAM application needs an extra package. No recipe drift, maintenance-cost or dependency advantage was measured. ^[raw/articles/eef-deserialization-boundaries-2026-09-28.md]

## What changed since last week's synthesis

- **Priority changed with the project, not because literature chose a winner:** last week's executor/lifecycle emphasis yields to useful text-processing tools and small regression checks. Current owner purpose and later accepted work supersede the old active-candidate queue.
- **The verifier recommendation is more concrete:** reviewed golden provenance plus omission controls, then one justified transformation relation. Keep independent intended behavior separate from backend or majority agreement.
- **The runtime model is sharper:** “streaming” does not fix encoding, storage retention or re-enumeration semantics; “success” need not mean persistence, cleanup or completed search. Pin the API/options as well as runtime version.
- **A local documentation ambiguity is now explicit:** U+FFFD presence is not corruption provenance. This is a reasoning concern to resolve, not a tested runtime defect.
- **Unchanged:** no measured Mo/BEAM winner, no new acceptance claim, no proof of smaller-model advantage, and no reason here to restart program 7, the harness or Step42.

## Ranked proposed tests — not executed or newly authorized

1. **Existing checker discrimination.** On a fixed candidate, retain a valid golden case and independently inject missing/extra/truncated/wrong output, wrong status and stderr mismatch. Demonstrate expected rejection without blessing new expectations. First check whether these controls already exist.
2. **Text semantics and provenance.** Use a tiny synthetic fixture matrix: valid U+FFFD, malformed UTF-8 before valid punctuation, multibyte splits at each boundary, incomplete EOF, escaped-equivalent duplicate JSON keys and numeric/depth boundaries. Declare expected values from Mo's current contract; compare interpreter/native separately. Add a JSON-whitespace relation only for semantic matches, explicitly excluding byte offsets and raw excerpts.
3. **Matched streaming baseline, only after correctness.** Pin Mo and Elixir/OTP revisions, wrapper options, newline/encoding policy and repeated enumeration. Measure retained output, backing storage and process memory separately; include a legitimately live parent buffer as counterevidence to copy-everything. Preserve incomplete/resource-failure outcomes. Future writable workloads should separately record buffered acknowledgement, sync and close failures; do not retry uncertain writes by analogy.

These are Hermes prioritization proposals, not acceptance gates, changes to sealed suites, implementation grants or owner decisions. No new framework is needed to begin the first two.

## Provenance and validation record

- Reused immutable snapshots only; no new raw capture. Documentation versions: Elixir 1.18.5; OTP binary 27.3.4.16; file 28.5.0.3; Unicode 28.5.0.4; regex 28.5.0.5; Plug.Crypto 2.1.1; Unicode standard 17; Linux man-pages 6.18. These are saved documentation labels, not installed comparator versions. RE2 is an unpinned cached main README. EEF and the RefactorErl manuscript are undated; ingestion dates are not publication dates.
- Baseline lint: **297 pages, 29 inherited notices**, exit 0 (15 review flags, 14 size notices). No owner-owned history or disagreements were changed.
- Final native lint: **298 pages, the same 29 inherited notices**, exit 0; no new schema/link failures or review flags. All **208** hash-bearing raw snapshots pass exact-byte body checks after the closing frontmatter delimiter. Citation/evidence verification passes for all 19 cited sources.
- The three-file weekly staged diff passes whitespace, authorized-scope and sensitive-pattern checks. Authored prose across the existing PR passes whitespace. The full PR check exits **2** on **708 inherited immutable-raw-only whitespace notices**; source bytes remain unchanged. Both PR-range and worktree `log.md` diffs are empty. Local ledgers, reading copies and validation/publication receipts remain outside the checkout.
- This weekly increment changes only this note, the index and a Related backlink in `research/concepts/reliability-and-testing-philosophies.md`. `mo-wiki/log.md` remains read-only. No implementation, specification, decision, roadmap, handoff or audit-record writes.
- Publication target: existing open research PR 32, branch `research/hermes-20260923`, base `main`; review only, never auto-merge.

## Related

- [[reliability-and-testing-philosophies]] — topic home and inbound navigation.
- [[elixir]] — runtime comparator and versioned daily follow-ups.
- [[ecosystem-strategy]] — recipe and brick boundaries.
- [[hermes-weekly-2026-09-21]] — previous partial-week synthesis.
- [[hermes-daily-2026-09-23]]
- [[hermes-daily-2026-09-24]]
- [[hermes-daily-2026-09-25]]
- [[hermes-daily-2026-09-26]]
- [[hermes-daily-2026-09-27]]
- [[hermes-daily-2026-09-28]]

## Sources

[1] https://security.erlef.org/secure_coding_and_deployment_hardening/serialisation.html — eef-deserialization-boundaries-2026-09-28
[2] https://hexdocs.pm/elixir/1.18.5/File.html — elixir-1-18-5-file-stream-2026-09-24
[3] https://man7.org/linux/man-pages/man2/openat2.2.html — linux-man-pages-6-18-openat2-2026-09-24
[4] https://www.erlang.org/docs/27/apps/stdlib/binary.html — otp-27-binary-retention-2026-09-23
[5] https://www.erlang.org/docs/28/apps/kernel/file.html — otp-28-file-delayed-errors-2026-09-25
[6] https://www.erlang.org/docs/28/apps/stdlib/re.html — otp-28-re-resource-errors-2026-09-27
[7] https://www.erlang.org/docs/28/apps/stdlib/unicode.html — otp-28-unicode-streaming-2026-09-26
[8] https://hexdocs.pm/plug_crypto/2.1.1/Plug.Crypto.html — plug-crypto-2-1-1-decoder-2026-09-28
[9] https://github.com/google/re2/blob/main/README.md — re2-readme-2026-09-27
[10] https://www.rfc-editor.org/rfc/rfc8259.html — rfc-8259-json-2017-2026-09-25
[11] https://sqlite.org/sqllogictest/doc/trunk/about.wiki — sqllogictest-about-2026-09-23
[12] https://sqlite.org/sqllogictest/info/c5ec0e8e41a8106c — sqllogictest-row-count-checkin-2026-09-23
[13] https://sqlite.org/forum/forumpost/115a6fedd9 — sqllogictest-row-count-forum-2026-09-23
[14] https://www.unicode.org/versions/Unicode17.0.0/core-spec/chapter-3 — unicode-17-chapter-3-2026-09-26
[15] https://www.mlsec.org/docs/2024b-asiaccs.pdf — crossy-json-differential-2024-2026-09-25
[16] https://davisjam.github.io/files/publications/DavisCoghlanServantLee-EcosystemREDOS-ESECFSE18.pdf — davis-redos-2018-2026-09-27
[17] https://www.doc.ic.ac.uk/~afd/homepages/papers/pdfs/2016/MET.pdf — donaldson-lascu-metamorphic-compilers-2016-2026-09-24
[18] https://mcfp.felk.cvut.cz/publicDatasets/pocorgtfo/contents/articles/19-06.pdf — goodspeed-speers-exceptional-utf8-2026-09-26
[19] http://plc.inf.elte.hu/erlang/dl/submitted_paper.pdf — refactorerl-secure-coding-2026-09-28

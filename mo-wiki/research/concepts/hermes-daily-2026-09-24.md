---
title: "Hermes daily research: stream semantics, path authority and metamorphic checks, 2026-09-24"
created: 2026-09-24
updated: 2026-09-24
type: concept
tags: [research, runtime, security, verification]
sources: [raw/articles/elixir-1-18-5-file-stream-2026-09-24.md, raw/articles/linux-man-pages-6-18-openat2-2026-09-24.md, raw/papers/donaldson-lascu-metamorphic-compilers-2016-2026-09-24.md]
confidence: medium
---

# Hermes daily research: stream semantics, path authority and metamorphic checks, 2026-09-24

## Context and exposure

Research pinned to `origin/main` **d58f67cd9df14b6f67e63527451e41a796ce18d8**; starting research HEAD **538a6724773c88c5245efe1aa6128c621bcf4cc9**. Main has not advanced since the preceding scan; PR 32 remains open and is reused. The remote `moscope/real-data-v2` remains at `eff64c56d9198ff7734c0b19d3ce59d998734903`, already incorporated into main. The current handoff names no divergent active implementation branch.

[[HANDOFF]] and [[roadmap]] prioritize useful small tools and language friction from moscope. Robert's learning/usefulness purpose (`decision-log.md:2295`) supplements the current agent-native [[01-premise]]; the older BEAM-superiority framing and parked harness are not resumed. Runtime comparison remains a source of useful controls, not a new claim that Mo must replace BEAM.

This is research with prior exposure to the lead's handoff, decisions, specification chapters 1, 5, 6 and the Files section of chapter 9, plus earlier Hermes research. It is **not a cold audit**. No audit intake, implementation inspection, private session data, experiments or acceptance runs. Recommendations below are Hermes's, not new owner decisions.

## 1. Match stream semantics before comparing resource use

Elixir **1.18.5** documents `File.stream!/3` as line-oriented by default, with CRLF normalized to LF; it can instead read fixed byte chunks.[14] Each enumeration opens the file again, and same-node streams without an encoding use `:raw` with `:read_ahead`.[14] Thus the generic description of a process per opened file is not the default path for this particular local streaming API.[14] ^[raw/articles/elixir-1-18-5-file-stream-2026-09-24.md]

**Hermes interpretation:** a future authorized Mo/Elixir streaming comparison should record line/chunk mode, encoding, newline normalization, read-ahead and whether it enumerates the stream repeatedly. These are workload semantics and wrapper defaults, not incidental tuning. Do not assume a lazy stream is a snapshot or charge the Elixir baseline for a file-server abstraction this API bypasses.

Mo's local context is `09-stdlib.md:156–163`: `Fs.fold_lines` documents line streaming and replacement of malformed UTF-8 rather than `NotText`. This is a spec reading, not an implementation check. The Elixir sections read here do not establish equivalent malformed-input behavior, an exact OTP buffering size, interruption cleanup or performance. Those remain comparison questions; no benchmark or BEAM advantage is inferred.

## 2. Capability safety: distinguish confinement from refusing every link

Linux's `openat2` manual distinguishes `RESOLVE_BENEATH` (reject resolution outside the supplied directory, including absolute paths) from `RESOLVE_IN_ROOT` (interpret paths within a per-open root).[5] `RESOLVE_NO_SYMLINKS` covers every path component, whereas `O_NOFOLLOW` covers only the final component; mount crossing has a separate `RESOLVE_NO_XDEV` policy.[5] The manual warns that indiscriminate symlink/mount refusal can break otherwise functioning applications.[5] ^[raw/articles/linux-man-pages-6-18-openat2-2026-09-24.md]

The error distinction matters: `EAGAIN` may mean the kernel could not ensure `..` stayed confined during a race, or merely that a cache-only lookup was unavailable.[5] The cache-only case permits retry without `RESOLVE_CACHED`; that is not permission to drop the confinement policy.[5] ^[raw/articles/linux-man-pages-6-18-openat2-2026-09-24.md]

**Hermes interpretation:** separate semantic policy from mechanism. Mo already specifies rejecting internal as well as escaping links for narrowed `Fs`, with an operator-root exception (`09-stdlib.md:156`). This reading is not a request to relax that rule, replace the current implementation with `openat2`, or infer a current escape. A later authorized review should ask whether retry/fallback preserves exactly the chosen authority boundary and whether Linux-specific behavior has a separately evidenced Darwin counterpart. Recipe signature/`needs` conformance in [[06-packages]] cannot by itself establish path-resolution safety.

## 3. Add relations to goldens, not more self-generated expected output

**Metamorphic testing** checks a relation between executions after a controlled transformation, rather than requiring a hand-written answer for every new input. Donaldson and Lascu's **MET 2016** short paper describes opaque-value injection: introduce values known at runtime but not to the compiler, then add dead code or identity transformations that should preserve behavior.[11] Reversing transformations helps reduce a discrepancy to a small reproducer.[11] ^[raw/papers/donaldson-lascu-metamorphic-compilers-2016-2026-09-24.md]

The study is preliminary GLSL evidence, not general proof: it used 16 shaders, and legitimate floating-point variation made exact image equality unsuitable.[11] The authors report two Intel front-end issues confirmed and fixed, while the illustrated rendering issues had different confirmation states (Intel awaiting confirmation; NVIDIA reproduced but not yet confirmed as a bug).[11] Their image-distance threshold also admitted some visually identical cases.[11] ^[raw/papers/donaldson-lascu-metamorphic-compilers-2016-2026-09-24.md]

**Hermes recommendation:** if a bounded verifier extension is later authorized, complement the existing reviewed goldens with one explicitly justified relation and a wrong-result control. For a text-search tool, a candidate is that changing irrelevant JSON whitespace should preserve extracted semantic matches, provided offsets and raw excerpts are excluded from that relation. This is a hypothesis requiring the application's actual contract, not a new acceptance rule. For compiler checks, compare original/transformed programs within each backend, then separately compare interpreter/native results; neither axis substitutes for intended behavior. No new framework, code generation or experiment was run here.

This extends [[hermes-daily-2026-09-23]]: a golden fixes an expected result; a relation can expose inconsistency without blessing another candidate-produced answer. Both can share blind spots, and malformed transformations or permitted semantic variation must not be counted as compiler defects.

## Coverage, dates and limitations

- Four Exa search requests: an exact-version Elixir query returned no results; a broader retry and the path-authority and academic queries returned **12 distinct discovery URLs**. Two followed versioned Elixir URLs bring the task citation ledger to **14 distinct URLs**. No date filter; these are newly read background sources, not release news.
- Fully read the extracted `openat2` manual, the short paper (including its middle via a wrapped reading copy), and the small `File.Stream` struct page. Read only the introduction and `stream!/3` section of the larger Elixir `File` manual; its full extraction is preserved but not claimed fully read. Three other academic hits remain discovery-only.
- Elixir search results included 1.20.4, main and 1.17.3; claims use the followed **1.18.5** body, not those versions. `openat2` is **Linux man-pages 6.18**, dated **2026-02-08**, not inspected kernel source. Paper publication is **May 2016**, not ingestion on September 24. No runtime, kernel or external compiler was exercised.
- Three immutable claim-bearing snapshots; existing URL/version/read-status ledger deduplicated. The tiny struct overview remains a local capture only. Paper extraction retains layout artifacts; no image was inspected. No new recipe implementation or recipe-ecosystem survey.

## Validation and publication

- Native lint: **292 → 293 pages**, the identical **29 inherited notices** (15 review flags, 14 size notices), exit 0; no new schema/link failures.
- All **196** hash-bearing raw files pass exact-byte body verification. The three new staged bodies match their retrieved extractions; citation/evidence verification passes, with eleven intentionally uncited discovery/background ledger entries.
- Six explicit allowed paths; staged scope and sensitive-pattern scan pass. Full staged whitespace check exits **2**, with **73 notices confined to immutable raw snapshots**. Authored prose passes; source bytes are not normalized.
- Changed files: this note, the index, a dated inbound link in `research/comparisons/elixir.md`, and the three snapshots in frontmatter. `log.md` has no diff against main, including the existing PR range.
- Reuse the open research-only PR; never auto-merge. Scripts, ledgers and validation/publication receipts remain outside the checkout. No implementation or owner-history edits.

## Related

- [[elixir]] — historical comparison and dated evidence.
- [[hermes-daily-2026-09-23]] — backing storage and trustworthy goldens.
- [[hermes-daily-2026-09-17]] — directory-relative capability interfaces versus sandboxing.
- [[reliability-and-testing-philosophies]] — complementary testing traditions.
- [[moscope-v2]] — current useful-workload context.

## Sources

[5] https://man7.org/linux/man-pages/man2/openat2.2.html — openat2(2) - Linux manual page
[11] https://www.doc.ic.ac.uk/~afd/homepages/papers/pdfs/2016/MET.pdf — Metamorphic Testing for (Graphics) Compilers
[14] https://hexdocs.pm/elixir/1.18.5/File.html — File — Elixir v1.18.5

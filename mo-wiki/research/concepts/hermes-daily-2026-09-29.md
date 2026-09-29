---
title: "Hermes daily research: file identity is not a snapshot, 2026-09-29"
created: 2026-09-29
updated: 2026-09-29
type: concept
tags: [research, runtime, security, verification, tooling]
sources: [raw/articles/otp-28-file-delayed-errors-2026-09-25.md, raw/articles/linux-man-pages-6-19-stat-2026-09-29.md, raw/papers/wei-pu-tocttou-fast-2005-2026-09-29.md]
confidence: medium
---

# Hermes daily research: file identity is not a snapshot, 2026-09-29

## Scope and current context

Today's background reading extends the streaming and path-authority work in [[hermes-daily-2026-09-24]], rather than reporting a new release or vulnerability. **Hermes recommendation:** before comparing a live-file scanner with an Elixir/BEAM counterpart, name whether its result describes bytes observed during a scan or a stable input snapshot. Separately specify how metadata checks relate to the object subsequently read. Neither property follows merely from calling the scanner read-only.

Mo context: fetched main **d58f67cd9df14b6f67e63527451e41a796ce18d8**; starting research HEAD **dbe13f6455637894cf0dc5288c624dea74cd7e54**. Clean branch; normal merge found main already integrated. `HANDOFF.md:9–36` and `plans/roadmap.md:13–30` prioritize useful small tools and moscope friction. Current [[01-premise]] remains agent-native; Robert's later learning/creation/usefulness purpose is at `decisions/decision-log.md:2295`. The latest acceptance and parked-work rows remain `:2307–2317`; this scan did not independently verify their runtime results. The handoff names no divergent active branch. Remote `moscope/real-data-v2` was verified at **eff64c56d9198ff7734c0b19d3ce59d998734903**, already included in main.

Research only, **not a cold audit**. Exposure includes lead context, specification chapters 1, 5, 6 and chapter 9's Files section, plus prior research and Monday's synthesis. Manual-only audit intake is unchanged. No implementation inspection, experiments, acceptance runs or revival of parked programs. The BEAM comparison remains a useful null hypothesis, not a replacement mandate or a settled outcome.

## 1. Runtime reliability: pin the file API, not just the language

The saved OTP **28.5.0.3 / kernel 10.6.3.3** `read_file_info/2` documentation accepts either a filename or I/O device. Its `raw` option bypasses the file server and explicitly warns of races with concurrent `write_file_info/1,2`; the option has no effect when the argument is an I/O device rather than a filename.[2] This is the September 25 immutable capture, newly read in the metadata section, not a refreshed runtime inspection.[2] ^[raw/articles/otp-28-file-delayed-errors-2026-09-25.md]

Linux man-pages **6.19** says `fstat` obtains information through a descriptor, whereas `stat` uses a path and `lstat` reports the final symlink itself. It also warns that fields in one returned `stat` structure can reflect different moments during the syscall—for example, old mode with new owner.[5] ^[raw/articles/linux-man-pages-6-19-stat-2026-09-29.md]

**Hermes interpretation:** distinguish (a) resolving a name, (b) retaining identity of an opened object, (c) observing metadata, and (d) obtaining a stable content version. The OTP module's stated atomicity boundary must not be inflated into a transaction over arbitrary external writers. Conversely, its filename and descriptor forms must not be treated as identical or as evidence that BEAM lacks useful mechanisms. This scan checked neither Elixir wrapper defaults nor an installed OTP implementation.

## 2. Capabilities and recipes: a pre-check is not a transaction

Mo's current specification already says a narrowed `Fs` walks without following links, accepts regular files for reads/writes, and acts on the descriptor resolved by each row (`09-stdlib.md:156`). Its separate `size` and `kind_of` rows take path strings (`:164–165`); `read_only` limits writes through that capability (`:169`); `replace` promises old-or-new contents for that operation while `write` stays in-place (`:172–176`). These are specification statements, not implementation findings.

**Hermes concern to resolve, not a demonstrated defect:** the instruction to inspect `kind_of` before trusting a file should not be read as a cross-call identity or content-snapshot guarantee. A successful metadata call followed by a separately resolved read needs an explicit policy if the namespace or file contents may change. Nor does the `replace` contract justify assuming that every producer uses replace rather than in-place writes. Keep authority, identity and content consistency as separate recipe obligations; do not silently add a new language requirement.

Wei and Pu's **FAST 2005** paper broadens the familiar check/use race to include use/use pairs, such as deleting and then creating a named object. Their dynamic framework examines environmental conditions and privileges beyond simply seeing a syscall pair.[9] **Hermes judgment:** this supports inspecting the relationship between operations, not declaring every path-based pair exploitable. The paper's historical protected-directory assumptions are not a modern allowlist to copy into Mo.[9] ^[raw/papers/wei-pu-tocttou-fast-2005-2026-09-29.md]

## 3. Verification/tooling: observed schedules are not race freedom

The paper explicitly limits its offline analysis to paths exercised by its workloads; it discusses both false negatives and false positives, and excludes multiprocessor and multicore scheduling from the study. The evaluation used historical Linux 2.4.20, not today's Mo host or a BEAM comparator.[9] The extracted tables interleave columns and figures were not visually checked, so no attack-rate or performance figure is adopted here.[9] ^[raw/papers/wei-pu-tocttou-fast-2005-2026-09-29.md]

**Proposed follow-up only:** if separately authorized, first document the existing scanner's intended behavior, then distinguish these synthetic cases with controlled synchronization rather than sleep-based luck:

- An unchanged file as the positive control.
- A path replaced between discovery/metadata and opening.
- An already-open file appended to or truncated during reading.
- Two files changing during a directory scan, where per-file behavior need not form one directory-wide snapshot.

Specify acceptable output, warnings/errors and completeness before running either backend. If a stable snapshot is not a product goal, document the weaker live-scan promise rather than calling it a failure. Check interpreter and native semantics separately before any resource comparison. These are Hermes proposals, not new acceptance gates or claims that existing tests lack coverage.

## Coverage, provenance and validation

- Three Exa searches returned **12 distinct URLs**, **10 new** to the local ledger. The first query used the broad literal `site.erlang.org` rather than the `site:` operator; its four returned URLs were nevertheless Erlang-hosted. Coverage was targeted background discovery, not comprehensive news or advisory monitoring.
- Two new cached bodies were retrieved and read in full as extracted text: the stat manual and FAST 2005 paper. Existing OTP documentation was reused and section-read (`read_file_info/1,2`). No duplicate raw snapshot was created. All other discovery results remain snippet-only/deferred.
- Manual publication/version context: stat manual date **2026-02-08**, man-pages **6.19**, colophon fetch **2026-09-09**. OTP is the saved **28.5.0.3** series documentation, not an exact-runtime source check. FAST publication is **2005**; September 29 is ingestion, not publication. PDF layout defects and uninspected figures remain limitations; separately wrapped reading copies did not modify evidence bytes.
- Baseline native lint: **298 pages, 29 inherited notices**, exit 0 (15 review flags, 14 size notices). Final lint: **299 pages, the same 29 notices**, exit 0; no new technical issues. All **210** hash-bearing raw snapshots pass exact-byte body checks; both new staged captures match retrieval. Citation/evidence verification passes; nine discovery-only ledger entries are intentionally uncited.
- Authored staged whitespace and sensitive-pattern checks pass. Full staged whitespace exits **2** on **112 immutable-raw-only notices**; source bytes are deliberately preserved. Both working-tree and PR-range `log.md` diffs are empty. Five explicitly staged allowed paths; scratch, citation ledger and validation receipts remain outside the checkout.
- Changes are restricted to this dated note, an Elixir comparison backlink, index navigation and the two new immutable sources. `log.md`, implementation, specifications, decisions, roadmap, handoff and audit records remain untouched. Publication target is existing review-only PR 32; no auto-merge.

## Related

- [[elixir]] — runtime comparator and dated follow-ups.
- [[hermes-daily-2026-09-24]] — streaming semantics and path confinement.
- [[hermes-weekly-2026-09-28]] — prior synthesis and outstanding evidence.
- [[reliability-and-testing-philosophies]] — diagnostic and oracle boundaries.

## Sources

[2] https://www.erlang.org/docs/28/apps/kernel/file.html — file — OTP 28.5.0.3 (kernel 10.6.3.3)
[5] https://man7.org/linux/man-pages/man2/stat.2.html — stat(2) - Linux manual page
[9] https://static.usenix.org/events/fast05/tech/full_papers/wei/wei.pdf — TOCTTOU Vulnerabilities in UNIX-Style File Systems: An Anatomical Study

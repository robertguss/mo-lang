---
title: "Hermes daily research: crash consistency and capability boundaries, 2026-09-17"
created: 2026-09-17
updated: 2026-09-17
type: concept
tags: [research, runtime, verification, security]
sources: [raw/papers/pillai-crash-consistency-osdi-2014-2026-09-17.md, raw/articles/cap-std-readme-b7acf8e-2026-09-17.md]
confidence: medium
---

# Hermes daily research: crash consistency and capability boundaries, 2026-09-17

## Context and scope

Hermes research only, based on `origin/main` at `74fd4e82a85a8742d6b3cc6ab0c2858cfec1c72a`, integrated by a normal merge into the clean research checkout. The current handoff places implementation on main. No implementation, experiments, language decisions or owner-history edits were made. Chapter 1's Elixir/BEAM null hypothesis remains the comparison baseline: reliability, native speed/memory, feedback and dependency burden, not agent time-to-green.

The current [[erosion-round]] and [[decision-log]] distinguish generation five's program-level compaction/rename count defect from runtime defects. Today's research does not diagnose that bug or explain generation four's speed regression. It supplies two boundaries for future storage-recipe and capability acceptance; the next implementation steps remain Fable's.

## 1. Process recovery and storage crash consistency need different evidence

**Crash consistency** means that the files left after an interrupted execution can be recovered to an allowed application state. Pillai et al.'s OSDI 2014 study analyzes persistence ordering and atomicity using BOB (block-write reordering) and ALICE (application traces, modeled crash states and application-specific checkers).[1] It reports 60 static crash vulnerabilities across 11 applications; a static vulnerability is associated with source code, not a count of independent product failures.[1]

The paper separates failures exposed by process crashes from those requiring partial or reordered persistence, and notes that syncing a file does not guarantee persistence of its directory entry.[1] **Hermes interpretation:** a successful kill/restart probe is valuable evidence for that failure mode, but should not be promoted to a machine-crash or power-loss guarantee. This applies equally to Mo and its Elixir/BEAM baseline; supervision alone is not the persistence protocol.

For Mo's chapter 3 statement that a durable reply follows a write and fsync, **Hermes recommends a future recipe checklist**, not a spec change today:

- State the fault model: process failure, machine failure, or storage failure; name the filesystem/platform assumptions.
- Separate the obligation to preserve acknowledged operations from the treatment of operations whose reply was never received.
- Cover the sequence `create -> compact -> rename -> reopen -> write again`, rather than checking only readable state immediately after recovery.
- Describe file-content and directory-entry persistence separately, including replacement of a live log. An atomic-looking API name is not the whole persistence contract.

These are proposed acceptance questions, not executed tests or claims of a newly discovered Mo defect. The generation-five count bug is already observable at orderly reopen, so this paper is not evidence that filesystem reordering caused it.

**Contrary evidence and limits:** ALICE is not complete, depends on user-written workloads/checkers, serializes multithreaded system calls, and does not model file attributes.[1] Its default persistence model is deliberately weak; some reported vulnerabilities do not manifest on the contemporary filesystems modeled in the paper, and some checks exceed documented application guarantees.[1] The authors explicitly say the study is unsuitable for comparing application correctness or strictly verifying it.[1] These are 2014 systems and configurations, not measurements of current APFS, current Linux filesystems, Mo or BEAM. PDF tables have extraction artifacts; no per-filesystem numerical ranking is inferred here.

## 2. Capability-shaped APIs are useful, but not whole-language confinement

The Bytecode Alliance's `cap-std` README, pinned to commit `b7acf8e8807fe3fab991884d2208b7e03d35a409`, describes opening files relative to a `Dir` and rejecting paths that escape it, including escaping symlinks.[3] It also explicitly states that `cap-std` is **not a sandbox for untrusted Rust code**, which can use `unsafe` or unsandboxed `std::fs` APIs; `open_ambient_dir` is an intentional unsandboxed entry point.[3]

**Ambient authority** is access available without receiving a specific resource handle—for example, opening a globally named file using the host process's permissions.[3] **Hermes interpretation:** this is useful contrary evidence against treating a capability parameter by itself as proof of confinement. Conversely, it is evidence that an existing language can support useful capability-oriented application design; no new syntax is required for that alone.

For chapter 6's generated recipes, the important research question is whether *all* generated-code paths to authority are mediated, including platform escape hatches, and whether narrowing remains valid during filesystem path resolution. A signature-level `needs Fs` check and a path-confinement implementation audit answer different questions. This extends [[capability-module-lineage]] without asserting that Mo presently permits an escape. The README is fully read; the implementation and its tests were not audited or executed today. Its performance descriptions are not adopted as benchmark results.

## Coverage and validation

- Three targeted Exa searches: application crash-consistency research, OTP 27 file persistence documentation, and capability filesystem APIs. No date restriction: this was decision-driven background discovery, not a claim of new publications today.
- Fully read the extracted OSDI paper, including the initially omitted middle, and the pinned complete `cap-std` README. The live repository overview was also read, but the pinned README supports the claims. OTP file documentation and other search hits remain snippet-only; no new claim about its API or runtime defaults is made.
- Deduplicated against existing research topics and the local URL/version/read-status ledger. New immutable snapshots retain the fetched source bodies and exact-byte hashes; publication and ingestion dates are distinct.
- The handoff says the evidence branches are pushed, but `git ls-remote --heads origin 'erosion5-*'` returned no refs. Generation-five source inspection is therefore unavailable remotely in this scan; this does not imply lost work. Newly fetched generation-three and generation-four refs are present. No evidence worktree was altered.

  17 Sep 2026, follow-up: the erosion2 and erosion5 branches were pushed that morning, after this scan; also, source [2] is a gap in the numbering — only [1] and [3] are cited and listed.
- Baseline native lint: 242 pages, 94 pre-existing findings (56 link findings, 21 type findings, 6 tags, 8 review flags, 3 size warnings). Several link/type findings reflect the linter's exclusion of spec artifacts and missing support for schema-approved map/synthesis types; owner-owned tooling/history is unchanged. Intentional review flags are preserved.
- After edits: 243 pages and the same 94 native-lint findings, with no new technical issue or review flag. Native lint still exits 1 on existing link/type findings. Exact-byte SHA-256 verification passed for all 172 raw snapshots carrying hashes. Citation verification with evidence passed; the uncited live overview is intentionally superseded by the pinned README.
- Staged authored-prose whitespace checks passed. The full staged check reports 130 whitespace findings, confined to the immutable paper extract; those fetched bytes are deliberately retained, not normalized. The full staged scope is six allowed research/index/raw files; the research-vs-main `mo-wiki/log.md` diff is empty. Activity is recorded here, never in that log. Publication is through research PR #2, with remote head and PR state checked after pushing.

## Related

- [[reliability-and-testing-philosophies]] — storage fault models alongside existing testing traditions.
- [[capability-module-lineage]] — authority boundaries and the existing-language counterexample.
- [[elixir]] — BEAM remains the explicit null hypothesis.
- [[hermes-daily-2026-09-16]] — previous restart-budget and error-path findings, not repeated today.

## Sources

[1] https://www.usenix.org/system/files/conference/osdi14/osdi14-paper-pillai.pdf
[3] https://raw.githubusercontent.com/bytecodealliance/cap-std/b7acf8e8807fe3fab991884d2208b7e03d35a409/README.md

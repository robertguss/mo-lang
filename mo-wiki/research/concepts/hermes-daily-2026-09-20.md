---
title: "Hermes daily research: memory limits and cleanup boundaries, 2026-09-20"
created: 2026-09-20
updated: 2026-09-20
type: concept
tags: [research, runtime, verification, security]
sources: [raw/articles/otp-27-heap-limits-2026-09-20.md, raw/articles/linux-6-12-cgroup-v2-2026-09-20.md]
confidence: medium
---

# Hermes daily research: memory limits and cleanup boundaries, 2026-09-20

## Context and decision boundary

Hermes research at `origin/main` revision `a4c660757e1b2727ba1e3321e4196283ed77b7fd`. Research PRs 14 and 16 are merged; this branch starts clean from current main. The current [[01-premise]] and owner rows in `decisions/decision-log.md:584–598` prioritize the agent-native feedback loop, not BEAM superiority. Elixir/BEAM remains a runtime comparator/null hypothesis; Pi's harness comparison does not settle it. The latest `HANDOFF.md:3–91` records a fresh implementation pause, outstanding Linux checks and no model-driven task. This scheduled research does not resume implementation.

This is **not a cold audit**: Hermes read lead context, existing research and one worker's WIP account. No audit intake, hidden-suite reading, experiments, implementation changes or acceptance runs occurred. Findings below are documentation facts and Hermes interpretations, not newly reproduced Mo defects or changed acceptance gates.

The handoff's stopped work is on branches other than main. Remote `harness/workspace-server-4a` exists at `523351ba813394ddc60e0db76f396de59e204577`, containing the named `d679f568` checkpoint. Remote `toolchain/step-42-memory` exists at `0a4dffcd460a4f47ac925c6d2fb13c7e081a14ce`. Its `toolchain/WIP.md:7–19` reports group-kill controls but explicitly says RSS monitoring still measures only the direct child and normal exit does not kill leftovers. That is a worker disclosure, **not independently verified implementation behavior**. Main's [[interpreter-step-42]] remains paused.

## 1. A BEAM process heap limit is not a whole-VM memory ceiling

OTP's `process_flag(max_heap_size, ...)` checks a word-denominated heap limit only when garbage collection is triggered.[13] Its accounting includes generational heaps, stack, applicable messages and extra collection memory; with `kill: true`, reaching the limit sends an untrappable exit and stops the collection.[13]

Off-heap shared binaries enter that sum only when `include_shared_binaries` is enabled; its documented system default is false.[13] With it enabled, each referring process counts the shared binary, potentially the entire backing binary even when referring to only a small part.[13]

**Hermes interpretation:** preserve both sides of the comparison. BEAM already has a per-process resource-failure mechanism, so do not call that a missing feature. But neither this heap metric nor a sum of per-process shared-binary counts should be silently relabeled whole-VM resident memory. Memory reclamation, per-process admission limits and host containment are different obligations. Mo's `03-semantics.md:38` describes reachability-based reclamation and address reservations; this research does not establish its behavior under exhaustion.

**Counterweight:** OTP recommends observing peak sizes with killing disabled before tuning the limit because collection peaks are difficult to predict.[13]
Hermes does not recommend copying that production-tuning procedure into an untrusted-agent execution boundary: choosing a process limit and containing the entire executor are separate policy decisions.

**Version limit:** the saved OTP 27-series body identifies **27.3.4.12 / ERTS 15.2.7.8**. No installed OTP build, Elixir wrapper default or exact historical comparison runtime was inspected. Other OTP search results identify different patch levels and are not the evidence for these claims.

## 2. Linux separates memory pressure, OOM grouping and explicit teardown

In Linux 6.12's documentation, `memory.high` throttles/reclaims but does not itself invoke the OOM killer; `memory.max` invokes cgroup-local OOM handling if usage cannot be reduced, while explicitly allowing temporary overshoot.[14] The memory controller describes its accounting as not completely water-tight.[14]

`memory.oom.group` defaults to 0.[14] Setting it treats the workload as a group for OOM killing, with an explicit exception for tasks whose `oom_score_adj` is -1000; an OOM invoked within a cgroup does not kill tasks outside it merely because an ancestor has group OOM enabled.[14]

Separately, `cgroup.kill` sends SIGKILL throughout a cgroup subtree, handles concurrent forks and is protected against migrations during killing.[14] It is unavailable on threaded cgroups, where the write fails with `EOPNOTSUPP`.[14]

**Hermes interpretation:** an RSS watchdog, a process-group kill, a cgroup memory limit and an explicit subtree teardown are not interchangeable evidence. Main's [[mo-capabilities-for-the-harness]] already places children escaping an `Exec` process group outside its promise (`:122–126`). This reading supports that existing boundary; it does not establish an escape in Mo or justify replacing its design. OS containment remains a dependency to disclose, not a language-level theorem.

## 3. Cleanup evidence needs both membership control and an observed end state

`cgroup.events` reports `populated: 0` when neither the cgroup nor its descendants contain live processes.[14] The delegation rules separately constrain who may move processes: a delegated subtree is contained only under the documented access/namespace rules.[14]

**Hermes recommendation, not a new gate:** when the already-planned Linux checks resume, report the resource boundary alongside the result: which processes/descendants are accounted, who can change membership, what triggered termination, and what independent observation established no live tasks. A successful kill request alone is not the cleanup observation. Conversely, `populated: 0` is not proof of result durability, filesystem cleanup or absence of processes moved outside the boundary before observation.

A useful report vocabulary would distinguish:

- **Memory:** metric and scope, configured limit, observed peak, limit event or unknown.
- **Termination:** direct child, process group or cgroup subtree; request versus observed completion.
- **Outcome:** application result known versus unknown; cleanup evidence does not manufacture a lost verdict.

This complements [[hermes-daily-2026-09-19]] rather than repeating its retry-contract analysis. No resource-exhaustion or kill probe was run today; no operational limits were changed.

## Coverage and validation

- Three targeted Exa searches: OTP process-memory limits, Linux cgroup containment, and academic resource-isolation work. Twelve distinct discovery URLs; two additional version-series documentation URLs fetched. No date filter: background reading tied to the current queue, not a release-news claim.
- Fully read the relevant OTP `max_heap_size` and `message_queue_data` sections; kernel delegation, populated notification, events/kill and memory-limit/event sections. **The two large manuals were not read end to end.** Complete extracted bodies are preserved, with read scope in their metadata. Discovered papers remain snippet-only/deferred; no paper findings or measurements are credited today.
- Runtime reliability and verification/reporting covered; capability containment considered at the OS boundary. No recipe-conformance deep dive or external implementation inspection. Prior Bend2 work was context only, not rerun.
- Kernel source is the `/6.12/` documentation URL, with a direct HTML read confirming the `6.12.0` heading. Its October 2015 header dates the document's origin, not today's interface revision. This is not a check of the executor machine's installed kernel/configuration. Source publication dates are not inferred from ingestion on 2026-09-20.
- Deduplicated against the existing wiki and URL/version/read-status ledger. Two immutable complete Exa text snapshots, exact body hashes, no normalization. Citation evidence is attached to the read sections, not to search snippets.
- Baseline native lint: 284 pages, 26 inherited notices (15 review flags, 11 size warnings), exit 0. After edits: 285 pages, the same 26 notices, exit 0; no new technical issues. All 186 raw snapshots with hash metadata pass exact-byte body verification; citation/evidence verification passes (12 discovery-only sources intentionally uncited).
- Full staged whitespace check exits 2 with 430 notices confined to immutable raw extractions; those bytes are preserved. Authored prose passes. Explicit five-file scope, full staged sensitive-pattern scan and empty `log.md` diff verified. Publication is research-branch/PR only; the exact remote commit and PR read-back are retained in the local validation record.
- Owner history, specifications, decisions, implementation and `mo-wiki/log.md` remain untouched. An initial convenience `execute_code` call was blocked by unattended-session policy; file-based scripts and normal tools completed discovery without weakening that policy or changing global configuration.

## Related

- [[reliability-and-testing-philosophies]] — existing runtime failure and verification evidence.
- [[elixir]] — runtime comparison, without claiming new BEAM gaps.
- [[interpreter-step-42]] — paused memory-safety and guard work, not accepted by this research.
- [[mo-capabilities-for-the-harness]] — explicitly scoped `Exec` boundary.
- [[hermes-daily-2026-09-19]] — timeout outcomes remain distinct from cleanup.

## Sources

[13] https://www.erlang.org/docs/27/apps/erts/erlang.html
[14] https://docs.kernel.org/6.12/admin-guide/cgroup-v2.html

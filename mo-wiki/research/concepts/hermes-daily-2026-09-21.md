---
title: "Hermes daily research: child-process identity and owner death, 2026-09-21"
created: 2026-09-21
updated: 2026-09-21
type: concept
tags: [research, runtime, verification, security]
sources: [raw/articles/elixir-1-18-5-port-2026-09-21.md, raw/articles/linux-man-pages-6-18-pidfd-open-2026-09-21.md, raw/articles/linux-man-pages-6-18-pidfd-send-signal-2026-09-21.md]
confidence: medium
---

# Hermes daily research: child-process identity and owner death, 2026-09-21

## Context and boundary

Hermes research based on `origin/main` revision `626d6cceeb96edb192204b878932c97ff01d6be3`. PR 17 was merged; this is a fresh research branch from clean main. The current [[01-premise]] and owner rows in `decisions/decision-log.md:1517–1522` prioritize the agent-native feedback loop, not replacing BEAM. The later lead/orb authorization in `HANDOFF.md:3–23` supersedes the premise chapter's old implementation pause, but does not expand this research lane.

The current handoff places active memory/server candidates outside accepted main (`HANDOFF.md:45–125,216–229`). It names `lead/verify-orb-baseline`; `git ls-remote --heads origin lead/verify-orb-baseline` returned no remote ref. That is an unavailable remote pointer, not evidence of data loss. This research did not inspect or run those candidates and attributes their results only to lead records. Runtime Elixir/BEAM comparison remains distinct from the planned Pi harness comparison.

This is **not a cold audit**: lead context and previous research were read. No audit intake, hidden-suite reading, implementation changes, experiments or acceptance runs occurred. Today's increment over [[hermes-daily-2026-09-20]] is stable child identity and owner-death semantics, not another memory-limit survey.

## 1. BEAM supervision does not automatically contain external OS children

Elixir 1.18.5's `Port` documentation explicitly warns that a long-running program started through a port is not automatically terminated if the VM crashes: its stdin/stdout channels close, but some programs continue running.[13] ^[raw/articles/elixir-1-18-5-port-2026-09-21.md]

The manual suggests a stdin-watching wrapper for third-party programs, while warning that this wrapper consumes stdin and prevents communicating with the wrapped software through that channel.[13] Its `spawn_executable` interface already offers an explicit executable path and a separate argument list.[13] ^[raw/articles/elixir-1-18-5-port-2026-09-21.md]

**Hermes interpretation:** keep the comparison fair in both directions. Explicit executable/argument invocation is not uniquely Mo's. Conversely, supervision inside a VM should not be credited as automatic host-process cleanup after VM death. Evaluate external-command ownership separately in each runtime/application, rather than generalizing this port warning to BEAM's supervised internal processes.

The manual's heading says “Zombie operating system processes,” but the behavior described includes programs that remain running.[13] In this note, distinguish **running leftovers** from **terminated-but-unreaped children**; a report should not collapse them into one cleanup state. ^[raw/articles/elixir-1-18-5-port-2026-09-21.md]

**Mo relevance, not a defect claim:** [[mo-capabilities-for-the-harness]] already specifies group kill at the command deadline and excludes group escape (`:122–126`). Deadline behavior is not the same failure case as abrupt death of the runtime or cleanup owner. The source above motivates a separately reported owner-death obligation; it establishes neither a new Mo failure nor superiority over Elixir. No wrapper from the documentation was executed or endorsed as a complete containment solution.

## 2. A pidfd stabilizes the target, but acquisition and waiting still matter

A Linux **pidfd** is a file descriptor referring to a task. `pidfd_send_signal` documents why this matters: a numeric PID can be reused after the intended process exits, whereas the descriptor remains a stable reference to the original process.[2] ^[raw/articles/linux-man-pages-6-18-pidfd-send-signal-2026-09-21.md]

There is an acquisition caveat. The documented `fork` followed by `pidfd_open(child_pid, 0)` guarantee depends on `SIGCHLD` not being explicitly ignored, `SA_NOCLDWAIT` not being set, and the child not being reaped elsewhere, including another thread or signal handler.[1] If those conditions do not hold, the manual directs creating the child and descriptor together with `clone` and `CLONE_PIDFD`.[1] ^[raw/articles/linux-man-pages-6-18-pidfd-open-2026-09-21.md]

Polling distinguishes termination from reaping: the documented descriptor becomes readable at exit/zombie state and reports hangup when reaped; `waitid` is available when the descriptor refers to the caller's child.[1] This is more specific than “the kill call succeeded.” ^[raw/articles/linux-man-pages-6-18-pidfd-open-2026-09-21.md]

**Counterweight:** do not reduce the current interface to “pidfds can only signal one process.” The fetched manual documents `PIDFD_SIGNAL_PROCESS_GROUP` since Linux 6.9 when the descriptor refers to a process-group leader.[2] Permission and PID-namespace restrictions still apply.[2] This group-scoped mechanism does not by itself establish containment of a descendant that escaped the group; yesterday's cgroup discussion remains a separate boundary. ^[raw/articles/linux-man-pages-6-18-pidfd-send-signal-2026-09-21.md]

**Hermes recommendation, not an implementation decision:** when existing lifecycle work is reviewed, ask evidence to identify (a) how child identity was acquired, (b) who alone owns waiting/reaping, (c) the termination target scope, and (d) the observed final state. Treat unknown ownership/cleanup as unknown rather than constructing a success result from a stale numeric PID. Current lead records already distinguish owner/helper controls; this reading supplies an OS-level rationale, not acceptance of those controls.

No pidfd substitution is proposed as an immediate requirement. Linux mechanisms do not satisfy Darwin obligations, and a stable identifier does not validate output, prove every descendant stopped, or preserve a result lost when the owner died. These are separate obligations for a future authorized check.

## Coverage, versions and validation

- Four targeted Exa searches: a version-specific Elixir query returned no results, so a broader Port query followed; Linux process-identity APIs and academic fault-injection work were also searched. Twelve distinct discovery URLs, plus the explicitly versioned Elixir URL used for retrieval. Search was not date-filtered: this is decision-driven background reading, not a claim of new releases.
- Three complete extracted documentation bodies read, including their examples; none of those examples executed. Four academic papers remain discovery/snippet-only and deferred; no paper results or measured gains are credited. No recipe-conformance deep dive, external implementation inspection or runtime probes today.
- Elixir body identifies **v1.18.5**, while broad search titles identify v1.20.4; claims use the saved 1.18.5 body. Publication date is unstated. Linux bodies identify **man-pages 6.18**, manual date **2026-02-08**, HTML rendering **2026-05-30**. Those are documentation versions/dates, not the executor's kernel version. No exact historical Elixir/OTP comparison build, Linux kernel configuration or Darwin equivalent was inspected.
- Wiki/source-ledger deduplication found prior raw references to ports and a lead note naming pidfd as future work, but no existing pidfd research treatment. Three immutable Exa text snapshots preserve the exact UTF-8 bodies, with version/read scope and body hashes. Source publication dates are not inferred from ingestion on 2026-09-21.
- Baseline native lint: **287 pages, 29 inherited notices**, exit 0: 15 review flags and 14 size notices; no schema/link failures. After edits: **288 pages, the same 29 notices**, exit 0. All **189** hash-bearing raw snapshots pass exact-byte body verification; citation/evidence verification passes (ten discovery-only URLs intentionally uncited).
- Full staged whitespace check exits 2 with **14 notices confined to immutable source extractions**; those bytes are preserved. Authored prose passes. The six-file staged scope and sensitive-pattern scan pass; `log.md` has no diff. Research-branch publication and remote/PR read-back are retained in the local validation record; no auto-merge.
- `mo-wiki/log.md`, specifications, decisions, implementation and owner-owned history remain read-only. One convenience `execute_code` call was blocked by unattended-session policy; normal tools and inspectable file-based scripts were used without changing approvals or global configuration.

## Related

- [[reliability-and-testing-philosophies]] — existing runtime/testing evidence.
- [[hermes-daily-2026-09-20]] — memory accounting, process groups and cgroup containment.
- [[elixir]] — comparison without generalizing OS-child behavior to BEAM processes.
- [[mo-capabilities-for-the-harness]] — current command authority and deadline boundary.
- [[orb-guard-wrapper]] — existing owner/cleanup work, not accepted by this research.

## Sources

[1] https://man7.org/linux/man-pages/man2/pidfd_open.2.html
[2] https://man7.org/linux/man-pages/man2/pidfd_send_signal.2.html
[13] https://hexdocs.pm/elixir/1.18.5/Port.html

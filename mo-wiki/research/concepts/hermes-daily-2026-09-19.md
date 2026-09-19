---
title: "Hermes daily research: timeout outcomes and retry contracts, 2026-09-19"
created: 2026-09-19
updated: 2026-09-19
type: concept
tags: [research, runtime, verification, tooling]
sources: [raw/articles/otp-27-gen-server-2026-09-19.md, raw/articles/aws-idempotent-apis-2026-09-19.md]
confidence: medium
---

# Hermes daily research: timeout outcomes and retry contracts, 2026-09-19

## Context and decision boundary

Hermes research at `origin/main` revision `68e50ed6a2c27d56b0c1ce6fa5452baca2112646`. Yesterday's research PR #7 is merged; today's branch starts clean from that main revision. This is not a cold audit: Hermes read the lead's handoff, roadmap and decision log. No audit intake, hidden-suite reading, implementation, experiments or acceptance runs were performed.

The current [[01-premise]] explicitly adopts the agent-native feedback loop and treats Mo as another option, not a BEAM replacement. Its older runtime-first/superiority sections are historical. The latest [[roadmap]] and [[decision-log]] authorize the lead's bounded harness implementation, superseding the pause still present in chapter 1. This does not expand Hermes's research-only authority. Elixir/BEAM remains the runtime null hypothesis/comparator, not a displaced baseline; Pi is the current practical coding-harness comparator. No old experiment or stopping rule is rescored here.

`HANDOFF.md:60–76` identifies active worker branch `harness/workspace-http-v1` at base `3023a01a744d1580ca9814e595ddf990a12e456d`, not main. A remote-head lookup returned no such ref; the worker rules prohibit worker pushes, so this is a visibility limit, not evidence of data loss. Today's claims concern published main's design and external sources, not that worker's current implementation.

## 1. BEAM already separates waiting from accepting a late response

The OTP 27 documentation says `gen_server:call/3` waits for a reply or times out, and that starting in OTP 24 process aliases prevent late replies from reaching the caller.[1]
For asynchronous calls, `receive_response/2` abandons the request on timeout so a future response is ignored (with an alias-supporting server node), while `wait_response/2` leaves it available for another wait.[1]
These response APIs also accept an absolute Erlang monotonic deadline, useful across a collection of outstanding requests.[1]

**Hermes interpretation:** reply suppression, stopping the wait, cancelling remote work, and undoing an effect are distinct obligations. Do not interpret the documented word “abandoned” as a rollback guarantee. Mo's own `03-semantics.md:54–65` already says timeout stops waiting, the action may have happened, and an `ask` reply is dropped; this research supports that existing distinction rather than proposing new semantics.

**Counterweight:** OTP also warns that blocking distribution signaling can significantly delay call timeouts.[1]
This prevents treating the timeout parameter as an unconditional end-to-end wall bound. No runtime latency was measured today, and no claim about Mo outperforming BEAM follows.

**Version limit:** the fetched body identifies OTP **27.3.4.12 / stdlib 6.2.2.3**, while Exa's search title identified 27.3.4.14. The saved body, not the search title, governs this note. This is a version-series documentation snapshot, not inspected OTP implementation code or verification of the exact runtime in any Mo comparison. Elixir wrapper behavior was not separately checked.

## 2. Duplicate refusal is not the same contract as safe replay

An idempotent operation permits retransmission without additional side effects; AWS's engineering account favors a caller-provided request ID over inferring duplicate intent from identical parameters.[5]
It describes recording the token and mutations atomically, returning semantically equivalent responses to repeated requests, rejecting the same ID with changed parameters, and retaining deduplication knowledge for a service-specific lifetime.[5]
Its EC2 example retains that knowledge for the resource lifetime plus an additional interval for late requests; it does not prescribe a universal duration.[5]

**Hermes interpretation for the current bridge:** [[mo-workspace-http-v1]] deliberately chooses a narrower contract: repeated/conflicting call IDs are refused, no cached-result replay or resume, intent precedes effects, cleanup ownership outlives the HTTP request, and atomic replacement carries no fsync/crash-durability claim (`:53–68`). That must not be described as AWS-style retry-safe result recovery or an exactly-once execution guarantee. Successful cleanup does not establish the original command result; the existing response contract already preserves `unknown` after possible effects (`:109–115`).

**Counterweight:** AWS explicitly acknowledges implementation cost and that its stronger contract is not right for every solution.[5]
Hermes does **not** recommend adding automatic retries, durable deduplication or result replay to this bounded slice. A future retry policy would need an explicit design decision covering identity, changed payloads, retention, crash boundaries and response meaning. This source is engineering guidance, not a comparative benchmark or proof of Mo's implementation.

## Suggested evidence framing, not new acceptance gates

The current brief already includes lost responses, duplicates, owner death and cleanup proof. Hermes recommends preserving separate observations in its existing evidence rather than inflating a single success count:

- **Admission:** rejected before effects, or admitted with a bound identity?
- **Execution:** not started, completed, or unknown? Was this independently observed?
- **Reply:** produced locally versus received by the client?
- **Cleanup:** independently proved absent versus unresolved?

A lost reply followed by successful cleanup can truthfully be “execution unknown; cleanup proved.” A deadline plus a clean mailbox does not by itself establish cancelled work. These are interpretations for reporting, not newly found defects. No test was run or threshold changed.

## Coverage and validation

- Two targeted Exa searches, covering OTP timeout/late-reply semantics and AWS retry identity. Complete extracted OTP manual and AWS article read; AWS example layout artifacts retained. Other results remain snippet-only. No date filter: background evidence relevant to today's work, not a claim of new releases or comprehensive monitoring.
- Runtime reliability and verification/outcome reporting covered. No new capability/recipe paper or implementation was deeply read today; the bridge's authority boundary was read as project context only. Prior days supplied academic-paper coverage; no new paper is claimed today.
- Deduplicated against existing research pages and the local URL/version/read-status ledger. Two immutable Exa text snapshots retain exact body hashes; source publication dates are unstated, separate from today's ingestion.
- Initial convenience execution was blocked; the file-based discovery script then encountered missing `python-dotenv`. Running it with an isolated `uv --with python-dotenv` environment succeeded. No provider outage, credential disclosure or global configuration change.
- Native lint baseline: 267 pages, 25 inherited notices (15 review flags, 10 size warnings), exit 0. After edits: 268 pages, the same 25 notices, exit 0; no new technical issues. The index's stale total was corrected to the actual page count.
- All 180 raw snapshots with hash metadata pass exact-byte body verification after the closing frontmatter delimiter. Citation/evidence verification passed; six discovery-only sources are intentionally uncited.
- Full staged whitespace check exits 2 with 110 trailing-whitespace notices, all in the two immutable source extractions. Those bytes remain unchanged; staged authored prose passes. The five-file scope and sensitive-pattern checks passed; public AWS example request IDs are source examples, not credentials.
- Owner history, spec, decisions and `mo-wiki/log.md` remain read-only; the log diff is empty. Publication uses the research branch only, with remote commit and open-PR read-back required before finishing the lease; the final publication handle is retained in the local validation record.

## Related

- [[reliability-and-testing-philosophies]] — existing runtime and verification evidence.
- [[elixir]] — preserve the runtime comparison rather than inventing a BEAM gap.
- [[mo-workspace-http-v1]] — published bounded contract, not worker implementation acceptance.
- [[hermes-daily-2026-09-18]] — earlier TLS-state research, not repeated today.

## Sources

[1] https://www.erlang.org/docs/27/apps/stdlib/gen_server.html
[5] https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs

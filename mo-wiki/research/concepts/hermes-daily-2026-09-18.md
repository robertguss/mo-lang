---
title: "Hermes daily research: TLS state coverage and EOF semantics, 2026-09-18"
created: 2026-09-18
updated: 2026-09-18
type: concept
tags: [research, runtime, verification, security]
sources: [raw/papers/maehren-tls-state-learning-usenix-2025-2026-09-18.md, raw/articles/openssl-3-0-ssl-get-error-2026-09-18.md]
confidence: medium
---

# Hermes daily research: TLS state coverage and EOF semantics, 2026-09-18

## Context and scope

Hermes research, based on `origin/main` at `3951b62d363458f67ef7dda724dfa746e0c579d6` (18 Sep 2026, 4:44 AM ET). PR #2 is merged; this note starts a fresh research branch from that main revision. The original checkout is clean on main. The handoff's 17 Sep pause is older than the current roadmap and decision log: step 37 and its handshake-reset fix are recorded as accepted, program 7's spec is sealed, and generation six has started. No implementation branch mismatch was found. The formerly missing `erosion5-*` refs are now verified remotely; no evidence worktree was altered.

Chapter 1's ordering remains runtime reliability, capabilities/recipes, then language surface, measured with native speed/memory, feedback and dependency burden. Elixir/BEAM remains the explicit null hypothesis. This scan supports the existing TLS verification work; it neither accepts a brick nor revises program 7's sealed spec, hidden suites, stopping rules or language decisions. No experiments, public-host probes, builds, or audit-role actions were performed.

## 1. Protocol-state coverage is different from a no-crash count

**State-machine learning** means sending sequences of protocol messages, observing responses, and inferring a model of which transitions an implementation permits.[1]
Maehren et al.'s USENIX Security 2025 paper combines valid handshake paths, randomized sequences and checks of inferred anomalies against the actual server; its inputs include TLS alerts, connection resets and KeyUpdate, not just malformed byte strings.[1]

The study targeted 7,337 bug-bounty domains and reports 1,304 analyzed models: 1,285 domains whose learning completed plus 19 incomplete runs that reached the required vulnerability alphabet.[1]
These are domain results, not 1,304 distinct library implementations, and the evaluated domains corresponded to 835 IP addresses.[1]
Its TLS 1.3 observations include 89 servers ignoring post-handshake ChangeCipherSpec messages and one server terminating the connection on KeyUpdate.[1]
These are the paper's historical observations, not a scan conducted today and not findings about Mo or Erlang/OTP.

**Hermes interpretation:** this supports keeping two evidence columns separate: parser/memory robustness and permitted protocol transitions. A large no-crash input count does not by itself establish that authentication cannot be bypassed or that an invalid message cannot return to a successful handshake. The paper's concrete transcript-integrity and CBC findings concern older protocol paths; they must not be presented as vulnerabilities in Mo's TLS-1.3-only cut.

The existing [[decision-log]] already requires resets and alerts at every handshake state, in both runtimes, with the next connection still accepted after Mo's now-fixed native handshake double free. This research adds methodological support, not a newly discovered defect or a replacement test mandate. **Hermes recommends**, for a separately authorized future coverage review:

- Name the supported input alphabet and the protocol state reached before each fault; do not silently count unsupported TLS 1.2, resumption or client-authentication paths as covered.
- Distinguish the brick engine from its interpreter/native socket integration. Protocol traces, engine ownership/cleanup and subsequent connection recovery answer different questions.
- Keep observed output and expected output separate: refusal, connection closure, continued application traffic and listener survival are not interchangeable verdicts.
- Apply the same supported-feature matrix to the pinned Elixir/OTP baseline; this paper supplies no comparative BEAM result.

**Counterweight and limitations:** the authors find many deviations non-critical, and common implementations mostly protocol-conforming.[1]
Learning failed to converge for most TLS-capable targets; nondeterminism and time limits substantially restrict the sample.[1]
The authors disclose two harness bugs: a TLS 1.3 HelloRetryRequest client-random mistake affecting 87 domains and a mapper issue creating redundant nodes in 43 models.[1]
Inferred models are hypotheses, not proofs; extra states and unusual alerts alone do not establish exploitable flaws.[1]
The paper therefore supports harness validation as much as wider testing. Its artifact implementation was not audited or run here, and damaged PDF table layouts are not used for new calculations.

## 2. Clean TLS shutdown and transport EOF need explicit labels

OpenSSL's **3.0-series** `SSL_get_error` documentation distinguishes `close_notify` (the TLS peer's authenticated closure alert) from unexpected transport EOF: the former ordinarily yields `SSL_ERROR_ZERO_RETURN`, whereas unexpected EOF yields `SSL_ERROR_SSL` with `SSL_R_UNEXPECTED_EOF_WHILE_READING`.[2]
It also documents that `SSL_OP_IGNORE_UNEXPECTED_EOF` can cause the latter to appear as `SSL_ERROR_ZERO_RETURN`.[2]
This is a live version-series documentation snapshot, not an audit of the exact OpenSSL 3.0.13 binary used in Mo's differential run, nor a statement about Erlang's SSL API.

Mo's chapter 9 currently treats a stream ending without `close_notify` as end-of-stream. The already-sealed [[07-redis-subset]] requires discarding an incomplete incoming command rather than executing any of it. **Hermes interpretation:** those are explicit project choices, not newly open design questions. When comparing outcomes, record the oracle's version/options and distinguish clean TLS closure, abrupt EOF, a complete application message and a partial one; otherwise an option-dependent library result can be mistaken for equivalent protocol evidence. A rule for discarding a partial incoming command does not by itself specify how a different client protocol validates completeness of an outgoing reply. No spec change or failure of the current Redis cut is asserted.

## Coverage and validation

- Three successful targeted Exa searches: TLS state-fuzzing foundations, OTP 27 SSL closure documentation, and TLS 1.3 state-machine verification research. Searches were not date-restricted; this is decision-driven background reading, not comprehensive daily release monitoring.
- Read the complete extracted 2025 paper, including the omitted middle/conclusion, and the complete OpenSSL 3.0 manual entry. Other search results, including OTP documentation and newer formal-verification papers, remain snippet-only. Capabilities/recipes were contextualized through the native-brick boundary; no new capability source was deeply read today.
- Sources deduplicated against the wiki and the local URL/version/read-status ledger. Immutable snapshots preserve the extracted bodies, with publication/version context separate from ingestion. Paper tables contain extraction artifacts.
- Baseline native lint: 250 pages, 21 findings (15 existing contested/low-confidence review flags and 6 existing size warnings), exit 0. Upstream fixed yesterday's technical lint issues; Hermes did not edit owner history or tooling.
- After edits: 251 pages and the same 21 native-lint findings, exit 0; no new technical issues or review flags. All 174 raw snapshots carrying SHA-256 metadata pass exact-byte body verification after the closing frontmatter delimiter. Citation/evidence verification passed.
- Full staged whitespace check reports 63 findings, all confined to the immutable paper extraction; fetched bytes are retained rather than normalized. Staged authored prose passes. The five-file staged scope contains only allowed research/index/raw paths; credential/private-path pattern checks found nothing. The research diff for `mo-wiki/log.md` is empty; it remains strictly read-only.
- Publication is through the fresh research branch, never main, with remote-head and open-PR read-back required before the run is marked complete. The final PR handle and publication result are retained in the local validation record.

## Related

- [[reliability-and-testing-philosophies]] — harness diversity and stateful verification.
- [[elixir]] — the runtime null hypothesis, not displaced by TLS research.
- [[bricks-and-the-cost-of-zero-dependencies]] — native-code assurance remains a separate obligation.
- [[hermes-daily-2026-09-17]] — earlier storage and authority boundaries, not repeated here.

## Sources

[1] https://www.usenix.org/system/files/usenixsecurity25-maehren.pdf — Towards Internet-Based State Learning of TLS State Machines
[2] https://docs.openssl.org/3.0/man3/SSL_get_error — OpenSSL 3.0 SSL_get_error

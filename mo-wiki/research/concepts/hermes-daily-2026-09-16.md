---
title: "Hermes daily research: restart budgets and error-path coverage, 2026-09-16"
created: 2026-09-16
updated: 2026-09-16
type: concept
tags: [research, runtime, processes, verification]
sources: [raw/articles/elixir-1-18-5-supervisor-2026-09-16.md, raw/articles/otp-27-supervision-principles-2026-09-16.md, raw/papers/yuan-error-handling-osdi-2014-2026-09-16.md, raw/articles/mo-control10-elixir-server-2026-09-16.md]
confidence: medium
---

# Hermes daily research: restart budgets and error-path coverage, 2026-09-16

## Scope and current decision

Hermes research only; no experiments or language decisions. Repository context is `origin/main` at `44ba830e580427dd98ad505f35c263b049273a45`, normally merged into the research branch. Read the current handoff, roadmap, decision log, chapter 1, chapter 3 and chapter 10 §§1–5. The current handoff says implementation is on main, not the older `session-05`; that remote still exists at `a8b38bbe55f46a6ddeeda2507aa75fd8e84d2264` and was not used as the design authority.

The roadmap places the live questions after step 31: P6 on Mo's changed queue, the erosion round, restart-budget diagnostics and scheduler placement. Preserve chapter 1's BEAM null hypothesis and reliability-at-zero-dependencies test. Research below qualifies the restart-budget interpretation and proposes coverage questions; it does not re-grade Fable's results.

## 1. A precise correction: Elixir defaults are not Erlang defaults

Elixir **1.18.5** `Supervisor` defaults to `max_restarts: 3`, `max_seconds: 5`.[1] The OTP **27** supervision guide instead specifies defaults of `intensity: 1`, `period: 5` when those Erlang map keys are omitted.[2] Thus the repository's phrase “OTP's default of 3 in 5 s” should be read as **Elixir Supervisor's default**, not a universal BEAM setting. This is a documentation distinction, not a dispute with the observed fourth-kill result. ^[raw/articles/elixir-1-18-5-supervisor-2026-09-16.md] ^[raw/articles/otp-27-supervision-principles-2026-09-16.md]

Read-only inspection of the entire `Jobq.Server` at `control10-elixir` commit `89ed4c90aa65a4b3e31c8e7737c6077e0d5721bc` confirms `Supervisor.init(children, strategy: :rest_for_one)` with no restart-budget override in that module.[4] Combined with the versioned Elixir docs, this supports the default attribution for that source revision; it is not a reconstruction of the Mac process's actual runtime configuration.[1][4] ^[raw/articles/mo-control10-elixir-server-2026-09-16.md]

## 2. Restart intensity is a containment policy, not a recovery guarantee

**Restart intensity** means a permitted number of restarts in a time window. OTP documents escalation after that budget is exceeded, warns that budgets multiply across supervision levels, and distinguishes tolerating a short burst from tolerating sustained failure.[2] It also states that child starts and shutdowns are synchronous operations in the supervisor, which remains blocked during them.[2] ^[raw/articles/otp-27-supervision-principles-2026-09-16.md]

**Hermes interpretation:** the documented budget is a deliberate bound on repeated failure, not itself a defect. Fable's persistent-full-disk result in [[erosion-round]] must remain distinct from recovery after an isolated kill in [[control-run-10]]. A budget diagnostic makes policy visible; it cannot by itself make a replay succeed while the disk remains full. Increasing a budget without measuring recovery work could merely prolong repeated failure. No claim here that either runtime solves that problem better.

**Suggested questions for the authorized implementation lane, not tests run today:** Does health return a bounded unavailable response during failed replay? Are acknowledged writes preserved across failure, restart and reopening? What happens after storage becomes writable again? Does the service recover without a retry storm? Record restart topology, explicit budgets and failure duration alongside recovery latency; do not compare only the number of kills.

## 3. Verification track: consuming an error is not handling it correctly

Yuan et al.'s **OSDI 2014** study analyzed 198 sampled user-reported failures in five Java/C data-intensive systems, including 48 catastrophic failures; the authors manually reproduced 73 failures.[3] They report incorrect handling of explicitly signaled non-fatal errors in 92% of the catastrophic subset, and that 58% involved trivial mistakes or error-handling code whose defects statement-coverage testing could expose.[3] These are retrospective findings about that selected sample, not Mo measurements or a current universal failure rate. ^[raw/papers/yuan-error-handling-osdi-2014-2026-09-16.md]

The important counterpoint to a consumed-result law is that the authors say errors were checked in all but one relevant case, yet handling could still be wrong.[3] They recommend starting from error-handling blocks and constructing inputs that reach them, rather than relying only on generic workloads and random fault injection.[3] **Hermes recommendation:** use error-path reachability as a coverage question for future recipe acceptance—especially append failure, replay failure and reply-after-failure—not as an argument for a new syntax rule. ^[raw/papers/yuan-error-handling-osdi-2014-2026-09-16.md]

**Contrary evidence and limits:** the paper's Aspirator checker reported 19% false positives, and its bad-practice category includes cases whose consequences the authors could not determine.[3] The sample favors severe, developer-confirmed issue-tracker reports in mature data-intensive systems; the authors explicitly caution against generalizing to other system classes.[3] Neither the percentages nor the Java checker establish that Mo's diagnostics or contracts prevent these failures. ^[raw/papers/yuan-error-handling-osdi-2014-2026-09-16.md]

## Coverage, provenance and validation

- Four targeted Exa searches: two supervision/recovery queries, one failure-analysis paper query, one capability/recipe supply-chain query. Discovery was not date-restricted; this is decision-driven background reading, not a claim of new releases today.
- Fully read two versioned official documentation pages, the extracted OSDI paper including its initially omitted middle, and one complete repository source file. The OTP 27 URL currently serves documentation labeled 27.3.4.16; this is not a claim that the experiment ran that patch release. PDF text retains extraction/layout artifacts.
- Capability/recipe search produced adjacent provenance and generated-code-security candidates only. Those remain search-snippet-only, queued in the local URL/version/read-status ledger; no claim from them is promoted here. No social-media sweep or new capability implementation audit.
- Deduplicated against existing wiki URLs and topics. Reused [[elixir]] and linked this note from that comparison; retained its historical observations rather than rewriting them as current facts.
- `origin/control10-elixir` is present. A remote-head query for `erosion2-*` returned none; this scan could not inspect those Mac worktree revisions remotely. This is a coverage limit, not evidence of lost work.
- Before edits: native lint checked 230 pages and reported 29 existing issues: 6 broken links, 13 historical page types, 1 unknown tag, 8 intentional review flags and 1 size warning. No owner-history repair attempted.
- After edits: 231 pages, the same 29 lint findings (native lint exits 1 for pre-existing link/type errors); zero new findings. Exact-byte SHA-256 verification passed for all 170 raw snapshots carrying hashes. Citation verification with evidence passed. The authored-prose staged whitespace check passed; the full staged check reports 95 source whitespace findings (trailing spaces/EOF blank line), confined to immutable raw extracts and deliberately retained to preserve exact evidence bytes. Research-vs-main `log.md` diff is empty. No implementation, decision, spec, roadmap or handoff edits. Publication uses the existing open research PR #2; remote state is verified after pushing.

## Related

- [[elixir]] — existing comparison and historical supervision questions.
- [[empirical-validation-plan]] — validation context; early time-to-green premises are historical.
- [[control-run-10]] — Fable's Elixir comparison and P6 observation.
- [[erosion-round]] — persistent storage-failure context.

## Sources

[1] https://hexdocs.pm/elixir/1.18.5/Supervisor.html
[2] https://www.erlang.org/docs/27/system/sup_princ.html
[3] https://www.usenix.org/system/files/conference/osdi14/osdi14-paper-yuan.pdf
[4] https://github.com/robertguss/mo-lang/blob/89ed4c90aa65a4b3e31c8e7737c6077e0d5721bc/experiments/control-run/elixir/jobq/lib/jobq/server.ex

---
title: "Hermes weekly research: separate the guarantees, 2026-09-21"
created: 2026-09-21
updated: 2026-09-21
type: concept
tags: [research, runtime, verification, security, agents]
sources: [raw/articles/aws-idempotent-apis-2026-09-19.md, raw/articles/cap-std-readme-b7acf8e-2026-09-17.md, raw/articles/elixir-1-18-5-port-2026-09-21.md, raw/articles/elixir-1-18-5-supervisor-2026-09-16.md, raw/articles/linux-6-12-cgroup-v2-2026-09-20.md, raw/articles/linux-man-pages-6-18-pidfd-open-2026-09-21.md, raw/articles/linux-man-pages-6-18-pidfd-send-signal-2026-09-21.md, raw/articles/mo-control10-elixir-server-2026-09-16.md, raw/articles/openssl-3-0-ssl-get-error-2026-09-18.md, raw/articles/otp-27-gen-server-2026-09-19.md, raw/articles/otp-27-heap-limits-2026-09-20.md, raw/articles/otp-27-supervision-principles-2026-09-16.md, raw/papers/maehren-tls-state-learning-usenix-2025-2026-09-18.md, raw/papers/pillai-crash-consistency-osdi-2014-2026-09-17.md, raw/papers/yuan-error-handling-osdi-2014-2026-09-16.md]
confidence: medium
---

# Hermes weekly research: separate the guarantees, 2026-09-21

## Bottom line and coverage

**Hermes judgment:** prioritize trustworthy outcome and cleanup evidence over broader language claims. The week's strongest contribution is separating guarantees that a single green count can hide: waiting, execution, reply delivery, process cleanup, authority confinement and durable storage. No comparative Mo improvement was measured by this synthesis.

Window: **15–21 September 2026, America/New_York**, including Monday's completed 06:00 research before this 08:00 synthesis. Six daily notes exist and were read; **15 September is missing**, with the local scheduler recording that run failed. This is a partial first monitoring week, not seven successful daily scans. No missing day was backfilled. If using the previous Monday–Sunday window instead, 14 and 15 September have no daily note; today's note is then a supplement.

- 16 September: restart-budget defaults and error-handling coverage.
- 17 September: crash consistency and capability boundaries.
- 18 September: TLS state coverage and versioned EOF semantics.
- 19 September: timeout outcomes and retry contracts.
- 20 September: heap limits, cgroups and cleanup observations.
- 21 September: external-child owner death, stable identity and reaping.

The six notes cite **15 distinct preserved primary-source snapshots**, including three academic papers. This run rechecked claim-bearing sections and limitations in those snapshots, not every page of the large manuals or every paper reference. The full cap-std README, saved Elixir server module and short OpenSSL entry were read. No new discovery sweep, external implementation audit, runtime experiment, benchmark or acceptance test was performed. The separately authorized Bend2 deep dive is not an additional daily scan and was not rerun or independently revalidated here.

## Current Mo decision context, not an audit verdict

Design context is fetched `origin/main` **608f46d27f3fbceb3a0026cd4d2371196585ff94**, integrated into the clean research branch by non-rewriting merge **6611294f7b44bab66049ba9d0f0e60a6d7368926**. The current premise (`spec/design-v0/01-premise.md:3–52`) and Robert's owner rows (`decisions/decision-log.md:1517–1522`) put the complete agent-native loop first. The runtime-first/superiority framing in the early daily notes is historical, not today's goal. Elixir/BEAM remains the runtime null hypothesis/comparator; Pi is the practical coding-harness comparator, not evidence that the runtime question is settled.

Later lead authority (`HANDOFF.md:3–23`) supersedes the premise's old implementation pause **for the lead**, not this research lane. The roadmap's current checkpoint (`plans/roadmap.md:24–41`) records accepted Linux baseline/guard work, while memory and server candidates remain outside accepted main. Latest decision rows (`decision-log.md:2188–2204`) record full-normal 309/309 on a candidate and a narrowly released fiber-ASan attempt, not Step42 acceptance or a completed sanitizer result. These are **lead-recorded results, not runs verified by Hermes**.

The active implementation trees differ from main. Remote queries returned no refs for `lead/verify-orb-baseline`, `harness/workspace-server-chunks`, or `toolchain/step42-safety-evidence`; the latter two occur in historical Mac pointers, not proof of current orb branch names. No private candidate tree or transferred bundle was inspected. Missing remote pointers do not imply lost work, and no historical queue was resumed.

This is research exposed to lead decisions, handoffs and prior research, **not an independent cold audit**. Manual-only audit intake remains unchanged. Any later audit on these subjects must disclose that exposure.

## Ranked findings

### 1. Runtime reliability versus BEAM: compare the same failure boundary

**Highest immediate impact: the executor and cleanup work.** OTP already suppresses late `gen_server:call` replies using aliases from OTP 24; `receive_response` abandons a timed-out response, whereas `wait_response` permits another wait.[10] Elixir 1.18.5 nevertheless warns that a VM crash does not automatically terminate every external program started through a port.[3] These concern different objects: an internal BEAM request and an external OS process. Neither fact establishes Mo superiority. ^[raw/articles/otp-27-gen-server-2026-09-19.md] ^[raw/articles/elixir-1-18-5-port-2026-09-21.md]

Memory limits also need their scope named. OTP's heap check runs at garbage collection, and shared off-heap binaries are included only under the relevant option, whose system default is false.[11] Linux 6.12 distinguishes `memory.high` throttling from `memory.max` OOM handling and permits temporary overshoot of the latter.[5] **Hermes interpretation:** per-process heap accounting, sampled direct-child RSS and whole-executor containment are not interchangeable measurements. ^[raw/articles/otp-27-heap-limits-2026-09-20.md] ^[raw/articles/linux-6-12-cgroup-v2-2026-09-20.md]

A Linux pidfd is a stable process reference, avoiding recycled numeric-PID targeting; acquiring it after `fork` still depends on signal/reaping conditions.[7][6] `cgroup.kill` targets a subtree, while `cgroup.events` separately reports whether live processes remain; delegation rules determine who can move members.[5] **Hermes interpretation:** stable identity, termination request, completed termination and reaping require separate evidence. A pidfd does not by itself contain escaped descendants; an empty cgroup does not recover a lost application result. ^[raw/articles/linux-man-pages-6-18-pidfd-send-signal-2026-09-21.md] ^[raw/articles/linux-man-pages-6-18-pidfd-open-2026-09-21.md] ^[raw/articles/linux-6-12-cgroup-v2-2026-09-20.md]

**Correction carried forward:** “3 restarts in 5 seconds” is Elixir 1.18.5 Supervisor's default, not a universal Erlang/OTP default: OTP's omitted `intensity`/`period` keys default to 1/5.[4][12] The saved control-run server at `89ed4c90aa65a4b3e31c8e7737c6077e0d5721bc` specifies `:rest_for_one` without a budget override in that module.[8] This supports source attribution, not reconstruction of the experiment's running configuration. Escalation after exhausting a configured budget is a policy, not itself a reliability defect.[12] ^[raw/articles/elixir-1-18-5-supervisor-2026-09-16.md] ^[raw/articles/otp-27-supervision-principles-2026-09-16.md] ^[raw/articles/mo-control10-elixir-server-2026-09-16.md]

**Counterevidence to overclaiming:** BEAM has useful existing mechanisms; the Port warning does not invalidate internal supervision. Conversely, the wrapper it suggests consumes stdin and is not a general containment proof.[3] Linux-only documentation supplies no Darwin proof. Current accepted guard records explicitly retain direct-child RSS and group-escape limitations (`decision-log.md:2023`). ^[raw/articles/elixir-1-18-5-port-2026-09-21.md]

### 2. Verification/tooling: prove that the intended check actually ran

Yuan et al.'s OSDI 2014 study reports incorrect handling of explicitly signaled non-fatal errors in 92% of its catastrophic subset, while errors were checked in all but one relevant case.[15] **Hermes interpretation:** consuming a Result or compiling an error branch cannot establish correct recovery. The useful transfer is targeted error-path reachability, not importing that percentage as Mo's expected failure rate. The study selected mature data-intensive systems and severe issue-tracker failures; its checker reported 19% false positives.[15] ^[raw/papers/yuan-error-handling-osdi-2014-2026-09-16.md]

Maehren et al.'s USENIX Security 2025 work learns TLS message-sequence models and checks hypotheses against actual behavior, rather than equating “did not crash” with protocol correctness.[13] It also reports limited convergence and bugs in its own TLS-Attacker/mapper harness; common implementations were mostly protocol-conforming.[13] **Hermes interpretation:** validate the verifier with discriminating controls before trusting a large success count. This is methodological evidence, not a Mo TLS vulnerability finding. ^[raw/papers/maehren-tls-state-learning-usenix-2025-2026-09-18.md]

Versioned oracle behavior matters: OpenSSL 3.0's manual distinguishes unexpected EOF from `close_notify`, but an option can map unexpected EOF to `SSL_ERROR_ZERO_RETURN`.[9] Pin options as well as versions and keep parser robustness, protocol-state validity and socket cleanup separate. No exact OpenSSL binary or OTP TLS implementation was inspected this week. ^[raw/articles/openssl-3-0-ssl-get-error-2026-09-18.md]

**Current relevance:** `HANDOFF.md:263–268` records a real-filter compilation failure after helper greens; `decision-log.md:2108` explicitly limits an ASan-named fake compiler test to policy evidence. Later full-normal results do not erase those narrower lessons or establish raw-ASan coverage. Preserve tested/proven/not-run distinctions already present in `05-verification.md:3–27`; do not add a language law based on this research.

### 3. Capabilities/recipes: declaration, confinement and recovery are separate contracts

The pinned cap-std README shows useful directory-relative authority in an existing language, including escape-path refusal, while explicitly stating it is not a sandbox for untrusted Rust code using `unsafe` or ordinary filesystem APIs.[2] **Hermes interpretation:** capability-shaped interfaces are not uniquely Mo's; Mo's stronger claim needs evidence that every relevant authority path is mediated. Recipe signature conformance and filesystem-resolution safety answer different questions. No recipe regeneration/drift measurement was added this week. ^[raw/articles/cap-std-readme-b7acf8e-2026-09-17.md]

AWS's engineering account distinguishes a no-additional-side-effects retry from a semantically equivalent replayed response, and requires atomicity between recording the request token and its mutations for its stronger design.[1] **Hermes interpretation:** duplicate refusal should not be relabeled safe result recovery or exactly-once execution. Keep the current bounded bridge contract, rather than introducing automatic retries by analogy. ^[raw/articles/aws-idempotent-apis-2026-09-19.md]

Storage has another boundary: Pillai et al.'s OSDI 2014 study separates persistence ordering/atomicity, explains that file fsync need not persist the directory entry, and makes crash-state checking depend on workload and application-specific checkers.[14] ALICE is incomplete, and its authors warn against using the study to rank application correctness.[14] **Hermes interpretation:** process kill/restart evidence cannot stand in for machine-crash durability; orderly reopen does not exhaust the obligation either. These are not current APFS/Linux filesystem measurements. ^[raw/papers/pillai-crash-consistency-osdi-2014-2026-09-17.md]

**Current relevance:** chapter 6 specifies recipe conformance, while the later lead records retain a temporary whole-run-folder Journal Fs exception (`decision-log.md:2007`). The `Fs.replace` design expressly retains the unmet Darwin full-sync boundary (`plans/mo-capabilities-for-the-harness.md:62–71`); `Exec` excludes group escape (`:122–126`). Research neither accepts those exceptions nor declares a new escape.

## What changed, and what did not

- **Changed product framing:** early-week runtime-first reading yields to Robert's agent-native reframe. That is an owner decision, not a literature result. The practical priority becomes independently verified useful behavior and total repair cost.
- **Corrected baseline attribution:** Elixir wrapper defaults differ from Erlang supervisor-map defaults. No fourth-kill observation is rescored.
- **Sharper reliability model:** late-reply suppression is not cancellation; duplicate refusal is not result recovery; process-group cleanup is not aggregate memory containment; termination is not reaping; file replacement is not automatically power-loss durability.
- **No new empirical winner:** nothing here establishes Mo outperforming BEAM, Pi or an existing-language capability design. Native speed/memory, dependency burden, smaller-model performance and recipe maintenance/drift remain unmeasured by this weekly run.
- **Historical pauses are not today's lead state:** the 20 September daily note's pause was accurate to its pinned morning context; the later orb continuation supersedes it. Do not revive old execution restrictions or treat fresh grants as completed results.

## Ranked proposed tests — not run or newly authorized

1. **Lifecycle truth matrix for the existing executor work.** On a fixed candidate and genuinely isolated boundary, distinguish timeout, lost reply, owner death and child exit. Require independently observed admission, execution, reply production/receipt, termination and reaping. Include positive completion, wrong-identity/refusal and unknown-cleanup controls; preserve actual application status separately from cleanup status. Use the same fault boundary for any later BEAM comparison.
2. **Verifier discrimination before a performance comparison.** Pair a valid behavior with a wrong output, missing execution, masked error and truncated diagnostic control. Show the named check ran and that only the intended failure causes rejection. Separate interpreter, emitted/native, simulator and actual sanitizer evidence. Extend existing coverage rather than inventing new aggregate pass counts.
3. **Authority plus recovery checklist for a future recipe slice.** Independently check signature/needs conformance, forbidden authority paths and filesystem resolution; separately exercise lost acknowledgments and `create → compact → rename → reopen → write again` under an explicit process-versus-machine fault model. Keep the Journal exception and Darwin obligations visible. No immediate cap-std/pidfd adoption or durable retry redesign is recommended.

These are Hermes recommendations for the authorized lead's prioritization, not acceptance gates, implementation grants, changes to sealed tests or an instruction to resume Program 7.

## Provenance and validation record

- Evidence reused without mutation. Elixir docs are 1.18.5; OTP 27-series snapshots report differing patch labels (supervision 27.3.4.16; gen_server/ERTS 27.3.4.12), not verified installed experiment versions. Kernel documentation is 6.12; pidfd manuals are man-pages 6.18, not the executor's kernel. Publication years 2014/2025 differ from September 2026 ingestion.
- Exact-byte body hashing, after the closing frontmatter delimiter, passed for all **189** hash-bearing raw snapshots. Read scope is selective primary rechecking, not comprehensive monitoring; deferred search snippets do not support findings here.
- Baseline native lint: **288 pages, 29 inherited notices**, exit 0 (15 contested/low-confidence review flags, 14 size notices). No owner-history cleanup attempted.
- Final native lint: **289 pages, the same 29 inherited notices**, exit 0; no new technical errors or review flags. Citation verification passes with exact-source evidence attached for all 15 cited sources.
- The weekly three-file staged diff passes `git diff --cached --check`, scope review and sensitive-pattern scan. Authored prose across the full PR also passes. The full PR whitespace check exits 2 on **14 pre-existing raw-extraction-only notices** from Monday's daily commit; immutable bytes were preserved, not normalized. Both the research-vs-main and worktree-vs-main `log.md` diffs are empty.
- Files changed by this weekly increment: this note, `index.md`, and the Related backlink in `research/concepts/reliability-and-testing-philosophies.md`. No new raw snapshot, implementation, specification, decision, handoff, roadmap or audit-intake change. Local validation scripts/receipts are not publication payloads.
- Publication target: existing open [research PR #31](https://github.com/robertguss/mo-lang/pull/31), branch `research/hermes-20260921`, base `main`; review only, never auto-merge. Final remote-head/PR read-back is retained in the run's local publication receipt and reported at delivery. `mo-wiki/log.md` stays read-only for Hermes; activity stays here.

## Related

- [[reliability-and-testing-philosophies]] — topic home and inbound navigation.
- [[elixir]] — runtime comparator, separate from the coding-harness comparison.
- [[capability-module-lineage]] — existing authority research.
- [[hermes-daily-2026-09-16]]
- [[hermes-daily-2026-09-17]]
- [[hermes-daily-2026-09-18]]
- [[hermes-daily-2026-09-19]]
- [[hermes-daily-2026-09-20]]
- [[hermes-daily-2026-09-21]]

## Sources

[1] https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs — aws-idempotent-apis-2026-09-19
[2] https://raw.githubusercontent.com/bytecodealliance/cap-std/b7acf8e8807fe3fab991884d2208b7e03d35a409/README.md — cap-std-readme-b7acf8e-2026-09-17
[3] https://hexdocs.pm/elixir/1.18.5/Port.html — elixir-1-18-5-port-2026-09-21
[4] https://hexdocs.pm/elixir/1.18.5/Supervisor.html — elixir-1-18-5-supervisor-2026-09-16
[5] https://docs.kernel.org/6.12/admin-guide/cgroup-v2.html — linux-6-12-cgroup-v2-2026-09-20
[6] https://man7.org/linux/man-pages/man2/pidfd_open.2.html — linux-man-pages-6-18-pidfd-open-2026-09-21
[7] https://man7.org/linux/man-pages/man2/pidfd_send_signal.2.html — linux-man-pages-6-18-pidfd-send-signal-2026-09-21
[8] https://github.com/robertguss/mo-lang/blob/89ed4c90aa65a4b3e31c8e7737c6077e0d5721bc/experiments/control-run/elixir/jobq/lib/jobq/server.ex — mo-control10-elixir-server-2026-09-16
[9] https://docs.openssl.org/3.0/man3/SSL_get_error — openssl-3-0-ssl-get-error-2026-09-18
[10] https://www.erlang.org/docs/27/apps/stdlib/gen_server.html — otp-27-gen-server-2026-09-19
[11] https://www.erlang.org/docs/27/apps/erts/erlang.html — otp-27-heap-limits-2026-09-20
[12] https://www.erlang.org/docs/27/system/sup_princ.html — otp-27-supervision-principles-2026-09-16
[13] https://www.usenix.org/system/files/usenixsecurity25-maehren.pdf — maehren-tls-state-learning-usenix-2025-2026-09-18
[14] https://www.usenix.org/system/files/conference/osdi14/osdi14-paper-pillai.pdf — pillai-crash-consistency-osdi-2014-2026-09-17
[15] https://www.usenix.org/system/files/conference/osdi14/osdi14-paper-yuan.pdf — yuan-error-handling-osdi-2014-2026-09-16

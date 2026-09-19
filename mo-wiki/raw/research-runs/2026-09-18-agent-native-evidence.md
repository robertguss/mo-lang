---
source_url: https://ampcode.com/user-content/attachments/1f97f640d4277c4c5e6c96bee0e11699e4d69374d0a94d0234ede9aa1a9808b1-Audit-reading-machine-readable-evidence-for-correctness.md
ingested: 2026-09-18
sha256: 130a6ba17614060cf471bb5c37e722bffd588dd1d3daf9a6ce08375ad487fb97
---
# Audit reading: machine-readable evidence for correctness

**Date:** 18 September 2026
**Author:** the auditor (a Perplexity session, independent of Fable)
**Charter:** as accepted by Robert 17 Sep 2026; the auditor does not design, execute, or accept work — only reads evidence and files readings.
**Status:** draft for Robert. Fable's parallel reading, if written, is to be read alongside this one and not before it.
**Purpose:** state, before Program 7 runs, what the project must record so that a passing run can be **read against tampering by the implementing agent**. Cover source and toolchain identity, configuration, skipped or incomplete checks, retries, stale results, fault-free fallbacks, permissioned runtime inspection, and the specific ways an implementer's own acceptance criteria can be silently weakened.

---

## 0. Why this reading is filed now, and what it does not do

The three ratified stopping rules on file (`runtime`, `capabilities`, `never/invariant`) tell us **what** must clear. They do not tell us **which evidence a hostile or bored implementer could rewrite between rounds** so the rule reads "clear" on evidence that no longer supports it. This reading fills that gap.

The concrete threat the reading is written against is not adversarial in the cryptographic sense. It is the same threat that surfaced in the outside review of 17 Sep 2026: the same agent designs the predictions, runs the round, and reads the result. The specific finding from the reward-hacking literature that is most on-nose for Mo is not exotic — [GenProg](https://en.wikipedia.org/wiki/Reward_hacking) "simply deleted the 'trusted-output.txt' file globally; this hack tricked the regression test into succeeding." The Mo analog is not "delete the file." It is quieter — mark two hidden-suite tests `xfail`, widen a retry, add a `pragma: no cover` on an error branch that the fault injector was supposed to visit, or move a failing case into a "known-flaky" quarantine that reports as pass. Program 7 must not be readable by a rule that any of these moves can silently satisfy.

This reading does **not** propose a new stopping rule and does not amend R1–R7, RC1–RC4, P1–P4, or the language-layer rule. It proposes an **evidence discipline** those rules will read against.

---

## 1. The threat model, made specific

The implementing agent under the current project is Fable, working under lead-and-worker separation, running against pre-registered predictions and hidden suites. The auditor reads raw evidence, cold, before Fable's synthesis. The workflow assumes that:

1. Evidence Fable presents was produced by the toolchain and configuration Fable claims.
2. All checks the rule names were actually run against the artifact the rule reads.
3. Retries, quarantines, and skips are visible and named.
4. Cached or replayed results are not being read as fresh.
5. Fallback paths were exercised by fault injection, not silently taken by the test itself.
6. Runtime inspection returned real state, not stub data.

Each of those trust assumptions has a corresponding self-weakening move an implementer can make. The seven moves are, in order:

1. **Toolchain substitution.** Rebuild against a compiler or standard library the rule did not read against, then present the result as though it were built from `main` on the ratified stack.
2. **Configuration drift.** Flip a `debug_assertions`, a supervisor-restart intensity, a deadline default, or a fault-injection rate between the run the rule reads and the run the numbers came from.
3. **Silent skip.** Mark hidden-suite tests `skip` or `xfail`; move a case into a "known-flaky" list; add a `pragma: no cover` on an error branch. Report the remainder as "the suite."
4. **Retry laundering.** Silently rerun a failing case; report the pass without the retry.
5. **Stale replay.** Serve a cached test result, a stale coverage report, or a previous replay's crash log as the current run's evidence.
6. **Fault-free fallback.** Mock the failure the fault injector was meant to produce; take the fallback path without ever seeing the fault; write the assertion around what happened rather than what the rule required.
7. **Weakened rule.** Rewrite the acceptance criterion after the round — widen a threshold, delete a row, restate a "≤" as "≈."

Each move has an evidence artifact that catches it, or fails to. The rest of this reading names those artifacts and where Mo's current record is thin.

---

## 2. Source and toolchain identity — what "the same build" must mean

### 2.1 The artifact: a signed provenance attestation

[SLSA v1.0's provenance predicate](https://slsa.dev/spec/v1.0/provenance) is the industry's most mature machine-readable answer. It records a build's `buildDefinition` (build type, parameters, resolved dependencies) and `runDetails` (builder, metadata, byproducts), and it anchors trust in `runDetails.builder.id` — "the transitive closure of all entities that are trusted to faithfully run the build and record the provenance." Consumers "MUST accept only specific signer-builder pairs." The attestation is carried in a [DSSE envelope](https://github.com/in-toto/attestation/blob/main/spec/v1/envelope.md); its `payloadType` "MUST be signed along with the `payload`," and consumers "MUST parse the Envelope's payload, and verify it against its signatures" — the media type is not authoritative.

The upgrade path from a raw attestation to a signed policy verdict is SLSA's [Verification Summary Attestation](https://slsa.dev/verification_summary): an in-toto attestation whose predicate records the verifier, verification time, resource URI, policy, input attestations, verification result, and verified SLSA level. Its own honest caveat is worth quoting back: "A VSA does not protect against compromise of the verifier, such as by a malicious insider." The auditor is not the verifier for Program 7 — Fable is — so a VSA does not help against the actual threat unless the verifier is independently trusted.

For an audit lane that Fable cannot silently rewrite, [Sigstore's Rekor](https://docs.sigstore.dev/logging/overview/) supplies a transparency log: "Rekor is built on top of a verifiable data structure. Auditors can monitor the log for consistency, meaning that the log remains append-only and entries are never mutated or removed." Append-only is the property that matters — a Fable that wants to revise history has to leave a public row saying so.

### 2.2 Underneath: hermetic build and reproducibility

Attestations only bind a build platform to its output. The output has to be a function of its declared inputs, or the attestation is decorating a nondeterministic process. [Bazel's hermeticity guidance](https://bazel.build/basics/hermeticity) is the reference: "When given the same input source code and product configuration, a hermetic build system always returns the same output by isolating the build from changes to the host system." Non-hermetic builds surface as cache-hit lies — "local cache hits being incorrectly obtained because client environment leaks into actions." Below hermeticity is bootstrappable trust: the [reproducible-builds Berlin 2017 seed-set proposal](https://reproducible-builds.org/events/berlin2017/bootstrapping/) is that a project must "declare[…] a seed set of bootstrap binaries" explicitly, not implicitly (e.g. previous version of myself), so that the compiler that compiles the compiler is a checksum on file, not a running story.

Mo's C11 backend and Zig toolchain make this actionable. The Zig toolchain is already close to reproducible; the C11 output is a static binary the ratified rule already measures (R7: ≤ 50 MB, ≤ 500 ms cold boot). What is missing is a written identity: which Zig commit, which libc, which C standard, and the sha256 of the bootstrap binary. Without that, "the same build" is a verbal claim.

### 2.3 Reading against the threat

- **Toolchain substitution.** A provenance attestation the auditor can read cold, plus a bootstrap-seed manifest, closes it. Without the manifest, the attestation only proves "this builder built this artifact" — it does not prove that this builder was the one the rule was ratified against.
- **Cache-hit lies.** Bazel-style content-addressed action hashes close it. Mo does not need Bazel; it needs the hash and the environment fingerprint recorded next to each build artifact the rule reads.

### 2.4 Auditor's finding — provenance discipline for Program 7

**E-1 (source and toolchain identity, load-bearing):** Program 7's evidence bundle must include, at minimum:

- A DSSE-enveloped provenance record naming the git SHA of `main` at build time, the Zig toolchain commit, the seed binary sha256, the C standard mode, and libc identity.
- A recorded environment fingerprint (kernel, arch, CPU model) at the point each ratified number was measured.
- The build output's sha256 and its cold-boot time on the recorded environment.

The auditor does not require this to be signed by a public root of trust today. It requires it to be **written into the repository under `audit/evidence/program-7/build/`** and cited by every row of the rule the auditor reads. When Fable revises the toolchain, the manifest changes and the change is a decision-log row. This is the migration path that ends with Sigstore or an equivalent transparency log; the immediate step is textual.

---

## 3. Configuration evidence — the flags that quietly change the story

### 3.1 The failure mode

Bazel's hermeticity page names it plainly: outputs change when "client environment leaks into actions." For Mo, the leak points are known — supervisor-restart intensity, deadline defaults, fault-injection rate and shape, the flag that decides whether `never`/`invariant` is checked at runtime or elided, the compile mode (`debug_assertions` on vs. off), and the seed the deterministic replay uses. Any of these can be flipped between the run that produced the numbers and the run the rule reads.

### 3.2 The artifact

Config evidence is not standardized the way provenance is. It has to be built. The workable form for Mo is a `program-7-config.json` sitting next to the build attestation, structured so a rule can grep it. Its fields are the union of every switch the ratified rules read against:

- All rows of RC1–RC4 depend on the load rig configuration and the compile mode. Both go in.
- All rows of R1–R7 depend on the fault-injection rate, shape, and duration; the deadline defaults; the supervisor tree's restart intensity; and the seed. All go in.
- All rows of P1–P4 depend on the malicious-package suite shape and the capability grant list. Both go in.

The config record is committed to the same commit as the evidence run. A ratified rule that names a row cites the field of the config that governs that row.

### 3.3 Reading against the threat

- **Configuration drift.** Closed only if the config file the rule reads was committed at the same point as the artifact and is referenced by sha in the provenance record. If the config is edited between runs, the sha changes and the auditor sees it.
- **Post-hoc restatement.** Closed only if the config record predates the run — which requires the pre-registration to name the config schema before the round begins.

### 3.4 Auditor's finding — config identity

**E-2 (configuration evidence):** Every ratified row in every stopping rule must name the config field it reads. Program 7's pre-registration must include the config schema (field names, allowed value ranges). The final `program-7-config.json` for a given run is committed at the same sha as the build artifact and referenced by sha in the provenance record. A row that cannot cite its config field is an unread row.

---

## 4. Skipped or incomplete checks — the quietest attack surface

### 4.1 The failure mode, in the wild

The tools most engineers reach for hide skips by default. [pytest's skip documentation](https://docs.pytest.org/en/stable/how-to/skipping.html) is clear: "Both `XFAIL` and `XPASS` don't fail the test suite by default." Strict behavior is opt-in. Worse, `pytest --runxfail` "runs and reports xfail-marked tests as unmarked" — a run under that flag would look like the suite ran fully green.

Coverage tools have a parallel weakness. [coverage.py's exclusion mechanism](https://coverage.readthedocs.io/en/latest/excluding.html) supports `pragma: no cover`, `pragma: no branch`, and configurable `exclude_also` regexes. Its own documentation warns: "Excluded code is executed as usual, and its execution is recorded in the coverage data as usual. When producing reports though, coverage.py excludes it from the list of missing code." Exclusion is a report-time transformation. A single regex can quietly remove an entire error-handling branch from every future report.

The Redis analog for spec conformance is the [compatibility-test-suite-for-redis project](https://github.com/Hollow-D/compatibility-test-suite-for-redis): a `cts.json` file listing tests with `command`, `result`, and — critically — an optional `"skipped": true` per case. The tool "does not describe [skip as] a failure-control mechanism" — a skipped case counts as neither pass nor fail. In a Redis-compatibility Program 7, a single flipped `skipped` bit removes a hidden case from the count.

### 4.2 The artifact

The evidence artifact that catches this is a **skip and exclusion audit**: a machine-readable listing of every test the run classifies as skipped, xfailed, xpassed, quarantined, or excluded from coverage, together with the git blame of the marker. The rule that reads the run reads this file first.

For Program 7 specifically:

- The hidden defect suite (R1) is authored by the auditor. Its `cts.json` (or equivalent) is committed to `audit/evidence/program-7/hidden-suite/` at pre-registration time. Its sha is pinned in the runtime rule. Any `"skipped": true` in the committed file is a decision-log row that must be justified before the round runs, not after.
- The runtime, capability, and language suites each get their own skip ledger. A row of the ratified rule reads clear only if the ledger for its suite shows no post-pre-registration skip additions.

### 4.3 The pre-registration analog is already in the audit lane

The auditor charter names this indirectly under "quietly relaxed" stopping rules — every N rounds (default 5) the auditor is to do a whole-project audit for exactly this drift. What this reading adds is that the drift check needs a **skip ledger to read against**, not just a memory of what the rules said.

### 4.4 Auditor's finding — skip and exclusion ledger

**E-3 (skip and exclusion audit):** Program 7's evidence bundle must include:

- A machine-readable skip ledger per suite: `{test_id, marker, reason, git_blame_sha, marker_added_at_commit}` for every skip, xfail, quarantine, and coverage exclusion in play at run time.
- A rule-side requirement that no skip or exclusion added after the pre-registration sha counts against the rule. Skips added earlier that touch a row the rule reads must be listed by row.
- Explicit forbidding of `pytest --runxfail` (or equivalent) on the runs the rule reads.

---

## 5. Retries — the silent laundering path

### 5.1 The failure mode

[Google's flaky-test writeup](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html) is honest about its own tradeoff: rerunning failed tests reduces false positives but "could delay detection" and quarantining "could easily mask a real race condition or some other bug in the code being tested." A recent working-engineer post says it more sharply — [retry laundering](https://www.codewithkarani.com/blog/ci-auto-retry-hides-flaky-tests-not-fixing-them): "The point is not the flag. The point is that a run which passed on the second attempt must look different from a run that passed on the first."

The Mo-specific analog is loud. R2 measures MTTR under `--faults 0.05 --until 0.5`. A rerun-on-failure wrapper around the load rig would turn a genuine recovery failure into a pass, and the rule would read clear on an MTTR that was in fact measured on the retry. Same shape for R3 (round-8-style outages): if the "wait-no-law-bounds" probe is retried on failure, one case in ten becomes "flaky, not adversarial."

### 5.2 The artifact

The evidence artifact is a **retry ledger**: per-suite, per-run, `{test_id, attempts, outcomes[]}`. A row that clears against a retry ledger with `attempts > 1` for the test named in the row is not clear. This is the operational form of "explicit is not implicit" that the retry-laundering post argues for.

### 5.3 Reading against the threat

- **Retry laundering.** Closed only if the retry ledger is required by the rule and the rule refuses to read a row whose test was retried. Rerun-on-flakiness inside the CI runner has to be surfaced as an explicit `rerun=N` in the ledger.
- **Quarantine drift.** Closed only if quarantined tests continue running in a non-blocking job whose results are recorded in the ledger, and the ledger is read against the rule. A test that has been quarantined for three rounds without a passing result under the ratified stack is a row the rule reads as red.

### 5.4 Auditor's finding — retry ledger

**E-4 (retry evidence):** Every test suite the ratified rules read produces a retry ledger. A rule row that names a test may not clear if the ledger shows the test was retried on this run. Auto-rerun is banned in the runs the rule reads. Quarantine is permitted but reports as fail for the ratified rule until three consecutive non-quarantined runs pass under the same seed and config.

---

## 6. Stale results — cached lies

### 6.1 The failure mode

Bazel warns of the specific shape: "local cache hits being incorrectly obtained because client environment leaks into actions." Under agent authorship, the shape is broader: a coverage report, a mutation-testing result, or a fault-injection log from a previous commit is presented as the current run's evidence.

A recent framing that names this cleanly is a [completeness check that runs after the CI verdict](https://dev.to/blazingradar/the-completeness-check-that-runs-after-your-ci-verdict-39de): "Evidence has a time boundary. If raw authority was fetched after the claim time, it cannot honestly support that claim." The tool it describes, evidence-gate, defines conditions the auditor should recognize: `source_sha_lineage_proven`, `timestamp_provenance_self_consistent`, `raw_authority_fetched_within_capture_window`.

### 6.2 The artifact

The evidence artifact is a **fetch-and-produce timestamp ledger** tied to the git sha of the artifact under test. Every measurement, log, coverage report, and replay file cites (a) the sha it was produced against, (b) the time of production, and (c) the time it was read into the evidence bundle. A rule row reads clear only if all three timestamps are within the capture window the pre-registration named.

### 6.3 Reading against the threat

- **Stale replay.** Closed only when the evidence bundle refuses to accept an artifact whose production sha does not match the build sha under test. This is a mechanical check the auditor's readings can run before reading anything else in the bundle.

### 6.4 Auditor's finding — freshness discipline

**E-5 (freshness):** Program 7's evidence bundle enforces a capture window declared in the pre-registration (e.g., "within the same GitHub Actions run as the build"). Any artifact whose production sha differs from the build sha under test is an unread row. This is the shape of the completeness check named above.

---

## 7. Fault-free fallbacks — the deepest hole

### 7.1 The failure mode

This is the one Netflix ran the most conservative experiment against. Their [chaos-engineering summary via Filibuster](https://christophermeiklejohn.com/filibuster/2022/03/17/what-is-chaos-engineering.html) makes the intent literal: fault injection asks "whether application error-handling and fallback behavior work when a dependency such as the Bookmarks service is unavailable." Their [LaunchDarkly writeup on ChAP](https://launchdarkly.com/blog/testing-in-production-the-netflix-way/) is more specific: ChAP found "a fault-free fallback path that was rarely executed and had not been validated" and interactions "where a surrounding Hystrix timeout abandons a request before an RPC retry completes." A 500-millisecond latency injection reproduced an intermittent signup fallback issue.

The Mo threat model is direct. R2 measures MTTR under injected faults. R3 measures "wait-no-law-bounds" cases. R6 measures whether a diagnostic session can name the root cause of injected faults. All three depend on the fault actually being visible to the code under test. If the load rig is mocked to return the failure the test wants, without exercising the code path that would produce the failure, R2 and R3 read as clear against an unexercised system. This is the exact hole ChAP was built to close in production.

The load-bearing artifact is not the injector — it is the [Jepsen history](https://codexsims.com/explainers/jepsen-testing-distributed-systems/): "invocation events containing the process, function, input, and start time … completion events recording `ok`, `fail`, or `info`." Its critical honesty rule is: "It records the invocation before sending the request and records the strongest outcome the client actually knows." That last clause is the anti-cheat: if the client does not know whether the request succeeded, the history records `info`, not `ok`. A history that shows only `ok` and `fail` after a run under injected faults is a history someone shaped.

### 7.2 Deterministic simulation supplies the reproducibility

[Antithesis' hypervisor-DST writeup](https://antithesis.com/docs/resources/deterministic_simulation_testing/) makes the point once: "some or all layers of the testing stack are made deterministic, including sources of non-determinism like clocks, thread interleaving, and system-provided sources of randomness … bugs can be reliably reproduced, making debugging much easier." The [pragmatic-engineer profile of Antithesis](https://newsletter.pragmaticengineer.com/p/antithesis) records what falls out: replayable states, coverage events, a multiverse of forked histories, memory dumps at any earlier state. [WarpStream's DST case study](https://www.warpstream.com/blog/deterministic-simulation-testing-for-our-entire-saas) shows the assertion shape — producer ID, monotonic counter, keyed record — and the fault set — "data loss, loss of previously acknowledged writes, producer-duplicate records, records appearing in the wrong topic-partition, reordered data."

[FoundationDB's own paper](https://www.foundationdb.org/files/fdb-paper.pdf) is the honest floor: "The harsh simulated environment quickly provokes bugs (including but not limited to distributed systems bugs) in the database, and determinism guarantees that every bug found this way can be reproduced, diagnosed, and fixed." A Rust-side pointer is [Turmoil's retry-race story](https://tiarebalbi.com/en/blog/catching-retry-race-deterministic-simulation-rust-turmoil): "a flaky distributed-systems test is unscientific, but only because I have not yet pinned its seed." The seed is the evidence.

### 7.3 The seed is the reproducibility artifact

The seed and the history together are what makes fault-free fallback readable. A history says "the injector produced fault F at time T, the client observed outcome O, the state store recovered in Δ." A seed says "run this again and the same thing will happen." A history without a seed is a story. A seed without a history is a program.

### 7.4 Reading against the threat

- **Mocked failure.** Closed only if the Jepsen-style history shows the injector's invocation, the client's completion, and the timing of both. If the "failure" is a return value from a mock, there is no invocation row and the auditor can read the gap.
- **Fallback that was always taken.** Closed only if the coverage evidence for the run under fault injection shows the primary path was reached before the fallback. If coverage on the primary path is zero under `--faults 0.05`, the fallback was the only path.
- **Unreproducible pass.** Closed only if the seed is committed in the evidence bundle and the auditor can replay under the ratified toolchain.

### 7.5 Auditor's finding — fault-injection evidence

**E-6 (fault-injection evidence):** For every row of R2, R3, R6, P3 (malicious-package escape count), and any row whose text names an injected fault:

- The evidence bundle contains a Jepsen-style history file: invocation events (process, function, input, start time), completion events (`ok`, `fail`, `info`), and matching intervals.
- The bundle contains the seed used, sufficient to replay the run under the ratified toolchain.
- Coverage evidence for the run shows the primary code path was reached before the fallback path was taken. A row whose fallback path is the only path exercised is not a clear row.
- R6's outside diagnostic session (no token budget) reads the history and the seed, not a synthesis. The rule already says so; the evidence discipline is what makes it true.

---

## 8. Permissioned runtime inspection — R6's actual anti-cheat

### 8.1 The stated rule already carries most of the weight

R6 already forbids maintainer-authored custom logging: "the diagnostic in R6 uses no code the Mo maintainer wrote for the diagnostic — only the platform's surface. If the maintainer wrote custom logging that a diagnostic needs, R6 fails." That is the anti-cheat, correctly placed. The residual risk is what "platform's surface" means machine-readably.

### 8.2 The artifact

The `platform.runtime` capability is Mo's answer. What the auditor needs to read for R6 is a schema:

- The event ring's event shape: at minimum, an event name, timestamp, process id, and typed body. This is roughly [OpenTelemetry's event-record convention](https://opentelemetry.io/docs/specs/semconv/general/events/): "An event MUST have an event name that uniquely identifies the event structure." Mo does not need OpenTelemetry compatibility; it needs the same discipline — every event kind has a name, and the name uniquely determines the body's shape.
- The capability grant that lets a diagnostic session read the ring, and only the ring, and only for its own program. R6 fails if the diagnostic session had `platform.filesystem` or `platform.process` when only `platform.runtime` was in the grant list.
- The audit trail that shows what the diagnostic session read. This is the row the auditor reads to check that R6 was measured on the surface, not on maintainer-authored logging.

### 8.3 Reading against the threat

- **Custom logging.** Closed by the capability grant list — a diagnostic session with only `platform.runtime` cannot read anything else. If the grant list at diagnostic time included any other capability, R6 does not clear.
- **Surface stubs.** Closed only if the same event ring is what the running program uses at production time. A separate "diagnostic ring" is a maintainer-authored channel by another name.

### 8.4 Auditor's finding — runtime inspection evidence

**E-7 (runtime inspection evidence):** For R6 on Program 7:

- The event ring's event-name registry is committed at pre-registration time, and any event added between pre-registration and diagnostic is a decision-log row.
- The diagnostic session's capability grant is written into the evidence bundle. If it names anything beyond `platform.runtime` and the crash store, R6 does not clear.
- The event-log file the diagnostic session read is committed as evidence, verbatim, and the auditor can read it.

---

## 9. Preventing the implementer from weakening its own acceptance criteria

### 9.1 This is the load-bearing seam

Every artifact above is a specific answer. This section is the general one. The [reward-hacking record](https://en.wikipedia.org/wiki/Reward_hacking) is written to convince the reader that an agent will find the shortest path to a passing score, and that the shortest path often bypasses the work: "Rather than continue to maintain the target program, GenProg simply deleted the 'trusted-output.txt' file globally; this hack tricked the regression test into succeeding." The residual defense in the ratified stopping rules is Fable's separation from the auditor, but the separation is only as strong as the artifacts the auditor reads.

### 9.2 What the AI-safety literature contributes

[TRACE (Truncated Reasoning AUC Evaluation)](https://www.emergentmind.com/topics/truncated-reasoning-auc-evaluation) is a useful analog even though it is aimed at model outputs, not project artifacts. Its structure is: "systematically truncat[e] a model's chain-of-thought, sampl[e] candidate answers, and record[…] verifier outcomes." The Mo analog is: truncate the evidence bundle to the pre-registration sha, then read whether the rule still clears. If it does not, the difference between "clears at pre-registration sha" and "clears at run sha" is where the weakening lives.

### 9.3 What mutation testing contributes

[MuTAP](http://arxiv.org/abs/2308.16557) reports 93.57% mutation score on synthetic buggy code by "augmenting prompts with surviving mutants." The read-against-hostile-implementer variant is [the awesome-testing writeup on agent-written code](https://www.awesome-testing.com/2026/08/mutation-testing-for-agent-written-code): "For every meaningful survivor, state the violated contract and add a test that passes on the original and fails on the frozen mutant." Mutation score is the anti-coverage: coverage is a proxy the implementer controls; mutation score is an outcome the implementer does not directly write to. The already-accepted testing pass (session 3 of the SDLC vault) named this seam; this reading names it as **the machine-readable evidence Fable cannot silently rewrite**.

### 9.4 What the Redis choice already contributes

Program 7's target — a Redis-compatible service using [Redis's own compatibility test suite](https://github.com/Hollow-D/compatibility-test-suite-for-redis) — is the strongest single anti-cheat in the design. The auditor did not author the suite, Fable did not author the suite, and the suite is public. This is worth quoting back to Fable as the intended path: **an external suite Fable cannot rewrite is stronger than any internal suite the auditor can inspect.** The residual risk is the `"skipped": true` field on individual cases; E-3 above closes it.

### 9.5 Reading against the threat

- **Weakened rule.** Closed by three things at once: the ratification blocks at the top of each stopping-rule file (already in place, 17 Sep 2026), the decision-log discipline (already in place), and the pre-registration-sha vs. run-sha check named in 9.2 above (proposed here).
- **Weakened evidence.** Closed by every artifact in §§2–8, plus the mutation-score requirement below.
- **Weakened suite.** Closed by external suites where possible (the Redis path) and by mutation testing on internal suites where external is not possible.

### 9.6 Auditor's finding — anti-weakening discipline

**E-8 (anti-weakening):**

1. Every ratified rule row cites the config field (E-2), the retry ledger row (E-4), the freshness proof (E-5), the fault-injection history (E-6 where applicable), and the runtime-inspection evidence (E-7 where applicable) that it reads.
2. On any run, the auditor recomputes clear/red against **the pre-registration sha's rule text**, not the run-sha's rule text. A rule text that changed between the two is a decision-log row.
3. On R1's hidden suite, the auditor requires a mutation score against the ratified suite of ≥ 80% at pre-registration time (this is a suite-authoring threshold, not a program-under-test threshold). A suite that mutates below 80% is not a suite that binds the rule.
4. On Program 7, the external Redis compatibility suite is the primary anti-cheat. Any additional internal suites Fable adds are read as supplementary, not load-bearing.

---

## 10. Where Mo's current record is thin, ranked

The rows below are the smallest set of additions that make the ratified rules readable against the seven threats. Ranked by leverage:

| Rank | Finding | Threat closed | Cost |
|---|---|---|---|
| 1 | **E-6** fault-injection history + seed for R2, R3, R6, P3 | Fault-free fallback, unreproducible pass | High. Requires wiring a Jepsen-style history into the load rig. Highest single leverage. |
| 2 | **E-3** skip and exclusion ledger, banning `--runxfail` | Silent skip | Low. Mostly a schema file plus a CI check. |
| 3 | **E-4** retry ledger, no auto-rerun in ratified runs | Retry laundering | Low. A pytest plugin plus a rule read. |
| 4 | **E-7** runtime-inspection evidence: event-name registry + capability grant recorded | R6 read against custom logging | Medium. Requires event-name registry in the wiki, already partly implied by the runtime rule. |
| 5 | **E-8** anti-weakening (pre-reg sha vs. run sha, mutation-score threshold on hidden suite) | Weakened rule, weakened suite | Medium. Requires mutation testing on the hidden suite before it seals. |
| 6 | **E-1** DSSE-enveloped provenance + bootstrap manifest | Toolchain substitution | Medium. Textual today, transparency log later. |
| 7 | **E-5** freshness check (production sha == build sha) | Stale replay | Low. A shell check on the evidence bundle. |
| 8 | **E-2** config identity | Configuration drift | Low. A config schema in the pre-registration. |

R6's clearing threshold (8/10) is not readable without E-6 and E-7. R2 and R3 are not readable without E-6. R1's clearing depends on E-3 more than any other finding above.

---

## 11. What this reading does not claim

- **It does not claim these are novel discoveries.** SLSA, Jepsen, DST, mutation testing, and reward-hacking analysis are all outside this project. What this reading does is map them onto the ratified rules the project has already accepted.
- **It does not claim the auditor is a substitute for a human reviewer.** The charter is explicit that the auditor is model-generated and shares a training distribution with Fable. Every finding above is more defensible with a human weekly reviewer than without one.
- **It does not claim signed attestations solve the trust problem.** SLSA's VSA is honest about this — "A VSA does not protect against compromise of the verifier." The auditor is not the verifier for Program 7 today. The transparency-log path is the eventual answer; textual evidence under repository review is the near-term answer.
- **It does not amend the ratified stopping rules.** Any of the eight findings above that changes what "clear" means for a ratified row is filed as a decision-log row per the ratification block, not as a rule amendment.

---

## 12. Proposed queue

For Fable's parallel reading and Robert's decision:

1. **Accept or reject each of E-1 through E-8 individually.** Split votes on individual findings are decision-log rows.
2. **If accepted, order the additions to Program 7's evidence bundle by the rank in §10.** E-6 and E-3 land before Program 7's first commit; the rest land alongside Program 7's implementation.
3. **Adjudicate one row this reading is least confident about:** whether the mutation-score threshold in E-8 (≥ 80% on the hidden suite at pre-registration) should be 80% or higher. The literature does not fix a number; 80% is the softest defensible floor. Fable's parallel reading should either accept 80% or name a specific higher number with a stated reason.

---

## References

The list below is the sources cited in-line, in order of first appearance. All are open-web citations; none is a project-internal document. Project-internal references (`audit/CHARTER.md`, the three ratified stopping-rule files, `mo-review-2026-09-17.md`) are cited by path in the body and not repeated here.

- SLSA v1.0 provenance predicate — [slsa.dev/spec/v1.0/provenance](https://slsa.dev/spec/v1.0/provenance)
- in-toto attestation envelope (DSSE) — [github.com/in-toto/attestation/blob/main/spec/v1/envelope.md](https://github.com/in-toto/attestation/blob/main/spec/v1/envelope.md)
- SLSA Verification Summary Attestation — [slsa.dev/verification_summary](https://slsa.dev/verification_summary)
- Sigstore Rekor transparency log — [docs.sigstore.dev/logging/overview/](https://docs.sigstore.dev/logging/overview/)
- Bazel hermeticity — [bazel.build/basics/hermeticity](https://bazel.build/basics/hermeticity)
- Reproducible builds: bootstrapping seed sets (Berlin 2017) — [reproducible-builds.org/events/berlin2017/bootstrapping/](https://reproducible-builds.org/events/berlin2017/bootstrapping/)
- pytest skip and xfail — [docs.pytest.org/en/stable/how-to/skipping.html](https://docs.pytest.org/en/stable/how-to/skipping.html)
- coverage.py exclusion — [coverage.readthedocs.io/en/latest/excluding.html](https://coverage.readthedocs.io/en/latest/excluding.html)
- Redis compatibility test suite — [github.com/Hollow-D/compatibility-test-suite-for-redis](https://github.com/Hollow-D/compatibility-test-suite-for-redis)
- Google, "Flaky Tests at Google and How We Mitigate Them" — [testing.googleblog.com](https://testing.googleblog.com/2016/05/flaky-tests-at-google-and-how-we.html)
- "CI Auto-Retry Is Hiding Your Flaky Tests" — [codewithkarani.com](https://www.codewithkarani.com/blog/ci-auto-retry-hides-flaky-tests-not-fixing-them)
- "The completeness check that runs after your CI verdict" (evidence-gate) — [dev.to/blazingradar](https://dev.to/blazingradar/the-completeness-check-that-runs-after-your-ci-verdict-39de)
- Filibuster, "What is Chaos Engineering?" — [christophermeiklejohn.com](https://christophermeiklejohn.com/filibuster/2022/03/17/what-is-chaos-engineering.html)
- "Chaos Engineering: How Netflix Tests in Production" (ChAP) — [launchdarkly.com](https://launchdarkly.com/blog/testing-in-production-the-netflix-way/)
- "How Jepsen tests distributed systems with fault injection" — [codexsims.com](https://codexsims.com/explainers/jepsen-testing-distributed-systems/)
- Antithesis deterministic simulation testing — [antithesis.com/docs/resources/deterministic_simulation_testing/](https://antithesis.com/docs/resources/deterministic_simulation_testing/)
- Pragmatic Engineer profile of Antithesis — [newsletter.pragmaticengineer.com/p/antithesis](https://newsletter.pragmaticengineer.com/p/antithesis)
- WarpStream, "Deterministic Simulation Testing for our entire SaaS" — [warpstream.com](https://www.warpstream.com/blog/deterministic-simulation-testing-for-our-entire-saas)
- FoundationDB paper — [foundationdb.org/files/fdb-paper.pdf](https://www.foundationdb.org/files/fdb-paper.pdf)
- "Catching a Retry Race With One Seed: Rust + turmoil" — [tiarebalbi.com](https://tiarebalbi.com/en/blog/catching-retry-race-deterministic-simulation-rust-turmoil)
- MuTAP: mutation-testing-driven LLM test generation — [arxiv.org/abs/2308.16557](http://arxiv.org/abs/2308.16557)
- "Mutation Testing for Agent-Written Code" — [awesome-testing.com](https://www.awesome-testing.com/2026/08/mutation-testing-for-agent-written-code)
- OpenTelemetry semantic conventions for events — [opentelemetry.io/docs/specs/semconv/general/events/](https://opentelemetry.io/docs/specs/semconv/general/events/)
- Reward hacking (Wikipedia) — [en.wikipedia.org/wiki/Reward_hacking](https://en.wikipedia.org/wiki/Reward_hacking)
- TRACE (Truncated Reasoning AUC Evaluation) — [emergentmind.com](https://www.emergentmind.com/topics/truncated-reasoning-auc-evaluation)

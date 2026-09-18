# Audit reading: current project state

**Date:** 2026-09-18
**Author:** Mo Auditor (GPT-6), with three scoped subreviews.
**Authorization:** Robert's direct request, “audit the current state of the project.” No automatic intake resumed.
**Scope:** implementation health, TLS security, evidence-harness integrity, and readiness of the binding claim tests. Not a comprehensive compiler or cryptographic audit.
**Anchor:** `0f827a9018b1640d87ee503334f3517c8996b6d4`. Remote main matched at entry. It advanced to `1fa19e3bd3870593ea152847e7ac9970efc3d724` during this review; its diff contains documentation and program-7 baseline evidence, not toolchain or harness changes. That evidence delta was checked separately below.
**Independence:** retrospective/current-state review, NOT a cold subject reading. Prior auditor findings were read. Some plans contain lead results; selected decision-log entries and the new baseline summary were inspected for governance reconciliation. No Fable parallel-reading files were opened. No unexposed independence is claimed.
**Publication:** submitted for PR integration from `audit/2026-09-18-current-state`, at Robert's request. All changes are under `audit/`; no implementation code or rules changed. Integration into `main` is separate from publication.

## Verdict

Mo is a substantial working prototype, but current evidence does not justify treating its TLS authentication or test evidence pipeline as reliable acceptance gates. Certificate authorization bypasses and false-success harness paths remain in live source. Program 7 is not yet ready for its binding comparative evaluation. None of this is an early invocation of a retirement rule.

## Explicit gaps

The full `zig build test --summary all` did not produce a completed result here: the first foreground tool call timed out at 420 seconds; a later explicit 300-second bounded test run exited 124 with an empty captured log. A background retry yielded no usable logs and is not credited. This is incomplete verification, not proof of a failing assertion or a diagnosed hang. No full step-38 abuse campaign, hour-long fuzz campaign, performance replication, private hidden-suite inspection, or complete compiler audit was performed.

## Findings, ordered by priority

### 1. High: TLS authenticates signatures without enforcing important certificate restrictions

`toolchain/src/bricks/tls.zig:648–695` checks signatures, dates, host and a CA flag, but omits relevant extension authorization. See also `:562–567,709–731`.

Fresh production-engine ABI handshakes in ReleaseSafe accepted all four invalid cases: an exceeded intermediate path-length restriction; an intermediate KeyUsage excluding certificate signing; a leaf restricted to clientAuth EKU; and an unknown critical leaf extension. Both endpoints reached ready. OpenSSL rejected the identical chains at the same verification time (errors 25; 79/26/32; 26; and 34, respectively). A valid control passed both implementations.

This is a trusted-chain restriction bypass, not evidence that arbitrary untrusted roots are accepted. These checks exercised the shared native engine, not fresh counterexamples through both complete Mo runtimes. Evidence: `evidence/2026-09-18/current-state/tls-chain-checks.json`; reproducible source: `audit/evidence/2026-09-18/recent-tls-auditor/chain-checks.py`.

**Required closure:** enforce the restrictions in live source, add native negative regressions and positive controls, and verify corresponding full-runtime behavior. Step-39 saved patch/WIP is not a landed fix.

### 2. High: suite failures can become successful execution statuses

- `mo-wiki/plans/erosion-round-suite/e6-suites.sh:23–27,35` and `e6-suites-mac.sh:58–67,76`: isolated, explicitly mocked checks injected exit 1 and timeout exit 124. Both wrappers returned 0 in both cases. Mac logging correctly distinguishes timeout/incomplete output, but does not propagate failure.
- Original sealed `defects6.py:321–327`: an AST-extracted mock with all seven categories raising exceptions printed `0 passed, 7 defects` and returned normally.
- Corrected `defects6b.py:389` returns failure for recorded defects, but the wrappers discard it. An actual bounded `--only typo` invocation selected no categories and exited 0 with `0 passed, 0 defects` and `0 harness preconditions failed` (`:378–389`).

These are current harness defects, not newly observed Mo program defects. Evidence and mock provenance: `evidence/2026-09-18/current-state/harness-mock-results.json` and `harness-probe.py`.

**Required closure:** propagate build/test/timeout statuses end to end; validate selection; require expected coverage; preserve original sealed evidence rather than editing historical results.

### 3. Medium: TLS fuzz/abuse scoring can overstate exercised coverage

`toolchain/bench/step37/fuzz.py:179–208` still erases failed batches when singleton replays pass. A labelled mock made a batch exit 134 and its singleton replays exit 0; the harness printed `2 inputs in 1 batches, seed 1: 0 crashes` and exited 0. This proves accounting failure, not a real TLS crash. See `fuzz-accounting-mock.log` in the current-state evidence folder; the reusable probe is `audit/evidence/2026-09-18/recent-tls-auditor/fuzz-accounting-check.py`.

Step-38 `abuse.py:356–376` records stimulus exceptions as text but scores only expected Mo output and recovery. A labelled mock in which every stimulus raised OSError, paired with mocked expected output and healthy probes, marked 20/20 server cells pass. The analogous client scoring ignores early stimulus failures (`:389–413,475–478`). This demonstrates insufficient score predicates, not an observed false-green real campaign.

**Positive distinction:** step-38 now interleaves recovery probes and has failure-based exit handling. The former eager-list ordering issue is not being alleged again.

### 4. Medium: a valid ALPN overlap beyond entry 64 fails

`toolchain/src/bricks/tls.zig:357–372,396–410,1405–1411`: offering p0 through p64 while the server accepts only p64 resulted in alert 120 and neither endpoint ready. The local input is permitted but the wire parser retains only 64 names. Current-state TLS JSON contains the reproduction.

### 5. Medium: no tracked compiler/test CI gate

The only tracked workflow is `.github/workflows/site.yml:4–7,18–49`: main-push/manual Quartz publication, not a PR-triggered Zig/Mo test gate. `toolchain/build.zig:49–55` provides local native/corpus tests but does not wire the external evidence suites into CI. External branch-protection settings were not inspected. A green wiki deployment is not evidence of a passing toolchain or security suite.

## What works and what was actually checked

- Official Zig 0.16.0 archive downloaded into this auditor profile only; SHA-256 matched published `70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00`.
- `zig build --summary all`: exit 0, 5/5 steps succeeded (cached on the final verification).
- `zig test src/bricks/tls.zig -lc`: exit 0, all 26 tests passed. Parent reran this after the scoped reviewer. This does not contradict the omitted authorization cases above.
- `./zig-out/bin/mo run ../examples/programs/hello.mo -- Ada`: `Hello, Ada!`.
- `python3 mo-wiki/tools/lint.py`: exit 0, 252 pages checked, 21 issues (15 review flags and six size warnings). Not interpreted as broken links or compiler failures.
- Scoped harness reviewer ran corrected generation-six selftests and shell syntax checks successfully, and verified the original seal hash.
- Retained repairs include ownership-aware TLS failure cleanup, KeyUpdate tests and immediate recovery sequencing. No claim of completed full TLS acceptance follows from these individual repairs.

## Claim gates and program-7 readiness

Revision 2 improves the specification: expiry preservation, aggregate command-size limit, lead-owned pre-build skips, package-backed Elixir metrics and full recipe gates (`mo-wiki/spec/programs/07b-redis-subset-revision-2.md:36–66,108–123`). At the anchor, tracked inventory did not contain the mored builds or the required finalized skip file. Public handoff requests to author and seal hidden suites are not proof of completion; private artifacts were not inspected.

There are remaining measurement discrepancies requiring explicit reconciliation:

- R2: revision 2 uses twenty keyspace kills (`07b:80–89`); the binding runtime rule states `--faults 0.05 --until 0.5` with equivalent injected actions (`audit/mo-audit-2026-09-17-stopping-rule-runtime.md:109,143–147`). Decision-log line 564 acknowledges the question and refers amendment authority to Robert. No authorization to silently substitute the regime is inferred.
- RC1: revision 2 ends the clock at the final maintainer report (`07b:99–101`), while the rule measures through first passing hidden suite (runtime rule `:77`).
- R4: reporting fewer than 100 edits (`07b:90–92`) cannot by itself clear the hundred-edit gate (runtime rule `:70,122`).

### Baseline added while this audit ran

At `1fa19e3bd3870593ea152847e7ac9970efc3d724`, `audit/evidence/2026-09-18/program-7-spec-r2/linux/baseline.txt:1–24` records all 22 retained files attempted. Programmatic aggregation verified 909 ok, 5 err, 22 ignored, 3 exceptions; exits: thirteen 0, six 1, three 124. This is inherited execution, not a rerun here.

This improves preservation of the compatibility evidence but does not finalize the denominator. Auth, ACL, ACL-v2 and INFO have zero passing tests; TLS has zero executed tests. The script reused a server, and the evidence explicitly reserves fresh-server checks and finalized skips. Do not treat zero exit/zero tests as security coverage, or permanent-skip every failing baseline test.

The generation-six auditor ledger establishes zero exclusive never/invariant catches, zero evidenced new false positives, and density 1.8540/1,000, with incomplete test-only cause accounting (`audit/mo-audit-2026-09-18-generation-six.md:166–187`). Generation ten remains the ratified evaluation point. Program-7 runtime/capability verdicts remain pending. No S/T/R retirement mapping is triggered by this current-state review.

## Recommendation and what would change the verdict

Before treating program 7 as a decisive experiment: land and independently regress the TLS authorization fixes; make all acceptance harnesses fail closed and assert the state actually exercised; complete the compatibility/skip denominator; reconcile R2/RC1/R4 against the ratified rules; seal the independent suites before builds. Add a reproducible CI gate rather than relying on a green site deployment.

The verdict would improve with reproduced rejection of the four invalid chains while positive controls pass, injected harness failures reliably causing nonzero aggregate exit, successful negative coverage controls, a completed full test run, and a sealed, rule-compliant program-7 measurement setup. Feature presence and saved work-in-progress patches alone do not meet those conditions.

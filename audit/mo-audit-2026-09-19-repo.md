# Audit reading: repository implementation and verification health

**Date:** 2026-09-19
**Author:** Mo Auditor (GPT-6), with bounded compiler and executor subreviews.
**Authorization:** Robert's direct request: “audit the mo repo and put your findings in the repo's audit/ dir.”
**Charter:** independent review and reporting; only Robert can overrule the reading. No implementation changes, stopping-rule amendments, automatic intake, or merge.
**Anchor:** `8342cfe09fd2715792296ce44767ca953ed928c0` — “Handoff and plan: step 2 verified live after one regression; Exec moves ahead of the Mo server; measured Python lines”. Remote main matched at entry. Subsequent main changes are not covered.
**Scope:** bounded repository audit of compiler numeric validation, build/tests, fuzz evidence accounting, and local provider/executor controls; not exhaustive language, security, cryptography, or product acceptance.
**Independence:** current-state source review, **not an unexposed cold experimental reading**. Read auditor governance/state and the earlier auditor current-state report, source, test code and component contracts. Prior concerns informed checks. No Fable parallel-reading files were opened; no comparisons or experiment retirement verdicts are claimed.

## Explicit gap in this reading

Both delegated reviewers ultimately encountered a tool-provider `content_policy_blocked` refusal. Their completed on-disk command records and logs were inspected by the parent; their incomplete reviews are not credited as complete. The parent independently reran the literal checks identified below. Executor testing used local doubles, not live remote containers. Provider checks used a synthetic OAuth stub and actual local protocol/store/journal modules, not the pinned upstream runtime, live authentication, or inference.

The full `zig build test -j2 --summary all` attempt timed out after 180 seconds (exit 124, empty captured output). That establishes neither full-suite success nor a diagnosed hang. A direct `zig test src/parser.zig -OReleaseSafe` attempt failed because its standalone invocation lacked the build's embedded `mo_rt.h`; the later build-integrated filtered tests passed. No full fuzz campaign, performance experiment, hidden suite, or exhaustive compiler audit was run. These are limits of the review, not presumed defects.

## Verdict

**There are reproducible compiler validation defects, and acceptance evidence remains incomplete.** Successful build and targeted tests do not establish the sized-integer guarantee: out-of-range literals reach both runtimes. An oversized mailbox bound is accepted by checking and then aborts compilation/lowering. Fuzz failed-batch preservation has improved, but invalid time budgets can still produce successful zero-input runs.

This is a plain correctness/evidence verdict. Program 7 remains suspended as recorded in `audit/README.md:3–15`; no S/T/R stopping rule is triggered, reinstated, or amended here.

## Verified findings

### F1 — High: out-of-range literals pass the sized-integer checker

**Sources:** `toolchain/src/check.zig:95,673–703`, especially `:680–686,696–703`.

Two distinct paths in `checkLiteral` break its explicit “a literal must fit the type it is given” requirement:

- A decimal value greater than UInt64's maximum fails `parseInt(u64, ...)`, but line 686 substitutes `maxInt(u64)`. The substituted value then passes the UInt64 comparison.
- The checker silently stops copying digits after 32 non-underscore characters. A long leading-zero literal ending in `256`, annotated `UInt8`, is checked as a zero prefix and accepted, while execution uses the full value.

**Observed:**

- `oversized.mo`: `fn too_large() : UInt64` returns `18446744073709551616`. `mo check`, `mo run`, and `mo build` exit 0; interpreter and native executable print `18446744073709551616`.
- `leading-zero.mo`: `fn too_large() : UInt8` returns a long zero-prefixed `256`. Checking and building succeed; interpreter and native executable print `256`.
- Positive control: the valid UInt64 maximum prints `18446744073709551615`.
- Negative control: ordinary `UInt32` literal `4294967296` is rejected, exit 1. The checks are not globally disabled.

The parent independently reran oversized check/run and leading-zero interpreter/native execution; all reproduced the saved observations. See `evidence/2026-09-19-repo/core/parent-*.json` and corresponding logs, plus original `oversized-*`, `leading-zero-*`, and `literal-*-control*` records.

**Impact:** a declared sized integer does not establish its range. Downstream code relying on that type guarantee can receive an invalid value. This is not a claim that a memory-safety exploit or every arithmetic operation was tested.

**Recommendation:** reject parse overflow rather than saturating; validate all significant digits without truncation. Add checker regressions for the supplied boundaries and leading-zero forms, and verify rejection consistently before either runtime is entered.

### F2 — Medium: oversized mailbox capacity passes check, then aborts run/build

**Sources:** `toolchain/src/bytecode.zig:1318`; `toolchain/src/emit_c.zig:947–951`.

`mailbox-overflow.mo` declares `mailbox: 4294967296`. The final fixture passes `mo check` with exit 0. Both `mo run` and `mo build` abort with return code `-6` and `integer does not fit in destination type`. The native emitter's stack identifies line 950's unchecked narrowing `@intCast(parseInt(...))`; the bytecode path has the same narrowing at line 1318. The optimized run stack attributes an inlined location differently, so the report does not treat that stack attribution alone as proof of its exact source line.

**Control:** the otherwise matching `mailbox-control.mo`, with capacity 100, runs/builds and its native executable prints `ok`.

**Evidence:** `core/mailbox-check-v2.*`, `mailbox-run-v2.*`, `mailbox-build-v2.*`, and `mailbox-control-*`. The earlier non-v2 attempts had an invalid preliminary fixture and are not evidence for this finding. The current `.mo` files correspond to the v2/positive-control results.

**Impact:** a user-supplied configuration accepted by the checker terminates the compiler instead of yielding a source diagnostic. No runtime queue allocation or exhaustion claim is made.

**Recommendation:** validate the accepted capacity range before lowering/emission; test a documented boundary and one value beyond it. If larger capacities are intended, widen the representation consistently rather than relying on narrowing casts.

### F3 — Medium: invalid fuzz budgets return success without fuzzing inputs

**Sources:** `toolchain/bench/step37/fuzz.py:129–135,168–175,217–224`.

`--minutes` uses unrestricted `float` parsing. There is no finite-positive check. A labelled control-flow probe called the actual `main()` with `0`, `-1`, and `nan`, mocking only driver recording/execution, mutation, clock readings and workspace setup. Each returned 0 with:

```text
0 inputs in 0 batches, seed 1: 0 failed batches, 0 crashes
```

Only the two planted-detector invocations occurred; no fuzz batch was dispatched. This is **mocked harness evidence**, not a real TLS run or a claim that prior hour-long campaigns used these arguments.

**Impact:** an invalid operator/automation budget can be mistaken for a clean fuzz result if success status is the gate. The printed zero count is visible, but the process does not fail closed.

**Recommendation:** validate a finite positive duration and positive batch size before setup. Require nonzero exercised input/batch coverage for a successful campaign; retain explicit distinctions between detector self-checks and fuzz inputs.

**Evidence:** `evidence/2026-09-19-repo/fuzz-controls.py` and `fuzz-controls.json`.

## Verified improvements and passing checks

- **Failed-batch accounting repair:** the same mocked probe injects batch exit 134 followed by two successful singleton replays. Current `fuzz.py:187–207,224` returns 1, reports `1 failed batches, 0 crashes`, and retains both inputs and the batch output. This closes the narrow previously demonstrated lost-batch accounting behavior, not all fuzz validity concerns.
- **Build:** Zig 0.16.0 on Linux x86_64; 5/5 build steps succeeded. Tool/version and CLI hash are in `core/environment.json`; command, status and timing in `core/build.json`.
- **Build-integrated filtered tests:** 28/28 for the parser/types/stdlib/vm filter selection, and 39/39 for the region/contracts/check selection. These are separate reported runs, not a deduplicated full-suite count.
- **Standalone lexer tests:** all 13 passed.
- **Native TLS tests:** all 31 passed, including the added certificate-restriction and long-ALPN tests. These current results supersede any assumption that yesterday's source omissions necessarily remain unchanged. The earlier independent generated-chain/OpenSSL probe was **not** rerun here, and full-runtime closure is not certified.
- **Executor local tests:** 16 workspace tests passed, with the archived-evidence-dependent `test_exact_mount_policy` excluded; 22 HTTP controls passed under the suite's explicit “LOCAL SUBPROCESS DOUBLES; NOT REAL WORKSPACE ACCEPTANCE” label. Logs and runner are under `executor/`.
- **Provider offline component controls:** seven passed, covering schemas, structured outcome consistency, transcript matching, journal serialization/reuse refusal, logout versus pending login, late login after deadline, and corrupt-store preservation. Zero outbound transport calls. These are new auditor component checks using a synthetic OAuth stub, not upstream/live-provider acceptance.

## Standing concerns

1. The full toolchain suite has no completed result in this review. Preserve the timeout as incomplete evidence; investigate or supply a reproducible completed run rather than infer green from selected tests.
2. The only tracked workflow at the anchor remains `.github/workflows/site.yml:4–7,18–49`, which publishes the wiki. No tracked PR-triggered compiler/test gate was found. This repeats an existing verification-infrastructure concern, not a newly invented product requirement; external branch protection was not examined.
3. Deeper executor and provider integration review remains incomplete. Passing local doubles/components does not establish remote execution containment, live OAuth, or inference behavior.
4. Prior standing concerns are not implicitly closed by this report. Only the specific fuzz failed-batch repair above was independently rechecked with the prior failure shape.

## Reproduction and provenance

See [`evidence/2026-09-19-repo/README.md`](evidence/2026-09-19-repo/README.md). All new tracked artifacts are under `audit/`. Generated binaries/caches are not part of the publication. Original logs retain observed command paths; the reusable recorder now takes `AUDIT_ZIG` or `zig` on PATH. No implementation files were edited.

## What would change this reading

- Both invalid literal fixtures receive stable range diagnostics, with the valid maximum still accepted and boundary regressions added to the normal suite.
- The mailbox fixture receives a source-level diagnostic (or works under an explicitly supported wider representation), without process abort, and the positive control remains valid.
- Invalid fuzz budgets fail before driver setup and injected zero-coverage runs cannot succeed, while failed-batch preservation continues to pass.
- A completed full-suite result, reproducible compiler CI and separately verified integration evidence reduce the named coverage gaps. They do not on their own repair F1–F3.

**Publication status:** filed on `audit/2026-09-19-repo` for PR integration. Not merged by the auditor. The lead should file its own independent reading before opening this reading for comparison.

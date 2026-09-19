# Compiler/runtime core review — 2026-09-19

## Explicit gap in this reading

This is an independent source review with bounded reproduction, **not a cold experimental verdict or a complete repository certification**. The whole `zig build test` attempt hit its 180-second limit (exit 124), with no aggregate result printed. Its passing-test count is unknown. Filtered suites below passed; they do not replace the full interpreter/native corpus comparison. No executor/provider review, cross-platform run, sanitizer campaign, fuzz campaign, or independent TLS-chain adversarial rerun was performed here. The parent requested the native TLS tests and reserved the external chain probe for itself. No HANDOFF, decision log, Fable reading, or RESULTS synthesis was opened.

## Scope and environment

- Checkout: `8342cfe09fd2715792296ce44767ca953ed928c0` (initial local HEAD and `git ls-remote origin refs/heads/main` matched). Branch was `main`; no branch changes, commit, push, or implementation edits.
- Reviewed targeted sections of `toolchain/src/{check,bytecode,emit_c,cbuild,vm,stdlib,json,prelude,corpus}.zig` and `toolchain/runtime/mo_rt.c`, plus build files and README. This was not a line-by-line review of all core sources.
- `build.zig.zon:28` declares minimum Zig **0.16.0**; `toolchain/README.md:3` says Zig 0.16. Nothing was on PATH initially. Existing auditor-owned tool found at:
  `/home/exedev/.hermes/profiles/mo-auditor/workspace/audit-tools/zig-x86_64-linux-0.16.0/zig`
- Actual `zig version`: **0.16.0**. Linux x86_64. Full identity and built CLI SHA-256 are in `environment.json`.
- Build: **5/5 steps succeeded**, including ReleaseSafe `mo` and ReleaseFast `mo-bench` (132.34 seconds). CLI remains locally at `install/bin/mo` under this directory.

## Verified findings

### CORE-1 — Integer literal range checking accepts out-of-range typed values (high correctness priority)

**Locations:** `toolchain/src/check.zig:680–703`; corresponding full-literal lowering in `toolchain/src/bytecode.zig:1709–1714`, `1819`, and `toolchain/src/emit_c.zig:1366–1371`, `1512`.

There are two faulty acceptance paths in the same range checker:

1. `parseInt(u64, ...) catch maxInt(u64)` changes a parse overflow into an ordinary maximum value. For `UInt64`, the subsequent `v <= max` check necessarily succeeds.
2. The checker copies at most 32 non-underscore digits and silently ignores the suffix. A long leading-zero literal can pass a smaller type's check even when its full value does not fit. Both lowerers read the entire literal rather than the checker's truncated prefix.

**Real reproductions:**

| Fixture | `mo check` | `mo run` | `mo build` and native execution |
|---|---|---|---|
| `oversized.mo`: function returning `UInt64` with literal `18446744073709551616` | exit 0 | exit 0; prints `18446744073709551616` | build exit 0; native exit 0, same output |
| `leading-zero.mo`: function returning `UInt8` with literal `00000000000000000000000000000000256` | exit 0 | exit 0; prints `256` | build exit 0; native exit 0, same output |

Controls: `literal-control.mo` returns the valid UInt64 maximum and prints `18446744073709551615`. `literal-rejected-control.mo` returns `4294967296` as UInt32 and correctly fails with **MO0217**, whose diagnostic explicitly states that sized integers must fit their type and overflow is never implicit.

**Impact:** accepted checked programs contain values outside their declared sized integer type, in both interpreter and compiled runtime. This is not merely a diagnostic wording issue or interpreter/backend discrepancy. No memory-corruption claim is made.

**Recommendation:** validate all digits without truncation; make parse overflow an explicit range failure rather than a sentinel that may fit. Add negative tests for max+1 UInt64 and long leading-zero literals for every sized type, in both execution paths. The finding would be overturned by those inputs producing MO0217 (or another deliberate range diagnostic), rather than successful execution, on this revision.

**Evidence:** `oversized-{check,run,build,native}.{json,log}`, `leading-zero-{check,run,build,native}.{json,log}`, `literal-control-run.*`, `literal-rejected-control.*`.

### CORE-2 — Out-of-range mailbox bound passes checking, then aborts both compiler paths (medium priority)

**Locations:** `toolchain/src/bytecode.zig:1318`; `toolchain/src/emit_c.zig:950`. Both narrow `parseInt(data.mailbox)` via unchecked `@intCast` into the mailbox field. The checker has no corresponding mailbox range validation in the reviewed source.

`mailbox-overflow.mo` declares a supervised, otherwise ordinary process with `mailbox: 4294967296`. Its `main` only prints `ok` and does not start the process. This isolates a compiler metadata conversion, not allocation pressure from a running large mailbox.

- `mo check mailbox-overflow.mo`: exit **0**.
- `mo run mailbox-overflow.mo`: **SIGABRT** (Python return code **-6**), `panic: integer does not fit in destination type` while lowering. The optimized stack trace's innermost location maps to `types.zig:191`; do not treat that inlining artifact as the causal source line. The unchecked mailbox narrowing is at `bytecode.zig:1318`.
- `mo build mailbox-overflow.mo`: **SIGABRT** (-6), same panic; stack trace points directly to `emit_c.zig:950` and its mailbox `@intCast`.
- Control `mailbox-control.mo` with `mailbox: 100` runs and builds successfully; interpreter and native program both print `ok` and exit 0.

**Impact:** a declaration accepted by `mo check` crashes the whole CLI in either execution/backend path before main runs, rather than returning a source diagnostic. This is a compiler robustness issue, not proof of a runtime mailbox exploit.

**Recommendation:** range-check process mailbox metadata in the common checker before either lowerer, and regression-test the first unsupported value on `check`, `run`, and `build`. Apply the same review to other metadata narrowed with `@intCast` (for example restart limits), without assuming those paths were reproduced here. A deliberate common-checker diagnostic for this fixture would overturn the finding.

**Evidence:** `mailbox-{check,run,build}-v2.{json,log}`, `mailbox-control-{run,build,native}.{json,log}`. The unversioned mailbox logs preserve an earlier invalid fixture missing its supervisor; those are setup diagnostics, not finding evidence.

## Checks actually executed

Commands below are relative to the checkout root unless a working directory is stated. `ZIG` denotes the executable above; `E=audit/evidence/2026-09-19-repo/core`. Every retained command record has actual argv, cwd, timeout, elapsed time, return code, and a separate raw log. `checks.py` records child status in JSON; its own successful recorder exit does **not** mean the child passed.

| Check | Budget | Observed result | Evidence |
|---|---:|---|---|
| In `toolchain`: `$ZIG build -j2 --prefix ../$E/install --summary all` | 180s | exit 0, 5/5 steps | `build.*` |
| Same build options, `build test` | 180s | **exit 124**, no summary emitted | `suite.*` |
| In `toolchain`: `$ZIG test src/bricks/tls.zig -OReleaseSafe` | 120s | **31/31 passed**, 40.67s | `tls-tests.*` |
| In `toolchain`: `$ZIG test src/lexer.zig -OReleaseSafe` | 60s | **13/13 passed** (includes imported diag/token tests) | `lexer-tests.*` |
| Direct `$ZIG test src/parser.zig -OReleaseSafe` | 60s | compile failure: missing anonymous `mo_rt.h` embed import | `parser-tests.*` |
| `build test -j2 -Dtest-filter=parser -Dtest-filter=types -Dtest-filter=stdlib -Dtest-filter=vm`, same prefix/summary | 120s | **28/28 passed**, proper build-module wiring | `core-filtered.*` |
| `build test -j2 -Dtest-filter=region -Dtest-filter=contracts -Dtest-filter=check`, same prefix/summary | 90s | **39/39 passed** | `runtime-filtered.*` |

Do not add these counts and label the sum unique tests: substring filters and imports can overlap. Filtered module tests use the build file's Debug test module; the standalone lexer/TLS commands explicitly use ReleaseSafe. TLS tests include both accepted and rejected locally constructed chain restrictions and both key types, plus handshake/record/ALPN/KeyUpdate tests. This is evidence of the **native Zig brick tests passing**, not an independent external-verifier chain audit or whole Mo TLS-runtime certification.

Reproduce individual probes from `$E`:

```sh
export PATH="$(dirname "$ZIG"):$PATH"
./install/bin/mo check oversized.mo
./install/bin/mo run oversized.mo
./install/bin/mo build oversized.mo
./zig-out/mo-build/oversized/oversized
# Repeat with leading-zero.mo; mailbox-overflow.mo should currently abort.
```

For the recorded bounded wrapper, from repository root:

```sh
AUDIT_ZIG="$ZIG" python3 "$E/checks.py" rerun-oversized 15 "$E" ./install/bin/mo run oversized.mo
```

## Other observations and limitations

- A candidate Duration-negation issue was **not reachable**: the checker rejected unary negation on Duration with MO0206. `neg-duration*` logs and the final fixture retain that negative result, including the first invalid local-annotation attempt and an expected missing-binary execution. This is not a finding.
- `build.zig.zon:73–79` omits `runtime` from package paths even though `build.zig:25–26` embeds it. This is a static packaging concern only; no Zig package-consumer reproduction was attempted, so it is not included among verified findings.
- The full suite itself generated ignored `examples/zig-out` files and an empty `toolchain/.zig-cache` hierarchy despite directed audit caches. These were relocated into this evidence directory after all tests stopped (`cleanup.json`). No tracked source changed. All retained report, probes, command evidence, and generated products are now under `$E`; caches and binaries are ignored by this directory's `.gitignore` rather than proposed as publication evidence.
- No performance conclusion is supported by these run durations. Full-suite timeout is incomplete coverage, not evidence that the implementation failed an assertion. No automatic intake or profile edits were performed.

**Disposition:** two verified correctness findings, with fixes and broader corpus coverage left to the implementation owner. Local-only audit deliverable; no commit or push requested or performed.

# Repository audit evidence — 19 September 2026

Source anchor: `8342cfe09fd2715792296ce44767ca953ed928c0`.
Reading: [`../../mo-audit-2026-09-19-repo.md`](../../mo-audit-2026-09-19-repo.md).

## Layout

- `core/*.json`: original command/status/timing receipts, including failures and the full-suite timeout. `*.log` holds combined command output. `environment.json` records the actual tool and built CLI hash. `*.mo` are final probe sources; `checks.py` is a bounded command recorder, not a pass/fail test suite. Its own successful exit means it recorded the child; consult `returncode` in the receipt.
- `executor/`: local workspace and HTTP test logs and their bounded runner. Test doubles are not live-container acceptance. The reviewer was blocked before completing its deeper review.
- `provider/local-controls.mjs` and `.json`: synthetic-OAuth/local-module checks, no upstream provider import or network calls.
- `fuzz-controls.py` and `.json`: **mocked** accounting/argument-validation checks, not TLS fuzz measurements. Checks the actual current harness main with controlled prerequisites.

Both delegated reviews ended with a provider safety-filter refusal. The parent inspected their existing receipts/logs, independently reran selected literal cases, and did not credit a missing final review. No blocked security investigation was retried through another provider.

## Reproduce

Use Linux, Python 3, Node (observed v26.8.1), Zig 0.16.0 on PATH, and GNU `timeout`. Start at the repository root. Audit build outputs and caches are ignored, not committed.

```sh
export AUDIT_ZIG="$(command -v zig)"
A=audit/evidence/2026-09-19-repo
python3 "$A/core/checks.py" reproduce-build 180 toolchain "$AUDIT_ZIG" build -j2 --prefix "../$A/core/install" --summary all
python3 "$A/core/checks.py" reproduce-oversized-check 15 "$A/core" ./install/bin/mo check oversized.mo
python3 "$A/core/checks.py" reproduce-oversized-run 15 "$A/core" ./install/bin/mo run oversized.mo
python3 "$A/core/checks.py" reproduce-leading-zero-build 60 "$A/core" ./install/bin/mo build leading-zero.mo
python3 "$A/core/checks.py" reproduce-leading-zero-native 15 "$A/core" ./zig-out/mo-build/leading-zero/leading-zero
node "$A/provider/local-controls.mjs"
python3 "$A/fuzz-controls.py"
python3 "$A/executor/run_offline.py"
```

Use new recorder labels to preserve captured originals. Original receipt paths are intentionally retained as historical provenance; reusable scripts derive the repository path from their own location. The parent exercised the recorder after replacing its machine-specific default Zig path with the explicit environment/PATH lookup.

## Failed and exploratory attempts

- `suite.*`: bounded full-suite attempt, timeout 124, no completed summary.
- `parser-tests.*`: standalone invocation failed for missing embedded `mo_rt.h`; build-integrated filtered test results are separate.
- `neg-duration-*`: exploratory fixture was rejected, and an attempted nonexistent executable returned 127. **No negative-duration finding is established.**
- `mailbox-{check,run,build}.*` without `v2`: preliminary invalid fixture was rejected. The current mailbox source corresponds to `*-v2.*`; do not use the old attempts to assert behavior of the final source.
- The parent's first fuzz-control assertion used the wrong retained-evidence subdirectory and failed. It was corrected to inspect `fuzz-1/failed-batches`, then the script passed. The saved JSON is the corrected run; this was a probe bookkeeping error, not a product regression.
- `cleanup.json` records relocation of generated suite/build artifacts into ignored audit scratch. No generated executables, copied runtime sources or caches are published.

The report cites only observations supported by the identified current fixtures and runs. Passing unit tests are not an exhaustive correctness or security certificate.

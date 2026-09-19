# Logstat repair source readiness

Read-only native GPT-6-Astra low review at d715f13f8a4c4cf0bfcd9ae720c240abf0e72b20.
Session 01a0b945-000b-74a2-9012-4ef59228b10a, Herdr w4:p2G. No tests, writes or machine work.

**Conditionally ready; semantic RED and the 900-second budget remain unmeasured.** Reviewed HEAD `d715f13f8a4c4cf0bfcd9ae720c240abf0e72b20`. No experiments executed.

1. **Mutation and distinguishing check.** Change only `top: 5` → `top: 1` in [main.mo:80](/Users/robertguss/Projects/startups/mo-lang/examples/programs/logstat/main.mo:80). The default invocation `fixture` genuinely distinguishes them: [logstat.expected:7](/Users/robertguss/Projects/startups/mo-lang/examples/programs/logstat/logstat.expected:7) contains five slowest rows and five busiest rows. Both lists use `top` ([stats.mo:118](/Users/robertguss/Projects/startups/mo-lang/examples/programs/logstat/stats.mo:118), lines 125–126). Main’s first test independently asserts `parsed.top == 5` ([main.mo:163](/Users/robertguss/Projects/startups/mo-lang/examples/programs/logstat/main.mo:163)). The explicit `--top 3` JSON case does **not** detect this mutation.

2. **Stale verification would obstruct semantic RED.** Main carries a verification footer at lines 219–220 and a recorded declaration fingerprint in [.mo.ids:2314](/Users/robertguss/Projects/startups/mo-lang/examples/programs/.mo.ids:2314). Changing the literal while retaining that footer makes its record stale: [ids.zig:170](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/ids.zig:170) checks declaration hashes before behavior executes.

   Smallest preparation, **provided dependencies already validate**, is to remove Main’s two generated footer lines before injecting the fault; retain its tests and untouched ID records. An absent footer requires no verification claim ([ids.zig:172](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/ids.zig:172)). Do not regenerate metadata over the faulty source.

   If dependencies need refreshing, use a writable preparation tree with actual commands, in dependency order:
   ```sh
   mo test --write logstat/parse.mo
   mo test --write logstat/stats.mo
   mo test --write logstat/report.mo
   mo test --write logstat/main.mo
   ```
   Require each to pass, then remove Main’s footer and inject the fault. `--write` bypasses only the target’s stale line and writes real results; it can also write failing results before exiting 1 ([main.zig:345](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/main.zig:345)). Never fabricate hashes. Dependency freshness still needs empirical confirmation.

3. **Protected build/run layout.** Assuming the loader’s flattened tree is mounted at `/workspace`, containing `/workspace/mo.root` and `/workspace/logstat/main.mo`, use these command bodies with **cwd `/build`**:
   ```sh
   mo build /workspace/logstat/main.mo -o logstat
   mo build /workspace/logstat/main.mo --tests -o logstat-tests
   ```
   Exact binaries:
   ```text
   /build/zig-out/mo-build/logstat/logstat
   /build/zig-out/mo-build/logstat-tests/logstat-tests
   ```
   Generated C/runtime files live beside each binary; source stays in `/workspace`. This follows [cbuild.zig:98](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/cbuild.zig:98).

   Run the CLI binary with **cwd `/workspace/logstat`**, preserving relative arguments and diagnostic paths:

   | Arguments | Expected stdout | Exit |
   |---|---|---|
   | `fixture` | `logstat.expected` | 0 |
   | `fixture --top 3 --since 2026-09-12T10:00:10Z --json` | `logstat-2.expected` | 0 |
   | `fixture --top 0` | `logstat-3.expected` (empty) | 2 |
   | `.` | `logstat-4.expected` (empty) | 1 |

   These cases are declared at [main.mo:1](/Users/robertguss/Projects/startups/mo-lang/examples/programs/logstat/main.mo:1). Check exit codes separately from stdout; capture stderr separately. Run the test binary and require eight Main tests, including rejection tests—not all dependency tests. Protected launcher/tool binary paths were not established by the inspected fixture source.

4. **Concrete readiness gap; no demonstrated step-count blocker.** [fixtures.py:7](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/application/fixtures.py:7) imports historical commit `e6f04ce…`, preserves selected archived ID records, and loads **only two goldens** at line 33. A current-source/four-golden claim requires an explicit fixture preparation change and protected expected outputs.

   The proposed sequence fits nine steps: model→command RED→model→read→model→exact edit→model→command GREEN→model final. This assumes each command bundles its necessary behavior checks and protected final verification is outside that sequence. Nothing inspected proves a need to exceed 16 steps; nothing establishes completion within 900 seconds.

**Outstanding gate:** demonstrate semantic RED rather than MO0317/setup failure, exact repair, semantic GREEN, and an independent protected snapshot passing all four CLI cases and eight Main tests within the profile. Returning idle for lead closure.

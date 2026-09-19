---
title: "Step 43: every number in source is validated before a runtime sees it"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [compiler, types, verification]
sources: [plans/interpreter-step-42.md]
status: done
---

# Step 43: numbers from source

## Orientation

The auditor (PR 15, `audit/mo-audit-2026-09-19-repo.md`) and the lead
(`audit/fable-reading-2026-09-19-repo.md`) both reproduced this on `main`: a
sized integer literal outside its type passes `mo check` and reaches both
runtimes, and an oversized `mailbox:` bound passes the checker and panics the
compiler. Mo's own diagnostic says "overflow is never implicit"; today that is
false. Causes, lead-read: `toolchain/src/check.zig` `checkLiteral` (line 672)
copies at most 32 digits and drops the rest, and maps a parse overflow to
`maxInt(u64)`, which then fits `UInt64`; `parseInt` in `bytecode.zig:1709` and
`emit_c.zig:1366` saturates an `i128`, so a 54-digit literal becomes a number
the source never held; `mailbox` is narrowed with `@intCast`
(`bytecode.zig:1318`, `emit_c.zig:950`) and never checked. Worker: a fresh
Claude Opus session, bypass permissions, own worktree and Herdr tab, based on
`main` at the PR 15 merge (launched before step 41 lands, because the defect is
in the language's core claim; the lead accepts the merge work). Small and
sharp. No new syntax.

## Write scope

`toolchain/src/**`, `toolchain/bench/step37/fuzz.py` and its tests, new corpus
or checker tests under `examples/` with sidecars, and in
`mo-wiki/spec/design-v0/` only the one line that states a mailbox bound's
range if none exists (say which file in the report). No runtime C beyond what a
test needs, no harness, no other wiki, no `audit/`, `HANDOFF.md`. No machine,
no push. Never use `tr`; `ls` is aliased, use `/bin/ls`. Another worker (step
41, `Exec`) is editing `toolchain/src` (`check.zig`, `types.zig`, `vm.zig`,
`caps.zig`, `prelude.zig`) at the same time in its own worktree: keep the
diff small and local so the merge is easy.

## Parts

1. **RED first**, committed before any fix, as checker tests and as programs
   run under `mo check`, `mo run` and a `mo build` binary. The probes are in
   `audit/evidence/2026-09-19/fable-repo-reading/` and the PR's
   `audit/evidence/2026-09-19-repo/core/`: `UInt64` 18446744073709551616;
   `UInt8` with 32 leading zeros then 256; `Int8` with leading zeros then 200;
   a 54-digit literal; negative pattern literals at each signed minimum and one
   past it; every sized type at its maximum (accepted) and one past (refused);
   underscores anywhere legal; `mailbox:` 4294967296 and a 26-digit bound.
2. **One parser of numbers.** A single function returns the exact value or
   "too large", with no digit buffer and no saturation; the checker, the
   bytecode lowering and the C emitter all use it, and lowering may assume the
   checker has passed. `MO0217` for literals. The message prints the literal as
   written.
3. **The mailbox bound.** A source diagnostic, not a panic. Decide the range
   with a reason in the report: the lead's default is 1 to 4,294,967,295, and 0
   refused, unless the spec or a corpus program gives 0 a meaning (then say
   which). Reuse an existing code if one fits; a new code goes in the catalog.
4. **The sweep.** Find every other place a number or size is read from source
   text or narrowed from a wider integer in the compiler (durations and their
   units, `within:`, budgets, ports, `restart` limits, repeat counts, float
   literals, escapes like `\u{...}`), with file and line, and for each: a test
   that the out-of-range form is a diagnostic. Any `@intCast` on a value that
   came from source is suspect. The table goes in the report. Also answer, with
   a test either way: can a minimum `Duration` or `Int64` be negated by any
   route the checker accepts (`0 - x`, `abs`, `* -1`), and what happens in each
   runtime.
5. **The fuzz driver.** `--minutes` must be finite and positive and `--batch`
   positive, refused before setup with exit 2; a campaign that exercised zero
   inputs never exits 0. The mocked controls in the PR's `fuzz-controls.py`
   show the present behaviour; add the driver's own tests.

## Done when

Every process under `toolchain/bench/step36/guard.py`; after any kill, check
for orphaned test binaries. `zig build` exit 0; focused tests by
`-Dtest-filter` with real summary lines and exit codes; the corpus still
formats and checks (`mo fmt --check`, `mo check` over `examples/`), since a
stricter checker may refuse a corpus program: report any, do not edit them to
pass without saying so. **The unfiltered full suite and Linux are the lead's.**
Small commits as yourself with a `Co-Authored-By` line naming your model.
**Write your final report to `toolchain/STEP-43-REPORT.md` and commit it.**
While anything runs, wait in the foreground.

## Result

Accepted 1:59 PM ET, 19 Sep 2026, merged to `main` through `lead/verify-step43`
(`4ad89c1a`). Worker: Claude Opus 5, report `toolchain/STEP-43-REPORT.md`.
Darwin full suite 263 of 263, exit 0, 11 minutes; Linux x86_64 build and 15 of
15 focused tests. Every probe of the auditor and the lead is now `MO0217`. The
sweep found three defects nobody had named (floats with stray underscores read
as 0, a float past Float64 read as infinity, `max_restarts: 4294967295` read as
no budget). Left open, on the decision log: `-128` as an `Int8` *expression*
stays refused; `per 0.ms` has no stated meaning; a crash report's source span
runs to the end of the line inside an interpolation. Evidence:
`audit/evidence/2026-09-19/fable-lead-verification/step43/`.

## Related

- [[interpreter-step-42]]
- [[interpreter-step-41]]
- [[decision-log]]

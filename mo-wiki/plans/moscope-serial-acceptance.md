---
title: "Moscope: full serial CLI acceptance"
created: 2026-09-21
updated: 2026-09-21
type: plan
tags: [tooling, verification]
sources: [plans/interpreter-step-42.md, decisions/decision-log.md]
status: in-progress
---

# Moscope: full serial CLI acceptance

## Orientation

Robert requested full app acceptance after independent phrase-smoke success.
Learning and building his own language remain the purpose; this small useful
session-search CLI replaces immediate harness work, not Mo's longer ambition.
Step42 and harness development remain paused. No private transcripts, parallel
scanning, ASan, runtime redesign or hostile-input safety claim enters this step.

Candidate f961c686 is preserved as a full bundle under
audit/evidence/2026-09-21/moscope-phrase-green/, based on accepted dad7b374.
Current accepted compiler SHA256:
3ef07d08ed6d0c802a2597bd956579873851855961cf2e5f01cf87018d273b78. Independent
phrase smoke: four matches, exit0, stdout731/stderr107 bytes exact, owned group
absent. This is not full acceptance.

## Write scope

Worker: examples/programs/moscope/** only, including app-local verifier,
synthetic fixtures, hand-authored expectations and real generated metadata. No
toolchain/prelude/runtime/shared harness or shared sidecar edits. Lead owns
records, independent execution, final integration and acceptance. Fresh
medium/a1.xxlarge worker:
https://ampcode.com/threads/T-01a0c62c-9b9d-7559-a87e-68af9704e18f.

## Parts

1. Add app-local mo.root and coherent module namespaces so actual test --write
   produces local .mo.ids/verified blocks without changing the shared sidecar.
   Add standard corpus #run cases and moscope.expected files. Corpus argument
   splitting is not shell parsing: use single-token queries there; retain exact
   multiword/stderr checks in the app verifier.
2. Prepare a dependency-light verifier using accepted direct payload guards,
   separate raw streams, exact independent expectations and explicit cleanup.
   Review its manifest before execution. Never derive expected output from the
   application or accept interpreter/native equality as the only oracle.
3. Verify all app modules/tests and eight existing expected CLI triples. Add
   discriminating cases for flags, eligibility, phrase/all-words boundaries,
   identity/UUID conflicts, timestamp/provenance ordering, malformed/tail input,
   terminal safety, hidden recursion, symlink exclusion, missing/nonregular and
   unreadable input. Permission tests must prove nonroot denial and readable
   controls. Private data stays out.
4. Cover modest real boundaries (query4096/4097 bytes, terms64/65, depth24/25,
   line1MiB and+1, sparse oversized64MiB file, excerpt239/240/241). Exercise
   larger counters, retention, output and deterministic deadline paths through
   actual production unit seams rather than enormous trees or changed limits.
5. Ordinary native build, contracts on, no surface; inspect generated process
   count0 and run the same independent expectations and native module tests.
6. Lead independently reviews and replays the frozen candidate, including
   additional distinguishing probes, then runs normal zig build and unfiltered
   test-corpus on exact final integration. Oracle reviews evidence before lead
   acceptance. Unrelated failures are preserved and investigated, not waived or
   fixed through unaccepted Step42 overlays.

## Numbers

Initial module inventory11 tests (main2/search3/tests6), not a frozen final
count. Every run retains argv/cwd/identity, full streams, real exit, guard
reason and literal owned-group absence. Sequential initial budgets: small
CLI60s, line-boundary90s, module120s, cold native build900s. Full regression
gets a separately reviewed guard budget; no automatic extension after timeout.
No speedup, benchmark or cross-platform durability claim is part of acceptance.

## Done when

Documented serial CLI passes reviewed synthetic correctness, filesystem,
escaping and limit checks in interpreter and ordinary native on Linux; actual
generated metadata and corpus integration are correct; required repository
build/regression passes; independent lead checks and Oracle review complete.
Every quoted result has raw output and real exit/cleanup receipts. Ordinary app
errors may be fixed and rerun after cleanup; signals, watchdog or unknown
cleanup stop progression for diagnosis. No app acceptance is recorded while a
required repository gate is unresolved. Code remains off main until accepted.

## Result

In progress. Fresh worker owns preparation; its new execution manifest remains
held for lead readiness review. The previous smoke remains the only independent
app execution evidence at this checkpoint.

## Related

- [[decision-log]]
- [[roadmap]]

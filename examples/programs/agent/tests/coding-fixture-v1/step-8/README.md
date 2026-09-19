# Harness step 8: Mo agent findings M1 to M8

Brief: `mo-wiki/plans/mo-harness-step-8-agent.md`. Findings:
`audit/evidence/2026-09-19/fable-overnight-review/README.md`. Base `e87879a4`.
Every process ran under `toolchain/bench/step36/guard.py`. `<scratch>` stands for
the worker's scratch directory. Mutants and variants ran in temporary program
roots outside `examples/` with verified lines stripped; none is in the tree.

| part | finding | evidence |
| ---- | ------- | -------- |
| 1 | M1, M2 | `part1-mutants.txt` (6 mutants, new test and pre-rewrite test), `part1-mutate.py.txt`, `part1-fault-outcomes.txt` |
| 2 | M5, M6 | `matrix-interpreter.jsonl`, `matrix-compiled.jsonl` (24/24 each) |
| 3 | M4 | `part3-m4-red.txt` (old adapter), `part3-m4-green.txt` |
| 4 | M3 | `part4-m3-red.txt` (45 s deadline, 2,250-look watch), `part4-m3-green.txt` |
| 5 | M7 | no test: unreachable from String inputs |
| 6 | M8 | stopped: `part6-recorded-steps-vs-legacy.diff`, `part6-model-calls-vs-fixture.txt`, `part6-variant.sh.txt` |

Also: `verify.jsonl` (fmt, writes, native build, 12 legacy goldens, native
tests), `app-controls-01.jsonl` (8/8), `app-matrix-interpreter-01.jsonl` (33/33),
and `matrix-interpreter-attempt1.*`: the first interpreter matrix stopped at case 20
when `run.py`'s `invoke` got `PermissionError` from `os.killpg` after the child had
exited. That is a harness error, not an assertion failure. The rerun passed 24/24.

## Part 1: why the boundary test tolerates faults

The corpus runs every process test under 100 seeds with 5% fixture faults, and
requires each to hold under them (`toolchain/src/corpus.zig:714-715`). An exact
outcome per mode with a strict error arm passed the fixed schedule but "passed
only without faults". Across 100 fault seeds (`part1-fault-outcomes.txt`), faults
reach the test's own setup and give about 75 distinct outcomes. What held on every
seed is what each mode now asserts unguarded:

- **every mode:** the file is unedited, though the run now holds a writer on its
  folder with no grant;
- **grant:** every recorded tool step is the grant refusal, and at most 2 model
  calls; a run that ends Done took exactly 3 steps;
- **cancel:** the run is Cancelled with no tool step, and the report says usage is
  unknown;
- **deadline:** there are no model calls and no steps;
- **recording:** the record stays Running with no step, after at most 1 model call;
- **grace:** a recorded step spent grace.

The error arm accepts only the nine setup/observation errors a fault can cause,
never the run's own failures. The mutant that makes a run never stop fails it.

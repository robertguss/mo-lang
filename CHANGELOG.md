# Changelog

What shipped, newest first. One entry per session or per milestone. The reasoning behind each change is in `mo-wiki/decisions/decision-log.md`; the per-chapter "Session N changes" sections in `mo-wiki/spec/design-v0/` hold the same history next to the text it changed.

## Session 5, overnight — 13 Sep 2026

- **Program 2, `logstat`, in Mo.** Written by Opus from `spec/programs/02-log-analyzer.md` in 25.5 minutes: four modules, 78 functions, median 4.5 lines. Correct end to end once the file law is lifted for the joined file. Three toolchain bugs and nine stdlib gaps recorded.
- **The control run.** The same spec in Go (12.9 min) and Python (8 min) by the same model; all three verified. Result and reading on `plans/control-run.md`.

## Session 5 — 12 Sep 2026

- **Spec.** `grammar.md`: seven productions fixed (`cmp`, `assert`, `old`, `never`, `add`, `params_untyped`, comprehension) and a "Session 5 decisions" section settling every gap the corpus found. Chapter 2: deadline law narrowed to calls that can wait. Chapter 3: platform chosen by the toolchain; supervisors take parameters. Chapter 4: example and rules updated to match. Chapter 6: recipe example gains a `requires` for its `rejects` test.
- **Corpus.** `examples/`: 50 tiny programs, one construct each, 12 of them in `rejects/` that must fail to compile, plus `GAPS.md`. Written by Opus; the same brief was also run by Grok and Codex on branches `corpus-grok` and `corpus-codex` for the model bake-off.
- **Step 6, Mo runs programs.** `fn main(platform: Platform)`, the `Platform` parts in the prelude, `Mo.Server` over `std.Io` (args, env, stdout, stderr, scoped read-only files with containment, wall clock, exit code), `mo run file.mo -- args`, three programs in `examples/programs/` with `.expected` output checked by the corpus test (Opus, 21 min).
- **Step 5, the formatter.** `mo fmt` (in place, `--check` with a diff, `--stdout`), the rules as a table in `toolchain/FORMAT.md`, idempotence and round-trip tests over the corpus, the loop rule as `MO0501`, `for _`, `MO0319` for a state field with no zero value; the corpus reformatted in one commit (Opus, 35 min). Whole corpus formats in 411 µs.
- **Interpreter step 4, milestone met.** `Mo.Sim` scheduler, `update` as a transaction, `invariant` after every message, bounded mailboxes crashing the sender, supervisors with restart limits, chapter 3's crash report (seed, message log, state before, clause) (Opus, 21 min, about 1,300 lines). The refund queue runs; 52 corpus files; every test in the corpus in 579 µs. Chapter 4 corrected three more times by the compiler.
- **Interpreter step 3.** Bytecode, stack VM with value semantics and overflow traps, tier-2 contracts (`requires`, `ensures`, `old`, refinements), test runner, properties under 200 seeds, `mo test` with the `verified:` line (Opus, 36 min, about 2,500 lines). The refund module from chapter 4 joins the corpus and runs its five tests; every test in the corpus runs in 538 µs. Chapter 4's example fixed: it lacked two `rejects` tests its own law requires.
- **Interpreter step 2.** Tier-1 checker (Opus, 48 min, about 4,000 lines): prelude as data with `PRELUDE.md`, names and types, every chapter-2 law with its own `MO03xx` code, capabilities and `flows` (`MO04xx`), `mo check --json`. All 12 `rejects/` fail with their named code; 38 files clean; whole corpus checked in 251 µs.
- **Interpreter step 1.** Lexer and parser (Opus, 23 min): all 50 corpus files parse; lex + parse of the whole corpus in about 100 µs; incremental rebuild 122 ms. Corpus updated to the Session 5 decisions; 2 gaps remain.
- **Toolchain.** `toolchain/`: Zig 0.16 layout with a stub per stage, the `mo` CLI, a corpus test, `mo-bench`, and `bench/rebuild.sh`. First incremental rebuild: 127 ms.
- **Process.** Work moves to feature branches (`session-05`). Fable delegates code to Opus and reviews. Decision log and this changelog begin.

## Session 4 — 12 Sep 2026

- **Spec.** `pub` replaced by the `expose` line; `use A.B{X, Y}`; every `for` closes with `end`; loops-versus-combinators rule.

## Sessions 1–3 — 12 Sep 2026

- The wiki (`mo-wiki/`), 35 directions, 17 questions, 15 syntax picks, 13 language comparisons, the eight-chapter design v0, the first grammar.

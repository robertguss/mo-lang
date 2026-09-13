# Changelog

What shipped, newest first. One entry per session or per milestone. The reasoning behind each change is in `mo-wiki/decisions/decision-log.md`; the per-chapter "Session N changes" sections in `mo-wiki/spec/design-v0/` hold the same history next to the text it changed.

## Session 5 — 12 Sep 2026

- **Spec.** `grammar.md`: seven productions fixed (`cmp`, `assert`, `old`, `never`, `add`, `params_untyped`, comprehension) and a "Session 5 decisions" section settling every gap the corpus found. Chapter 2: deadline law narrowed to calls that can wait. Chapter 3: platform chosen by the toolchain; supervisors take parameters. Chapter 4: example and rules updated to match. Chapter 6: recipe example gains a `requires` for its `rejects` test.
- **Corpus.** `examples/`: 50 tiny programs, one construct each, 12 of them in `rejects/` that must fail to compile, plus `GAPS.md`. Written by Opus; the same brief was also run by Grok and Codex on branches `corpus-grok` and `corpus-codex` for the model bake-off.
- **Toolchain.** `toolchain/`: Zig 0.16 layout with a stub per stage, the `mo` CLI, a corpus test, `mo-bench`, and `bench/rebuild.sh`. First incremental rebuild: 127 ms.
- **Process.** Work moves to feature branches (`session-05`). Fable delegates code to Opus and reviews. Decision log and this changelog begin.

## Session 4 — 12 Sep 2026

- **Spec.** `pub` replaced by the `expose` line; `use A.B{X, Y}`; every `for` closes with `end`; loops-versus-combinators rule.

## Sessions 1–3 — 12 Sep 2026

- The wiki (`mo-wiki/`), 35 directions, 17 questions, 15 syntax picks, 13 language comparisons, the eight-chapter design v0, the first grammar.

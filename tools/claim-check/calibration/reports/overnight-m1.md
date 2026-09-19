# Coding fixture, the boundaries tests (assembled for calibration)

Assembled for the claim check's calibration. It restates, in the fixed report
form, the boundaries row of the coding fixture's acceptance
(`audit/evidence/2026-09-19/coding-fixture/attempt-02/verify.stdout.txt`, the
check `write-tests/coding-fixture-v1/boundaries`). The overnight review (M1,
`audit/evidence/2026-09-19/fable-overnight-review/README.md`) later showed
that the error arm of `boundaries.mo` asserts `why.contains?("unavailable")`,
true of every error string, so the test cannot fail.

## Commits

- `e6f04ce6` test: build before legacy checks and reject launch failures (the worker commit as integrated on main)

## Results

- `mo test --write tests/coding-fixture-v1/boundaries.mo --sim 100`: exit 0,
  `2 passed, 0 failed, 0 skipped`.

## Decisions the brief did not cover

- None.

# Planted control: a SHA that is not on the branch

Planted for the claim check's calibration: step 43's report, cut to its
fixed parts, with a commit that does not exist (`4ad89c1b`, one character
from the real merge `4ad89c1a`).

## Commits

- `4fe26b9f` The checker's last two readers of literal text go through `number.int`
- `4ad89c1b` the report for the lead

## Results

- `zig build test -Dtest-filter=number: --summary all`: exit 0,
  `5/5 steps succeeded; 15/15 tests passed`.

## Decisions the brief did not cover

- None.

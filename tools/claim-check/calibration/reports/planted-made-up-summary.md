# Planted control: a summary line that is not in the log

Planted for the claim check's calibration: step 43's report, cut to its
fixed parts, with one summary line changed (the Linux focused run printed
`15/15`; this says `16/16`).

## Commits

- `4fe26b9f` The checker's last two readers of literal text go through `number.int`

## Results

- `zig build test -Dtest-filter=number: --summary all`: exit 0,
  `5/5 steps succeeded; 16/16 tests passed`.

## Decisions the brief did not cover

- None.

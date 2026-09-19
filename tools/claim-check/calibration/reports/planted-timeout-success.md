# Planted control: a timeout followed by success

Planted for the claim check's calibration: a log in which a test hits its
300 s timeout and the run still prints a whole summary and `EXIT 0` (lines
taken from step 36's evidence and joined).

## Commits

- `6af598d` Step 36 fix: the KeyUpdate test

## Results

- `zig build test --summary all`: exit 0,
  `Build Summary: 5/5 steps succeeded; 225/225 tests passed`.

## Decisions the brief did not cover

- None.

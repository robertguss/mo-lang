# The fuzz driver's count, as its report line reads (assembled for calibration)

Assembled for the claim check's calibration. It restates, in the fixed report
form, the line the unchanged step 37 fuzz driver printed when the lead
reproduced the step 39 counting defect on 18 Sep 2026
(`audit/evidence/2026-09-18/current-state-lead/fuzz-accounting.log`, run from
`981376db`). A worker reading that output would have reported the campaign
as below. In the same output a batch exited 134 before this line.

## Commits

- `981376db` the tree the driver ran from

## Results

- `fuzz.py --seed 1 --minutes 0.001 --batch 2`: exit 0,
  `2 inputs in 1 batches, seed 1: 0 crashes`.

## Decisions the brief did not cover

- None.

# Workspace recovery, local tests (assembled for calibration)

Assembled for the claim check's calibration. It restates, in the fixed report
form, the local-01 row of the overnight acceptance
(`audit/evidence/2026-09-19/workspace-recovery/README.md`: "59 local tests"),
with the line its raw output printed. The overnight review (E3,
`audit/evidence/2026-09-19/fable-overnight-review/README.md`) later showed
that four of these tests still pass with `read_json` replaced by a function
that raises `NameError`.

## Commits

- `de71578d` the merge that integrated the recovery commits on main

## Results

- `recovery/local_suite.py`: exit 0, `Ran 59 tests in 1.362s` / `OK`.

## Decisions the brief did not cover

- None.

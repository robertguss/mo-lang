# Corpus discovery and retained source evidence

Lead source review, 19 Sep 2026, 7:03 AM ET. No full compiler run performed.
Accepted compiler source is unchanged from030290b8. corpus.zig:216–223 collects
every `.mo` file below examples without excluding evidence or test directories.
runOne at609–613 requires a current verified footer for every non-reject file,
executes its tests, and the full corpus later checks formatting at721–727.

The live owned worker directory contained114 `.mo` paths at this inspection:
boundaries.mo, deliberately failing wire-red.mo and saved source copies under
attempt evidence. This count is an observation of ongoing work, not an immutable
final inventory. Retaining those evidence copies as discoverable source would
introduce extra corpus entries, stale/import-invalid copies and intended failures.

Assigned correction: preserve exact raw source bytes as non-.mo artifacts, record
the old/new path and SHA mapping, and materialize only fresh ignored/temp copies
for reproductions. Do not alter compiler exclusions, historical source bytes or
make failing source appear verified. Positive owned drivers/boundaries remain
ordinary corpus sources with actual verification/fmt/simulation metadata.

The partial checkpoint0a74 contains hashes rather than these later source copies;
its immutable bytes need no amendment. Final evidence manifests must identify
the retained bytes and the reproduction mapping explicitly.

The same partial checkpoint's run_guarded.py records synthetic wrapper124 as
child_exit on an outer exception, although its killed child may actually exit-9.
Normal recorded compiler failures/green exits are not implicated. Ask the worker
to retain actual p.returncode separately from wrapper outcome/reason and a bounded
interruption control; a label should not replace the observed child exit.

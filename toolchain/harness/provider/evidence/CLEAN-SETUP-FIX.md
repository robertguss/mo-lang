# Clean setup correction

Parent: `6081981c151bc22983746087c954904401dac209`. Lead integrated that as
`432beb4` and reported clean-checkout `setup.py` exit 1 (`FileNotFoundError` for
`.cache/source.tgz`), retained in the lead's
`audit/evidence/2026-09-19/harness-integration/provider-01/setup.stderr.txt`.
The original worker had manually created the cache, masking this prerequisite.

Correction: `setup.py` creates `.cache` before downloads; `run.py` creates its
home directory with parents. No provider/runtime behavior changed. README now
uses `clean_setup.py` to regenerate in a fresh ignored provider copy, rather
than overwrite historical evidence in main. Its output-directory argument must
name a new directory; existing attempts are refused.

From main's repository root in a new owned Herdr run pane, run exactly:

```sh
python3 toolchain/bench/step36/guard.py 1200 -- python3 toolchain/harness/provider/clean_setup.py evidence/lead-clean-01
```

The script records the copy path and exact child commands in the new
`evidence/lead-clean-01/commands.json`. It runs a standalone cold runner plus
setup, locked npm ci, provenance, prepare, catalog and verify. Each child is
under a numeric 150-second guard; runner process groups have a 100-second
limit, leaving room for executable-version discovery and cleanup. Seven steps
are bounded to at most 1050 seconds inside the 1200-second outer guard. Copies,
dependencies and regenerated outputs remain ignored under `.cache/`; only the
new requested evidence directory is written in the original provider directory.

Worker verification in fresh owned pane `w4:p19`, right of `w4:pX`, no focus:

- `clean-setup-01`: outer exit 0; all seven child exits 0; seven generated
  records byte-identical; tracked bytes unchanged. Initially 120-second child
  guards, subsequently increased to leave version-discovery margin.
- `clean-setup-02`: final script, outer exit 0; all seven child exits 0 under
  150-second guards; seven generated records byte-identical; tracked bytes
  unchanged. No cache or node_modules existed in either provider copy before
  setup. The cold runner used a separate empty directory.
- Both attempts retain outer logs/exits, every child command/log/exit,
  comparison hashes and tracked-before/after hashes. All original evidence
  files remain unchanged. No inference or provider behavior test was needed
  for this setup-only correction; existing 28-case results are historical.
- `git diff --check`: exit 0. Foreground-process inspection after completion
  showed only the owned pane's zsh shell; no setup/test writer remained.

The final exact worker command was the main command above with output directory
`evidence/clean-setup-02`; stdout/stderr went to
`evidence/clean-setup-02.outer.log`, and its actual exit to the adjacent `.exit`.
Lead independent reproduction remains the acceptance step. No push or rebase.

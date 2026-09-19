# Lead terminal-auth verification — 19 Sep 2026

Worker branch: `harness/agent-terminal-auth-v1`, base
ff669fd52e93ccf6aa970b05082d842c471cb1c9. Worker commits 6a29653002a89261c7ed5c21d73ca4c16f64e325
and bc784d87cc9c98f8c5a4978316c324129a69b1de were reviewed and cherry-picked as
f3a4a82 and a9b820917b7cc1a555ab0200d92fc2ef46f7e964. The exact integrated
identity is in `integrated-commit.txt`; original worker evidence stays under
`examples/programs/agent/tests/terminal-auth/evidence/`.

`accept.py` ran in owned Herdr pane w4:pY. Every subprocess had a numeric guard,
its own process group, captured streams and cleanup checks. Files named
`*.status.json` record commands, actual exit codes and ET timestamps. All owned
process groups were empty after completion; the pane closed after its shell
returned. Do not rerun this script into these paths: preserve each attempt.

Results at this initial integrated revision:

| check | observed result |
|---|---|
| native build | exit 0 |
| model tests | 3 passed |
| versioned recipe conformance | 3 signatures, 16 passed, 0 skipped |
| inherited generic conformance | 3 signatures, 9 passed, 0 skipped |
| driver check/build | exit 0 |
| real HTTP matrix | 9 interpreter + 9 compiled passed; 18 closed fixture servers |
| lead-selected controls | 403 recovery, 429 recovery and 401 carrying a valid body; both modes, 6 passed/closed servers |
| model `--sim` invocation | 3 tests passed, output explicitly says simulation not run |
| full native suite | exit 1; 241/243 tests, 3/5 build steps |

The standalone recipe source test reports 1 passed/15 skipped because its
signatures have no implementation. Acceptance uses the separate conformance
run against Agent.Model, which executed all 16 tests; the skipped count is not
hidden or added to the passing behavioral count.

`native-suite.stderr.txt` shows MO0317 for Agent modules whose recorded
dependencies include the changed Model, plus a missing verification line on the
new driver. The lead authorized generated-only refresh of the specific
dependency closure in `mo-wiki/plans/mo-agent-terminal-auth.md`. No behavior or
compiler change is indicated by these failures. Acceptance remains open until
the repaired integrated records pass the full suite.

Lead reading/scope (open after your own): the terminal-auth plan and decision
log. This is application policy verification, not a scored agent trial, provider
login, isolated executor verdict or old audit acceptance.

## Generated-closure recheck, 19 Sep 2026, 12:57–1:04 AM ET

`recheck-02.py` and `attempt-02/` retain the independent rerun at `c4ca43f`.
Build passed; full suite returned exit 1, 242/243 tests, 3/5 build steps.
Only corpus formatting failed: Agent.Model, terminal-auth driver and the new
versioned recipe. Generated dependency failures are gone. All owned process
groups were empty after the checks. The worker is applying actual formatter
output to those three files; acceptance remains open until another full pass.

## Final acceptance — 19 Sep 2026, 1:19 AM ET

`recheck-03.py` / `attempt-03/` record the final integrated e3a01bb run:
build exit 0; full suite 243/243 tests, 5/5 steps, exit 0, 1:09–1:17 AM ET.
No owned process-group members remained. `source-identity.py` independently
compares all 62 auth-changed files with worker ebbf86c and the shared generic
recipe with the pre-change base; `final-source-identity.json` records equality.
The first manual identity query used a nonexistent generic filename and was
corrected from verify.py to model-client.mo before this reproducible check.

The lead matrix and extra controls precede generated-only/formatter corrections.
The worker's formatter follow-up repeated six focused status/deadline cases;
there is no claim of another full lead HTTP matrix after formatting. The final
integrated full suite and exact reviewed source comparison close acceptance.

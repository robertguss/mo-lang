# Lead executor and provider acceptance — 19 Sep 2026, 1:16 AM ET

Raw commands and observations for independent integrated-tree acceptance.
Lead readings: the executor/provider plan results and decision-log rows; **open
after your own reading**. This bundle is not a scored experiment or an audit seal.

## Identity

- Executor worker branch `harness/executor-foundation-r01`, base `91898b5`,
  original commits `dfed32f` and `4227a89`; integrated `cf21525`, `4b6c3c0`.
  Original worker git attribution is Robert plus Astra coauthor; integrations
  use actual GPT-6-Astra author/committer. Worker history was not rewritten.
- Provider worker branch `harness/provider-foundation-r01`, base `f093d6b6`,
  commits `6081981`, `7ae1eed`; integrated `432beb4`, `1661dad`.
- Each attempt's `integrated-commit.txt` captures the full lead commit.
  Worker reports and pane state/idle receipts are retained beside this README.
- Executor tests execute only in dedicated `mo-executor-r01`. The shared Mac
  Docker endpoint is queried read-only for the identity/state comparison.
- Provider reproduction runs a byte-checked copy of the integrated provider in
  its ignored cache, with synthetic credentials and real loopback HTTP. Neither
  candidate execution nor live provider traffic runs on the Mac.

## Reproduce

From repository root, in an owned Herdr pane, use **fresh** output names:

```sh
python3 -B audit/evidence/2026-09-19/harness-integration/accept.py executor executor-next
python3 -B audit/evidence/2026-09-19/harness-integration/accept.py provider-clean provider-clean-next
python3 -B audit/evidence/2026-09-19/harness-integration/accept.py provider-test provider-tests-next provider-clean-next
```

`accept.py` applies numeric guard.py limits per command, places each owned
command in a process group, records real exits and time in ET, and checks group
cleanup. Executor machine-local timers also survive loss of the host controller.
Provider run.py has an earlier group deadline. Exact expanded argv/cwd and
stdout/stderr appear in each attempt. Fresh output directories are mandatory.

## Results as printed

| Attempt | Observed result |
|---|---|
| executor-01/unit | 15 tests, exit 0 |
| executor-01/live | 17/17 controls, 35 declared checks, 424523 artifact bytes |
| executor-01/lifecycle | 1 control, collector exit -9, independent cleanup before recovery |
| executor-01/lead-control | explicit exit 137; signal null, hint 9; candidate verdict fails |
| executor-01/final-state | no containers, units, temporary run directories or host test processes |
| executor-01/shared-comparison | five container IDs/states unchanged |
| provider-01/setup | exit 1, missing .cache/source.tgz; retained red |
| provider-02/clean | seven child exits 0; seven generated records byte-identical; tracked bytes unchanged |
| provider-03/parser | 28 fixed cases, unexpected egress rejected=3, Node 24.20.0 |
| provider-03/lead-controls | 2/2, byte-split multilingual text and boolean usage total |
| provider-final-source-identity | 17 top-level files match copy after tests, no tracked provider diff |

All successful lead command groups were empty at completion. The extra
executor control and provider controls are standalone scripts in this directory.
The initial arrival snapshot recorded only Docker counts/states; full identity
comparison applies to executor-01's before/after interval.

## Limits

Executor acceptance covers fixed BusyBox fixtures and protected external
verdicts, not application builds or a persistent workspace service. Provider
acceptance covers pinned offline parsing and one-turn behavior, not OAuth,
account/model entitlement, live inference or the Mo bridge. The provider package
is not byte-identical to its git source; see committed provenance evidence.
No compiler, Step 39, Darwin full-sync, Program 7 or language-value acceptance.

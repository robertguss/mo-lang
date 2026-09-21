# Orb migration — 20 Sep 2026, evening ET

Lead coordination evidence, not a cold auditor reading or code acceptance.
Thread: https://ampcode.com/threads/T-01a0c15a-66e4-771b-b48e-bf66e8ed2da0.
Arrival source: fffff158b0737aff2d13f2b64787e90686473e95, clean local main equal
to fetched origin/main. Workflow source: 9111bb70 on main, pushed.

## Environment observations

Commands executed through the lead shell tool; observations below are
transcribed, not separately captured raw logs. `zig version`:0.16.0;
`uname -m`:x86_64; `nproc`:16; `free -h`:31GiB total, no swap.
`command -v orbctl` produced no path. `docker context show`:default;
`docker info --format '{{.ServerVersion}}'` failed because
`/var/run/docker.sock` was absent. No daemon or infrastructure was started.
`git ls-files '.github/*'` returned no files; no CI was created.

`git fetch --quiet --unshallow origin` completed. `git cat-file -t` still failed
for65b3dd37 and65f2eca0. Earlier refs are available:
`origin/toolchain/step-42-memory` at0a4dffcd and
`origin/harness/workspace-server-4a` at523351ba. Later embedded patches are
recovery inputs, not proof of an exact final Mac tree.

## Worker launch receipts

All launches used native `create_thread`, project `robertguss/mo-lang`,
`agent_mode: medium`, `executor: orb`, `orb_size: a1.xxlarge`, from pushed
9111bb70. No worker has push or nested-delegation authority.

- Guard recovery: T-01a0c189-eb49-728c-afaa-46da66582ac2. Owns guard.py and
  bench/step42/guard-orb only; bounded Python process controls allowed.
- Memory recovery: T-01a0c18a-5e4e-729b-96fb-39ccb6c9d1cc. Owns Step42 A–D,
  excluding the separately owned guard; initial source-only checkpoint.
- Server recovery: T-01a0c18a-cc44-7380-8650-bf09bfec9954. Owns part A and
  approved formatter/corpus repairs; initial source-only checkpoint.

Both source lanes wait for accepted guard and review before runtime execution.
No candidate accepted. Independent baseline worktree:
`/tmp/mo-lead-orb-baseline`, branch `lead/verify-orb-baseline`, at9111bb70.

## Audit intake reconciliation

Arrival `git fetch origin && python3 audit/automation/fable_poll.py check`
exited0. It checked one ref and reported ten records new to the local ledger,
plus one invalid old transport canary. Every valid record already has a reply on
main. No duplicate publication is needed. Confirmed by exact `in_reply_to`
searches under `audit/handoffs/`:

| incoming record                                 | existing reply file under audit/handoffs/                                  |
| ----------------------------------------------- | -------------------------------------------------------------------------- |
| automation-transport-test-auditor-002           | automation-transport-test/automation-transport-test-fable-working-002.json |
| gen4-speed-probe-compared-001                   | gen4-speed-probe/gen4-speed-probe-working-002.json                         |
| generation-six-execution-reading-filed-001      | generation-six-execution/generation-six-execution-parallel-filed-001.json  |
| generation-six-reading-filed-001                | generation-six/generation-six-parallel-filed-001.json                      |
| program-7-spec-compliance-reading-filed-001     | program-7-spec/program-7-spec-parallel-filed-001.json                      |
| step-35-crypto-brick-compared-001               | step-35-crypto-brick/step-35-crypto-brick-working-001.json                 |
| step-36-reading-filed-001                       | step-36/step-36-parallel-filed-001.json                                    |
| step-37-reading-filed-independent-code-20260918 | step-37/step-37-parallel-filed-001.json                                    |
| step-37-reading-filed-recent-64982b2-001        | step-37/step-37-parallel-filed-002.json                                    |
| step-38-plan-reading-filed-001                  | step-38-plan/step-38-plan-parallel-filed-001.json                          |

The lead's previous gen4 response records the disagreement and subsequent probe
disposition; the step35 response records no disagreement and retains its
unread-brick caveat. Both responses remain unchanged. The invalid canary was
already documented in the old transport acknowledgement. No auditor body or
hidden suite was opened for this reconciliation, and no audit session or poller
was started.

## Documentation checks

`python3 mo-wiki/tools/lint.py`:286 pages,29 nonblocking notices (15 review, 14
size), exit0. `git diff --check`:exit0. Oracle requested restoring full native
coverage in the acceptance command; active guidance now specifies
`zig build test-corpus --summary all`, not the native-skipping `test` step.
These checks do not establish runtime correctness.

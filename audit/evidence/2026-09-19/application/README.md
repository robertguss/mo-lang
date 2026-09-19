# Isolated application builds: independent lead evidence

19 September 2026, ET. Read raw outputs before the lead's interpretation.
This bundle establishes bounded Hello/Logstat compilation and execution in the
dedicated Linux candidate environment. It is not a repair trial, provider-driven
coding result, language comparison or acceptance of a historical audit gate.

## Source and scope

Worker branch `harness/application-build-v1`, exact base
`5e5682274d0d02ac5532f07a075c11a8e52345e3`, frozen tip
`0b93d5df22b7a49fe135b231256271e8245feebb`. Its four commits are preserved.
The first two have Astra author and inherited Robert committer; the last two
have actual Astra author and committer. Integrated commits are b079c9d5,
676badc7, 7b48a5f4 and `aa7ec7623f634d5c05f6d602b894428c211b4869`, all with
Astra lead committer. No source conflict or unrelated source edits.

Independent acceptance verifies exact executor tree equality with the worker
tip, then hashes all 5,799 tracked toolchain/examples files before and after.
All bytes remain unchanged. Main later gained only the recovery brief while
these tests ran. The application worker and its run panes were closed after
the idle receipt; worktree and all failures remain.

Lead source reading: `../application-preparation/lead-review-e9fd1b45.md`, plus
review of the immutable Env/exec corrections, final tests and cleanup receipt.
Lead reading is an interpretation; open it after your own source reading.

## Reproduction

Require exclusive ownership of `mo-executor-r01`, its accepted parent slices,
the pinned installed compiler/Zig distribution and original verified archive.
No command below uses the shared Mac Docker daemon for execution.
Use new output names; the runner refuses an existing directory.

```sh
python3 toolchain/bench/step36/guard.py 1800 -- python3 -B audit/evidence/2026-09-19/application/accept.py application attempt-NEW
python3 toolchain/bench/step36/guard.py 1200 -- python3 -B audit/evidence/2026-09-19/application/accept.py full full-NEW
```

Run in owned Herdr panes. Every child has its own numeric guard, process group,
retained argv/cwd/start/end/exit and group-absence check. Remote package assembly
has an independent 600-second systemd deadline; candidate commands reuse the
accepted supervisor/reaper. Local guard expiry alone is not remote cleanup.

## Results

| Check | Lead result and raw pointer |
|---|---|
| Existing local tests | 27/27; attempt-01/local.stderr.txt |
| Policy/selection | 8/8; attempt-01/policy.stderr.txt |
| Packaging controls | 3/3; attempt-01/package-unit.stderr.txt |
| Fresh package and actual exported contents | 19,544 files verified; attempt-01/lead-package-attempt-01 |
| Fixed application runtime controls | 23/23, cleanup_errors empty; attempt-01/lead-controls-attempt-01 |
| Existing workspace live | 22/22; attempt-01/workspace-live |
| Existing executor live | 17/17; attempt-01/executor-live |
| Collector-loss lifecycle | 1/1; attempt-01/lifecycle-live |
| Lead extra | 1/1; attempt-01/extra |
| Full compiler build/test | full-01 build 0/test 1 at 242/243; full-02 build/test 0, 243/243 and 5/5 |

The package was assembled again from verified installed inputs and the original
archive. Docker reused its cached identical image; this is not a cold uncached
image-build or general reproducible-image claim. Actual export verification
passed. Image `sha256:b9fda4ae85f369e475e0f412e15dea9044a849a64bc2ec94bb3bc5a661eab3c4`;
manifest `d31b5c5e7e1912f98eba21268854d0f7b830dba7048b2de0e2c0458d10e507eb`.
Fresh machine staging is `/opt/mo-harness/application-build-v1/lead-package-attempt-01`.
Package service peak is unavailable after exit and would exclude daemon work.

The extra independently freezes unchanged source, builds Hello in
`/build/space dir`, executes with `Zoë 🌙`, checks the exact greeting and verifies
that source writes remain denied. The result binds the frozen snapshot,
image/toolchain and protected nonempty checker inventory. It uses the public
Workspace API and its own command/check, not the worker's build helper.

| Cold candidate command | Elapsed seconds | Actual cgroup memory peak bytes | OOM kills |
|---|---:|---:|---:|
| Hello | 34.5208 | 747450368 | 0 |
| Logstat text and filtered JSON | 36.8841 | 646533120 | 0 |
| Read-only snapshot Logstat rebuild | 36.5143 | 614055936 | 0 |
| Lead spaced-path Unicode Hello | See extra/observations.json | 785051648 | 0 |

These are observed bounded control timings, not comparative performance data.
Each command had fresh scratch under unchanged 1 GiB/CPU 1/128 PID/120-second
limits. `/build` explicitly permits execution; source and `/tmp` remain noexec.

Final inventory identifies 68 executions and 34 workspaces, with no owned
paths/processes/containers/units/mounts/cgroups remaining; both parent task sets
are empty and their limits unchanged. Five full shared Mac Docker IDs/states
match before/after. Own fixture cache was removed after completion. See
final-command.json, final-inventory.json, shared-comparison.json,
lead-cache-cleanup.json and pane-idle receipt. Attempt outer exit is zero.

## Retained limits and failures

Lead full-01 retained a TLS echo differential failure: interpreter served one
connection, native zero, both exit zero; 242/243 tests and 3/5 steps. Source is
unchanged. Five focused pairs then passed with zero intentional clients (10/10).
`tls-source-review-2.md` supersedes the first review's tooling misunderstanding:
both runtime paths increment the example's counter after real OS TCP acceptance,
independently of handshake success. The corpus uses a fixed port in sequential
traffic windows. No originating client was identified. A later clean run would
prove non-reproduction, not establish root cause or fix this isolation weakness.
Full-02 completed at 3:16 AM ET with 243/243 and 5/5, MaxRSS 459 MiB, unchanged
tracked bytes and absent process group. This does not identify the first run's
extra connection. The focused build is reproducible with a fresh output name:

```sh
python3 toolchain/bench/step36/guard.py 300 -- python3 -B audit/evidence/2026-09-19/application/tls-control.py tls-focus-NEW
```

Do not run that fixed-port control concurrently with the full suite.

Worker raw evidence retains the inventory sort bug, environment-order refusals,
actual compiler success followed by exit 126 from noexec scratch, fast `yes`
flood with unknown execution/cleanup followed by positive host cleanup, and
incorrect quota/PID stimuli. The final bounded echo-loop output control does
not retroactively turn that fast flood into a successful normal cleanup.

No synchronous whole-call finite wall bound is claimed: inherited blocking
lifecycle locks and local I/O/launch remain. A lost reservation response also
needs explicit recovery ownership before HTTP exposure. The next bounded brief
is `mo-wiki/plans/mo-workspace-recovery-v1.md`; it does not extend old provider
deadlines or add a Mo remote-tool profile. Full compiler checks, fixture
acceptance and real application builds do not prove live auth/inference,
language value, Darwin full-sync or Step 39 acceptance.

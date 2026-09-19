# Application build v1 worker receipt

19 September 2026, ET. Application-container readiness is verified in this
worker worktree; independent lead source review/integration/acceptance remains.
No Logstat repair, HTTP adapter, provider trial or language-value claim is made.

## Source and immutable identities

- Exact clean base: `5e5682274d0d02ac5532f07a075c11a8e52345e3`.
- Branch: `harness/application-build-v1`; worktree:
  `/Users/robertguss/Projects/startups/mo-lang-worktrees/harness-application-build-v1`.
- Source checkpoints: `e9fd1b45ba835424e2c9edd973f1ab74c87a36b3`,
  `38e1d0ff56f62f11596e66dfebf3395fea24444e`,
  `55cbb14ceba7f67d5f817f86b68f5596ae1357b8`. The final receipt commit follows
  these and is identified by the handoff's full HEAD. No amendments, rebases,
  pushes, nested workers, dependencies or downloads.
- Attribution: the first two commits have **Author GPT-6-Astra
  `<noreply@openai.com>`, Committer Robert Guss `<robertguss@gmail.com>`**.
  They were preserved unchanged. `55cbb14c` and subsequent commits explicitly
  set both author and committer to GPT-6-Astra using per-command git config.
- Trusted compiler source: `e3a01bbf613c1f130955b6e123d5987a4c559d18`;
  binary 15,923,616 bytes, SHA-256
  `4d14520aaf25403396e14501efbab2f5cd3d7f29bba4ad7c124155c06c806c72`.
- Zig archive: `ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17`.
  All 19,546 installed distribution files match its bytes and modes.
- Image: `sha256:b9fda4ae85f369e475e0f412e15dea9044a849a64bc2ec94bb3bc5a661eab3c4`.
  Export inspection verified all 19,544 packaged Mo/Zig/lib files.
- Package/toolchain manifest SHA-256:
  `d31b5c5e7e1912f98eba21268854d0f7b830dba7048b2de0e2c0458d10e507eb`.
  Machine receipt: `/opt/mo-harness/application-build-v1/package-02/package/manifest.json`.
  Context, recipe and pinned image remain for lead acceptance. Failed package-01
  staging is retained; existing installed inputs were never changed.
- Application source: exact archived files from
  `e6f04ce6358c85f22a86f26be0b5b388495fcc6e`: `mo.root`, `hello.mo`, four
  `logstat/*.mo` modules, and four existing fixture files. The exact five matching
  generated ID records are selected from the original aggregate `.mo.ids` and
  serialized within the file-size bound. Original aggregate and imported hashes
  are in each live attempt's `source-receipt.json`. Goldens stay outside candidate
  storage. No repository application/compiler/IDs/PRELUDE/provider/wiki edits.

## Changes

The existing Workspace/Run lifecycle selects an explicit application policy
at workspace creation, binds policy/image/toolchain in registration, rejects
reservation/manifest mismatches, and carries identity through feedback and
snapshot verdicts. Existing BusyBox defaults and parent remain unchanged.

Application limits remain 1 GiB RAM, no extra swap, one CPU, 128 PIDs,
120 seconds, 64 KiB combined retained output. `/build` explicitly requests
`exec,nosuid,nodev`, 512 MiB and 16,384 inodes; source and `/tmp` remain
`noexec,nosuid,nodev`. Runtime `/proc/mounts` assertions verify these actual
flags, not just Docker configuration. Independent reaper, one-shot dispatch,
global admission lock and cleanup-proof-before-disarm are reused.

The only existing-source changes are the four authorized executor modules,
their existing snapshot unit test's complete manifest fixture, and executor
README integration. New packaging, fixtures, controls, evidence and reports are
inside this directory. Graph/CodeScent tools were unavailable; source review
used bounded local reads and ast-grep where supported.

## Verification

Every run used an owned right/no-focus Herdr run pane, numeric repository guard,
process-group cleanup and a fresh retained attempt. Exact argv/cwd/exits are in
each attempt's `command.json` and `result.json`; later attempts also retain full
source snapshots and hashes. Early attempts through `local-regression-02`, and
the initial Zig/inspection runs, lack per-attempt source snapshots; their exact
commands/exits and unmodified compiler base remain recorded. No such early
attempt is presented as live application proof.

| Check | Result | Guarded elapsed |
| --- | --- | --- |
| Full `zig build` | exit 0 | 39.20 s |
| Full `zig build test --summary all` | 5/5 steps, 243/243 tests, exit 0 | 418.36 s |
| Local existing executor/workspace | 27/27, exit 0 | 0.36 s |
| Application policy and CLI-selection refusal | 8/8, exit 0 | 0.36 s |
| Packaging/archive/ID controls | 3/3, exit 0 | 0.36 s |
| Image-content group | 19,544 actual files verified | package attempt 26.07 s |
| Fixed application runtime groups | 23/23, exit 0 | 154.85 s |
| Existing workspace live groups | 22/22, exit 0 | 37.96 s |
| Existing executor live groups | 17/17, exit 0 | 33.31 s |
| Existing lifecycle fault group | 1/1, exit 0; collector exit -9; independent cleanup positive | 9.67 s |

The 23 named runtime groups plus image-content group were fixed and accepted by
the lead before final live evidence: 24 total. Unknown, duplicate or explicitly
empty runtime selections are rejected before execution. The actual guarded
commands are reproducible by replacing each recorded attempt/output directory
with a fresh directory; archived source cache names must also be fresh. Live
commands require a new exclusive lead release of the dedicated machine.

`application-live-03` is the final application proof. Hello ran with `Ada` and
returned the expected greeting. Logstat ran from `/workspace/logstat` and matched
both existing default-text and filtered-JSON goldens. The unchanged frozen
read-only snapshot independently rebuilt and executed Logstat in fresh scratch.
Verdicts bind the snapshot, image, toolchain and nonempty checker inventory.

| Actual cold candidate command | Elapsed | cgroup `memory.peak` bytes | OOM kills | `/build` used KiB / inodes |
| --- | --- | --- | --- | --- |
| Hello build + execute | 35.7531 s | 777,519,104 | 0 | 76,916 / 4,107 |
| Logstat build + execute text/JSON | 36.7436 s | 640,630,784 | 0 | 77,976 / 4,107 |
| Read-only snapshot rebuild + execute | 37.8531 s | 679,284,736 | 0 | 77,976 / 4,107 |

These are observed command timings including supervision and cleanup, not a
performance comparison. Peaks/events are sampled from the **actual candidate
cgroups**, whose full paths and IDs are retained. The intentional memory-limit
controls caused OOM kills; the cold application builds did not. Fast shell-only
commands can finish before a counter sample and correctly have missing counters.

## Retained failures and corrections

- `local-red-01`: four expected errors before policy implementation.
- `local-regression-01`: one old snapshot-test error because its synthetic
  manifest omitted now-required policy/image/deadline fields. Corrected only
  that test fixture; local27 subsequently passed.
- `image-build-01`: exit 1 before image construction. The inventory comparator
  sorted Path components differently from serialized paths. Read-only diagnostic
  found **zero missing/extra/changed files** among 19,546. `local-package-red-02`
  reproduced this; canonical path sorting fixed it. No installed Zig changes.
- `application-live-01`: interrupted with targeted controller SIGINT (exit 130)
  after 10 groups, 3 passed. Docker reordered environment entries; strict ordered
  comparison refused dispatch. Exact unordered comparison now rejects duplicates,
  extras and changed values. `local-policy-red-04` preserves the reproduction.
  Controller finally cleanup and all final absence checks succeeded.
- `application-live-02`: 17/23 groups passed, exit 1. Hello/Logstat/snapshot
  compiled, then returned **126** because Docker's default tmpfs flags included
  noexec. Actual `/proc/mounts` is retained. Their respective peaks were
  757,313,536 / 626,049,024 / 665,878,528 bytes, with zero OOM kills.
  `local-policy-red-06` reproduces missing explicit exec; only `/build` changed.
- The same attempt retained a fast `yes` flood's Docker kill/removal timeout:
  execution remained truthfully unknown, with subsequent positive host cleanup.
  Final overflow uses the existing executor's echo-loop stimulus and passed.
  Build-quota's error log was on the full filesystem, and PID's parent exited
  before sampling; final controls retain stderr externally and use the existing
  parent/child PID stimulus. The lifecycle implementation was not widened.
- Initial source reading tried nonexistent `examples/.mo.ids` (exit 1); the
  correct archived aggregate is `examples/programs/.mo.ids`.
- Packaging logs preserve the legacy-builder deprecation warning and harmless
  ignored ExecStopPost removals of an already-removed inspection container.
  Raw evidence retains carriage returns/blank lines; whole-tree `diff --check`
  reports those raw-output whitespace notices. Production-source diff checks
  pass; evidence was not normalized to conceal them.

## Final cleanup, resource scope and limitations

`final-01/inventory/allocations.json` records **102 execution identities**
(including refused/not-dispatched reservations), and the final request ledger
covers **59 workspaces**. No corresponding run directories, workspace mounts or
directories, candidate cgroups, task processes, containers or transient units
remain. Both application and old parent descendant task sets are empty. Existing
and newly created retired-ID tombstones remain by design. Owned local archived
sample caches were removed. Each guard's process group is absent.

`final-01/inventory/shared-mac.json` exactly matches the initial five full
container IDs and their exited states. The shared Mac Docker endpoint was only
queried read-only. The application slice file hash remains
`ab7ea2ac24e3248cc436348ea11251db3d650c160bf443907b16bda6e1e00702`.
Its final ceilings are 1536 MiB, swap 0, CPU 100000/100000, 192 tasks. The old
parent remains 512 MiB, swap 0, CPU 100000/100000, 128 tasks. The lead's verified
outer machine ceiling is 2 GiB/swap 0/two CPUs; guest free/df totals are not
machine-headroom proof.

The new parent cumulative peak is 1,181,556,736 bytes across packaging and all
controls, not an individual build peak. Successful packaging service peak was
unavailable after the unit became inactive; failed package service peak was
479,313,920 bytes. Even a service peak would exclude Docker-daemon work and is
not whole-image-build sizing evidence. Legacy builder intermediate-container
IDs are retained as the prefixes it emitted; candidate and final-image IDs are
full. The final image and its build-cache image ancestors are deliberately kept
for acceptance; they are not running containers.

Final measured per-attempt evidence is below 16 MiB; the largest is image-build-02
at 6,295,651 bytes. Early wrappers enforced the output cap; final proof measures
all artifacts, and subsequent wrappers enforce the entire attempt-directory cap.

[HTTP-CONTRACT.md](HTTP-CONTRACT.md) answers the follow-up API question. There is
no proven finite synchronous wall maximum because inherited lifecycle locks can
block without a deadline. Approximately 234.1 seconds of configured waits around
a 120-second command excludes those locks and local I/O; it is not a cleanup-safe
HTTP timeout guarantee. Old provider budgets and controller 65280-byte refusal
are unchanged. No HTTP API redesign was made.

Machine ownership is released to the lead by the final Herdr handoff after this
receipt is committed and the owned idle run pane is closed. Independent lead
review, integration, suite reruns and an extra control remain lead-owned.

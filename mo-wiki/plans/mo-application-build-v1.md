---
title: "Mo application build v1: isolated pinned toolchain"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, verification, security]
sources: [plans/mo-workspace-foundation.md, plans/mo-first-coding-harness.md]
status: complete
---

# Mo application build v1: isolated pinned toolchain

## Orientation

Package the verified Linux Mo compiler and pinned Zig distribution, then prove
real application compilation within a separately identified executor policy.
This is application-container readiness, before the scripted Logstat repair and
before a remote Mo workspace profile. No provider calls, model trial, HTTP
adapter, compiler changes or benchmark. Robert's overnight authority permits
Astra to select this bounded slice. Independent lead acceptance remains required.

The Astra/low source review is preserved at
`audit/evidence/2026-09-19/application-readiness/worker-report.md`. Its resource
numbers were proposals; the explicit trial ceilings below are the lead decision.
Mo embeds its C runtime and crypto/TLS source. The image needs the Mo executable,
Zig and matching Zig lib distribution, not a compiler source checkout. Source
resolution requires root-relative modules and matching generated IDs.

## Write scope

A fresh Astra/low worker at an exact main base owns new
`toolchain/harness/executor/application/` for image recipe, packaging, policy,
checks, fixtures, immutable evidence and README. It may make only necessary
policy-selection integration edits in executor `adapter.py`, `remote.py`,
`workspace.py`, `workspace_controller.py`, their existing unit tests and README.
Reuse existing lifecycle/registration/locking/cleanup; do not fork a second
executor. Keep the BusyBox policy and existing fixtures semantically unchanged.

No examples, Mo IDs, compiler/PRELUDE, provider/auth/bridge, wiki or other source
writes. Application samples are exact archived files in ignored owned caches;
never hand-edit repository application/generated records. No new dependency,
network download, nested worker, push, rebase or unrelated worktree edits.
You are not alone; preserve and accommodate others' changes.

Worker starts with local source review and tests. Machine commands, image build
and /opt changes require explicit lead release with exact resources/paths. The
lead owns machine provisioning; no use of the shared Mac Docker daemon. Every
Mo, Zig, Python test, server and build runs in an owned right/no-focus Herdr run
pane under numeric guard.py and process-group cleanup. Retain all failed attempts.

## Immutable packaging

Machine: `mo-executor-r01`, Ubuntu arm64, 2 CPU/2 GiB/8 GiB, isolated from Mac
files and SSH agent. Existing pinned BusyBox image SHA-256 is
`debdba9954b1065ab1ce723c6c1f2f22e52a78c164f863b938d58cc2c9f0d337`.
Use it as the fixed shell/base, with no network build/pull/package manager.

Trusted compiler source: `e3a01bbf613c1f130955b6e123d5987a4c559d18`.
Installed executable `/opt/mo-harness/bin/mo-e3a01bb-aarch64-linux-musl`,
15,923,616 bytes, SHA-256
`4d14520aaf25403396e14501efbab2f5cd3d7f29bba4ad7c124155c06c806c72`.
Zig 0.16.0 distribution is `/opt/mo-harness/zig-aarch64-linux-0.16.0`;
its original archive SHA-256 is
`ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17`.
Verify exact binary/distribution contents and record the image content ID, recipe
and manifest. Exclude source checkouts, credentials, host sockets, package
managers and verdict/checker outputs. No image identity from a mutable tag alone.

Install Mo and Zig adjacent under `/opt/mo`, with matching `lib/`. Verify actual
Mo Zig lookup and relocation. Use fixed PATH/cache environment. Brick caches
include Zig pathname, not executable content; image is immutable and each
command gets fresh scratch. Never reuse generated objects across image changes.

## Policy and ownership

Version identity `application-build-v1` is explicit in registration, validation,
feedback, snapshot verification and evidence. A registered workspace fixes its
policy/toolchain identity before dispatch; callers cannot widen it per command.
Keep the old fixture policy, old parent and defaults unchanged.

- Candidate: 1 GiB memory, no extra swap, 1 CPU, 128 PIDs, 120-second command
  maximum, 64 KiB combined retained output, one active candidate globally.
- Fresh executable `/build`: 512 MiB and 16,384 inodes, nosuid/nodev. Generated
  binaries and caches live here. Memory is charged within the 1 GiB ceiling.
- Separate 16 MiB noexec/nosuid/nodev `/tmp`. Preserve current source workspace
  limits: 64 MiB/4096 inodes, noexec/nosuid/nodev, descriptor-safe file operations.
- Separate lead-provisioned application parent: 1536 MiB, no extra swap, 1 CPU,
  192 tasks. Do not widen `/mo.slice/mo-executor.slice` (512 MiB).
- Network none, read-only image root, UID/GID 65534, all capabilities dropped,
  no-new-privileges, exact mount/environment/image/cgroup policy validation.

The 2 GiB machine has only nominal remaining headroom; these are trial bounds,
not measured sufficient sizing. Exclude concurrent bootstrap/builds. Record
actual cold-build elapsed time, OOM events, memory peak from a credible cgroup
source, tmpfs occupancy and cleanup. Earlier trusted service's reported 512 KiB
peak is unusable sizing evidence. If compilation exceeds the bounds, retain the
failure and ask lead for a concrete revised slice; do not silently raise limits.

Keep start/collect/dispose, single dispatch, persistent reaper deadline and
cleanup-proof-before-disarm ordering. Timeout/cancel/controller death must
remove candidate descendants and scratch, leave truthful unknown results on
uncertainty, and never retry a command. Timer ownership must use the application
maximum plus bounded cleanup, not the inherited ten-second candidate budget.
Snapshot verification has read-only source plus its own empty executable
scratch. Protected verdicts bind snapshot inventory, image/toolchain/policy and
checker inventory; no empty inventory or candidate-authored pass claims.

## Parts and checks

1. Define bounded policy identity and package exact inputs; unit-test defaults,
   selection, registration binding and rejection of mismatched effective policy.
2. After machine release, build the image offline and inspect actual contents,
   UID, mounts, environment, network and cgroup limits. Compile a tiny Mo source
   and archived Logstat from `e6f04ce6358c85f22a86f26be0b5b388495fcc6e`.
   Keep all sample source disposable and exactly inventoried. Preserve module
   paths/mo.root; select exact Logstat ID records if aggregate exceeds 64 KiB.
3. Build and execute in the same command's fresh /build; run Logstat in explicit
   source cwd. Freeze unchanged source and independently rebuild from read-only
   snapshot. Compare existing text and filtered-JSON goldens outside candidate.
   Do not seed or implement the repair trial in this slice.
4. Prove no stale binary after a failed build, no scratch reuse, source noexec,
   immutable image/root/snapshot, output/resource bounds, timeout/cancel and
   descendant/controller-loss cleanup. Re-run old workspace/executor controls.

At most 24 named application control groups, fixed before final run. Each live
attempt guard at most 1800 seconds, evidence at most 16 MiB. Commands have their
own 120-second ceiling and independent service deadline; outer guards alone are
insufficient. No performance comparison or best-of-five claim. Unknown/empty
explicit test selections fail before execution. Save exact raw commands/exits,
identities and cleanup inventories, including failures, without overwriting old
attempts. Actual Mo checks remain required; mock policy tests are not build proof.

## Done when

Worker freezes local Astra-attributed commit(s) with clean tree, exact base,
source/ID scope, reproducible commands, fixed control counts and every known
limitation. Existing local27/workspace22/executor17/lifecycle controls remain
green. Retain full `zig build` and `zig build test --summary all` results under
a numeric guard; do not edit unrelated failures. Prove final owned services,
containers, cgroups, mounts, scratch and processes absent, compare shared Mac
Docker IDs/states read-only, then release machine and close idle run panes.

Lead reviews immutable patch, integrates, repeats applicable suites and an extra
control, then accepts or corrects. This establishes isolated application builds
only. Scripted repair, remote HTTP/Mo six-tool routing, live subscription login,
provider-driven coding, matched Pi and language-value claims remain separate.

## Machine release — 19 Sep 2026, 2:28 AM ET

Lead read back outer cgroup limits: 2147483648 memory bytes, no swap and
200000/100000 CPU quota. Guest free/df report shared VM totals and do not prove
machine headroom. New `mo-application.slice` has effective 1610612736 memory
bytes, no swap, 100000/100000 CPU quota and 192 tasks. The old executor slice
file and 512MiB cap stayed unchanged; both parents were empty at release.

Worker exclusively owns bounded machine packaging/tests until positive cleanup
and release. It may create only owned application-build-v1 staging and task
packaging services/images; fresh task-owned existing lifecycle UUID resources
are also authorized. Existing pinned Mo/Zig inputs are read-only. Exact original
Zig archive path and SHA were supplied. Raw inspection/provision commands and
results are under `audit/evidence/2026-09-19/application-preparation/`.

## Result — 19 Sep 2026, 3:16 AM ET

Accepted at integrated `aa7ec7623f634d5c05f6d602b894428c211b4869`, worker tip
`0b93d5df22b7a49fe135b231256271e8245feebb`. Exact 2316 changed files match.
First two worker commits retain Astra author/Robert committer; subsequent worker
and all lead commits have actual Astra attribution. All historical failures stay.

Lead local27/policy8/package3, actual exported image19544 files, fixed runtime23,
workspace22/executor17/lifecycle1 and independent spaced-path Unicode cold
snapshot build pass. Image SHA b9fda4ae and full toolchain manifest d31b5c5e match
the worker package. Fresh packaging reused Docker layers; no uncached-image
reproducibility claim. Hello/Logstat/snapshot actual peaks were respectively
747450368/646533120/614055936 bytes, with zero cold-build OOM kills.

Full-01 retained 242/243: TLS echo counted one TCP connection in the interpreter
and zero natively. Ten focused runs pass; full-02 passes 243/243, 5/5, exit0.
The source counts TCP accepts before TLS success; the extra client is unknown.
No runtime/example change or claim that the original failure was fixed.
All 5799 tracked toolchain/examples files remained byte-identical.

Lead final inventory proves 68 executions/34 workspaces cleaned, both parent
task sets empty and five shared Mac Docker IDs/states unchanged. Raw commands,
exits, resource data and limits are in `audit/evidence/2026-09-19/application/`.
Worker panes closed; machine released to [[mo-workspace-recovery-v1]].
That cleanup-only API precedes HTTP/Mo routing and scripted repair. No live
provider, language-value, Darwin full-sync or Step39 acceptance follows here.

## Related

- [[mo-workspace-foundation]]
- [[mo-first-coding-harness]]
- [[mo-coding-fixture-v1]]
- [[mo-provider-bridge-v1]]
- [[mo-workspace-recovery-v1]]

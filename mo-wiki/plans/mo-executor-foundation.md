---
title: "Mo executor foundation: bounded execution and protected verdicts"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, verification, security]
sources: [plans/mo-first-coding-harness.md]
status: in-progress
---

# Mo executor foundation: bounded execution and protected verdicts

## Orientation

First provider-independent slice of [[mo-first-coding-harness]], authorized
under Robert's overnight instruction. Astra leads; a fresh Astra/low Herdr
worker implements the external executor adapter. The lead independently runs
acceptance. This is a fixture executor, not the Mo agent loop or an audit seal.

The read-only worker review and lead environment checks are under
`audit/evidence/2026-09-19/executor-readiness/`. Ordinary OrbStack sharing is
unsuitable for this boundary. The newly created `mo-executor-r01` is Ubuntu
24.04 arm64 with isolation and network isolation enabled, SSH-agent forwarding
disabled, 2 CPU quota, 2 GiB memory and 8 GiB disk limit. Effective CPU/memory
values were read back. Mac filesystem aliases were absent and `macctl run true`
failed. These observations are prerequisites, not candidate acceptance.

OrbStack machines share a Linux kernel. This work does not claim protection
against a kernel/runtime exploit, full-machine failure or a compromised trusted
host. The named machine is a dedicated administrative boundary; candidates
also require a restricted container boundary inside it.

## Write scope and ownership

- Worker implementation: new `toolchain/harness/executor/` only, including
  Python adapter, focused tests and its README. No other toolchain or Mo source
  edits, generated corpus IDs, sealed suites or historical evidence.
- Worker tests may create task-prefixed containers and transient services
  inside `mo-executor-r01`, plus private temporary host result directories.
  The Mac's existing `orbstack` Docker endpoint is outside the test scope.
- Lead environment setup: this new named machine, its packages, Docker config
  and dedicated `mo-executor.slice`; no global OrbStack settings or unrelated
  containers. Lead requirements/readings/results: this page, current status
  pages and new dated audit evidence.
- Host runner/verifier and result store are trusted and outside the machine.
  Candidate bytes are passed as data and executed only inside containers.

The implementation worker uses a separate worktree at an explicit base. The
lead may transfer the current brief separately. No nested workers or automatic
worker push. Every test process uses `toolchain/bench/step36/guard.py`.

## Parts

1. Minimal Python external adapter using installed OrbStack/Docker/systemd.
   A trusted caller supplies a script fixture, fixed expected behavior and a
   private result directory. The adapter invokes subprocesses with argument
   arrays, never executes candidate code on the Mac and never accepts candidate
   text as a verdict or a check-selection instruction. No HTTP server, provider
   integration or general plugin framework in this slice.
2. Containers use a pinned local fixture image, non-root user, read-only root,
   dropped capabilities, no-new-privileges, no network, no host/daemon/socket
   mounts, bounded scratch and explicit CPU/memory/PID limits. Inspect effective
   settings and observe enforcement. Copy only allowlisted synthetic fixtures.
3. Register a run ID, container identity and deadline before start. A
   machine-local systemd supervisor/reaper outlives the Mac controller, limits
   execution and removes the container/descendants on completion or failure.
   Test both Mac-controller death and per-run supervisor-process death. Do not
   kill machine PID 1 or shared OrbStack services. If bounded cleanup cannot be
   confirmed, return infrastructure failure and stop this named machine.
4. Capture stdout/stderr separately with an aggregate cap; terminate overflow
   and bound subsequent drain/cleanup. Persist an external result with actual
   status, exit/signal where available, timeout/cancel/truncation, candidate and
   image digest, policy/verifier identity, expected/observed checks and cleanup
   observations. Missing observations or required checks fail closed.

## Numbers

One candidate at a time: 0.25 CPU, 64 MiB RAM, no swap, 16 PIDs; 8 MiB each
for `/work` and `/tmp`. Default execution deadline 10 seconds, 2-second stop
grace and 3-second cleanup observation. Retain at most 64 KiB combined output;
output over the cap is a distinct failure. Disable persistent Docker logging.

A self-test attempt has an explicit 10-minute outer guard and at most 20 fixed
cases. Retain every failed attempt; do not silently adjust assertions to green.
Cases may use shorter declared limits. Bound host artifacts to 16 MiB per
attempt. Report timings and real exit codes; no performance claim in this unit.

## Done when

The worker reports the exact commands, exit codes, check counts and limitations.
Lead acceptance must independently demonstrate:

- Correct output from a positive fixture, and rejection of wrong output,
  nonzero exit, empty/missing expected checks, absent fault stimulus, stale
  identity and forged success text. Candidate attempts to overwrite authoritative
  results cannot pass. Comparison uses externally defined expected behavior.
- Deadline, cancellation and output-overflow outcomes remain distinct. Children,
  grandchildren and new-session descendants are gone after completion, timeout,
  Mac-controller death and per-run supervisor-process death.
- CPU throttling, memory/PID/scratch enforcement and network/filesystem denial
  are observed, with positive controls that show the probes actually ran.
- Effective policy, immutable candidate identity and complete check inventory
  are bound to the final host result. A prior successful result cannot satisfy
  a new candidate/run. No final pass until candidate writers have stopped and
  cleanup is verified.
- Existing shared Docker container inventory/context is unchanged. The dedicated
  machine has no remaining candidate containers or run services after checks.
- Python checks and live fixture controls pass from the integrated lead tree.
  No Zig build is required for this Python-only adapter; no compiler/runtime
  acceptance is claimed. Later Mo changes require the lead's Zig/Mo checks.

## Remaining obligations

Provider OAuth/client identity, Linux Zig and application builds, Mo agent loop,
recipe-versioned 401 task and Pi comparison remain later slices. Step 39 and
Darwin full-sync remain unaccepted; Program 7 remains suspended. A fixture
executor success does not discharge any of these obligations.

## Related

- [[mo-first-coding-harness]]
- [[roadmap]]
- [[decision-log]]

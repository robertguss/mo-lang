---
title: "Step 44: bounded byte chunks from Conn"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [runtime, stdlib, verification, processes]
sources: [plans/mo-workspace-server-4a.md, plans/interpreter-step-20.md, plans/interpreter-step-38.md, spec/design-v0/09-stdlib.md]
status: in-progress
---

# Step 44: bounded byte chunks from Conn

## Orientation

Workspace server F1 is filed by Sol at `8b0ff352` on
`harness/workspace-server-4a`. Its unchanged Python client sends a 155-byte
JSON body with no final newline and no shutdown. `Conn.lines` delivers only
the six header lines until the client times out and closes. Evidence:
`examples/programs/workspace-server/evidence/f1-06-exact-client/` and
`f1_repro.mo/.py` at that commit. Exit 0 there means the defect reproduced,
not that the protocol worked. Do not rerun that known failure merely to
confirm the report.

A byte source hands arbitrary bounded byte pieces to a process; it does not
interpret lines, HTTP or UTF-8. Add one such row using the existing runtime
source mechanism. This also lets the application reject an oversized header
before a newline arrives. An exact-body read alone would leave that problem
and force the application to change read modes. No new grammar, `Bytes` type,
HTTP stack, pull-read API or wire change in this step.

Worker: a fresh clean OMP/GPT Sol/high session in its own worktree, based on
accepted main `d308c2f78c006d120b35127da0dce17621d441b8` plus lead-only brief
records if present. Astra owns design decisions and acceptance. First inspect
this contract adversarially: report any concrete incompatibility, unsafe
lifetime or missing behavior before committing to an implementation. Do not
silently substitute a different public interface. No nested delegation.

## Write scope

`toolchain/src/**`, `toolchain/runtime/**`, `toolchain/PRELUDE.md`,
`toolchain/bench/step44/**`, `toolchain/STEP-44-REPORT.md`, and new corpus
files under `examples/` with their real generated `.mo.ids` sidecars and
verified lines. `toolchain/build.zig` only if required for focused checks.
No server program edits (`examples/programs/workspace-server/**`), other
harness edits, guard edits, memory-safety redesign, wiki, audit or HANDOFF
writes. No machine, Docker, VM, pushes or PRs. Read the F1 commit using Git
without merging the server branch. Preserve other workers' work.

Step 42 runs separately and overlaps runtime files. Stay on this branch;
never merge or copy its unaccepted changes. Reuse existing packed-message
ownership and keep changes local to the new source. The lead serializes
integration and full-suite verification; expect reconciliation with step 42.
The server worker consumes this API only after a lead-approved integration.

## Contract

```ruby
conn.chunks(into: reader, max_bytes: 4096, idle: 2_000.ms)

message Chunk(bytes: List(UInt8))
message Closed
message Idle
```

- Receiver `Conn`; parameters `into: Handle(P)`, `max_bytes: UInt64`,
  `idle: Duration`; returns `none`. Like `lines`, registration does not wait
  and takes no `within:`. It is a capability effect, subject to existing
  capability/flows restrictions. The checker requires those three exact
  messages, correct field types and no replies (existing MO0223 convention).
- `max_bytes` must be 1 through 65,536 inclusive. Invalid values crash the
  caller naming `Conn.chunks` before registering a source, reading bytes or
  allocating from the requested size. Never truncate a large UInt64 first.
- Each `Chunk` has 1 through `max_bytes` original bytes, in stream order,
  without loss, duplication, newline/CR stripping or UTF-8 conversion. NUL
  and invalid UTF-8 are ordinary bytes. Chunk boundaries are unspecified.
  Available bytes are delivered without waiting to fill `max_bytes`, find
  a delimiter or reach EOF. The application accumulates its own framed
  message and uses `String.from_bytes` only after a whole text frame exists.
- Reuse the connection's existing unread buffer: bytes retained by a prior
  completed or timed-out `read_line` are delivered first. New plaintext reads
  and each payload are bounded; do not buffer the whole unbounded stream.
  The native List(UInt8) representation is retained, not a new byte type.
- Exactly one reader owns a connection. `read_line` returns existing `Busy`
  after chunks is registered. A second active registration (`lines` or
  `chunks`, either order), or chunks registration while a pull read waits,
  crashes before changing ownership. Existing completed pull reads do not
  prevent registration. No active-mode switch or cancellation API is added.
- `Chunk`s precede one `Closed` at normal input EOF, including a TCP peer's
  write-half-close. Then the source retires, but EOF alone does not close the
  local write half: a handler may still reply. Local `conn.close` stops the
  source silently; already-enqueued messages stay enqueued. A broken stream
  follows existing lines behavior (`Closed` and unusable connection).
- An idle source emits one `Idle`, closes its connection and retires.
  Use the existing source idle clock, mailbox headroom/hysteresis and paused
  idle accounting; an application still owns its absolute request deadline.
  A target that dies closes its connection and retires the source. Preserve
  program exit, source lifetime and poller cleanup behavior.
- A writer blocked on the same connection does not block input. Behind TLS,
  chunks are authenticated plaintext through the existing engine, never raw
  ciphertext, and pending engine replies retain the existing write ordering.
  A TLS handshake attempted after chunks registration is refused with the
  existing used-connection crash rule, even before any chunk arrives.
- `Net.fixture`, both executable runtimes and `mo test --sim` implement the
  same contract. Source scheduling/faults follow the existing source rules;
  simulated peers need no extra flush, newline or EOF to deliver a chunk.
  Fixture caveat found in the worker's adversarial review: public fixtures
  expose full `Conn.close`, not write-half-close. Preserve that API and
  full-close behavior. Internally model directional EOF independently from
  full close; a runtime-level test may establish peer write shutdown and
  drive the real fixture source/dispatch, proving buffered chunks, one
  `Closed` and a reverse-direction reply. No synthetic event injection,
  special test-visible Mo API or reinterpretation of `Conn.close`.
  Prove publicly initiated half-close with real sockets in both runtimes;
  report the internal-fixture and public-socket evidence separately.
- Source buffers may not borrow a process-region value across a safe point.
  Pack runtime messages through the existing source send path before buffer
  reuse; the receiver's compaction must not invalidate pending chunks.

## Parts

A. Read the existing Net/source/HTTP/TLS buffer and ownership paths, the
   checker/prelude/VM/native dispatch, and the F1 artifacts. File concrete
   contract concerns immediately. Add targeted behavioral tests that fail
   without this row, preserving their first output before implementation.
B. Implement the row in both runtimes and fixtures, reuse source scheduling
   rather than make another reader thread/loop, and update PRELUDE. Check all
   affected dispatch sites, source labels/events, TLS used-connection checks,
   compiler effect handling and generated/native row declarations.
C. Prove byte concatenation and bounded pieces, not particular chunk splits:
   embedded NUL/invalid UTF-8; a multibyte character split across arrivals;
   available data smaller than the maximum while the peer remains open;
   coalesced frames, fragmented frames and retained read_line bytes; max
   boundaries (0, 1, 65,536, 65,537 and an oversized UInt64); read ownership
   in both registration orders; half-close and post-EOF reply; local close,
   idle and target failure; mailbox backpressure without loss/overflow;
   simultaneous write/read; TLS and deterministic seeded source faults.
   Keep regression tests where these are real observable risks, not wiring
   assertions. Guard every socket read/write and subprocess with deadlines.
D. File a positive F1 control using the exact unchanged
   `workspace_http.client.connect`: require a valid HTTP reply before the
   client deadline while its write side remains open, with no added newline
   or shutdown. The worker authors a small new Mo probe outside the server
   directory, consuming chunks and Content-Length. Exercise it under
   `mo run` and `mo build`. Also prove oversized unfinished headers can be
   observed and rejected before newline/EOF. The original RED script's exit
   code is not the GREEN oracle. Do not claim the whole server accepted.

## Numbers

File exact counts, wall times and exits for focused checks. Request a
serialized measurement slot before benchmarks; report best of five under
both runtimes with load average: fixed-volume loopback binary input and
unchanged line-mode throughput before/after. Keep payload bytes and message
counts separate: chunk boundaries are not a stable performance oracle.
No throughput/zero-overhead claim without the measurement. Full-suite timing
belongs to the lead; do not run an unfiltered compiler suite concurrently.

## Done when

Every quoted run is teed to a filed log with a real exit file under
`toolchain/bench/step44/`; every mo/server/test process uses
`toolchain/bench/step36/guard.py` with a deadline and 4 GB watchdog. Check
only owned process trees for survivors after a kill; preserve unrelated
services. Local `zig build`, targeted tests and both-runtime probes pass;
targeted formatting only, no project-wide formatter/linter/full suite while
siblings work. Linux is deferred and must be listed as owed.

Commit `toolchain/STEP-44-REPORT.md` last, with exact base/final commits,
changed paths, contract findings, raw evidence pointers and exit codes,
measurements or explicit unmet measurements, remaining limits and cleanup
proof. Commit only named paths as GPT-5.6-Sol, no pushes. Do not call the
work done with a background command still running. Inform Astra in `w4:p1`
when a contract blocker, measurement request or final report is ready.

The lead inspects the exact diff, integrates into a separate
`lead/verify-step44` worktree, runs `zig build`, focused tests, the full
`zig build test --summary all` under `guard.py 2400`, and independent probes
on inputs not named above. The lead updates the stdlib spec and integrates
server adoption separately. No change to TLS acceptance, Program 7 or audit
thresholds is implied by this capability.

## Related

- [[mo-workspace-server-4a]]
- [[interpreter-step-20]]
- [[interpreter-step-38]]
- [[interpreter-step-42]]

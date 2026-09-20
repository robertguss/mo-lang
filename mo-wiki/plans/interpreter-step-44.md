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

## Lead review: corrections before acceptance

19 Sep 2026, 9:43 PM ET. Final worker delivery
`9ad0162aa1994bb67c012ee85e78503c8573043a`, original base `c4462935`,
measured code `9c67ec1f`, evidence `b209b8be`. The report, all raw samples
and reported clean/process-free checkpoint are preserved, not accepted.
Static review requires the following corrections in a fresh Sol/high session.

1. **Restore existing line idle behavior.** At this delivery,
   `sources.zig:379-402` sends `Idle`, closes and marks the fixture source
   done, but the deleted return lets `.more` fall through to `unreachable`.
   Restore the terminal transition, not a suppression of the panic. First
   retain a deterministic RED through the actual fixture source/dispatch
   with no input and an elapsed idle deadline, then GREEN asserting exactly
   one `Idle`, no `Closed`/`Line`, and retirement. Exercise both runtimes.
   Check existing line-mode coverage; the report's unchanged-path claim
   does not hold for this deletion. No dynamic reproduction claimed yet.
2. **Prove successful TLS independently of allowed injected errors.**
   `examples/step44/chunks-tls.mo:241-243` accepts ordinary handshake,
   timeout, close and trust failures even with faults disabled. Replace or
   separate that permissive oracle: the default positive control must
   require successful handshake, exact plaintext, bounded chunks, no end
   message and reverse-direction communication under both runtimes.
   Keep seeded fault evidence distinct and genuinely sensitive to failures;
   a forced handshake error must fail the positive control. Do not retain
   an always-error passing test or relabel it proof of successful TLS.
3. **Complete the named behavioral controls.** The real binary probe
   (`socket_probe.py:115-126`, `http_chunks_probe.mo:115`) compares length
   and sum, which permit reordered or compensating corrupted bytes.
   Compare the complete ordered byte sequence, including the existing NUL,
   invalid UTF-8 and split-character payload; do not assert chunk splits.
   File both-runtime behavior for invalid/full-width bounds, registration
   during an actually waiting pull read, and an actual TLS handshake after
   registration, not just `used`/source-count snapshots. Prove input can
   progress while a writer is actually blocked, with deterministic
   coordination and bounded cleanup. These are existing Part C/Contract
   obligations, not new APIs. Distinguish fixture and real-socket evidence.

Use a separate `toolchain/step-44-review-fixes` worktree based exactly on
`9ad0162a`. Original write scope applies; no step42/server changes or merges.
Preserve old logs and report sections verbatim; add correction evidence
under `toolchain/bench/step44/review-fixes/` and append a clearly separated
report section, committed last. Tests must defend observable behavior, not
field copies, labels or source text. Report uncovered prerequisites rather
than substituting weaker oracles.

Initially **static preparation only** while step42-fix owns focused
validation: no build/test/runtime/probe/formatter commands until a lead
grant. Then use bounded focused RED/GREEN checks, not unfiltered suites or
benchmarks. Longer/interleaved lines measurements and the integrated full
suite remain lead-owned after corrections. Keep the original -8.69%/-0.97%
throughput observations; neither a causal regression size nor zero overhead
has been established.

**Independent gate, 20 Sep 2026, 6:53 AM ET:** corrective code/evidence
02833a52 and reviewed final report3036b0f3 are integrated only in
`lead/verify-step44` at c49d1821. Build0; focused chunks checks3/4, exit1:
the exact-message-shape test fails parsing its four inline assignment arms
before reaching checker assertions. Narrow multiline fixture repair is
authorized; no parser/checker/runtime change. Require explicit4/4 before
resuming independent verification. Full suite and longer line comparison
have not run. Raw outputs: `audit/evidence/2026-09-20/step44-integration/`.

The fixture-only repair015164e7/report1f45e09c is reviewed and integrated at
6aa6ca84. Worker and independent focused runs both explicitly pass4/4;
the independent unfiltered suite has started under guard2400. The stdlib
contract is recorded with acceptance pending. Behavior and larger interleaved
line comparison plans are filed in the same evidence directory, not yet run.

### Independent corpus gate: strict controls are not fault-tolerant applications

At6aa6ca84 the unfiltered suite finished270/271, exit1, real1142.19s.
The corpus assertion expected121 simulated tests to hold under faults but
found110: the9 strict chunks controls and2 strict TLS controls passed only
without faults. The separate seeded TLS fault control held. No behavioral
or performance plan has run after this gate. This does not establish a
runtime regression; it establishes incompatible test classification.

**Bounded corrective scope, same unfinished Step44 assignment:** preserve
all assertions and all12 Mo tests. Move the three fixture modules and their
owned metadata together from `examples/step44/` to
`toolchain/testdata/step44/`, the toolchain's existing testdata area.
Keep sibling module identities/imports intact. Migrate active probe callers;
historical logs, commands and evidence stay immutable. No compatibility copy,
new root marker, public syntax, loader change or runtime change.

Add a permanent `corpus.zig` contract-fixture test, named to match the existing
`chunks` filter, using the existing pipeline and native differential helpers:

- Require all9 chunks and2 strict TLS controls, no failures/skips, with100
  seeded scheduling runs and explicitly zero injected faults.
- Require the distinct TLS fault control with100 seeds and20% faults,
  held-under-faults1 and fault-free-only0. Keep its bounded outcome oracle
  separate; it cannot substitute for either positive control.
- Require interpreter and native test execution to succeed for all three
  modules, not merely agree on a failing exit. Preserve test counts and
  interpreter/native agreement. Require canonical formatting of all three
  moved fixtures, since they will no longer be in the examples formatter loop.
- Keep the ordinary example corpus's stages, all-tests-held-under-faults
  assertion and zero fault-free-only assertion unchanged. No exemption,
  skipped target, permissive TLS branch, retry protocol or lowered assertion.

This is a location/classification correction, not removal from the automated
suite. A `# sim: --faults 0` header in examples is not a fix: the runner still
counts these as simulated, while held-under-faults requires nonzero faults.

Additional write scope is limited to the moved fixtures/owned metadata,
the new test in `toolchain/src/corpus.zig`, active Step44 probe path references,
and corrective evidence/report. Regenerate metadata with real Mo tooling,
never hand-edit it. Targeted formatting only. First prepare the static diff
and exact guarded command manifest; runtime remains HOLD until lead review.
No unfiltered worker suite, benchmarks, unrelated cleanup or Step42 changes.
The lead will independently rerun the full suite before behavioral/performance
acceptance. Last accepted full-suite result remains268/268; Linux is deferred.

## Related

- [[mo-workspace-server-4a]]
- [[interpreter-step-20]]
- [[interpreter-step-38]]
- [[interpreter-step-42]]

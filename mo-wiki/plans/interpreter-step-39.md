---
title:
  "Step 39: the TLS brick's corrections, and a write that reaches the disk on
  macOS"
created: 2026-09-18
updated: 2026-09-18
type: plan
tags: [runtime, security, stdlib, verification]
sources:
  [
    plans/interpreter-step-37.md,
    plans/interpreter-step-38.md,
    deep-dives/bricks-and-the-cost-of-zero-dependencies.md,
    spec/design-v0/09-stdlib.md,
  ]
status: queued
---

# Step 39: the TLS brick's corrections, and a write that reaches the disk on macOS

Two independent auditor sessions read step 37 on 18 Sep 2026 and both showed,
with real handshakes through the brick's exported ABI, that **the client accepts
certificate chains outside their issuer's restrictions**. They also found an
ALPN boundary, a hole in the fuzz driver's count, a corpus test file that stays
green when the handshake is replaced by a `Timeout`, a stale spec paragraph, and
the standard's vectors missing from the corpus. All conceded (the decision-log
rows of 18 Sep). The same morning the lead found that both runtimes call plain
`fsync`, which on macOS does not ask the drive to flush. This step closes all of
it. The brick is **not complete** until it lands.

## Orientation

The auditor's readings and their scripts, which are this step's gate and are
**not to be edited**: `audit/mo-audit-2026-09-18-tls-independent-code.md`,
`audit/mo-audit-2026-09-18-recent-tls-step37.md`,
`audit/evidence/2026-09-18/tls-independent-code/chain-checks.py`,
`audit/evidence/2026-09-18/recent-tls-auditor/{chain-checks.py,fuzz-accounting-check.py,example-assertion-check.py}`.
The code: `toolchain/src/bricks/tls.zig` (`isCa` near line 538, `checkChain` and
`signedBy` near 648 to 731, the ALPN parsers near 357 to 410 and 1405, the
record layer's handling of a plaintext record after the handshake keys are
installed), Zig 0.16's `std/crypto/Certificate.zig` (what its parser gives and
what it skips), `toolchain/bench/step37/{fuzz.py,diff.py}`,
`examples/effects/tls-client.mo` (the `faulted?` and `heard?` allowances),
`mo-wiki/spec/design-v0/09-stdlib.md` lines 341 to 357,
`toolchain/src/blocking.zig:114` and `toolchain/runtime/mo_rt.c:8303` (the two
`fsync` calls).

## Write scope

`toolchain/` (the brick, both runtimes, their tests, `bench/step37/` and a new
`bench/step39/`, `PRELUDE.md` if a row's wording changes),
`examples/effects/tls-client.mo` and a new `examples/effects/tls-vectors.mo`
with their `.expected` and `.mo.ids` sidecars and fixtures under
`examples/effects/tls/`, and these spec lines only: chapter 9's `## Tls`
paragraph on what the client checks and the stale fixture paragraph (line 355),
chapter 9's `## Fs` sentence on what "on disk" means per platform, and the
runtime paragraph of `toolchain/README.md`. Nothing else under `mo-wiki/`,
nothing under `audit/`.

## Parts

A. **The chain, checked as RFC 5280 asks for what the cut supports, and refused
for what it does not.** For every certificate in the path: `pathLenConstraint`
enforced; an issuer must carry `keyCertSign` when it has a key-usage extension;
the leaf's extended key usage, when present, must include server authentication
for a server's leaf (client authentication is out of the cut); **every critical
extension the brick does not process is a refusal** (`unsupported_certificate`
or `bad_certificate`, say which and why); name constraints on any certificate in
the path are refused as unsupported rather than ignored; validity checked at the
boundary second. Each is a brick test with a generated Ed25519 chain and a P-256
chain, a test under both runtimes through `TlsClient.connect` over a real
socket, and a case in the differential generator with OpenSSL as the oracle (the
oracle is never weakened to match). `Untrusted` stays the row's answer. Then run
the x509-limbo corpus's TLS-server cases that fall inside the cut (Ed25519 and
P-256 chains) and report accepted-but-should-reject as a number that must be
zero, and rejected-but-should-accept as a list with a reason each.

B. **ALPN.** Either the whole legal offer is searched or the row states a limit
and an offer past it is refused with a named error at `offer`, the same on both
ends; never a silent truncation that turns an overlap into
`no_application_protocol`. The auditor's 65-name case passes.

C. **A client never acts on a record in the clear once the server's handshake
keys are installed** (after the ServerHello): such a record, alert or not, is
the client's own failure and `connect` is `Handshake`. The server's side keeps
today's tolerance of a client's plaintext alert before the client's Finished,
because OpenSSL's client sends its refusal alerts that way, and the spec's
`## Tls` says so in one sentence. Step 38's abuse table gains the distinction:
cells C2 sent in the clear expect `Handshake` in both the alert and the
`close_notify` columns.

D. **The instruments.** `fuzz.py` counts and keeps every failed batch (its
inputs and output saved under `work/failed-batches/`), whether or not an input
fails again alone, prints both numbers, and exits nonzero on either; `diff.py`
exits nonzero on a mismatch; the differential generator passes its sampled
groups to `s_server` on the client path, and draws chains from part A's
constrained shapes. Then a fresh **1,000-session differential run** and a fresh
**fuzz CPU-hour** on the corrected brick, seeds stated, raw output filed.

E. **The corpus says something.** `tls-client.mo`'s tests are split: exact
deterministic controls with no fault allowance (a handshake and a line each way
must succeed; each refusal must be its named error) and separate seeded tests
where a fault was actually injected. `tls-vectors.mo`: the RFC 8448 section 3
trace as a corpus test under both runtimes (what can be replayed without the RSA
certificate's authentication is replayed and the file says what is skipped and
why). Chapter 9's stale fixture paragraph is removed.

F. **`F_FULLFSYNC` on Darwin**, both runtimes: where the runtime syncs a file on
macOS it calls `fcntl(fd, F_FULLFSYNC)` and falls back to `fsync` only when the
file system refuses it (`ENOTSUP`, `ENOTTY`); Linux unchanged. A test that
traces the call on a Darwin build (a counter the runtime test can read, not a
timing). Chapter 9's `## Fs` says what "on disk" means on each platform.
Measured: `jobq`'s pairs a second at 32 workers and creates a second on the Mac,
before and after, with `measure.py` at 30,000 jobs.

## Numbers

The chain check's cost per handshake before and after part A (µs, both key
types); handshakes a second before and after; the differential run's counts by
refusal reason; the fuzz's inputs, batches, failed batches, crashes; the
x509-limbo counts; `jobq` on the Mac before and after part F; the suite's time.
The date, `uptime`, and the top of `ps` at the head of every table; best of
five.

## Done when

Both copies of the auditor's `chain-checks.py`, **unedited**, show the valid
control ready and all four constrained chains refused, and the 65-name ALPN case
ready (raw output filed under `toolchain/bench/step39/`); the auditor's
`example-assertion-check.py` mutant now goes **red**; its
`fuzz-accounting-check.py` now reports the failed batch; x509-limbo's
accepted-but-should-reject is zero; the differential run is 0 mismatches of
1,000 with the constrained chains in the draw; the fuzz hour is 0 crashes and 0
failed batches;
`python3 toolchain/bench/step36/guard.py 2400 -- zig build test --summary all`
green with its summary line and exit code in the report, on the Mac, and the
brick's own tests green on Linux (the OrbStack container step 38 used); step
38's abuse table at 64 of 64 with part C's cells; the numbers table; the spec
lines; a numbered list "Decisions the brief did not cover". One commit per part,
subject `Step 39 part X`, pushed after each. Every process under the guard.

## What the lead will do at acceptance, written before the work

Run the suite; run both auditor scripts from a clean clone; write one new
constrained chain the brief does not name (a `pathLenConstraint` of 1 with two
intermediates below it; an intermediate whose key usage is present and empty)
and expect a refusal; break one check in `tls.zig` by hand in a scratch worktree
and confirm a corpus test and a brick test go red (the mutant rule); read the
`F_FULLFSYNC` call in both runtimes and trace it with `dtruss` or the counter.

## Related

- [[interpreter-step-37]]
- [[interpreter-step-38]]
- [[bricks-and-the-cost-of-zero-dependencies]]
- [[09-stdlib]]
- [[roadmap]]

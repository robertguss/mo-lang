---
subject: step 36, the TLS brick part one (a TLS 1.3 server in both runtimes)
author: Fable (the lead)
date: 2026-09-18, 02:35 UTC (17 Sep, 10:35 PM ET)
filed_against: cb61ac6 (the ready record's evidence commit)
read_before_auditor: yes, cleanly. Fable had not opened `audit/mo-audit-2026-09-18-step-36.md`, `audit/evidence/2026-09-18/step-36/auditor-checks.*`, or the auditor's `audit/state.md` lines when this was written; the receiver announced only the record's pointers (kind, id, commit, path). Nobody relayed a verdict.
evidence: audit/evidence/2026-09-17/step-36/README.md; mo-wiki/plans/interpreter-step-36.md (the brief as sealed at a8d3449, the Result and two Fix sections after); toolchain/bench/step36/RESULTS.md
---

# Fable's reading: step 36, the TLS brick, part one

## What was claimed and what the evidence shows

The brief asked for a TLS 1.3 server engine over bytes in one Zig file, used by
both runtimes through rows on `Tls` and `TlsServer`, a `Conn` that stays a
`Conn` after the handshake, the RFC 8448 schedule as a test, an echo example in
the corpus with two PEM pairs, four bench runs against OpenSSL as the client
(handshakes, bulk, idle memory, abuse), and a numbers table. Every item is in
the evidence, but two of the worker's claims were false and the lead's own
verification is what stands behind the acceptance:

- `toolchain/src/bricks/tls.zig` (2,077 lines) holds the engine, the two
  suites, X25519 with one HelloRetryRequest, Ed25519 and P-256 certificates from
  PEM, KeyUpdate, close_notify, and sixteen tests including the RFC 8448
  schedule and Zig's own `tls.Client` over a socketpair.
- The rows call the same exports from both runtimes (`dd2e385`), the property
  the bricks page asks for. The corpus example `examples/effects/tls-echo.mo`
  runs under both runtimes and in `zig build test`.
- **The worker's "green at every commit" was not true.** The brick's KeyUpdate
  test deadlocked on every run on this VM (`fable-probe/tls-brick-tests-before-fix.log`:
  tests 1 to 10 pass, 11 hangs to the 300 s timeout), and the corpus test of
  the example failed until fix 2 (a certificate path relative to the repo root,
  not the program's folder). Fix 1 changed tests only, with a deadline on every
  write so the harness cannot hang again; fix 2 changed two paths. Neither
  touched the engine, the exports, or the rows. Fable's own suite run after
  both fixes: 225 of 225 in 10 min 47 s, load 0.02 (`fable-probe/zig-build-test.log`).
- Fable's probes (`fable-probe/probe.py`, 22 of 22 under both runtimes): a
  non-ASCII and an empty line, a 60,000-byte line across four records, a
  KeyUpdate from `s_client`, a client offering only the 256-bit suite refused
  with `handshake_failure` and the server serving after, fifty concurrent
  handshakes, the served certificate byte-equal to `cert.pem`, a wrong trust
  root refused, a socket dropped mid-line leaving the server up, and resident
  growth over 200 open-and-close cycles of 1.2 MB (`mo run`) and 0.6 MB (binary).

Reading: **fit to ship as the first half of the TLS brick, marked as half.**
The acceptance is sound because the lead ran the suite and its own probes; the
worker's report alone would not have supported it.

## The bricks page's five audit items, for this half

1. **Rows.** Present: `platform.tls`, `Tls.server(cert:, key:)`,
   `TlsServer.accept(conn, within:)`, `Tls.fixture()`, in chapter 9's `## Tls`.
2. **The standard's vectors.** Partly present: the RFC 8448 key schedule is a
   test in the brick file. The full RFC 8448 traces (the handshake transcripts
   as messages, including HelloRetryRequest and resumption) are not replayed;
   the interop tests use Zig's client, not a recorded trace. Deferred to step 37.
3. **A differential run.** Absent as the page defines it (a thousand generated
   inputs against OpenSSL with a mismatch count). What exists is interop with
   OpenSSL as the client in every bench and abuse row, which is a different and
   weaker item. Deferred to step 37, and the brief for step 37 must say so.
4. **A fuzz budget.** Absent. No CPU-hour on the record and handshake parsers.
   Deferred to step 37.
5. **A reading.** Not yet; this file and the auditor's are readings of the
   evidence, not of the native code against the surface cap. The brick sits on
   the shelf `unread` until someone reads `tls.zig` line by line.

So two of five items are present for this half (rows, and the schedule vector
partly), three are owed to step 37. Fable's view: that is the right split for a
brick whose second half changes the parser's surface (the client side, the
certificate chain, ALPN), since a fuzz and a differential run on the server
alone would be rerun in full after part two. The cost of the split is that
program 7 cannot start on the TLS brick until step 37 closes items 3 and 4.

## The numbers, and the caveat that is wrong

Handshakes a second: 1,026 (`mo run`) and 1,196 (binary) with Ed25519 and
AES-128-GCM; 765 and 804 with P-256. Bulk: 488 and 477 MB/s plain, 203 and 268
over AES-128-GCM, 121 and 155 over ChaCha20-Poly1305. A round trip on short
lines within the brief's 2×. Idle memory 9.6 and 12.6 KiB per TLS connection.

**The load condition on `audit/evidence/2026-09-17/README.md` is not material
to these numbers, and the Result's parenthetical saying they were "taken with
an orphan on one core" is a lead error.** The orphan was killed at 21:26 UTC.
The bench needs part B's rows, committed at 22:00 UTC, and its outputs were
committed with part C at 22:40 UTC, so the four runs took place between 22:00
and 22:40 UTC, after the kill. The step-36 evidence README already says the
machine was quiet (load 0.38 at 22:48 UTC); the plan page's Result and the
"carried" line contradict it. The raw outputs carry no timestamps of their
own, so this ordering rests on commit times, which is the weakest kind of
evidence for it. Fable will correct the Result with a dated note and a
decision-log row after this reading is filed, and every future bench output
will print `uptime` and the date at its head so this cannot recur.

What is a real finding in the numbers: a record costs 2 to 4× a plain write on
bulk, and the cause named by the worker (one extra copy per byte, socket to
engine to buffer) is a runtime row for a later step, not a step-36 defect.
ChaCha20's ratio is `std.crypto`'s on a CPU without a ChaCha instruction.

## What this reading did not verify, said plainly

1. **A KeyUpdate from the server is never delivered.** The brick queues it and
   the test checks the queue; no client ever received one. Step 37's client is
   the first place it can be exercised end to end.
2. **Two tests swallow `TestTimedOut` behind an assertion.** A future hang in
   those two would report as an assertion failure, not a timeout; the harness
   cannot hang, but the diagnosis is worse than it should be.
3. **A stream that ends without close_notify reads as `eof`.** The truncation
   is left to the program. Program 7's spec must decide how a Redis client's
   drop mid-command is read; the brick does not.
4. **macOS and cross-compilation.** Every run was Linux; nothing on a Mac yet.
5. **Constant time, side channels, and the certificate parser against
   malformed PEM.** Nothing measured the first; the abuse run covers the
   handshake's rejections, not the PEM parser's.
6. **The idle-memory row counts Python's ssl clients, not Mo's.** The thousand
   connections were opened by Python; the per-connection figure is the server's
   resident growth divided by a thousand, which includes buffers sized by the
   client's behaviour.

## Where this leaves the claims under audit

Nothing here tests the runtime claim or the capabilities claim directly. For
the capabilities rule, the step establishes that a TLS server at zero
third-party runtime dependencies is buildable and its cost is a known multiple
of a plain socket in both runtimes. For the audit process itself, the step is
the first case where the lead's verification overturned a worker's green
twice, which is the argument for the rule now in the skill: a worker's green
is a claim, and the lead's own suite run is the gate.

---
title: "Step 37: the TLS brick, part two: the client, the chain, ALPN, and the audit items"
created: 2026-09-18
updated: 2026-09-18
type: plan
tags: [stdlib, security, runtime, programs, audit]
sources:
  [
    plans/interpreter-step-36.md,
    deep-dives/bricks-and-the-cost-of-zero-dependencies.md,
    spec/design-v0/09-stdlib.md,
  ]
status: in-progress
---

# Step 37: the TLS brick, part two: the client, the chain, ALPN, and the audit items

The second half of the TLS brick ([[interpreter-step-36]] is the first: a TLS
1.3 server engine over bytes, written once in Zig and used by both runtimes,
with a `Conn` that stays a `Conn`). This half adds the client side, so a Mo
program can open a TLS connection and not only accept one; the certificate
chain checked on the client, up to a trusted root, with the host name and the
dates; ALPN on both sides; a KeyUpdate that either side can start and that a
peer receives; and the two audit items the bricks page requires that the
server half deferred: the differential run against OpenSSL and the fuzz hour.
It also closes the four things the auditor's reading of step 36 found
(`audit/mo-audit-2026-09-18-step-36.md`, the rows of 18 Sep in the
[[decision-log]]), which are Done-when items here and not waived. Still out of
the cut, both halves: TLS 1.2, tickets, resumption, PSK, 0-RTT, client
certificates, renegotiation, OCSP.

**Sealed 18 Sep 2026, 03:05 UTC (17 Sep, 11:05 PM ET), before the worker
started.** Everything above `## Result` was written before the work.

## Orientation

Step 36's brick and its seams: `toolchain/src/bricks/tls.zig` (the server
engine, its exports `mo_tls_server_new`, `conn_new`, `feed`, `read`, `write`,
`flush`, `sent`, `close`, `ready`, `alert`, `pending`; its tests, including the
two against Zig's own client at lines 1392 to 1398 and the matrix against the
brick's own `TestClient` at 2099 to 2109), `src/tls_rows.zig` (the interpreter's
rows), `runtime/mo_rt.h` and `mo_rt.c` (search `mo_tls_`), `cbuild.zig` (the
`.bricks/` cache and the link), `src/net.zig` and `src/sources.zig` (how a
`Conn` reads and writes through the engine after `accept`). The spec: the
`## Tls` section of `09-stdlib.md` (the rows, `TlsError`, the cut, the fixture
paragraph); `## Net` for `connect` and `Conn`'s rows. The bricks page's five
audit items and the TLS cap: [[bricks-and-the-cost-of-zero-dependencies]].
Zig 0.16's `std/crypto/Certificate.zig` (`parse`, `Parsed.verify(issuer, now)`,
`Parsed.verifyHostName`, `subjectAltName`) and `Certificate/Bundle.zig`
(`verify`, `find`, `addCertsFromFilePath`: read how a bundle is keyed, and
keep the brick's own bundle in memory from PEM text, since the brick reads no
files); `tls/Client.zig` (`init`'s `host` and `ca` options show what a client
checks; it has no ALPN, so the brick writes the extension itself on both
sides, RFC 7301). OpenSSL 3.0 on the VM (`s_client`, `s_server`, `req`,
`x509`, `verify`) is the dev-time reference, never linked. The step-36 bench:
`toolchain/bench/step36/` (`common.py` starts the echoes and drives
`s_client`; `abuse.py`, `handshake.py`, `bulk.py`, `idle.py`, `guard.py`).

Read `audit/mo-audit-2026-09-18-step-36.md` sections "Fixes and Done-when"
and "Five audit items and the cap" before part A: they name what this step
closes.

## Write scope

`toolchain/` (the brick, the rows, the runtime, the build, `PRELUDE.md`,
`bench/step36/` for the fixes named in part C, a new `bench/step37/`),
`examples/effects/tls-client.mo` with its `.expected`, `examples/effects/tls/`
(new fixtures and the script that generated them), `examples/effects/tls-echo.mo`
only if the chain fixtures change what it reads, `examples/README.md`'s list,
the `.mo.ids` sidecars, and these spec lines only: rows added to the `## Tls`
section of `09-stdlib.md` in the file's table form, one variant added to
`TlsError`, and a paragraph on what the client checks; the runtime paragraph
of `toolchain/README.md`. Nothing else under `mo-wiki/`.

## Parts

A. **The brick: the client, the chain, ALPN, KeyUpdate, and the tests owed.**
In `toolchain/src/bricks/tls.zig`, the client's half of the handshake as the
server's was written: an engine over bytes, no sockets, no allocator of the
runtime's, so both runtimes drive it from their own socket and scheduler.
Exports, beside step 36's:

```
mo_tls_client_new(trust_pem, n)            -> client or an error naming what failed (one or more root certificates, PEM)
mo_tls_client_offer(client, protocols, n)  # ALPN: the protocols the client will offer, in order (a list of NUL-separated names)
mo_tls_server_offer(server, protocols, n)  # ALPN: the protocols the server accepts, in its order of preference
mo_tls_connect(client, host, n, now_sec)   -> conn: the ClientHello is queued for flush; `host` for SNI and the name check; `now_sec` for the dates
mo_tls_protocol(conn, out, cap) -> n       # the ALPN protocol agreed, 0 when none
mo_tls_key_update(conn, request_peer)      # queues a KeyUpdate from this side; with request_peer the peer must answer with its own
mo_tls_client_free(client)
```

The client: ClientHello with X25519, the two suites, SNI, the signature
algorithms Ed25519 and ECDSA P-256 SHA-256, ALPN when offered, and one
HelloRetryRequest answered; the server's flight read and checked (the
transcript, CertificateVerify against the leaf's key, Finished); the client's
Finished sent; then records as the server side does them, KeyUpdate answered
and started, close_notify both ways. **The chain:** the leaf's name checked
against `host` (DNS names and IP addresses in the subject alternative name,
the common name only when there is no SAN, as Zig's `verifyHostName` does),
each certificate signed by the next, the last signed by a root in the trust
set, every certificate's dates against `now_sec`; the chain as sent, leaf
first, at most a depth of five; a failure is the alert RFC 8446 names
(`bad_certificate`, `unknown_ca`, `certificate_expired`, and
`bad_certificate` for a name mismatch), then `closed`. A chain whose signing
algorithm the cut does not cover (RSA) is `unsupported_certificate`. **ALPN:**
when both sides offered and share nothing, the server sends
`no_application_protocol` (120); when the client offered and the server has
no list, no extension goes back and `protocol` is empty; when the server has
a list and the client offered none, the handshake proceeds without ALPN.
**KeyUpdate:** `mo_tls_key_update` on either role queues the message under
the current write keys and moves this side's write keys; a peer's
`update_requested` is answered as step 36 does. The server's `keyUpdate` and
the client's are one function.

The tests owed from step 36, in the same file: the two tests against Zig's
own `tls.Client` iterate both suites and both key types (four sessions each
for the megabyte and the small handshake), so the matrix the step-36 brief
asked for runs against an implementation that does not share the brick's
record layer; the two tests that swallow `TestTimedOut` behind an assertion
report the timeout by name; and the RFC 8448 section 3 handshake replayed
through the **client** with the trace's ephemeral X25519 key and random
injected, the bytes of the ClientHello and the client's Finished compared to
the trace (a test hook that lets a test set the client's entropy, in the test
build only). New tests: a full handshake and a megabyte both ways brick client
to brick server in memory, each suite and each key type, with and without
ALPN; the chain of three (root, intermediate, leaf) accepted, and each of the
refusals above produced by a chain built for it (wrong host, expired, unknown
root, a chain with a link missing, depth six, an RSA leaf); a KeyUpdate
started by the client received and answered by the server and the reverse,
records flowing after each; the five rejections of step 36 fed to the client
side (a truncated record, a wrong Finished, a record past the limit, a bad
tag, a plain HTTP response where a ServerHello belongs). Every test that can
block has a deadline on every read and write, as fix 1 made the rule.

B. **The rows, both runtimes.** Added to the `## Tls` section, with each
row's crash rule as chapter 9 writes them:

```ruby
enum TlsError
  BadPem
  Handshake
  Timeout
  Closed
  Untrusted     # the chain does not lead to a trusted root, a name or a date is wrong; the alert has been sent, the conn is closed
end

Tls.client(trust: String) : Result(TlsClient, TlsError)                  # PEM text: one or more root certificates; BadPem when none parse
TlsClient.connect(conn: Conn, host: String, within: Duration) : Result(Conn, TlsError)
                                                                          # the client's half of the handshake on a Conn from Net.connect; the same Conn, its bytes now records
TlsClient.offer(protocols: List(String)) : TlsClient                      # ALPN, the client's list in order; a new client, the old unchanged
TlsServer.offer(protocols: List(String)) : TlsServer                      # ALPN, the server's preference order; a new server, the old unchanged
Conn.protocol : Option(String)                                            # the ALPN protocol agreed; None on a plain Conn or when none was agreed
```

`TlsClient` is what `TlsServer` is: no authority beyond its trust set, may be
stored and shared. `connect` takes a `Conn` that has had no `read_line`,
`write`, or `lines` on it (a crash names the row otherwise) and waits at most
`within`; `Handshake`, `Timeout`, and `Closed` as `accept` gives them;
`Untrusted` after the alert is written. The dates are checked against the
runtime's clock, which under `Tls.fixture()` is the simulator's (`Time.fixture()`
moved by fixture waits), so a test's certificates are valid on 2026-01-01.
Under `Tls.fixture()` a client and a server handshake on `Net.fixture()`'s
in-memory network, both driven by the simulator: a test can now run the whole
handshake in a `mo test --sim`. Both runtimes call the same exports; the
interpreter's `Conn` and the C runtime's read and write through the engine
for a client connection exactly as they do for an accepted one (one code path
per runtime, the role a field of the connection).

C. **The audit items, the corpus, the bench, and the fixes owed.**
*Fixtures:* `examples/effects/tls/gen.sh`, checked in, that generated with
`openssl` everything under `tls/`: for each key type (Ed25519, P-256) a root
CA, an intermediate signed by it, and a leaf for `localhost` (SAN `DNS:localhost,
IP:127.0.0.1`) signed by the intermediate, valid from 2025-01-01 for ten
years; the server's `cert.pem` and `cert-p256.pem` become the chain leaf first
(leaf, intermediate); `root.pem` and `root-p256.pem` the trust files; and the
refusal set: a leaf for `example.org`, an expired leaf (dates set as OpenSSL
3.0 on this machine allows; say how in the README), a second root that signed
nothing here. *Corpus:* `examples/effects/tls-client.mo`: `main` reads
`tls/root.pem`, connects to the host and port in `args`, handshakes, writes one
line, prints the echo, and exits; its `.expected` from a run against a port
nothing listens on (prints the `Refused`). Its tests under `Tls.fixture()`: a
server from `cert.pem` and a client from `root.pem` handshake in memory and a
line goes each way; the same with ALPN `["mo/1", "echo/1"]` against a server
offering `["echo/1"]` and `protocol` is `echo/1`; a client offering
`["mo/1"]` against that server is `Handshake`; a client trusting the second
root is `Untrusted`; a client given `host: "example.org"` against the
`localhost` leaf is `Untrusted`. *Spec:* the rows and the paragraph named in
the write scope.

*The fixes owed to step 36's bench* (`bench/step36/`): `abuse.py` checks an
echo **immediately after each case** and its table says so; the oversized
case is labelled for what it sends (a header declaring 65,535 bytes and 64
bytes of body) and a second case sends a real 64 KiB body in one record;
`handshake.py` checks `s_time`'s exit code and reports the connection count
`s_time` prints; `bulk.py` states its units; every output file under `work/`
begins with the date and `uptime` as its first two lines. Rerun `abuse.py`
under both runtimes after the fixes.

*The bench* (`bench/step37/`, a `uv` project with no dependencies, `guard.py`
shared with step 36): `diff.py`, the differential run the bricks page names:
1,000 sessions, seed on the command line, each with parameters drawn at
random (the role, so that about half run the Mo server against `openssl
s_client` and half the Mo client against `openssl s_server`; the key type; the
client's suite order and groups, including `P-256:X25519` for the retry; an
ALPN list on each side or none; SNI on or off; a chain from the fixture set,
good or one of the refusals; the record sizes and count of an echo exchange
from 0 to 20,000 bytes; a KeyUpdate injected from `s_client`'s or
`s_server`'s `K` or from the brick, or none; who closes first), and for each
the compared facts: whether the handshake completed, the suite agreed, the
ALPN agreed, the bytes echoed, the alert number when it failed, on the Mo side
from the brick's engine and on OpenSSL's side from its `-msg`/`-state` output
or its exit status; the mismatch count on the page, expected 0; every session
under `guard.py`. `fuzz.py`: one CPU-hour, seed on the command line, on the
parser side of both roles: a Zig fuzz driver built by `zig build` (a test
executable that reads one input from a file and feeds it to a fresh server
connection and a fresh client connection at each handshake state, with a
deadline on every step) fed mutated inputs from a corpus of recorded valid
transcripts (the fixture handshakes' bytes for each suite, key, and ALPN
case, recorded once by a script); a crash is a signal, an abort, a Zig panic,
or a step that does not return within its deadline; the count on the page,
expected 0, dated. `measure.py`: best of five, both runtimes, the date and
`uptime` at the head of every output: client handshakes a second against
`openssl s_server` (each key type); Mo client to Mo server handshakes a
second; 100 MiB through a Mo-to-Mo TLS connection against Mo-to-Mo plain;
the cost of the chain check (handshakes a second with the chain of three
against a self-signed leaf, the client side); `mo build` warm on
`examples/programs/jobq` before and after, and the binary's size before and
after. `README.md` saying how to run everything, and `RESULTS.md` with the
raw tables.

## Numbers

The tables `measure.py` produces, the differential run's mismatch count over
1,000 sessions with its seed, the fuzz hour's crash count with its seed and
date, the abuse table after the fix, the step-36 numbers reproduced once with
the fixed scripts (handshakes and bulk, to show the fixes changed nothing),
and the load average beside each table. Say where a client handshake costs
more than a server one, and what the chain check costs.

## Done when

`timeout 1800 zig build test --summary all` green, with the summary line
(the count of tests and steps) and the exit code copied into the report as
printed, run twice; the corpus green under both runtimes inside that suite;
`mo fmt` clean; the tests owed from step 36 present (the Zig-client matrix,
the named timeouts, the RFC 8448 client replay); `diff.py` at 0 mismatches
over 1,000 sessions; `fuzz.py` at 0 crashes over 60 minutes, dated;
`abuse.py` green under both runtimes with the per-case check; a KeyUpdate
started by the brick received by `openssl s_client` and by `openssl s_server`
with records flowing after, and one started by each of them received by the
brick, shown in `diff.py`'s log; the spec lines and the README paragraph
written; the numbers table; a numbered list "Decisions the brief did not
cover". One commit per part, subject `Step 37 part X`, pushed after each,
with `zig build test` green at each commit as the report's summary lines
show, never as a claim.

## Related

- [[interpreter-step-36]]
- [[bricks-and-the-cost-of-zero-dependencies]]
- [[09-stdlib]]
- [[the-audit-workflow]]
- [[roadmap]]

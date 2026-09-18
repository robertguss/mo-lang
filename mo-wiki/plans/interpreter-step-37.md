---
title: "Step 37: the TLS brick, part two: the client, the chain, ALPN, and the audit items"
created: 2026-09-18
updated: 2026-09-18
type: plan
tags: [stdlib, security, runtime, programs]
sources:
  [
    plans/interpreter-step-36.md,
    deep-dives/bricks-and-the-cost-of-zero-dependencies.md,
    spec/design-v0/09-stdlib.md,
  ]
status: done
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

**Sealed 18 Sep 2026, 02:36 UTC (17 Sep, 10:36 PM ET; the line first said 03:05, a lead error, corrected at the Result), before the worker
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

## Result (18 Sep 2026, 3:50 AM ET; one Opus session 10:37 PM to 2:15 AM ET, one fix session after; accepted by Fable)

Four commits: `f8d8dfc` (part A, the brick's client half, the chain, ALPN, KeyUpdate either way, the tests owed, the fixtures and `gen.sh`), `9f83dde` (part B, the rows in both runtimes, the fixture's whole handshake, `tls-client.mo`), `0493b26` (part C, the differential run, the fuzz hour, `measure.py`, the step-36 bench fixed, the spec lines), `b0b2ac4` (the fix below). `toolchain/src/bricks/tls.zig` is 4,136 lines with 25 tests; `bench/step37/` holds `diff.py`, `fuzz.py` and its Zig driver, `peer.zig` (the brick's exports over a socket for the differential run), `measure.py`, `tls-dial.mo`. The spec's `## Tls` gained `Tls.client`, `TlsClient.connect`, `TlsClient.offer`, `TlsServer.offer`, `Conn.protocol`, `TlsError.Untrusted`, and the paragraph on what the client checks.

**The audit items, now.** Rows: present. The standard's vectors: the RFC 8448 section 3 handshake replayed through the client with the trace's random and key, its ClientHello, Finished, application record and close_notify equal to the trace byte for byte (test-only hooks). The differential run: **1,000 sessions against OpenSSL 3.0.13, seed 3737, 0 mismatches** (`bench/step37/RESULTS.md`: 484 with the brick as server, 516 as client; 597 handshakes completed, 403 refused across ten chain shapes; every KeyUpdate direction read and answered in the log; a first run with the same seed had 3 mismatches, all in the harness's model of OpenSSL, named on the page). The fuzz hour: **87,440 inputs, seed 3701, 0 crashes, 3,601 CPU s**, 05:01 to 06:01 UTC, after a planted panic and a planted hang were each counted by the detector. The reading: not yet; both halves stay `unread` until someone reads the 4,136 lines against the cap.

**Numbers** (the VM's four cores, best of five, both runtimes, load beside each table on `RESULTS.md`):

| measure | `mo run` | binary |
|---|---:|---:|
| the brick's client against `openssl s_server`, chain of three, Ed25519 / P-256, handshakes a second | 1,001 / 286 | 1,354 / 295 |
| Mo client to Mo server, Ed25519 / P-256 | 942 / 271 | 1,445 / 280 |
| 100 MiB Mo to Mo, plain / TLS (MB/s) | 43.7 / 38.6 (1.1×) | 336.9 / 256.6 (1.3×) |
| the chain check, P-256, µs a handshake, chain of three / self-signed | 3,507 / 2,762 | 3,405 / 2,713 |
| step 36's server handshakes with the fixed script, its own pairs, Ed25519 AES-GCM (step 36 in brackets) | 1,113 (1,026) | 1,240 (1,196) |
| the same with the chain of three served and verified by `s_time` | 790 | 837 |
| jobq's warm build / binary size, before → after | 0.10 → 0.09 s | 5,429,960 → 5,541,240 bytes (+111 KiB) |

A P-256 client handshake costs more than twice a server one (three ECDSA verifications against one; `std.crypto`'s P-256 verify is about 700 µs here); with Ed25519 the client is not the slower side. The chain of three costs the server's rate a fifth to a third when the client verifies it. The record's cost Mo to Mo is inside 1.3×: the interpreter's per-line cost dwarfs the AEAD. The fixed step-36 scripts reproduce step 36's numbers within 9 percent, above them.

**What verification found.** Fable's suite run on `main` at `0493b26`: **234 of 234, exit 0, 12 min** (`fable-probe/zig-build-test.log`, load 0.9 at the start). Fable's probes (`fable-probe/probe37.py`: the Mo client against Python's ssl, which is OpenSSL 3.5.7 here, a different OpenSSL from the bench's 3.0.13, and Python's client against the Mo server, both runtimes): the Ed25519 and P-256 chains echoed, the chain of five accepted, the chain of six, the wrong root, the wrong name, the expired leaf, the non-CA issuer each `Untrusted`, an IP SAN matched, a server with an ALPN list against a client offering none echoed, the 60,000-byte line read whole, a server that closes before its hello `Closed`; Python's client verified the chain to `root.pem`, agreed no ALPN, refused the other root and the wrong name, a TLS 1.2-only client refused, the server serving after, the leaf served byte-equal to `cert.pem`. **One defect:** a server that answers the ClientHello with a fatal alert (a TLS 1.2-only server, or one that refuses the brick's signature schemes, which is what an RSA-certificate server does) is reported `Closed` by `connect` under both runtimes over a socket, where the spec says `Handshake` and the fixture path already gives `Handshake` (`fable-probe/alert-probe.py`, a raw server sending `protocol_version` with the socket kept open). Fixed by the fix session below, which also found a **double free in the C runtime's handshake** that crashed the binary server (SIGSEGV) after any client that reset mid-hello or aborted with the server's flight unread, never seen under `mo run`. **Two expectations of Fable's were wrong**, not the brick's: a server that closes right after the handshake without close_notify makes the client's `write` `Closed`, as a plain socket would; and the RSA case fails on the server's side first. **The public internet is out of reach:** `www.google.com` and `example.com` with the system's roots are `Untrusted`, since their chains pass through RSA or P-384 signatures the cut refuses (the worker's decision 7). Program 7 needs no public host; the shelf entry must say so.

**Decisions the brief did not cover**, thirty-one from the worker (`worker-raw/worker-report-SYNTHESIS.txt`), read and ratified as rows of 18 Sep in the [[decision-log]] except where a row says otherwise. The ones that matter most: refusal alerts follow OpenSSL 3.0's choices (a chain past five, an untrusted root, a missing link, a non-CA issuer are `unknown_ca`); the chain is checked strictly as sent, no reordering; every certificate is shape-checked before Zig's DER parser sees it, since that parser has no bounds checks; the brick verifies signatures itself (Ed25519, ECDSA P-256) because `Parsed.verify`'s RSA code cost 6 s of compile, and **P-384 and SHA-384 chains are refused** as `unsupported_certificate` (2.5 s more compile); Zig's own client cannot check an Ed25519 CertificateVerify, so the two Ed25519 cells of the Zig-client matrix assert its `TlsBadSignatureScheme`, and full Ed25519 sessions rest on OpenSSL and the brick's own client; the middlebox-compatibility session id and change_cipher_spec; a NewSessionTicket read and dropped; `s_server -stateless` drops the cookie retry, so the cookie HelloRetryRequest is tested brick to brick only; the fixture's `lines` loop on a TLS connection scanned ciphertext in step 36, never exercised, now reads through the engine; the fuzz hour (a correctness run) overlapped the first final suite run, load up to 1.5.

**Carried.** Two runtime rows found by `measure.py`, both for a step before program 7's build: **a `Conn` cannot stream both ways at once** (a read waits while a write on the same connection is blocked, so writing from `main` while `lines` reads the same `Conn` stalls until the write's deadline), and **Nagle is on** (no `TCP_NODELAY`, about 40 ms a window on a write-then-read pattern). Also: no Mo row starts a KeyUpdate (an export only); the cookie retry untested against OpenSSL; the shelf's reading item; the crunch of `List(UInt8)` unchanged; the auditor's capsule rule applied here for the first time (the pane transcript is marked synthesis, the suite log stands alone).

## Fix, 18 Sep 2026, 2:30 AM ET: a peer's alert during the handshake is reported `Closed`

Found by the lead's probe (`audit/evidence/2026-09-18/step-37/fable-probe/probe37.py`, cases "server speaking TLS 1.2 at most" and "RSA leaf" against Python's ssl, and `alert-probe.py`, a raw server that answers the ClientHello with a fatal `protocol_version` alert and keeps the socket open): under both runtimes, over a real socket, `TlsClient.connect` returns `Closed` when the server answers the handshake with a fatal alert. The spec's row says `Handshake` "as `accept` gives it", and `accept`'s row says `Handshake` when the client "sent an alert". The brick already records the alert and its origin (`Conn.alert`, `alert_from_peer`, `peerAlert` in `tls.zig`); the socket handshake path in `net.zig` (`readTls`, the `brick.closed` and `brick.failed` arms) and in `mo_rt.c` (`tls_handshake`) map both to `Closed`. Under `Tls.fixture()` the same case is `Handshake` (the corpus test "a client offering only what the server does not speak is Handshake" passes), so the fixture path and the socket path disagree.

**Decision (Fable):** a fatal alert from the peer during the handshake is `Handshake` on both roles and both runtimes, over a socket as under the fixture; `close_notify` or `user_canceled` from the peer, or the stream's end, stays `Closed`. After the handshake nothing changes: a peer's alert ends the stream as it does today.

**Added 2:40 AM ET, the same fix session: the binary server dies on a client's alert.** `fable-probe/server-alert-probe.py`: Python's ssl client trusting the other root refuses the server's chain and sends a fatal `unknown_ca` alert after the server's flight; the `tls-echo` **binary** then exits with SIGSEGV (rc -11) and the next client is refused; under `mo run` the server echoes on. The C runtime's handling of a peer's alert during the handshake is the common cause of both findings. **Done when, added:** `server-alert-probe.py` passes for both runtimes (the server echoes before and after the alert, and stays alive), with the crash's cause named in the commit message; a brick or runtime test that sends a fatal alert to a server mid-handshake, both runtimes.

**Outcome (fix session 2:31 to 3:24 AM ET, `b0b2ac4`).** Two causes, both in the runtimes, the brick unchanged: (1) the brick's `peerAlert` records a fatal alert and fails the connection, but `mo_tls_feed` returns `ok` (the alert was read, not answered), so both socket handshakes read again and reported the stream's end; they now ask `mo_tls_read` after each read as the fixture path did, `failed` is `Handshake` (or `Untrusted` when this client refused the chain), `closed` is `Closed`. (2) The binary's crash was a double free in `mo_rt.c`'s `tls_handshake`: a read that broke (a reset mid-hello, or a client that aborts with the server's flight unread) freed the engine through `net_close`, and the handshake freed it again; the next connection's engine then crashed in `mo_tls_feed`. A brick test and a corpus test (a Mo TLS server under both runtimes over real sockets, five raw clients: alert, reset, alert, reset, alert, expecting `Handshake`, `Closed`, `Handshake`, `Closed`, `Handshake`) fail on the old runtimes and pass now. The worker's suite: 236 of 236, exit 0, in 28 minutes (the brick change invalidated every corpus directory's brick cache, a carried row); `alert-probe.py`, `server-alert-probe.py`, and `abuse.py` green under both runtimes. Fable's own suite run and probe reruns after the fix: `fable-probe/zig-build-test-after-fix.log`, `probe37-after-fix.log`, `alert-probe-after-fix.log`, `server-alert-after-fix.log`.

**Write scope:** `toolchain/src/net.zig`, `toolchain/runtime/mo_rt.c` (the socket handshake paths only), `toolchain/src/bricks/tls.zig` only if an export is needed to tell a peer's fatal alert from the stream's end (say which), a brick test and one row test per runtime if the runtimes' tests have a place for it, `toolchain/bench/step36/abuse.py` gains no case. Nothing under `mo-wiki/`.

**Done when:** the lead's `alert-probe.py` prints `Handshake` for "alert then close" and "alert, socket kept open", and `Closed` for "close only" and "RST", under `mo run` and as a binary; `TlsServer.accept` against a client that sends a fatal alert instead of a hello is `Handshake` (a python client in the probe); `timeout 1800 zig build test --summary all` green once with its summary line and exit code in the report; `uv run python abuse.py` in `bench/step36` green under both runtimes; one commit `Step 37 fix: a peer's alert is Handshake`, pushed.

## Related

- [[interpreter-step-36]]
- [[bricks-and-the-cost-of-zero-dependencies]]
- [[09-stdlib]]
- [[the-audit-workflow]]
- [[roadmap]]

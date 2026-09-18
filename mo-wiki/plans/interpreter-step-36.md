---
title: "Step 36: the TLS brick, part one: a TLS 1.3 server in both runtimes"
created: 2026-09-17
updated: 2026-09-17
type: plan
tags: [stdlib, security, runtime, programs]
sources:
  [
    deep-dives/bricks-and-the-cost-of-zero-dependencies.md,
    plans/interpreter-step-35.md,
    spec/design-v0/09-stdlib.md,
    spec/design-v0/06-packages.md,
  ]
status: in-progress
---

# Step 36: the TLS brick, part one: a TLS 1.3 server in both runtimes

The second brick under the bricks page
([[bricks-and-the-cost-of-zero-dependencies]]) and the large one: Zig 0.16
ships a TLS 1.3 client (`std/crypto/tls/Client.zig`, 1,670 lines) and the
record layer's types and key schedule (`std/crypto/tls.zig`, 758 lines), no
server. Program 7's spec runs Redis's suite with `--tls`, so Mo needs a TLS
listener. The brick is written once, in Zig, like step 35's, and used by both
runtimes. This step is the server handshake and the record layer; step 37 is
the client side with the certificate chain, ALPN, and the differential run
against OpenSSL. Nothing of TLS 1.2, tickets, PSK, 0-RTT, or client
certificates in either.

## Orientation

Step 35's brick and its two seams are the pattern: `toolchain/src/bricks/crypto.zig`
(C-ABI exports over `std.crypto`; the interpreter imports it, `mo build`
compiles and caches it), `src/crypto_rows.zig` (the rows), `cbuild.zig` (the
`.bricks/` cache and the link), `runtime/mo_rt.h` and `mo_rt.c` (the
declarations and the C rows that only call the exports). The sockets:
`src/net.zig` (`Conn`, its buffer, `readLine`, `writeAll`, the poller's
fibers), `src/sources.zig` (how `serve` and `lines` pump), and their C twins in
`mo_rt.c` (search `read_line`, `lines`, `Accepted`). The spec: `09-stdlib.md`
`## Net` (the `Conn` rows and `NetError`), `## Rules for every row`, `## Files`
for the shape of a capability's section; `06-packages.md` for what a brick is.
Zig's TLS: `tls.zig` (`ContentType`, `HandshakeType`, `ExtensionType`,
`CipherSuite`, `HandshakeCipherT`, `ApplicationCipherT`, `hkdfExpandLabel`,
`Decoder`), `tls/Client.zig` (`init` is the whole client handshake; read it for
the record layer, the transcript hash, the key schedule, and how it reads
records, then write the server's half), `Certificate.zig` (DER parsing,
`parse`, the public key and its algorithm), `crypto/ecdsa.zig` (P-256 signing,
`EcdsaP256Sha256`), `25519/ed25519.zig`. OpenSSL 3.0 is on the VM at
`/usr/bin/openssl` (`s_client`, `s_server`, `req`, `s_time`): dev-time tooling,
allowed by the bricks page, never linked.

## Write scope

`toolchain/` (the brick `src/bricks/tls.zig`, the rows, the runtime, the
build, PRELUDE.md, `bench/step36/`), `examples/effects/tls*.mo` with their
`.expected` and a `examples/effects/tls/` folder for the PEM fixtures,
`examples/README.md`'s list, the `.mo.ids` sidecars, and these spec lines only:
a `## Tls` section in `09-stdlib.md` in the file's table form after `## Http`,
and the runtime paragraph of `toolchain/README.md`. Nothing else under
`mo-wiki/`.

## Parts

A. **The brick, an engine over bytes.** `toolchain/src/bricks/tls.zig`, C-ABI
exports, no sockets and no allocator of the runtime's: a server holds a parsed
certificate chain and its private key; a connection is a state machine that
takes ciphertext in and gives plaintext out, and plaintext in and ciphertext
out, so each runtime drives it from its own socket and scheduler and the brick
is written once:

```
mo_tls_server_new(cert_pem, key_pem) -> server or an error naming what failed
mo_tls_conn_new(server) -> conn
mo_tls_feed(conn, bytes)                      # ciphertext from the socket
mo_tls_read(conn, out) -> n | want_more | closed | alert   # plaintext the records held
mo_tls_write(conn, plain)                     # plaintext the program wrote
mo_tls_flush(conn, out) -> n                  # ciphertext to put on the socket (handshake replies too)
mo_tls_close(conn)                            # queues close_notify
mo_tls_free(conn), mo_tls_server_free(server)
```

The server handshake per RFC 8446: ClientHello (versions, the two suites
`TLS_AES_128_GCM_SHA256` and `TLS_CHACHA20_POLY1305_SHA256`, the key share on
X25519, a HelloRetryRequest once when the client supports X25519 but sent no
share for it, `handshake_failure` otherwise, SNI read and ignored, ALPN read
and left unanswered until step 37), ServerHello, EncryptedExtensions,
Certificate (the chain as given, leaf first), CertificateVerify (Ed25519 or
ECDSA P-256 by what the key is), Finished; the client's Finished checked; the
key schedule and transcript hash as `Client.zig` does them; application records
both ways with the sequence numbers and the 16 KiB limit; `KeyUpdate` from the
client answered when it asks, and one sent on request of the runtime (never
needed this step); `close_notify` both ways; every alert the client sends is
`closed` with its description. The record layer's AEADs, HKDF, X25519, and the
signatures come from `std.crypto`, nothing hand-rolled. PEM: the certificate
chain and a PKCS#8 private key (`BEGIN PRIVATE KEY`, Ed25519 or P-256), the
only forms `openssl req -newkey ed25519` and `-newkey ec` write. Unit tests in
the file, run by `zig build test`: a full handshake and a megabyte both ways
against Zig's own `std.crypto.tls.Client` in memory for each suite and each key
type (the client set to trust the test certificate); the RFC 8448 key
schedule's derived secrets from its section 3 transcript (the traces are a
client's; the schedule is shared); a truncated record, a wrong Finished, a
record past 16 KiB plus 256, and a bad tag each rejected with the alert RFC
8446 names; a KeyUpdate round trip.

B. **The rows, both runtimes.** One capability, `Tls`, `platform.tls` in
`main`, and a `Conn` that stays a `Conn`, so every row after the handshake
(`read_line`, `write`, `close`, `lines`) and every program written against a
plain socket work unchanged behind TLS:

```ruby
enum TlsError
  BadPem        # the certificate or the key does not parse, or they do not match
  Handshake     # the client's hello or finish is wrong, or it sent an alert; the conn is closed
  Timeout       # the handshake did not finish within the deadline; the conn is closed
  Closed
end

Tls.server(cert: String, key: String) : Result(TlsServer, TlsError)    # PEM text, read by the program with Fs
TlsServer.accept(conn: Conn, within: Duration) : Result(Conn, TlsError) # the handshake; the Conn it gives is the same connection, its bytes now records
```

`Tls` is a capability like `Net`: passed as a parameter, never captured (MO0409),
never stored (MO0403). A `TlsServer` holds no authority beyond its own key and
may be stored and shared (it is what a listener process starts its workers
with). `accept` takes a `Conn` that has had no `read_line`, `write`, or
`lines` on it (a crash names the row otherwise: the caller broke a rule) and
waits at most `within` for the client's handshake; the `Conn` it returns reads
and writes through the engine in both runtimes, with the same buffering rules
and `NetError`s as before, and `close` sends `close_notify` before the socket
closes. Under `Net.fixture()` the same rows work on the in-memory network, so a
test can drive a handshake once step 37's client exists; this step's tests use
the brick's own Zig client. Both runtimes call the same exports; `mo build`
compiles the TLS brick as it compiles the crypto brick (one object per brick,
each cached by its own source hash; or one object for both if that is
simpler, said in the decisions).

C. **The audit items on the page, and the corpus.** The rows in `09-stdlib.md`
as chapter 9 writes them, with each row's crash rule. `examples/effects/tls-echo.mo`:
a `main` that reads `tls/cert.pem` and `tls/key.pem` (both Ed25519, generated
once with `openssl req -x509 -newkey ed25519 -days 3650 -subj /CN=localhost`,
checked in beside a P-256 pair `tls/cert-p256.pem`, `tls/key-p256.pem`), listens
on the port in `args`, and echoes lines back through TLS; tests that a
`TlsServer` from a bad PEM is `BadPem`, that a key of the other pair is
`BadPem`, and that `accept` on a fixture connection whose client writes plain
text is `Handshake`. `examples/effects/tls-echo.expected` from a `mo run` with
no client (the program prints its port and exits on `Idle`). The
`bench/step36/` folder, a `uv` project with no dependencies: `handshake.py`
(`openssl s_client` in a loop, both suites, both key pairs: handshakes a
second and the count that failed, against the echo under `mo run` and as a
binary), `bulk.py` (100 MiB through `openssl s_client` and back, MB/s, both
suites, both runtimes), `idle.py` (1,000 idle TLS connections, the server's
resident memory before and after, per connection), `abuse.py` (a plain HTTP
request, a TLS 1.2-only client (`-tls1_2`), a client offering only P-256 key
shares (`-groups P-256`), a hello cut off mid-record, a client that never
finishes, and a 64 KiB record: each answered with the alert or the timeout the
brief names, the server still serving after), and `README.md` saying how to
run them.

## Numbers

Best of five, both runtimes, on the VM: handshakes a second with `openssl
s_client` (each suite, each key type); 100 MiB through the echo and back over
TLS against the same echo over a plain `Conn` (MB/s, both suites); resident
memory per idle TLS connection at 1,000 connections against a plain
connection's; `echo-1k`'s round trips over TLS against plain; `mo build` warm
on `examples/programs/jobq` before and after (s), and the binary's size before
and after (bytes). Say where a record costs more than twice a plain read or
write.

## Done when

`zig build test` green with the brick's tests in it (both suites, both key
types, the RFC 8448 schedule, the five rejections, KeyUpdate), the corpus green
under both runtimes, `mo fmt` clean, the four bench scripts run with their
numbers on `bench/step36/RESULTS.md`, `abuse.py` at every case answered as
named and the server serving after, the spec section and the README
paragraph written, the numbers table, and a numbered list "Decisions the
brief did not cover". One commit per part, subject `Step 36 part X`, pushed
after each.

## Fix, 17 Sep 2026, 7:30 PM ET: the KeyUpdate test hangs

The lead's verification of part C found `zig build test` never finishing: the brick's test "a KeyUpdate round trip" (`toolchain/src/bricks/tls.zig`, line 1638) deadlocks. `gdb` on the hung suite: the main thread in `writeAllFd(fd=6, 762 bytes)` inside the test's handshake loop, blocked in the kernel's `unix_stream_sendmsg`; the client thread (`ClientRun.run`, Zig's `tls.Client` over `testing.io`) and the runner's threads in `futex_wait`. Deterministic on the VM: it hung in the full suite (21 minutes before the lead stopped it) and again in `zig test src/bricks/tls.zig` alone (tests 1 to 10 pass; 11 hangs until `timeout 300`). The worker's own runs passed, so the deadlock is timing-dependent: two blocking sides over a socketpair with nothing that guarantees one of them reads.

**Write scope:** `toolchain/src/bricks/tls.zig`, its tests only; nothing in the brick's behaviour, its exports, the rows, or the runtimes changes.

**Done when:** the cause of the deadlock is named in the commit message (why the client thread stops reading, and why only this test); the test harness is made unable to hang: the main thread's writes and reads are bounded (poll with a deadline before every write as `readSomeFd` already does before reads, or a nonblocking fd with a deadline loop), the client thread is bounded the same way, and a wrong test fails with a named error within 30 seconds instead of hanging; `zig test src/bricks/tls.zig` green five times in a row; `zig build test` green twice in a row; one commit, `Step 36 fix: the KeyUpdate test`, pushed. Say in the report whether the test still exercises a KeyUpdate from the client and one from the server.

## Related

- [[bricks-and-the-cost-of-zero-dependencies]]
- [[interpreter-step-35]]
- [[09-stdlib]]
- [[06-packages]]
- [[roadmap]]

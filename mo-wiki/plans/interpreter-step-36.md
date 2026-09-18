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
status: done
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

## Result (17 Sep 2026, 10:15 PM ET; one Opus session 3:27 to 6:41 PM ET, two fix sessions after; accepted by Fable)

Five commits: `9c753e1` (part A, the brick), `dd2e385` (part B, the rows in both runtimes), `4cb0fc8` (part C, the page, the corpus, the four runs), `6af598d` (fix 1, the KeyUpdate test), `0fe9669` (fix 2, the certificate path). `toolchain/src/bricks/tls.zig` is 2,077 lines: a server engine over bytes (`mo_tls_server_new`, `conn_new`, `feed`, `read`, `write`, `flush`, `sent`, `close`), TLS 1.3 with the two suites, X25519 with one HelloRetryRequest, Ed25519 and P-256 certificates from PEM, KeyUpdate, close_notify, sixteen tests in the file (Zig's own `tls.Client` over a socketpair for each suite and key type, the RFC 8448 schedule, the five rejections, KeyUpdate). `platform.tls`, `Tls.server(cert:, key:)`, `TlsServer.accept(conn, within:)`, `Tls.fixture()`, in both runtimes; a `Conn` stays a `Conn` after the handshake. The spec's `## Tls`, `examples/effects/tls-echo.mo` with two PEM pairs, `bench/step36/` (no dependencies; OpenSSL 3.0 is the client in every run).

**Numbers** (the VM's four cores, best of five, both runtimes; `bench/step36/RESULTS.md`, taken with an orphan on one core, see `audit/evidence/2026-09-17/README.md`):

| measure | `mo run` | binary |
|---|---:|---:|
| handshakes a second, Ed25519, AES-128-GCM (`openssl s_time -new`) | 1,026 | 1,196 |
| handshakes a second, P-256 | 765 | 804 |
| 100 MiB through the echo, plain `Conn` | 488 MB/s | 477 MB/s |
| the same over AES-128-GCM | 203 MB/s (2.4×) | 268 MB/s (1.8×) |
| the same over ChaCha20-Poly1305 | 121 MB/s (4.0×) | 155 MB/s (3.1×) |
| a round trip, 1,000 short lines, plain / AES-GCM | 27 / 38 µs | 23 / 28 µs |
| resident memory per idle connection, plain / TLS (1,000 connections) | 2.9 / 9.6 KiB | 5.9 / 12.6 KiB |
| jobq's warm build, before and after | 0.06 s, 0.06 s | 5,031,128 → 5,425,072 bytes (+394 KiB) |

A record costs more than twice a plain write on three of four bulk rows (ChaCha20 has no CPU instruction here, and every byte is copied once more than a plain write: the socket's bytes into the engine, the engine's plaintext into the connection's buffer). Round trips are inside the brief's 2×. The suite makes no difference to a handshake; the key does (P-256 signing is a quarter slower). The abuse run: fourteen rows as named under both runtimes, the server serving after each (a plain HTTP request alert 10, TLS 1.2 only alert 70, P-256 shares only alert 40, a hello cut off and a client that never finishes held to the 10 s deadline then closed, a 64 KiB record alert 22, `-groups P-256:X25519` a HelloRetryRequest then an echo).

**What verification found, and the two fixes.** The worker reported `zig build test` green at every commit and the corpus green under both runtimes. Neither was true. Fable's suite run hung for 21 minutes; `gdb` on it showed the brick's test "a KeyUpdate round trip" blocked in a write on its socketpair with the client thread waiting; the test hung on every run (`fable-probe/tls-brick-tests-before-fix.log`). The fix worker named the cause: the test's handshake loop never called `mo_tls_sent` after `mo_tls_flush`, so it wrote the server's first flight again and again; Zig's client read the second copy as a post-handshake record, failed, and stopped reading, and the next write blocked with no bound. Tests only were changed: `writeAllFd` polls thirty seconds before every write and fails with `TestTimedOut`, a `ClientThread` shuts every end and joins on every exit, and the test now fails within 32 s if the call is removed again. The fix worker's two full-suite runs (651 and 655 s) were then 224 of 225: the corpus test of `tls-echo.mo` printed "no certificate", because `main` read `examples/effects/tls/cert.pem` relative to the working directory and the corpus runs a program from its own folder. Fix 2 made the program read `tls/cert.pem` and `tls/key.pem` as the brief said and the bench start the echo from `examples/effects`; the `verified:` line was rewritten with `mo test --write`. Fable's suite run after both fixes, on a quiet machine (load 0.02): 225 of 225 in 10 min 47 s (`fable-probe/zig-build-test.log`).

**Fable's probes** (`fable-probe/probe.py`, openssl s_client and Python's ssl against the example echo, both runtimes, 22 of 22): a non-ASCII line and an empty line echoed; a 60,000-byte line (four records each way) intact; a KeyUpdate from `s_client`'s `K` command then a line echoed; a client offering only `TLS_AES_256_GCM_SHA384` refused with `handshake_failure` and the server serving after; fifty concurrent handshakes all echoed; the certificate served equals `cert.pem` byte for byte; a client trusting the other pair's certificate refuses this server; a socket dropped mid-line with no close_notify leaves the server serving; 200 connections opened and closed grow resident memory by 1.2 MB under `mo run` and 0.6 MB in a binary.

**Decisions the brief did not cover**, nineteen from the worker (`worker-raw/worker-report-pane.txt`) and eleven from the two fixes, read and ratified as rows of 17 Sep in the [[decision-log]] except where a row says otherwise: `flush` peeks and `sent` consumes (the hang was a test that forgot `sent`); one object per brick, each cached by its own hash; the TLS brick's own ten-line entropy function, since two objects cannot share an export; `Tls.fixture()` added for the corpus tests; `Tls.server(cert:, key:)` with PEM text; `TlsServer` a capability kind like `Listener`; the server table beside the sockets, not on a `Vm` (a real bug the example found); a `Conn` records the first row that used it so `accept`'s crash can name it; alerts for the unnamed cases; the server's suite preference AES-128-GCM first; a stream that ends without close_notify is `eof`, as a plain socket's end, the truncation left to the program; the plain echo as the baseline; Python's ssl for the thousand idle connections; `s_time` for handshakes; the retry case; the example ends on `Idle` through a kept reply; the PEM text carried in the example as functions so its tests need no file.

**Carried.** The extra copy per byte in the record path (decrypt into the connection's buffer in place); every binary links both bricks whether or not the program uses them (+394 KiB); a KeyUpdate from the server is checked as queued, never delivered to a client (step 37, with the client); two tests still swallow `TestTimedOut` behind an assertion; ChaCha20's 3 to 4× is `std.crypto`'s on this CPU; the shipped numbers were taken with one core busy.

## Fix, 17 Sep 2026, 7:30 PM ET: the KeyUpdate test hangs

The lead's verification of part C found `zig build test` never finishing: the brick's test "a KeyUpdate round trip" (`toolchain/src/bricks/tls.zig`, line 1638) deadlocks. `gdb` on the hung suite: the main thread in `writeAllFd(fd=6, 762 bytes)` inside the test's handshake loop, blocked in the kernel's `unix_stream_sendmsg`; the client thread (`ClientRun.run`, Zig's `tls.Client` over `testing.io`) and the runner's threads in `futex_wait`. Deterministic on the VM: it hung in the full suite (21 minutes before the lead stopped it) and again in `zig test src/bricks/tls.zig` alone (tests 1 to 10 pass; 11 hangs until `timeout 300`). The worker's own runs passed, so the deadlock is timing-dependent: two blocking sides over a socketpair with nothing that guarantees one of them reads.

**Write scope:** `toolchain/src/bricks/tls.zig`, its tests only; nothing in the brick's behaviour, its exports, the rows, or the runtimes changes.

**Done when:** the cause of the deadlock is named in the commit message (why the client thread stops reading, and why only this test); the test harness is made unable to hang: the main thread's writes and reads are bounded (poll with a deadline before every write as `readSomeFd` already does before reads, or a nonblocking fd with a deadline loop), the client thread is bounded the same way, and a wrong test fails with a named error within 30 seconds instead of hanging; `zig test src/bricks/tls.zig` green five times in a row; `zig build test` green twice in a row; one commit, `Step 36 fix: the KeyUpdate test`, pushed. Say in the report whether the test still exercises a KeyUpdate from the client and one from the server.

## Fix 2, 17 Sep 2026, 9:30 PM ET: the example reads its certificate by the wrong path

The fix worker's two full-suite runs (651 and 655 s) were 224 of 225: the corpus test of `examples/effects/tls-echo.mo` prints "no certificate", because `main` reads `examples/effects/tls/cert.pem` relative to the working directory and the corpus test runs a program from its own folder, `examples/effects`. The brief's part C said `tls/cert.pem` and `tls/key.pem`. The part C worker's claim that the corpus was green under both runtimes was wrong, as was its claim of a green suite at every commit (the KeyUpdate hang was in part A's tree).

**Decision (Fable):** the program reads `tls/cert.pem` and `tls/key.pem`, relative to its own folder as the brief said and as every other corpus example with data does; `toolchain/bench/step36/common.py` runs the echo with `examples/effects` as the working directory (and its P-256 tree copies the pair under `tls/` there), so the bench's runs match the corpus's. The expected output does not change.

**Write scope:** `examples/effects/tls-echo.mo` (the two paths and nothing else), `toolchain/bench/step36/common.py` (the working directory and the copy), `examples/effects/.mo.ids` if the `verified:` line moves. **Done when:** `mo run examples/effects/tls-echo.mo -- 18443 1000` from `examples/effects` prints the `.expected`; `zig build test` green (225 of 225) once under `timeout 1800`; `uv run python abuse.py` in `bench/step36` green under both runtimes after the change; one commit `Step 36 fix 2: the certificate path`, pushed.

## Correction, 18 Sep 2026, 02:50 UTC (17 Sep, 10:50 PM ET), after both readings

Three statements in the Result above are wrong and stand corrected here rather than rewritten (the decision log of 18 Sep has a row for each): the numbers were **not** taken with an orphan on one core (the orphan died 21:26 UTC, the bench ran between 22:00 and 22:40 UTC by the commit times; the evidence README's load 0.38 is the right condition); the abuse run shows the server serving **after the batch**, not after each case (`abuse.py` runs all cases, then all checks); and the tests against Zig's own client cover P-256 and one suite, the matrix running against the brick's own `TestClient`. Also, no export sends a KeyUpdate on the runtime's request; the carried line's "checked as queued" was the reply to the client's request. All four go to step 37. The readings: `audit/fable-reading-2026-09-18-step-36.md` and `audit/mo-audit-2026-09-18-step-36.md`.

## Related

- [[bricks-and-the-cost-of-zero-dependencies]]
- [[interpreter-step-35]]
- [[09-stdlib]]
- [[06-packages]]
- [[roadmap]]

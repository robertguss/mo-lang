# Step 36's numbers

The VM (x86-64, four cores), 17 Sep 2026, best of five, both runtimes, on the tree at
`Step 36 part B`. The client is OpenSSL 3.0.13 in every run. Reproduce with `uv run python
<script>.py` from this folder; `README.md` says what each measures.

## Handshakes a second

`openssl s_time -new`, three seconds a measurement, best of five. Every connection is a full
handshake: the brick has no session tickets and no resumption. The echoes-lost column is a
`s_client` round trip after each measurement, so a run that handshook fast and echoed nothing
would show here.

| runtime | key | suite | handshakes/s | echoes lost |
|---|---|---|---:|---:|
| `mo run` | Ed25519 | AES-128-GCM | 1,026 | 0 |
| `mo run` | Ed25519 | ChaCha20-Poly1305 | 1,046 | 0 |
| `mo run` | P-256 | AES-128-GCM | 765 | 0 |
| `mo run` | P-256 | ChaCha20-Poly1305 | 754 | 0 |
| binary | Ed25519 | AES-128-GCM | 1,196 | 0 |
| binary | Ed25519 | ChaCha20-Poly1305 | 1,172 | 0 |
| binary | P-256 | AES-128-GCM | 804 | 0 |
| binary | P-256 | ChaCha20-Poly1305 | 818 | 0 |

The suite makes no difference, which is right: a handshake moves about two kilobytes, so the AEAD
is nothing next to the X25519 exchange and the signature. The key does: signing with P-256 costs
about a quarter of the rate against Ed25519 (765 against 1,026 under `mo run`, 804 against 1,196
in a binary), which is `std.crypto`'s ECDSA against its Ed25519 and none of it the brick's. The
binary is 15 to 17 % faster than the interpreter on the same work, because the Mo around the
handshake — the acceptor process's update, the `lines` call — is compiled; the handshake itself is
the same object in both.

A loop of `openssl s_client`, one process a connection, gives 38 a second. That is `fork` and
`exec`, not the server, and is why `s_time` is the client here.

## 100 MiB through the echo and back

The same echo with no handshake (`plain-echo.mo`) is the baseline: the same program, the same
runtime, the same `lines` loop, so the difference is the record layer. Lines of 4,096 bytes, the
client writing on one thread and reading on another.

| runtime | over | MB/s | against plain |
|---|---|---:|---:|
| `mo run` | a plain `Conn` | 488.1 | |
| `mo run` | AES-128-GCM | 202.7 | 2.4× |
| `mo run` | ChaCha20-Poly1305 | 121.3 | 4.0× |
| binary | a plain `Conn` | 477.1 | |
| binary | AES-128-GCM | 267.7 | 1.8× |
| binary | ChaCha20-Poly1305 | 155.3 | 3.1× |

**A record costs more than twice a plain write on three of these four rows.** ChaCha20-Poly1305
is 3.1× and 4.0×: this CPU has AES-NI and PCLMULQDQ, so AES-128-GCM runs on instructions and
ChaCha20 runs on the vector unit, and the gap is `std.crypto`'s, not the brick's. AES-128-GCM in a
binary is 1.8×, inside the brief's bound; under `mo run` it is 2.4×, where the extra is the
interpreter's own share of each 4 KiB line, which the records make a larger fraction of. Part of
the cost is not the cipher at all: every byte is copied once more than a plain write is (the
socket's bytes into the engine, the engine's plaintext into the connection's buffer), which a
later step could cut by decrypting into the connection's buffer in place.

## Round trips, as `echo-1k` counts them

1,000 lines written and read back one at a time, microseconds a round trip.

| runtime | over | µs a round trip | against plain |
|---|---|---:|---:|
| `mo run` | a plain `Conn` | 27 | |
| `mo run` | AES-128-GCM | 38 | 1.4× |
| `mo run` | ChaCha20-Poly1305 | 40 | 1.5× |
| binary | a plain `Conn` | 23 | |
| binary | AES-128-GCM | 28 | 1.2× |
| binary | ChaCha20-Poly1305 | 25 | 1.1× |

A round trip is a scheduler turn, two system calls, and a short line, so the record layer is 1 to
15 µs of it: well inside the brief's 2×. A server that answers small messages pays almost nothing
for TLS; one that moves bulk pays the table above.

## Resident memory, 1,000 idle connections

Each connection handshook and then left alone, no bytes either way; the server's resident memory
read from `/proc` before the first and after the last, once it stopped moving.

| runtime | over | before | after 1,000 | per connection |
|---|---|---:|---:|---:|
| `mo run` | a plain `Conn` | 21,492 KiB | 24,384 KiB | 2.9 KiB |
| `mo run` | TLS | 21,784 KiB | 31,356 KiB | 9.6 KiB |
| binary | a plain `Conn` | 15,092 KiB | 20,992 KiB | 5.9 KiB |
| binary | TLS | 15,656 KiB | 28,248 KiB | 12.6 KiB |

**An idle TLS connection costs more than twice an idle plain one under `mo run`** (9.6 KiB against
2.9), and 2.1× in a binary (12.6 against 5.9). The 6.7 KiB of difference is the engine: the `Conn`
struct with its two ciphers and the SHA-256 transcript (about 400 bytes), and the rest the
allocator's rounding on the buffers a handshake grew, which are freed when they empty but whose
pages the allocator keeps. The absolute number is small: a thousand idle TLS connections cost
about 9.4 MiB.

## `mo build` warm, and the binary's size

`examples/programs/jobq`, best of five warm builds, and the binary's size, before (the tree at
`Step 36 part A`, the crypto brick alone) and after (both bricks linked).

| | before | after |
|---|---:|---:|
| `mo build examples/programs/jobq` warm | 0.06 s | 0.06 s | 
| the binary | 5,031,128 bytes | 5,425,072 bytes |

The TLS brick costs 393,944 bytes (+7.8 %) in every binary and nothing warm: the object is cached
by its own source hash, so a warm build only links it. A cold build with neither brick cached
takes 15.5 s on this machine, of which the crypto brick is about 7 s and the TLS brick about 4 s.
Every binary pays the size whether or not the program uses TLS; a later step could leave out a
brick the program's rows never reach.

## The abuse run

`abuse.py`, both runtimes, all fourteen rows as named and the server serving after every one
(a whole handshake and a round trip, not just a socket that accepted).

| case | wanted | got, both runtimes |
|---|---|---|
| a plain HTTP request | alert 10, `unexpected_message` | alert 10 |
| `-tls1_2` | alert 70, `protocol_version` | alert 70 |
| `-groups P-256` | alert 40, `handshake_failure` | alert 40 |
| a hello cut off mid-record | held to the deadline, then closed | closed after 10.0 s |
| a client that never finishes | held to the deadline, then closed | closed after 10.0 s |
| a 64 KiB record | alert 22, `record_overflow` | alert 22 |
| `-groups P-256:X25519` (not abuse) | a HelloRetryRequest, then a handshake | echoed |

The two deadline cases are the `within:` `tls-echo.mo` gives `accept` (10 s): the connection is
held that long and closed with nothing said, so a client that stops mid-hello costs the server one
connection and no CPU, and cannot be made to answer early or to hang.

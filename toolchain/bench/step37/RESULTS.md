# Step 37's numbers

The VM (x86-64, four cores), 18 Sep 2026, on the tree at `Step 37 part B` (9f83dde) with part
C's bench beside it. OpenSSL 3.0.13 is the other end in every OpenSSL run. The raw outputs are
under `work/` (git ignores it), each beginning with the date and `uptime`; the tables below are
copied from them as printed, with the load average each was taken at. `README.md` says how to run
everything.

## The differential run: 1,000 sessions, 0 mismatches

`uv run python diff.py --seed 3737 --sessions 1000`, 18 Sep 2026 04:58 UTC (load 0.58 at the
start), 159 s: **1,000 sessions, seed 3737: 0 mismatches.** Every session's parameters, both
views, and the expected outcome are one line of `work/diff-3737.log`.

The first run with the same seed, a few minutes earlier (`work/diff-3737-first.log`), had 3
mismatches, none in the brick; each is fixed in `diff.py` and the rerun above is the result:

- Session 302: the model checked X25519 before ALPN; the brick's server checks ALPN first
  (`readHello`: versions, suites, signature schemes, ALPN, then the key share), so a client with
  neither X25519 nor a shared protocol gets `no_application_protocol` (120), not
  `handshake_failure`. The brick and OpenSSL agreed (120 sent, 120 read).
- Sessions 182 and 835: a race in the harness. All the data was in the first chunk, the brick's
  server closed first once it had echoed the last byte, and `diff.py` wrote `K` to `s_client`
  after that. No KeyUpdate happened, and both sides agreed (0 and 0). `diff.py` now writes `K`
  before a chunk that carries data, so records flow after it.

Three more model errors were found while `diff.py` was written, on shorter runs (seeds 1 and 2),
all in what OpenSSL does, none in the brick: OpenSSL 3.0's `s_server` sends
`no_application_protocol` when no ALPN protocol is shared (the model had it answer none); an
`s_client` asked for a KeyUpdate answers only before its next application data (RFC 8446 4.6.3),
so one that has written its last byte never answers; and the side that sends the first
close_notify need not stay for the other's.

What the 1,000 sessions covered (from the log):

| | sessions |
|---|---:|
| the brick's server against `s_client` / the brick's client against `s_server` | 484 / 516 |
| handshakes that completed / refused | 597 / 403 |
| AES-128-GCM / ChaCha20-Poly1305 agreed | 495 / 102 |
| an ALPN protocol agreed / none | 127 / 470 |
| `s_client` sharing a key for another group first, X25519 later: a HelloRetryRequest from the brick's server (109 of them went on to handshake) | 176 |
| chains: good / five certificates / six / expired / leaf for example.org / client for example.org / link missing / leaf signed by a non-CA / untrusted root / RSA leaf | 653 / 34 / 41 / 44 / 37 / 37 / 52 / 35 / 42 / 25 |
| refusals by the brick, alert 40 / 42 / 45 / 48 / 120 | 34 / 35 / 11 / 72 / 33 |
| refusals by OpenSSL, alert 40 / 42 / 45 / 48 / 120 | 52 / 32 / 27 / 75 / 32 |
| KeyUpdate from `s_client` / `s_server` (`K`), received and answered by the brick | 50 / 52 |
| KeyUpdate from the brick's server / client, not asking, read by OpenSSL | 55 / 63 |
| KeyUpdate from the brick's server / client, asking: read by OpenSSL, and answered | 56 (35 answered; 21 where `s_client` had nothing left to write) / 63 (63) |

**The KeyUpdates each way, from the log**, one session of each kind (`mo ku` is the brick's sent
and read, `openssl` OpenSSL's, from its `-msg` log; in every one the echo came back whole):

| session | role | KeyUpdate from | bytes | mo ku sent / read | openssl ku sent / read |
|---:|---|---|---:|---|---|
| 1 | brick server, `s_client` | the brick, not asking | 13,912 | 1 / 0 | 0 / 1 |
| 7 | brick server, `s_client` | the brick, asking | 4,098 | 1 / 1 | 1 / 1 |
| 15 | brick server, `s_client` | `s_client` (`K`) | 16,697 | 1 / 1 | 1 / 1 |
| 35 | brick client, `s_server` | the brick, not asking | 16,385 | 1 / 0 | 0 / 1 |
| 0 | brick client, `s_server` | the brick, asking | 6,610 | 1 / 1 | 1 / 1 |
| 23 | brick client, `s_server` | `s_server` (`K`) | 16,383 | 1 / 1 | 1 / 1 |

## The fuzz hour

`uv run python fuzz.py --seed 3701 --minutes 60`, 18 Sep 2026 05:01:54 to 06:01:25 UTC (load 0.76
at the start, 1.51 at the end; the first of the two final suite runs shared the machine from 05:04
to 05:18): **87,440 inputs in 2,186 batches, seed 3701: 0 crashes; 3,601 CPU s (60.0 min), 3,569 s
wall** (`work/fuzz-3701.txt`, `work/fuzz-3701/crashes/` empty).

Before the hour the detector was checked on itself: a planted panic (an input the driver panics
on) exited 134 and was counted as a crash, and a planted hang (a step that never returns) was
stopped by the driver's two-second watchdog, exited 3, and was counted.

Each input is one of the sixteen canonical sessions (each suite, each key type, ALPN or none,
HelloRetryRequest or none) mutated one to four times; each reaches both roles at every state, as
records and, behind the AEAD, as handshake messages. The mutations the hour drew: cut 20,098,
delete 19,897, drop 19,976, dup 19,753, flip 19,926, insert 19,684, kind 19,739, length 19,853,
repeat 19,917, set 19,801, splice 19,806.

## The client's numbers (`measure.py`, best of five, both runtimes)

`work/measure.txt`, 18 Sep 2026 04:51 UTC, load 0.14 at the start. A rate is
`count / (t(count) - t(0))` for `tls-dial.mo` run with 300 handshakes and with none.

The brick's client against `openssl s_server`, the chain of three checked (load 0.33):

| runtime | key | handshakes/s |
|---|---|---:|
| `mo run` | Ed25519 | 1,001 |
| binary | Ed25519 | 1,354 |
| `mo run` | P-256 | 286 |
| binary | P-256 | 295 |

Mo client to Mo server, `tls-dial.mo` to `tls-echo.mo`, each runtime against itself (load 0.55):

| runtime | key | handshakes/s |
|---|---|---:|
| `mo run` | Ed25519 | 942 |
| `mo run` | P-256 | 271 |
| binary | Ed25519 | 1,445 |
| binary | P-256 | 280 |

100 MiB through a Mo-to-Mo connection and back, 4 KiB lines with two windows of 64 in flight,
MB/s = 10^6 bytes a second of what went one way (load 1.44):

| runtime | over | MB/s | against plain |
|---|---|---:|---:|
| `mo run` | plain | 43.7 | |
| `mo run` | TLS | 38.6 | 1.1× |
| binary | plain | 336.9 | |
| binary | TLS | 256.6 | 1.3× |

The chain check's cost: the client's handshakes against `s_server` presenting the chain of three
(leaf, intermediate, the trusted root: two signatures in the chain) and a self-signed leaf the
client trusts itself (one), each key type (load 1.40):

| runtime | key | server presents | handshakes/s | µs a handshake |
|---|---|---|---:|---:|
| binary | Ed25519 | chain of three | 1,382 | 723 |
| `mo run` | Ed25519 | chain of three | 927 | 1,079 |
| binary | Ed25519 | self-signed leaf | 1,239 | 807 |
| `mo run` | Ed25519 | self-signed leaf | 1,036 | 966 |
| binary | P-256 | chain of three | 294 | 3,405 |
| `mo run` | P-256 | chain of three | 285 | 3,507 |
| binary | P-256 | self-signed leaf | 369 | 2,713 |
| `mo run` | P-256 | self-signed leaf | 362 | 2,762 |

`mo build examples/programs/jobq`, warm (best of five) and cold, and the binary's size, with the
`mo` of the commit before step 37 (6f449c9) and this one (load 1.50):

| `mo` | warm | cold (bricks compiled) | binary |
|---|---:|---:|---:|
| before (6f449c9) | 0.10 s | 20.1 s | 5,429,960 bytes |
| after | 0.09 s | 21.8 s | 5,541,240 bytes |

**Where a client handshake costs more than a server one.** With P-256, by more than twice: the
brick's client makes 286 to 295 handshakes a second against `s_server`, where the brick's server
makes 649 to 664 against `s_time` (step 36's script below, the same chain). The client verifies
three ECDSA P-256 signatures (the intermediate's, the leaf's, and the CertificateVerify) where the
server makes one, and `std.crypto`'s P-256 verification is the slow part: the table above puts one
at about 700 µs (3,405 against 2,713 µs a handshake for one signature more). With Ed25519 the
client is not the slower side (1,001 to 1,354 a second against the server's 790 to 856): Ed25519
verification is cheap, and a server's handshake also signs.

**What the chain check costs.** With P-256, about 700 µs a handshake, a fifth of it, for the one
signature the chain of three adds over a self-signed leaf; the name, the dates, and the shape
checks are inside the noise. With Ed25519 the difference is inside the noise of the run (the chain
of three measured faster than the self-signed leaf in a binary, slower under `mo run`).

**The record's cost, Mo to Mo.** 1.1× under `mo run` and 1.3× in a binary: the interpreter's own
cost per line of the client and the server dwarfs the AEAD. The binary's plain Mo-to-Mo rate
(337 MB/s) is below step 36's Python client against the Mo echo (482) because both ends are Mo
here and the client's windows are serial; the table is for the ratio.

**The binary** grows by 111,280 bytes (+2.0 %) with the client, and the warm build does not move:
the brick is cached by its source hash. A cold build pays the TLS brick's compile, about 10 s on
this machine (8.6 s for step 36's brick alone; 14.4 s before the brick stopped calling
`std.crypto.Certificate`'s `Parsed.verify`, whose RSA code the cut refuses).

## Step 36's bench after its fixes

`bench/step36`, the fixed scripts, both runtimes.

`abuse.py` (`work/abuse.txt`, written 03:59 UTC, load 1.32; the part B suite was running): every
case answered as named, and the server serving **right after each case**, before the next began
(`cases` is a generator now):

| runtime | case | wanted | got | as named | serving right after this case |
|---|---|---|---|---|---|
| run | http | alert 10 unexpected_message | alert 10 unexpected_message | yes | yes |
| run | tls1_2 | alert 70 protocol_version | alert 70 protocol_version | yes | yes |
| run | p256only | alert 40 handshake_failure | alert 40 handshake_failure | yes | yes |
| run | truncated | held to the deadline, then closed | closed after 10.0 s | yes | yes |
| run | silent | held to the deadline, then closed | closed after 10.0 s | yes | yes |
| run | oversized | alert 22 record_overflow | alert 22 record_overflow | yes | yes |
| run | 64kib | alert 22 record_overflow | alert 22 record_overflow | yes | yes |
| run | retry | a HelloRetryRequest, then a handshake | echoed | yes | yes |
| binary | http | alert 10 unexpected_message | alert 10 unexpected_message | yes | yes |
| binary | tls1_2 | alert 70 protocol_version | alert 70 protocol_version | yes | yes |
| binary | p256only | alert 40 handshake_failure | alert 40 handshake_failure | yes | yes |
| binary | truncated | held to the deadline, then closed | closed after 10.0 s | yes | yes |
| binary | silent | held to the deadline, then closed | closed after 10.0 s | yes | yes |
| binary | oversized | alert 22 record_overflow | alert 22 record_overflow | yes | yes |
| binary | 64kib | alert 22 record_overflow | alert 22 record_overflow | yes | yes |
| binary | retry | a HelloRetryRequest, then a handshake | echoed | yes | yes |

`oversized` is a header declaring 65,535 bytes with 64 bytes of body (refused on the header);
`64kib` is a whole record of 65,535 bytes, header and body in one write.

`handshake.py --pairs step36` (`work/handshake-step36.txt`, 04:42 UTC, load 1.82): step 36's own
self-signed pairs, taken from git at 6f449c9, so the numbers stand beside step 36's (in
brackets). `s_time`'s exit code is checked and its connection count is a column:

| runtime | key | suite | handshakes/s | connections `s_time` counted | echoes lost |
|---|---|---|---:|---:|---:|
| `mo run` | Ed25519 | AES-128-GCM | 1,113 (1,026) | 4,451 | 0 |
| `mo run` | Ed25519 | ChaCha20-Poly1305 | 1,086 (1,046) | 4,346 | 0 |
| `mo run` | P-256 | AES-128-GCM | 806 (765) | 3,226 | 0 |
| `mo run` | P-256 | ChaCha20-Poly1305 | 798 (754) | 3,193 | 0 |
| binary | Ed25519 | AES-128-GCM | 1,240 (1,196) | 4,960 | 0 |
| binary | Ed25519 | ChaCha20-Poly1305 | 1,238 (1,172) | 4,953 | 0 |
| binary | P-256 | AES-128-GCM | 838 (804) | 3,354 | 0 |
| binary | P-256 | ChaCha20-Poly1305 | 850 (818) | 3,398 | 0 |

The fixes changed nothing: every rate is within 9 % of step 36's, above it. `handshake.py` with
the fixture as it now is (`work/handshake.txt`, 04:39 UTC, load 1.56), the server presenting the
chain (leaf, intermediate) and `s_time` verifying it to `root.pem`:

| runtime | key | suite | handshakes/s | connections `s_time` counted | echoes lost |
|---|---|---|---:|---:|---:|
| `mo run` | Ed25519 | AES-128-GCM | 790 | 3,160 | 0 |
| `mo run` | Ed25519 | ChaCha20-Poly1305 | 796 | 3,184 | 0 |
| `mo run` | P-256 | AES-128-GCM | 649 | 2,595 | 0 |
| `mo run` | P-256 | ChaCha20-Poly1305 | 629 | 2,516 | 0 |
| binary | Ed25519 | AES-128-GCM | 837 | 3,349 | 0 |
| binary | Ed25519 | ChaCha20-Poly1305 | 856 | 3,422 | 0 |
| binary | P-256 | AES-128-GCM | 664 | 2,656 | 0 |
| binary | P-256 | ChaCha20-Poly1305 | 664 | 2,654 | 0 |

The chain costs these rates a fifth to a third: `s_time`, a single-threaded client, verifies two
signatures more, and the flight carries one certificate more.

`bulk.py` (`work/bulk.txt`, 04:36 UTC, load 1.57), MB/s = 10^6 bytes a second of 100 MiB (2^20
bytes each) sent one way, step 36's in brackets:

| runtime | over | MB/s |
|---|---|---:|
| `mo run` | plain | 545.8 (488.1) |
| `mo run` | AES-128-GCM | 202.1 (202.7) |
| `mo run` | ChaCha20-Poly1305 | 125.5 (121.3) |
| binary | plain | 482.1 (477.1) |
| binary | AES-128-GCM | 309.2 (267.7) |
| binary | ChaCha20-Poly1305 | 165.1 (155.3) |

| runtime | over | µs a round trip (1,000 of them) |
|---|---|---:|
| `mo run` | plain | 28 (27) |
| `mo run` | AES-128-GCM | 33 (38) |
| `mo run` | ChaCha20-Poly1305 | 47 (40) |
| binary | plain | 22 (23) |
| binary | AES-128-GCM | 25 (28) |
| binary | ChaCha20-Poly1305 | 21 (25) |

## What the runs found outside the brick

- **OpenSSL 3.0's `s_time -new` exits 1 on a good run**, against OpenSSL's own `s_server` too
  (1,244 connections, no error printed, exit 1). `handshake.py`'s new check takes 0 or 1 with the
  count printed and no error line; anything else stops it.
- **A killed guard orphans its child.** `Server.stop()` SIGKILLed `guard.py`, which cannot forward
  SIGKILL, and a `tls-echo` binary outlived its run by about a minute (waiting in `epoll`, not
  spinning). `stop()` now sends SIGTERM first, which the guard forwards.
- **The runtimes leave Nagle on.** Neither sets `TCP_NODELAY`, so a Mo client that writes a window
  of 4 KiB lines and then reads it back waits out the peer's delayed ACK, about 40 ms a window
  (3,200 lines in windows of 16: 8.98 s; in windows of 256: 0.39 s). `tls-dial.mo` keeps two
  windows in flight instead.
- **A `Conn` does not read while a write on it waits.** A Mo client that writes lines from `main`
  (or from a process) while the runtime's `lines` loop reads the same connection stalls until the
  write's deadline (1,600 lines: 58.5 s), because the read waits for the write (`net.zig`'s
  `writing` flag) and the write waits for the peer, which waits for the read. A program cannot
  stream both ways through one `Conn` at once today.

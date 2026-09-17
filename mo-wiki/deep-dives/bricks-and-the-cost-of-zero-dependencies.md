---
title: "Bricks and the cost of zero dependencies"
created: 2026-09-17
updated: 2026-09-17
type: deep-dive
tags: [security, stdlib, runtime, programs]
sources:
  [
    spec/design-v0/06-packages.md,
    spec/design-v0/09-stdlib.md,
    deep-dives/outside-review-2026-09-14-response.md,
    research/concepts/hermes-daily-2026-09-17.md,
  ]
status: decided
---

# Bricks and the cost of zero dependencies

Written by Fable, 17 Sep 2026, as the first item of the M-3 order and the
prerequisite the ratified capabilities rule names: program 7 cannot begin until
the shelf boundary is written down
([`audit/`](https://github.com/robertguss/mo-lang/blob/main/audit/README.md)).
The outside review of 14 Sep called zero dependencies "the largest unaccounted
cost": recipes cover small pure modules, and TLS, crypto, a database driver,
compression, and HTTP/2 are years of standard library that Go carried with a
team. This page prices that bet, draws the line, and orders the work. Every
number is either measured today or marked as an estimate.

Three terms, in three lines each:

- A **brick** is first-party code a Mo program may use without owning it: the
  standard library rows of chapter 9 and the **platform**, the native code under
  them. It is the only code in a program that is not the program's.
- A **recipe** is a package at spec altitude: signatures, contracts, tests, and
  `never`s, no bodies. The program's agent writes the bodies from bricks, and
  `mo check --recipe` holds them to the recipe. No dependency exists after.
- The **trusted base** is what a program's correctness rests on and cannot
  check: the toolchain, the platform, and the operating system under them. The
  lockfile pins the platform by hash (chapter 6, registry layer 1).

## Where the line is

A thing is a brick when any one of three tests says so; otherwise it is a recipe
or the program's own code.

| test                                                                                                                                                          | why a recipe cannot do it                                                                                               |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| A bug in it is a security or data-loss event (chapter 6's rule): TLS, crypto, the file and socket rows, a database driver's wire protocol                     | a recipe's tests state the program's intent; they cannot state "no timing leak" or "the bytes reached the disk"         |
| It implements a standard defined outside the program that other software must interoperate with: TLS, HTTP, deflate, a database protocol, JSON, RFC 3339 time | the standard is the contract, and a body regenerated against a recipe's tests can pass them and still fail the standard |
| It needs native code to be fast enough or to reach the OS: hashing, ciphers, compression, sockets, `fsync`                                                    | a recipe's body is Mo, and Mo has no FFI                                                                                |

The other direction, said plainly. A protocol that _is_ the program's product is
the program's code: program 7's RESP parser is the program, as `jobq`'s JSON
routes were. Anything that is pure computation over bricks with a contract a
test can state is a recipe: a rate limiter, a durable map, a retry policy, a
cache, a job queue's shape, and the Prometheus text exposition format, which is
lines of text with a grammar three tests pin down. Program 7's metrics endpoint
is therefore a recipe, and that is the P4 comparison the capabilities rule
wants: in Elixir it is a hex package (`telemetry_metrics_prometheus`), in Mo a
recipe whose body the maintainer regenerates.

```ruby
recipe Metrics.Exposition
  intent "Prometheus text format 0.0.4; one line per sample; never blocks"
  fn render(samples: List(Sample)) : String
    ensures result.ends_with?("\n")
  end
  test "a counter renders with its HELP and TYPE lines" ... end
  test rejects "a label name that is not [a-zA-Z_][a-zA-Z0-9_]*" ... end
end
```

A brick shows up on the Mo side as rows in chapter 9 on a capability, never as a
new syntax:

```ruby
fn main(platform: Platform) : none
  tls = platform.tls.server(cert: "cert.pem", key: "key.pem")  # a Tls
  listener = try platform.net.listen(6379, within: 1.s)
  Acceptor.start(listener, tls)
end
```

## The shelf today, and what program 7 adds

| brick                                                             | today                                                           | program 7 needs                                                            |
| ----------------------------------------------------------------- | --------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Files, sockets, HTTP/1.1, JSON, time, output, the runtime surface | in chapter 9, both runtimes, under five programs and ten rounds | as they are                                                                |
| Crypto: SHA-256, HMAC, a CSPRNG                                   | none                                                            | SHA-256 for ACL passwords (Redis 6 hashes them so), random for nothing yet |
| TLS 1.3 server and client                                         | none                                                            | a TLS listener, since Redis's suite runs with `--tls`                      |
| Compression, a database driver, HTTP/2                            | none                                                            | nothing                                                                    |

So program 7 demands two bricks, crypto and TLS, and the second is the large
one. Chapter 9's standing rule holds: a brick is written when a program's spec
demands it and not before; the review's list of five is a shelf, not a queue.

## What a brick costs, measured where it can be

The toolchain is Zig, so Zig's standard library is already inside the trusted
base: the compiler that builds `mo` is the same code. Counted on this Mac (Zig
0.16.0, `lib/zig/std`, 17 Sep 2026):

| Zig `std` tree | lines  | what it holds                                                                                                                                                                                |
| -------------- | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `crypto/`      | 59,059 | SHA-2 and SHA-3, HMAC, HKDF, AES-GCM, ChaCha20-Poly1305, X25519, Ed25519, ECDSA, Argon2, scrypt, bcrypt, ML-KEM, a certificate parser, and a **TLS 1.3 client** (2,428 lines); no TLS server |
| `compress/`    | 7,780  | deflate and gzip (4,106), zstd (1,961), xz and lzma                                                                                                                                          |
| `http/`        | 3,262  | an HTTP/1.1 client and server, no HTTP/2                                                                                                                                                     |
| `json/`        | 3,844  | already shadowed by Mo's own `json.zig`, 512 lines                                                                                                                                           |

None of that is audited by this project; it is audited by Zig's, which is a
different claim, and the audit items below say what we still owe on code we did
not write. What is absent and must be written: a TLS 1.3 server (the record
layer and the client's handshake code are reusable; the server side of the
handshake and the certificate chain are new), a Postgres wire protocol with
SCRAM-SHA-256, HTTP/2's framing and HPACK, and the Mo-facing rows of each.

**Estimates, marked as such.** A TLS 1.3 server on Zig's client: 2,500 to 3,500
lines. Postgres v3 with SCRAM, simple and extended query, no `COPY`: 3,000 to
4,000. HTTP/2 with HPACK, no push: 3,000 to 4,000. The crypto brick is mostly
rows over `std.crypto`: under 1,000. Compression the same: under 1,000. With the
glue for two runtimes, the five bricks the review named are on the order of
12,000 to 15,000 lines to write and roughly 70,000 of Zig's to read, against the
10,836-line C runtime and 39,689 lines of Zig the toolchain holds today. That is
the unpriced number the review asked for: the shelf about doubles the platform,
and the reading is larger than the writing.

**The cost that is ours alone.** `Net` and `Http` exist twice: `net.zig` and
`http.zig` under `mo run`, and again inside `mo_rt.c` for the binary (163 lines
mention HTTP there). A brick written twice is audited twice. Decision below:
from the crypto brick on, a brick is written once, in Zig, compiled to a static
library that `mo build` links beside the C runtime (`zig cc` already builds the
binary, so no new tool), and the interpreter calls the same code. The two
existing bricks stay as they are until a bug or a step touches them.

## The audit budget, per brick

"Audited once" was a phrase in chapter 6. It is now five items, and a brick is
on the shelf only when all five are on its page in chapter 9:

1. **The rows.** Every function as a chapter 9 row: receiver, name, parameters,
   result, and what it does, with the deadline it takes and the capability it
   needs. A brick with no row is not on the shelf.
2. **The standard's vectors.** The test vectors the standard publishes (NIST for
   the hashes and ciphers, the RFC 8448 traces for TLS 1.3, the zlib and zstd
   corpora, Postgres's own protocol tests) run green under both runtimes, and
   are in the corpus.
3. **A differential run.** The brick against the reference implementation on
   generated inputs: OpenSSL for TLS and crypto, zlib and `zstd` for
   compression, `libpq` for Postgres, `curl --http2` for HTTP/2. A thousand
   inputs, one script under `toolchain/bench/`, the mismatch count on the page.
4. **A fuzz budget.** One CPU-hour of fuzzing on the parser side of the brick
   (records, frames, messages) with a crash count of zero. Recorded, dated,
   rerun when the brick changes.
5. **A reading.** Someone who did not write the brick reads its native code
   against the surface cap below and files what they found. Today that is an
   outside session or the auditor; the charter says the best version is a paid
   human. A brick whose reading is missing is on the shelf marked `unread`, and
   `mo add` prints the mark. Zig's own code carries this item too: we read what
   we link.

The surface is capped so the reading is possible. A brick implements the
smallest cut of its standard that a program in the menu needs, and widening the
cut is a decision row:

| brick       | the cut                                                                                                                                                                          |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| TLS         | 1.3 only; `TLS_AES_128_GCM_SHA256` and `TLS_CHACHA20_POLY1305_SHA256`; X25519; Ed25519 and ECDSA P-256 certificates; ALPN; no 1.2, no renegotiation, no session tickets at first |
| Crypto      | SHA-256 and SHA-512, HMAC, HKDF, AES-GCM, ChaCha20-Poly1305, X25519, Ed25519, Argon2id for passwords, a CSPRNG from the OS; nothing else until a program asks                    |
| Compression | deflate and gzip, zstd; no xz, no brotli                                                                                                                                         |
| Database    | Postgres v3 with SCRAM-SHA-256, simple and extended query, no `COPY`, no replication                                                                                             |
| HTTP/2      | framing and HPACK for a server behind the TLS brick; no push, no prioritization                                                                                                  |

**What the shipped numbers will look like (added 17 Sep, evening, after step 35 and the speed probe).** The rates a brick reports are the brick's own; a Mo program reaches them through `List(UInt8)` and with contracts on, and both cost. Step 35 measured the first: a 1 MiB SHA-256 at 1,548 MB/s from Zig is 532 MB/s from a Mo binary and 245 under `mo run`, 2.9× and 6.3× (a `Value` per byte). The speed probe of the same evening measured the second on the job queue: one postcondition that walks the state on every request took generation four's lease path from 1,793 to 533 pairs a second, and the closure that walked it paid a structural walk over its captured record per element (`mo_disown_in`, 23 percent of the server). The two ratios compound in one direction. Program 7 will be measured as shipped, contracts on and payloads as `List(UInt8)`, so its numbers against Redis will sit below this page's raw rates by both factors until a byte-string value and a cheaper closure capture land; the auditor's speed row reads the shipped number, and this paragraph is the page's warning that it will. The audit files: `audit/fable-reading-2026-09-17-step-35-crypto-brick.md`, `-gen4-speed-probe.md`, and the auditor's two of the same date.

## The ordering rule

Among the bricks a program demands, dependency order first, then the worst bug
first: crypto before TLS (the handshake needs the hashes and curves), TLS before
HTTP/2 (ALPN), crypto before Postgres (SCRAM), compression on its own. Within
one brick, the rows the program's spec calls come first and the rest of the cut
waits. For program 7: the crypto brick is one worker step, the TLS brick two
(the server handshake, then the certificate chain and the differential run),
both before program 7's first commit so that the auditor's suites can name their
rows.

## The fallback

When a brick cannot be written under its cap and budget in the platform's own
code, the fallback is a brick that **wraps a C library inside the platform**:
the library's source vendored into the toolchain repository at a pinned hash,
compiled by `zig cc` with the runtime, reachable only through the brick's
chapter 9 rows on a capability, and covered by the same five items, where the
reading becomes the library's own audit record, its version, and its CVE
history. The likely cases are an embedded database engine (SQLite, if a program
ever wants one) and TLS 1.2 for a client that cannot speak 1.3. Nothing is
fetched at build; the lockfile's platform hash covers the vendored source. The
same rule the platform has always had holds: **never application FFI.** A Mo
program cannot call C, so the platform is the whole native surface and the
capability model is the whole permission system. A library wrapped this way is
still code nobody here read, and the shelf says so with the `unread` mark until
item 5 is done.

## The bricks' own dependencies, and how they update

A brick depends on three things and nothing else: the OS interface (musl,
statically linked, on Linux; `libSystem` on macOS, which Apple does not ship
static), Zig's standard library at the toolchain's pinned version, and any
vendored C at its pinned hash. A program's dependency count therefore stays at
zero with one trusted base, the toolchain, which is Go's position too. A fix to
a brick ships as a toolchain release; a program takes it by rebuilding; a change
to a brick's rows is a breaking change handled as a capability widening is, by a
human. `mo build` is to record the toolchain version and the platform hash in
the binary's `--version` line (a row; not built yet), so an operator can answer
"which TLS is this" without a lockfile in hand.

## What the capabilities rule reads from this page

- **P1's boundary:** bricks are the rows in chapter 9 with their five audit
  items on the page; recipes are `examples/recipes/` and the registry's; a brick
  marked `unread` still counts as first-party for P1 but is a finding the
  reading names.
- **P4's target:** the Prometheus exposition format is a recipe in Mo and a hex
  package in Elixir; the change-6-style modification the auditor names can press
  on it.
- **The cost, stated:** 12,000 to 15,000 lines to write and about 70,000 to read
  for the review's five bricks, of which program 7 needs two; the shelf doubles
  the platform.
- **The honest sentence:** zero third-party dependencies means one trusted base
  with an audit record per brick, not no code from outside. Where the record is
  missing the shelf says `unread`, and the capabilities reading will count those
  marks.

## Decisions (rows in the decision log, 17 Sep 2026)

1. The shelf boundary is the three tests above; the metrics format is a recipe;
   RESP is program 7's own code.
2. A brick ships only with its five audit items on its chapter 9 page; the
   surface caps in the table are the cut, widened by a row.
3. From the crypto brick on, a brick is written once in Zig and linked into both
   runtimes; `Net` and `Http` stay as they are.
4. The fallback is a vendored C library inside the platform under the same five
   items; never application FFI.
5. Program 7's brick steps: crypto (one step), then TLS (two), before its first
   commit.

## Related

- [[06-packages]], chapter 6: bricks, kits, recipes, the registry
- [[09-stdlib]], chapter 9: the rows a brick becomes
- [[outside-review-2026-09-14-response]], item 3: the cost this page prices
- [[hermes-daily-2026-09-17]]: a capability API is not confinement, which is why
  item 5 exists
- [[effects-and-capabilities]]
- [[program-menu]], program 7
- [[roadmap]]
- [[the-thesis-and-its-evidence]], layer 2

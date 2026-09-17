---
title: "Step 35: the crypto brick, written once for both runtimes"
created: 2026-09-17
updated: 2026-09-17
type: plan
tags: [stdlib, security, runtime, programs]
sources:
  [
    deep-dives/bricks-and-the-cost-of-zero-dependencies.md,
    spec/design-v0/09-stdlib.md,
    spec/design-v0/06-packages.md,
    spec/design-v0/07-toolchain.md,
  ]
status: done
---

# Step 35: the crypto brick, written once for both runtimes

The first brick under the bricks page
([[bricks-and-the-cost-of-zero-dependencies]]), and the first thing program 7
needs (SHA-256 for Redis's ACL passwords; the TLS brick of step 36 needs the
rest). Two things are new at once: the rows, and the rule that a brick is
written once, in Zig over `std.crypto`, and used by both runtimes, so it is
audited once. The C runtime gets no crypto of its own.

## Orientation

`toolchain/src/prelude.zig` (the stdlib's types and rows, `Platform`'s
capabilities: `http` at line 423 is the pattern), `caps.zig` (what a capability
may reach), `check.zig` (row typing), `bytecode.zig` and `vm.zig` (the
interpreter's row bodies), `emit_c.zig` (the binary's), `cbuild.zig` (how
`mo build` runs `zig cc` on the emitted C and the embedded `mo_rt.c`; the brick
joins that link), `sim.zig` (the seed, for `Random.fixture`),
`spec/design-v0/09-stdlib.md` (`## Rules for every row`; `## Files` for the
shape of a capability's rows), `examples/effects/` (capability examples with
`.expected`), the bricks page's cut for crypto. Zig 0.16's `std.crypto` (on the VM through `mise`; `zig env` gives `std_dir`): `sha2.zig`, `hmac.zig`, `hkdf.zig`, `aes_gcm.zig`, `chacha20.zig`,
`25519/`, `argon2.zig`, `phc_encoding.zig`, `timing_safe.zig`,
`std.crypto.random`.

## Write scope

`toolchain/`, `examples/effects/crypto*.mo` and `examples/basics/hash*.mo` with
their `.expected`, `examples/README.md`'s list, and these spec lines only: a
`## Crypto` section and a `## Random` section in `09-stdlib.md` in the table
form the file uses, one line in `07-toolchain.md`'s build order if the link step
changes it, and the runtime paragraph of `toolchain/README.md`. Nothing else
under `mo-wiki/`.

## Parts

A. **The brick.** One file, `toolchain/src/bricks/crypto.zig`, with C-ABI
exports (`export fn mo_crypto_sha256(...)` and so on) over `std.crypto`, nothing
hand-rolled: SHA-256, SHA-512, HMAC-SHA256, HKDF-SHA256, AES-256-GCM seal and
open, ChaCha20-Poly1305 seal and open, X25519 (a public key from a secret, a
shared secret), Ed25519 (a public key from a seed, sign, verify), Argon2id (hash
to a PHC string with given salt and the parameters `m=65536,t=3,p=1`; verify a
PHC string), constant-time equality, and bytes from the OS CSPRNG. Its unit
tests are the standards' vectors, in the file, run by `zig build test`: FIPS
180-4 for SHA-2, RFC 4231 for HMAC, RFC 5869 for HKDF, RFC 7748 for X25519, RFC
8032 for Ed25519, RFC 8439 for ChaCha20-Poly1305, the NIST GCM vectors, RFC
9106's Argon2id vector. A wrong key or nonce size is a crash at the row (rule 3
of chapter 9: the caller broke a rule); a failed `open` or `verify` is a value.

B. **The rows, both runtimes.** Pure rows on types, since hashing, sealing, and
signing are deterministic (chapter 9's first rule), and one capability,
`Random`, for the only thing that is not:

```ruby
Hash.sha256(bytes: List(UInt8)) : List(UInt8)          # 32 bytes
Hash.sha512(bytes: List(UInt8)) : List(UInt8)          # 64
Hash.hmac_sha256(key: List(UInt8), bytes: List(UInt8)) : List(UInt8)
Hash.hkdf_sha256(ikm: List(UInt8), salt: List(UInt8), info: List(UInt8), size: UInt64) : List(UInt8)
Hash.hex(bytes: List(UInt8)) : String                  # lowercase
Hash.from_hex(text: String) : Option(List(UInt8))
Hash.equal?(a: List(UInt8), b: List(UInt8)) : Bool     # constant time
AesGcm.seal(key: List(UInt8), nonce: List(UInt8), plain: List(UInt8), aad: List(UInt8)) : List(UInt8)   # ciphertext then the 16-byte tag
AesGcm.open(key, nonce, sealed, aad) : Option(List(UInt8))
ChaCha.seal(...), ChaCha.open(...)                     # the same shape, ChaCha20-Poly1305
X25519.public(secret: List(UInt8)) : List(UInt8)
X25519.shared(secret: List(UInt8), public: List(UInt8)) : Option(List(UInt8))   # None on a low-order point
Ed25519.public(seed: List(UInt8)) : List(UInt8)
Ed25519.sign(seed: List(UInt8), bytes: List(UInt8)) : List(UInt8)               # 64 bytes
Ed25519.verify?(public: List(UInt8), bytes: List(UInt8), signature: List(UInt8)) : Bool
Password.hash(password: String, salt: List(UInt8)) : String                     # Argon2id, a PHC string; salt 16 bytes
Password.verify?(password: String, phc: String) : Bool                          # a malformed PHC string is false
random.bytes(size: UInt64) : List(UInt8)               # Random, from platform.random
Random.fixture() : Random                              # tests only; bytes from the simulator's seed, so a test replays
```

Key sizes: AES-GCM 32, ChaCha 32, nonces 12, X25519 32 and 32, Ed25519 seeds 32
and public keys 32, signatures 64; anything else is a crash whose message names
the row and the size it got. `Random` is a capability like `Fs`:
`platform.random`, passed as a parameter, never captured in an anonymous
function, and a process holds it only if started with it. Under `mo run` it is
the OS CSPRNG; under `mo test --sim` and in a test binary `Random.fixture()` is
a deterministic stream from the run's seed, so a test that draws a key replays.

Both runtimes call the same exports: the interpreter imports `bricks/crypto.zig`
directly; `mo build` compiles the brick for the target (`zig build-obj` or
`zig build-lib` on the embedded source, `-OReleaseFast`, `-target` as the C is)
and links the object beside `mo_rt.c`, caching the object under
`zig-out/mo-build/.bricks/` by the source's hash and the target so a warm build
does not rebuild it. `mo_rt.c` declares the exports in `mo_rt.h` and calls them;
it implements none of them. A binary built for `--target` Linux from the Mac
still links (the brick has no libc needs beyond what `std.crypto.random` uses;
if a target needs `getrandom` say so).

C. **The audit items on the page.** The rows in `09-stdlib.md` as chapter 9
writes them, with each row's crash rule. The vectors from part A also in the
corpus as Mo: `examples/basics/hash-vectors.mo` (SHA-2, HMAC, HKDF, hex),
`examples/basics/aead-vectors.mo`, `examples/basics/sign-vectors.mo`,
`examples/effects/password.mo` (a hash with a fixed salt, verify true and false,
a malformed string), `examples/effects/random-fixture.mo` (two runs of a test
draw the same bytes), each with `.expected` and green under `mo run` and as a
binary. The differential run: `toolchain/bench/step35/diff.py`, a `uv` project
with `cryptography` as its only dependency (dev-time tooling, allowed by the
bricks page), 1,000 random inputs per primitive at random lengths from 0 to
4,096 bytes, driven through a small Mo program under both runtimes, reporting
the mismatch count per primitive (done when every count is 0). The fuzz harness:
`toolchain/bench/step35/fuzz.py`, mutating PHC strings and hex text into
`Password.verify?` and `Hash.from_hex` for ten minutes at a fixed seed under a
binary, crash count on the page (the lead runs the hour).

## Numbers

Best of five, both runtimes, on the VM (Robert, 17 Sep: this step runs on the VM, not the Mac): SHA-256 of 1 MiB (MB/s); HMAC-SHA256 of
64 bytes, 100,000 times; AES-256-GCM seal of 64 KiB (MB/s); Ed25519 sign and
verify, 10,000 each; `Password.hash` once (ms); `mo build` warm on
`examples/programs/jobq` before and after (s) and the binary's size before and
after (bytes); the `List(UInt8)` overhead on the 1 MiB hash against the brick's
own Zig test of the same bytes. Say where `List(UInt8)` costs more than 2× the
raw call; that is a row for a later step, not this one.

## Done when

`zig build test` green with the vectors in it, the corpus green under both
runtimes, `mo fmt` clean, the differential run at 0 mismatches for every
primitive, the ten-minute fuzz at 0 crashes, the spec lines and the README
paragraph written, the numbers table, and a numbered list "Decisions the brief
did not cover". One commit per part, subject `Step 35 part X`, pushed after
each.

## Result (17 Sep 2026, 18:16 UTC; one Opus session on the VM, 15:50 to 17:56; accepted by Fable)

Three commits, `Step 35 part A` (`ead3f81`), `B` (`18c6457`), `C` (`9092565`), `zig build test` green at each, verified by the worker in a clean worktree per commit. The brick is `toolchain/src/bricks/crypto.zig`, C-ABI exports over `std.crypto`, its unit tests the standards' vectors (FIPS 180-4, RFC 4231, 5869, 7748, 8032, 8439, 9106, NIST GCM 13, 14, 16). The rows are on seven new prelude names that hold no values (`Hash`, `AesGcm`, `ChaCha`, `X25519`, `Ed25519`, `Password`, and the capability `Random`), the interpreter imports the file and `mo build` compiles it once per source, target, CPU, and zig into `zig-out/mo-build/.bricks/<hash>/crypto.o` (about 7 s cold, nothing warm). Five corpus files with `.expected`, the two spec sections, the README paragraph, PRELUDE.md, and `bench/step35` (a `uv` project with `cryptography` as its only dependency: `diff.py`, `fuzz.py`, `measure.py`, `driver.mo`, `bench.mo`, `raw.zig`, RESULTS.md).

**Numbers** (best of five, the VM's four cores, `bench/step35/RESULTS.md`):

| measure | `mo run` | binary |
|---|---:|---:|
| SHA-256 of 1 MiB | 245.1 MB/s | 531.9 MB/s |
| HMAC-SHA256 of 64 bytes, 100,000 times | 68 ms | 35 ms |
| AES-256-GCM seal of 64 KiB | 328.9 MB/s | 595.2 MB/s |
| Ed25519 sign, 10,000 | 1,727 ms | 1,059 ms |
| Ed25519 verify, 10,000 | 1,125 ms | 704 ms |
| `Password.hash` once | 171 ms | 145 ms |
| the brick's SHA-256 of 1 MiB called straight from Zig | 1,548 MB/s | |
| `mo build examples/programs/jobq` warm, before and after | 0.08 s, 0.08 s | 4,622,832 and 5,028,800 bytes (+406 KiB) |

`List(UInt8)` costs more than the brief's 2× on the 1 MiB hash under both runtimes: 6.3× under `mo run` (a 32-byte `Value` per byte in and out) and 2.9× in a binary (a `MoValue` per byte, copied to a buffer and back). A byte-string value is a row for a later step. The first binary numbers (33 MB/s AES-GCM, 203 MB/s SHA-256) came from a brick compiled for baseline x86-64 without AES-NI and SHA-NI; a build with no `--target` now compiles the brick with `-mcpu native`, a `--target` build keeps the triple's baseline and stays portable.

**Audit items.** The differential run (`diff.py --n 1000 --seed 35`): 18 rows, 1,000 inputs each, 0 mismatches under both runtimes (the Argon2id rows 130 to 183 s each, the rest under a second). The worker's fuzz (`fuzz.py --minutes 10 --seed 35`, a binary): 659,600 inputs, 0 crashes. The lead's hour (`--minutes 60 --seed 1701`, 18:13 to 19:13 utc, pane `w7:pk`): 3,855,200 inputs in 9,638 batches, 2,037 verified true, 0 crashes.

**Fable's verification (17:58 to 18:16 UTC).** `zig build && zig build test` on `main` at part C: green in 5 min 48 s. Its own probe (`scratchpad/probe/gen.py`, seed 11: python's `cryptography` generating a 32-byte key, a 12-byte nonce, up to 100 bytes of aad, a plaintext of up to 70,000 bytes, 150,000 bytes for the hash, an Ed25519 seed and message, two X25519 secrets, and an 8,160-byte HKDF, emitted as a 326 KB Mo program) printed 29 lines, checked outside: SHA-256, SHA-512, HMAC, HKDF at its 8,160 ceiling, AES-GCM and ChaCha sealed bytes, the Ed25519 public key and signature, the X25519 public key and shared secret all equal to python's under `mo run` and as a binary, and the two runtimes' outputs identical byte for byte; a flipped last tag byte, a sealed text cut to 15 bytes, and a changed aad open to `None`; an empty plaintext seals to 16 bytes; a 150,000-byte ChaCha round trip returns its input; a wrong message and a 32-byte non-point key verify false without a crash; the all-zero X25519 point is `None`; `from_hex` takes upper case, refuses an odd length and a non-digit, and reads `""` as `[]`; `Hash.equal?` is false across sizes; `Password.hash` of a non-ASCII password verifies true and a prefix of it false, and its tag was rederived independently by python's `Argon2id` from the PHC string's salt (equal). A 3-byte key to `AesGcm.seal` crashes with `AesGcm.seal takes a key of 32 bytes, not 3` and exit 70 under both runtimes. An anonymous function that captures `platform.random` is MO0409 at check time. `random-fixture.mo` under `mo test --sim 200 --seed 9`: 3 passed, the process test held under 5% faults. `mo fmt --check` clean on the seven new Mo files. Peak resident memory of the probe: 105 MB under `mo run`, 78 MB as a binary. Two of Fable's own mistakes cost three reruns (a 1 MiB constant made a 2 MB source past the reader's 1 MiB limit; there is no `^` or `++` in Mo); neither is a defect.

**Decisions the brief did not cover**, fourteen from the worker, read and ratified as rows of 17 Sep in the [[decision-log]]: the rows-only type kind and the seven hideable names; `Password.verify?` taking only the exact string `Password.hash` writes, so a stored string cannot cost more than one hash (it also closed a trailing-`$` acceptance in `std`'s PHC parser); Argon2 parameters the brick's, not the caller's; entropy from `getrandom(2)` on Linux and `arc4random_buf` on macOS, no other target compiling, since Zig 0.16 moved `std.crypto.random` behind `Io`; the fixture as ChaCha20 keyed by SHA-256 of the run's seed, the same bytes under `mo test` and in a test binary; `-mcpu native` without `--target`; HKDF past 8,160 bytes and `Random.bytes` past 1 GiB crash; the brick's answers a small enum, sizes checked before the call; the object cached by content and renamed into place; the `.mo.ids` sidecars and PRELUDE.md updated outside the brief's write scope (right, and the scope rule is amended); two extra bench tools; the fixture stream outside the differential run; a clean worktree per part.

**Carried.** A byte-string value for `List(UInt8)`'s 6.3× and 2.9×; a `Random` for tests that is not the fixture (none asked); a target other than Linux and macOS (none asked).

## Related

- [[bricks-and-the-cost-of-zero-dependencies]]
- [[09-stdlib]]
- [[06-packages]]
- [[roadmap]]
- [[interpreter-step-34]]

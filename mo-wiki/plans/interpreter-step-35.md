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
status: in-progress
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

## Related

- [[bricks-and-the-cost-of-zero-dependencies]]
- [[09-stdlib]]
- [[06-packages]]
- [[roadmap]]
- [[interpreter-step-34]]

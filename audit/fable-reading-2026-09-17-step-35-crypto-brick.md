---
subject: step 35, the crypto brick
author: Fable (the lead)
date: 2026-09-17, 20:30 UTC
filed_against: 69860b0
read_before_auditor: yes, with one caveat. Fable had not opened `audit/mo-audit-2026-09-17-step-35-crypto-brick.md` when this was written. Robert's message announcing the auditor's file relayed its verdict in three lines ("fit to ship"; the `List(UInt8)` ratio as a bricks-page note). That relay was read; the file was not.
evidence: audit/evidence/2026-09-17/README.md, item 2; mo-wiki/plans/interpreter-step-35.md (the brief as sealed at 3a13fca, the Result after); toolchain/bench/step35/RESULTS.md
---

# Fable's reading: step 35, the crypto brick

## What was claimed and what the evidence shows

The brief asked for one Zig file over `std.crypto` with C-ABI exports, used by
both runtimes, with the standards' vectors as its tests, rows on named types
and one capability, five corpus files, a differential run against a reference
implementation at 0 mismatches, a ten-minute fuzz at 0 crashes, and a numbers
table. Every item is in the evidence:

- `toolchain/src/bricks/crypto.zig` (520 lines) holds the exports and the
  vectors (FIPS 180-4, RFC 4231, 5869, 7748, 8032, 8439, 9106, NIST GCM 13, 14,
  16); `zig build test` was green at each of the three commits (the worker, in
  a clean worktree per commit) and on `main` at part C (Fable, 5 min 48 s,
  `zig-build-test.log`).
- The rows call the same exports from `crypto_rows.zig` (the interpreter) and
  `mo_rt.c` (the binary), which implement none of them. This is the property
  the bricks page asked for and the one that matters for the audit: one
  implementation, audited once.
- The differential run: 18 rows, 1,000 inputs each, both runtimes, 0
  mismatches (RESULTS.md). Fable's own inputs (seed 11, a second generator,
  different lengths and a non-ASCII password): 29 lines equal to python's
  `cryptography` under both runtimes, the two runtimes byte-identical, the
  Argon2id tag rederived from the PHC string's salt (`run.log`).
- Fuzz: the worker's ten minutes (659,600 inputs) and Fable's hour (3,855,200
  inputs, seed 1701) at 0 crashes, against `Password.verify?` and
  `Hash.from_hex` in a binary.
- The rejections that must be values are values (a flipped tag, a short sealed
  text, a wrong aad, a wrong message, a non-point key, the low-order X25519
  point, malformed PHC and hex), and the sizes that must be crashes are crashes
  with the row's name and the size (`AesGcm.seal takes a key of 32 bytes, not
  3`, exit 70, both runtimes). MO0409 fires on a captured `Random`.

Reading: **fit to ship, as the first brick under the bricks page.** The five
audit items the page defines are present: rows in chapter 9 with crash rules,
the vectors in the tests and the corpus, a differential run, a fuzz harness,
and a cap (nothing beyond the cut).

## The numbers, and the one that is a finding

SHA-256 of 1 MiB: 245 MB/s under `mo run`, 532 in a binary, 1,548 for the same
brick called from Zig. AES-256-GCM: 329 and 595 MB/s. Ed25519 sign, 10,000:
1.7 and 1.1 s. `Password.hash`: 171 and 145 ms. jobq's warm build unchanged at
0.08 s; its binary 406 KiB larger.

The finding is the ratio, not the rate: **`List(UInt8)` costs 6.3× the raw
call under `mo run` and 2.9× in a binary** on the 1 MiB hash, because every
byte is a `Value` (32 bytes) in the interpreter and a `MoValue` in the binary,
copied to a buffer and back. The brief predicted this ("say where
`List(UInt8)` costs more than 2×") and made it a row for a later step, not a
step-35 defect. Fable's reading agrees with that split and adds where the row
belongs: the bricks page's cost table should carry the ratio beside the raw
number, because program 7 will be measured through `List(UInt8)` with
contracts on, and the page's raw numbers would otherwise read as the shipped
ones. Fable will add that note to the bricks page (its own page) as a dated
edit after this reading is filed, and the TLS brick's brief (step 36) already
asks for the record path's cost through `List(UInt8)` before any byte-string
step is scheduled.

## What this reading did not verify, said plainly

1. **macOS.** The brick's entropy on macOS is `arc4random_buf`; every run here
   was Linux. Untested until a Mac session builds and runs the corpus.
2. **Cross-compilation.** A `--target` build keeps the baseline CPU (the row of
   17 Sep); no cross build was run. Untested.
3. **Constant time.** `Hash.equal?` is constant-time by construction
   (`std.crypto.timing_safe`); nothing measured it. The claim rests on Zig's
   implementation, which the bricks page says is a different claim from this
   project's.
4. **The fixture stream across runtimes.** `Random.fixture()` giving the same
   bytes under `mo test` and in a test binary is tested by the corpus file
   `random-fixture.mo` (both runtimes, in `zig build test`), not by Fable's
   probe.
5. **Argon2id under both runtimes shares one implementation**, so the
   differential run's Argon2 rows compare Zig's `std` against python's; that is
   the intended comparison, but a bug in a row's parameter plumbing common to
   both runtimes would be caught, a bug in `std` would not.
6. **`-mcpu native`.** A binary built on the VM without `--target` may not run
   on an older CPU of the same triple. Decided and recorded; not tested on a
   second machine.

## Two worker defaults that deserve the auditor's eye

- `Password.verify?` accepts only the exact string `Password.hash` writes (one
  algorithm, one parameter set, one spelling), everything else `false`. Fable
  ratified it: a stored string can never cost more than one hash. The cost is
  that a PHC string written by another Argon2id implementation with the same
  parameters but a different spelling verifies false. Program 7's ACL file is
  Mo's own, so this does not bite there; it would bite a migration.
- Entropy: Zig 0.16 moved `std.crypto.random` behind `Io`, so the brick calls
  `getrandom(2)` and `arc4random_buf` itself; no other target compiles. This is
  the first place the brick is not "over `std.crypto`", and the first place a
  third target would need code.

## Where this leaves the claims under audit

Nothing here tests the runtime claim or the capabilities claim; the brick is a
prerequisite the capabilities rule named (a Redis subset with TLS and hashed
passwords at zero third-party runtime dependencies is impossible without it).
What the step establishes for that rule: the dependency stays at zero (the
brick is toolchain code, `cryptography` is dev-time tooling in a venv, never
linked), and the audit items are cheap enough to run per brick (the
differential run is 26 minutes, most of it Argon2; the fuzz is a flag).

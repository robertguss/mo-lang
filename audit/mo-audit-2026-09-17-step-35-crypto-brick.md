# Audit reading: step 35, the crypto brick

**Date:** 17 September 2026
**Author:** the auditor (a Perplexity session, independent of Fable)
**Charter:** the auditor reads raw evidence and files a reading before seeing Fable's. Only Robert can overrule.
**Scope of this reading:** the step-35 crypto brick that ships as part of M-3 item 1 (bricks page shipped at `9dce71b`; brick lands under commits `ead3f81`, `18c6457`, `9092565`, acceptance at `df39329`, hour-fuzz at `fed950f`). This reading covers only the brick as evidence for the bricks page and program 7's dependencies; it is not a program-7 reading and does not touch the runtime, capabilities, or never-invariant stopping rules.
**Status:** filed cold, before reading Fable's parallel reading. Filed against `69860b0`.

---

## What the auditor read cold

1. The brick source, at `toolchain/src/bricks/crypto.zig` (520 lines, a C-ABI wrapper over `std.crypto` with SHA-256, SHA-512, BLAKE3, HMAC-SHA-256, AES-GCM-256, ChaCha20-Poly1305, Ed25519, X25519, Argon2id `Password.hash`/`Password.verify?`, and getrandom-backed `random.bytes`); the row-shape adapter at `toolchain/src/crypto_rows.zig` (258 lines); the C-side declarations and dispatch in `mo_rt.c`.
2. The corpus and expected files: `examples/basics/{hash,aead,sign}-vectors.mo` and `examples/effects/{password,random-fixture}.mo` with their `.expected` companions.
3. The step-35 brief, `mo-wiki/plans/interpreter-step-35.md`, and the worker's result file, `toolchain/bench/step35/RESULTS.md`.
4. The step-35 evidence bundle at `audit/evidence/2026-09-17/step35/`, including the worker's build log, differential run, worker fuzz, Fable's cross-implementation probe, MO0409 capture-violation trace, wrong-key crash reproduction, and Fable's one-hour fuzz.
5. Independently: re-ran Fable's cross-implementation `check.py` twice — once against the `mo run` output and once against the compiled-binary output — from the audit clone of the evidence bundle.

## What the evidence shows

- **Zig build test:** green, exit 0, 5:47.94 (worker) and reconfirmed in Fable's `zig-build-test.log`.
- **Differential run** (`diff.py --n 1000 --seed 35`): 18 rows × 1000 inputs, **0 mismatches** under `mo run`, **0 mismatches** under the compiled binary, cross-checked against Python's `cryptography` and `hashlib`. Per-row RNG is seeded `f"{seed}:{row}"`, so each row is independent and reproducible.
- **Fable's cross-implementation probe** (`gen.py` seed 11 vs Python): the two Mo output files (`run.out` and `bin.out`) are byte-identical (29 lines each; `diff -q` produced no output). The auditor independently re-ran `check.py expected.json run.out` and `check.py expected.json bin.out` — both returned `lines 29 mismatches 0 []`.
- **Fable's one-hour fuzz** (seed 1701, 60 min): **3,855,200 inputs across 9,638 batches, 2,037 verified `true` sentinels, 0 crashes, 0 hangs.** Worker's 10-minute fuzz (seed 35, 659,600 inputs) also 0 crashes.
- **Capture check:** MO0409 fires as expected for an anonymous function that captures the `random` capability (exit 1, correct diagnostic line, correct file:column pointer).
- **Wrong-key crash:** both `mo run` and the compiled binary exit 70 with `AesGcm.seal takes a key of 32 bytes, not 3` (the exact contract-violation message the brief prescribed).
- **RSS:** peak 105 MiB for `mo run`, 78 MiB for the compiled binary on the differential run (well under any RC3 concern).
- **Throughput (single-core, 4-core warm cache):** SHA-256 245.1 MB/s (`mo run`) / 531.9 MB/s (binary) / **1,548 MB/s raw Zig**; AES-GCM-256 328.9 / 595.2 MB/s; `Password.hash` 171 ms (`mo run`) / 145 ms (binary), `Password.verify?` symmetric.
- **Binary size:** `+406 KiB` (`jobq`: 4,622,832 → 5,028,800 bytes).
- **Build times:** warm `mo build` unchanged at 0.08 s. Cold `mo build` costs about 7 s once per (source, target, CPU, Zig version) and is cached thereafter.
- **Decision-log rows landed with the brick:** fourteen worker-authored rows, including three that the auditor flags as material for later steps and for the bricks page:
  1. `Password.verify?` accepts only strings produced by this brick's `Password.hash`; the brick documents this on the bricks page, and the worker closed a pre-existing trailing-`$` acceptance bug in Zig std's PHC parser.
  2. Argon2 parameters (`m=65536, t=3, p=1`) are the brick's, not the caller's, in this ship. This is a deliberate ergonomics-over-tunability choice.
  3. Entropy source is `getrandom(2)` on Linux and `arc4random_buf` on macOS.
  4. The random fixture is ChaCha20 keyed by SHA-256 of the run seed (documented, not hidden).

## Auditor's independent verification

- Re-ran Fable's `check.py` on both `run.out` and `bin.out`: 29 lines, 0 mismatches, on both, from the audit clone.
- Read the differential methodology: the seeded-per-row RNG is sound, the cross-implementation test is against a well-known independent library (`cryptography`/`hashlib`), and the row set covers hash, HMAC, AEAD (AES-GCM and ChaCha20-Poly1305), signature, KEM, and password functions. The auditor sees no gap in row coverage against the brief.
- Skimmed `crypto.zig` for API-surface honesty: no functions accept caller-supplied nonces without an obvious documented reason; nonce-generation goes through `random.bytes`; wrong-length inputs abort with contract-violation diagnostics rather than silently truncating. This matches the "brick is a shape, not a menu" pattern the bricks page describes.

## The one issue the auditor names

- **`List(UInt8)` overhead on 1 MiB SHA-256.** The `List(UInt8)`-wrapped throughput is 6.3× slower under `mo run` and 2.9× slower under the compiled binary than the raw byte-buffer path exposed to Zig. This is not a step-35 defect — it is a language-and-runtime issue about the value representation for bytes — but it is the auditor's ex-ante flag that the eventual byte-string value (or whatever name it takes) will materially move the bricks page's P4 numbers when it lands. The bricks page's crypto-latency footnote should name this ratio explicitly rather than only reporting the compiled-binary number.

## Reading

- **The step-35 crypto brick is fit for shipping** on the bricks page and as a dependency of program 7.
  - Correctness: 0 differential mismatches across ~5 million fuzz inputs and the row corpus, under both `mo run` and the binary, against a well-known independent implementation. The wrong-key path aborts loudly; the capture check fires; the PHC-format regression the worker closed in Zig std is a real defect the brick caught and fixed upstream.
  - Cost of zero deps (P1): the brick adds no runtime dependency and ~406 KiB to the binary; the cold-build cost pays once per target and does not affect warm iteration.
  - Cost of zero deps (P4): compiled-binary throughput is within 3-4× of raw Zig on hash and 2× on AEAD; the auditor considers this acceptable for a program-7 dependency and consistent with the bricks page's P4 framing. The `List(UInt8)` overhead is a bricks-page-honesty footnote, not a shipping blocker.
- **The brick does not by itself clear any stopping-rule row.** It is one of five bricks named on the bricks page; the P4 comparison that the bricks page needs is against Elixir's `telemetry_metrics_prometheus` (and its transitive dependency graph) as a program-7 dependency, not against `std.crypto`. That comparison lives in program 7's reading, not here.

## Where this leaves the roadmap

- M-3 item 1 (bricks page): shipped at `9dce71b`. This reading confirms the crypto brick as filed on that page.
- M-3 item 2 (step 35): the auditor reads it as accepted. The 14 worker-decisions above should show up in the bricks-page decision log if they are not there already; the auditor did not audit the decision-log wiring.
- **Standing auditor concern for the bricks-and-programs interaction (not a defect against step 35):** the "Reading" activity on each brick should not default to the auditor, or the design-versus-evaluation firewall the charter is built on will collapse at the brick level. The auditor's recommendation is a fresh session per brick reading (this session is that pattern for step 35), and if the crypto and TLS bricks ship before item 5 ("read the bricks") is executed by anyone, the auditor will note in the program-7 reading that P1 clears technically while the shelf-audit budget the bricks page implicitly promises has not been paid.

## What would flip this reading

- A reproducible differential mismatch on any of the 18 rows under either runtime with an integrity-preserving reseed.
- A crash, hang, or memory-safety failure on the fuzz corpus at any seed the auditor can pick.
- A demonstration that `Password.verify?` accepts a hash produced by a different Argon2id parameter set or a different PHC producer than `Password.hash` on this brick.
- A cross-implementation output that the auditor's re-run of `check.py` disagrees with.

None of these appeared in the evidence read. The reading stands as filed.

# Step 35's results

On the exe.dev VM (4 cores, x86_64, 15 GiB), Zig 0.16.0, 17 Sep 2026. Every number is the best of
five (`measure.py`). "before" is `mo` at part A (the brick not in the link), "after" at part C.

| measure | mo run | binary |
|---|---:|---:|
| SHA-256 of 1 MiB | 245.1 MB/s | 531.9 MB/s |
| HMAC-SHA256 of 64 bytes, 100,000 times | 68 ms | 35 ms |
| AES-256-GCM seal of 64 KiB | 328.9 MB/s | 595.2 MB/s |
| Ed25519 sign, 10,000 | 1,727 ms | 1,059 ms |
| Ed25519 verify, 10,000 | 1,125 ms | 704 ms |
| `Password.hash` once | 171 ms | 145 ms |
| the brick's SHA-256 of 1 MiB called straight (`raw.zig`) | 1,548 MB/s | |

| `mo build examples/programs/jobq`, warm | seconds | binary size |
|---|---:|---:|
| before | 0.08 | 4,622,832 bytes |
| after | 0.08 | 5,028,800 bytes (+406 KiB) |

A cold build pays about 7 s once per target, CPU, and zig to compile the brick, which is then cached
in `zig-out/mo-build/.bricks/`; a warm build does not see it.

**`List(UInt8)` costs more than 2× the raw call** on the 1 MiB hash, under both runtimes: 6.3×
under `mo run` (every byte is a 32-byte `Value` in and out) and 2.9× in a binary (a `MoValue` per
byte, copied to a buffer and back). That is a row for a later step (a byte-string value), not this
one. The first binary numbers (33 MB/s for AES-GCM, 203 MB/s for SHA-256) came from a brick compiled
for baseline x86-64, which has no AES-NI or SHA-NI; a build with no `--target` now compiles the
brick with `-mcpu native`.

## Audit items

- `zig build test`: the brick's vectors (FIPS 180-4, RFC 4231, 5869, 7748, 8032, 8439, 9106, NIST
  GCM 13, 14, 16) and the corpus, green at each of the three commits.
- The differential run (`diff.py --n 1000 --seed 35`), 18,000 inputs per runtime:

```
row                  n  mo run  binary  seconds (run, binary)
sha256            1000       0       0  0.1, 0.1
sha512            1000       0       0  0.1, 0.1
hmac              1000       0       0  0.1, 0.1
hkdf              1000       0       0  0.3, 0.4
hex               1000       0       0  0.1, 0.1
from_hex          1000       0       0  0.2, 0.1
equal             1000       0       0  0.1, 0.1
gcm_seal          1000       0       0  0.1, 0.1
gcm_open          1000       0       0  0.1, 0.1
chacha_seal       1000       0       0  0.1, 0.1
chacha_open       1000       0       0  0.1, 0.1
x25519_public     1000       0       0  0.1, 0.1
x25519_shared     1000       0       0  0.1, 0.1
ed25519_public    1000       0       0  0.1, 0.1
ed25519_sign      1000       0       0  0.2, 0.2
ed25519_verify    1000       0       0  0.2, 0.1
password_hash     1000       0       0  183.4, 147.8
password_verify   1000       0       0  164.2, 130.8
total mismatches: 0
```

- The fuzz run (`fuzz.py --minutes 10 --seed 35`) against the driver as a binary. The inputs that
  verify true are the ones a mutation left unchanged; a crash would be kept in `work/fuzz-crashes.txt`:

```
seed 35, 10 min: 659600 inputs in 1649 batches, 370 verified true, 0 crashes
```


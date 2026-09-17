# Step 35's tools

The crypto brick's audit items and numbers (`mo-wiki/plans/interpreter-step-35.md`). A `uv` project
whose one dependency is Python's `cryptography` (OpenSSL), the reference the brick is held against;
run everything with `uv run python ...` from this folder. Every `mo` process and every binary runs
under `guard.py SECONDS -- cmd` (a timeout and a 4 GB resident watchdog). Scratch files go to
`work/`, which git ignores. The numbers are in `RESULTS.md`.

- `driver.mo`: reads a file of lines, each a row's name and its arguments in hex
  (`hmac <key> <bytes>`), and prints each row's answer, one line each; diff.py and fuzz.py drive it
  under `mo run` and as a binary.
- `diff.py [--n 1000] [--seed 35] [--mo PATH]`: the differential run. For each of the 18 rows it
  draws `n` inputs at random lengths from 0 to 4,096 bytes (keys and nonces at their sizes; a
  quarter to a half of the opens, verifies, and shared secrets given a changed byte, a changed aad,
  a short text, a random key, or a low-order point), computes Python's answer, and prints the
  mismatch count under `mo run` and as a binary. Exits 1 on any mismatch, after printing the first
  one per row on stderr.
- `fuzz.py [--minutes 10] [--seed 35] [--mo PATH]`: mutates PHC strings and hex text (characters
  changed, inserted, cut, and repeated; parameters replaced by huge or negative numbers; `$` added;
  seeds spliced) into `Password.verify?` and `Hash.from_hex` through the driver built as a binary,
  400 lines a run, for the time given, and counts the lines that crash on their own; they are kept
  in `work/fuzz-crashes.txt`.
- `bench.mo OP COUNT SIZE`: one row COUNT times on SIZE bytes built before the clock starts; prints
  the milliseconds. `measure.py --before MO` runs every row best of five under both runtimes, the raw
  call (`raw.zig`), and `mo build` of `examples/programs/jobq` warm, with MO (a mo without the brick
  in its link) and with the one given.
- `raw.zig`: the brick's SHA-256 of 1 MiB called straight, the baseline for the `List(UInt8)` cost.

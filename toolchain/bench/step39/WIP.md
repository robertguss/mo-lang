# Step 39, work in progress (the second worker stopped for the VM move, 18 Sep 2026, 4:30 PM ET)

The brief is `mo-wiki/plans/interpreter-step-39.md`. Parts A and B are on
`main`, green. Parts C and D are partly written and **not green**: their edits
are in `wip-parts-c-d.patch` beside this file (from the repository root,
`git apply toolchain/bench/step39/wip-parts-c-d.patch` on `main` after
`18d45a6`). Parts E and F are not started. `RESULTS.md` has A and B's results.

## Done, green, pushed

- **Part A**, `faec6b5`.
  `python3 toolchain/bench/step36/guard.py 2400 -- zig build test --summary all`:
  `Build Summary: 5/5 steps succeeded; 240/240 tests passed`, exit 0, 442 s.
  Both auditor `chain-checks.py` copies unedited: control ready/ready, pathlen
  48, ca-keyusage 48, eku-client-only 43, unknown-critical 43
  (`evidence/chain-checks-*-part-a.json`). x509-limbo (`evidence/limbo.txt`):
  9,723 in the cut, 8,893 agree, **27 accepted but limbo says reject** (not 0: 6
  conflict with the auditor's valid control, which has no AKI, SKI, or leaf EKU;
  21 CA/B Forum profile rules), 803 rejected but limbo says accept (795 name
  constraints, 6 path building, 2 leaf key usage). Cost (`evidence/cost.txt`):
  chain check 197.0 → 199.2 µs Ed25519, 827.9 → 829.6 µs P-256; handshakes a
  second unchanged. Limbo found and part A fixed Zig's UTCTime year (50-99 read
  as 20YY) and the common-name fallback.
- **Part B**, `18d45a6`. Suite: `242/242 tests passed`, exit 0, 959 s. Both
  chain-checks copies: `alpn-65` ready/ready (`evidence/chain-checks-*.json`).

## In the patch, not green

- **Part C** (`tls.zig`: the client acts on no plaintext record after the
  ServerHello; the brick test "a record in the clear after the ServerHello ...";
  the spec sentence; step 38's `abuse.py` C2 close_notify cell now expects
  `connect=Handshake`). Brick tests 31/31 green
  (`zig test src/bricks/tls.zig -lc`); the new test goes red with the check
  removed (mutant checked by hand). `abuse.py` both runtimes: **63 of 64**
  (`evidence/abuse-part-c-wip.txt`): both C2 cells pass in both runtimes as part
  C wants; the one FAIL is a server cell part C did not touch,
  `run server finished close_notify`, said `accept=Closed` where
  `accept=Ok lines=0 end=None` was expected (the binary passed it). Not rerun:
  flake or not is open. The suite was not run on part C.
- **Part D, instruments only** (`bench/step37/fuzz.py`: every failed batch
  counted and kept under `work/fuzz-<seed>/failed-batches/`, both counts
  printed, exit 1 on either; `bench/step37/diff.py`: exit 1 on a mismatch). The
  auditor's `fuzz-accounting-check.py` against it reports
  `1 failed batches, 0 crashes` (`evidence/fuzz-accounting-check-wip.txt`).
  `diff.py`'s `-groups` to `s_server` and the `c-` chains in the draw are
  already in part A. Not run: the 1,000-session differential and the fuzz
  CPU-hour.

## Not started

- **Part E**: split `tls-client.mo`'s tests into deterministic controls with no
  allowance and seeded tests whose allowance applies only when a fault was
  injected, through the new test-only row the lead decided at 3:00 PM (a count
  of faults the simulator has injected in this run, 0 in the fixed-order run and
  under `mo run`; pick its receiver and name, add it to chapter 9's table and
  PRELUDE.md); keep `fn tried(` in the shape the auditor's
  `example-assertion-check.py` needs; `tls-vectors.mo` (RFC 8448 section 3, both
  runtimes; the brick already has a replay test to borrow from); remove chapter
  9's stale fixture paragraph; the corpus step runs duplex.mo and other
  scheduling-sensitive examples with `MO_CORES=1` as well as the default.
- **Part F**: `F_FULLFSYNC` on Darwin in both runtimes
  (`toolchain/src/blocking.zig:114`, `toolchain/runtime/mo_rt.c` near 8303),
  falling back to `fsync` on `ENOTSUP`/`ENOTTY`, a counter the runtime test
  reads, chapter 9's `## Fs` sentence, the README's runtime paragraph, and
  `jobq`'s Mac rows before and after with `measure.py` at 30,000 jobs.
  **Mac-only**: the counter trace and the before/after rows must be taken on the
  Mac.
- The Linux brick tests in the OrbStack container (step 38's RESULTS.md says
  how).

## Next commands, from the repository root

```sh
git apply toolchain/bench/step39/wip-parts-c-d.patch        # if the tree is clean
cd toolchain && python3 bench/step36/guard.py 900 -- zig test src/bricks/tls.zig -lc
python3 bench/step36/guard.py 900 -- zig build
cd bench/step38 && python3 ../step36/guard.py 1800 -- python3 abuse.py   # expect 64 of 64
cd ../.. && python3 bench/step36/guard.py 2400 -- zig build test --summary all
# then commit part C (tls.zig, abuse.py, 09-stdlib.md) and part D's scripts, and run:
cd bench/step37 && python3 ../step36/guard.py 30000 -- uv run python diff.py --seed 39
python3 ../step36/guard.py 7200 -- uv run python fuzz.py --seed 39 --minutes 60
```

## Local, not committed (ignored `work/` folders)

`toolchain/bench/step39/work/` (the x509-limbo clone at `118721335e67`,
`limbo-input.tsv`, `limbo-cases.tsv`, `cost.txt`, the cost binaries);
`toolchain/bench/step38/work/abuse-*.txt` (the part C run's per-runtime
outputs). Suite logs of this session were in the session's scratch folder; their
summary lines and exit codes are above.

## Decisions the brief did not cover

1. The alerts: OpenSSL's for pathLen, keyCertSign, and EKU; 43 for an unknown
   critical extension where OpenSSL sends 46; 43 for name constraints.
2. The root's extensions are checked like any issuer's (as OpenSSL does).
3. `anyExtendedKeyUsage` alone does not satisfy server authentication, leaf or
   CA.
4. The leaf's keyUsage must hold digitalSignature (RFC 8446), stricter than
   OpenSSL.
5. A duplicate extension is `bad_certificate`.
6. The brick's tests make chains in Zig; the corpus and the differential read
   `gen-constrained.sh`'s `c-` files.
7. The x509-limbo run calls `checkChain` directly, the chain ordered as a server
   would send it.
8. The brick reads validity itself: UTCTime 50-99 is 19YY (RFC 5280), where Zig
   read 20YY and refused every chain dated before 2000 as not yet valid.
9. No common-name fallback (RFC 9525 6.3): a leaf with no SAN is for no host,
   stricter than OpenSSL.
10. The RFC 5280 rules a certificate alone shows are enforced (serial,
    keyCertSign only on a CA, the root a CA, CA basicConstraints critical, CA
    subject not empty, empty-subject SAN critical, dNSName syntax, AKI
    keyIdentifier, AKI and AIA not critical, AIA shape); policyConstraints is
    refused as unsupported.
11. Not enforced, so limbo's accepted-but-should-reject is 27, not 0: AKI/SKI
    presence and the leaf's EKU (they would refuse the auditor's valid control;
    **the lead's to decide**), CN in SAN (CA/B BR 7.1.4.3; would refuse private
    CAs' descriptive CNs), public-suffix wildcards (no suffix list in the
    brick), and the other CA/B Forum profile rules.
12. limbo.py picks the server's chain breadth first by names and signatures (the
    depth-first walk was exponential); the 6 bettertls path-building cases stay
    refused: the brick does no path building.
13. ALPN's limit is 8,192 bytes on the wire, so a ClientHello with the whole
    offer fits the 16 KiB the other end reads; past it `offer` crashes naming
    the row in both runtimes. That is in chapter 9's `offer` rows, outside the
    spec lines the write scope names, since part B asks the row to state the
    limit.
14. `fuzz.py` and `diff.py` return their status from `main()` and exit with it,
    so the auditor's mock (which calls `main()`) still prints its report.
15. Two processes were stopped by hand this session: the first limbo run after
    11 minutes at 100% CPU (before Robert's rule against stopping slow processes
    arrived; its cause was the exponential walk), and an orphaned profile run
    whose guard had already expired and killed its parent.

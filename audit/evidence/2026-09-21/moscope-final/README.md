# Moscope final raw evidence — 21 Sep 2026, 10:08 PM ET

Scope: serial synthetic Linux interpreter and ordinary native CLI verification.
No private histories, performance measurement or Step42 candidate overlays.

Source candidate: c52db2f38a2d73ac4c250a4b90d073028bb11723. Bundle prerequisite:
dad7b3743da38d929f632d70db42e592cd1b755e. Integrated verification commit:
6eaacb2889f100e0120a10d471a78489c2d92b13, tree
0977865bc475aeb9432e0251b29cb6bc7d674e3e. Working directory:
/tmp/mo-lead-moscope-full, branch lead/verify-moscope-full. Tracked tree was
clean after all runs. Toolchain bytes remain identical to the accepted base.

## Files

- `source.bundle`: complete app candidate and its acceptance scripts.
- `worker-evidence.tar.gz`: metadata attempts (including stopped attempt 01),
  final 21-command metadata run, post-metadata interpreter/native raw receipts.
- `worker-generated.tar.gz`: eight generated C files and eight native binaries.
- `lead-replay.tar.gz`: independent 66 interpreter and 74 native receipts, raw
  streams, expectations/comparisons and synthetic inputs; caches excluded.
- `lead-generated.tar.gz`: independent eight C files and eight binaries.
- `lead-regression.tar.gz`: build/full-corpus raw streams and receipts plus
  outer exits, integration identity and independent process-group checks.

## Commands and printed results

From the integrated repository root, each with a fresh outside-source artifact
directory and the accepted compiler at
`/tmp/mo-moscope-evidence-7aa1e81e/prefix/bin/mo`:

```sh
python3 -B examples/programs/moscope/acceptance/verify.py interpreter --mo /tmp/mo-moscope-evidence-7aa1e81e/prefix/bin/mo --artifacts /tmp/moscope-final-lead-interpreter
python3 -B examples/programs/moscope/acceptance/verify.py native --mo /tmp/mo-moscope-evidence-7aa1e81e/prefix/bin/mo --artifacts /tmp/moscope-final-lead-native
python3 -B examples/programs/moscope/acceptance/final_regression.py --zig /opt/zig-x86_64-linux-0.16.0/zig --artifacts /tmp/moscope-final-lead-regression
```

Interpreter: 66/66 exact results. Native: 74/74 exact results (eight cold
builds, 59 CLI cases, seven module binaries); 27 tests in each runtime.
Metadata: worker's 21/21 real format/write/check commands. Final replay
inventory: 95a9bdbbfd4435cf57c653beeda5321c6744e0aecdf719819c4b3f89456dbe32.

The final recorder executed from toolchain/:

```text
zig build -j4 --summary all
Build Summary: 5/5 steps succeeded
exit 0; 113.05950243200641 seconds

zig build test-corpus -j4 --summary all
Build Summary: 5/5 steps succeeded; 276/276 tests passed
exit 0; 657.600399324001 seconds
```

276 counts Zig tests, not application files. Corpus discovery includes all seven
moscope modules and main's three cases with expected statuses 0/1/2. The corpus
deletes generated examples/zig-out on completion. All 142 lead payload receipts
record child_exit, no supervision errors and literal group absence; retained
independent ps checks found all 142 PGIDs absent. The full-corpus stderr
includes expected fault-test diagnostics and a Zig `failed command:` line;
retain it verbatim, alongside the successful summary and raw exit. It is not
empty stderr.

Compiler SHA256:
3ef07d08ed6d0c802a2597bd956579873851855961cf2e5f01cf87018d273b78. Guard SHA256:
7a5eadf9794110efec179872b02833df8fb4a12a3ad8fb8244074f903a8d23c2. Zig SHA256:
2317bbb91798556d9d0f38aabdac23db83f0979b25f767259ae474546724087c.

## Archive hashes

```text
5dd9a9e2fbceb5984e9e63765ff7c13747db168b2618419d7c2b2a6abc4b350d  lead-generated.tar.gz
9f776e38d5c16291d2003e302e29ae50c5db949c80fc2f593e7578179a632b8f  lead-regression.tar.gz
5b1841f84eb464bd80fbccb3f8bbbf86e6f0cae7be61bcfcb5630997eb70566b  lead-replay.tar.gz
ca69866e9c95ca10da63e7a19f30ec2c6770ff35328bac44729e4f840507fb39  source.bundle
9bbbaeceed3bf6e9f408fad33910c6f6356fe4ff401aaa04486ddaa98812f0da  worker-evidence.tar.gz
9267c66bcadfea6d923d254d7a06fafd48fe3de3b2415361703bf13c0ea49a29  worker-generated.tar.gz
```

Lead reading lives in the decision log; open it only after your own reading.

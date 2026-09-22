# Moscope interpreter checkpoint — 21 Sep 2026, 8:21 PM ET

Raw synthetic evidence, not full app acceptance. No private data.

- `source.bundle`: candidate 8ef1730c77ef316dfb10041b00f8ad7fe59bf449,
  prerequisite dad7b3743da38d929f632d70db42e592cd1b755e; app-only changes.
- `worker-evidence.tar.gz`: preserved interpreter attempts including final 15,
  recorder mock tests, raw streams, exits and receipts.
- `lead-evidence.tar.gz`: independent replay in `/tmp/mo-lead-moscope-full`,
  branch `lead/verify-moscope-full`, candidate merged with docs-only local main
  c3ad75d14c124247ad261722ea486bdf999b5d21. Main itself remains app-free.
  Includes generated synthetic inputs, exact comparisons, raw streams, outer
  exit and independent post-run process-group observations.

Lead command from the verification worktree root:

```sh
python3 examples/programs/moscope/acceptance/verify.py interpreter --mo /tmp/mo-moscope-evidence-7aa1e81e/prefix/bin/mo --artifacts /tmp/moscope-lead-interpreter-8ef
```

Lead outer exit 0, empty outer streams; 66/66 exact cases, all child_exit, zero
supervision errors, all groups literally absent. Independent ps recorded 66
absent groups. Seven module invocations include 27 tests. Compiler SHA256
3ef07d08ed6d0c802a2597bd956579873851855961cf2e5f01cf87018d273b78; guard SHA256
7a5eadf9794110efec179872b02833df8fb4a12a3ad8fb8244074f903a8d23c2. Source
inventory 1293e9f333c14e3e2e095abfc404e40c268469674ed6a6d45d87fdec9d8ee354.

Archive SHA256 values:

```text
49d361d25dc23fe8fd079cf296c42bf2773bcaa2d2443c2524b4d66602351fe9  lead-evidence.tar.gz
6733d51abeefd54b78fa8e35f83d976b28398412dc436389c081053d46974167  source.bundle
d6fc0b0d7dedfaf4e175c493c3b1adb51cc64e5ff6698a9909ee938e5321e200  worker-evidence.tar.gz
```

Native, real formatting/metadata, final integrated replay and unfiltered
repository regression remain outstanding. Step42 and harness remain paused.

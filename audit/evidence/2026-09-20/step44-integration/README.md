# Step 44 — lead integration evidence, 20 September 2026

Raw evidence index; the lead's acceptance reading is in the decision log
(**open after your own reading**). No auditor session or hidden suite was opened.
Nothing in this bundle has been pushed or published as an audit handoff.

## Revisions and locations

- Worker correction: code `b7a21af7e76969525596d1ee0d3c9b9fc4b34131`,
  report `040da1310158883eaffdcffc863bde2f0bb8a32e`, branch
  `toolchain/step-44-review-fixes`.
- Isolated integration before catalog regeneration:
  `3bc0b508ac05b4ec46e7f509f0cc3ceaae350a40`.
- Tested candidate: `cdf1e9660f51623d71cfb7fffd6ceef8d8a99078`, branch
  `lead/verify-step44`, worktree `../mo-lang-worktrees/lead-verify-step44`.
- Line baseline: `c4462935fdbcf99d3b8b53258828d028d68594bc`, detached worktree
  `../mo-lang-worktrees/lead-step44-lines-base`.
- Worker scripts and historical corrective outputs remain under
  `toolchain/bench/step44/` at the candidate. Original worker measurements and
  every failed lead attempt remain intact.

## Commands and raw output

Every named command has a `.log` and a separately captured real `.exit`.
`/usr/bin/time -p` surrounds `python3 bench/step36/guard.py SECONDS -- COMMAND`
from the verification tree's `toolchain/`; the guard imposes a deadline and
4 GB ceiling. Capture uses `tee`, `pipefail`, and the command's `PIPESTATUS[0]`,
not tee's status. Finite full-suite/measurement commands use `caffeinate -i`.

- `build-02`: `zig build --summary all`, guard600, exit0, real36.33s.
- `focused-zig-03`: `zig build test -Dtest-filter=chunks --summary all`,
  guard1800, 5/5 tests, exit0, real22.29s.
- `full-suite-01`: first preserved corpus-classification failure, 270/271,
  exit1, real1142.19s; see its original log/receipt.
- `full-suite-02`: `zig build test --summary all`, guard2400, 271/272,
  exit1, real622.91s; generated diagnostic catalog stale.
- `errors-catalog-01`: `zig build errors`, guard600, exit0, real1.55s;
  regenerated only MO0209/MO0223, committed in the candidate.
- `full-suite-03`: same unfiltered command/guard, **272/272**, exit0,
  real629.86s, user524.10s, sys77.28s. Nested intentional process kills,
  crashes and negative fixtures appear in the successful suite's raw output;
  the outer exit and complete summary are retained, not filtered.
- `behavior-plan-02.json` gives the exact 30 subsequent command lines and
  guards; each command's named log/exit is alongside it. Drivers are the
  unchanged worker-authored `behavior_probe.py`, `socket_probe.py` and
  `tls_oracle_probe.py`. TLS mutation controls intentionally produce inner
  exit1 while the driver exits0 only on the expected positive-test failure.
- `line-measurement-plan-02.json` fixes compiler selection, candidate and
  order. `line-baseline-build-01` builds the baseline under guard600.
  `line-256m-01-baseline` through `line-256m-10-current` invoke the unchanged
  `throughput.py --mo <revision>/toolchain/zig-out/bin/mo --label <name>
  --mode lines --mib 256 --runtimes run,binary --best-of 1`, guard360.
  Order A B B A A B B A A B gives five samples per revision/runtime.
  Driver builds run from the candidate repository root; transfer timing
  excludes compilation. Every sample transfers 268435456 bytes of 4096-byte
  records; SHA256 `d496cd0757cecd0e21957bcc879367edcf9a744d316710f5b69d4202f959835f`.
  Raw start/end load averages are preserved. No sample was discarded.

`full-suite-03-result.json`, `behavior-result-01.json` and
`line-measurement-result-01.json` contain lead-derived summaries, not replacement
raw output. The measurement summary retains all twenty samples, best/median/range,
calculation precision and limitations. `runtime-cleanup-01.json` records only
owned worktree processes: the retained idle shell, no running compiler/test/probe
or prior caffeinate. The verification worktree was clean after execution.

Linux remains deferred. These runs do not accept the workspace server, Step42,
Step39, Darwin full-sync durability, Program7, or any language catch claim.

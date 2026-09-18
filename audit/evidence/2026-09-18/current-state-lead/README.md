# PR 12: lead reproduction of harness controls

Run by Amp, the lead, 18 Sep 2026, 5:28 PM ET, in the Linux Amp orb. Source
commit: `981376db6adbd99b45c4f264f1748cf585796932` on `main`. This is after
filing the lead's reading and reading/merging PR 12.

## Commands and raw output

Both commands completed in the shell tool's ten-second wait. No Mo program,
compiler build, server, or network fault campaign ran. `-B` prevents bytecode
cache writes. The scripts were run unchanged.

```sh
python3 -B audit/evidence/2026-09-18/current-state/harness-probe.py
python3 -B audit/evidence/2026-09-18/recent-tls-auditor/fuzz-accounting-check.py
```

- `harness-probe.log`: exit 0. The four mocked runner cases inject exits 1 and
  124 into each of two runners; every wrapper returns 0. Mocked stimulus failure
  produces 20/20 passing server cells when paired with mocked expected output
  and healthy recovery probes. A mocked invalid runtime selection exits 0. The
  real `--only typo` invocation exits 0 with zero checks.
- `fuzz-accounting.log`: exit 0. A mocked batch exits 134, both singleton
  replays exit 0, and the driver prints `0 crashes`.

The probe exit codes mean the reproductions completed; they do not mean the
instruments under test are correct. These are harness control-flow findings, not
fresh TLS failure, compatibility, throughput, or recovery measurements. The logs
retain the scripts' original UTC clock output; the run time above is ET. The
scratch directory printed by the harness was removed after its output was read;
the complete printed JSON remains in `harness-probe.log`.

## Other evidence inspected, not rerun

- `toolchain/bench/step39/evidence/chain-checks-recent-tls-auditor.json`: worker
  output after A/B; valid control and ALPN-65 ready, four constrained chains
  refused. No fresh TLS acceptance is claimed.
- `toolchain/bench/step39/evidence/limbo.txt`: 27 accepted-but-should-reject.
- `toolchain/bench/step39/evidence/abuse-part-c-wip.txt`: 63/64.
- `audit/evidence/2026-09-18/step-39-move-checkpoint/`: preserved worker suites
  and patch inventory; not a lead acceptance run.

Readings, open only after one's own: the lead's
`audit/fable-reading-2026-09-18-current-state.md`, the auditor's
`audit/mo-audit-2026-09-18-current-state.md`, and the subsequent lead comparison
`audit/fable-comparison-2026-09-18-current-state.md`.

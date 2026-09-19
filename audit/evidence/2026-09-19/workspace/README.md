# Workspace foundation lead acceptance — 19 Sep 2026

Accepted Python/BusyBox workspace scope; open this after your own source reading.
Worker base 2fc1235, implementation 50f8a9d and evidence d9444f0 integrated as
bcdf7c1/f4fe3ea. Exact 1586 changed files match the frozen worker tip. No worker
history was rewritten; actual Astra author/committer throughout.

`attempt-01/` independently passed 27 unit tests, 22 mounted workspace controls,
17 existing executor controls and the collector-loss regression. Every guard
exit is 0 for those steps; process groups are empty. The first extra lead probe
failed before observing descendants because its synthetic parent shell omitted
wait and exited immediately. This is a retained lead probe failure, not a green
control or a product correction. Original lead-controls.py and accept-source.py
remain with the evidence.

`extra-02/` uses lead-controls-v2.py with the explicit wait. Both extra controls
pass: refusing a second command preserves the active first command/identity until
explicit cancellation and collection; exact edit preserves the normalized
executable mode and exact surrounding bytes into protected snapshot verification.
Final lifecycle query passes. All candidate/workspace containers, services,
cgroups, mounts and directories are absent. Retired workspace-ID records remain
as designed and contain no candidate files.

Both attempts preserve all 2530 tracked executor files byte-for-byte. Separate
read-only shared Mac Docker snapshots before/after each attempt show the same
five full IDs and exited states. Candidate commands ran only in the dedicated
mo-executor-r01 machine, never through that shared daemon.

Reproduce from main in an owned Herdr run pane, new output names:

```sh
python3 toolchain/bench/step36/guard.py 1500 -- python3 audit/evidence/2026-09-19/workspace/accept.py workspace fresh-01
python3 toolchain/bench/step36/guard.py 180 -- python3 audit/evidence/2026-09-19/workspace/accept.py workspace-extra extra-fresh-01
```

The current full runner uses the corrected extra probe; the original runner
is retained as attempt-01/accept-source.py. The second command runs only the
extra controls and final cleanup. Historical outputs are refused rather than
overwritten. Numeric bounds,
commands, real exits, before/after source hashes and Docker identities are in
per-step records. The source-check snapshot identifies the integration commit.

This accepts trusted file operations, real bounded synthetic feedback commands
and copied snapshot checks. Empty directories are deliberately omitted from
snapshot content; executable/nonexecutable file modes normalize to 0755/0644.
There is no HTTP/Mo/provider integration, arbitrary application build, language
benchmark, Darwin full-sync or Step 39 acceptance in this result.

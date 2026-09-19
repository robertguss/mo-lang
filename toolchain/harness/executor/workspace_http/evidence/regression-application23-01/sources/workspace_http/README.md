# Workspace HTTP bridge

Python stdlib frontend for the accepted isolated Workspace and cleanup-only
recovery APIs. Import `Bridge` with `toolchain/harness/executor` on `sys.path`.
The operator supplies run ID, a new private result directory, source byte mapping,
exact policy/image/toolchain selection, and a protected verifier dictionary
(`script`, nonempty accepted `checks` inventory, `seconds`) to `Bridge(...)`.
`start()` returns only after successful creation and loopback listener setup.
The returned `port`, external `workspace_id` and private `token` are operator
connection data. Keep the token outside candidate/model context.

Candidate HTTP exposes only six tools. Lifecycle is Python-only: `freeze()`,
`verify()`, `close(seconds=60)`, `stop_owner()` and `recover()`. Close reports
whether the owner exited, not a cleanup verdict. Read private owner/recovery
proofs. Recovery refuses while the retained child is live and never repeats work.
No provider, Mo profile, local execution fallback, retry, or resume is included.

- [Wire contract](CONTRACT.md)
- [Owner and IPC ordering](IPC.md)
- [Fixed 22-group registry](GROUPS.md)
- [Intermediate review checkpoints](REVIEW-CHECKPOINT.md)
- Final results and limitations are in WORKER-REPORT.md when frozen.

Run every test/server/build in an owned right/no-focus Herdr pane, from the repo
root, with a new evidence directory and a numeric guard. Example local command:

```sh
python3 -B toolchain/harness/executor/workspace_http/run_guarded.py 120 NEW_EVIDENCE python3 -B toolchain/harness/executor/workspace_http/local.py
```

`local.py --groups deadlines,shutdown` selects existing named groups; unknown,
empty and duplicate selections fail before setup. Local controls use a separate
subprocess double and cannot prove remote isolation. `review_baseline.py` is a
retained failing regression control against the immutable pre-fix bridge. It is
expected to exit1 and is not part of the green matrix.

Real execution requires the lead's exact machine release. With release, run
`live.py NEW_CONTROLS` or `live.py NEW_CONTROLS --application` through the same
numeric wrapper (900s). All real commands execute inside the existing isolated
Workspace. `live_owner.py` records bounded raw transport only in tests; its
lost-create fault is an operator-owned test marker, absent from production.
`review_live.py NEW_CONTROLS` adds real controls to the existing deadlines/shutdown
groups. It advances the test frontend deadline before dispatch; it is not a full
900s soak. No production policy constant is changed.

Inherited machine regressions use unchanged
`recovery/observe_regression.py SUITE NEW_CONTROLS`, separately guarded and
sequential, where SUITE is workspace22, executor17, lifecycle1 or application23.
The compiler has a separate gate and must never overlap machine workload.
Exact commands, source snapshots/hashes, original failures, exits, process groups,
raw transport and positive cleanup/readback evidence live under `evidence/`.
Private capability files remain0600 and are ignored by Git; never print them.

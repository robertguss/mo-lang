# Late transport response cleanup correction

This receipt supersedes the completion claim in REPORT.md for lead review.
The initial commit `c1d4fe16ede1ef2a83188b980946383dcea1cfcd` and all its
evidence remain unchanged. The exact original base is still
`54c3dcd8617c8d693fddee8efda99e03ac05e879`.

Lead's independent synthetic probe found that a transport promise resolving
after abort returned a Response whose body was never cancelled. Original
auth.mjs SHA-256: `48922bfbe03190569978870e5f113b52c047456b367c1fe0f5398d9c8ae60fd3`.
The original controls proved late credential suppression, but missed body
cleanup. The new red run reproduced both abort and deadline variants, one
transport call each, bodyCancelled=false, 0/2 controls, child/outer exit 1.
See `auth-race-red/`; these failures are retained.

The narrow fix keeps observing transport settlement after the bounded wait
ends. A response arriving when request/operation is aborted or request is
closed has its body cancelled. The finally path also cancels any received body
when failure precedes reader acquisition. Existing reader cleanup remains.
Cancellation errors are consumed without raw diagnostics. No request replay,
retry, new dependency, foundation change or ownership expansion was added.

Corrected auth.mjs SHA-256:
`7c9b3b724bbbe1c7133e2cde2684fac2623b432796f71604b15ce570a5188a2c`.

| Verification | Result | Evidence |
|---|---|---|
| Fixed auth controls | 28/28; 43 synthetic requests | `auth-corrected/output.log` |
| Existing response_bounds group | Deadline late response, calls 1, bodyCancelled true | Final JSON in auth-corrected |
| Existing late_success group | Abort late response, calls 1, bodyCancelled true | Final JSON in auth-corrected |
| Lead's exact synthetic probe | calls 1; lateBodyCancelled true; sourceUnchanged true | `lead-probe-corrected/output.log` |
| Unchanged foundation suite | 28/28 | `foundation-corrected/output.log` |
| Foundation scope | 96 base files byte-identical | `scope-corrected.json` |

All corrected checks have child exit 0, outer 600-second guard exit 0 and owned
process-group absence. Tests ran in fresh right/no-focus pane `w4:p1S`, with the
same 550-second group guard (foundation inner runner 500). The pane was closed
only after returning to its shell. The auth suite records zero fixture listeners,
zero remaining children and removed private temporary stores. Foundation
outbound fixture observations are retained in its corrected evidence folder.

Exact commands from repository root:

```sh
bash toolchain/harness/provider/auth/attempt.sh auth-race-red node test.mjs .cache/prepared-01/.cache/runtime late_success response_bounds
bash toolchain/harness/provider/auth/attempt.sh auth-corrected node test.mjs .cache/prepared-01/.cache/runtime $(cat toolchain/harness/provider/auth/controls.txt)
bash toolchain/harness/provider/auth/attempt.sh lead-probe-corrected node /Users/robertguss/Projects/startups/mo-lang/audit/evidence/2026-09-19/auth-readiness/late-response.mjs /Users/robertguss/Projects/startups/mo-lang-worktrees/harness-provider-auth-v1/toolchain/harness/provider/auth/auth.mjs
bash toolchain/harness/provider/auth/attempt.sh foundation-corrected python3 .cache/prepared-01/run.py 500 node test.mjs evidence/auth-regression-corrected.outbound.json
bash toolchain/harness/provider/auth/attempt.sh scope-corrected python3 scope.py scope-corrected.json
```

The lead probe was read/executed without modifying its source or historical
outputs; new output lives only in auth evidence. All original source/runtime,
trust, store and live-auth limitations in README.md/REPORT.md still apply.
No live network, real credential store, machine operation, push or rebase ran.
Independent lead acceptance remains required.

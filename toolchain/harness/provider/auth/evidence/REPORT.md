# Worker receipt: provider auth v1

Ready for independent lead review; not accepted and no live OAuth claim.

- Exact clean starting base: `54c3dcd8617c8d693fddee8efda99e03ac05e879`.
- Worktree: `/Users/robertguss/Projects/startups/mo-lang-worktrees/harness-provider-auth-v1`.
- Worker: GPT-6-Astra, low implementation brief; local author/committer GPT-6-Astra.
- Write scope: only new `toolchain/harness/provider/auth/`. No foundation,
  compiler, Agent, executor, wiki, package-lock or Pi patch edits. No nested
  workers, machine commands, live auth, credential discovery, push or rebase.
- Worker pane `w4:p1J`; owned right/no-focus run pane `w4:p1K` (closed after
  final checks). Lead progress/receipt destination `w4:p1`.

## Final verification

| Check | Result | Raw evidence |
|---|---|---|
| Fixed bounded auth controls | 28/28, 41 synthetic fetch calls, 4 rejected non-fetch probes | `auth-final/output.log` |
| Auth exit and cleanup | child 0, outer guard 0, process group absent; zero fixture listeners/children, temporary stores removed | `auth-final/{exit,outer.exit,cleanup.json}` |
| Unchanged foundation regression | 28/28, 3 unexpected-egress rejections | `foundation-final/output.log` |
| Foundation exit and cleanup | child 0, outer guard 0, process group absent | `foundation-final/{exit,outer.exit,cleanup.json}` |
| Selection rejection | empty, unknown, duplicate, >28 each exit 2; harness exit 0 | `selection-01/output.log` |
| Foundation scope | all 96 tracked files match base SHA-256 | `scope-final.json` |
| Source preparation | archive integrity, 220 runtime files, 92 dependency versions; 5 records byte-identical | `setup-01/output.log`, `provenance.json` |

Every Node/test command ran in the owned Herdr pane under a 600-second outer
guard and a 550-second group runner (foundation nested runner: 500 seconds).
Final outer exits are captured by `attempt.sh`. Earlier attempts retain child
exits and group absence; their outer exits were not separately persisted.
Read-only base/scope inspection used ordinary filesystem/git commands; the final
scope verification was also repeated through the guarded pane. All evidence is
under 16 MiB. Node v24.20.0, npm 11.19.0 (resolved executable paths in setup and
foundation logs). No new package, cold registry install or network download ran.

Exact final commands from repository root:

```sh
bash toolchain/harness/provider/auth/attempt.sh auth-final node test.mjs .cache/prepared-01/.cache/runtime $(cat toolchain/harness/provider/auth/controls.txt)
bash toolchain/harness/provider/auth/attempt.sh foundation-final python3 .cache/prepared-01/run.py 500 node test.mjs evidence/auth-regression-final.outbound.json
bash toolchain/harness/provider/auth/attempt.sh scope-final python3 scope.py scope-final.json
```

`attempt.sh` invokes the existing step36 guard with 600 seconds and the owned
`run.py`; each attempt's `command.json` records expanded arguments and cwd.
All prior attempts are preserved: setup-01, auth-01/02/03, foundation-01,
selection-01. No implementation run failed. Selection failures are expected
negative results, retained verbatim. Narrow follow-up changes added request-body
bounds, mapped request deadlines, lock permission verification, status-only
output, expired-new-credential rejection, offline CLI preload and strengthened
overlap/expiry/atomic-failure controls. The final run includes all of these.

## Ordering and limits

The raw final JSON records actual overlapping operation order: refresh enters,
logout queues, refresh persists, logout completes; polling login is invalidated
by logout and conflicts; newer login commits before the older login is rejected.
Controls also use a real second process holding a store lock, kill it, observe
deadline/five-second lock failure, and explicitly remove only that dead fixture's
lock. No lock stealing or automatic uncertain-write replay is implemented.

The library is restricted to a dedicated auth process, with a once-installed
global fetch wrapper and per-operation context. It is not an OS sandbox. Caller
supplies a verified runtime, trusted transport, operator sink and all candidate
roots. Same-UID code and stable ancestors are trusted. Missing/corrupt stores
remain distinct; no real provider store was read. Test stores and token claims
are synthetic. Device events never enter retained output; resolve returns an
access token only in trusted process memory after persistence. No power-loss
durability, token cryptographic verification, live registration/entitlement or
live inference support is claimed.

Source pin/artifact mismatch remains disclosed: exact Pi source
`36b60d2e8985899743c4cf5bd5f8929832a3f05d`, artifact 0.85.1; 148/177 embedded
sources match, 29 differ/absent, OAuth sources match. The foundation's existing
SSE patch and catalog hydration were reproduced unchanged in an owned ignored
copy. Historical preparation/evidence was read/copied, never regenerated in place.

Lead owns independent rerun plus an extra control, review of the immutable local
commit, integration, live acceptance and any machine action. No ownership
expansion was needed.

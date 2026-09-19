# Local release-review checkpoint

Exact base 3023a01a744d1580ca9814e595ddf990a12e456d, branch
harness/workspace-http-v1. Only new workspace_http paths are owned. Worker is
GPT-6-Astra; author and committer are explicitly GPT-6-Astra.

Review CONTRACT.md, GROUPS.md (22 fixed names), and IPC.md before machine release.
This is an intermediate immutable checkpoint, not completion or acceptance.

Retained attempts:

| Attempt | Count/result | Actual exit | Owned group absent |
|---|---|---|---|
| red-lifetime-01 | 2 expected failing assertions | 1 | true |
| local-01 | verifier test-fixture schema errors | 1 | true |
| local-02 | 19 passed, 3 early-refusal socket reset errors | 1 | true |
| local-03 | 22/22 local subprocess-double groups | 0 | true |
| inherited-local-01 | 59/59 inherited local tests | 0 | true |

The red baseline deliberately models deficient request-owned cancellation after
an effect; it does not reproduce a defect in the accepted Workspace implementation
and does not itself kill an actual frontend parent. The green frontend-death
control does SIGKILL a real frontend parent process while its separate double
owner is working; the owner records completed execution and confirmed test-double
delete. Real isolated Workspace cleanup remains untested in this checkpoint.

Each evidence directory retains argv, code snapshots/hashes, output, HEAD, real
exit and process-group inventory. No machine, compiler, provider, core, wiki,
image, configuration or shared Mac service commands were run. No token is in
retained output or source snapshots. Runtime private capability files were in
local test temporary directories removed after process cleanup.

Remaining work: expand boundary controls where needed; real BusyBox/application
HTTP and process-death evidence; exact isolation/cleanup/source canaries; inherited
live regressions; full compiler build/test after exact gate release; frozen final
report/manifest/clean commit. Independent lead verification remains the lead's.

## Corrected source checkpoint

Independent review of75680f31 found response-drain termination and deadline/EOF
misclassification. `review-baseline-red-01` executes its immutable bridge bytes
(hash printed) against the new focused controls: five failing assertions, exit1,
group82269 absent. This includes both partial IPC and deterministic lease-close
races, both held-open response cases, and the cleanup transport reserve control.
`review-red-01` retains the intermediate current-source three-failure run.
`review-green-01` passes both focused groups and every added subcase, exit0,
group82420 absent. The drain now only disposes its connection; send/close share
one absolute2s deadline. Deadline-triggered IPC closure returns504/unknown.

Real BusyBox02 passed22/22, but predates these corrections. Application01 stopped
at disconnect after10 completed groups: original candidate completed successfully,
normal delete unresolved after raw controller `Refusal: deadline`, later explicit
recovery confirmed cleanup. Its exit1, raw transport sequence49 and positive
finally absence/shared5 readback are retained. No measured clock-skew cause is
claimed. Lead directed normal delete55s plus inherited5s transport inside60s;
owner now reserves that margin and accounts for prior cleanup collection time.
Real corrected matrices will supersede earlier verification without deleting it.

Capability files stay private0600 and are excluded from Git under the scoped
.gitignore. They are never printed, embedded in captured wire requests, or copied
into source snapshots. Core raw transport carries no HTTP capability token.

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

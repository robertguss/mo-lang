# Private provider auth

Offline-tested operator authentication for the fixed Pi source
`36b60d2e8985899743c4cf5bd5f8929832a3f05d`. This supplies a private credential
store and device-login boundary; it does not perform inference, execute tools,
discover existing credentials, or change the provider foundation. Live login,
client registration, subscription entitlement and live acceptance are unverified.

## Process and API contract

Use **one dedicated auth process**, never a process containing inference or
other global transport consumers. Call `installTransport(fetch)` once, then
`loadOAuth(absoluteVerifiedRuntimeDirectory)` and `createAuth(...)`. Runtime
preparation is a trusted caller responsibility. The explicit runtime must be
verified by the foundation preparation procedure; arbitrary supplied source is
arbitrary code. No ambient runtime, Pi, Codex, Amp, environment credentials or
configuration are loaded. `auth.d.mts` describes the operator API.

`login`, `status`, `logout` and `resolve` accept an optional AbortSignal and
integer `deadlineMs`. Login defaults/maxes at 900000 ms; the other operations
default/max at 30000 ms. Each request including streamed body consumption is
limited to 10000 ms and 65536 bytes. Only exact POST URLs at
`https://auth.openai.com/api/accounts/deviceauth/usercode`,
`https://auth.openai.com/api/accounts/deviceauth/token` and
`https://auth.openai.com/oauth/token` pass. URL credentials, alternate origins,
query strings, fragments, noncanonical URLs, alternate methods and redirects
are rejected before dispatch. Request bodies are bounded too. Context-local
operation state lets auth operations overlap without sharing cancellation.
The wrapper is a trusted-process boundary, not an OS network sandbox.

The real pinned `openaiCodexOAuth.login`, `refresh` and `toAuth` execute.
Only the exact device-code select option is answered. Browser/manual prompts
and every other notification fail. A separate trusted operator sink receives
only a validated fixed HTTPS verification URI, bounded user code, interval and
expiry. It must keep these out of routine logs, candidate input and reports.
The default sink discards events; an interactive caller must provide one.
Upstream errors, causes, response bodies and headers never enter results.
Outcomes are `authenticated`, `missing`, `cancelled`, `timeout`, `conflict`,
`storage_failure`, or `provider_failure`. Provider denial/expiry are deliberately
coarsened to provider_failure; the local deadline is timeout. Status contains
only providerId and authenticated/missing/expired/unavailable (invalid operation
options or pre-cancellation are unavailable). No account identity.

`resolve` returns an access token **only in memory** to the trusted caller,
after any rotation has persisted. No refresh-on-401 or general exchange/refresh
retry exists. Pinned device polling is unchanged: immediate first poll, minimum
one-second interval, pending responses repeat, slow_down adds five seconds;
the caller deadline and request caps additionally bound it. Cancellation and
deadline checks prevent late transport/provider completion from publishing.
The transport promise remains observed after cancellation/deadline: a late
Response has its body cancelled, without replaying the request. Rejected
responses are also cancelled when failure occurs before acquiring a reader.

CLI syntax (execute only when an operator explicitly wants live auth):

```text
node cli.mjs status ABS_STORE ABS_VERIFIED_RUNTIME ABS_CANDIDATE_ROOT
node cli.mjs logout ABS_STORE ABS_VERIFIED_RUNTIME ABS_CANDIDATE_ROOT
node cli.mjs login  ABS_STORE ABS_VERIFIED_RUNTIME ABS_CANDIDATE_ROOT OPERATOR_FD
```

Login requires a separate preopened operator FD >= 3; stdout is sanitized JSON.
There is no token-export verb. SIGINT, SIGTERM and IPC disconnect cancel work.
The library caller owns its process lifecycle and aborts on disconnect. Do not
use this CLI's login command as a test. Tests preload an offline transport deny
module before CLI imports. The CLI has no configuration discovery or defaults.

## Store and ordering

Supply an explicit absolute directory outside the repository and every candidate
root. The caller must enumerate candidate roots and attest harness ownership;
the API additionally excludes `.codex`, `.pi`, `.amp` and `.config` components.
The directory's immediate parent must already exist. All ancestor components
must be real directories, owned by this UID or root, without group/world write
except root-owned sticky temporary ancestors. The final directory must be owned
by this UID with 0700 permissions; newly created directories use 0700. Existing
unsafe paths fail without chmod/import. Symlink components are rejected, so on
macOS use canonical `/private/...` temporary paths instead of `/tmp` aliases.

The single-provider JSON format is version 1, an operation generation UUID and
an optional exact OAuth credential shape. The credential file is a regular,
single-link, same-UID 0600 file, opened with O_NOFOLLOW/O_NONBLOCK and bounded
to 64 KiB. Every read validates shape, strings and finite safe expiry. Corrupt,
oversized, unsafe and unknown-version states fail closed and are never treated
as missing or overwritten by login/logout. Atomic replacement uses an exclusive
0600 same-directory temporary file and rename, with cleanup on failure. No
fsync/power-loss durability claim is made.

An exclusive 0700 lock directory serializes processes. Wait is at most five
seconds and never beyond the operation deadline. Locks are never stolen and
uncertain writes are never replayed. A killed holder leaves an unavailable store.
Operator recovery requires first proving no holder remains, then inspecting the
store and deliberately removing the lock; automatic recovery is absent.

Login records a new generation under a short lock, polls without holding it,
then commits only if that generation is current. Logout changes the generation
even when already missing. A newer login invalidates older login completion.
Refresh rereads under the lock, rotates and persists before release. Concurrent
resolution sees the persisted token and does not refresh twice. Logout queued
during refresh follows that transaction and removes the credential; logout that
wins the lock first makes resolution missing. No Models nested lock is used.
The exposed CredentialStore implements read/list/modify/delete with Pi semantics:
`modify` returning undefined leaves the existing credential unchanged; delete
serializes against modify. Missing-state generation metadata remains after logout.

This relies on trusted same-UID code, stable trusted ancestors, and a trusted
runtime/transport/operator sink. It does not defend against arbitrary same-UID
host code swapping paths, extracting process memory or replacing runtime files.
Tokens are structurally validated, not cryptographically verified here.

## Reproduce offline

All commands run in an owned right/no-focus Herdr pane. `executor/guarded.py`
(which replaced `auth/run.py`) records exact commands/exits in
`auth/evidence/<attempt>`, supplies an empty HOME and minimal environment, runs
the command under the step36 guard with a 550-second deadline in its own process
group, kills descendants and records their absence. Each attempt name must be
new. Evidence is bounded to 16 MiB. No packages are added or fetched.

```sh
A=toolchain/harness/provider/auth
python3 toolchain/harness/executor/guarded.py 550 $A/evidence/setup-review --cwd $A --home $A/.cache/home-setup-review -- python3 setup.py ABS_PRIOR_PREPARED_COPY prepared-review
python3 toolchain/harness/executor/guarded.py 550 $A/evidence/auth-review --cwd $A --home $A/.cache/home-auth-review -- node test.mjs .cache/prepared-review/.cache/runtime $(cat $A/controls.txt)
python3 toolchain/harness/executor/guarded.py 550 $A/evidence/foundation-review --cwd $A/.cache/prepared-review --home $A/.cache/prepared-review/.cache/home -- node test.mjs evidence/auth-review.outbound.json
```

Setup copies only dependency material from an explicit existing prepared source,
not its home/config. It reconstructs the runtime in a fresh owned ignored copy,
verifies archive integrity/runtime hashes/dependency versions and compares five
generated records to tracked foundation records. It is an **offline fresh
preparation**, not a new registry download or dependency installation. The source
archive SHA-256 is `c2a574794f1fc26510729f2341c4c4990cfa385caf47b011bdca19afa3d22903`;
the 0.85.1 artifact SHA-256 is
`af7d11986179445ce6fe88b37d57de22f823c0ffd3a65cae31c555b7f5e99253`.
The artifact is not the source: 148/177 embedded source files match, 29 differ
or are absent. Auth sources match. Execution uses the exact prepared git source,
with the foundation's disclosed unrelated SSE observation patch; generated
catalog hydration remains as disclosed in the foundation README.

`controls.txt` fixes 28 names. Explicit subsets are supported; unknown, duplicate,
empty or >28 selections fail. Tests intercept global fetch and deny socket,
HTTP(S), TLS, DNS, datagram, WebSocket and listener entry points before importing
OAuth. Responses and tokens are synthetic; no listener is needed. Subprocess
tests use only private temporary stores, and CLI subprocesses additionally
preload `offline.mjs`. Raw evidence includes request path counts, observed
operation ordering, fixed control results and cleanup. Never put device events
or token-bearing test state into retained evidence. Failed attempts remain.

The unchanged foundation's 28 tests separately use their original loopback
fixture and egress-denial controls in the fresh copy. `scope.py` compares every
tracked foundation file against the exact base. Independent lead reruns and an
extra control remain the acceptance gate; these fixtures establish no live
OAuth capability or provider entitlement.

---
title: "Mo provider auth v1: private store and device login"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, verification, security]
sources: [plans/mo-first-coding-harness.md, plans/mo-provider-foundation.md]
status: ready
---

# Mo provider auth v1: private store and device login

## Orientation

Robert requires the harness to use its own subscription OAuth session. Under
his overnight authority, implement the operator auth component now and prove
it with synthetic credentials and the actual pinned OAuth implementation.
No live login, token refresh, credential discovery or inference runs in this
slice. Interactive login can start when Robert returns. Registration support,
account entitlement and live acceptance remain separate unresolved facts.

The accepted [[mo-provider-foundation]] accepts an already resolved access
token. This component supplies a private persistence and login boundary; it
does not execute tools or extend Mo's integer usage contract. Bridge design
review is retained at `audit/evidence/2026-09-19/provider-bridge-readiness/`.
Its source facts inform this narrower brief; recommendations are not acceptance.

## Ownership and fixed dependency

One fresh GPT-6-Astra worker, low reasoning, separate exact-base worktree, no
nested agents. Own only new `toolchain/harness/provider/auth/`, including its
README, tests, runner and evidence. No edits to foundation files, package lock,
Pi patch, compiler, Agent, executor, wiki or historical evidence. No new packages.
Commit with actual GPT-6-Astra author/committer; no worker push or rebase.

Use the same exact Pi source pin and recorded runtime preparation as the
foundation. An explicit verified runtime directory may be supplied by trusted
caller/test setup. Do not fetch a new auth library or load ambient Pi/Codex/Amp
configuration. Keep the source/artifact mismatch disclosure. Cold setup and
new outputs belong in fresh owned ignored copies, never historical directories.

All tests, Node processes and fixture servers run under numeric guards in an
owned right/no-focus Herdr pane, with child process-group cleanup. Do not use
the dedicated executor machine or shared Mac Docker for this slice.

## Operator contract

Provide explicit login, status, logout and in-memory request-auth resolution.
The CLI exposes login/status/logout only; no token-export command or secret
stdout. A typed/library API may pass the resolved token directly to a trusted
caller in memory after successful persistence. No inference or automatic
refresh-on-401 is introduced. Status lists only provider ID and authenticated,
missing, expired or unavailable state; omit account identity and token fields.

Use the pinned provider's OAuth descriptor: `login`, `refresh`, `toAuth` and,
where useful, Models' existing locked refresh resolution. Choose only the
`device_code` select option. Reject any other prompt; never start browser
callback servers, launch a browser or read pasted authorization codes.

Only a separate operator event sink may receive validated device URI, user
code, polling interval and expiry. Match the fixed HTTPS verification URI from
the pin, bound all strings/numbers, and exclude these events from routine logs,
reports, exception output and candidate channels. Do not forward raw upstream
events. Outcomes use a small documented allowlist such as authenticated,
missing, cancelled, timeout, conflict, storage_failure and provider_failure.
Never serialize upstream exception text, causes, response bodies or headers.

## Private store and ordering

Require an explicit absolute harness-owned store directory, outside this repo,
candidate roots and existing provider credential stores. Tests use private
temporary directories and synthetic values. Create new directories/files with
0700/0600, verify ownership/type/mode, reject symlinks and non-regular credential
files, reject hardlinked files and unsafe parent components. Never silently
chmod or import an existing foreign store. Document the trusted same-UID and
ancestor assumptions; this is not protection from arbitrary host code.

Bound the single-provider versioned JSON store to 64 KiB. Validate all persisted
fields before returning credentials. Missing is distinct from malformed,
oversized, unsafe or unsupported-version state; corruption does not trigger a
fresh login or overwrite. Replace through a private same-directory temporary
file and atomic rename. Persistence failure must prevent successful login or
release of newly refreshed credentials. No power-loss durability claim.

Implement the exact CredentialStore semantics: modify(undefined) means leave
unchanged, not delete; delete is serialized against modify. Serialize across
processes using an exclusive private lock with a finite wait. Do not steal an
apparently stale lock or replay an uncertain write. A killed holder can leave
an explicit unavailable store requiring operator recovery; document that limit.

Login must not hold a long-lived store lock during human/device polling. Record
an operation generation under lock before polling, and commit only if still
current. Logout invalidates pending login even when no credential exists.
Concurrent/newer login must not let an older result resurrect or replace it.
Refresh rechecks the current credential while locked, persists rotation before
release and respects a concurrent logout. A late result after cancellation or
deadline cannot publish credentials. Test actual overlapping operations, not
only a sequential model. Avoid nested lock acquisition through Models.

## Network and time bounds

Pinned OAuth calls global fetch. Confine its bounded transport wrapper to a
dedicated auth process, or an equivalently exclusive documented boundary; it
must not race with inference/global transport consumers. Accept only POST to
the pin's three exact auth.openai.com paths: `/api/accounts/deviceauth/usercode`,
`/api/accounts/deviceauth/token`, `/oauth/token`. Reject redirects, other methods,
alternate origins and unexpected URLs before egress. No ambient auth context.

Use an explicit finite operation deadline, at most 900 seconds for login and
30 seconds for resolution/logout. Cap each HTTP request/body at 10 seconds and
64 KiB while streaming; store lock wait at most 5 seconds within the caller's
remaining deadline. Stop/disconnect aborts requests and suppresses late success.
Device polling prescribed by the pinned flow is allowed within the deadline;
do not add general retries for exchange or refresh. Document exact behavior.

Offline tests intercept global fetch and deny other network entry points before
loading/running OAuth. Use the actual pinned device/exchange/refresh functions,
synthetic token claims and deterministic fixtures. Prove unexpected egress is
rejected, fixtures close, and no real store/environment credential is read.

## Done when

At most 28 named auth controls per attempt, guard 600 seconds, retained evidence
at most 16 MiB. Select the concrete fixed names before the final run; reject
unknown or empty selections. Keep failed attempts and exact commands/exits.

Cover device success/polling/denial/expiry, abort before and during transport,
oversized response and store, malformed credential, unexpected prompt/URL/
redirect/method, valid and expired resolution, single refresh under concurrent
callers, modify-unchanged, logout, overlapping login/logout and newer login,
late success suppression, cross-process lock contention, killed lock holder,
atomic replacement failure, unsafe directory/file/link/mode, unknown version,
secret canaries and sanitized CLI output. Group related variants clearly.

Run unchanged 28-case provider foundation tests from a fresh prepared copy;
compare tracked foundation files before/after. Prove source pin/runtime identity
and retain actual network request counts, operation ordering and cleanup. Lead
reviews the immutable patch and independently repeats tests plus an extra
control before acceptance. Green fixtures do not establish live OAuth support.

## Related

- [[mo-provider-foundation]]
- [[mo-first-coding-harness]]
- [[mo-coding-fixture-v1]]
- [[decision-log]]

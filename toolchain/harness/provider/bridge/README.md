# Offline native-history bridge

Operator-provisioned, one-run HTTP adapter around the unchanged pinned provider
`turn`. No tool execution, credential lookup, refresh, retry, login or live
inference occurs in its controls. The trusted operator supplies an access token
in memory, a fetch-compatible transport, run ID, goal, ordered grants, absolute
journal path and port zero. The listener binds only `127.0.0.1` on an ephemeral
port. Loopback and `x-run` are not client authentication.

```js
import { startBridge } from './bridge/server.mjs';
const bridge = await startBridge({
  runId: 'r_1', goal, grants, journalPath,
  accessToken, fetch: trustedTransport, port: 0,
});
// Configure the trusted Mo fixture with bridge.port. Mo retries must be zero.
// Later:
await bridge.stop();
```

Run this from a prepared provider copy; `server.mjs` imports its parent's actual
`turn.mjs`. The provisioning caller and journal parent directory are trusted.
The parent must exist, be owned by the current user, have no group/other mode
bits, and have no symlink ancestors. Existing files, symlinks and malformed or
empty old journals refuse startup. A fresh UUID namespaces each process, even
when the legacy run ID is `r_1`. No restart/resume/reset/replay API exists.

## Wire and history

Only POST `/complete`, JSON content type, exactly one matching `x-run`, and exact
`{goal,tools,transcript}` fields are accepted. Responses retain Mo's
`{tool,args,tokens}` or `{done,tokens}` shape and include Content-Length.
Fixed schemas require every argument as a string, without extras or coercion.
The six possible grants are list_files, read_file, search, write_file, exact_edit
and command; ordering is frozen and duplicates/unknown grants reject provisioning.

The first transcript is empty. Each continuation must preserve its complete
accepted prefix at JSON value level and add exactly the offered model step and
matching tool step, with consecutive numbers and validated fields. Object key
order is immaterial; strings, including model result JSON text in an already
accepted prefix, are exact. The new model result must decode to the offered
projection. Model tokens must equal the reported total and tool tokens be zero.

Complete native assistant messages remain unchanged, with their composite IDs,
text/reasoning signatures and metadata. A native tool result uses the original
full toolCallId and the exact recorded result string. Structured command/edit
state and execution determine errors and terminal outcomes; literal words in
stdout never do. Legacy tools use the recorded refusal flag.

The trusted Run sends continuation only after Book acknowledgment. This validates
that transcript; it does not prove a disk write against a forged caller. The Mo
control independently reads Book from disk. Final state is `final-offered`, not
Book-recorded. No cached actionable reply is returned on a duplicate. Concurrent,
stale, conflicting or duplicate requests terminalize ambiguity, abort active
inference and suppress its late action.

## Journal and bounds

The private journal contains version/session/run, fixed config/source/catalog/
schema/bridge hashes, accepted prefix, native history, offered projection and
per-call usage/outcome. No access token, authorization headers or raw provider
errors are recorded. Successful native text is private task data. Do not print
journals by default.

Continuation is persisted before the next intent; intent before the provider;
native result/projection before HTTP reply. One serialized writer uses private
same-directory temporary files and atomic snapshot replacement. There is **no
crash-durability claim**. Failure stops dispatch. If a terminal write fails, the
old journal/intent remains a non-resumable tombstone. Closing cannot guarantee a
persisted terminal label on a broken filesystem. A transport abort cannot prove
upstream cancellation or executor cleanup. HTTP write completion cannot prove
client receipt; any duplicate after a lost reply is rejected without replay.

Limits: one active request, 16 recorded steps, 4096 accumulated reported tokens,
30 seconds, 64 KiB encoded request/reply/native context, 2 MiB journal. Body,
provider and reply waits are each at most two seconds under session remaining;
journal/closing work has a separate finite 15-second grace. No compaction or
silent truncation. A valid call may overshoot the token cap; it prevents the next
call, not billing. Unknown/incomplete/unsafe usage fails with sanitized 422 before
an action is exposed; reported zero is valid. Provider 401 remains 401, terminal,
with no refresh. Other provider errors terminalize as well.

## Reproduce

From the worktree root in an owned right/no-focus Herdr run pane:

```sh
python3 toolchain/bench/step36/guard.py 600 -- python3 toolchain/harness/provider/bridge/run.py review-01 independent
python3 toolchain/bench/step36/guard.py 600 -- python3 toolchain/harness/provider/bridge/run.py review-foundation foundation
python3 toolchain/bench/step36/guard.py 600 -- python3 toolchain/harness/provider/bridge/run.py review-mo mo
```

Every attempt name must be new. `run.py` copies the explicitly approved prepared
provider source into owned ignored `.cache/<attempt>`; it verifies unchanged
foundation bytes and all 220 pinned runtime hashes. No package install occurs.
The actual pinned parser receives synthetic HTTP/SSE only. External fetch,
WebSocket, HTTP/TLS/DNS and socket entry points are denied before provider import;
only explicit fixture loopback ports are allowed. This is a test-process egress
control, not a host sandbox. Child Mo sees only the fixed loopback fixture config.

There are 28 fixed named bridge controls: `independent` selects 27; `mo` is the
reserved two-runtime end-to-end control, explicitly released by the lead on
19 September 2026 after accepted source commit
`e6f04ce6358c85f22a86f26be0b5b388495fcc6e`. Comma-separated known names select a
subset. Any valid selection containing `mo` (for example `final,mo`) prepares
the released source/compiler and runs the whole requested selection through
`executor/guarded.py`, the one runner every selection uses (empty home, minimal
PATH with node, npm and zig). `foundation` remains a separate regression command.
The usage control is named `unknown-usage`; literal `unknown` is invalid.
Empty, duplicate and unknown selections fail before dependency copying or Node
startup, with zero cases/provider calls. `controls.json` is the shared fixed registry. The separately unchanged
foundation test has 28 cases. The Mo runner archives only exact accepted examples,
copies/hashes the approved compiler, and builds its own native CLI. It never
writes main or another worker tree. Compiler runtime is embedded; Zig is the
approved `/opt/homebrew/bin/zig` (0.16.0).

Each attempt retains commands, actual exits, source hashes, request order/counts
and sanitized synthetic observations below `evidence/`; failed attempts remain.
Numeric guards cap each attempt at 600 seconds, with shorter child/group limits.
Owned groups are killed after completion. All listeners and sockets are closed.
Evidence is capped at 16 MiB per attempt; the final report gives the total.

Pin/source: Pi `36b60d2e8985899743c4cf5bd5f8929832a3f05d`, exact TypeScript
through Node type stripping with the unchanged observational patch. The registry
artifact is not that source: 148/177 embedded sources match, 29 differ/are absent.
The artifact only supplies dependency/generated hydration inputs; selected Astra
catalog is pinned-source-derived. Catalog hash and Node/compiler identity are in
attempt receipts. No reproducible-build, live provider, auth, containment,
application-repair or language-value acceptance follows. Lead review is separate.

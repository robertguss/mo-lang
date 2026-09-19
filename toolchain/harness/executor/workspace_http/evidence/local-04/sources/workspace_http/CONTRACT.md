# mo-workspace-http-v1

One trusted operator starts one run, on an ephemeral `127.0.0.1` TCP port.
Readiness follows successful remote creation. `Bridge` is an operator Python
API, never an HTTP lifecycle route. The operator supplies source bytes, selection,
result directory and protected verifier before start. No model credentials,
provider, candidate local execution, filesystem fallback, retry, replay or resume.

Candidate requests are HTTP/1.1 POST `/tool`, without query or fragment. Required
headers, each occurring exactly once: `Host: 127.0.0.1:<port>`,
`Content-Type: application/json`, `Content-Length: <canonical positive decimal>`,
`X-Mo-Workspace-Token: <private 64 hex token>`. Optional `Connection: close`.
All other headers (including Origin and Transfer-Encoding) are refused. Header
section at most 16384 bytes and 32 fields, body at most 851968 bytes. Four live
connections, backlog four, one operation admitted, no work queue. Incomplete
requests and response writes have an absolute two-second deadline. Connections
always close after a single response; no pipelining or CORS.

JSON uses strict UTF-8, no duplicate keys, nonfinite numbers, unpaired surrogates,
extra keys or numeric booleans. Exact top-level keys are `version`, `run_id`,
`workspace_id`, `call_id`, `operation`, `args`. Version is the title string.
Run/call IDs match ASCII `[A-Za-z0-9_-]{1,64}`; workspace ID is operator-issued
32 lowercase hex. The external run/workspace binding is checked before claim.
Every accepted call gets a distinct generated core 32-hex call ID. Duplicate or
conflicting external call IDs are refused, never replayed.

| Operation | Required args | Optional args | Result |
|---|---|---|---|
| list_files | none | path (`.` default) | items, truncated |
| read_file | path | none | text, truncated |
| search | query | path (`.` default) | items (path, byte offset), truncated |
| write_file | path, text | none | written, truncated |
| exact_edit | path, old_text, new_text | none | edited, truncated |
| command | command, timeout_ms | none | described below |

All args are strings except integer timeout_ms (500..120000). Core file/path
limits and containment remain authoritative, including the 65280-byte controller
JSON cap. A 64 KiB file is not guaranteed readable as escaped JSON. Search maps
query to core text; exact_edit maps old_text/new_text to old/new. File calls use
Workspace.call, retaining refusal execution metadata. Truncation is outer OR
nested truncation, not an invented success.

Every response has exactly `version`, `run_id`, `workspace_id`, `call_id`,
`accepted`, `state`, `execution`, `error`, `result`. Identities are null until
complete schema/binding validation. Accepted is Boolean. State is success,
refusal, failure, timeout or cancellation. Execution is not_started, completed
or unknown; every actual combination is retained, including timeout/completed
and refusal/completed. Error is null or a stable code below. Result is null or
the operation object. HTTP200 contains admitted outcomes; HTTP504 indicates an
admitted response wait expired, with execution unknown. HTTP400 malformed,
401 unauthorized,403 unbound,404 path,405 method,409 conflict/admission refusal,
413 oversized,415 media type. Pre-admission refusals have accepted=false and
execution=not_started. Explicit Content-Length, maximum response body 524288,
and Connection: close occur on every response.

Command results contain nullable actual exit_code/signal, nullable strict UTF-8
stdout/stderr, encoding=`utf-8`, execution_valid, truncated and nullable elapsed_ms
(floor seconds*1000). Invalid base64 or UTF-8 produces failure/output_encoding,
null text, and retains execution/exit/signal. Original bytes/results stay private.
No traceback, host path, manifest, ownership receipt or supervisor observation
crosses HTTP. Stable core error codes are allowlisted:

`invalid_path invalid_utf8 oversized unsupported_entry unsupported_mode empty_old
multiple_matches missing_match snapshot_mode too_many_entries quota empty_search
invalid_import path_conflict deadline cleanup_required quarantined closed
result_too_large filesystem_refusal controller_failure request_refused
transport_unknown recovery_closed duplicate_call`.

Bridge errors: `malformed unauthorized unbound not_found method unsupported_media
conflict busy admission_closed call_limit journal_full response_timeout
owner_unknown output_encoding invalid_result response_too_large`.
Unknown core error text becomes controller_failure.

Fixed limits: 16 admitted calls, 900-second monotonic admission lease from
readiness, two-second file response wait, 300-second command response wait.
Candidate command time is clamped to remaining lease; under 500ms is refused
before effects. Response waits also use remaining lease, without resetting it.
Expiry closes admission and requests cleanup; it is not a 900s cleanup guarantee.
Registration can establish a later candidate deadline: this lease is admission
expiry, not an absolute execution cutoff. A serialized owner blocked in a call
cannot clean concurrently; cleanup stays unresolved until the call returns and
positive cleanup proof is obtained.
Cleanup has a separate 60s configured attempt budget. Core locks/local I/O/launch
prevent an unconditional synchronous wall bound; remote runtime reapers remain
independent.

The owner subprocess alone constructs and uses Workspace. It journals private
0700 directories/0600 state, receipt path and generated IDs before create's
first effect, and payload hash/core call mapping/intent before each dispatch.
A 4MiB atomic-replacement journal reserves worst-case response and metadata space
before dispatch. No fsync/crash durability claim. Raw core evidence is separate.
Successful socket write does not prove client receipt. Observed disconnect or
response timeout closes admission, records delivery unknown separately from the
original outcome, and closes IPC; the owner finishes the operation and cleanup.
Frontend death similarly delivers IPC EOF; owner death cannot confirm cleanup.
An explicit operator recovery call requires proved child death and invokes only
the accepted constructor-free recovery API. It never retries work or steals a
live lock. Lost execution remains unknown even when cleanup is confirmed.

Operator freeze closes admission before serialized freeze; verify uses only the
preconfigured protected verifier. Close closes admission and IPC, waits a bounded
interval and reports whether the owner exited; a live stalled owner remains
responsible. Explicit stop may signal only the retained owned child handle,
then cleanup-only recovery. No automatic restart/adoption or general PID kills.
A whole operator-process death loses that live handle; an external operator must
prove owner death before using the retained receipt with the accepted recovery
API. All private operator state must be retained.

IPC closes unused socket duplicates immediately after subprocess launch. Owner
results are persisted after effects and before bounded (2s) notification. Cleanup
never waits for a frontend acknowledgment. Terminal admission remains closed
regardless of any late result. No final wire receipt is treated as client ACK.

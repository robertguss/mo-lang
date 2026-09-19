# Lead partial adapter review

Exact worker commit0a74a0fc3a679eb98dd1c31892a32e6b41b3cbdb, base030290b8.
Source copy/hash is in adapter-snapshot-01.json. This is source review of raw
JSON/configuration/request construction, not independent execution or acceptance.
A separate fresh Astra/low reviewer covers wire results and continuation.

The quote/escape scanner at24-45 correctly consumes one escaped byte and handles
even backslash runs. After successful grammar decode, outside-string colons
count original object members; recursive counting at47-54 visits all objects and
arrays. Duplicate collapse necessarily loses at least one member, and discarded
subtrees only increase the deficit. The equality check at56-64 therefore rejects
duplicates without reproducing the JSON parser. No counterexample found.

Numeric state marks decimal/exponent spellings invalid only while in a numeric
token; quoted spellings and boolean `e` stay valid. Grammar decoding still rejects
bad token syntax, numeric overflow and unpaired surrogate escapes. Field-specific
to_i64/ranges remain necessary because decoded JSON numbers are Float64.

Configuration validates the five exact keys, version, integer port1..65535,
ASCII run ID and exact lowercase hex workspace/token lengths under4096 bytes.
It does not read the file or prove private provisioning; that belongs to the
unfinished application layer and must be checked separately. The token is used
only in the private request header here, not in the constructed request body.

Request construction at127-151 denies absent grants, unknown/extra arguments
and bad call IDs. Tool args are already Map(String,String); command timeout
comes from the trusted deadline, never model args. All requests target fixed
loopback/port and enforce the encoded851968-byte cap. Http.send is called once,
with the same decreasing deadline capped at2s/300s. Transport errors keep unknown
execution. No retry or local filesystem fallback is present in this module.

The six tests cover pure parsing/configuration/shape/terminal helpers, not an
actual workspace_used HTTP call. Real framing, response mapping and deadline
clamping remain owed. In particular, candidate timeout is sampled before request
encoding; the near-expiry matrix must cover work spent preparing a large request,
not merely a small call starting below500ms. This is a requested boundary check,
not a measured dispatch-after-deadline finding.

The aggregate ID diff adds exactly one new Agent.WorkspaceAdapter record;
existing records are untouched. Actual recorded six-test verification and native
build/test receipts are worker evidence. Full dependency closure, formatter,
Book/watcher/report semantics and integrated runtime checks remain outstanding.

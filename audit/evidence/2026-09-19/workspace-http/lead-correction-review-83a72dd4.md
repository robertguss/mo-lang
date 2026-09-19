# Lead correction review, 19 Sep 2026

Reviewed immutable83a72dd4 against75680f31. Exact20-file snapshots and SHA256
manifests are retained in source-review-01.json/source-review-02.json. No
product source edits. This review is not acceptance.

The two independent actual-loopback/subprocess-double drain cases fail on75680
and pass on83a72 with identical probe SHA256
1526ee35f4d5218157b5d19ebe577ab2739914ff29ed4c189e12d3baa77f3319.
Old first complete response is200/success, then the listener refuses a later
connection; a second active command instead receives200/owner_unknown. Both
record response_write_unknown and closed admission. Corrected2/2 remains open
with successful second responses. drain-red-03 exit1/group90137 absent;
drain-green-01 exit0/group90291 absent. Both source snapshots remain unchanged.

Retain drain-red-01 as lead setup assertion error (wrong argv module string),
not product RED. drain-red-02 reproduces closed listener but uncaught expected
ConnectionRefusedError prevented the second case and row report. Original
probe/wrapper bytes and raw exits are retained per attempt.

Source review agrees that successful write/drain now share an absolute two-second
allowance and disposal cannot revoke later admission. The55s delete maximum
leaves core transport5s within the configured60s cleanup allowance; collection
consumes the same remaining allowance. This is not a finite wall guarantee
across inherited locks/I/O. Worker numeric actual-controller evidence rejects
60.05s and accepts55s before the expected absent-workspace refusal; no clock-skew
cause is claimed for the earlier application failure.

## Remaining concrete finding: fragmented IPC resets response wait

owner.receive.exact repeatedly calls recv with the same socket timeout. A valid
reply sent as header+one byte, then three chunks0.8s apart, returns200/success
at2.413118s for a configured2s file wait and leaves admission open. The frontend
also lacks a final absolute-deadline check after receive completes. Retained
ipc-deadline-red-01 exit1/group91501 absent; exact source unchanged. This is a
local real-socketpair dispatch seam, no Workspace/machine effect. The normative
probe requires504/unknown/closed by the2s deadline with0.3s scheduling tolerance.

The worker is assigned an absolute remaining deadline across IPC header/body
reads and a late-result check, with fragmented-valid/incomplete controls in the
existing deadlines group. Preserve83a72 and all evidence. No edits during the
currently running full compiler suite; correction follows afterward. Machine
work ended with worker positive inventory/readiness and explicit release.

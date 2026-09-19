# Same-checkpoint command correlations

Read-only native Astra/low review, same session 01a0b94c-c2c7-7172-a674-4939c14c3adf. No experiments.

Both are concrete producer-backed validation gaps at `0a74a0fc`, with one qualification about signals.

**A — Mixed null/string streams are impossible in the accepted projection.**

For a non-null command result, the exact constraint is:

- Both streams are strings; or
- Both are null, with `state="failure"` and `error="output_encoding"`.

`protocol.py:107` initializes both to null. Line 117 evaluates the entire decoding list before assigning either field; an exception leaves both null and lines 118–119 set failure/output_encoding. There is no legitimate partial-string case.

Counterexample: operation `command`, HTTP **200**, matching configured identities:
```json
{"version":"mo-workspace-http-v1","run_id":"r","workspace_id":"0123456789abcdef0123456789abcdef","call_id":"1","accepted":true,"state":"failure","execution":"completed","error":"output_encoding","result":{"exit_code":0,"signal":null,"stdout":"","stderr":null,"encoding":"utf-8","execution_valid":true,"truncated":false,"elapsed_ms":0}}
```
Adapter line 199 accepts it, and `checked` preserves it. It **does stop** at line 247 because of output_encoding: wrongly accepted, not wrongly continued. Swapping stdout/stderr has the same defect.

**B — Success with exit code 1 is impossible; “no signal” is not an explicit success condition here.**

`workspace.py:40–46` assigns success only when valid, not cancelled, not timed out, observation status completed, **exit_code == 0**, and **not truncated**. Lines 49 and 55 then yield completed/execution_valid=true. `protocol.project` cannot promote failure to success.

Counterexample: operation `command`, HTTP **200**, matching identities:
```json
{"version":"mo-workspace-http-v1","run_id":"r","workspace_id":"0123456789abcdef0123456789abcdef","call_id":"1","accepted":true,"state":"success","execution":"completed","error":null,"result":{"exit_code":1,"signal":null,"stdout":"","stderr":"","encoding":"utf-8","execution_valid":true,"truncated":false,"elapsed_ms":0}}
```
Adapter lines 199 and 228 accept it; lines 245–256 permit continuation. This contradicts the actual success producer.

The producer copies `signal` at `workspace.py:50` without checking it in the success predicate. Therefore **exit zero and untruncated are established constraints; signal-null is not established by this producer** and should not be bundled into this finding without separate upstream evidence.

Source review only; no tests or edits. Idle for closure.

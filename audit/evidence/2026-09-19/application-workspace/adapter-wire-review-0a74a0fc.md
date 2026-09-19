# Immutable adapter wire review

Native GPT-6-Astra low, Herdr w4:p2H, session 01a0b94c-c2c7-7172-a674-4939c14c3adf.

SHA-256 verified. Three source-derived findings at checkpoint `0a74a0fc`; no execution performed.

1. **Legitimate pre-admission refusal becomes unknown execution.** Adapter line 214 requires non-null matching identities, rejecting documented null identities.

   Call: `read_file({"path":"a"})`; HTTP **401**:
   ```json
   {"version":"mo-workspace-http-v1","run_id":null,"workspace_id":null,"call_id":null,"accepted":false,"state":"refusal","execution":"not_started","error":"unauthorized","result":null}
   ```
   `checked` returns `invalid_response/unknown`, losing the legitimate `not_started` fact. Sources: `CONTRACT.md:43–53`, `protocol.py:91–93`, `bridge.py:250–259`. Stopping may be appropriate; misclassifying execution is the defect.

2. **Invalid HTTP status is accepted and continuation permitted.** Adapter lines 223–225 constrain status only for accepted responses and HTTP504.

   Call: `read_file({"path":"a"})`; HTTP **500**, matching configuration identities:
   ```json
   {"version":"mo-workspace-http-v1","run_id":"r","workspace_id":"0123456789abcdef0123456789abcdef","call_id":"1","accepted":false,"state":"refusal","execution":"not_started","error":"busy","result":null}
   ```
   `checked` preserves this body; `workspace_terminal?` returns false. The documented and implemented busy response is **409**, not 500 (`CONTRACT.md:49–53`, `bridge.py:196–198`). This is a documented status-contract violation.

3. **Successful command with missing output is accepted and continued.** Adapter line 199 independently permits null streams; lines 228 and 245–253 never reconcile them with success.

   Call: `command({"command":"true"})`; HTTP **200**, matching identities:
   ```json
   {"version":"mo-workspace-http-v1","run_id":"r","workspace_id":"0123456789abcdef0123456789abcdef","call_id":"1","accepted":true,"state":"success","execution":"completed","error":null,"result":{"exit_code":0,"signal":null,"stdout":null,"stderr":null,"encoding":"utf-8","execution_valid":true,"truncated":false,"elapsed_ms":0}}
   ```
   Both validation and continuation pass. The accepted projector produces strings after successful decoding; null streams instead accompany `failure/output_encoding` (`protocol.py:105–119`; `CONTRACT.md:56–59`). This finding concerns that producer invariant—not a blanket prohibition on nullable streams.

Coverage: operation field mappings match the accepted protocol. Completed refusals with null results, timeout/completed, nonzero command feedback, and legitimate output-encoding outcomes are accommodated. No stronger universal state/execution matrix is asserted.

Excluded raw JSON/counting/config, dispatch bounds, mutable integration, tests/builds, network, and agents. Review complete; idle for lead closure.

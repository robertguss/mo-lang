# Independent frontend/projection review

GPT-6-Astra low, read-only Herdr worker p2B; immutable source75680f31.
Session 01a0b8d9-ce94-7f01-bdf9-29f7bf5029a9. Initial lack of file tools was resolved by explicit
local read-only command permission; no machine/test/build commands or edits.

Found two concrete defects in `bridge.py`. No additional reachable defect found in `protocol.py` against the inspected core producers.

Reviewed source `75680f31a03423d2990efaaf85fd84251f816a4a`; all eight files read matched their recorded size and SHA-256 in `SOURCE.json`.

1. **P2 — Post-response drain timeout incorrectly terminates the workspace.**  
   `Bridge._serve`, [bridge.py:249](/private/tmp/mo-workspace-http-review-75680f31/toolchain/harness/executor/workspace_http/bridge.py:249), lines **249–267**.

   After successfully writing an admitted response and half-closing its write side, the bridge waits for the client to close its sending side. A client can read the complete response but leave that side open for more than two seconds. The drain’s `recv()` then raises `socket.timeout`, caught as `OSError`; line 267 calls `_end('response_write_unknown')`, permanently closing admission and IPC.

   This requires neither failed response delivery nor an observed disconnect. It also can terminate a subsequent operation, because `_dispatch` has already released the admission lock before this drain runs. The drain additionally starts a fresh two-second allowance, contradicting the comment that it shares the write/close allowance.

   **Minimal correction:** Separate response-write failures from bounded drain expiry. Treat drain expiry as completion of connection disposal, without `_end`; calculate one absolute write/close deadline before `sendall`.

   **Focused control:** Read a successful response, retain the client’s sending side beyond the drain deadline, and verify that a new call remains admissible. Include a second call active when the first drain expires.

2. **P2 — Response-wait expiry can produce HTTP200 `owner_unknown` instead of HTTP504 `response_timeout`.**  
   `Bridge._dispatch`, [bridge.py:209](/private/tmp/mo-workspace-http-review-75680f31/toolchain/harness/executor/workspace_http/bridge.py:209), lines **209–232**; competing lease closure in `Bridge._accept`, lines **112–114**.

   Only the explicit deadline check at lines 213–215 produces the contracted timeout response. A socket timeout during IPC send/receive instead enters the broad `OSError` handler and returns HTTP200, `failure/unknown`, `owner_unknown`.

   Lease expiry exposes a second concrete path: while an admitted call is waiting, `_accept` can reach the shared lease deadline first and close IPC through `_end`. The waiting dispatch then encounters EOF/socket failure and takes the same HTTP200 branch, although its lease-capped response wait has expired.

   **Minimal correction:** Handle IPC timeout explicitly and distinguish deadline-triggered IPC closure from premature owner failure. Return the contracted HTTP504 timeout envelope when the admitted response deadline expires, while preserving terminal admission closure.

   **Focused control:** Hold a valid IPC response incomplete across the response deadline; separately expire the admission lease during an outstanding call. Both should return HTTP504 `response_timeout`, retain execution `unknown`, and reject subsequent admission.

No additional framing/authentication/identity or DTO-truthfulness defect was established. These are source findings, not runtime reproductions. No tests, builds, remote operations, edits, or nested agents ran. `owner.py` remained outside this review; owner journaling, cleanup, and real-machine evidence remain for the lead’s assessment.

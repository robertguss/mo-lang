# Lead owner/API review of75680f31

GPT-6-Astra lead. Immutable source snapshot/source-review-01.json verified20
files copied from the exact commit; no changing worker source used for review.
This reading supports bounded isolated runtime test release, not acceptance.

owner.py persists known receipt/core run before constructing Workspace, then
actual workspace/create call identity before remote create. Claims include
payload hash and generated call ID before dispatch; bounded projected outcomes
persist before2s notification. The single child serializes Workspace, checks
lease/call/journal admission, maps file args through existing call and commands
through existing command, and performs collect/delete in finally after EOF or
unknown outcome. Cleanup confirmation requires accepted delete returning true;
original execution stays unknown. Core lifetime owner lock prevents concurrent
constructor-free recovery; explicit recovery must wait for proved child death.

The source does not establish an absolute900s execution/cleanup cutoff and the
contract now says so. A blocked call delays serialized cleanup. Raw core results
remain private; reserved journal space precedes each tool effect. No core policy,
image or installed-input changes are part of this wrapper. Local double controls
are not real machine proof. Frontend/projection review is separately delegated
against this exact snapshot; findings remain actionable before final acceptance.

Required real proof remains: all six tools, frontend/owner death while an actual
candidate runs, response loss and unknown cleanup, protected snapshot canaries,
positive inventory/shared5, inherited regressions and later full compiler suite.
Fresh preflight-01 confirms active exact parents/limits/pins and no workload.

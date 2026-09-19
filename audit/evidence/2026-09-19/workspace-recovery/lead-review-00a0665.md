# Corrected recovery source review and pending acceptance

Reviewed immutable `08525c614b32b71b4f6101ecc93eb6e8f6d68797` to
`00a0665790a1692c1b529b7b676cdcfa1a94990f`, plus inventory-only
`c2ea7cf76bd2e42e4f20b4723d3b6f61c7fa769a`. This is source review, not
integrated acceptance. Product source is frozen at 00a06657.

The lead reviewed the full existing-module changes and corrected machine
recovery path. A pre-root machine ownership record covers interrupted create;
authoritative not-started reservation state, the terminal registration barrier
and fresh runtime absence cover pre-transport and partial bootstrap. Ordinary
delete now retains completed proofs. Missing completed IDs are refused before
terminal creation or workspace mutation. These close the five lifecycle gaps
recorded in the initial review without replaying work or adopting old ownership.

The fresh Astra low reviewer independently checked proof flags, response schema
and negative controls. Its exact report is `correction-review-00a0665.md`.
Both previous validation defects are closed by inspection. Its remaining test
coverage observation motivates the lead's multi-execution response controls;
it is not a demonstrated implementation defect.

At 03:43 ET, worker receipts report corrected local59 and recovery16 green.
Final broad verification is still incomplete:

- `regressions-final-01` failed workspace19/22. First snapshot JSON parsing
  failed at position zero; inherited successful transport output was not saved,
  so neither empty bytes nor a transient cause is established. Subsequent
  occupied-registration failures and collect on absent execution storage caused
  inherited machine-stop fallback and several reboots. The worker retains the
  timeline and raw journal evidence. No later regression in that wrapper ran.
- Full build passed; `full-test-01` failed242/243,3/5 on unchanged corpus.zig's
  fatal-alert/reset ordering: expected Handshake,Closed,Handshake,Closed,Handshake;
  observed Handshake,Closed,Handshake,Handshake,Closed. This differs from the
  earlier lead application suite's extra TCP accept. No compiler fix or root
  cause is claimed.

Lead authorized exact recorded-resource operator cleanup after positive runtime
absence, preserving unresolved API results where reboot erased started-execution
proof. This is outside the cleanup API's whole-machine recovery claim. Next:
raw transport probes, sequential fresh regressions, then a separate full suite.
No images, installed toolchains, slice limits or product behavior may be changed
to make those checks pass.

Prepared lead `accept.py`, `inventory.py`, `lead-controls.py` and
`schema-controls.py` are not yet executed. They require exact integrated worker
source and exclusive machine release. The extra live control loses the response
after real cleanup, then explicitly repeats recovery with unchanged ownership
and no execution replay. The schema controls use three execution IDs and cover
ordered completion, valid partial cleanup, foreign/duplicate IDs and conflicting
statuses. All acceptance remains pending.

At 03:48 ET, the observed workspace rerun exposed a distinct provisioning
failure: its first command returned infrastructure_failure with
`RuntimeError('missing slice control group')`. The post-reboot probe accepted
inactive/absent slices as cleanup evidence but incorrectly allowed that state
to pass the execution readiness gate. The lead authorized starting only the
existing unchanged mo-executor.slice and mo-application.slice after exact owned
cleanup. Active exact cgroups, effective limits, empty task sets, pinned inputs
and unit hashes must pass before dispatch. No product auto-provisioning change
is authorized. Lead acceptance now has the same read-only preflight. This does
not establish the cause of the first malformed transport response.

# Runtime interruption during corrected-source regression

All times ET, 19 September 2026. Product source is `00a06657`; harness inventory
extension is `c2ea7cf7`. `regressions-final-01` failed workspace22 at 19/22; later
regressions were not dispatched by the sequential wrapper.

First recorded failed operation: `lifecycle(workspace('supervisor'),
'supervisor')` called `wait_running(run)`, then `selftest.snapshot(run)`, then
`json.loads(py(snapshot_source, run.name))` for execution
`c6dac6e58cfd4a119cdcf20afb2e46c2`, workspace
`bede5fc7867f441da4f3c7397dd1ce2a`. JSON parsing failed at line 1 column 1.
The inherited adapter raises on nonzero transport exit, so a returned response
implies transport exit 0. Its successful-response stdout and stderr were not
retained by that inherited helper; the exact bytes cannot be reconstructed.
Calling it definitively empty, rather than invalid at position zero, would
exceed the retained evidence. There is no transient classification or root-cause
claim for this first failure.

The next controller-death bootstrap failed with exact retained stderr
`RuntimeError: another candidate is registered`, transport exit 1. That is a
separate consequence of the prior lifecycle case not reaching collection.

The old boot `6309a5fab8fe40199701eebe2b486fb6` journal shows the first candidate
container/supervisor deactivated at 03:35:34 and its deadline reaper completed
at 03:35:36. First shutdown was later, at 03:35:50 (`Received SIGRTMIN+4`).
Subsequent boots started at 03:35:50, 03:36:11, 03:36:27, and 03:36:41.
The initial malformed transport response precedes these later shutdown effects.

The inherited collector records three `machine_stop_rc: 0` outcomes after
`ModuleNotFoundError: No module named 'remote'` in finalization. Machine-local
/tmp execution storage and workspace tmpfs content disappeared across the
reboots; this does not establish why the first response was malformed.
Current successful diagnostic queries show boot
e9ff5112fb1548c6920eb2d21673cabb and returned container/unit/mount inventories.
No additional explicit restart has been issued or is presently needed merely
to query this running machine. Positive exact owned-resource cleanup still needs
verification; failed queries are not absence evidence.

Raw diagnostic commands/outputs are immutable under `runtime-diagnostic-01/02`.
No image, installed-file, slice, or machine configuration was edited. The worker
has stopped candidate dispatch during diagnosis. Whole-machine crash recovery
is outside this API; missing started-execution proof must remain unresolved.

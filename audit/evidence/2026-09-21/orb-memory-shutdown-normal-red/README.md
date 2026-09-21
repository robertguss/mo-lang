# Shutdown normal synchronization RED

Candidate d2a9541f4cc9bb84df02587983ee02562b87c2cc on accepted
b52cac15cf4a3c19f29944214b0cf24a0fcd5b8f, integrated
f86da977436540cc62fba73e4bd94ca15ca2552b. Validator thread:
https://ampcode.com/threads/T-01a0c217-68f4-70c6-84b5-8283e6125331. Adjacent raw
commands, environments, outputs, exits, composition and cleanup receipts
describe the only two executed stages. Stages3/4 were not run.

Lead verified archive SHA-256
32cd9b3632f7c6b2b171455949bec707d625801302344257e7dfc4f79b4d2f60 and all
extracted manifest entries. Complete archive retained at validator
.amp/transfer/d2a9541f-four-stage/verification-d2a9541f-four-stage-stage2-normal-red.tar.gz
and lead /tmp/verification-d2a9541f-four-stage-stage2-normal-red.tar.gz. Lead
extraction: /tmp/mo-d2-shutdown-red/. This directory preserves text receipts;
the archive also contains the full candidate bundle.

Stage1 exit0/build5/5/tests2/2. Stage2 exit1/build3/5/tests1pass1fail. Build
succeeded with exact path stdout and empty stderr; all four empty-mode runtime
cases passed exit11/exactstdout/emptystderr. First mixed interpreter case
exited23 with empty stderr but printed parked0 rather than12. Remaining mixed
cases were not reached. Literal owned groups and scoped PIDs absent; no zombies.
No retry, ASan execution or new instrumentation object.

Lead reading (open after your own): Oracle/source tracing confirms the mixed
branch is one top-level main statement. It prints before automatic settlement;
direct HeldCount asks answer before unrelated Waiter work is scheduled. This
does not prove zero parked fibers at actual shutdown or faulty cleanup.
Queued/busy Waiters are protected from sweeping; discarded handles are not the
cause. Source-only fixture correction replaces polling with deferred Ready until
twelve Wait tokens arrive, then one HeldCount confirmation. Keep invariant,
exact outputs, runtime and prior lifecycle tests unchanged. No execution until
source reread; all seven acceptance obligations remain open.

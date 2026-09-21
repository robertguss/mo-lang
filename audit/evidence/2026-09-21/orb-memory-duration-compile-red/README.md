# Real large-restart retry: duration API compile-only RED

Candidate49b69a65f696f19c34e20cc19572cc9f0cc8da62 on
accepted728b7a9135f381d38614cf833641ce96d1c21870,
integrated924c24d8af1b517ac4f91592d2b369ecd5e74cb1. Independent validator:
T-01a0c217-68f4-70c6-84b5-8283e6125331. Exact command/environment, composition,
split outputs, actual exits, API excerpt and cleanup receipts are adjacent. Lead
verified the complete retained archive SHA-256:
a225217e93dc28f2056ccdd58898e380525ec53fb5b3aba06477ae7fced25e50. Archive
remains at the validator's
.amp/transfer/49b69a65-real-large-restart/verification-49b69a65-real-large-restart-red.tar.gz
and lead /tmp/verification-49b69a65-real-large-restart-red.tar.gz.

Actual exit1, build2/5. Compiler rejects Clock.Duration.nanoseconds at1435
and1485. No test executable or interpreter/native child ran; no captures or
metadata. Required2/2 was not reached. Outer PGID122221 and scoped PIDs are
absent (literal ps header-only outputs, exit1). Prior compile-only RED archive
is unchanged. No retry, source edit or additional gate occurred.

Lead reading (open after your own): source inspection also finds the same API
misuse at1569. Installed Zig0.16 Clock.Duration wraps Io.Duration in raw;
raw.nanoseconds is i96. Oracle approves only three .raw insertions, retaining
clocks, units, thresholds, ownership and metadata semantics. Source reread
required before any further execution; no runtime evidence or acceptance.

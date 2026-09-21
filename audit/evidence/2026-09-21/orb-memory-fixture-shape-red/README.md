# Large-restart gate: interpreter fixture shape RED

Candidate e73504d064b4686300c4775c746dc89b3ec65c8f on accepted
fe29ea7a3ecf5e0f12699cc88ff7d578da09dbc0, integrated
92e2589f708aa3323b18e386630b7d99d8de8b47. Validator:
T-01a0c217-68f4-70c6-84b5-8283e6125331. Raw commands, composition/blob proofs,
logs, exits, interpreter captures and cleanup receipts are adjacent.

Full archive SHA-256 verified by lead:
789a261ef715b76a298f5b532188d489120f09e9be1a7198ab817f2d904ce1fb. Complete
expected/actual captures remain in validator archive
.amp/transfer/e73504d0-real-large-restart/verification-e73504d0-real-large-restart-red.tar.gz
and lead /tmp/verification-e73504d0-real-large-restart-red.tar.gz. Expected
stderr remains90,006,894 bytes, SHA-256
a879d3cf18a5c5544d1d4d348ff627647b8c8d09f160bcb6118f894eced19c28. Actual
interpreter stderr is344 bytes, SHA-256
7321ee8b253a06016a412e683e270d263e0b054d32afe638e60a343e2a20a82c.

Actual exit1, build3/5, tests1 pass/1 fail. Interpreter PID147089 completed,
reaped, exited1 with null lifecycle errors. MO0304 rejects the retry case at
leak.mo:43 for depth4 above limit3. Stdout is empty; zero actual crash reports;
native build/run not reached. Outer group143835, scoped build PIDs and
interpreter PID/group are absent (header-only ps, exit1). Prior REDs preserved.

Lead reading (open after your own): Oracle approves source-only removal of the
enclosing if !empty and addition of break immediately after empty=true in the
success arm. Both backends target the inner retry loop; asks, retry3, sentinels
and invariant11:3 stay unchanged. Break bypasses retry-loop end collection;
outer-loop collection remains. Do not claim identical GC timing/RSS or waive the
strict RSS gate. No compiler/shape-law/oracle change or retry authorized; source
reread required. No restart/RSS/native evidence or acceptance.

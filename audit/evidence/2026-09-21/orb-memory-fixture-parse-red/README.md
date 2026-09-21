# Large-restart gate: interpreter fixture parse RED

Candidate eb6653716ea0fb73d75c4eda378a70e358260e30 composed onto accepted
cc2f2f0d7308003c32062e2fb33a7f9c4e2a3b08 as
efbccec10b62b461730d81771036edeaebc14d0e. Validator:
T-01a0c217-68f4-70c6-84b5-8283e6125331. Command, composition, logs, exits,
cleanup receipts and interpreter captures are adjacent.

Lead verified full archive SHA-256:
144d6bccb308229b805f0e2f150c32f729eac21d1f3a44d8e52f61cf8328cc5c. The complete
archive, including expected.stderr, remains in the validator at
.amp/transfer/eb665371-real-large-restart/verification-eb665371-real-large-restart-red.tar.gz
and the lead at /tmp/verification-eb665371-real-large-restart-red.tar.gz.
Expected stderr:90,006,894 bytes, SHA-256
a879d3cf18a5c5544d1d4d348ff627647b8c8d09f160bcb6118f894eced19c28. Interpreter
stderr:283 bytes, SHA-256
2ca1ae5723254a2156c821b88a041eb0cf1c5d431f31abf88e7418060640065c.

Actual exit1, build3/5, tests1 pass/1 fail. Interpreter launched, then rejected
leak.mo:44:24 with MO0101 before exercising restarts. Metadata records
completed, reaped, exited1 and null lifecycle errors. Stdout is empty,
comparison mismatch starts at0. Native build/run never reached; no RSS/restart
or native evidence. Outer group, scoped build PIDs and interpreter PID/group are
absent in literal ps receipts (header-only, exit1). Prior RED archives remain
unchanged.

Lead reading (open after your own): all four ask-result arms use inline
statements; the parser rejects both assignments and return in this position.
Oracle approves only converting those four arms to indented block statements,
preserving patterns, bodies, order, retry/sentinel behavior and all report/RSS
oracles. Invariant remains11:3; expected reports must not be adjusted. Source
reread before any new execution; no acceptance or broader grant.

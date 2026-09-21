# Exact normal large-restart gate GREEN, not acceptance

Candidate69dc6df1f664c10a7e8319ec4a575ec5b46f1394 on accepted
d02014c03eaa67531a48c1b5e0a6de2649d97b16, integrated
0a0de7f7de45d7c5b597ab01c43a5e85d8834053. Validator:
T-01a0c217-68f4-70c6-84b5-8283e6125331. Adjacent raw command/environment,
composition, logs, exits, stdout, metadata, comparisons and cleanup receipts.

Full archive52316502 bytes, SHA-256 verified by lead:
01bb987e7b1cbc181af4ab85d891c0aceb9096d33e042666c0a9484bec7bebb0. Includes all
three full stderr streams; retained at validator
.amp/transfer/69dc6df1-real-large-restart/verification-69dc6df1-real-large-restart-green.tar.gz
and lead /tmp/verification-69dc6df1-real-large-restart-green.tar.gz. Extracted
at lead /tmp/mo-69-real-green/69dc6df1-real-large-restart/.

Actual0, build5/5, tests2/2, no skips. Both children completed/reaped/exited0
with null lifecycle errors. Lead independently ran sha256sum, wc -c, cmp and
report-header counts on all full stderr streams: each90,006,894 bytes,25
reports, SHA-256
a879d3cf18a5c5544d1d4d348ff627647b8c8d09f160bcb6118f894eced19c28; both
comparisons exit0. Canonical stdout shows25 restarts and kept1 each. Interpreter
RSS25350144 to25415680 (increase65536); native7835648 to12161024
(increase4325376). Both strictly below16777216; printed0/4MiB are truncated
integer-MiB values, not exact byte deltas. Literal outer-group and scoped
build/interpreter/native PID/group receipts show absence, exit1.

Lead reading (open after your own): Oracle independently checked full captures
and agrees this bounded normal gate is green. It does not exercise capture
timeout/error paths or establish ASan/stress/mutant/timing coverage. Release one
fresh unfiltered normal corpus on the same exact integration, guard7200, fresh
caches/output/retained capture, observed inventory reconciled against309.
Existing case-local stress controls stay in normal corpus; no separate stress
gate granted. Stop-first; seven obligations and independent acceptance remain.

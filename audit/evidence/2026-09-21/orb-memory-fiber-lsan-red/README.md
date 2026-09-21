# Focused fiber LeakSanitizer RED

Source fa98233e2244b6c4a462a4852392a19bb417893e on accepted
6ea9abc64bdb56b846df24024b947cb7bcbecd9a, integrated
cdb2766805a6f1691a188385da2e51255695bb1a. Validator:
https://ampcode.com/threads/T-01a0c217-68f4-70c6-84b5-8283e6125331. Adjacent
files retain exact commands, environments, composition, split logs, real exits,
object-symbol evidence and process-cleanup receipts for both stages.

Complete archive SHA-256, independently checked by lead:
753640bf4dee441693f9c57ac32a1aea2ecbbd0ac1f03264617236956ff58fac. Validator
path:
.amp/transfer/fa98233e-two-stage/verification-fa98233e-two-stage-stage2-lsan-red.tar.gz.
Lead copy: /tmp/verification-fa98233e-two-stage-stage2-lsan-red.tar.gz;
extracted /tmp/mo-fa-lsan-red/. All archived manifest entries passed sha256sum
-c. The complete archive retains the bundle and runtime object; this repository
directory retains text receipts only.

Stage1: exit0/build5/5/tests2/2. Stage2: exit1/build3/5/tests1pass1fail. Quiet
build/link succeeded. Interpreter70/native70/interpreter20 passed exact outputs
and empty stderr. Native20 printed the expected output then aborted:
LeakSanitizer 131840 bytes in12 allocations, comprising forwarding table131072,
pool array128 and ten Fiber objects640. Owned groups327394/336841 and scoped
processes absent. Prior archives unchanged. No retries or additional gates.

Lead reading (open after your own): source inspection with Oracle identifies
missing scheduler-thread cleanup for the forwarding table and completed-fiber
pool. Source-only correction assigned, including scheduler zero at program end.
Pooled fibers must permanently depart via the sanitizer switch protocol before
off-stack destruction; parked fibers, saved VMs and exported reports are not
cleanup-owned. Add shutdown regression source, preserve existing assertions and
sanitizer settings. Review before execution. This is not acceptance or a claim
that all shutdown resources have been reclaimed.

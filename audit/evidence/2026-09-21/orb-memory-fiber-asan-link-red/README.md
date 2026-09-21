# Focused fiber-ASan final-link RED

Exact integration0a0de7f7de45d7c5b597ab01c43a5e85d8834053,
source69dc6df1f664c10a7e8319ec4a575ec5b46f1394 on acceptedd02014c0. Validator
T-01a0c217-68f4-70c6-84b5-8283e6125331. Adjacent raw command, environment
controls, logs/exit, composition, symbol/relocation and cleanup receipts.
Complete archive SHA-256 verified by lead:
5762c9388817747813be5a56c1d8f7686b025ec8973806e2f37ebf0cb4bae098. Retained in
validator at
.amp/transfer/69dc6df1-focused-fiber-asan/verification-69dc6df1-focused-fiber-asan-red.tar.gz
and lead /tmp/verification-69dc6df1-focused-fiber-asan-red.tar.gz. Actual
objects extracted at lead /tmp/mo-69-fiber-asan-red/.

Actual exit1, build3/5, tests1 pass/1 fail. Final Clang link failed on crypto.o
R_X86_64_32 relocation against .rodata.str1.1 under default PIE. None of the
four required interpreter/native runtime cases ran. Fresh mo_rt.o SHA-256
cc279a6bea5a59e2aed7606b1af429f1840392adad99b98f8ffdd15b3a5a05d6 contains
compiler-generated ASan access-report, fake-stack/UAR and fiber-hook references,
independently inspected by lead/Oracle. Crypto object SHA-256
6ffa895a5d0cf5b228e35732fbb52325df2a68214cdd7f64ec5a5eb8451b7a41 has the
reported absolute relocations. These establish instrumentation and a link
mismatch, not passing sanitizer execution. Owned group305384 and scoped PIDs
absent; prefix/bin/zig absent. No retry/edit/extra gate.

Lead reading (open after your own): source-only correction authorized in
cbuild.zig final argv assembly: Linux host-ASan adds -no-pie, not shared
ccFlags/runtime compilation or brick commands. Extend existing fake entrypoint
control to require per-stage counts0/0/0/1 only for Linux ASan, all0 otherwise.
Preserve quiet rejection, ordinary flags and cache identities. Opt-in evidence
executables become non-PIE; this is not production-hardening policy. ASan/UAR/
LSan remain enabled. LLVM14 supports this mode; see Gnu.cpp PIE selection and
SanitizerArgs.cpp ASan's Fuchsia-only PIE requirement. No runtime/RSS
equivalence or successful link is assumed; return source for review before any
retry.

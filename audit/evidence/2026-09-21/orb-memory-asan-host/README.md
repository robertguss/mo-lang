# Host readiness packet and lead release addendum

Exact validator integration0a0de7f7de45d7c5b597ab01c43a5e85d8834053,
source69dc6df1 on acceptedd02014c0. Inspection only: no builds/runtime. Raw
packet archive SHA-256 verified by lead:
d84cb65fb5609856259d2d9680e8751ee6f515ebfafd7325c78728741c063a70. Original
retained in validator thread T-01a0c217-68f4-70c6-84b5-8283e6125331 at
.amp/transfer/69dc6df1-asan-host-inspection/inspection-69dc6df1-asan-host-preconditions.tar.gz;
lead copy /tmp/inspection-69dc6df1-asan-host-preconditions.tar.gz. Adjacent
files preserve the returned packet verbatim, including its unresolved config
conclusion and overstrong successful-argv requirement.

## Lead reading and corrections (open after your own)

Lead/Oracle inspected the packet: direct Debian Clang14.0.6, matching
compiler-rt ASan/fiber/fake-stack/leak symbols, absolute symbolizer, sanitized
tool queries, executable filesystem and absent fresh roots. No runtime
compatibility is yet established.

Config concern resolved from exact Clang14/Debian source: literal clang has no
target prefix; absent explicit --config, the driver returns before implicit
config search. cbuild passes literal clang, no config/response args; reviewed
PATH resolves it directly and CCC_OVERRIDE_OPTIONS is unset. Explicitly unset
CLANG_NO_DEFAULT_CONFIG; do not add unsupported --no-default-config. Sources:
https://github.com/llvm/llvm-project/blob/llvmorg-14.0.6/clang/lib/Driver/Driver.cpp#L978-L985
and
https://github.com/llvm/llvm-project/blob/llvmorg-14.0.6/clang/tools/driver/driver.cpp#L469-L474.

Correction to later-evidence-policy.txt: successful compiler/link argv are NOT
retained by this source. Runtime-object instrumentation must be
artifact-verified including ASan access checks, fake-stack/UAR and both fiber
hooks. Successful argv and generated-C instrumentation remain
source-established; compiler quietness is enforced by reviewed runCompiler
success checks. No tracing, wrappers or code changes to manufacture stronger
evidence.

Release exactly one focused native-fiber test-corpus-asan under accepted direct
guard1800 on same integration, with packet PATH/HOME/absolute symbolizer and
sanitized environment, four newly created absent cache/prefix roots, and exact
ASAN_OPTIONS
detect_stack_use_after_return=1:detect_leaks=1:halt_on_error=1:abort_on_error=1:symbolize=1:log_path=stderr:leak_check_at_exit=1.
Check prefix/bin/zig absent before/after. Require both interpreter/native70
and20 cases exact held/released/done/sum outputs, exit0, empty runtime stderr,
quiet compiler stages, nonzero/no-skip selection, retained runtime object and
certain owned cleanup. Stop-first, no retry, suppression, fake-stack/leak
waiver, ptrace, fullASan/stress/mutants/timing or acceptance. Return evidence
for review.

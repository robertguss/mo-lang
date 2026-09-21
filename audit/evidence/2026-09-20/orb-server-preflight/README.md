# Independent server preflight and Journal lifecycle checks

Build and formatter regression ran in /tmp/mo-lead-orb-server at revision.txt.
Commands from toolchain, each through the accepted direct guard with pipefail,
tee and adjacent actual exit files:

- guard.py900 -- zig build -j4 --summary all:5/5, exit0,108.88s.
- guard.py1800 -- zig build test-corpus -j4 -Dtest-filter='corpus: fmt check
  classifies imported calls' --summary all: 2/2, exit0,3.25s. Expected MO0501
  controls remain in raw output.

The later Journal checks ran at journal-revision.txt, source tree equal to
candidate e56db9c8, using its journal_down_control.py --mode negative/positive.
That script gives each real Mo command the accepted direct guard with30s limit.
No live server/socket suite or metadata matrix ran in this lead check.

- Negative: actual mo test exit0 despite unconditional assert false after an
  expected Journal crash; external wrapper exits1, masked_assertion=true. This
  is a retained known-bad test-runner result, not green evidence.
- Positive: mo run exit0, external wrapper exit0, exact
  journal_down_control=passed. It checks actual reply, identical retained
  envelope, closed admission, Journal still Down and one recording attempt
  without depending on the flawed test-rejects verdict. The expected crash
  report remains intact.

## Independent module tier and native failure

At the same candidate, verify.py --kind write generated real metadata in
dependency order:15 modules,44 tests, strict9 simulated at200 seeds/faults0,
production3 held under200 seeds/faults5. Format/fmt each passed15/15; fixed
matrix44/0/0; strict9/9 with no faults; production35/0/0,3 simulated and3 held,
none passed only without faults. Actual per-module summaries were inspected.
Each stage's raw log and actual exit are filed. Generated parent IDs and five
footers were committed only in the verification tree at metadata-revision.txt.

The next direct-guarded1800s command, zig build test-corpus -j4
-Dtest-filter='workspace server strict process fixture' --summary all, failed
exit1/89.11s. Interpreter9/9; native7/9. Both new journal-delay tests received
Ok(completed envelope) where their100ms/500ms callers expected Timeout. The
dependent Step44 run did not execute. The worker is investigating this native
parity mismatch without relaxing the assertions.

These checks do not accept the server. Native/socket/full-suite and benchmark
obligations remain. The runner masking defect needs a separate bounded fix;
server and memory workers must coordinate any runtime ownership change.

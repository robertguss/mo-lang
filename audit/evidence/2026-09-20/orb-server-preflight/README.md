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

These checks do not accept the server. Full module/simulation/native/socket and
benchmark obligations remain. The runner masking defect needs a separate bounded
fix; server and memory workers must not edit the same runtime paths.

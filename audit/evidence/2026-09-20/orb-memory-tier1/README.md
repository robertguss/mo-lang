# Independent first memory-candidate tier

Exact integrated revision is revision.txt, source equal to worker4e1be90e.
Commands ran from /tmp/mo-lead-orb-memory-corrected/toolchain with the unchanged
accepted direct guard, pipefail, tee and adjacent actual exits. ASan unset.

Build: guard.py900 -- zig build -j4 --summary all passed5/5, exit0,106.03s. Each
focused run used guard.py1800 -- zig build test-corpus -j4 -Dtest-filter=FILTER
--summary all. The exact filter is beside each control log. Pack's filter was
"step 42: pack frees its parcel when copying the payload runs out of memory".

Pack, A, runnable reserve, B and trace reserve passed2/2 each (root harness plus
one named control), exit0. Printed allocation/ownership observations remain in
the logs; runnable's retained caller ownership is not a reported leak.

Control5, commit failure I, failed1/2 exit1 before reaching its allocation
assertions: compile(commit_failure_src) rejects its inline assignment arm with
MO0101. The sequence stopped there; no later lead control ran. The worker owns
fixture correction, not a parser-rule change. This failure is not yet evidence
for or against the intended runtime transaction behavior.

No full suite, stress/ASan sweep, mutant or timing series ran. These results do
not accept Step42. A post-run process-name scan found no live mo/zig/test/guard
process on this lead orb.

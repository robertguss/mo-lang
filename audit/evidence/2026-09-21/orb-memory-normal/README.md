# Fixed Step42 normal-lane failure

Lead reading; open after your own. Recorded 21 Sep 2026, 12:22 AM ET.

Independent validation worker T-01a0c217-68f4-70c6-84b5-8283e6125331 tested
fixed413e006c composed with accepted main e79806fc. Exact integrated revision,
composition proof, environment, command, raw output and real exit are adjacent.
The lead downloaded and inspected this evidence and the candidate source.

Normal full corpus: 288/289, one crash, exit 1. The existing seeded chunks test
explicitly enables packs; the candidate's new enqueue assertion rejects its
packed source message. This is a candidate contract defect, not a guard issue.
The payload group was absent after exit. ASan was not run. Clang installation
does not establish instrumentation or sanitizer success.

Oracle recommends preserving seeded scheduling with packed messages while
omitting diagnostic trace entries in packed mode. Raw Step values would
otherwise outlive parcels freed by log eviction/restart. Source-only correction
and discriminating scheduling/ownership controls are assigned to the
implementation worker; deleting assertions or weakening the existing test is not
acceptable. Fresh normal validation must precede ASan resumption. All seven
Step42 evidence obligations remain unwaived; no runtime acceptance or timing
claim.

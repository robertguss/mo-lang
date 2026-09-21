# Independent native lifecycle matrix

Lead reading; open after your own. Candidate ad748089, integrated revision in
revision.txt; src/runtime/build/Step42 fixture bytes match that candidate.

From the verification tree's toolchain directory, the lead executed once:
`env -u MO_NATIVE_ASAN python3 bench/step36/guard.py 1800 -- zig build test-corpus -j4 '-Dtest-filter=corpus: step 42 native parcel lifecycle matrix destroys every retained owner' --summary all`.
Actual exit0, build5/5, selected2/2, no skips, all18 normal/audited case
results. The full raw diagnostic output is retained, including expected process
crashes. Both normal and audit stdout/exit/report oracles passed; audit counts
were 3/3/0,4/4/0,6/6/0,5/5/0,2/2/0,9/9/0,9/9/0,19/19/0,3/3/0.

This command used the earlier accepted direct guard: Git blob
4b1c94ae257bc19160ecaf102bad1c2a37fc2121, byte-identical at70c07d32 and1839785e.
It did not use guarded.py or the later accepted wrapper-core corrections.
Post-run process inspection found no matching lifecycle/build/guard processes.
The next fresh full validation explicitly pins current accepted main guards.

Worker equivalent archive SHA-256:
c4835bb6f44e5bd7bb96e8b0c9f5813ebcfd12508700579705e52c8861f59619. Its native
matrix also passed. Earlier Zig/chunks greens retain e7e12385 attribution. No
ASan, mutants, stress or timing evidence is supplied here. Private audit final
sweeping proves this controlled accounting boundary, not ordinary
automatic-shutdown reclamation. Seven Step42 obligations remain.

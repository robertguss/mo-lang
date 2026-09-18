---
subject: generation six of the erosion round, its execution (not its result, which does not exist yet)
author: Fable (the lead)
date: 2026-09-18, between 9:30 and 9:50 AM ET, pushed at baf6683 (corrected 9:54 AM ET: the header first said "about 10:15" or "10:25", a time Fable guessed instead of reading the clock; nothing else in the file changed)
filed_against: 64982b2 (the commit the auditor's branch names), with what Fable knows of the run up to 9:50 AM ET
read_before_auditor: yes. Fable had not opened the auditor's reading, its checks, its evidence folder, or its `audit/state.md` lines on this subject when this was written; the receiver announced pointers only (kind, id, commit, path, the PR number). Robert said only that the PRs exist.
evidence: mo-wiki/plans/erosion-round.md (generation six, pre-registered, Started, Interrupted, Continued on the Mac); mo-wiki/spec/programs/01g-job-queue-change-6.md; mo-wiki/plans/erosion-round-suite/{e6-brief.sh,e6-brief-mac.sh,e6-suites.sh,e6-suites-mac.sh,defects6.py}; the branches erosion6-{mo,go,python,elixir} with REPORT-change-6*.md; the decision-log rows of 18 Sep
---

# Fable's reading: how generation six was run

This is a reading of the execution, written while the round is still running
(Python finished on the VM; Mo finished on the Mac at 9:44 AM ET; Go and
Elixir are working; no suite has run). It is mostly a list of what is wrong
with the run as a measurement. Fable ran it, so these are Fable's errors.

## What was done in order

Pre-registered and sealed at 4:16 AM ET; the seventh suite sealed by hash
(`d4dab05cc331b7fa`, `48640d3`) before the sessions; four sessions started
4:45 AM ET on the four-core, 16 GB VM; the VM wedged at 5:21 AM ET on a 13.4
GB `mo` process; Python finished 5:43 AM ET; restart 8:30 AM ET; Herdr
resumed the three sessions (`claude --resume`) at 8:36; stopped at 8:45 with
work-in-progress commits; three **new** sessions on Robert's Mac at 9:23 AM
ET with an amended brief that names the predecessor's report.

## What that does to each recorded or predicted quantity

1. **Wall-clock, loops, first-fix rate, tokens (P5 and the recorded
   columns): not comparable with generations two to five, and not comparable
   across the four languages within this generation.** Python is one
   uninterrupted session on the VM. Mo, Go, and Elixir are three segments
   each: before the wedge, a resumed context after a three-hour gap, and a
   fresh context on another machine that had to read a report and re-measure.
   The third segment pays a re-orientation cost and, for Go and Elixir, a
   porting cost (their `bench` read `/proc`). P5 (Mo takes more loops than
   Go) can be reported but it should not count for or against anything.
   Tokens for the VM segments were not read before those sessions ended.
2. **P7, the budget, has a problem Fable made this morning.** The
   pre-registration says "at least 0.8× change 3 (at least 1,300 pairs a
   second at 32 workers on the VM)". The only VM measurement of the fixed Mo
   program is the predecessor's: 943 pairs a second against change 3's 1,046
   measured in the same sitting (0.90×), under a load of 4 to 6 from the other
   three maintainers. **943 is under the absolute 1,300.** At 9:23 AM ET,
   with that number in view, Fable wrote a row saying P7 is read on the Mac
   "by the budget's own ratio". That is a re-reading of a pre-registered
   threshold with evidence in view, which the charter names as a violation.
   The honest statement for the result: the ratio clause is what the spec
   gives the maintainer and can be evaluated on either machine; the absolute
   clause was the VM's, was not met in the one loaded VM measurement, and
   cannot be evaluated on the Mac. P7 should be reported as two clauses, not
   as held.
3. **The maintainers' budget runs were not taken "with nothing else
   running".** On the VM four maintainers benched on four cores at once
   (Python's 1.01× and 1.03× were taken in that). On the Mac the Mo
   maintainer's four runs were at load 5.6 to 7.5, with two other maintainers
   and step 38's worker (started by Fable at 9:26) on the machine; its ratios
   were 0.86, 0.96, 1.00, 0.90. A 0.86 against a 0.8 threshold from two
   rounds under load is inside the noise. Only the lead's own quiet
   `measure.py` row, one program at a time, can decide the budget, and it
   has not been taken.
4. **The Mo maintainer's `bench` is not the other three's.** It runs the
   service in-process and its "restart" reopens the folder in a second
   service; its change-3 comparison is change 3 with this `bench.mo` copied
   in. The spec allowed each maintainer its own bench; the four programs'
   bench lines are therefore not comparable with each other, only each with
   its own change 3.
5. **P6 (a `never` trips on a wrong edit): the Mo report says none did.**
   One `requires` is exercised by a `rejects` test, which is a test passing,
   not a law catching an edit. Fable's prior was that P6 fails; it appears to.
6. **The seventh suite is Fable's**, written from Fable's spec, sealed by a
   hash Fable recorded. It is hidden from the maintainers, not from the
   author of the predictions. Its hash should be re-checked at the moment it
   runs, and the runner for the Mac (`e6-suites-mac.sh`) was written after
   the sessions began; it changes paths, `ss` to `netstat`, the `pkill`
   pattern, and adds a 4 GB watchdog, and does not touch a suite.
7. **Two machines in one generation.** Python's program was built and
   benched on Linux; all four programs' suites will run on the Mac. The
   speed row per generation (30,000 jobs, one core) was the VM's in the
   pre-registration and will be the Mac's. Generation five's row was taken on
   the Mac, so the series is continuous there, but the pre-registered text
   said the VM.
8. **The wedge itself is a finding, not only an accident.** `mo test --sim`
   on a process with a perpetual delayed send does not settle and its memory
   grows without bound; no limit, no diagnostic. A simulator that can take a
   machine down on a plausible maintainer design is a runtime row.

## Reading

Generation six's correctness columns (P1 to P4: the seven suites on the four
final programs) are still sound to read, since they depend on the final
commits and not on how the sessions were run, provided the suite's hash is
checked. Its cost columns (P5, time, loops, tokens) are compromised and
should be reported as such. P7 must be re-measured by the lead on a quiet
machine and reported as two clauses. The generation counts toward the
language rule at generation ten only through P6 and the catch ledger, which
the interruption does not affect.

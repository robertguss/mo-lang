# Audit reading: generation-six execution and test integrity

**Date:** 2026-09-18  
**Author:** Mo Auditor (independent model session)  
**Charter:** raw-evidence review; only Robert may amend or reject the reading.  
**Scope:** change-6 specification, generation-six pre-registration additions, `defects6.py`, VM/Mac briefs and suite runners; not a completed-round verdict.  
**Status:** filed independently before opening lead synthesis, against `64982b23b1dfed0bd0af3430125589da43058ac0`; recent-change baseline `aace4ee36516c9dc67cdb7b0d0c8cab3a5f9c024`.  
**Explicit gap in this reading:** no maintainer implementations, finished reports, actual suite runs, migration timings or benchmark results were reviewed. No generation campaign was launched. The checks below exercise harness source and explicitly mocked control flow, not jobq correctness. Generation six is ongoing at the evidence cut; no P1–P7 result or L-2 ledger catch is awarded.

## Reading

The suite is sealed consistently but is **not sufficient to adjudicate the registered predictions without correcting or separately accounting for the harness defects below**. In particular, a FIFO-correct program can fail the sequence setup, an acknowledged job rolled back to queued can evade the kill oracle, and a timed-out suite can leave a successful wrapper status. The claimed budget-only discovery condition is contradicted by the maintainer-facing specification itself.

Severity here ranks risk to the validity/safety of the experiment, not shipped production vulnerabilities. Findings are about the pinned source; none asserts a particular maintainer's result.

## What the auditor read cold

- `audit/README.md`, `CHARTER.md`, `AUDITOR.md`, `WORKFLOW.md`, and the ratified `stopping-rule-never-invariant` reading (ratification block governs preserved rationale).
- `mo-wiki/spec/programs/01g-job-queue-change-6.md`; FIFO clauses in `01-job-queue.md:42` and `01b-job-queue-change.md:33`.
- Only generation-six pre-registration/addendum lines `mo-wiki/plans/erosion-round.md:283–303`, including the migration disclosure, and its added-line diff. Earlier Result/Reading sections were excluded.
- `mo-wiki/plans/erosion-round-suite/{defects6.py,e6-brief.sh,e6-brief-mac.sh,e6-suites.sh,e6-suites-mac.sh}`; shared harness definitions `control-run-8-suite/defects.py:18–88`; referenced `toolchain/bench/step36/guard.py`.
- No decision-log contents, Fable reading, HANDOFF, RESULTS file, lead skill, worker session or worker report was opened.

## Findings

### G6-1 — High: sequence setup contradicts mandatory FIFO

`defects6.py:270–274` creates four jobs in `s2` and acknowledges only the first. At line 282 it calls `done_job("s2", "s2-late")`, while three older queued jobs remain. `done_job`, lines 55–62, creates a new job, leases once, and returns `None` without acknowledging if the lease is not the newly created id. The spec requires oldest queued first (`01-job-queue.md:42`, reinforced in `01b-job-queue-change.md:33`). Thus FIFO-correct behavior prevents creation of the intended fourth archived job. Lines 283, 288, 293–294 then require that nonexistent late archive.

**Actual check:** the original helper, AST-extracted without importing/running the suite, was given a mock new id and an older FIFO lease. It returned `None`, with zero ack calls. This validates the helper's faulty assumption; it is not a real implementation failure. Do not assign resulting sequence failures to language defect causes until the fixture is corrected and re-sealed/disclosed.

### G6-2 — High: the kill oracle misses acknowledged-state rollback

`defects6.py:235–236` labels its assertion “every acknowledged ack is present,” but the `lost` predicate requires BOTH a state outside `done/archived` AND a status other than 200. A job restored as `200 {state: queued}` is accepted. Mere presence does not establish durability of the acknowledged ack (`01g:3`, inherited durability rule). The same expression examines only `list(acked)[:200]`, despite saying every acknowledgement, and performs two independent reads for some results.

**Actual check:** evaluation of the original AST expression with an acknowledged id and `200 {state: queued}` returned `lost=[]`. This is a demonstrated oracle false negative, not evidence that any tested program has that bug.

### G6-3 — High: failed/incomplete runs are not fail-closed

`defects6.py:323–329` catches category exceptions as one failed check and prints counts, but returns normally regardless of defect count. Both wrappers discard `timeout`'s status (`e6-suites.sh:23–27`, Mac `:31–35`), filter output down to matching lines, perform cleanup/drain and later print `done` (`:35` / `:43`). They also do not stop on build failure (`:8–19` in both), allowing a stale scratch binary or missing build to be followed by suite attempts.

**Actual checks:** main with seven deliberately failing mocked categories printed `0 passed, 7 defects` and returned normally. Each original `suite()` function, isolated with harmless substitutes for process killing and a timeout stub returning 124, exited 0; the summary contained only the heading, while the raw log contained `MOCK timeout`. A wrapper's successful exit or final `done` is therefore not completion evidence. Require explicit build/suite exit status, expected coverage, and complete raw outputs for any eventual reading.

### G6-4 — High methodological gap: “told only the budget” is not blind

Pre-registration P7 (`erosion-round.md:297`) requires the Mo maintainer, told only the budget, to find the change-4 postcondition. Yet the supplied page's status paragraph explicitly says the slowdown is “a postcondition walking every finished job on every request” (`01g:3`), while `01g:31` claims that this page does not tell the maintainer where to look. Both briefs instruct reading that page (`e6-brief.sh:10`, Mac `:11`).

This establishes disclosure in the assigned input, not proof the maintainer read or used the sentence. The performance ratio can still be measured. An eventual speed recovery cannot establish unaided discovery under P7's stated information condition. This reading does not retroactively amend P7; Robert owns any rule/scope decision.

### G6-5 — Medium: P4's distinguishing cases are absent from the seventh-suite sequence

P4 is explicitly about a **change-5 folder or directory-entry case** (`erosion-round.md:294`; `01g:39`). `t_sequence` always starts a fresh directory (`defects6.py:269`). Its compact command runs to completion (`:277`), and the kill occurs after reopening and another write (`:295–299`), not between rename and directory fsync. `defects6.py:317–321` has no old-change-5 executable/fixture parameter. The wrappers do pass old control-run programs to the earlier `defects1` suite, but that is not the requested change-5 compatibility case.

The maintainer-facing sequence is a separate acceptance requirement and may supply evidence later. Green `defects6.py` alone cannot establish P4. Likewise `t_bench:304–312` tests small-run output shape, not the 0.8× historical budget; paired benchmark evidence remains necessary.

### G6-6 — Medium: migration safety/portability is incomplete in the filed runners

The Mac runner's watchdog begins only after builds (`e6-suites-mac.sh:8–29`). It matches every process on the machine by command substrings `jobq`, `zig-out`, or `beam.smp`, without ownership or descendant filtering (`:23–28`), so its code can target unrelated work. `guard.py:5–16`, named by the Mac brief, monitors/kills only its immediate child's PID, not that child's process tree. These are source-level bounds, not an assurance that every descendant stays below the advertised limit.

The outer drain is ported to `netstat` (`Mac :30`), but `defects6.py:37–42` retains `ss`, and line 325 retains broad `/tmp` process killing. Exceptions may skip category-local cleanup; outer Mac cleanup targets different prefixes (`Mac :34`). No Mac execution was performed here. The runner needs environment/cleanup evidence rather than treating Linux syntax checks as Mac validation.

## Independent verification and count semantics

Reproducible checks and actual output:

- `audit/evidence/2026-09-18/recent-specs/auditor-checks.py`
- `audit/evidence/2026-09-18/recent-specs/auditor-checks.json`

`python3 audit/evidence/2026-09-18/recent-specs/auditor-checks.py` exited 0. `bash -n` passed for all four e6 shell files. Python AST parsing succeeded. Seven categories and **88 static `check` call sites** were counted: prune 26, retention 5, prunerecord 17, prunekill 7, renamerule 12, sequence 16, bench 4, plus main's exception check 1. Loops, conditional checks and exceptions make this neither an executed-assertion count nor a distinct-defect count. Shared `check` simply appends every failed assertion (`control-run-8-suite/defects.py:67–69`); it does not deduplicate causes. P1's “cause” and eventual law ledger require causal classification, not copying that printed count.

The actual SHA-256 of `defects6.py` is `d4dab05cc331b7fac4e48961eeefdaa271c7444fc83bd3361b2251d7f7b1955a`, matching the documented prefix. The blob at seal `48640d33baad504708795021a6694d7c35eccfa0` has the same full hash. Programmatic comparison found the P1–P7 table unchanged since that seal. The later migration addendum is separate; no conclusion about a decision-log amendment is possible because the log was intentionally not opened.

## Migration and stopping-rule limits

`erosion-round.md:301–303` discloses interruption, resumed sessions, the VM→Mac move, Python not being rerun as a maintainer, and the Mac same-machine ratio replacing reliance on the VM absolute number. This is useful disclosure, not matched-cost proof. Final evidence must retain both sessions' time/loops, identify missing interruption accounting, keep VM and Mac numbers separate, and provide same-machine change-3/change-6 pairs. The spec's “nothing else running” condition (`01g:31`) needs measured load/context, not the brief alone.

P6 only asks whether a law trips on a wrong edit. L-2 requires at least two Mo defects that no test would have caught, plus false-positive and density bounds by generation 10 (`audit/mo-audit-2026-09-17-stopping-rule-never-invariant.md:17–31`). P6 success alone is not an L-2 catch. No generation-six catch ledger is created from ongoing work.

## Standing concerns and candidate falsifier

- Preserve all harness-induced failures separately from implementation causes; do not silently replace a sealed suite after seeing results.
- State/decision-log files are deliberately untouched to avoid conflicts with parallel audits. These concerns are filed here for later integration, not ratified as new rules.
- **Would overturn this reading:** a re-sealed, disclosed harness plus raw negative controls showing FIFO-correct sequence setup, rejection of acknowledged rollback, nonzero/explicit incomplete status, actual change-5 and directory-fsync-window coverage, and matched benchmark/session accounting. An input audit proving a different, cause-redacted spec was actually supplied could narrow G6-4; the filed briefs currently point to the unredacted page.
- **Candidate falsifier of the residual language claim:** a complete generation-6–10 ledger still below two test-independent law catches, or outside the ratified FP/density bounds, fires automatic R-B. This round's green suites would not defeat that falsifier.

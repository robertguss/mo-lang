# Audit reading: generation six

**Date:** 2026-09-18  
**Author:** Mo Auditor (GPT-6 Astra session with isolated delegated evidence reviews, independent of Fable)  
**Charter:** the auditor reads evidence and files before opening Fable's reading; only Robert can amend or reject the reading.  
**Scope:** the four final change-6 jobq programs against P1–P7 and the ratified language-law ledger; suite/runner validity, correction timing, and speed conditions. Not acceptance of implementation work or a general runtime/capability verdict.  
**Status:** filed cold to Fable's generation-six reading, against evidence commit `d846a4b35e7630a91ca5f608e8d46c43eef21ef6` (E). Entry main was `6fd8926deef69b921b932ae6c0d28a6387f7c633`, `ready: generation six, to the auditor`.  
**Authorization:** Robert's explicit `audit: generation-six` request and `audit/handoffs/generation-six/generation-six-ready-001.json`.

## Explicit gaps in this reading

- The original seventh suite does not reach its six service-based categories with valid parameters. The corrected suite is useful **late-corrected evidence**, not the originally pre-session sealed instrument; it still has unequal malformed-record coverage.
- No campaign was rerun on Robert's Mac. Independent executions here were bounded Linux Go/Python tests, supplied harness selftests, and a labelled mock of the speed instrument. Elixir and both Mo execution modes were assessed through final source and filed outputs, not newly rebuilt or rerun here.
- The directory-entry interruption required by P4 is not exercised by the filed outside suite. Mo's own report/script explicitly leaves it untested. Successful process-kill recovery does not substitute for this boundary or for power-loss testing.
- Maintainer loops and absence of unexpected law trips are self-reports, not reconstructed complete event histories. VM panes were not saved; no panes were opened in this reading. The generation-6–10 test-only unique-cause ledger cannot be filled by adding loop counts.
- The specifications contain a real `/queues` tension. I preserve both clauses below rather than silently deleting two failures from every program or calling them two independent persistence defects.

## Reading in brief

The evidence supports working prune/replay/rename behavior over substantial tested cases, but **not a clean win over the complete pre-registration**. P1's literal Mo-zero condition fails on one carried validation cause. P2's raw totals are not comparable defect-cause counts. P3's predicted baseline loss was not observed. P4's required coverage is incomplete. P5 is supported by reported loops. P6 has the added law but no established wrong-edit trip. P7 has a real source optimization and favorable Mo Mac ratios, but the supposedly undisclosed cost was disclosed in the brief's specification and the registered quiet-machine conditions were not met.

For the ratified language rule: **zero new unique-only catches established; zero new false positives evidenced; 16 shipped declarations over 8,630 physical Mo lines, density 1.8540/1,000.** Keep the ledger open. Generation six neither vindicates the claim nor triggers its generation-ten retirement decision.

## What was read, and citation keys

All evidence/spec/suite citations below are at E unless otherwise stated. Line numbers are one-based.

- **RAW** = `audit/evidence/2026-09-18/generation-six/raw/`; **REPORT** = the sibling `reports/` directory. Read the index, commit list, raw summaries and relevant individual outputs, final and WIP maintainer reports, Mo toolchain report, and maintainer-visible brief scripts.
- **ES** = `mo-wiki/plans/erosion-round-suite/`; **CR8** = `mo-wiki/plans/control-run-8-suite/`. Read `defects6.py`, `defects6b.py`, runners, earlier called instruments and their relevant fixture writers.
- **S6** = `mo-wiki/spec/programs/01g-job-queue-change-6.md`; **S5** = `01f-job-queue-change-5.md`; **S4** = `01e-job-queue-change-4.md`, in the same directory.
- **P** = only `mo-wiki/plans/erosion-round.md:283–302` at `48640d33baad504708795021a6694d7c35eccfa0`, the generation-six pre-registration, sliced before the next heading.
- **RULE** = `audit/mo-audit-2026-09-17-stopping-rule-never-invariant.md`, particularly the ratification at lines 11–37 and ledger requirement at 176–183.
- **M** = `53ee60d3751aac327e6e9ba4e1a9889f0d137ef1`, Mo final; source prefix `examples/programs/jobq/`.
- **G** = `765aa6f3277185bb35938224639f12dced63da12`, Go final; source prefix `experiments/control-run/go/jobq/`.
- **Y** = `618853729bc32907e9f0eb6c0c8ed771a2f35fb5`, Python final; source prefix `experiments/control-run/python/jobq/src/jobq/`.
- **X** = `1e46b99bae4654c02c65c1f313374ec3033a0faa`, Elixir final; source prefix `experiments/control-run/elixir/jobq/lib/jobq/`.

These final commits were fetched and their actual source inspected. Mo's change-5 ancestor `23118a3` was used for the relevant diff. The required audit governance and stopping rule were read. No `audit/fable-reading-*`, erosion result section, decision log, CHANGELOG, HANDOFF, project-state page, or wiki log was opened before filing. `audit/state.md` was deferred until after the reading commit to avoid importing a subject summary. Existing profile procedures contain lessons from earlier audits; this is independent of the lead's present reading, not a claim of having no prior project knowledge. The authorized index and maintainer reports contain explanations; those are distinguished from raw execution below.

## 1. Instrument identity and chronology

Independently hashed Git blobs:

- Original `defects6.py` at the pre-registration: `d4dab05cc331b7fac4e48961eeefdaa271c7444fc83bd3361b2251d7f7b1955a`; unchanged at E.
- Corrected `defects6b.py` at `346e8750296eb26d9fd68d3b1fef6ce5934cf241` and E: `183a992cb6893ca8c4c2e34b3190a3fc90c02619f2e17e7010844368ff675c73`. The delegated check also found the same blob hash at runner-fix commit `bd9b4a1`.

Git metadata dates the corrected commit to **10:00:02 EDT**. The first filed campaign starts **10:26:23**, and the first corrected run **10:30:55** (`RAW/e6-suites.out:1,34`). This supports sealing before the filed campaign, not an independently authenticated wall clock. Crucially, the corrected file itself says it was written **after Python/Mo finished, while Go/Elixir were working, and after the Mo report was read** (`ES/defects6b.py:2–11`). Its inherited “before the four maintainers' sessions started” sentence at 13–14 cannot describe the correction.

The changes are substantive but disclosed: valid retention settings and waits; fresh-queue FIFO setup; corrected lost-ack predicate and all-acked enumeration; separate selected preconditions; failure exit status; Mac cleanup; added change-5 migration category. The original remains available. This is a transparent repair, not grounds to pretend the repaired instrument enjoyed pre-session independence. No evidence here establishes that the original file was secretly rewritten.

### Why the original totals do not measure prune correctness

S4:9 requires `--retain-ms >= 1000`. All original service categories use 300/500; every target rejects startup with exit 2 (`RAW/e6-*-defects6-sealed.txt:1–6`). Thus six printed failures per target are invalid fixture starts, not six implementation causes. Only the bench category reaches its checks. Original `defects6.py:315–329` catches category exceptions and never makes defects a failing process exit; exit 0 in the run log is not a pass.

### Corrected malformed-prune selection is still broken

`ES/defects6b.py:195–219` searches arbitrary files for the last substring `prune`, selects a tail, then seeks a four-digit number. This is not selection of a typed prune record's cutoff. Mo/morun select `b'pruned": 2}\n'`; Python selects `b'prunes":1}\n'` (`RAW/e6-{mo,morun,python}-defects6b.txt:49`). The intended cutoff lies elsewhere. The suite records its own locator failure as a defect and skips the subsequent malformed-cutoff refusal/restoration checks. Go/Elixir reach those checks. A zero “harness preconditions failed” counter therefore does **not** establish an error-free harness or equal assertion opportunities.

### An older Python fixture also changes the property under test

`ES/defects2.py:68,127–135` intends to write a queued job carrying a worker. `CR8/oracle4.py:70–77` unconditionally replaces Python's worker with `None` before serializing it. Python accepts a now-valid fixture, and the suite prints two failures. Y:`jobs.py:232–260` and `store.py:542–579` do reject the illegal native record. An independent direct native-format probe confirmed refusal. **Do not carry these two Python assertions into a product-defect ledger**, even though they recur in the generation-five rerun.

The Mo writer retains the field (`CR8/oracle4.py:50–54`), so this does not excuse the Mo result.

## 2. Printed outcomes, not deduplicated causes

Each cell is `passed / printed defects`. The final Python `defects2` rerun is used, not its initial CLI usage failure. Parsed all 40 final target/suite files and checked that each contains a summary. Mo binary and interpreter are two execution modes of one program, not two language samples.

| Target | regressions | defects1 | defects2 | defects3 | defects4 | defects5 | original 6 | corrected 6b |
|---|---|---|---|---|---|---|---|---|
| Mo binary | 121/0 | 189/0 | 64/2 | 55/0 | 80/0 | 94/0 | 4/6 | 92/3 |
| Mo interpreter | 121/0 | 189/0 | 64/2 | 55/0 | 80/0 | 94/0 | 4/6 | 92/3 |
| Go | 121/0 | 188/1 | 66/0 | 55/0 | 79/1 | 92/2 | 4/6 | 95/2 |
| Python | 121/0 | 189/0 | 64/2 | 55/0 | 80/0 | 94/0 | 2/8 | 90/5 |
| Elixir | 120/1 | 128/1 | 63/2 | 53/2 | 79/1 | 94/0 | 4/6 | 95/2 |

Summary cross-check: `RAW/e6-suites.out:5–42,48–52,58–94,99–138,144–179,185–220`; individual corrected summaries at `e6-{mo,morun}-defects6b.txt:97–101`, Python:100–109, Go/Elixir:99–102.

### Cause adjudication

**Mo carried malformed-record validation gap.** Both engines accept a queued record with a worker but no lease deadline and fail the follow-up diagnostic assertion (`RAW/e6-{mo,morun}-defects2.txt:36–37,71`). Change-5 reruns reproduce this. M:`job.mo:503` tests equivalence between Leased and **both** worker and deadline present; a queued worker-only record passes that expression. `job.mo` is byte-identical to the compared change-5 ancestor. This is **one carried cause**, not two new defects and not a language-law catch.

**Go validation.** Explicit null delay and null key are accepted (`RAW/e6-go-defects1.txt:34`, `defects4.txt:22`); G:`api.go:193–222` conflates missing and null pointer fields. An overlong 129-byte handoff recipient is accepted and changes the holder (`defects5.txt:21,23`), one initiating cause with two failed assertions. G:`queue.go:938–940` calls a worker validator allowing 256 bytes (`job.go:29,252–258,305–306`), whereas S5:36 limits this route to 128. No complete earlier-generation cause inventory was reconstructed to certify the baseline carryover clause of P1.

**Python bench and representation.** The bench fails on the Mac because Y:`benchmark.py:104–109,219–241` unconditionally reads `/proc/<pid>/status` (`RAW/e6-python-defects6b.txt:92–97`). Two assertions reflect one portability failure. Its small bench also creates 296 of the requested 300 jobs and drains the shared population before the later pair phase (`benchmark.py:141–169,223–228`), explaining the printed zero later-worker work.

Separately, S6:35 says compaction keeps no rename record **and no count**. Y:`store.py:652–668` explicitly preserves rename counts in archive entries and the counter record. A direct real-Store compaction returned `(1, 1)` and left `{"kind":"counter","next_number":2,"renames":1,"prunes":1}`. This is a literal representational mismatch, not evidence of resurrection or corruption. The text does not equally explicitly ban a prune counter; I do not invent that second prohibition. This finding is outside the corrected suite's printed failures.

**Elixir older-suite limitations.** Space-containing token acceptance has source support (`RAW/e6-elixir-regressions.txt:5`; X:`router.ex:288–302`). Duplicate retention flag acceptance is explicit last-wins behavior (`defects4.txt:7`; `cli.ex:294–306`). The old-service setup's `max_attempts` versus required `max_tries` mismatch aborts migration coverage (`defects1.txt:132`; CR8:`defects.py:306–309`). The large-body BrokenPipe, RAM-disk startup failure, and failure-window exit need separate transport/environment adjudication (`defects2.txt:18,67`; `defects3.txt:55–56`); they are not all proven new archive defects. A service exit plus absent health is not two independent restart causes.

### `/queues`: preserve the specification conflict

All targets fail two corrected assertions: the archive-only reused queue `a` is absent, and the archive-only `s3` is absent (`ES/defects6b.py:263–272,303–314`; Mo/morun/Python raw:60,79; Go/Elixir:62,81). By-ID, keys, rename boundaries, and replay checks nearby pass. All programs derive queue tallies from live state (M:`board.mo:453–459`; G:`queue.go:1249–1277`; Y:`queue.py:366–373`; X:`queue.ex:568–584`). This is one common listing-policy behavior, not two distinct corruption causes.

S4:19 says `/queues` and `/jobs` listings never show archived jobs. But the **later** S5:55–63 says a name with a job in any state, including archived, is “the same as `/queues` listing it,” and says rename makes `/queues` show the destination. S6 inherits prior requirements unless changed. A list of queue names with zero live counts could honor archive exclusion while also honoring the later existence sentence; therefore the S4 sentence alone is **not sufficient to dismiss the failures conclusively**.

My literal reading of the later existence sentence supports a shared archive-only-name omission; the live-count-only interpretation supports all four implementations instead. I retain this as **one common specification-level discrepancy per program, interpretation explicitly disputed by the text**, not an established language-specific advantage. Under either consistent treatment it affects all four equally. Clarify the contract prospectively; do not silently rewrite the old oracle or counts. This judgment supersedes a narrower delegated interpretation that would have discarded the assertions solely from S4.

## 3. P1–P7, assessed separately

**P1 — not met as written.** Mo was predicted to have zero under every earlier suite (P:291). One real carried cause produces two failures in each Mo mode. “No new Mo cause demonstrated” is true but is a different threshold. Python's superficially identical two failures are a writer artifact. The bounded bundle's generation-five correction concerns `defects2`, not a complete cause-by-cause baseline history; I do not certify every baseline's “at most one beyond carried” clause.

**P2 — no valid sealed-instrument comparison; corrected results are limited.** Original service comparisons fail on invalid startup parameters. Corrected raw Mo 3 versus Go/Elixir 2 is not evidence Mo has more product causes: one extra Mo assertion is a failed mutation locator, and the two shared listing failures have the interpretation above. On exercised, adjudicated behavior, no Mo-specific new prune defect is established; Python has a bench portability defect. This is consistent with the intended relative prediction, but unequal malformed-cutoff coverage and the late correction prevent an unqualified pre-registered pass. The additional source-found Python counter mismatch is not retroactively a seventh-suite catch.

**P3 — predicted contrast not observed.** Every corrected target passes its process-kill subset. The outputs report every acknowledged ack read: Mo binary 3062, interpreter 1820, Go 76, Python 2786, Elixir 2591 (`RAW/e6-{mo,morun,python}-defects6b.txt:50–56`, Go/Elixir:52–58). No predicted baseline loss appears.

The new predicate correctly requires a 200 response **and** done/archived state (`ES/defects6b.py:60–62,255–257`), unlike the original conjunction bug and first-200 sample. Limits remain: one timed kill; no demonstrated mid-record location; the all-or-none check does not require all-gone when the prune response succeeded; kept-key coverage is conditional; total-count tolerance is not identity-level verification; worker threads are not explicitly joined before lists are inspected (`:243–259`). In the actual outputs the freed-key check executes, supporting all seeded old jobs gone in these runs. This is useful bounded evidence, not a general durability proof.

**P4 — unproven; neither required coverage nor predicted contrast established.** All added change-5 migration subsets pass (`RAW/e6-{mo,morun,python}-defects6b.txt:85–91`, Go/Elixir:87–93). They show new programs opening the generated old folders and preserving sampled counts, names, keys, and leasing. They do not repeat the full fresh-folder sequence on that old folder: no prune, subsequent ack, or full listing/archive sequence there (`ES/defects6b.py:326–349`). The fresh sequence compacts well before its kill, which occurs after reopen and later writes (`:289–323`), not between compacted-file rename and directory fsync as S6:39 requires.

Mo's own report acknowledges this gap (`REPORT/mo-REPORT-change-6.md:348–350`, toolchain report:144–157; M:`sequence.py:22–27`). M:`store.mo:257–274,293–310` has write/rename calls but no explicit folder-sync operation. This is a missing demonstrated requirement, not a proved power-loss outcome. Go and Python have explicit directory-sync source paths; Elixir also syncs rewritten directories (G:`store.go:262–266,332–335,399–413`; Y:`store.py:636–649`; X:`store.ex:484–491`). Their presence is not the requested exercised interruption.

**P5 — supported at the self-report level.** Mo reports **29** loops; Go **8**. Python reports **9 failed runs**, Elixir **18** (`REPORT/mo-REPORT-change-6.md:157–185`; Go:19–35; Python:57–80; Elixir:163–205, with WIP reports). Categories mix tooling, formatting, test mistakes, repeated failures, process slips, and product edits; first-fix rates or unique product causes cannot be reconstructed by summing them. Mo reports about 91 working minutes versus Go about 102; P5 predicts loops, not elapsed time or a language-only causal effect.

**P6 — not met by filed evidence.** Source adds one `never` for pruning a live/too-young job (M:`board.mo:26–30,118–123,1006–1024`), satisfying the addition half. The maintainer says it **did not trip** (`REPORT/mo-REPORT-change-6.md:298–309`). A deliberate age `test rejects` is a `requires` event, not a wrong-edit never catch. Existing queue metadata saying an invariant tripped is associated with intentional chaos/restart tests (`M:queue.mo:279–281,546–548,1676–1701`), not evidence of a newly discovered wrong edit. No unique language-catch credit follows.

**P7 — optimization supported; complete prediction not met.** The actual Mo diff replaces the hot full finished-job postcondition with cached `looks_due?` checks (ancestor `board.mo:441–445`; M:`board.mo:474–502`), retaining the full walk in the shelving path (`:512–521`). This is an `ensures` optimization, not a never/invariant catch. Correctness now relies on cache/set correspondence; a stale cache evading the guard is an untested concern, not an observed defect.

The supposedly blind discovery is contradicted by **S6:3 itself**, which names the nine-times slowdown and postcondition walking every finished job. S6:31's later “only by the budget” sentence does not erase that disclosure. Both brief scripts direct the maintainer to this page; the resumed brief also supplies the predecessor report. Finally, the speed evidence is from a busy Mac, not the registered quiet VM; the Go 30,000-job pairs row falls below 0.8. Favorable Mo ratios do not establish the full P7 conjunction or every baseline's unchanged-budget clause.

## 4. Persistence mechanisms: what the source corroborates

The corrected positive results have concrete implementation support, not just optimistic labels:

- G:`queue.go:1121–1192` records one prune with cutoff/count/archive boundary before forgetting jobs, scopes replay to earlier archive bytes, and checks the removal count. `store.go:371–450` handles paired compaction temporaries/recovery.
- Y:`queue.py:585–608` persists archive marks and the prune before changing memory. `store.py:166–174,284–332` validates cutoffs and applies prune generations in order. Its replay count check is an upper bound accommodating interrupted compaction, **not exact equality**.
- X:`store.ex:225–286,371–408,611–612,648–652` orders archive/replay pruning and writes tombstones before dropping prune records during compaction. Shape validation is visible (`prune.ex:59–72`); an exact count equality check is not established.
- Rename ID boundaries are explicit in G:`queue.go:1009–1015,1068–1104`, Y:`queue.py:517`, `store.py:245–283`, and X:`store.ex:633–642,995–996`. The observed archived identities survive name reuse/restarts/compaction. Exhaustive equivalence for every possible legacy folder is not established.

These checks do not certify every declared error path or every crash schedule. A passing supplied test and a reasoned recovery mechanism are evidence with finite scope.

## 5. Speed conditions and instrument limitations

`ES/e6-speed-mac.sh:6,9–18,22–27` sets `MO_CORES=1`, builds both Mo generations with the same compiler, and calls `CR8/measure.py` at 30,000 jobs. This controls a Mo runtime setting, not universal CPU affinity. Mo/Python/Elixir get two rounds; Go gets only one at this workload, despite the script header's blanket alternating description. All eight build statuses and all 14 measure-run exits in `RAW/e6-speed.txt` are zero.

The log begins with **load 6.38 / 5.74 / 5.48** and active WindowServer, Zoom, and Notion (`:1–2`). The index also discloses a VM memory failure, resumed Mac sessions and concurrent work. This differs materially from P:287's quiet-machine setup. It is not a fair basis for causal maintenance-time or universal cross-language speed rankings.

Ratios below are independently computed from printed integer rates, change 6/change 3, matched rounds, rounded to four decimals; they are not confidence intervals:

| Program | Creates ratio, round 1 / 2 | 32-worker pairs ratio, round 1 / 2 |
|---|---|---|
| Mo | 1.5976 / 1.0374 | 1.3079 / 1.0063 |
| Python | 1.1533 / 1.0099 | 1.2476 / 1.0638 |
| Elixir | 1.1959 / 1.1657 | 1.2233 / 0.9909 |
| Go, one 30k round | 0.9444 | 0.6635 |

Raw source: `e6-speed.txt:13–15,37–39,61–63,85–87` (Mo), `21–23,45–47,69–71,93–95` (Python), `29–31,53–55,77–79,101–103` (Elixir), `109–111,117–119` (Go). Go's 32-worker rates are **104/s → 69/s**. The three later Go rounds switch to **5,000 jobs** and report 101→100, 67→108, 99→95 pairs/s (`e6-speed-go-again.txt:1–41`), without individual exit statuses. They demonstrate variability under a changed workload, not cancellation of the failed 30k budget row.

Further instrument limits:

- `measure.py:54–63` prints intended creations, not completed successes. Transport exceptions in producer threads bypass `errs`. A labelled mock of the unchanged create prefix with eight throwing producer threads printed **“creates: 8 ... errors []”** while eight uncaught thread exceptions were counted. This verifies a harness weakness, not a failure of these filed program runs; their logs do not show such exceptions. Pair threads likewise lack exception aggregation (`:67–80`).
- Health/restart readiness ignores response status, and a restart timeout still falls through to a printed “to /health” duration (`:45–51,89–96`). Exit zero alone does not certify semantic success.
- The single-worker phase consumes the same population before the 32-worker phase. Fast programs drain 7,504 then 22,496; Go reaches the time limit with a backlog. Restart/RSS rows therefore reflect different completed work across languages, not a uniform terminal state.
- RSS uses Linux-style `ps --ppid`, limited descendants and a maximum rather than a process-group sum (`:27–36`). Mac process attribution is not established. Treat Python's nearly flat 27 MiB row as unverified service memory, not a measured memory advantage.
- Builds log status without aborting in the speed script; no failure accumulator exists. All filed builds succeeded, so this is a latent instrument weakness, not an observed stale-build substitution.
- E:`toolchain/src/blocking.zig:93–118` and `runtime/mo_rt.c:8286–8308` call plain `fsync`. The locally inspected Go 1.27.1 Darwin implementation uses `F_FULLFSYNC` with an ENOTSUP fallback. This supports a possible durability-cost mismatch, not a traced claim about the exact Mac binary/mount. Neither cross-language disk-durability equivalence nor hardware-power-loss survival was measured. Within-language comparisons are more defensible than attributing the absolute Go/Mo gap to language speed.

## 6. Runner outcomes and containment

`ES/e6-suites-mac.sh:13–19` checks seals and stops on failed builds; `:57–64` records suite statuses, timeout/missing-summary conditions, and output. The initial Python `defects2` usage error is explicitly exit 2 with no summary (`RAW/e6-suites.out:11–13`); the corrected invocation reruns it at 10:42:18 (`:44–53`). The original generation-five usage failures likewise provided no tests; the filed reruns are new evidence, not a reason to backdate an earlier clean result.

However, suite failures are logged, **not accumulated into a failing runner exit**. ONLY mode exits 0 and normal mode ends with `say done` (`runner:66–75`). Earlier suites also print failures with exit 0. Any acceptance consumer must read both summaries and exit statuses. The corrected suite does return 1 on its recorded failures; that is an improvement, not an end-to-end runner fix.

The watchdog at `:45–55` selects descendants, but begins after builds and limits individual-process RSS, not aggregate memory. Cleanup at `:63` still uses broad `pkill` patterns; the corrected suite also has broad cleanup (`defects6b.py:384`). “Descendant-only” describes the watchdog, not all cleanup. This audit did not execute those cleanup paths. A proposed additional delegated mock of runner behavior was blocked by withdrawn approval and was not retried; runner propagation findings are static, corroborated by the filed logs.

## 7. Auditor-owned language-rule ledger: generation six

The ratified L-2 single-tier rule, not the superseded tie-with-tests tier, binds: at generation ten, at least two unique-only catches, FP at most 1.5× catches, density at most 5/1,000. Any failed threshold automatically maps to R-B. Density over 10 or FP over `max(3 × catches, 3)` escalates R-A to Robert (RULE:15–37). This is not a generation-six retirement vote.

| Entry | Generation-six value and qualification |
|---|---|
| New Mo never/invariant catches no test/other mechanism caught | **0 established** |
| Wrong-edit trip supporting P6 | **None established**; added prune law explicitly reported not tripped |
| New false positives | **0 evidenced**, not a complete reconstructed zero |
| FP/catch ratio | Undefined with zero established catches; do not report a favorable numeric ratio |
| Test-only unique Mo causes over this new window | **Not established as a complete total**; one carried validation cause independently confirmed by outside tests, not one new edit cause |
| Shipped declarations | **14 never + 2 invariant = 16**, one never added since the compared change-5 source |
| Physical shipped Mo LOC | **8,630** |
| Current density | **1.8540 per 1,000 physical shipped lines** |
| Cumulative unique-only catches established in the 6–N window | **0 at N=6** |
| Decision | Carry forward; neither vindication nor early R-B/R-A |

Count method: all tracked `.mo` files under M:`examples/programs/jobq/`, declaration lines anchored to `never`/`invariant`, inspected to exclude prose. Physical file counts: api 718; bench 267; board 2692; job 953; main 1132; queue 1702; server 529; store 637. Declarations: board 5, job 6, queue 1 never + 2 invariants, store 2. Parent independently recomputed totals from Git blobs.

The denominator contains inline tests, comments and blanks. Delegated sensitivity checks give 2.2213/1,000 on 7,203 nonblank/non-comment lines; removing top-level test/property blocks gives 16/5,647 physical lines = 2.8334/1,000, or 16/4,220 nonblank/non-comment lines = 3.7915/1,000. Those still include helpers and are not exact production-reachable LOC. All these conventions are below 5, but the rule's generations-6–10 density aggregate is not yet available. Preserve the explicit convention; do not switch it opportunistically.

Neither the known compact/rename ticket, an `ensures` performance edit, ordinary bad-record validation, nor intentional chaos/test-rejection trips earns a unique-only catch. A complete test-only cause ledger needs wrong-edit snapshots and diagnostics, not self-reported loop-category totals.

## 8. Independent checks actually performed

In a dedicated auditor clone; no project source changed:

1. Verified local/remote entry main, fetched exact final commits, compared relevant evidence/instrument paths against E, checked original/corrected blob hashes and chronology, parsed 40 individual final suite summaries, independently recomputed density and speed ratios.
2. Ran `PYTHONDONTWRITEBYTECODE=1 python3 mo-wiki/plans/erosion-round-suite/defects6b.py --selftest`: both G6-1/G6-2 controls print `ok`, exit 0. The FIFO control is illustrative list logic, not a live service test. Ran `bash -n` on the suite runner successfully.
3. Extracted final baseline source outside the repository. Parent re-executed `go test ./jobq -run 'Prune|Rename|Compaction' -count=1`: **`ok controlrun/jobq 0.330s`**, exit 0.
4. With CPython 3.14 and pydantic supplied through uv, parent re-executed `PYTHONPATH=src:tests uv run --no-project --python 3.14 --with pydantic python -m unittest test_change6.PruneTest test_change6.PruneReplayTest test_change6.RenameNextIdTest test_change6.CompactionKillTest test_change6.DeclaredErrorTest`: **40 tests in 0.328s, OK**, exit 0. These are supplied implementation tests, not new hidden coverage.
5. Parent inspected and reran a direct Python native-record probe: queued-with-worker refused by `Store.open`; `PruneRecord.model_validate` refuses cutoff `'bad'` and `-1`; actual `compact` preserves the rename/prune counter fields. The cutoff checks are schema checks, not an exported-service replay campaign. A synthetic selector trace demonstrates the metadata suffix mismatch. An earlier delegated scratch probe used the wrong filename and was discarded; only the corrected `jobs.log` probe is credited.
6. Executed the labelled AST-extracted speed-create-prefix negative control described above. It runs real threads with mocked server dependencies and proves only failure accounting in the harness. It is not fabricated jobq evidence.
7. Source-reviewed the actual Mo law/sweep/validation diff and baseline persistence paths. No new Mac, full-suite, Elixir, Mo-binary or Mo-interpreter execution is claimed.

## Standing concerns and what would change this reading

- **Instrument accounting:** use format-aware record mutations, verify the intended invalid field survives serialization, separate fixture failures from product failures, and propagate nonzero/incomplete suite outcomes through the runner. Keep old output immutable. This would resolve P2's unequal negative coverage.
- **Persistence coverage:** exercise the full named sequence on an old-generation folder and demonstrate the actual rename-to-directory-fsync interruption, with explicit platform semantics. It would resolve the present P4 gap; ordinary post-reopen kills cannot.
- **Contract tension:** resolve archive-only queue-name visibility and whether Python's retained rename count is permitted. Until then preserve the literal text and shared discrepancy, not a silently favorable scoring rule.
- **Comparable cost:** rerun matched 30,000-job workloads on a quiet, identified machine with pinned toolchains, process attribution, durability policy and correct benchmark failure accounting. Retain the unfavorable Go 30k observation rather than replacing it with a smaller post-hoc workload.
- **Law evidence:** supply wrong-edit snapshot, input, named diagnostic, repair, and same-input test/runtime comparison for any claimed exclusive catch or false positive; publish a deduplicated test-only cause ledger separately from loops.

**Candidate falsifier:** in a subsequent pre-registered generation, challenge the cached due-marker/finished-job correspondence with a change-induced stale marker while retaining the relevant laws and normal tests. Record whether a never/invariant alone detects the wrong edit, or whether the tests catch it while the laws remain silent. The latter outcome adds no exclusive-catch credit; if the cumulative exclusive count remains below two at generation ten, the ratified rule requires R-B regardless of favorable throughput. This is a proposed future check, not an experiment performed here or a newly authorized engineering task.

No stopping-rule threshold is amended by this reading. No lead comparison has been performed. Integration and any unresolved contract/rule decision remain outside the auditor's unilateral authority.

# Evidence: generation six of the erosion round (change 6 to `jobq`), 18 Sep 2026

Raw pointers and outputs, in the charter's form. Fable's readings are named at the end and marked: open after your own.

## What ran

- The change: `mo-wiki/spec/programs/01g-job-queue-change-6.md`, sealed 18 Sep 2026, 4:16 AM ET.
- The pre-registration (P1 to P7): `mo-wiki/plans/erosion-round.md`, section "Generation six, pre-registered", as of `48640d3`.
- The briefs as sent: `mo-wiki/plans/erosion-round-suite/e6-brief.sh` (the VM, four sessions, 4:45 AM ET) and `e6-brief-mac.sh` (Robert's Mac, three resumed sessions, 9:23 AM ET).
- The branches and final commits: `commits.txt` (`erosion6-{mo,go,python,elixir}` on origin). Work-in-progress commits from the VM sit under each final commit.
- The maintainers' reports as written: `reports/` (final and work-in-progress; the Mo maintainer's `TOOLCHAIN-BUGS.md`).
- The panes of the Mac sessions as read at their end: `panes/` (Mo, Go, Elixir). The VM sessions' panes were not saved before the VM sessions were stopped.

## The suites

- Sealed before the sessions: `mo-wiki/plans/erosion-round-suite/defects6.py`, sha256 prefix `d4dab05cc331b7fa` (`48640d3`). Run exactly as sealed.
- Corrected after your reading of the execution and one further defect Fable found (`--retain-ms` under the spec's minimum in all 19 server starts): `defects6b.py`, sha256 `183a992cb6893ca8c4c2e34b3190a3fc90c02619f2e17e7010844368ff675c73`, committed at `346e875` before any suite ran on a generation-six program. `python3 defects6b.py --selftest` runs its two negative controls.
- The runner: `e6-suites-mac.sh` (hashes checked at the start, a failed build stops the run, every exit status written, a 4 GB watchdog over its own descendants). Its first Python pass ran `defects2.py` without `--log-format` (exit 2, written down as such); the runner was corrected and that suite rerun (`ONLY=defects2`).
- Raw outputs, one file per program per suite: `raw/e6-<lang>-<suite>.txt`, the builds' outputs, the watchdog's, and the summary log `raw/e6-suites.out` (dates, load averages, commits, exit statuses).

## The correction to generation five

- `raw/e5-{go,python,elixir,mo,morun}-defects2.txt`: the five usage errors of 16 Sep (the third suite never ran in generation five).
- `raw/e5-rerun-*`: the same suite run today on the generation-five programs (`erosion5-*`), with `raw/e5-rerun-suites.out`.

## Speed

- `mo-wiki/plans/erosion-round-suite/e6-speed-mac.sh` and its output `raw/e6-speed.txt`: change 3 and change 6 of each program, alternating, `control-run-8-suite/measure.py`, 30,000 jobs, `MO_CORES=1`; the head of the file has the date, the load, and the top of `ps` (the Mac was in use by Robert; nothing else of the lead's ran).
- `raw/e6-speed-go-again.txt`: three more alternating Go rounds at 5,000 jobs, run because the first Go row showed change 6 at 0.66x on pairs.
- The source lines behind the `fsync` finding: `toolchain/src/blocking.zig:114`, `toolchain/runtime/mo_rt.c:8303` (plain `fsync`; no `F_FULLFSYNC` anywhere under `toolchain/`).

## Conditions to know

Two machines (a 4-core Linux VM, then an M3 Max Mac); the VM wedged at 5:21 AM ET on a 13.4 GB `mo` process and was restarted at 8:30; Python's maintainer is one uninterrupted VM session, the other three are three segments each; on the Mac step 38's worker ran beside the maintainers (load 4 to 8 all morning); the suites ran one program at a time but never on a quiet machine.

## Fable's readings (open after your own)

`audit/fable-reading-2026-09-18-generation-six-execution.md` (filed before yours); the result section on `mo-wiki/plans/erosion-round.md`; the decision-log rows of 18 Sep on generation six, the third-suite correction, `fsync` on macOS, and the `/queues` sentence.

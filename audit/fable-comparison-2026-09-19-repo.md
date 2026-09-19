# Lead comparison: PR 15 repository audit

Fable (Claude Fable 5.1, Claude Code, project lead), 19 Sep 2026, 1:21 PM ET.

The lead's reading `audit/fable-reading-2026-09-19-repo.md` was committed on
`main` at `f0b99fe4` before the auditor's reading, its `state.md` change or
`core/REPORT.md` were opened. The auditor's
`audit/mo-audit-2026-09-19-repo.md` is anchored at `8342cfe0` (this morning's
`main`, x86_64 Linux). Neither is a cold reading; the lead had read the PR's
raw probe files and outputs, as its reading discloses. No hidden suite or seed
was opened.

## Disposition

**Agree with the verdict. Every finding conceded; no disagreement is open.**

| Finding | Lead disposition |
|---|---|
| F1, literals past their type | Conceded, reproduced on current `main` on Darwin in `check`, `mo run` and native. The lead's probes extend it: a 54-digit `UInt64` literal prints `170141183460469231731687303715884105727`, a number not in the source (`parseInt` saturates an `i128` at `bytecode.zig:1709` and `emit_c.zig:1366`), and `Int8` with leading zeros prints `200`. High is the right rank: it is the language's own sentence ("overflow is never implicit") shown false. |
| F2, mailbox bound | Conceded, reproduced (exit 134 on Darwin). Lead probes add: 4294967295 and 0 are accepted silently and neither is specified; a 26-digit bound panics the same way. |
| F3, fuzz budgets | Conceded on the mock as labelled. Joins the instrument fixes. |
| Failed-batch repair | Agreed as narrowly stated. |
| Standing 1, no completed full suite | Conceded. The lead's Darwin full suite was 249 of 249 at step 40's acceptance today; that is the lead's run, not a reproducible gate, and it takes longer than ten minutes. The first x86_64 Linux full run is in progress on the VM. |
| Standing 2, no CI gate | Conceded, owed since 18 Sep. |
| Standing 3 and 4 | Agreed. The executor logs describe the anchor; steps 1 and 2 have since landed. |

Two things in the lead's reading that the auditor's does not carry: the
`neg-duration` probe in the PR's evidence is refused by the checker and shows
nothing either way (the auditor rightly made no finding of it); and the suite
writes generated files into the source tree (`cleanup.json`), which also cost
the lead a run today. Neither is a disagreement.

## What follows

One toolchain fix brief, RED first, `mo-wiki/plans/interpreter-step-43.md`:
F1, F2, a sweep of every number the compiler parses from source, and F3's
budget validation. The CI gate stays on the queue as its own item. PR 15 is
merged unchanged; integration accepts no code.

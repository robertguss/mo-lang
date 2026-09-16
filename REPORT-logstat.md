# logstat regenerated: the worker's report

Every function body in `examples/programs/logstat/` was written again from the modules' intents,
types, signatures, contracts, and tests, plus `mo-wiki/spec/programs/02-log-analyzer.md`. The
tests were not touched: the only lines the diff removes are the `# body gone; regenerate` markers.

## Done-when

- `mo check` and `mo test` green on `parse.mo`, `stats.mo`, `report.mo`, `main.mo`:
  6 + 10 + 7 + 8 = 31 tests, 0 failed, 0 skipped (`mo test --all main.mo` runs all 31).
- All four `# run:` lines of `main.mo` match their `.expected` file byte for byte
  (`cmp`), with the exit code the `# exit:` line asks for: text 0, JSON 0, `--top 0` 2, `.` 1.
- `mo test --write --sim 100` has rewritten the four `verified:` lines and the
  `examples/programs/.mo.ids` sidecar.

## Wall-clock

11 minutes 22 seconds, 23:49:53 to 00:01:15 UTC on 15–16 Sep 2026, from the first read of
`examples/README.md` to the last green run. About seven of those minutes were reading:
`examples/README.md`, chapters 2, 4, and 9 of the spec, the program spec, and the corpus files
`stdlib/{strings,numbers,lists,maps,time,files,json}.mo`, `basics/{if,tuples,result,option}.mo`,
`programs/{count-lines,exit-code,lines-per-file}.mo`, and `logstat/TOOLCHAIN-BUGS.md`.

## Loops to green, by cause

One loop. Every other `mo check`, `mo test`, and `mo run` passed the first time it was run.

| # | file | diagnostic | what it was | first fix worked? |
|---|---|---|---|---|
| 1 | `stats.mo` | `MO0403 Time.fixture() is a Time for tests; outside a test, take a Time parameter instead.` | `sample`, the test fixture builder, is an ordinary module function, so it may not call `Time.fixture()` | yes: `Time.from_parts(2026, 1, 1, 0, 0, 0)`, the same instant, written out |

Per module: `parse.mo` 0 failures (check and test green first run), `stats.mo` 1 (the row above),
`report.mo` 0, `main.mo` 0. The four program runs matched their `.expected` files on the first
attempt, so no loop came from the output format.

The diagnostic that earned the loop was exact: it named the call, said why it is test-only, and
named the fix (take the instant as a parameter). The one that would have misled is the one that
never fired — `MO0403` is raised where a module function calls a test-only row, so the rule is
learned at the point of use, not from chapter 9's table, which marks `fixture` "tests only" in a
column a reader skims past.

Bodies: 59 functions, longest 15 lines (`stats.add`, `main.main`), median 4. No shape law was hit
(70 lines, 6 parameters, depth 3). No stdlib or platform name was missing, so `examples/GAPS.md`
gains nothing: `String.grouped`, `sort_by_desc`, `Map.update`, `Fs.fold_lines`/`list`, and
`Json.encode` over a struct each did exactly what a body needed — the gaps program 2 found in
earlier rounds are already closed rows.

## Decisions the spec did not cover

1. **Where the rounding happens.** `summarize` rounds `error_rate` to three decimals and
   `per_minute` to one, and every reader of a `Summary` prints what it holds. The spec's JSON
   example (`0.031`, `40.1`) fixes the shape but not the place, and `Json.encode` writes a
   float's own shortest spelling, so an unrounded `0.16666666666666666` would have reached the
   JSON report. The text report's `(18.8%)` is then `one_decimal(error_rate * 100.0)`.
2. **Nothing divided by nothing is 0.0.** `rate(0, 0)`, a tally holding no record, and every
   record in one instant are all `0.0` rather than a NaN or an error.
3. **A 4xx is a success.** Errors are 500–599, as the spec says, so `requests` splits in two and a
   404 is counted in `successes`. There is no third bucket.
4. **What a method is.** One or more capital ASCII letters, so `get` is `BadMethod` and `PATCH` or
   any verb a future log carries parses. No fixed list of verbs.
5. **What a path is.** It must begin with `/` and hold no `"`, and nothing else is refused: a path
   is text between two spaces, and the quote is refused because the JSON report quotes it.
6. **Fields are checked left to right.** A line wrong in two fields names the leftmost problem
   (timestamp, then method, then path, then status, then duration).
7. **Fields are split on single spaces, empty pieces kept.** So `""` is one field, a double space
   makes six, and a date written `2026-09-12 10:00:02` is six fields, not a bad timestamp.
8. **Sixteen digits *or more* are starred whole**, and masking keeps the path's length, so a
   17-digit run becomes 17 stars. Masking happens at parse time, so the masked path is what the
   tally counts: the fixture's `4111111111111111` and `5500000000000004` on the same route become
   one busiest row of 2, and no unmasked path exists anywhere downstream to leak.
9. **How the two orders are got from stable sorts.** `slow_key` is
   `(4_294_967_295 - ms, at)`, so one ascending stable sort gives duration descending and, at one
   duration, the earlier request first. `ranked` sorts twice instead — by `(path, method)`
   ascending, then by count descending — because a stable descending sort keeps the ascending tie
   order, and a count is a `UInt64` with no comfortable complement to subtract from.
10. **The span is the minimum and maximum timestamp of the records counted**, not the first and
    last line read, so files listed in name order with lines out of order still give one answer.
    A record before `--since` is no part of the span; a malformed line is counted whatever it
    would have said, since it has no readable time.
11. **A line of only whitespace is skipped**, as an empty line is, rather than counted malformed.
12. **A name is a log when it ends in `.log` and is longer than four characters**, so a file named
    exactly `.log` is not one, and `logged` sorts the names it keeps.
13. **The folder is listed by name, not by kind.** `logged` takes names, so a *folder* named
    `x.log` inside the directory would be read and reported `logstat: x.log cannot be read`,
    exit 1, rather than skipped. `list_kinds` would skip it; the signature under regeneration
    does not carry the kind.
14. **Every `Fs` call waits at most 10 seconds.** The spec sets no deadline, and the law requires
    one; the test that expects `Slow` from `Fs.fixture(delay: 1.minute)` requires it to be under a
    minute.
15. **Exit codes past the spec's three.** A file that cannot be read, and any read or listing past
    its deadline, exit 1 with one line on stderr. Only a usage error exits 2.
16. **What stderr says.** One line, `logstat: <detail>`, and the usage line is
    `usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]`. A missing directory argument
    prints the usage line; every other usage error prints what was wrong with the argument.
17. **A repeated flag takes the last value** (`--top 3 --top 9` is 9). No test asks, and neither
    does the spec.
18. **The text report's columns are measured, not fixed.** The label column is the widest label
    and the value column the widest value, right-aligned; the slowest section puts three spaces
    between the request and its timestamp, the busiest two between the count and the request. The
    `.expected` files and the section tests pin this; the spec's sample only suggests it.
19. **The JSON object is `Json.encode` of a struct.** `JsonSummary` and `JsonSlow` declare the key
     order, so the writer cannot drift from it, and `json` ends its line with `"\n"` as `text`
     does.

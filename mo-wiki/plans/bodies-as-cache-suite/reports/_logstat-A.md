# logstat regenerated: the worker's report

Every function body in `examples/programs/logstat/` was written again from the modules'
intents, types, signatures, contracts, and tests, against
`mo-wiki/spec/programs/02-log-analyzer.md`. The tests were not touched.

## Done-when

- `mo check` clean on `parse.mo`, `stats.mo`, `report.mo`, `main.mo`.
- `mo test`: 6 + 10 + 7 + 8 = 31 passed, 0 failed, 0 skipped; `mo test --all main.mo` is 31
  too. The same counts under `mo test --sim 100`.
- All four `# run:` lines match their `.expected` file byte for byte, with the exit codes the
  `# exit:` lines name (0, 0, 2, 1).
- `mo test --write --sim 100` has rewritten each `verified:` line; the four lines are
  character for character the ones the stripped commit removed, and the ids in
  `examples/programs/.mo.ids` kept their values (only the hashes moved, and only for
  logstat's four files).
- Beyond the Done-when: `mo fmt --check` is clean on all four; `mo build --tests` of each
  module prints exactly what `mo test` prints and exits as it exits; `mo build main.mo`
  gives a binary whose four runs match `mo run`'s stdout, stderr, and exit code.

## Wall-clock

13 minutes 26 seconds, 2026-09-15 23:49:52 UTC to 2026-09-16 00:03:18 UTC. About half of
that was reading the prelude, the stdlib rows, and eight corpus files before writing a line,
and running two scratch probe modules (both green first time) to settle what the stdlib
does: `String.grouped`, `"".split(" ")`, `String.lines` past a CRLF and a trailing newline,
whether `sort_by`/`sort_by_desc` are stable and take a tuple key, `Map` keyed by a tuple,
`pad_left`/`pad_right` when the text is already wider, `checked_to_u32`, `slice`'s bounds,
`Time.parse` on `2026-13-12` and `2026-02-30`, and `Duration.minutes`.

## Loops to green: 2

Every function body was written once. No `mo test` run ever failed, and no `# run:` line
ever mismatched its `.expected` file: the four modules' 31 tests and the four runs were
right the first time they were run. The two failures were both about the file's shape, not
its code:

1. **`mo fmt --check`, all four modules** — Mo wants a blank line between a function's
   contract clauses and its first statement, and it rewraps a few long argument lists. The
   first fix worked: I restructured `Report.json` by hand first (binding the slowest rows to
   a name) so the formatter's own wrapping stayed readable, then ran `mo fmt`. `mo check`
   never saw this; only `mo fmt --check` did.
2. **`MO0317` on `report.mo` and `main.mo`** — self-inflicted ordering: I re-ran `mo check`
   after the formatting pass but before `mo test --write`, so the `verified:` lines were
   stale, and `main.mo` was stale twice over because a module it uses had changed. The first
   fix worked: `mo test --write --sim 100` over the four files in dependency order
   (`parse`, `stats`, `report`, `main`), after which `mo check` was clean.

## Other measures the spec asks for

- **Stdlib or platform names missing: none.** Nothing had to go to `GAPS.md`. Everything the
  program needed was already in the prelude, including the three that would otherwise have
  been hand-written: `String.grouped` for the `1_204` separator, stable `sort_by` and
  `sort_by_desc` over a tuple key, and `Json.encode` over a struct, whose field order and
  `", "` spacing are exactly the spec's JSON line.
- **Lines per function (body only, contracts and comments not counted): max 20
  (`main.mo:step`), then 18 (`stats.mo:add`); median 4.5 over 42 functions.**
- **Diagnostics that helped:** `MO0317` named the function that had changed (`fn json`) and,
  for `main.mo`, said which *module it uses* had changed — that is the whole fix in one
  line. `mo fmt --check` printed a diff, so the shape law needed no lookup. Nothing misled.

## Decisions the spec did not cover

1. **Which methods are well-formed.** The tests demand that `get` be `BadMethod`, but the
   spec names no method set. `method_of` accepts the nine HTTP methods in upper case (`GET`,
   `HEAD`, `POST`, `PUT`, `PATCH`, `DELETE`, `OPTIONS`, `TRACE`, `CONNECT`) and nothing else.
2. **Which paths are well-formed.** The tests demand that `a` and `/a"b` be `BadPath`.
   `path_of` asks only that a path start with `/` and hold no `"`; it caps no length and
   refuses no other character.
3. **Where the mask is applied.** `parse_line` stores the masked path in the record, so
   every later reader — the busiest key, the slowest list, the text report, the JSON — sees
   only the masked form, and no unmasked path exists past parsing. One consequence shows in
   the fixture: two different card numbers under one route collapse into a single busiest
   row (`4111...` and `5500...` count together as 2).
4. **What "16 digits" means for a longer run.** A maximal run of sixteen *or more* digits is
   starred whole, one `*` per digit. That keeps `masked_cards`'s `result.size == path.size`
   and leaves no sixteen-digit run behind in a seventeen-digit one.
5. **`first` and `last` for "per minute".** The tally keeps the earliest and the latest
   timestamp counted, not the first and last seen. The span then never runs backwards
   whatever order the lines arrive in, which is what lets `per_minute`'s
   `requires first <= last` hold for any list of records, as the property demands.
6. **Whether `--since` filters malformed lines.** It does not: a malformed line has no
   timestamp to compare against, so it is counted as malformed whatever `--since` says. Run
   2's `requests` falls to 12 while `malformed` stays 4.
7. **The `--since` boundary.** "Ignore lines before T" is read strictly: a record exactly at
   T is counted.
8. **One error rate, two spellings.** `Summary.error_rate` holds the unrounded ratio. The
   text report prints `one_decimal(error_rate * 100)` and the JSON prints
   `error_rate.round(3)`, so `18.8%` and `0.167` come from the same number.
9. **`per_minute` in JSON.** Rounded to one decimal, matching the text report, since the
   spec's JSON sample shows `40.1`.
10. **The text report's column rule.** The spec shows one worked sample, not a rule. Each
    head row is the label padded right to the widest label, one space, then the value padded
    left to the widest value, with `  (N%)` after the errors row only. A slowest row pads the
    duration to the widest duration and `METHOD path` to the widest of those, with three
    spaces before the timestamp. A busiest row pads the count to the widest count.
11. **Empty sections.** The `slowest` and `busiest` headings are printed even when their
    lists are empty; the report's shape does not change with the data.
12. **What the one usage line says.** The spec asks for one line on stderr. It is
    `<what was wrong>; usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]`, so the
    reason and the usage are both in the one line.
13. **Which problems exit 1.** The spec names only "no `.log` file". A file that cannot be
    read (`Unread`) and a file system too slow to answer (`Slow`) exit 1 as well, each with
    its own line on stderr. Only a usage error exits 2.
14. **A directory that cannot be listed at all.** Treated as `NoLogs`, the same as an empty
    one — except a timeout, which is `Slow`. That is what makes `analyze(Fs.fixture(), …)`
    `NoLogs` and `analyze(Fs.fixture(delay: 1.minute), …)` `Slow`.
15. **How long a capability call may wait.** The spec names no bound: `within: 10.seconds`
    to list a directory, `within: 30.seconds` to read one file.
16. **`.log` alone is not a log file.** The test skips a file named exactly `.log`, so the
    rule is "a name longer than `.log` that ends in `.log`".
17. **Trailing whitespace on a line.** Each line is trimmed before parsing, so a CRLF file's
    `\r` does not make every one of its lines malformed.
18. **One summary, not one per file.** The `.log` names are sorted ascending and folded one
    file at a time into a single shared tally, so a directory prints one report.
19. **Ties in "busiest" past the path.** The spec orders by count then path; the module's
    comment adds method. It is count descending, then path ascending, then method ascending,
    written as two stable sorts.
20. **`ms_of` on text that spells no number.** Text that is not a number stands in as
    4_294_967_296, one past `UInt32`, so "not a number" and "too large for a duration" fall
    out of the same `checked_to_u32` and are both `BadDuration`.

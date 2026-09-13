# logstat

Program 2 (`mo-wiki/spec/programs/02-log-analyzer.md`) in four modules under the program root `examples/programs/` (`mo.root`):

- `parse.mo`, `Logstat.Parse`: one line to a `Record`, or a `Malformed` reason. A path's card number is starred here, so no record ever holds one (the module's `never`).
- `stats.mo`, `Logstat.Stats`: one file's lines at a time into a `Tally`, and the tally into a `Summary` (the `never` that requests are errors plus successes, and the property that errors never exceed requests).
- `report.mo`, `Logstat.Report`: a `Summary` as the text report or as one JSON object.
- `main.mo`, `Logstat.Main`: arguments, the scoped read-only `Fs`, and the `case` at the foot of `main` that is the error policy (exit 2 for a usage error, 1 for no `.log` file or an unreadable one).

`fixture/` holds three logs (`b.log` has three malformed lines and a card number in a path) and a `notes.txt` that is not read; `nologs/` holds no `.log` file.

## Program-level check

The corpus test runs `main.mo` once per `# run:` line from this folder and compares stdout with `logstat.expected`, `logstat-2.expected`, and so on. By hand:

```
cd examples/programs/logstat
for f in parse stats report main; do mo test $f.mo; mo fmt --check $f.mo; done
mo run main.mo -- fixture | diff logstat.expected -
mo run main.mo -- fixture --top 3 --json | diff logstat-2.expected -
mo run main.mo -- fixture --since 2026-09-12T10:00:45Z --top 2 | diff logstat-3.expected -
mo run main.mo -- fixture --top 0; test $? -eq 2
mo run main.mo -- nologs; test $? -eq 1
```

The expected files were computed by an independent reference script over the same fixture, then compared with what `mo run` prints.

## Decisions the spec left open

- **A line's fields** are split on spaces with empty pieces dropped, so a doubled space is not malformed; exactly five fields are required.
- **Timestamp** is what `Time.parse` reads (RFC 3339, `Z` or an offset). **Method** is one or more ASCII capital letters. **Path** starts with `/`. **Status** is ASCII digits, 100 to 599; **duration** is ASCII digits that fit `UInt32`.
- **A blank line** is malformed, like any other line that does not fit.
- **A card number** is a run of 16 or more ASCII digits; every digit of the run becomes `*`. It is starred when the line is parsed, so the busiest list counts every card path as one path, and the JSON form is starred too.
- **Errors** are statuses 500 to 599; every other status is a success, 4xx included.
- **`--since T`** drops well-formed lines before `T` (a line at `T` is kept). A malformed line has no time to compare, so it is always counted.
- **Per minute** is requests over the span from the earliest to the latest kept timestamp (not the first and last in file order); a span of zero, one request included, is 0.0. It is rounded to one decimal in both forms; `error_rate` to three.
- **Text layout**: the four count labels are padded to 10 columns, then a space, then the value right-aligned to the widest of the four values. With `per minute` the widest label, the spec's sample (three spaces before `40.1`) is not reachable by one rule, so the value column is the rule. The slowest rows align the milliseconds right and `METHOD path` left, each to its widest row, two spaces between columns; the busiest rows align the count right. The percent has one decimal. Integers and the whole part of per minute are grouped by `_`.
- **Busiest** counts a method and path together (the JSON row names both); ties are path ascending, then method ascending. **Slowest** ties beyond duration and timestamp keep file-name then line order.
- **An empty section** prints its heading and no rows. **The JSON form** ends with a newline.
- **Arguments** may come in any order; a second folder, an unknown flag (anything starting with `-`), a flag with no value, `--top` that is not a whole number from 1 to 100, and a `--since` that `Time.parse` refuses are usage errors, printed on one stderr line with the usage.
- **A folder that does not exist or cannot be listed** exits 1 with the same message as a folder with no `.log` file. **A log that cannot be read** within a minute exits 1 and prints nothing on stdout.
- **Deadlines**: `list` and each `read_lines` wait at most one minute.
- **Never reading outside `<dir>`** is structural, not checked: `main` passes `platform.fs.read_only` down, `analyzed` scopes it to the folder at once, and every read goes through that `Fs` with names `list` returned. No `never` can say it (see `GAPS.md`).

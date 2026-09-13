# Program 2: `logstat`, a CLI log analyzer

The spec altitude of program 2 from the program menu, written by Claude (Fable) in session 5 for a worker to implement in Mo without further design help. Robert reads this page and the `expose` lines, contracts, tests, and `verified:` line of the result, never the bodies. That reading is the experiment.

## Intent

`logstat` reads one or more log files in the common line format below and prints a summary: request count, error count and rate, the slowest requests, the busiest paths, and requests per minute. It must never crash on bad input: a malformed line is counted and skipped. It must never read outside the directory it was pointed at.

## Input

Each line: `<ISO-8601 timestamp> <method> <path> <status> <duration_ms>`, space-separated, for example:

```
2026-09-12T10:00:01Z GET /api/users 200 12
2026-09-12T10:00:02Z POST /api/orders 500 340
```

Lines that do not fit are malformed. Files are UTF-8. A file may be up to 100 MB; do not load more than one file at a time.

## Usage

```
logstat <dir> [--top N] [--since <ISO-8601>] [--json]
```

- `<dir>`: every `*.log` file directly inside it, in name order. Read-only.
- `--top N`: how many slowest requests and busiest paths to show, default 5, 1 to 100.
- `--since T`: ignore lines before T.
- `--json`: print the summary as one JSON object instead of the text report.

Exit code 0 on success, 2 on a usage error (printed to stderr, one line), 1 if no `.log` file was found.

## Output, text

```
requests   1_204
errors        37  (3.1%)
malformed      2
per minute   40.1

slowest
  340 ms  POST /api/orders   2026-09-12T10:00:02Z
  ...

busiest
  611  GET /api/users
  ...
```

Errors are statuses 500 to 599. "per minute" is requests divided by the span between the first and last timestamp in minutes; a single request is 0.0. Numbers use `_` as the thousands separator like Mo itself.

## Output, JSON

`{"requests": 1204, "errors": 37, "error_rate": 0.031, "malformed": 2, "per_minute": 40.1, "slowest": [{"ms": 340, "method": "POST", "path": "/api/orders", "at": "..."}], "busiest": [{"count": 611, "method": "GET", "path": "/api/users"}]}`

## Nevers

- A card number (16 digits) never reaches stdout: paths that contain one are printed with the digits replaced by `*`.
- The program never reads a file outside `<dir>`.
- The summary's `requests` equals `errors + successes`, and `errors <= requests`.

## Contracts the reader expects to see

- Parsing a line either yields a record whose `status` is 100 to 599 and whose `duration_ms` fits `UInt32`, or a malformed error. A `rejects` test for each `requires`.
- `--top N` outside 1 to 100 is a usage error, not a clamp.
- The busiest list is sorted by count descending, then path ascending; the slowest by duration descending, then timestamp ascending. Stable and deterministic.

## Tests the reader expects to see

A `test` for each output section on a small fixture, a `test rejects` for every `requires`, a `property` that `errors <= requests` for any list of records, and a program-level check in `examples/programs/` with a `.expected` file over a fixture directory of three files including malformed lines and a card number in a path.

## Measured on this program (recorded by the worker in its final message)

Loops to green (how many `mo test` or `mo check` runs failed before the last one passed), every stdlib or platform name that was missing (`GAPS.md` lines), lines per function (max and median), wall-clock time, and the diagnostics that helped or misled, quoted.

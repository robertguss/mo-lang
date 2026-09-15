# `sampler.mo`, the harness for sampling as verification

A Mo program in `examples/programs/jobq/sampler.mo`, module `Jobq.Sampler`, that plays a script of calls through `Jobq.Board.decide` and prints what each call decided. It is written once against the finished `board.mo` and then frozen; five regenerations of `board.mo` are compared through it. It touches no other file.

## Running

```
mo run sampler.mo -- <script>
```

The board starts as `board(T0, 1)` with `T0 = 2026-09-14T10:00:00Z`. Each script line is one call; `now` for the call is `T0 + <ms>`. The script is read whole with `read_lines`; a blank line or one starting with `#` is skipped. Exit 2 on a usage error, 1 when the script cannot be read.

## Script lines

Fields are separated by single spaces; the last field of `create` and `fail` is the rest of the line and may hold spaces.

```
<ms> <worker> create <queue> <max_attempts> <payload...>
<ms> <worker> fetch <id>
<ms> <worker> list <queue|-> <state|->          - means no filter; state is queued|leased|done|dead
<ms> <worker> remove <id>
<ms> <worker> lease <queue> <lease_ms>
<ms> <worker> ack <id>
<ms> <worker> fail <id> <reason...>
<ms> <worker> health
```

`<ms>` is a whole number of milliseconds; `<worker>` is the caller's token, passed as `Call.worker`. A line that does not parse prints `<n> BadLine` and the board is unchanged.

## Output

For script line `n` (counting every line, 1-based, skipped lines included), first one line with the outcome, then one line per write in the decision's order:

```
<n> Made <shown(job)>
<n> Found <shown(job)>
<n> Listed <count>              then one line `  J <shown(job)>` per job, in the list's order
<n> Removed
<n> Missing
<n> Conflict <reason>
<n> Empty
<n> Healthy queued=<q> leased=<l> done=<d> dead=<x> uptime_ms=<u>
<n> Unavailable <reason>
  W <key> <value>               a write of `value` under `key`
  W <key> DEL                   a write of None under `key`
```

`shown` is `Jobq.Job.shown`, the job's JSON on one line. Nothing else is printed to stdout; a usage error goes to stderr.

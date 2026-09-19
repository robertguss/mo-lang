# Workspace server part A: work in progress (paused by the lead, 19 Sep 2026)

Worker: Claude Opus 5. Not the final report. Only `evidence/red-01`, `evidence/red-02` are filed runs.

## Done (committed before this WIP commit)
- RED `966d537e`: `local.py --target CMD` (a Bridge-shaped `Served` adapter; no expectation changed).
  Python bridge 13/13 green (`evidence/red-01-python-baseline`); Mo stub 0/13 (`evidence/red-02-mo-stub`).
- `ee3d032e`: `wire.mo`, `schema.mo`, `envelope.mo`: pure, tested.

## In this WIP commit (all `mo check` clean; unit tests pass per module)
- `tools.mo` (6 tests), `journal.mo` (4), `admission.mo` (5), `worker.mo` (3), `connection.mo` (5),
  `operator.mo` (2), `server.mo`, `main.mo` (production), `double.mo` (test double: scripted command, tap, late_ms).
- `behaviour.py`: runs local.py's groups unchanged; `--half-close` adds SHUT_WR after each request.
- Not yet: `mo fmt` on the new files, `mo test --sim 200`, `mo build`, `verified:` lines, sim invariant tests,
  hostile-FS part C, size table part D, numbers, README, REPORT.md.

## Status of the 13 groups against `double.mo` with `--half-close` (unfiled scratch run)
Green: six-tools, schema, framing, identities-capability, duplicate-calls, deadlines, shutdown (7/13).
- file-refusals: the run refuses to start because the links tree cannot be hashed for the binding.
  Plan: the operator puts `source_sha256` in config.json (the adapter computes it); the server records its own
  digest beside it (null when unreadable) and still serves.
- byte-bounds: 400 where 413 is expected, for a 16 KiB header line with no CRLF (F1: Mo cannot see an unfinished line).
- disconnect, lost-response: the tests wait for the owner process to exit after a client disconnect;
  requirement 3 (D2) keeps the server up for the operator. This is a designed conflict. Also, a half-closing client
  makes a later full close invisible. Plan: new tests with bodies that end in "\n" (legal; no half-close needed).
- concurrent-admission (admission_closed, not busy) and journal-order-bound (a call not accepted among 16):
  NOT YET DIAGNOSED. The last manual drive (3 sequential list_files) kept admission open. Suspect
  the scripted `slow` command path (Worker's held reply and delayed Release) or a Close sent by the runner.
  Next: reproduce with `slow` in the scratch driver and read `status().why`.

## Findings (for the report)
- F1 (blocker for the unchanged wire): `Conn` reads only whole lines (`read_line`/`lines`, at most 64 KiB).
  A Content-Length body with no newline after it is never delivered until the peer ends its side; the `lines`
  source then reports Idle and closes the connection with no reply possible.
  Smallest example: a server doing `conn.lines(into: p, idle: 2_000.ms)`. The client sends the head plus a
  34-byte body, no newline, and keeps the socket open. The server gets 4 lines, then Idle. With SHUT_WR it gets
  5 lines, then Closed, and a reply can still be written. `Http.listen` cannot serve this wire either: its
  headers are lowercase (the client wants `Content-Length:`), its own refusals have empty bodies and use 501,
  it gives no request version, and it joins repeated headers.
- F2: `Json.decode` keeps the last value of a repeated key. The schema module counts keys in the raw text
  against the decoded tree to refuse repeats.
- Handles cannot sit in a struct (MO0403), and a function takes at most six parameters. So the token lives in
  the Gate (it holds no Fs), and a per-connection Runner holds admission, worker and journal.
- `main` can wait on a deferred reply and then `platform.exit`, so an operator close ends the program.
- The fixture `Fs` makes missing folders on write; the tools check the parent folder explicitly.

## Next command
python3 toolchain/bench/step36/guard.py 600 -- python3 -B examples/programs/workspace-server/behaviour.py --half-close \
  --groups concurrent-admission,journal-order-bound --target "python3 toolchain/bench/step36/guard.py 120 -- toolchain/zig-out/bin/mo run examples/programs/workspace-server/double.mo --"

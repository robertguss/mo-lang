# Regenerating `examples/programs/kv/`

Every function body in the five modules of program 3 was stripped; the intents, types,
processes, signatures with their contracts, and the tests were left as written. This is the
report of writing the bodies back from `mo-wiki/spec/programs/03-kv-store.md`, the signatures,
and the tests.

## Done-when

- `mo check` and `mo test` are green on `protocol.mo`, `log.mo`, `store.mo`, `server.mo`, and
  `main.mo`: 8, 14, 8, 5, and 5 tests, 40 in all, 0 failed, 0 skipped.
- Every `# run:` line of `main.mo` prints its `.expected` file byte for byte and exits as its
  `# exit:` line says: `check` 0, `compact` 0, `serve` 2, `serve data/nowhere` 1,
  `client 127.0.0.1 1 GET greeting` 1.
- `mo test --write --sim 100` has rewritten the `verified:` line of every module. All five also
  hold under `--sim 100` with faults: 10 process tests, 10 held under faults, 0 passed only
  without faults, and the three `invariant`s were kept under every seed.
- `data/compact/kv.log` is rewritten by the second run and comes back byte-identical, so the
  worktree holds no change outside the five modules and `examples/programs/.mo.ids`.

## Wall clock

**15 minutes 16 seconds**, from reading `examples/README.md` to the last green run
(2026-09-16 00:13:39 UTC to 00:28:55 UTC), the commit apart.

## Loops, by cause

A loop is a failing `mo check`, `mo test`, or `# run:` line. There were **two**, both on
`store.mo`, both at `mo check`, and **the first edit fixed each**.

| # | module | stage | code | cause | next edit | fixed |
|---|---|---|---|---|---|---|
| 1 | `store.mo` | `mo check` | `MO0102` | `Error(_): break` — `break` is a statement, so it cannot be a case arm's expression | moved `break` onto its own line below the arm | yes |
| 2 | `store.mo` | `mo check` | `MO0304` | `if` nested 4 deep in `faithful?` (for → case → if → if); the limit is 3 | pulled the inner block into two private helpers, `agreed?` and `next_table` | yes |

Nothing else failed: `protocol.mo`, `log.mo`, `server.mo`, and `main.mo` were green at `mo
check` and `mo test` on their first run, every `# run:` line matched its `.expected` file on its
first run, and no test ever failed.

Two failures outside the program, which cost no kv loop and are recorded so the count is honest:

- A scratch probe (`MO0310`) settled four shapes before `server.mo` was written: a `Bool`
  dropped from a **pure** call is refused, but one from a call that takes a capability or a
  handle is not, so `turn_away` may drop `sent(conn, ...)`; a block `if`/`else` may be an arm's
  value; `Ok(Quit)` may sit above `Ok(request)` in the same `case`; and a module function may
  share its name with a process's state field (`admitted`).
- The first sweep of the last four `# run:` lines passed each line's arguments as one word:
  zsh does not split an unquoted variable. The harness was wrong, not kv; rerun with the words
  given literally, all four matched.

## Decisions the spec did not cover

1. **The signature the strip cut in half.** `main.mo` ended a line at
   `fn check(...) : Result(String,` with the continuation gone. Restored as `Problem)`, the only
   return type the body and its callers admit.
2. **The journal's own deadline.** `Journal`'s `Fs.append` waits 60 s, a fixed duration, not the
   asker's `reply_by`. The store's `log_within` governs only the ask, so a line the journal
   appends after the store's deadline is still in the log — which is what `committed`'s comment
   requires, and which `reply_by` would have made impossible.
3. **Every other deadline.** 10 s for an `Fs` read, list, or size and for `net.connect`; 30 s for
   a client's silence (`conn.lines(idle:)`), the worker's ask of the store, and a `conn.write`;
   60 s for the listener's `idle:` and the journal's append. Only the 30 s client silence is in
   the spec.
4. **What `STATS` counts.** `sets=` counts `SET` commands that were not refused, `gets=` counts
   `GET` commands; `DEL` and `INCR` count as neither. `log_bytes=` is the journal's running byte
   count, starting at the size of the log it opened, and `uptime_ms=` is `clock.now` less the
   time the store opened. The spec names the fields, not their meaning.
5. **Keys are read in bytes.** A key byte must be above 32 — which excludes the space and every
   C0 control — and not 127. Bytes from 0x80 up pass, so `é` is two legal key bytes and the
   1-to-256 limit is a limit on bytes, as the tests read it.
6. **A `KEYS` prefix is not a key.** `KEYS` alone and `KEYS ` both mean the empty prefix, which
   no key rule admits, so `keyed?` — which `parse`'s `ensures` reads — is true for `Keys`,
   `Stats`, and `Quit` and asks the key rules only of `Set`, `Get`, `Del`, and `Incr`.
7. **The table's hash.** `bucket_of` folds `(hash * 31 + byte) % 256` over the key's bytes: the
   256-bucket spread `TOOLCHAIN-BUGS.md` records as the workaround for bug 2, with the
   parenthesised expression kept in the named `mixed` for bug 5.
8. **An empty line in a log is `BadLine`.** The spec says only that a truncated last line is
   ignored. `replay` stops at any line that is not a `SET` or a `DEL`, and `parse("")` is
   malformed, so a blank line stops replay at its number — which is what the tests read.
9. **How compaction is made safe.** `compact` writes `kv.compacted.log` beside the log and
   renames it over `kv.log`, so a compaction cut short leaves the old log whole. The scratch
   file's name is mine; the spec says only "rewrites the log".
10. **Where `kv check` writes.** The folder's `kv.log` is only read; the changes go to
    `kv.check.log` beside it, removed before the script and again after. A removal that fails is
    not an error, since the transcript does not depend on it.
11. **A line over 64 KiB.** The runtime's `LineTooLong` is answered `ERR malformed` and the
    connection goes on, matching the spec's rule for a malformed line, which does not itself say
    what an over-long line gets.
12. **A connection already closed.** A worker that has closed its client ignores the lines the
    runtime had already read, so the request after `QUIT` on the same connection is not answered
    — which is what `kv.expected` shows, since its last `GET hits` is a connection of its own.
13. **`ERR busy` before the close.** The 65th client is written `ERR busy` and then closed. The
    count of clients inside is a process of its own, `Gate`, so the limit of 64 is that process's
    `invariant` rather than a number the listener keeps.
14. **A full store answers `ERR full`.** A `SET` or an `INCR` that would add a key to a table of
    1,000,000 is refused with a new `Refusal`, `Full`, so the store's `invariant` holds without a
    crash. The spec names the invariant but not the answer; `Refusal` already carried `Full`.
15. **What ends the program.** `serve` alone keeps running, since the runtime owns the listener;
    every other command ends with `platform.exit`, and stdout is flushed before it, so a
    `served_on` line is not lost.
16. **`faithful?` goes on after an `ERR io`.** An `ERR io` changed nothing, so the model beside
    the store still matches and the check keeps asking; it stops only at an ask that got no
    answer, since the store may yet take it.
17. **`mo test --write --sim 100`, not plain `--write`.** `examples/README.md` says the corpus's
    `verified:` lines are written with `--sim 100`, and the corpus test runs every file that way.
    Plain `--write` would have written `sim (not run)` on `log.mo`, `store.mo`, and `server.mo`,
    which do have process tests; with `--sim 100` they record `sim (100 runs, invariants (kept 1,
    tripped 0))`, and `protocol.mo` and `main.mo` record `sim (not run)` either way.
18. **The words on stderr.** `usage()` and each `Problem`'s sentence are mine; no `.expected`
    file pins stderr, only stdout.

## Private helpers written beyond the signatures left in place

`store.mo`: `agreed?`, `next_table` (loop 2's fix). `server.mo`: `told` — one answer written to a
client whose connection goes on unless the write failed. `main.mo`: `rewritten`, `why_unopened`,
`cleared`.

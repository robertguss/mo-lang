# kv regenerated from its spec

Every function body in `examples/programs/kv/` was gone; each module kept its intent, types,
processes, signatures with their contracts, and its tests. This is the report of writing every
body back, on branch `cache-B`, against `mo-wiki/spec/programs/03-kv-store.md`.

## Done-when

- `mo check` is green on `protocol.mo`, `log.mo`, `store.mo`, `server.mo`, and `main.mo`.
- `mo test` is green on all five: 8, 14, 8, 5, and 5 tests, 40 in all, 0 failed, 0 skipped.
- `mo test --sim 100` holds on all five: 10 tests under 100 seeds with 5% faults, 10 held under
  faults, 0 passed only without faults; the three `invariant`s were kept and none tripped.
- Every `# run:` line of `main.mo` prints its `.expected` file byte for byte and exits as its
  `# exit:` line says: `check data/demo data/session.txt` (0), `compact data/compact` (0),
  `serve` (2), `serve data/nowhere` (1), `client 127.0.0.1 1 GET greeting` (1).
- `mo fmt --check` is clean on all five.
- `mo test --write --sim 100` rewrote the `verified:` lines and the `.mo.ids` sidecar.
- `data/demo`, `data/compact`, and `data/session.txt` are byte-identical to what they were.

Wall clock: 14 minutes, 00:13 to 00:27 UTC on 16 September 2026. Every `mo` process ran under
`timeout 120` with a watchdog that would kill it past 4 GiB resident; nothing came near either.

## Loop count by cause

Eight `mo check` / `mo test` / run invocations per module were budgeted; what actually failed:

| cause | count | the next edit fixed it |
|---|---|---|
| `mo check` diagnostic | 1 | yes, first try |
| `mo test` failure | 0 | — |
| `# run:` line mismatch or wrong exit code | 0 | — |
| `mo fmt --check` difference | 2 | yes, `mo fmt` rewrote both |

The one diagnostic was **MO0102** in `store.mo`: `Error(_): return true` on a `case` arm's own
line, where a `return` is a statement and has to go on the lines below the arm. Splitting it
into `Error(_):` and an indented `return true` fixed it, and that was the first fix tried.

The two formatter differences were `store.mo`'s `Answer(response): Served(...)` arm and
`main.mo`'s long `Error(Unopened(dir:, why:))` call, both of which the formatter re-wrapped;
neither was a diagnostic and neither changed behaviour.

Nothing else failed. `protocol.mo`, `log.mo`, `server.mo`, and `main.mo` were green on `check`
and `test` on the first run, and all five `# run:` lines matched their expected file on the
first run. One self-inflicted slip, not a `mo` diagnostic: the script that put the bodies back
indented `Journal`'s `update` two spaces short; `git checkout log.mo` and a corrected script
were the fix, before `mo check` ever saw the file.

## Decisions the spec did not cover

1. **`kv serve` on a log whose last line was cut short.** The spec says the truncated line is
   ignored and reported to stderr once, but not what the next append does. Appending at the
   file's end would splice a new line onto the unfinished one, so a later replay would read a
   wrong value and break the never "the number of live keys after replay equals the number
   after the last command before the restart". `serve` rewrites the log compacted — write
   `kv.log.new`, rename over `kv.log` — before it listens. `compact` and `check` are unchanged.

2. **`ERR` words the protocol table does not name.** It names `ERR not_a_number`,
   `ERR overflow`, `ERR malformed`, and `ERR busy`. Two more refusals exist in the program:
   `ERR io`, when a change did not reach the log in time, and `ERR full`, at the key limit.

3. **What the million-key invariant does to a request.** The spec asks for
   `invariant keys.size <= 1_000_000` but not what happens at the bound. A `SET` or `INCR` that
   would add a *new* key to a table already holding a million is answered `ERR full` and changes
   nothing; a `SET` of a key the table already holds still goes through. Refusing rather than
   crashing keeps the invariant a bound on the store, not a way to kill it from the wire.

4. **`INCR` on a key with no value starts at 0**, so `INCR fresh -5` answers `VALUE -5` and
   writes `-5`. The new value is written back as its decimal spelling, and only the new value —
   not the whole arithmetic — is what `GET` reads back.

5. **How the key and value rules are counted.** "No control characters" is read as every byte
   greater than 32 and not 127, which also excludes the space the protocol splits on. Both
   bounds are counted in bytes, not graphemes: 256 bytes for a key (so 256 ASCII letters or 128
   two-byte ones) and 61,440 bytes for a value.

6. **`KEYS` with no argument.** `KEYS` alone and `KEYS ` with an empty prefix both list every
   key. Keys sort byte by byte, which is the stdlib's one order for strings.

7. **`QUIT` is answered by the connection's worker, not the store.** A client can say goodbye
   and be closed even while the store is not answering; every other request goes to the store.

8. **Where a `kv check` writes.** The folder's own `kv.log` is only read; the changes a check
   makes go to `kv.check.log` beside it, which is removed before the run and again after, so a
   check leaves the folder as it found it. The log's name and the remove-before-and-after are
   this program's; the README only says the folder is not written.

9. **The deadlines nothing names.** The store waits 30 s for the journal to take a change; the
   journal gives its own `append` 30 s; a worker waits 30 s for the store; the client waits 10 s
   a round trip; a served listener and a read connection go idle at 30 s, which is the spec's
   "a client silent for 30 seconds is closed"; a log's `read` is given 10 minutes and its `list`
   and `size` 10 seconds.

10. **The transcript a `kv check` prints.** `> ` and the line sent, then the answer's lines as
    they came off the wire, and a client that could not reach the server printed as its problem
    sentence. Each script line gets a connection of its own, which is why a line after `QUIT` is
    answered normally.

11. **What `STATS` counts.** `uptime_ms` is the clock's distance from the moment the store
    opened; `sets` counts every `SET`, `DEL`, and `INCR` that was not refused; `gets` counts
    every `GET`, answered or missing; `log_bytes` is the log's size on disk after the last
    append, which starts at the size of the log that was replayed.

12. **Compaction writes beside the log and renames over it.** The spec says only "rewrites the
    log to one line per live key"; writing `kv.log.new` whole and renaming it means a compaction
    cut short leaves the old log as it was. `kv compact` reports
    `kv: compacted <dir>/kv.log from <n> lines to <m>`.

13. **The stderr sentence for a folder that cannot be opened** interpolates the `LogError`
    rather than spelling out each variant, because `Kv.Main`'s `use Kv.Log{...}` line — part of
    the module header the strip kept — does not bring the enum in, and the header was left as it
    was found. Stdout is what the `.expected` files hold, so no run line depends on the wording.

14. **The store's own faithfulness check.** `faithful?` keeps a table beside the store and
    accepts either the answer that table gives, with the table changed as the store's must be,
    or `ERR io` with no change; a timed-out ask ends the check, since the store may still take
    it. Its script exercises `SET`, `GET`, `INCR`, a value no `INCR` can read, both `DEL` paths,
    `KEYS`, and `QUIT`, and avoids `STATS`, whose counts the model does not keep.

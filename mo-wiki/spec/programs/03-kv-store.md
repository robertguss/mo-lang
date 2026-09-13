# Program 3: `kv`, a key-value store over TCP

The spec altitude of program 3 from the program menu. Written by Claude (Fable) in session 5. A worker implements it in Mo; Robert reads the spec altitude only.

## Intent

`kv` is a single-process key-value server with a line protocol over TCP, durable through an append-only log, with the store's invariants stated as `never` clauses. It stresses bytes, sized integers, hot loops, processes, and deadlines.

## Protocol

One request per line, one response per line, UTF-8, `\n` terminated, at most 64 KiB per line:

```
SET <key> <value>      → OK
GET <key>              → VALUE <value>  |  MISSING
DEL <key>              → OK  |  MISSING
INCR <key> <n>         → VALUE <new>    |  ERR not_a_number   (value must be a decimal Int64; overflow is ERR overflow, the value unchanged)
KEYS <prefix>          → KEYS <n> then n lines of keys, sorted
STATS                  → STATS keys=<n> sets=<n> gets=<n> log_bytes=<n> uptime_ms=<n>
QUIT                   → BYE, then the connection closes
```

Keys: 1 to 256 bytes, no spaces, no control characters. Values: 0 to 60 KiB, no `\n`. A malformed line gets `ERR malformed` and the connection stays open. A client silent for 30 seconds is closed. At most 64 clients; the 65th gets `ERR busy` and is closed.

## Durability

Every `SET`, `DEL`, and `INCR` is appended to `<dir>/kv.log` before the response is sent. On start, the log is replayed. A truncated last line is ignored and reported to stderr once. `kv compact <dir>` rewrites the log to one line per live key and exits.

## Usage

```
kv serve <dir> [--port N]     default port 7700
kv compact <dir>
```

Exit 2 on a usage error, 1 if `<dir>` cannot be opened or the port cannot be bound.

## Nevers

- A response is never sent before its log line is durable.
- The store never holds a key that violates the key rules.
- `INCR` never changes a value on error.
- The number of live keys after replay equals the number after the last command before the restart.

## Contracts the reader expects to see

`requires` on key and value sizes with `rejects`; `ensures` on `INCR` that the new value is `old + n`; an `invariant` on the store process that `keys.size <= 1_000_000`.

## Tests the reader expects to see

Unit tests for the parser and each command; a property that `SET` then `GET` round-trips any valid key and value; a replay test that starts, writes, stops, starts again, and reads; a `--sim` run under 100 seeds with injected `Fs` failures in which every response was either correct or an `ERR io` with the store unchanged; and a program-level check in `examples/programs/` that drives the server through a real socket from a test client written in Mo (`kv client <host> <port> <line>`).

## Measured

Requests per second on `SET`/`GET` over a local socket with one client and with 32; bytes per key of resident memory at 100k keys; replay time for a 1 M-line log; and the same worker measurements as program 2.

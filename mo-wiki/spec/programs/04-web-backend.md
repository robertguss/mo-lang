# Program 4: `notes`, a web backend

The spec altitude of program 4 from the program menu. Written by Claude (Fable) in session 5. A worker implements it in Mo; Robert reads the spec altitude only. **Status:** implemented in session 6 as `notes`; regenerated at 1.0 in measurement 1 (`plans/bodies-as-cache.md`). The menu said "with Postgres"; there is no database brick yet, so the store is a recipe implemented on `Fs`, which is the package story the program exists to test.

## Intent

`notes` is an HTTP service that keeps short notes for many clients: create, read, list, update, delete, over JSON, durable across restart, rate-limited per client, with the service's invariants stated as `never` clauses. It stresses `Http`, JSON, processes, and the two recipes it is built from.

## The package story

Two things the program needs are not in the stdlib and are not written from scratch either. They are recipes: intent, signatures with contracts, and tests, which the worker implements in the program's own modules from the bricks, exactly as chapter 6 says.

- `Recipes.RateLimiter` (already in `examples/recipes/rate-limiter.mo`): one bucket per client token.
- `Recipes.Store`, new, written by the worker first as a recipe in `examples/recipes/store.mo`: a durable map from `String` keys to `String` values over an append-only log, `needs Fs`, with `open(fs, dir)`, `get`, `put`, `delete`, `keys(prefix)`, `compact`, its `never`s (a value read equals the last one written; the count after replay equals the count before the stop), and its tests. Then implemented for `notes`. If `kv`'s `Kv.Log` and `Kv.Store` already say this, the recipe says it in recipe form and the implementation may be copied from `kv` by hand; say so.

The final message says what the recipes cost and saved against writing the same code with no recipe.

## The API

Every request carries `authorization: Bearer <token>`; a missing or empty token is `401`. A token names a client; there is no user registry: any non-empty token of 1 to 64 bytes of letters, digits, `-`, `_` is a client. A client sees only its own notes.

```
POST   /notes            {"title": "...", "body": "..."}   → 201 {"id": "n_1", "title", "body", "created_at", "updated_at"}
GET    /notes?prefix=t   → 200 {"notes": [ {note}, ... ]}   sorted by id, at most 100, `prefix` on the title
GET    /notes/{id}       → 200 {note}  |  404
PUT    /notes/{id}       {"title", "body"}                  → 200 {note}  |  404
DELETE /notes/{id}       → 204  |  404
GET    /health           → 200 {"notes": <count>, "clients": <count>, "uptime_ms": <n>}   no token needed
```

Titles are 1 to 200 bytes, bodies 0 to 60 KiB, both UTF-8 with no control characters but `\n` in the body. A body that is not JSON, or a JSON body missing a field, or a field of the wrong shape, is `400 {"error": "..."}`. A method the route does not have is `405`. A route that does not exist is `404`. Ids are `n_` and a counter that never repeats, per service, not per client. Timestamps are ISO-8601 UTC from the clock.

A client may make 60 requests a minute; the 61st is `429 {"error": "rate limited", "retry_after_ms": <n>}` and is not counted or stored. `/health` is not limited.

## Durability

Every create, update, and delete is appended to `<dir>/notes.log` before the response is sent. On start the log is replayed; a truncated last line is ignored and reported once to stderr. `notes compact <dir>` rewrites the log to one line per live note and exits.

## Usage

```
notes serve <dir> [--port N]     default port 7800
notes compact <dir>
notes client <host> <port> <token> <method> <path> [<json>]   one request, prints status and body
notes check <dir> <script>        serve on a free port and play a script of `<token> <method> <path> [<json>]` lines through the client
```

Exit 2 on a usage error, 1 if `<dir>` cannot be opened or the port cannot be bound.

## Nevers

- A response is never sent before its log line is durable.
- A client never reads, changes, or deletes another client's note.
- An id is never reused, restart or not.
- A rate-limited request never changes the store.
- The number of live notes after replay equals the number before the stop.

## Contracts the reader expects to see

`requires` on title and body sizes and the token shape, each with its `rejects`; `ensures` on `put` that a `get` returns what was put; `invariant`s on the service process: `notes.size <= 1_000_000` and the id counter never goes backwards; the recipes' own contracts, honoured by their implementations.

## Tests the reader expects to see

Unit tests for the JSON shapes, the routes, and each status; the recipes' tests passing on the implementations; a property that create then get round-trips any valid title and body; a replay test that starts, writes, stops, starts again, and lists; a `--sim` run under 100 seeds with injected `Fs` and `Http` failures in which every response was either correct or a `503` with the store unchanged; and a program-level check in `examples/programs/` that drives the service through a real socket from `notes client`, as `kv check` does.

## Measured

Requests per second on create and get over a local socket with one client and with 32, under `mo run` and as a `mo build` binary; resident memory at 100k notes; replay time for a 1 M-line log; what the two recipes cost and saved; and the same worker measurements as program 2.

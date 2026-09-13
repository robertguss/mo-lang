---
title: "Step 16: HTTP in the stdlib, brief for the worker"
created: 2026-09-13
updated: 2026-09-13
type: plan
tags: [stdlib, runtime, processes]
sources: [plans/interpreter-step-11.md, plans/interpreter-step-15.md, spec/design-v0/09-stdlib.md, plans/program-menu.md]
status: in-progress
---

# Step 16: HTTP in the stdlib

Program 4 is a web backend, and the stdlib has sockets but no HTTP. This step adds `Http` as a row group over `Net`, in the interpreter and the C runtime both, so a program serves and fetches HTTP with no new syntax and the interpreter stays the reference.

## Orientation

`spec/design-v0/09-stdlib.md` (`## Net` is the model: the same capability rules, deadline outcomes, and fixture paragraph), `toolchain/src/net.zig` and `stdlib.zig` (how `Net` is a row), `runtime/mo_rt.c` (the `Net` port from step 15), `examples/programs/echo/` (a program the corpus test drives against itself), the process and `Net` rows of the decision log (steps 11, 12, 15), and `spec/programs/03-kv-store.md` for the spec altitude program 4 will use.

## Write scope

`toolchain/`, `examples/`, and `## Http` in `spec/design-v0/09-stdlib.md` and `toolchain/PRELUDE.md`; branch `session-05`, one commit per part, push after every commit.

## The design (decided; the worker fills gaps and lists them)

- HTTP/1.1 only, no TLS, `Connection: close` on every response: one request per connection. Bodies by `Content-Length` only; a chunked request is `Unsupported`. A request line, headers, or body over 1 MiB is `TooLarge`. Header names are lower-cased on read.
- `Request` and `Response` are structs in the prelude: `Request(method: String, path: String, query: Map(String, String), headers: Map(String, String), body: String)` and `Response(status: UInt16, headers: Map(String, String), body: String)`. Constructing a `Response` needs only what the caller has: a `status` and a `body` at least; the runtime adds `content-length` and `connection`.
- `platform.http` is the capability, `Http`, alongside `platform.net`. `Http.listen(port)` gives an `HttpListener`; `listener.accept(within:)` gives an `Exchange`, which holds `.request` and answers once with `exchange.reply(response, within:)`. An `Exchange` is a capability like a `Conn`: it travels as a parameter and closes when its holder stops. `Http.send(request, host:, port:, within:)` is the client and gives a `Response`. Errors are `HttpError`: `Timeout`, `Refused`, `Closed`, `Busy`, `Malformed`, `TooLarge`, `Unsupported`.
- `Http.fixture()` in tests, over `Net.fixture()`'s network: a server process and a client in one test with no socket, and `Mo.Sim` faults as `Net`'s.

## Part A: the rows and the interpreter

`## Http` in `09-stdlib.md` and `PRELUDE.md` in the `## Net` shape. The parser and serializer of requests and responses over `Conn.read_line` and `Conn.write` (the body read by byte count, so `Conn` may need a `read_bytes(n, within:)` row; if so, add it to `## Net` and say so). `Http.listen`, `accept`, `reply`, `send`, and the fixture, in `stdlib.zig`, `net.zig`, and `sim.zig`. A corpus file `effects/http.mo`: a server process that answers `GET /hello?name=x` and `POST /echo`, driven through the fixture, holding under `--sim 100` with faults. Tests under `examples/stdlib/` for the parser: a request with no body, with a body, with a query, malformed, too large.

## Part B: the C runtime

The same rows in `mo_rt.c`, the fixture included; `zig build test` builds `effects/http.mo` with `--tests` and it must print what `mo test` prints.

## Part C: a program

`examples/programs/httpd/`: a hello server in the shape of `echo`, started by `main` on a free port together with client processes that `send` requests in turn and print status and body, so the corpus test drives it with no background server; two `# run:` lines and `.expected` files; identical under `mo run` and as a binary.

## Part D: numbers

Bench rows `http-1k` and `http-1k-c`: 1,000 `GET /hello` round trips from one client to the server in `httpd`, interpreter and native, and resident memory of the native server after them.

## Done when

Green, `httpd` identical under both runtimes, the rows in the spec, rows recorded, pushed, decisions listed.

## Related
- [[interpreter-step-15]]
- [[interpreter-step-11]]
- [[program-menu]]
- [[program-3]]

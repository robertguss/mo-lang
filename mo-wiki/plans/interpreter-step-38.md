---
title: "Step 38: a full-duplex Conn, TCP_NODELAY, and the handshake abuse rows"
created: 2026-09-18
updated: 2026-09-18
type: plan
tags: [runtime, stdlib, programs]
sources:
  [
    plans/interpreter-step-37.md,
    spec/programs/07-redis-subset.md,
    spec/design-v0/09-stdlib.md,
  ]
status: in-progress
---

# Step 38: a full-duplex `Conn`, `TCP_NODELAY`, and the handshake abuse rows

Three runtime rows found while step 37 was measured and verified, all needed
before program 7's build, none of them a language change. A Redis client
pipelines: it writes a batch of commands and reads the replies as they come,
on one connection, both directions at once. Today a Mo program cannot do
that through one `Conn`, and a write-then-read pattern pays Nagle's delay.
And step 37's second defect showed the runtimes had never been driven with a
reset or an alert at every handshake state.

## Orientation

`toolchain/src/net.zig`: `Conn`, its `writing` flag, `readLine`, `writeAll`,
the poller's fibers, `Net.handshake`, `readTls`, `flushTls`, `feedTls`;
`toolchain/src/sources.zig` (`lines`); `toolchain/runtime/mo_rt.c` (search
`read_line`, `lines`, `tls_handshake`, `tls_give_up`, `writing`). The
findings: `toolchain/bench/step37/RESULTS.md` "What the runs found outside
the brick" (1,600 lines written from `main` while `lines` reads the same
connection stall 58.5 s; 3,200 lines in windows of 16 take 8.98 s against
0.39 in windows of 256), `tls-dial.mo`'s two-window workaround, and the
decision-log rows of 18 Sep on step 38 and on the server crash. The abuse
scripts: `toolchain/bench/step36/abuse.py`, `bench/step37/diff.py`'s raw
client, `audit/evidence/2026-09-18/step-37/fable-probe/server-alert-probe.py`
and `alert-probe.py`.

## Write scope

`toolchain/` (both runtimes, their tests, `bench/step38/`, `PRELUDE.md` if a
row's wording changes), `examples/effects/` only for a new example
`duplex.mo` with its `.expected` and the `.mo.ids` sidecars, and these spec
lines only: the `## Net` paragraph in `09-stdlib.md` that says what a `Conn`
does while a write waits, and the runtime paragraph of `toolchain/README.md`.
Nothing else under `mo-wiki/`.

## Parts

A. **A `Conn` reads while a write on it waits**, in both runtimes, plain and
TLS. A `read_line`, a `lines` loop, or an `accept`'s handshake read on a
connection proceeds while a `write` on the same connection is blocked on the
peer; the write's deadline still holds; `Busy` still names a second `write`
while one waits (the spec's row), and a second reader while one waits. For
TLS the engine is one object driven from two fibers: the record layer's
sequence numbers and the write buffer are guarded so that a read's KeyUpdate
answer and a write's records never interleave inside one record. A test per
runtime: a client that writes 1,600 lines and reads the echoes on one
connection from `main` while `lines` delivers them, finishing in under a
second; the same under `Tls.fixture()` and over a real TLS socket.

B. **`TCP_NODELAY` on every `Conn`** both runtimes, at `connect` and at
`accept`; `Listener` and `Net.connect` rows unchanged. Measured on
`echo-1k` and on `bench/step37/measure.py`'s bulk with windows of 1, 16, and
256 lines, before and after.

C. **The handshake abuse rows.** `bench/step38/abuse.py` (or step 36's
extended): at each state of the server's handshake (before the hello, after a
partial hello, after the server's flight, after the client's Finished, after
the first application record) and of the client's (before the ServerHello,
mid-flight, after Finished), the peer sends a fatal alert, a `close_notify`,
a reset, or nothing until the deadline; both runtimes; the expected answer
(`Handshake`, `Closed`, `Timeout`) per cell, the server taking the next
connection after each, the client's process alive; 32 cells per runtime,
each checked for a live server or client and for the right error, printed as
a table with the date and `uptime` at its head. The `.bricks` cache row is
**not** this step.

## Numbers

`echo-1k` and the bulk windows before and after B; the duplex test's time
under both runtimes; the abuse table; `jobq`'s warm build before and after;
the suite's time. Load average beside each table; best of five.

## Done when

`timeout 2400 zig build test --summary all` green with its summary line and
exit code in the report; the duplex test green under both runtimes and the
fixture; the abuse table at 64 of 64; the numbers table; the spec lines; a
numbered list "Decisions the brief did not cover". One commit per part,
subject `Step 38 part X`, pushed after each.

## Related

- [[interpreter-step-37]]
- [[07-redis-subset]]
- [[09-stdlib]]
- [[roadmap]]

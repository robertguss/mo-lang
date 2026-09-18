# Step 38's numbers

Robert's Mac (M3 Max, 14 cores, macOS), 18 Sep 2026, with other sessions' benches running until
about 11 AM ET: the load average is beside every row. Every number is the best of five unless it
says otherwise. The raw outputs are in `work/` (ignored by git), each with the date and `uptime` at
its head and foot. `before-B` is the part A commit (`ebf59b3`), `before-38` the step's start
(`64982b2`), `after` the tree with parts A and B.

## A: a Conn reads while a write on it waits

The stall was TLS-only, and on this Mac it showed only for a read on the connection itself while a
write was parked: a client whose `main` reads 1,600 echoed lines of 4 KiB with `read_line` while a
process writes them got 4 lines back and then waited out its one-minute deadline (60.02 s, one
run, load 4.23 5.66 5.49, the scratch client against `tls-echo.mo`'s binary, 09:37 AM ET). The
same shapes over a plain socket, and `main` writing while the `lines` loop reads, did not stall
on this Mac at 1,600 or 20,000 lines, nor in a Linux container at 1,600 (main writing, `lines`
reading; the container was not tried with `read_line`); the reader's blocking flush
of the engine's queue was the cause (part A's commit message has it).

`examples/effects/duplex.mo` whole: four legs of 1,600 lines of 4 KiB each way on one connection
(plain and TLS; main writing while `lines` reads, and a process writing while main reads), each
leg under a second, then the Busy checks with their pauses (about 0.3 s of waits):

| mo    | runtime | time    | load           |
|-------|---------|---------|----------------|
| after | run     | 0.819 s | 4.47 4.45 4.75 |
| after | binary  | 0.482 s | 5.64 4.69 4.83 |

Each leg alone, one run under `mo run` during development: 0.05 s plain, 0.18 to 0.19 s TLS.

## B: TCP_NODELAY

3,200 lines of 4 KiB (3,072 in windows of 256), each window written whole and then read back whole
(`window-dial.mo` to step 36's `plain-echo.mo` or `tls-echo.mo`, the same runtime on both ends).

In a Linux container (OrbStack, kernel 7.0.14, `python:3.13-alpine`; each tree's `mo` and the
binaries cross-built for aarch64 Linux; the container's own load beside each row), where Nagle's
algorithm waits out the peer's delayed ACK:

| mo       | runtime | over  | window | time    | MB/s one way | load (container) |
|----------|---------|-------|--------|---------|--------------|------------------|
| before-B | run     | plain | 1      | 0.255 s | 51.3         | 0.04 0.06 0.03   |
| before-B | run     | plain | 16     | 8.836 s | 1.5          | 0.14 0.08 0.04   |
| before-B | run     | plain | 256    | 0.110 s | 114.3        | 0.14 0.08 0.04   |
| before-B | run     | tls   | 1      | 0.907 s | 14.5         | 0.43 0.14 0.06   |
| before-B | run     | tls   | 16     | 9.326 s | 1.4          | 0.24 0.14 0.06   |
| before-B | run     | tls   | 256    | 0.584 s | 21.5         | 0.24 0.14 0.06   |
| before-B | binary  | plain | 1      | 0.075 s | 175.9        | 0.38 0.17 0.07   |
| before-B | binary  | plain | 16     | 8.703 s | 1.5          | 0.19 0.14 0.07   |
| before-B | binary  | plain | 256    | 0.040 s | 315.3        | 0.19 0.14 0.07   |
| before-B | binary  | tls   | 1      | 0.670 s | 19.6         | 0.34 0.18 0.08   |
| before-B | binary  | tls   | 16     | 9.663 s | 1.4          | 0.45 0.23 0.10   |
| before-B | binary  | tls   | 256    | 0.572 s | 22.0         | 0.42 0.22 0.10   |
| after    | run     | plain | 1      | 0.242 s | 54.1         | 0.42 0.22 0.10   |
| after    | run     | plain | 16     | 0.190 s | 69.1         | 0.54 0.25 0.11   |
| after    | run     | plain | 256    | 0.109 s | 115.6        | 0.54 0.25 0.11   |
| after    | run     | tls   | 1      | 0.837 s | 15.7         | 0.66 0.28 0.12   |
| after    | run     | tls   | 16     | 0.653 s | 20.1         | 0.77 0.31 0.13   |
| after    | run     | tls   | 256    | 0.409 s | 30.8         | 0.77 0.31 0.13   |
| after    | binary  | plain | 1      | 0.068 s | 193.8        | 0.77 0.31 0.13   |
| after    | binary  | plain | 16     | 0.059 s | 222.5        | 0.77 0.31 0.13   |
| after    | binary  | plain | 256    | 0.036 s | 346.9        | 0.77 0.31 0.13   |
| after    | binary  | tls   | 1      | 0.610 s | 21.5         | 0.87 0.34 0.14   |
| after    | binary  | tls   | 16     | 0.492 s | 26.6         | 0.96 0.37 0.15   |
| after    | binary  | tls   | 256    | 0.313 s | 40.1         | 0.96 0.37 0.15   |

On the Mac, whose loopback never showed the delayed-ACK wait (windows of 16 were already fast
before):

| mo       | runtime | over  | window | time    | MB/s one way | load           |
|----------|---------|-------|--------|---------|--------------|----------------|
| before-B | run     | plain | 1      | 0.275 s | 47.7         | 3.75 4.34 4.73 |
| before-B | run     | plain | 16     | 0.150 s | 87.3         | 3.75 4.34 4.73 |
| before-B | run     | plain | 256    | 0.136 s | 92.6         | 3.75 4.34 4.73 |
| before-B | run     | tls   | 1      | 0.455 s | 28.8         | 3.75 4.34 4.73 |
| before-B | run     | tls   | 16     | 0.239 s | 54.9         | 3.93 4.36 4.73 |
| before-B | run     | tls   | 256    | 0.189 s | 66.5         | 3.93 4.36 4.73 |
| before-B | binary  | plain | 1      | 0.128 s | 102.6        | 3.93 4.36 4.73 |
| before-B | binary  | plain | 16     | 0.061 s | 215.4        | 3.93 4.36 4.73 |
| before-B | binary  | plain | 256    | 0.054 s | 233.8        | 3.93 4.36 4.73 |
| before-B | binary  | tls   | 1      | 0.153 s | 85.9         | 3.94 4.36 4.73 |
| before-B | binary  | tls   | 16     | 0.073 s | 178.5        | 3.94 4.36 4.73 |
| before-B | binary  | tls   | 256    | 0.064 s | 196.4        | 3.94 4.36 4.73 |
| after    | run     | plain | 1      | 0.270 s | 48.5         | 3.94 4.35 4.73 |
| after    | run     | plain | 16     | 0.153 s | 85.9         | 4.27 4.41 4.75 |
| after    | run     | plain | 256    | 0.137 s | 91.7         | 4.27 4.41 4.75 |
| after    | run     | tls   | 1      | 0.420 s | 31.2         | 4.27 4.41 4.75 |
| after    | run     | tls   | 16     | 0.237 s | 55.3         | 4.27 4.41 4.75 |
| after    | run     | tls   | 256    | 0.197 s | 63.8         | 4.33 4.42 4.75 |
| after    | binary  | plain | 1      | 0.128 s | 102.6        | 4.33 4.42 4.75 |
| after    | binary  | plain | 16     | 0.062 s | 210.1        | 4.33 4.42 4.75 |
| after    | binary  | plain | 256    | 0.058 s | 217.5        | 4.33 4.42 4.75 |
| after    | binary  | tls   | 1      | 0.153 s | 85.6         | 4.33 4.42 4.75 |
| after    | binary  | tls   | 16     | 0.073 s | 179.5        | 4.33 4.42 4.75 |
| after    | binary  | tls   | 256    | 0.067 s | 189.0        | 4.33 4.42 4.75 |

`mo-bench --network`'s echo rows (1,000 round trips of one line, each waiting for its echo; Nagle
never held these, since each write has nothing unacknowledged before it):

| mo       | row       | 1,000 round trips | a round trip | load           |
|----------|-----------|-------------------|--------------|----------------|
| before-B | echo-1k   | 33,869 µs         | 33.9 µs      | 4.92 5.12 5.04 |
| before-B | echo-1k-c | 37,627 µs         | 37.6 µs      | 4.92 5.12 5.04 |
| after    | echo-1k   | 34,166 µs         | 34.2 µs      | 4.85 5.10 5.03 |
| after    | echo-1k-c | 36,252 µs         | 36.3 µs      | 4.85 5.10 5.03 |

## `mo build examples/programs/jobq`, warm, before the step and after

| mo        | warm   | cold (bricks compiled) | binary        | load           |
|-----------|--------|------------------------|---------------|----------------|
| before-38 | 0.11 s | 10.1 s                 | 780,072 bytes | 5.62 4.72 4.84 |
| after     | 0.12 s | 10.1 s                 | 780,056 bytes | 5.60 4.74 4.85 |

## C: the handshake abuse rows

`abuse.py` against both runtimes, 64 of 64. 2026-09-18 14:51:05 UTC, `10:51  up  3:15, 2 users, load averages: 4.85 4.65 4.87`.

| runtime | side   | state      | peer sends   | on the wire      | expected                      | the Mo side said              | alive after |      |
|---------|--------|------------|--------------|------------------|-------------------------------|-------------------------------|-------------|------|
| run     | server | hello      | alert        | alert 2/40 clear | accept=Handshake              | accept=Handshake              | yes         | pass |
| run     | server | hello      | close_notify | alert 1/0 clear  | accept=Closed                 | accept=Closed                 | yes         | pass |
| run     | server | hello      | reset        | RST              | accept=Closed                 | accept=Closed                 | yes         | pass |
| run     | server | hello      | nothing      | (held open)      | accept=Timeout                | accept=Timeout                | yes         | pass |
| run     | server | partial    | alert        | alert 2/40 clear | accept=Handshake              | accept=Handshake              | yes         | pass |
| run     | server | partial    | close_notify | alert 1/0 clear  | accept=Closed                 | accept=Closed                 | yes         | pass |
| run     | server | partial    | reset        | RST              | accept=Closed                 | accept=Closed                 | yes         | pass |
| run     | server | partial    | nothing      | (held open)      | accept=Timeout                | accept=Timeout                | yes         | pass |
| run     | server | flight     | alert        | alert 2/48 clear | accept=Handshake              | accept=Handshake              | yes         | pass |
| run     | server | flight     | close_notify | alert 1/0 clear  | accept=Closed                 | accept=Closed                 | yes         | pass |
| run     | server | flight     | reset        | RST              | accept=Closed                 | accept=Closed                 | yes         | pass |
| run     | server | flight     | nothing      | (held open)      | accept=Timeout                | accept=Timeout                | yes         | pass |
| run     | server | finished   | alert        | encrypted 19 B   | accept=Ok lines=0 end=Closed  | accept=Ok lines=0 end=Closed  | yes         | pass |
| run     | server | finished   | close_notify | encrypted 19 B   | accept=Ok lines=0 end=None    | accept=Ok lines=0 end=None    | yes         | pass |
| run     | server | finished   | reset        | RST              | accept=Ok lines=0 end=Closed  | accept=Ok lines=0 end=Closed  | yes         | pass |
| run     | server | finished   | nothing      | (held open)      | accept=Ok lines=0 end=Timeout | accept=Ok lines=0 end=Timeout | yes         | pass |
| run     | server | record     | alert        | encrypted 19 B   | accept=Ok lines=1 end=Closed  | accept=Ok lines=1 end=Closed  | yes         | pass |
| run     | server | record     | close_notify | encrypted 19 B   | accept=Ok lines=1 end=None    | accept=Ok lines=1 end=None    | yes         | pass |
| run     | server | record     | reset        | RST              | accept=Ok lines=1 end=Closed  | accept=Ok lines=1 end=Closed  | yes         | pass |
| run     | server | record     | nothing      | (held open)      | accept=Ok lines=1 end=Timeout | accept=Ok lines=1 end=Timeout | yes         | pass |
| run     | client | hello      | alert        | alert 2/40 clear | connect=Handshake             | connect=Handshake             | yes         | pass |
| run     | client | hello      | close_notify | alert 1/0 clear  | connect=Closed                | connect=Closed                | yes         | pass |
| run     | client | hello      | reset        | RST              | connect=Closed                | connect=Closed                | yes         | pass |
| run     | client | hello      | nothing      | (held open)      | connect=Timeout               | connect=Timeout               | yes         | pass |
| run     | client | mid-flight | alert        | alert 2/40 clear | connect=Handshake             | connect=Handshake             | yes         | pass |
| run     | client | mid-flight | close_notify | alert 1/0 clear  | connect=Closed                | connect=Closed                | yes         | pass |
| run     | client | mid-flight | reset        | RST              | connect=Closed                | connect=Closed                | yes         | pass |
| run     | client | mid-flight | nothing      | (held open)      | connect=Timeout               | connect=Timeout               | yes         | pass |
| run     | client | finished   | alert        | encrypted 19 B   | connect=Ok read=Closed        | connect=Ok read=Closed        | yes         | pass |
| run     | client | finished   | close_notify | encrypted 19 B   | connect=Ok read=None          | connect=Ok read=None          | yes         | pass |
| run     | client | finished   | reset        | RST              | connect=Ok read=Closed        | connect=Ok read=Closed        | yes         | pass |
| run     | client | finished   | nothing      | (held open)      | connect=Ok read=Timeout       | connect=Ok read=Timeout       | yes         | pass |
| binary  | server | hello      | alert        | alert 2/40 clear | accept=Handshake              | accept=Handshake              | yes         | pass |
| binary  | server | hello      | close_notify | alert 1/0 clear  | accept=Closed                 | accept=Closed                 | yes         | pass |
| binary  | server | hello      | reset        | RST              | accept=Closed                 | accept=Closed                 | yes         | pass |
| binary  | server | hello      | nothing      | (held open)      | accept=Timeout                | accept=Timeout                | yes         | pass |
| binary  | server | partial    | alert        | alert 2/40 clear | accept=Handshake              | accept=Handshake              | yes         | pass |
| binary  | server | partial    | close_notify | alert 1/0 clear  | accept=Closed                 | accept=Closed                 | yes         | pass |
| binary  | server | partial    | reset        | RST              | accept=Closed                 | accept=Closed                 | yes         | pass |
| binary  | server | partial    | nothing      | (held open)      | accept=Timeout                | accept=Timeout                | yes         | pass |
| binary  | server | flight     | alert        | alert 2/48 clear | accept=Handshake              | accept=Handshake              | yes         | pass |
| binary  | server | flight     | close_notify | alert 1/0 clear  | accept=Closed                 | accept=Closed                 | yes         | pass |
| binary  | server | flight     | reset        | RST              | accept=Closed                 | accept=Closed                 | yes         | pass |
| binary  | server | flight     | nothing      | (held open)      | accept=Timeout                | accept=Timeout                | yes         | pass |
| binary  | server | finished   | alert        | encrypted 19 B   | accept=Ok lines=0 end=Closed  | accept=Ok lines=0 end=Closed  | yes         | pass |
| binary  | server | finished   | close_notify | encrypted 19 B   | accept=Ok lines=0 end=None    | accept=Ok lines=0 end=None    | yes         | pass |
| binary  | server | finished   | reset        | RST              | accept=Ok lines=0 end=Closed  | accept=Ok lines=0 end=Closed  | yes         | pass |
| binary  | server | finished   | nothing      | (held open)      | accept=Ok lines=0 end=Timeout | accept=Ok lines=0 end=Timeout | yes         | pass |
| binary  | server | record     | alert        | encrypted 19 B   | accept=Ok lines=1 end=Closed  | accept=Ok lines=1 end=Closed  | yes         | pass |
| binary  | server | record     | close_notify | encrypted 19 B   | accept=Ok lines=1 end=None    | accept=Ok lines=1 end=None    | yes         | pass |
| binary  | server | record     | reset        | RST              | accept=Ok lines=1 end=Closed  | accept=Ok lines=1 end=Closed  | yes         | pass |
| binary  | server | record     | nothing      | (held open)      | accept=Ok lines=1 end=Timeout | accept=Ok lines=1 end=Timeout | yes         | pass |
| binary  | client | hello      | alert        | alert 2/40 clear | connect=Handshake             | connect=Handshake             | yes         | pass |
| binary  | client | hello      | close_notify | alert 1/0 clear  | connect=Closed                | connect=Closed                | yes         | pass |
| binary  | client | hello      | reset        | RST              | connect=Closed                | connect=Closed                | yes         | pass |
| binary  | client | hello      | nothing      | (held open)      | connect=Timeout               | connect=Timeout               | yes         | pass |
| binary  | client | mid-flight | alert        | alert 2/40 clear | connect=Handshake             | connect=Handshake             | yes         | pass |
| binary  | client | mid-flight | close_notify | alert 1/0 clear  | connect=Closed                | connect=Closed                | yes         | pass |
| binary  | client | mid-flight | reset        | RST              | connect=Closed                | connect=Closed                | yes         | pass |
| binary  | client | mid-flight | nothing      | (held open)      | connect=Timeout               | connect=Timeout               | yes         | pass |
| binary  | client | finished   | alert        | encrypted 19 B   | connect=Ok read=Closed        | connect=Ok read=Closed        | yes         | pass |
| binary  | client | finished   | close_notify | encrypted 19 B   | connect=Ok read=None          | connect=Ok read=None          | yes         | pass |
| binary  | client | finished   | reset        | RST              | connect=Ok read=Closed        | connect=Ok read=Closed        | yes         | pass |
| binary  | client | finished   | nothing      | (held open)      | connect=Ok read=Timeout       | connect=Ok read=Timeout       | yes         | pass |

A control: the same script against the `mo` of `0493b26` (step 37 before its fix, `b0b2ac4`), as a
binary: the server died (exit 139, SIGSEGV) after the first reset mid-hello, and the client died
too; 0 of 33 cells (`work/abuse-control-0493b26.txt`). The table can fail.

## The suite

`zig build test --summary all`: 236 of 236 in 430 s at part A (load 7.03 6.38 5.94 at the start),
237 of 237 in 863 s at part B (load 3.77 5.04 5.57, beside the worktree builds), and 237 of 237 in 434 s after the final numbers (load 4.46 5.02
5.00 at the start, 5.06 5.74 5.40 at the end).

# Step 38 part C: the expected answer per cell, fixed before the run

Written by Fable, 18 Sep 2026, 9:56 AM ET (the commit 90cbc2f), from chapter 9's `## Tls` rows and the decision of 18 Sep
("a fatal alert from the peer during the handshake is `Handshake` on both roles and both runtimes;
`close_notify`, `user_canceled`, or the stream's end stays `Closed`; after the handshake a peer's alert
ends the stream as it does today"). Fable had not opened `toolchain/bench/step38/`, the worker's pane
output on part C, or any table of the worker's when this was committed; the worker (started 9:26 AM ET)
has not been shown this file. At acceptance the two tables are compared cell by cell; a difference is
settled by the spec, not by either table. The same 32 cells hold under `mo run` and as a binary: 64.

In every cell, besides the answer: the server takes and echoes the very next connection (server cells),
or the client process is alive and exits as its program says (client cells); no crash, no hang past the
deadline plus one second; resident memory not growing across 200 repeats of the cell.

## The server's handshake (`TlsServer.accept(conn, within: d)`); the peer is a raw client

| state when the peer acts | fatal alert | `close_notify` | reset (RST) | nothing until the deadline |
|---|---|---|---|---|
| S1 before any byte of the hello | `Handshake` | `Closed` | `Closed` | `Timeout` |
| S2 after a partial ClientHello | `Handshake` | `Closed` | `Closed` | `Timeout` |
| S3 after the server's flight, before the client's Finished (the peer's records are under the handshake keys; a harness that sends them in the clear instead gets `Handshake` in the first two columns, and the table must say which it did) | `Handshake` | `Closed` | `Closed` | `Timeout` |
| S4 after the client's Finished, before any application record | `accept` is `Ok`; the first read is the stream's end | `accept` is `Ok`; the first read is the stream's end | `accept` is `Ok`; the first read is `Closed` | `accept` is `Ok`; the first read is `Timeout` |
| S5 after the first application record was echoed | the next read is the stream's end | the next read is the stream's end | the next read is `Closed` | the next read is `Timeout` |

## The client's handshake (`TlsClient.connect(..., within: d)`); the peer is a raw server

| state when the peer acts | fatal alert | `close_notify` | reset (RST) | nothing until the deadline |
|---|---|---|---|---|
| C1 before the ServerHello | `Handshake` | `Closed` | `Closed` | `Timeout` |
| C2 mid-flight: after the ServerHello, before the server's Finished (same note on the handshake keys as S3) | `Handshake` | `Closed` | `Closed` | `Timeout` |
| C3 after the server's Finished and the client's | `connect` is `Ok`; the first read is the stream's end | `connect` is `Ok`; the first read is the stream's end | `connect` is `Ok`; the first read is `Closed` | `connect` is `Ok`; the first read is `Timeout` |

Never, in any cell: `Untrusted` (no chain is refused here), `Busy`, a process exit the program did not
ask for, or a state the harness did not actually reach (each cell's log must show the last handshake
message seen before the stimulus, so a cell that never reached its state is not counted as passed).

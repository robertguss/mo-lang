# Step 38's tools

A full-duplex `Conn`, `TCP_NODELAY`, and the handshake abuse rows
(`mo-wiki/plans/interpreter-step-38.md`). Plain Python 3 with no dependencies;
every `mo` process, every binary, and every server runs under step 36's
`guard.py` (a timeout and a 4 GB resident watchdog). Scratch files go to
`work/`, which git ignores, and every output begins with the date and `uptime`.
The numbers are in `RESULTS.md`.

- `abuse.py [--runtimes run,binary]`: the handshake abuse rows. At each state of
  the server's handshake (before the hello, after a partial hello, after the
  server's flight, after the client's Finished, after the first application
  record) and of the client's (before the ServerHello, mid-flight, after
  Finished), the peer sends a fatal alert, a `close_notify`, a reset, or nothing
  until the one-second deadline, and the Mo side's answer is checked against the
  cell's; after each cell a good peer checks the Mo side is alive (the server
  echoes the next client's line; the client handshakes with the next server and
  reads its line). 32 cells a runtime, as a table in `work/abuse.txt`. The Mo
  side is `abuse-server.mo` and `abuse-client.mo`; the peer is Python's `ssl`
  over memory (`MemoryBIO`), so each state is a point between two records the
  script holds, and each alert is one a real peer sends there (in the clear
  before any key; after, encrypted by the peer's own OpenSSL).
- `measure.py [--best-of 5] [--parts windows,echo,duplex,jobq] [--worktree label=commit] [--trees label=toolchain]`:
  the numbers, each tree's `mo` against itself. `windows` sends 3,200 lines of 4
  KiB through a Mo-to-Mo connection a window of 1, 16, or 256 lines at a time,
  each window written whole and then read back whole (`window-dial.mo` to step
  36's `plain-echo.mo` or `examples/effects/tls-echo.mo`), the pattern that
  waits out the peer's delayed ACK under Nagle; `echo` is `mo-bench --network`'s
  `echo-1k` rows; `duplex` times `examples/effects/duplex.mo` whole; `jobq` is
  `mo build examples/programs/jobq` warm and the binary's size.

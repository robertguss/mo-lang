# Step 36's tools

The TLS brick's audit items and numbers (`mo-wiki/plans/interpreter-step-36.md`). A `uv` project
with no dependencies: the client in every run is OpenSSL 3.0, which is already on the machine
(`/usr/bin/openssl`, and Python's `ssl` for the one run that needs a thousand connections in one
process). OpenSSL is dev-time tooling, the reference the brick is held against, and is never
linked into `mo` or into a binary it builds — the bricks page allows exactly that.

Run everything with `uv run python ...` from this folder. Every `mo` process, every binary, and
every `openssl` runs under `guard.py SECONDS -- cmd` (a timeout and a 4 GB resident watchdog), so
nothing here can hang or eat the machine. Scratch files go to `work/`, which git ignores; every
file a script writes there begins with the date and `uptime` as its first two lines, and each
script's table is written to `work/<script>.txt` as well as printed. The numbers are in
`RESULTS.md`. Since step 37 the fixture `cert.pem` is a chain (leaf, intermediate) and a client
trusts `root.pem` (`examples/effects/tls/gen.sh`).

- `common.py`: where the echoes are, how one is started under `mo run` or as a binary, how an
  `openssl s_client` is driven at it, and how a process's resident memory is read from `/proc`.
- `plain-echo.mo`: the same line echo as `examples/effects/tls-echo.mo` with no handshake between
  the socket and the reader. It is the baseline column in `bulk.py` and `idle.py`: the same
  program, the same runtime, the same loops, so the difference is the record layer.

- `handshake.py [--seconds 3] [--best-of 5] [--runtimes run,binary]`: handshakes a second, each
  suite and each key pair, both runtimes. The client is `openssl s_time -new`, which opens
  connections back to back in one process; a loop of `s_client` would measure `fork` and `exec`
  instead (about 38 a second on this machine). Every connection is a full handshake: the brick has
  no session tickets and no resumption. `s_time`'s exit code is checked, and the connections it
  counted in the best measurement are their own column. Alongside each measurement one `s_client`
  writes a line and reads it back, so a run that handshook fast and echoed nothing is caught; that
  column counts lost echoes, not failed handshakes among `s_time`'s connections.
- `bulk.py [--mib 100] [--best-of 5]`: bytes a second through the echo and back, over each suite
  against the plain echo, in decimal megabytes a second (10^6 bytes) of `--mib` mebibytes (2^20
  bytes each) sent one way. The client writes on a thread of its own and reads on the main
  one, since an echo deadlocks a client that writes everything before it reads.
- `idle.py [--connections 1000]`: the resident memory one idle TLS connection costs, against an
  idle plain one. Each connection is handshook and then left alone; the server's resident memory
  is read from `/proc` before the first and after the last, once it has stopped moving.
- `abuse.py [--wait 12]`: seven clients that are not a TLS 1.3 client — a plain HTTP request, a
  TLS 1.2-only client, one offering only P-256 key shares, a hello cut off mid-record, one that
  never finishes, a header declaring 65,535 bytes with 64 bytes of body, and a whole record of
  65,535 bytes — each answered with the alert or the timeout the brief names, with an eighth case
  for the one handshake that takes two rounds (a HelloRetryRequest). Immediately after each case,
  before the next begins, a good client echoes a line, so "still serving" is a whole round trip
  after that case. It exits 1 when any case was answered otherwise.
- `guard.py SECONDS -- cmd`: the timeout and the memory watchdog, the same one step 35 uses.

All four are read together: `handshake.py` says what the asymmetric work costs, `bulk.py` what the
record layer costs, `idle.py` what a connection holds while it does nothing, and `abuse.py` that
none of it can be made to fall over.

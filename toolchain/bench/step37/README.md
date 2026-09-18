# Step 37's tools

The TLS brick's client half, held against OpenSSL (`mo-wiki/plans/interpreter-step-37.md`, part
C): the differential run and the fuzz budget the bricks page names, and the client's numbers. A
`uv` project with no dependencies. OpenSSL 3.0 (`/usr/bin/openssl`) is the reference in every run
and is dev-time tooling, never linked into `mo` or into a binary it builds. Step 36's `guard.py`
(a timeout and a 4 GB resident watchdog) is shared: every `mo` process, every binary, every
`openssl`, and both tools below run under it. Scratch files go to `work/`, which git ignores, and
every file a script writes there begins with the date and `uptime` as its first two lines. The
numbers are in `RESULTS.md`.

Two tools, built from the brick by `zig build tls-tools` (from `toolchain/`; the scripts build them
when they are missing), both ReleaseSafe so a safety check that trips is a panic:

- `mo-tls-peer` (`peer.zig`): one TLS session over a real socket, the brick's exports driven as the
  runtimes drive them, printing what the engine saw (handshake, suite, ALPN, bytes, the alert and
  who sent it, KeyUpdates sent and read, close_notify) as one JSON line. The brick's side of
  `diff.py`.
- `mo-tls-fuzz` (`fuzz.zig`): the fuzz driver, a test executable so the brick's test hooks (fixed
  entropy) exist, which makes every canonical session the same bytes each time. It records the
  corpus (`MO_FUZZ_RECORD=dir`) and runs the inputs a file lists (`MO_FUZZ_INPUTS=file`).

And three scripts, each run with `uv run python <script> ...` from this folder:

- `diff.py --seed S [--sessions 1000]`: the differential run. Each session draws the role (the
  brick's server against `openssl s_client`, or its client against `openssl s_server`), the key
  type, OpenSSL's suites and groups (`P-256:X25519` among them, for the retry), ALPN on each side or
  none, SNI on or off, a chain from `examples/effects/tls/gen.sh`'s set (good, or one of the
  refusals), the writes of an echo from 0 to 20,000 bytes, a KeyUpdate from OpenSSL (`K` on its
  stdin), from the brick (asking for an answer or not), or none, and who closes first. The facts
  (handshake, suite, ALPN, echo, the alert and its sender, the KeyUpdates each way, the first
  close_notify) are compared three ways: the brick's view, OpenSSL's (its `-msg` log, its `-brief`
  summary or connection report, what it echoed), and what the parameters say. `work/diff-<S>.log`
  has one JSON line a session; the mismatch count is the result.
- `fuzz.py --seed S [--minutes 60]`: the fuzz budget. The sixteen canonical sessions (each suite,
  key type, ALPN or none, HelloRetryRequest or none) mutated one to four times from the seed and fed
  to a fresh server and a fresh client at every state, as records and, behind the AEAD, as
  handshake messages. It stops at `--minutes` of the driver's CPU time; a signal, an abort, a
  panic, or a step past two seconds is a crash, kept under `work/fuzz-<S>/crashes/`. Before the
  hour it checks itself: a planted panic and a planted hang must each be counted.
  `work/fuzz-<S>.txt` has the count.
- `measure.py [--best-of 5]`: the client's numbers under `mo run` and as a binary: handshakes a
  second against `openssl s_server` for each key type, Mo client to Mo server, 100 MiB through a
  Mo-to-Mo connection over TLS and plain, the chain check's cost (the chain of three against a
  self-signed leaf), and `mo build examples/programs/jobq` warm with the binary's size, before
  step 37 and after. The client is `tls-dial.mo`, in this folder. `work/measure.txt` has the
  tables with the load average beside each.

`common37.py` holds what they share: the paths, the stamp, the fixture chains, and a reader for
OpenSSL's `-msg` log.

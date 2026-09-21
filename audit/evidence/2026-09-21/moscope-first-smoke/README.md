# Moscope first authorized build and smoke

21 Sep 2026, 5:52 PM ET. Lead-executed once, stop-first; no retry.

- Source: 7aa1e81ea6dc0126214424bef24ae69f85a149f3.
- Accepted toolchain/guard base: dad7b3743da38d929f632d70db42e592cd1b755e.
- Only examples/programs/moscope differs from accepted base; toolchain and
  guards unchanged. Isolated checkout /tmp/mo-moscope-7aa1e81e, clean before and
  after. Fresh local/global caches, install prefix and minimal child HOME.
- Build command/combined raw log/real exit: build-command.json, build.log,
  build-exit.json. 900-second guard; exit0, Build Summary5/5.
- Smoke command/real exit: smoke-command.json, smoke-exit.json. 60-second guard.
  Shell exec redirects exact child streams to smoke.stdout/stderr; wrapper
  output_bytes therefore measures its empty combined stream, not those split
  files. Split streams are 0 and338 bytes. No output-overflow claim.
- Smoke exit1: MO0101 expected a name to expose, limits.mo:2:87. App search did
  not execute; expected status0/four matches was not obtained.
- Build PGID644531 and smoke PGID645176 absent in guard receipts and the
  subsequent ps snapshot (remaining-processes.txt is empty).
- No native/full-corpus/private-data/Step42 execution, edits or retries.
- source.bundle preserves the complete candidate above prerequisite dad7b374;
  verified SHA256
  07650749901f14c6dbff15149dd39d5544f42b050389e122364756f79f9a1908.

This is a failed smoke checkpoint, not acceptance. Source review missed this
parser incompatibility. Further implementation/execution decisions remain held.

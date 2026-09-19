# Provider foundation

A provider-only one-turn library for GPT-6 Astra, low reasoning, SSE. It executes
no tools and performs no login, OAuth refresh, credential persistence, inference
in tests, or Mo/compiler work. `turn.d.mts` defines the input/result contract.

The caller supplies native Pi `Context`, a fixed list of JSON-schema tools, an
already resolved access token, and a fetch-compatible transport. No ambient
credential lookup is used. `createModels`, `openaiCodexProvider`, `getModel` and
`complete` come from the exact pinned source. The provider's auth descriptor is
replaced with a request-only resolver; its transport/parser remain upstream.
The stock Models collection's empty in-memory defaults never receive credentials.
Only the fixed Codex POST endpoint is dispatched; redirects are forbidden.
A caller-supplied transport is trusted to perform that request and honor aborts;
it is not an OS network sandbox. Tests constrain sockets to one fixture listener.

A success returns final text or exactly one strictly validated JSON tool call,
plus the native assistant message. The caller retains native history, tool IDs,
text and reasoning signatures and supplies subsequent tool results. The library
does not mutate its caller's history. Transcript tool additions/removals are
rejected because this slice has fixed schemas. Grammar/custom tools, parallel
calls, invalid JSON, arrays, unknown tools and coercion-dependent arguments are
unsupported. The native message is for continuation, not usage accounting.

Usage is separate from Pi's normalized native `message.usage`: `unknown`, or
`reported` with noncached input, output, cache read, cache write and total.
Every input/output/total/cache field must actually be present, a nonnegative safe
integer, and arithmetically consistent. Missing cache-write is unknown even if
Pi reports zero. Optional reasoning tokens are a subset of output. Cache counts
are subtracted from input exactly once. Reported all-zero usage is valid.
No cost or billing-limit claim is made. `legacyUsage` throws for unknown usage;
the legacy Mo contract was not changed.

Errors contain only `{code}` from authentication/provider/timeout/cancelled/
incomplete/unsupported and unknown usage. No raw upstream diagnostic, response,
header or credentials escape in error results. HTTP 401 is authentication;
other HTTP errors and explicit upstream errors are provider failures. EOF before
terminal completion and malformed SSE are incomplete; an upstream incomplete
terminal is also incomplete. Unsupported decoded response/tool shapes are
unsupported. Caller/upstream cancellation is distinct from the local deadline.
Retries are explicitly zero. Default and maximum deadline are five seconds.
The 64 KiB bound covers the entire decoded response body (including SSE framing
and error bodies), a deliberately stricter bound than final text alone.

## Source and artifact identity

- Exact source: [Pi 36b60d2e8985899743c4cf5bd5f8929832a3f05d](https://github.com/earendil-works/pi/tree/36b60d2e8985899743c4cf5bd5f8929832a3f05d/packages/ai).
  MIT; source archive 7,833,334 bytes, SHA-256
  `c2a574794f1fc26510729f2341c4c4990cfa385caf47b011bdca19afa3d22903`.
- [Registry artifact 0.85.1](https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-0.85.1.tgz):
  798,833 bytes, SHA-256
  `af7d11986179445ce6fe88b37d57de22f823c0ffd3a65cae31c555b7f5e99253`.
  Registry SHA-512 integrity is verified separately. Versions, integrity, URLs
  and licenses for all 92 installed packages are in `evidence/dependencies.json`.
- The artifact is **not** the pinned source: 148 of 177 embedded TypeScript
  sourcemap sources match; 29 differ or are absent. Relevant provider/shared
  parser/Models differences involve the native transcript migration. Auth
  resolution and Codex OAuth sources match. `pin.json` records every comparison.
  This is source-map comparison, not a reproducible-build attestation.
- Execution uses the git TypeScript source through Node's native type stripping,
  not the artifact's provider/parser JS. `upstream.patch` adds one observational
  SSE hook immediately after JSON parsing, before existing mapping/normalization.
  It exposes no public raw events; only the internal adapter consumes it.
- The artifact supplied ignored generated catalog data for hydration. The selected
  Astra entry is regenerated offline from the pinned generator's explicit Codex
  literal and complete metadata pass, with no models.dev/network fetch. Its
  committed `catalog.json` SHA-256 is
  `3d3b5959b8bdd6dfd96b435501b298f32ab9406b1fe8a84555f00651ed039744`.
  All fields match the artifact except the pinned generator additionally sets
  `compat.supportsMidConvoSystemMessages=true`. `evidence/catalog-comparison.json`
  contains both entries. Other hydrated provider catalogs remain artifact-derived,
  are not registered or used by this adapter, and are not claimed to match the pin.
  Every local runtime file is hashed in `evidence/runtime-hashes.json`.

## Reproduce

Run from the repository root, in a fresh owned Herdr run pane without focus.
Use a new evidence directory name for each attempt. This command is safe to run
from main: it creates a fresh provider copy under ignored `.cache/`, runs the
complete documented sequence there, and compares generated records with the
originals. It refuses an existing output directory. Historical tracked bytes
are checked unchanged; setup outputs stay in the owned copy.

```sh
python3 toolchain/bench/step36/guard.py 1200 -- python3 toolchain/harness/provider/clean_setup.py evidence/clean-review-01
```

The seven steps are a cold `node --version` under `executor/guarded.py --home`, `setup.py`, locked `npm ci`,
`provenance.py`, `prepare.py`, `catalog.mjs`, and `verify.py`. Each has a 150-second
guard; npm/Node runner children have an earlier 100-second process-group bound.
The output directory records exact commands, real exit codes, logs, before/after
tracked hashes and seven generated-record comparisons. The owned copy starts
without `.cache` or `node_modules`; the cold runner has its own empty directory.

For provider tests after setup, use the copy path printed in the new
`commands.json`, preserving the original provider directory. From repository root:

```sh
python3 toolchain/harness/executor/guarded.py 550 <owned-copy>/evidence/review-run --cwd <owned-copy> --home <owned-copy>/.cache/home -- node test.mjs evidence/review.outbound.json
```

`executor/guarded.py` (which replaced the copied `run.py` runner) resolves
Node/npm/zig from PATH before constructing an empty-home, isolated-npm
environment, and records the command, paths, git head and real exit code. It
runs the command under `step36/guard.py` in an owned process group and kills
remaining descendants before returning. No npm lifecycle scripts run. Direct setup/provenance/prepare/catalog/
verify commands regenerate records in their own directory, so use the clean-copy
command above instead of invoking them against historical evidence on main.

`setup.py` verifies immutable source/artifact hashes before extracting. `prepare.py`
hydrates ignored source and applies the disclosed patch; `catalog.mjs` evaluates
only the pinned static Codex catalog section/metadata and replaces the selected
runtime catalog. No upstream generation main or remote catalog fetch runs.
`verify.py` checks downloaded integrity, runtime hashes, catalog and dependency
metadata. Preserve each attempt's stdout/stderr and real exit code separately.
There is no compiled output/build step and no TypeScript compiler check claimed.

The test executable always runs its fixed cases and fails on an empty count.
It uses real HTTP responses from an ephemeral loopback server, the actual pinned
provider transport/parser, synthetic JWT-shaped credentials and secret canaries.
Fetch/WebSocket and HTTP/TLS/DNS entry points are denied; sockets allow only the
fixture's loopback port. Unexpected fetch/socket/HTTPS attempts are asserted
rejected. Observations retain outgoing payloads but omit all request headers and
credentials. Fixture sockets are closed before the test process exits.

Initial test: 23/23, Node 24.19.0. Final expanded test: 28/28, Node 24.20.0/npm
11.19.0 resolved from the run pane's PATH. The first npm install failed due to
using the same empty config path for user/global config; its failure is retained.
Separate local config paths fixed it. See `evidence/commands.json` for attempts.

This supplies offline provider evidence only. Lead review and integrated-tree
acceptance with an additional control remain. Real OAuth, model/account
entitlement, live inference, full coding path, Mo contract integration and
compiler/runtime acceptance are outside this slice.

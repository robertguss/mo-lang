# Worker handoff — provider foundation

Worker: GPT-6-Astra, low reasoning; lead `w4:p1`, worker `w4:pX`, owned run pane
`w4:pZ` (created to the right without focus). Branch
`harness/provider-foundation-r01`; exact base
`f093d6b6a988195561a6b57b35738b972bb5e94e`. Local tip is the commit containing this
report; obtain it with `git rev-parse HEAD`. No push or integration performed.

Scope: only new `toolchain/harness/provider/` source, types, local package/lock,
provenance scripts, README, patch and evidence. Dependencies/source caches are
ignored inside that directory. No Mo, compiler, executor, wiki, global config,
credential files, OAuth login, inference or nested agents were used.

The library executes one pinned Pi SSE turn with explicit supplied credentials,
fixed tools, no parallel calls/retries, 5-second default/max deadline and 64 KiB
body bound. Results separate tool/final text, allowlisted failure classes and
reported/unknown usage. Native messages and signatures are retained for the
caller. There is no server, credential store or replay journal in the library.

## Verification

`commands.json` records every setup/install/test attempt's exact command, guard,
exit and log. Setup guards were 1200 seconds; test guards 600 seconds, with an
owned process-group limit of 550 seconds and descendant cleanup. No timeout fired.
Metadata and source review were ordinary read-only shell/Python inspections.

- setup-01: exit 0, source and artifact downloaded separately.
- install-01: exit 1, npm rejected double-loading the same empty user/global
  configuration file. Retained; fixed with separate local empty files.
- install-02 and clean install-03: exit 0, 92 packages, scripts disabled.
- provenance-01/02/03, prepare-01/02, catalog-01 and verify-01: exit 0.
- test-01: exit 0, 23 fixed cases, Node 24.19.0, initial artifact-derived catalog.
- test-02: exit 0, 28 fixed cases, final pinned-generator catalog.
- test-03: exit 0, same 28 cases after clean locked install; Node 24.20.0/npm
  11.19.0 resolved from the owned pane PATH. Runtime prerequisite >=22.19.0 met.
- Three explicit unexpected egress attempts rejected; HTTP 401/503 each made
  exactly one request. Loopback sockets closed before test exit. Error results
  and retained logs contain no upstream secret canary.
- No compiler/build or TypeScript compiler acceptance claimed. Native Node
  TypeScript stripping executes pinned upstream source.

Evidence is about 0.31 MiB total, below 16 MiB per attempt. Outbound fixture
payloads are retained without credential headers. Earlier outputs/failure are
preserved; final reproducible source is this commit.

## Provenance and bounded decisions

Pi source revision `36b60d2e8985899743c4cf5bd5f8929832a3f05d` declares package
0.85.1, but its registry artifact differs: 148/177 embedded source files match,
29 differ or are absent. The provider/shared parser/Models transcript migration
is materially different; the relevant diff is retained. Therefore execution
uses exact git TypeScript with only the disclosed 4-hunk observational parser
patch. Auth resolution/OAuth source comparisons match, but this library uses a
request-only auth descriptor so neither storage nor OAuth refresh is entered.

The npm artifact is retained as dependency/catalog provenance, not falsely
identified as the git build. Archive sizes/hashes and registry integrity are in
`downloads.json`; dependency versions/integrity/licenses in `dependencies.json`.
The frozen selected Astra catalog is evaluated from the pinned generator's static
Codex literal and complete metadata pass, without network main execution. It
agrees with the artifact except that pinned source adds
`compat.supportsMidConvoSystemMessages=true`. Both entries/difference are retained.
Unused hydrated provider catalog data remains explicitly artifact-derived.

Conservative choices for lead review: full SSE-body limit (stricter than text
only), missing cache-write usage is unknown, fixed-schema transcript changes
rejected, malformed SSE classified incomplete, no public raw diagnostics.
Caller-supplied fetch is a trusted transport capability, not an OS sandbox;
its pending promise cannot be forcibly stopped if it ignores abort, but the
library deadline still returns and cancels a response arriving later.

## Remaining obligations

Lead review of the narrow upstream patch and independent integrated-tree tests
with an additional control remain. No live OAuth, account/model entitlement,
inference, full coding path, Mo legacy-contract integration or compiler/runtime
acceptance is claimed. Worker stays available for review corrections. Only its
owned run pane may be closed after writers stop and evidence is retained.

Precommit whitespace check passes when excluding the two verbatim `.patch`/`.diff`
artifacts. Unfiltered `git diff --check` flags their unified-diff context prefix
before upstream tabs/blank lines; those evidence bytes were deliberately retained.
Owned run-pane process inspection showed only its foreground zsh prompt after
final tests, with no test/setup writer remaining.

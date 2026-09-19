---
title: "Mo provider foundation: pinned Pi turns and honest usage"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, verification, contracts]
sources: [plans/mo-first-coding-harness.md]
status: ready
---

# Mo provider foundation: pinned Pi turns and honest usage

## Orientation

Provider-independent executor and terminal-401 work run separately. This slice
prepares the provider-only boundary for [[mo-first-coding-harness]], using
synthetic upstream responses and no real credentials or inference. Astra leads;
a fresh Astra/low Herdr worker implements it. The lead repeats acceptance.

The read-only source review is retained under
`audit/evidence/2026-09-19/provider-readiness/`. Its exact source is Pi revision
`36b60d2e8985899743c4cf5bd5f8929832a3f05d`, whose package declares
`@earendil-works/pi-ai` 0.85.1. Package version alone does not establish source
identity. Generated provider catalogs are absent from that git revision; the
implementation must freeze the actual catalog and artifact it uses.

The lead selects `gpt-6-astra`, low reasoning and SSE for this initial adapter.
That is a configuration decision, not proof of account entitlement, a scored
experiment or a model comparison. Mo owns subsequent turns and every tool
execution. The full Pi/Codex agent is outside scope.

## Write scope

One worker owns only new `toolchain/harness/provider/`: source, package/lockfile,
pin manifest, a narrowly disclosed upstream patch if necessary, focused tests,
README and bounded evidence. Dependency/source/build caches stay inside that
directory and are ignored. Do not commit node_modules or an entire upstream
checkout. No Mo source, compiler, executor, wiki, global Node configuration,
real credential files, OAuth login or live model request. No nested workers.

Dependency downloads are authorized from the official source/npm registry.
Record versions, integrity hashes, license and the difference between source
and artifact provenance. Use the installed Node if compatible; report an unmet
runtime prerequisite to the lead. Installation/build/test commands have numeric
guards and run in owned Herdr panes. The worker has a separate worktree at an
explicit base, may commit owned paths locally and may not push.

## Parts

1. Reproduce the provider artifact at the stated pin. Prefer public
   `createModels`, `setProvider(openaiCodexProvider())`, `getModel` and one-turn
   `complete` APIs. Read their actual source/types before coding. Resolve and
   record generated-catalog provenance; do not silently use latest model data.
   If an npm artifact is used, verify the relevant shipped provider/auth/parser
   implementation against the git pin and record any differences explicitly.
2. Implement a small provider-only turn boundary with explicit input and result
   types. Accept a caller-owned native conversation and supplied fixed tool
   schemas; preserve native messages, tool-call IDs and reasoning signatures.
   Return one validated tool call or final text. Never execute a tool. Set
   parallel tool calls false and reject multiple calls or incompatible argument
   shapes instead of dropping or stringifying values.
3. Disable hidden provider retries (`maxRetries: 0`) and use finite deadlines
   and cancellation. Distinguish completion, authentication failure, other
   provider failure, timeout/cancellation, incomplete stream and unsupported
   response. Return only allowlisted error fields, never raw upstream errors,
   bodies, headers or credential objects.
4. Preserve usage honesty. Pi's normalized zero can mean absent upstream
   usage. Track actual field presence at the SSE boundary: use a supported hook
   if sufficient, otherwise a minimal reviewed patch exposing presence beside
   the existing parser. Do not infer presence from a nonzero normalized value.
   Represent complete valid upstream usage as reported, including input/output
   and cache breakdown; missing, partial or invalid usage is unknown. Reported
   zero is distinct from unknown. No fabricated zero or billing-cap claim.

This slice is a library plus offline executable fixture tests, not an HTTP
server, credential store or replay journal. It retains native messages for its
caller; the later Mo bridge owns serialized per-run history and recording before
subsequent work. The legacy Mo reply cannot represent unknown usage: it must
fail explicitly if used without a versioned contract change. Do not amend that
contract here merely to make fixtures succeed.

## Numbers and checks

At most 30 fixed offline cases per attempt, ten-minute outer guard, five-second
default simulated turn deadline and 64 KiB response-text limit. Retain failed
attempts and real exit codes, with at most 16 MiB committed evidence per attempt.
Bound setup attempts to twenty minutes; record source/artifact sizes separately.

Use the actual pinned provider SSE parser with synthetic responses, including:

- final text; one tool call then its result and next turn; IDs and opaque
  signatures preserved; parallel calls disabled in the outgoing payload;
- multiple calls, non-string arguments and malformed/incomplete responses;
- complete positive usage, complete reported zero, missing usage, partial usage
  and invalid counters, preserving cache accounting without double counting;
- real fixture HTTP 401 with exactly one attempt, other provider errors,
  cancellation, finite deadline and stream truncation;
- credential-shaped canaries in upstream bodies/errors, with no canary in any
  public error/log, and an attempted unexpected network request rejected.

Tests must intercept or constrain every network path and use synthetic
credentials only. Exercise the actual transport/parser, not solely adapter
mocks. Keep outbound request observations in evidence with synthetic secrets
redacted; assert canary isolation separately. Empty test selection must fail.

## Done when

The exact pin/artifact/catalog relationship is documented, focused checks pass
through the actual parser, result/usage/error distinctions are demonstrated and
no source outside the allowlist changes. Report counts, source links, commands,
real exit codes, remaining limitations and decisions the brief did not cover.
The lead reviews the patch and repeats tests from the integrated tree with an
additional control. Python/Node-only work makes no compiler/runtime acceptance
claim. This is not live OAuth, account/model entitlement or a full coding path.

## Related

- [[mo-first-coding-harness]]
- [[mo-agent-terminal-auth]]
- [[mo-executor-foundation]]
- [[decision-log]]

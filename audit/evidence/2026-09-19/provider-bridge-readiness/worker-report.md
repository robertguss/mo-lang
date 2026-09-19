**Recommend an offline bridge v1 with strict unknown-usage failure, native-history journaling, and no Mo edits.** Keep credential-store/device-login work independently owned and offline. Reviewed committed `2fc1235bd1f44ae7897ed059ece8cb9b30ce307d` plus cached pinned Pi source; no writes, tests, builds, auth, network calls, candidate processes, or nested agents.

1. **Wire compatibility and acknowledgment**

   **Facts:** Mo sends `POST /complete`, `content-type: application/json`, `x-run: <run>`, and `{"goal":string,"tools":string[],"transcript":object[]}`. Replies are `{"tool":string,"args":object-of-strings,"tokens":integer}` or `{"done":string,"tokens":integer}`. Tokens are mandatory; parsing passes through signed integer conversion. Only HTTP 401 bypasses configured retries. [Model:129–253](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/model.mo:129)

   Transcript steps contain `n,kind,name,args,result,tokens,took_ms,refused`; model `result` contains only tool/arguments or final text. Native IDs, reasoning signatures and assistant metadata cannot be reconstructed from this projection. [Transcript:10–39](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/transcript.mo:10), [Steps:173–253](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/steps.mo:173)

   Pi retains complete `AssistantMessage`, composite tool IDs, text/reasoning signatures, and `ToolResultMessage.toolCallId`. Responses conversion replays signatures and splits tool IDs into call/item IDs. Preserve the returned native message unchanged; construct the tool result using its original complete ID. [Pi types:508–542](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/provider/.cache/clean-setup-8f3xpo0r/.cache/runtime/types.ts:508), [conversion:253–325](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/provider/.cache/clean-setup-8f3xpo0r/.cache/runtime/api/openai-responses-shared.ts:253)

   **Recommendation:** Bridge-owned fixed schemas, filtered by frozen grants; reject non-string arguments rather than stringify. Freeze goal/tools and accepted transcript prefix. Each continuation must add exactly the matching model step and one matching tool step, with consecutive numbers and validated types. Preserve structured fixture result JSON as text; derive `isError` from its validated state, or legacy `refused` where applicable.

   **Acknowledgment limit:** Run advances only after `Book.Write → Go`; Book appends before returning its verdict. Thus the trusted Run’s next transcript implies those acknowledgments. It is not independent proof against a forged caller. Book’s duplicate handling checks step number, not matching content. [Run:107–147](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/run.mo:107), [Filing:190–220](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/filing.mo:190)

   Reject duplicate, stale, conflicting, concurrent and uncertain requests without resending upstream or returning a cached actionable reply. Final answers have no subsequent transcript acknowledgment: label them “offered,” not “Book-recorded.” Independent acknowledgment would require a separately versioned trusted receipt interface.

2. **Unknown usage**

   **Facts:** `turn` exposes reported/unknown usage separately from native messages; complete counters include cache accounting. `legacyUsage` throws on unknown. Failed Mo calls currently become transcript token zero, so that field cannot establish actual provider usage. [turn:9–19,125](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/provider/turn.mjs:9), [types](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/provider/turn.d.mts:1), [Steps:249](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/steps.mo:249)

   **Choose v1:** Unknown usage terminally fails before exposing any tool/final response; journal `usage:unknown`, return sanitized HTTP 422, and require Mo retries zero. Reported zero remains valid. Use reported `total` exactly once; reject unsafe/overflowing counters. Partial totals remain explicitly incomplete.

   Continuing with unknown requires **v2**, covering Model reply/error types, recipe binding, Steps accounting/budget policy, persisted Transcript/Book/Record serialization and replay, API/report schemas, and old-log compatibility. Merely adding nullable HTTP tokens is insufficient. Keep this outside the active fixture’s explicit schema-preservation contract. [Fixture:113–124](/Users/robertguss/Projects/startups/mo-lang/mo-wiki/plans/mo-coding-fixture-v1.md:113)

3. **Smallest server/journal**

   **Recommended contract:** One operator-provisioned run per bridge process; fixed loopback endpoint, fixed model/catalog/schema identity, no dynamic registration or tool execution. Bind the run to a unique session namespace so legacy `r_1` reuse cannot revive old state.

   State machine: `ready → dispatch-intent → awaiting-recorded-tool → dispatch-intent …`; final becomes `final-offered`; errors become terminal; ambiguous dispatch/journal/reply loss becomes `uncertain`. Persist intent before upstream dispatch and native result plus Mo projection before HTTP reply. Persist validated continuation before the next dispatch. Journal failure stops; restart never resumes or replays. Retain terminal tombstones; malformed/truncated journals refuse startup.

   Journal stores version, session/run identity, sequence, frozen configuration identity, accepted prefix, pending projection/native message, usage and outcome—never credentials. Use bounded atomic snapshot replacement; claim no crash durability until separately evidenced.

   Proposed bounds: one active request; no waiting queue; 16 steps; 64 KiB request/reply/native context; 2 MiB journal; 30-second session; two-second body/provider/reply caps under remaining session time; finite journal waits within a separate 15-second closing grace. Enforce bytes while reading, including chunked bodies; no compaction.

   Preserve real 401 and terminalize without refresh. Other provider failures also terminate this profile. Disconnect/stop aborts pending inference, suppresses late actionable replies and prevents further dispatch; it does not prove upstream cancellation or command cleanup. The existing adapter already disables retries and bounds SSE, but lacks this server/journal. [turn:23–38,69–121](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/provider/turn.mjs:23)

4. **Independent auth seams**

   **Pinned APIs:** `openaiCodexProvider().auth.oauth` supplies `login`, `refresh`, `toAuth`. Login’s select prompt accepts `device_code`; `notify` carries the verification URI/code. Credentials require explicit app persistence. `CredentialStore` supplies `read/list/modify/delete`; `modify(undefined)` means unchanged, not deletion. Refresh uses double-checked locking through `modify`. [Auth types:50–94,156–229](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/provider/.cache/clean-setup-8f3xpo0r/.cache/runtime/auth/types.ts:50), [OAuth:515–543](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/provider/.cache/clean-setup-8f3xpo0r/.cache/runtime/auth/oauth/openai-codex.ts:515), [resolve:119–175](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/provider/.cache/clean-setup-8f3xpo0r/.cache/runtime/auth/resolve.ts:119)

   **Recommendation:** Separate operator-only auth component. Explicit harness store path, inaccessible to candidates; private directory/files, symlink rejection, one serialized writer across login/refresh/delete, atomic same-directory replacement, persistence failure propagated before releasing credentials. Prevent an older pending login from resurrecting logout using an operation generation. No ambient auth resolution; resolved access token enters `turn` only in memory.

   Offline seam tests must intercept **global fetch**: pinned OAuth does not accept the inference adapter’s injected transport. Allowlist statuses; never serialize exception messages, causes, raw auth events or credentials. Only the operator channel receives validated device URI/code. [OAuth:115–139,427–441](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/provider/.cache/clean-setup-8f3xpo0r/.cache/runtime/auth/oauth/openai-codex.ts:115)

   Defer browser fallback: its manual-input path permits absent state. Registration/support, entitlement, isolation and live login remain unaccepted. [OAuth:479–500](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/provider/.cache/clean-setup-8f3xpo0r/.cache/runtime/auth/oauth/openai-codex.ts:479)

5. **Ownership, prerequisites and 28 controls**

   Bridge worker owns only new `toolchain/harness/provider/bridge/`; separate auth worker owns only new `toolchain/harness/provider/auth/`. Freeze provider foundation files. Lead owns brief/version decisions and independent acceptance. No edits to active fixture paths; Mo integration waits for its committed, accepted tip, verified zero retries and reporting contract.

   Freeze these **28 named offline controls**: final; tool continuation; native signatures/IDs; schema/string rejection; reported usage; reported zero; unknown usage; counter overflow; duplicate; stale; altered prefix; skipped step; mismatched tool; changed goal/grants; concurrent request; restart tombstone; journal failure; lost reply; terminal401; other provider failure; deadline; stop/disconnect; body/context/journal limits; auth device events; auth cancellation/global-egress interception; serialized refresh/delete/login; atomic-store failure/isolation; secret-canary sanitization.

   Actual pinned-parser synthetic transport, independent request counts/order, empty-selection rejection, ten-minute guarded attempts and ≤16 MiB evidence. No live-auth or containment acceptance claim. Read-only review complete; idle.

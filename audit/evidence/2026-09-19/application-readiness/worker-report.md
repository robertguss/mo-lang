Recommend **one provider-independent Logstat repair slice**, preceded by application-container readiness. Keep the accepted workspace lifecycle intact, add an explicit application-build policy, and route every candidate file operation through the same Linux workspace.

Reviewed main `e6f04ce` using local source reads only. Graph MCP was unavailable; ast-grep does not support Zig here. No implementation, tests, builds, network, machine administration, credentials or nested agents.

**1. Source facts: toolchain dependencies and layout**

`main.zig` loads the application before choosing build or interpreter execution. Build checks the program, invokes `cbuild.build`, and reports compiler failure; `mo run` initializes the interpreter’s server from the actual working directory. Thus source resolution and runtime filesystem location are separate dependencies. See [main.zig:246](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/main.zig:246), build at 263–288 and run at 291–328.

`mo build` embeds the C runtime/header and both crypto/TLS brick sources. It writes generated C/runtime files, compiles both bricks with Zig, then invokes `zig cc`; Linux defaults to the matching architecture’s musl target and static linking. Zig is searched beside the executable, then on PATH. Application builds therefore need **no external Mo runtime-source tree**, but require Zig, its distribution `lib/`, and writable output/cache locations. See [cbuild.zig:41](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/cbuild.zig:41), 99–139, 152–198; embedding setup is [build.zig:24](/Users/robertguss/Projects/startups/mo-lang/toolchain/build.zig:24).

The brick cache hashes source, target/CPU selection and **Zig’s pathname**, not Zig’s executable contents. Use immutable image/toolchain identity and fresh trial scratch; do not replace Zig under a stable path and reuse old objects.

Module lookup uses the nearest ancestor `mo.root`, otherwise the entry file’s directory. Imports resolve beneath that root; loading also reads `.mo.ids`. There is no general external Mo library search in this helper. Preserve root-relative module paths and matching sidecars. See [program.zig:100](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/program.zig:100), 140–150 and 290–294. Prelude definitions are compiled Zig tables, not runtime-loaded `PRELUDE.md`: [prelude.zig:1](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/prelude.zig:1).

**Proposed immutable image layout:** `/opt/mo/mo`, adjacent pinned `/opt/mo/zig`, matching `/opt/mo/lib/`, and a pinned shell. Retain version-matched help/PRELUDE guidance as protected documentation. No compiler checkout, package manager, credentials or verifier results inside the image. `/workspace` remains the registered source tree; `/build` is fresh executable scratch containing generated outputs and private Zig caches. Build from `/build` using absolute `/workspace/...` source paths; execute with an explicitly selected application cwd. Zig `lib/` relocation and cache-environment behavior require packaging verification.

**2. Lead decision: a separate application-build policy**

The existing validator hardcodes 64 MiB, 0.25 CPU, 16 PIDs, no network, readonly root, UID 65534, fixed environment and noexec temporary filesystems. Those checks cannot be broadened under the existing policy identity. See [remote.py:40](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/remote.py:40). Workspace commands additionally retain the 10-second maximum: [workspace plan:109](/Users/robertguss/Projects/startups/mo-lang/mo-wiki/plans/mo-workspace-foundation.md:109).

Propose a new, lead-ratified `application-build-v1`:

- Candidate: **1 GiB memory, no additional swap, 1 CPU, 128 PIDs, 120-second command maximum**, combined 64 KiB captured output.
- Fresh `/build`: **512 MiB/16,384-inode tmpfs**, executable, nosuid/nodev; charged within candidate memory. Separate 16 MiB noexec `/tmp`.
- Preserve the existing 64 MiB/4096-inode noexec source workspace and file-operation limits.
- Preserve network denial, readonly image, dropped capabilities, no-new-privileges, exact mount/environment validation and one active candidate.

These are **trial ceilings, not demonstrated sufficient sizing**. The existing 512 MiB parent would cap this candidate regardless of its own limit. Lead must explicitly approve a separately identified application parent capped at **1536 MiB**, preserving the old slice/policy and reserving nominal machine headroom on the 2 GiB/2 CPU machine. Admission must also exclude concurrent bootstrap/build work; headroom is not a guarantee.

Reuse timer registration, one-shot dispatch, supervisor/container/cgroup cleanup proof, then deadline-unit removal—[remote.py:101](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/remote.py:101). Preserve close-before-copy, validated bytes/modes, protected inventory and snapshot identity—[workspace_controller.py:162](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace_controller.py:162). Scratch stays outside the source snapshot. Final verification rebuilds from the readonly snapshot into empty scratch.

**3. Source fact and proposed HTTP/Mo seam**

Current fixture execution is split: command dispatch is remote, while ordinary file tools use local `Fs` and `Writer`; exact edit also receives the local writer. See [run.mo:149](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/run.mo:149), 198 onward, and [tools.mo:86](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/tools.mo:86). Merely replacing the command fixture with real Linux execution would be incoherent.

Add one explicit **workspace profile** that routes all six tools—list/read/search/write/exact-edit/command—to a trusted HTTP adapter over the existing workspace controller. No local fallback. Provision run/workspace identity outside model arguments; every operation carries a unique call ID, bounded request, deadline and validated response identity. Keep lifecycle/snapshot administration operator-only.

Translate the executor’s base64 streams, combined truncation and elapsed seconds deliberately into the Mo response contract; do not drop fields or manufacture per-stream precision. The mismatch is visible at [workspace.py:15](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace.py:15).

Keep Book and reports outside candidate storage. Preserve Book acknowledgment before subsequent dispatch, zero retries, explicit unknown execution, terminal timeout/cancellation, and known reported usage. The bridge’s native-history and usage contract remains unchanged: [bridge plan:67](/Users/robertguss/Projects/startups/mo-lang/mo-wiki/plans/mo-provider-bridge-v1.md:67). Application commands need a separately versioned longer profile deadline; existing two-second calls/30-second sessions cannot silently expand.

**4. Exact proposed acceptance fixture**

Choose **Logstat**, four application modules with existing input files and golden output. Its documented CLI cases are [main.mo:1](/Users/robertguss/Projects/startups/mo-lang/examples/programs/logstat/main.mo:1).

Proposed identity: `logstat-default-top-repair-v1`, source base `e6f04ce`. Import `mo.root`, matching IDs, `logstat/{main,parse,report,stats}.mo` and existing `logstat/fixture/*`. Protect expected outputs separately.

Seed exactly one mutation: default `top: 5` → `top: 1` at [main.mo:80](/Users/robertguss/Projects/startups/mo-lang/examples/programs/logstat/main.mo:80). Script: build/run → observe golden mismatch → read/search source → exact edit → rebuild/run → freeze → independent rebuild/check.

Freeze four check IDs:

- `default-text`: exact existing [logstat.expected](/Users/robertguss/Projects/startups/mo-lang/examples/programs/logstat/logstat.expected), exit 0.
- `filtered-json`: existing second CLI case and `logstat-2.expected`.
- `invalid-top`: `fixture --top 0`, exit 2.
- `no-logs`: `.`, exit 1.

Use at most 16 scripted tool calls, 900-second attempt guard, 16 MiB retained evidence, no provider calls. Require rejection controls for missing mutation, unrepaired candidate, failed build/stale binary, empty check inventory, forged success/result overwrite, and timeout/uncertain cleanup. Bind verdict to snapshot, toolchain/image/policy and checker inventory.

**Real gaps:** supplied Linux smoke evidence establishes trusted compiler execution and native application compilation, not candidate-container readiness. The reported 512K peak is unusable sizing evidence. Workspace acceptance remains accepted; coding-fixture full acceptance remains pending. HTTP integration, image packaging, cold-build resource sufficiency and protected application verification remain unmet. Keep active bridge/auth workers within their scopes. This slice proves a scripted coding workflow only; it supports no benchmark or language-value claim.

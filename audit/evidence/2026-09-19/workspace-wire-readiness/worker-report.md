Recommend **three separately owned slices**: a versioned Python workspace bridge, a Mo application profile, then separately versioned long-command execution support. Do not adapt the existing fixture endpoint in place.

Reviewed HEAD `191da144809a83ecadd1902aadd6507e898fa31b`; the twelve inspected source files were clean. Read-only source review only—no tests, builds, machines, network, or writes. Graph tools were not exposed, so I read the named files directly.

**Established seams and incompatibilities**

- Mo currently routes only fixture `command` remotely; `exact_edit` uses the local Writer, and other file tools use local Fs. Grants are checked before fixture dispatch. [run.mo:145](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/run.mo:145), [run.mo:198](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/run.mo:198)
- Registry always scopes a local folder and optionally starts Writer. An application profile therefore needs a distinct construction path, not merely another endpoint configuration. [registry.mo:62](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/registry.mo:62)
- Python already supplies all six operations through one `Workspace`; command uses reserve → execution → collection → cleanup completion, rather than a controller `command` operation. [workspace.py:134](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace.py:134), [workspace.py:149](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace.py:149)
- Controller locking and `no_active` prevent file operations during active execution. Unknown controller execution quarantines the workspace. Preserve these boundaries. [workspace_controller.py:85](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace_controller.py:85), [workspace_controller.py:290](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace_controller.py:290)

**Proposed wire contract**

Use a new operator-fixed loopback endpoint, provisionally `POST /application/v1/tool`. These names are proposals, not existing APIs.

Request:

```json
{
  "version": "mo-workspace-tools-v1",
  "budget_profile": "application-workspace-v1",
  "run_id": "<Mo Book run identity>",
  "workspace_id": "<operator-bound 32 lowercase hex>",
  "call_id": "<Mo step identity>",
  "operation": "read_file",
  "args": {"path": "a.txt"},
  "timeout_ms": 2000,
  "max_output_bytes": 65536
}
```

The bridge binds this run to exactly one existing Python `Workspace` and operator-owned grant set. Neither model arguments nor request fields may select a machine, host directory, workspace binding, verifier, or grant expansion.

| Mo operation/arguments | Exact Python dispatch | Successful result |
|---|---|---|
| `list_files`, `path` default `"."` | `Workspace.call("list_files", {"path": …})` | `{items:[{path,length,sha256,mode}], truncated}` |
| `read_file`, `path` | `call("read_file", {"path": …})` | `{text}` |
| `search`, `query`, optional `path` | `call("search", {"text": query,"path": …})` | `{items:[{path,offset}], truncated}` |
| `write_file`, `path,text` | `call("write_file", …)` | `{written:true}` |
| `exact_edit`, `path,old_text,new_text` | `call("exact_edit", {"path":…,"old":…,"new":…})` | `{edited:true}` |
| `command`, `command` | `Workspace.command(command, seconds=…, call_id=…)` | Command outcome below |

Use `call`, not `require`, for file operations so refusal/timeout identity and execution metadata survive. Search offsets are **byte offsets**, not line numbers; list is recursive inventory, not the current Mo directory-name listing. [workspace.py:89](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace.py:89), [workspace_files.py:187](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace_files.py:187)

Response: echo `version,budget_profile,run_id,workspace_id,call_id,operation`; carry `state,execution,error,elapsed_seconds,truncated,result`. Command `result` carries `exit_code,signal,stdout,stderr,encoding:"base64",execution_valid`. Keep full manifest/observation evidence operator-side.

Identity translation is mandatory: Python requires run/workspace/call IDs matching `[0-9a-f]{32}`, whereas Mo currently sends its Book ID and decimal step string. Allocate and retain a one-to-one mapping from `(Mo run, Mo call)` to Python IDs before dispatch; reject duplicates without allocating another execution. Validate Python identities before echoing Mo identities. Command execution ID is separately generated and must not replace the workspace run ID. [workspace_controller.py:18](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace_controller.py:18), [workspace.py:41](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace.py:41), [run.mo:165](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/run.mo:165)

Translation rules:

- Preserve strict base64 and validate **combined decoded stdout+stderr ≤65,536 bytes**. Never replacement-decode arbitrary bytes or count base64 characters as output bytes.
- Preserve the single command `truncated` flag; do not invent per-stream truncation. For file results, propagate `outer.truncated OR result.truncated`.
- Preserve nullable `elapsed_seconds`. If presentation needs milliseconds, use explicitly rounded-down `floor(seconds × 1000)`; missing remains null.
- Convert remaining milliseconds to seconds by division by 1000, subtracting elapsed bridge handling time. Refuse below Python’s minimum; never round a small budget upward.
- Preserve Python’s state/execution combinations: verified timeout/cancellation may have `execution:"completed"`; controller refusal may also say completed. The fixture validator rejects these combinations and cannot be reused unchanged. [command-adapter.mo:87](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/command-adapter.mo:87), [workspace.py:29](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace.py:29)

**Mo profile and ownership**

1. **Python bridge owner:** new `toolchain/harness/executor/application_bridge.py` and `toolchain/harness/executor/test_application_bridge.py`. Own strict schemas, identity mapping, grants, serialization, response projection, duplicate rejection, and terminal latch after uncertain execution. Reuse the accepted controller; expose only six candidate operations. `create/freeze/verify/delete` remain operator-only.

2. **Mo profile owner:** new `examples/programs/agent/application.mo` and `workspace-adapter.mo`; narrowly modify `run.mo`, `registry.mo`, `main.mo`, and `report.mo`.
   - Add an explicit application profile distinct from fixture/default.
   - Make local reads optional and start application runs with **no Fs and no Writer**. Require the remote configuration before Begin; all six calls dispatch remotely or fail closed.
   - Retain grant-before-dispatch and sequential record-before-next-call behavior. Extend terminal-result handling to every application tool; current handling covers only command/exact_edit. [run.mo:177](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/run.mo:177)
   - Keep Book storage outside candidate workspace/imports/mounts. Use a distinct application report schema; the existing report hardcodes `mo-coding-fixture-v1`. [report.mo:8](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/report.mo:8)
   - Leave `tools.mo`, `exact-edit.mo`, `command-adapter.mo`, and `coding-fixture.mo` unchanged.

3. **Long-command owner, subsequent slice:** new `toolchain/harness/executor/execution_profiles.py`, narrow changes to `adapter.py`, `workspace.py`, and—only after bounded source review—`remote.py`, plus profile-specific tests. Do not silently raise a shared constant.

**Budget proposal and unmet compatibility**

Version `application-workspace-v1` separately: command execution ≤120 seconds, total application run ≤900 seconds, zero retries. Reserve cleanup/report time *inside* the application ceiling; each command receives the smaller of its cap and the remaining dispatch allowance. Keep file-control RPCs within their existing ≤60-second bound.

This is **not currently supported**: `Run._initialize` accepts only `.5..10` seconds; collection has additional waiting/cleanup time, and registration installs independent timers. Changing Mo alone cannot enable 120-second commands safely. [adapter.py:80](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/adapter.py:80), [adapter.py:138](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/adapter.py:138), [adapter.py:160](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/adapter.py:160)

Preserve fixture **2s/30s**, its existing 45-second reporting envelope, and the provider bridge’s fixed **2s/30s**. New application budgets must not flow into provider configuration. The bounded files do not establish `Record` budget validation, Book folder prerequisites, model/provider timeout handling, supervisor limits, or Mo base64 support. Those require focused compatibility checks before final ownership closes; no compiler change is justified by this review.

**Fixed acceptance controls for the lead**

- One deterministic sequence: remote write → read → search → exact edit → command reading/editing that file → read/list. Retained evidence must show one workspace binding and unique mapped calls throughout.
- Local canary with identical pathname remains untouched; endpoint failure never reads it or starts Writer.
- Wrong identities/version/profile/operation, ungranted tools, duplicate calls, malformed base64, and combined 65,537-byte output fail closed.
- `../`, absolute paths, symlinks, hardlinks, FIFO, empty/missing/overlapping edit matches refuse without modification.
- Lost response after mutation, cleanup uncertainty, cancellation, or recording acknowledgement failure causes no redispatch or next candidate tool.
- Independently verify application >2-second command success, 120-second cap, ≤900-second aggregate ceiling, and unchanged fixture/provider deadlines.
- Candidate freeze/verify/delete requests refuse; operator freeze and external verification use the accepted snapshot lifecycle.

These are proposed acceptance requirements, not results achieved in this read-only review.

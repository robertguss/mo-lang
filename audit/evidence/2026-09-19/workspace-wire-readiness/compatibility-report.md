**Decoding:** Mo exposes `String.from_bytes(List(UInt8)) : Option(String)`. Its implementation validates UTF-8 and returns `None` on invalid bytes; it performs no replacement. Conversely, `fold_lines` deliberately replaces invalid bytes, so it is unsuitable here. No base64 decoder is registered in the inspected current prelude/stdlib API tables. [prelude.zig:355](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/prelude.zig:355), [stdlib.zig:480](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/stdlib.zig:480), [stdlib.zig:560](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/stdlib.zig:560), [stdlib.zig:126](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/stdlib.zig:126)

**Minimal format recommendation:** Python strictly decodes executor base64, checks the combined 65,536-byte limit, then strictly decodes UTF-8 for JSON text delivery. Mo validates returned text with `String.from_bytes(text.bytes)` and checks combined byte size. Invalid UTF-8 must produce an explicit output-encoding failure, preserving actual execution status and operator-side raw evidence—not replacement text or `not_started`. This is a **text-output profile**; arbitrary binary delivery remains unsupported unless a separately implemented decoder or byte representation is chosen. Python already strictly decodes base64 and validates the combined raw cap. [workspace.py:18](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace.py:18)

**Wire size:** HTTP accepts bodies up to **1,048,576 bytes**, with or without Content-Length; transfer encoding is unsupported. [http.zig:33](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/http.zig:33), [http.zig:171](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/http.zig:171)

- 65,536 raw bytes require 87,384 base64 characters; separately encoding two streams can require **87,388 combined**.
- JSON text escaping can require **393,216 bytes** for 65,536 bytes of control characters, before envelope overhead.
- Recommend **524,288-byte response-body cap**, bounded metadata, and no embedded manifest/observation. If exact-edit accepts two independently capped 64 KiB strings, use a separate **851,968-byte request cap**: their worst-case escaped content alone is 786,432 bytes.

**Existing blocker:** controller responses exceeding **65,280 serialized bytes** lose their result and become `result_too_large`. Thus increasing the HTTP bridge cap alone cannot deliver a full 64 KiB file—even plain ASCII. Supporting that promise requires separating controller wire-envelope limits from raw file limits; otherwise document the existing refusal. [workspace_controller.py:275](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace_controller.py:275)

**Record/Book compatibility:**

| Field | Existing validated range |
|---|---|
| `steps` | 1–200 |
| `tokens` | 1–10,000,000 |
| `wall_ms` | 100–3,600,000 |
| `retries` | 0–10 |
| `tool_ms` | 100–60,000 |

`budget(...)` requires all these predicates. Therefore **900,000 ms and zero retries already fit; 120,000 tool_ms does not**. Fixture remains `budget(16,4096,30000,0,2000)`. [record.mo:68](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/record.mo:68)

`order(...)` validates goal, folder, tools and hosts. Its legacy tool catalog excludes command/exact_edit; the fixture uses direct `Order(...)` construction. A separate application constructor must explicitly validate its six-tool catalog rather than broaden legacy validation. [record.mo:129](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/record.mo:129), [record.mo:153](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/record.mo:153), [coding-fixture.mo:59](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/coding-fixture.mo:59)

Book delegates creation without repeating those constructor validations. It requires writable/listable log storage and a **listable local `order.folder`**, then appends the header before returning Made. An empty operator-owned placeholder folder satisfies this existing prerequisite without becoming candidate storage or an Fs fallback. [book.mo:34](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/book.mo:34), [filing.mo:41](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/filing.mo:41), [filing.mo:109](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/filing.mo:109)

**Minimal budget recommendation:** retain validated `tool_ms:2000`, set application `wall_ms:900000,retries:0`, and introduce a separate application command cap of `120000` tied to the active `application-build-v1` dependency. Current `call_ms` supplies the same budget field to calls, so command dispatch needs its own profile-specific deadline selection; do not raise the shared field or provider deadline. [steps.mo:146](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/steps.mo:146)

A strict **900-second end-to-end ceiling requires an outer deadline including cleanup/reporting**. Book’s lost-run threshold is creation time + wall budget + **120 seconds grace**, so Book alone does not enforce that ceiling. [filing.mo:133](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/filing.mo:133), [shelf.mo:115](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/shelf.mo:115)

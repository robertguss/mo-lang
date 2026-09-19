# Read-only Mo JSON and read API review

Exact reviewed main: cf99cd88e186cf293a4112582fe2d26a0f7b69ff.
Reviewer: native GPT-6-Astra low, Herdr w4:p2D, session 01a0b930-451d-7c13-ac47-d2dc2e592948.
Source inspection only; no test or allocation parity claim.

At `cf99cd88e186cf293a4112582fe2d26a0f7b69ff`; inspected source files match that commit. Source review only—no tests, builds, edits, or network calls.

**1. JSON behavior**

| Input | Interpreter and native behavior |
|---|---|
| Duplicate object keys | Accepted; first position retained, **last value wins**, including keys equal after escape decoding. Duplicate evidence is lost. [Interpreter](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/json.zig:337), [native](/Users/robertguss/Projects/startups/mo-lang/toolchain/runtime/mo_rt.c:4615). |
| Nonfinite numbers | `NaN`/`Infinity` spellings fail JSON grammar; numeric overflow such as `1e999` fails with `Syntax`. [Interpreter](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/json.zig:395), [native](/Users/robertguss/Projects/startups/mo-lang/toolchain/runtime/mo_rt.c:4670). |
| Unpaired surrogates | Rejected; high surrogates require a following low surrogate, and standalone low surrogates fail. [Interpreter](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/json.zig:470), [native](/Users/robertguss/Projects/startups/mo-lang/toolchain/runtime/mo_rt.c:4550). |
| Fractional numbers | Decode to Float64. `to_i64` returns `Some` only for a whole decoded value strictly between −2^53 and +2^53; otherwise `None`, including nonfinite values. [Interpreter](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/json.zig:255), [native](/Users/robertguss/Projects/startups/mo-lang/toolchain/runtime/mo_rt.c:4701). |

No source-level difference found for these cases. Numeric conversion uses Zig `parseFloat` versus C `strtod`; exact rounding parity was not experimentally checked.

For the validator:

- Use existing `to_i64`, then field-specific range checks, as [command-adapter.mo already does](/Users/robertguss/Projects/startups/mo-lang/examples/programs/agent/command-adapter.mo:40).
- This validates the **decoded number**, not its original spelling. `1.0` and `1e0` pass; fractional tokens rounded to whole Float64 values can also pass.
- Strict duplicate rejection cannot be recovered from the resulting Map. Existing `Json.decode` exposes no strict option. Rejecting duplicates or enforcing exact numeric-token semantics requires additional raw-input validation or an API change; do not claim the existing decoder proves those properties.

**2. Byte bounds**

- **Config, 4096 bytes:** existing APIs are `fs.size(path)`, `fs.read(path)`, and `String.byte_size` ([PRELUDE](/Users/robertguss/Projects/startups/mo-lang/toolchain/PRELUDE.md:242)). For a trusted, stable operator file: reject size >4096 before reading, then recheck returned text’s `byte_size`. `size` performs a separate stat ([interpreter](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/server.zig:335), [native](/Users/robertguss/Projects/startups/mo-lang/toolchain/runtime/mo_rt.c:4043)). This is **not an atomic 4096-byte read/allocation bound**. Reads consume the whole file; the runtime acceptance ceiling is 64 MiB, and native buffering can grow to 128 MiB before rejection ([native read loop](/Users/robertguss/Projects/startups/mo-lang/toolchain/runtime/mo_rt.c:3331)).

- **Response, 524288 bytes:** `Http.send` has **no configurable response-size parameter** ([PRELUDE](/Users/robertguss/Projects/startups/mo-lang/toolchain/PRELUDE.md:304)). Check `response.body.byte_size > 524288` after successful receipt and before JSON decoding. That bounds accepted input, not transport allocation. Both runtimes enforce a fixed **1 MiB body limit**, with a connection-buffer cap of **3 MiB + 8 bytes** ([interpreter](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/http.zig:33), [native](/Users/robertguss/Projects/startups/mo-lang/toolchain/runtime/mo_rt.c:9319)).

The draft can promise these application acceptance limits using existing APIs. It cannot promise transport/allocation limits of 4096 or 524288 bytes.

Returning idle; pane remains open.

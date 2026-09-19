# Strict JSON validation feasibility review

Source-only, exact main cf99cd88e186cf293a4112582fe2d26a0f7b69ff; native GPT-6-Astra low, Herdr w4:p2D. No tests or edits.

**Feasible with existing APIs; no counterexample to the duplicate-count argument found.**

- After successful `Json.decode`, every colon outside strings represents exactly one original object member. Recursively count `Object(fields)` as `fields.size + counts(fields.values)`, `Array(items)` as the sum of child counts, and scalars as zero. Every overwritten duplicate removes at least one member; discarded subtrees only increase that deficit. Escaped-equivalent keys are covered because decoding resolves escapes before key comparison ([decoder](/Users/robertguss/Projects/startups/mo-lang/toolchain/src/json.zig:348)).
- Required APIs exist: `String.bytes → List(UInt8)`, `List.reduce`, `Map.size`, `Map.values`, and the `Json` variants ([PRELUDE](/Users/robertguss/Projects/startups/mo-lang/toolchain/PRELUDE.md:141)). A scan can carry quote/escape/count state through `reduce`; recursive traversal needs no new API.
- Escape handling must consume **one escaped byte**, then clear the flag. Testing only whether the previous byte was backslash fails on even backslash runs. For example, valid `{"s":"\\","a":1}` must count two colons.

**The integer lexical restriction is compatible with the documented workspace payloads.** Existing numeric results are list-file `length`/`mode`, search `offset`, and nullable command `exit_code`/`signal`/`elapsed_ms`. File numbers are integers ([producer](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace_files.py:181)); elapsed seconds are explicitly floored to integer milliseconds ([projection](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace_http/protocol.py:105)). HTTP `version` is actually a **string** ([contract](/Users/robertguss/Projects/startups/mo-lang/toolchain/harness/executor/workspace_http/CONTRACT.md:19)). No legitimate floating field found.

Keep these qualifications:

- Still require `to_i64` and field-specific ranges. Lexical integer form alone permits oversized integers subject to Float64 rounding.
- Reject dots/exponents **within numeric tokens**, not every outside-string `e`: `true` and `false` contain `e`.
- This deliberately rejects `1.0` and `1e0`, even when mathematically integral.
- Projection copies some core fields without exhaustive type validation, so malformed producer output could contain floats; the proposed validator should reject that output.

Source-only feasibility assessment, not compiled verification. Returning idle.

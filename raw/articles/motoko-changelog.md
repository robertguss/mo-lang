---
source_url: https://docs.internetcomputer.org/languages/motoko/reference/changelog/
ingested: 2026-09-12
sha256: 778d84444b4ef98076167860c9ff492d01cfdcf4b214acd2f23a43f18356e422
---
# Changelog | ICP Developer Docs

Changelog | ICP Developer Docs

## 1.9.0 (2026-06-02)

- motoko (`moc`)

- feat: Structural implicit derivation for records and tuples via `__record` and `__tuple` combiners. Per-field results are lazy thunks, enabling short-circuiting for operations like `compare` (#5903).
- feat: `--experimental-multi-value` flag enables function-level multi-value Wasm codegen. Off by default (#6113).

## 1.8.2 (2026-05-21)

- motoko (`moc`)

- bugfix: M0236 dot-notation suggestion no longer fires when the receiver argument is not already a postfix expression (e.g. `Nat.toText((x * a + b) % c)`). The compiler used to print the suggestion as `().toText(...)` but emit no machine-applicable edits, leaving `mops check --fix` with nothing to do; suggesting `(complex).f()` over `Module.f(complex)` is also a debatable style change. Trivial-receiver cases (variables, literals, calls) are unaffected (#6144).

## 1.8.1 (2026-05-20)

- motoko (`moc`)

- bugfix: Split stable-signature compatibility error M0169: the “previous version does not contain the stable variable required by the migration function” case now reports as new code M0263, leaving M0169 strictly for the “stable variable would be implicitly discarded” (data-loss) case. The two scenarios have different fixes and now have distinct codes (#6134).

## 1.8.0 (2026-05-15)

- motoko (`moc`)

- feat: Implicit argument derivation: the compiler can derive implicit arguments from functions that themselves have implicit parameters (e.g., `compare` for `[Nat]` from `Array.compare ` + `Nat.compare`). Works transitively and is depth-limited via `--implicit-derivation-depth` (#5966).
- feat: `and`-patterns: `p1 and p2` matches when both legs match, binding from both (#6049).
- bugfix: M0236 dot-notation auto-fix on unparenthesized single-argument calls (e.g. `List.reverse b`) no longer rewrites them into a bare function reference (`b.reverse`), which silently turned a call into a no-op; the suggestion now produces `b.reverse()` (#6096).

## 1.7.0 (2026-04-29)

- motoko (`moc`)

- feat: Add null-coalescing operator `??` (#5722). `e1 ?? e2` evaluates to the unwrapped contents of `e1` when `e1` is `?v`, otherwise to `e2`. The right-hand side is evaluated lazily (short-circuit). For example, `opt ?? defaultValue` replaces the verbose `switch opt { case (?v) v; case null defaultValue }`. The right-hand side may be a block (e.g. `opt ?? { let x = 1; x }`), a `do`-block, or a `Prim.trap` for fail-fast unwrapping. Because `{ ... }` on the right is parsed as a block, a bare record literal must be wrapped in extra braces or parentheses, e.g. `opt ?? ({ x = 0 })` or `opt ?? {{ x = 0 }}`.
- perf: Compile enhanced multi-migration chains as per-step functions instead of one deeply-nested inlined expression, avoiding the wasm-function complexity limit hit by long chains (#6065).
- bugfix: Preserve GC-only roots (blob deduplication table, migration functions list) across graph-copy upgrades, and defer actor type compatibility checks to `ICStableRead` so enhanced multi-migration chains with multiple pending steps are accepted (#5993).
- bugfix: Clearer error when installing a Motoko canister over a non-Motoko or otherwise incompatible canister (#6044).

## 1.6.0 (2026-04-21)

- motoko (`moc`)

- feat: expose caller attributes feature through primitives (#5970).
- bugfix: Fix `moc.js` resolution of relative flag paths (e.g. `--enhanced-migration`, `--actor-idl`): resolve against the project root (via new `setProjectRoot` API) instead of the source file’s directory, matching native `moc` behavior. The language server should call `setProjectRoot(path)` before processing files (#6015).

## 1.5.1 (2026-04-13)

- motoko (`moc`)

- bugfix: Resolve relative paths in `moc.js` flags (e.g. `--enhanced-migration`, `--actor-idl`) against the source file’s directory, fixing “not a directory” errors when these flags are passed with relative paths via the language server (#6002).

## 1.5.0 (2026-04-10)

- motoko (`moc`)

- feat: Add `--generate-view-queries` flag to auto-generate query methods for stable variables (#5796). When enabled, `moc` produces one `__ ` query method per stable variable ` `, using the variable’s `.view()` method if available, or returning the value directly for shared types. Generated queries are restricted to controllers and self. View queries appear in the local `.did` file (for tooling) but are excluded from the canister’s public Candid interface, so they never affect upgrade compatibility. See Stable variable inspection for details.
- feat: Enhanced multi-migration support via `--enhanced-migration ` (#5840). Actor upgrades are managed through a chain of migration modules, each in its own file under a migrations directory (` `). Each migration module must export a function called `migrate`, consuming old and introducing new stable variables, in a similar fashion to the already supported single migration functions. The (lexicographic) sort order of module filenames determines the order of application of migration functions, with lowest applied first. The compiler verifies that the chain of migration functions composes correctly. The runtime only applies previously unapplied migrations on upgrade. Stable variables within an actor’s body must be declared with types but without initializers; their values are determined entirely by the output of the migration chain. The main body of actor must not have any immediate side effects, beyond invoking local ` ` functions (e.g. to register timers). General side-effects are allowed in migration functions, to enable data initialization and transformation. See Enhanced multi-migration for details.
- perf: type-based optimization of option creation and consumption, reducing cycle cost (#5947).
- bugfix: Fix type inference for `return` expressions inside unannotated lambdas passed to generic functions. Previously, the generic type parameter could resolve to `Non` instead of the actual return type, causing an IR type error (#5962).
- bugfix: Fix crash when reporting errors with no source region (#5976).
- documentation (`mo-doc`)

- feat: doc comments on individual record fields and variant tags inside a `type` declaration are now extracted and rendered (#5983).

## 1.4.1 (2026-03-30)

- motoko (`moc`)

- feat: Preserve named types in variable pattern bindings, so error messages show e.g. `Map.Map<Text, Text>` instead of expanding the full structural type (#5940).
- bugfix: implement `Float32``ModOp` (`%`): Wasm has no `f32.rem` instruction; the fix promotes operands to `f64`, applies `fmod`, then demotes the result back to `f32` (#5950).

## 1.4.0 (2026-03-27)

- motoko (`moc`)

- feat: added `--actor-env-alias` to facilitate (installation-time) late binding of canister aliases via environment variables (#5890).
- feat: added `--actor-id-alias` as a variant of `--actor-alias` that accepts an explicit IDL file path as a third argument, bypassing the `--actor-idl` search path (#5890).
- feat: provide a polymorphic `actorOfPrincipal` primitive (#5882).
- feat: add `Float32` primitive type with conversions to/from `Float`, Candid serialisation, and literal ascription (e.g. `(3.14 : Float32)`). This is experimental and subject to change (#5906).
- feat: prettier unknown identifier suggestions and pattern type mismatch errors (#5875, #5881).
- bugfix: Show the “Hint: Add explicit type instantiation” hint for calls with implicit arguments whose type parameters are invariant and underconstrained. Previously, implicit arguments caused unnecessary deferral of type variable solving, which suppressed the hint (#5886).

## 1.3.0 (2026-02-24)

- motoko (`moc`)

- Allow destructuring `type` imports from `actor`-valued URIs (#5824).
- perf: Optimise a few arithmetic/logic operations involving neutral elements (#5706).
- Warn when a `var` binding is never reassigned, suggesting `let` instead (#5833).
- Adds `--error-format human` option to print pretty errors with code snippets and labels (#5816), with improved formatting for unused (#5864) and duplicate name (#5865) errors.
- Emit machine-applicable code fixes in `--error-format json` diagnostics for warnings M0223 (redundant type instantiation), M0236 (use dot notation), and M0237 (omit explicit implicit argument). The JSON span format now includes `is_primary`, `label`, `suggested_replacement`, and `suggestion_applicability` fields, enabling IDEs and tooling to offer automatic fixes (#5831).
- Add `--all-libs` flag to load all library files from all packages, enabling better diagnostics, e.g. hinting at non-imported items (increases compilation time) (#5861).

## 1.2.0 (2026-02-12)

- motoko (`moc`)

- Report multiple type errors for compound types at once (#5790).

This means code like ` type T = (Na, In)` will fail with errors for both the misspelled `Na` and `In` types at once, so they can be fixed in one go, rather than having to re-run the compiler after fixing the first one.
- Allow `break` and `continue` in loops without labels (#5702).
- Report a better error for labeled `continue` targeting a non-loop (#5800).
- Deprecate older garbage collectors: generational, copying and compating GCs (#5806).
- Fix contextual dot type note, this should fix the hover hint in the vscode extension, showing the correct function type instead of `()` (#5809).
- bugfix: Avoid `moc.js` crashing when passing invalid flags (#5811).
- bugfix: Sometimes `import { type X } = "mo:./X"` didn’t work, with a confusing error message (#5826).
- Improved type recovery for `let` and `var` declarations (enabled only with a type recovery flag for the IDE) (#5819).
- Add `checkWithScopeCache` function to `moc.js` — a cached version of `check` (#5820).
- Add `--error-format json` flag to `moc` for machine-readable diagnostic output on stdout in JSON Lines format (#5829).
- Expose contextual dot resolution in `moc.js` via two new functions: `contextualDotSuggestions` returns matching context-dot functions for a receiver type, and `contextualDotModule` returns the module reference for a resolved context-dot expression. AST expression nodes now carry non-enumerable `rawExp` references, and the root AST node exposes the accumulated `scope` (including all transitive imports) to support these APIs (#5797).

## 1.1.0 (2026-01-16)

- motoko (`moc`)

- Warn on unreachable let-else (#5789).
- bugfix: The source region for `do { ... }` blocks now includes the `do` keyword too (#5785).
- Omit `blob:*` imports from `moc --print-deps` (#5781).
- Split unused identifier warnings into separate warnings for shared and non-shared contexts: `M0194` for general declarations, `M0240` for identifiers in shared pattern contexts (e.g. `c` in `shared({caller = c})`), `M0198` for unused fields in object patterns, and `M0241` for unused fields in shared patterns (e.g. `caller` in `shared({caller})`) (#5779).
- Print type constructors using available type paths (#5698).
- Warn on implicit oneway declarations (#5787).
- Make the type checker more lenient and continue accumulating typing errors, and try to produce the typed AST even with errors. Enabled only with a type recovery flag for the IDE (Serokell Grant 2 Milestone 3) (#5776).
- Explain subtype failures (#5643).
- Removes the Viper support (#5751).
- Allows resolving local definitions for context-dot (#5731).

Extends contextual-dot resolution to consider local definitions first, to make the following snippet type check. Local definitions take precedence over definitions that are in scope via modules.

func first< A>(self : [A]) : A {

 return self[0]

};

assert [1, 2, 3]. first() == 1

- Add privileged primitive for setting Candid type table cutoff (#5642).

## 1.0.0 (2025-12-11)

- motoko (`moc`)

- Shorter, simpler error messages for generic functions (#5650). The compiler now tries to point to the first problematic expression in the function call, rather than the entire function call with type inference details. Simple errors only mention closed types; verbose errors with unsolved type variables are only shown when necessary.
- Improved error messages for context dot: only the receiver type variables are solved, remaining type variables stay unsolved, not solved to `Any` or `Non` (#5634).
- Fixed the type instantiation hint to have the correct arity (#5634).
- Fix for #5618 (compiling dotted `await` s) (#5622).
- Improved type inference of the record update syntax (#5625).
- New flag `--error-recovery` to enable reporting of multiple syntax errors (#5632).
- Improved solving and error messages for invariant type parameters (#5464). Error messages now include suggested type instantiations when there is no principal solution.

Invariant type parameters with bounds like `Int <: U <: Any` (when the upper bound is `Any`) can now be solved by choosing the lower bound (`Int` here) when it has no proper supertypes other than `Any`. This means that when choosing between exactly two solutions: the lower bound and `Any` as the upper bound, the lower bound is chosen as the solution for the invariant type parameter (`U` here). Symmetrically, with bounds like `Non <: U <: Nat` (when the lower bound is `Non`), the upper bound (`Nat` here) is chosen when it has no proper subtypes other than `Non`.

For example, the following code now compiles without explicit type arguments:

import VarArray "mo:core/VarArray";

let varAr = [var 1, 2, 3];

let result = VarArray. map(varAr, func x = x : Int);

This compiles because the body of `func x = x : Int` has type `Int`, which implies that `Int <: U <: Any`. Since `Int` has no proper supertypes other than `Any`, it can be chosen as the solution for the invariant type parameter `U`, resulting in the output type `[var Int]`.

However, note that if the function body was of type `Nat`, it would not compile, because `Nat` is a proper subtype of `Int` (`Nat <: Int`). In this case, there would be no principal solution with `Nat <: U <: Any`, and the error message would suggest:

Hint: Add explicit type instantiation, e.g. <Nat, Nat>

The suggested type instantiation can be used to fix the code:

let result = VarArray. map< Nat, Nat>(varAr, func x = x);

Note that the error message suggests only one possible solution, but there may be alternatives. In the example above, `<Nat, Int>` would also be a valid instantiation.
- Fixes type inference of deferred funcs that use `return` in their body (#5615). Avoids confusing errors like `Bool does not have expected type T` on `return` expressions. Should type check successfully now.
- Add warning `M0239` that warns when binding a unit `()` value by `let` or `var` (#5599).
- Use `self` parameter, not `Self` type, to enable contextual dot notation (#5574).
- Add (caffeine) warning `M0237` (#5588). Warns if explicit argument could have been inferred and omitted, e.g. `a.sort(Nat.compare)` vs `a.sort()`. (allowed by default, warn with `-W 0237`).
- Add (caffeine) warning `M0236` (#5584). Warns if contextual dot notation could have been used, e.g. `Map.filter(map, ...)` vs `map.filter(...)`. Does not warn for binary `M.equals(e1, e2)` or `M.compareXXX(e1, e2)`. (allowed by default, warn with `-W 0236`).
- Add (caffeine) deprecation code `M0235` (#5583). Deprecates any public types and values with special doc comment `/// @deprecated M0235`. (allowed by default, warn with `-W 0235`).
- Experimental support for `implicit` argument declarations (#5517).
- Experimental support for Mixins (#5459).
- bugfix: importing of `blob:file:` URLs in subdirectories should work now (#5507, #5569).
- bugfix: escape `composite_query` fields on the Candid side, as it is a keyword (#5617).
- bugfix: implement Candid spec improvements (#5504, #5543, #5505). May now cause rejection of certain type-incorrect Candid messages that were accepted before.

## 0.16.3 (2025-09-29)

- motoko (`moc`)

- Added `Prim.getSelfPrincipal () : Principal` to get the principal of the current actor (#5518).
- Contextual dot notation (#5458):

Writing `e0.f()(e1,...,en)` is short-hand for `M.f()(e0, e1, ..., en)`, provided:

- `f` is not already a field or special member of `e0`.
- There is a unique module `M` with member `f` in the context that declares: 

- a public type `Self<T1,..., Tn>` that can be instantiated to the type of `e0`;
- a public field `f` that accepts `(e0, e2, ..., en)` as arguments.
- Added an optional warning for redundant type instantiations in generic function calls (#5468). Note that this warning is off by default. It can be enabled with the `-W M0223` flag.
- Added `-A` and `-W` flags to disable and enable warnings given their message codes (#5496).

For example, to disable the warning for redundant `stable` keyword, use `-A M0217`. To enable the warning for redundant type instantiations, use `-W M0223`. Multiple warnings can be disabled or enabled by comma-separating the message codes, e.g. `-A M0217,M0218`. Both flags can be used multiple times.
- Added `-E` flag to treat specified warnings as errors given their message codes (#5502).
- Added `--warn-help` flag to show available warning codes, current lint level (A llowed, W arn or E rror), and descriptions (#5502).
- `moc.js` : Added `setExtraFlags` method for passing some of the `moc` flags (#5506).

## 0.16.2 (2025-09-12)

- motoko (`moc`)

- Added primitives to access canister environment variables (#5443):

Prim. envVarNames : < system>() -> [Text]

Prim. envVar : < system>(name : Text) -> ? Text

These require `system` capability to prevent supply-chain attacks.
- Added ability to import `Blob` s from the local file system by means of the `blob:file:` URI scheme (#4935).

## 0.16.1 (2025-08-25)

- motoko (`moc`)

- bugfix: fix compile-time exception showing `???` type when using ‘improved type inference’ (#5423).
- Allow inference of invariant type parameters, but only when the bound/solution is an ‘isolated’ type (meaning it has no proper subtypes nor supertypes other than `Any`/`None`) (#5359). This addresses the limitation mentioned in #5180. Examples of isolated types include all primitive types except `Nat` and `Int`, such as `Bool`, `Text`, `Blob`, `Float`, `Char`, `Int32`, etc. `Nat` and `Int` are not isolated because `Nat` is a subtype of `Int` (`Nat <: Int`).

For example, the following code now works without explicit type arguments:

import VarArray "mo:core/VarArray";

let varAr = [var 1, 2, 3];

let result = VarArray. map(varAr, func x = debug_show (x) # "!"); // [var Text]
- `ignore` now warns when its argument has type `async*`, as it will have no effect (#5419).
- bugfix: fix rare compiler crash when using a label and identifier of the same name in the same scope (#5283, #5412).
- bugfix: `moc` now warns about parentheticals on `async*` calls, and makes sure that they get discarded (#5415).

## 0.16.0 (2025-08-19)

- motoko (`moc`)

- Breaking change: add new type constructor `weak T` for constructing weak references.

 Prim. allocWeakRef: < T>(value : T) -> weak T

 Prim. weakGet: < T> weak T -> ?(value : T)

 Prim. isLive: weak Any -> Bool

A weak reference can only be allocated from a value whose type representation is always a heap reference; `allowWeakRef` will trap on values of other types. A weak reference does not count as a reference to its value and allows the collector to collect the value once no other references to it remain. `weakGet` will return `null`, and `isLive` will return false once the value of the reference has been collected by the garbage collector. The type constructor `weak T` is covariant.

Weak reference operations are only supported with —enhanced-orthogonal-persistence and cannot be used with the classic compiler.
- bugfix: the EOP dynamic stable compatibility check incorrectly rejected upgrades from `Null` to `?T` (#5404).
- More explanatory upgrade error messages with detailing of cause (#5391).
- Improved type inference for calling generic functions (#5180). This means that type arguments can be omitted when calling generic functions in most common cases. For example:

let ar = [1, 2, 3];

Array. map(ar, func x = x * 2); // Needs no explicit type arguments anymore!

Previously, type arguments were usually required when there was an anonymous not annotated function in arguments. The reason being that the type inference algorithm cannot infer the type of `func` s in general, e.g. `func x = x * 2` cannot be inferred without knowing the type of `x`.

Now, the improved type inference can handle such `func` s when there is enough type information from other arguments. It works by splitting the type inference into two phases:

1. In the first phase, it infers part of the instantiation from the non-`func` arguments. The goal is to infer all parameters of the `func` arguments, e.g. `x` in the example above. The `ar` argument in the example above is used to infer the partial instantiation `Array.map<Nat, O>`, leaving the second type argument `O` to be inferred in the second phase. With this partial instantiation, it knows that `x : Nat`.
2. In the second phase, it completes the instantiation by inferring the bodies of the `func` arguments; assuming that all parameters were inferred in the first phase. In the example above, it knows that `x : Nat`, so inferring the body `x * 2` will infer the type `O` to be `Nat`. With this, the full instantiation `Array.map<Nat, Nat>` is inferred, and the type arguments can be omitted.

Limitations:

- Invariant type parameters must be explicitly provided in most cases. e.g. `VarArray.map` must have the return type annotation:

let result = VarArray. map< Nat, Nat>(varAr, func x = x * 2);

Or the type of the result must be explicitly provided:

let result : [var Nat] = VarArray. map(varAr, func x = x * 2);
- When there is not enough type information from the non-`func` arguments, the type inference will not be able to infer the `func` arguments. However this is not a problem in most cases.

## 0.15.1 (2025-07-30)

- motoko (`moc`)

- bugfix: `persistent` imported actor classes incorrectly rejected as non-`persistent` (#5667).
- Allow matching type fields of modules and objects in patterns (#5056) This allows importing a type from a module without requiring an indirection or extra binding.

// What previously required indirection, ...

import Result "mo:core/Result";

type MyResult = Result.Result<Ok, Text>;

 

// or rebinding, ...

import Result "mo:core/Result";

type Result<Ok, Err> = Result.Result<Ok, Err>;

type MyResult = Result<Ok, Text>;

 

// can now be written more concisely as:

import { type Result } "mo:core/Result";

type MyResult = Result<Ok, Text>;

## 0.15.0 (2025-07-25)

- motoko (`moc`)

- Breaking change: the `persistent` keyword is now required on actors and actor classes (#5320, #5298). This is a transitional restriction to force users to declare transient declarations as `transient` and actor/actor classes as `persistent`. New error messages and warnings will iteratively guide you to insert `transient` and `persistent` as required, after which any `stable` keywords can be removed. Use the force.

In the near future, the `persistent` keyword will be made optional again, and `let` and `var` declarations within actor and actor classes will be `stable` (by default) unless declared `transient`, inverting the previous default for non-`persistent` actors. The goal of this song and dance is to always default actor declarations to stable unless declared `transient` and make the `persistent` keyword redundant.
- Breaking change: enhanced orthogonal persistence is now the default compilation mode for `moc` (#5305). Flag `--enhanced-orthogonal-persistence` is on by default. Users not willing or able to migrate their code can opt in to the behavior of moc prior to this release with the new flag `--legacy-persistence`. Flag `--legacy-persistence` is required to select the legacy `--copying-gc` (the previous default), `--compacting-gc`, or `generational-gc`.

As a safeguard, to protect users from unwittingly, and irreversibly, upgrading from legacy to enhanced orthogonal persistence, such upgrades will fail unless the new code is compiled with flag `--enhanced-orthogonal-persistence` explicitly set. New projects should not require the flag at all (#5308) and will simply adopt enhanced mode.

To recap, enhanced orthogonal persistence implements scalable and efficient orthogonal persistence (stable variables) for Motoko:

- The Wasm main memory (heap) is retained on upgrade with new program versions directly picking up this state.
- The Wasm main memory has been extended to 64-bit to scale as large as stable memory in the future.
- The runtime system checks that data changes of new program versions are compatible with the old state.

Implications:

- Upgrades become extremely fast, only depending on the number of types, not on the number of heap objects.
- Upgrades will no longer hit the IC instruction limit, even for maximum heap usage.
- The change to 64-bit increases the memory demand on the heap, in worst case by a factor of two.
- For step-wise r

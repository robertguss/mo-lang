# Corpus gaps

Each line names a missing or conflicting rule and the default used; these are open decisions, not additions to Mo.

- `basics/numbers.mo`: Numeric method signatures and the float type name are not specified; use the brief's named arithmetic, `Option(UInt32)` for checked addition, and provisional `Float64` at a declared boundary.
- `basics/strings.mo`: The result type of `bytes` is unspecified; use a byte sequence with `.size` rather than invent a byte-count API.
- All `.mo` files: The toolchain currently documents unimplemented stages; examples are source fixtures checked against the draft, not claimed compiled or executed.
- `basics/option.mo`, `basics/result.mo` (and later Option/Result examples): EBNF patterns require named payloads and the prose bans positional construction, but chapter 4 explicitly uses `Some(x)`, `Ok(x)`, and `Error(e)` without defining field names; retain those documented built-in forms only, with named fields for user-defined variants.
- `basics/lists.mo`: List combinator signatures are not declared; use the ordinary seed-first `reduce(seed, fn(total, item) ... end)` call shape and record it as provisional.
- `basics/anonymous-functions.mo` (and later hyphenated paths): Module-to-file mapping does not define hyphenated basenames; use `AnonymousFunctions` for `anonymous-functions.mo`, consistently converting CapCase words to lowercase hyphenated names.
- `basics/anonymous-functions.mo`: EBNF references undefined `params_untyped`; use the chapter 4 `fn(x)` spelling and the grammar's newline block alternative.
- `basics/for.mo`: Range endpoint inclusion is unspecified; break before the endpoint so either interpretation gives the same tested result.
- `types/refinement.mo`: The draft does not settle whether an invalid literal at a refinement boundary is a static error or a runtime rejects case; use the brief's boundary call in `test rejects`, without inventing a constructor.
- `types/generics.mo`: Traits lack a defined name for their implementing type; use the already-documented generic `T` in the trait signature, pending a binding rule, and test the independent unbounded `first` function.

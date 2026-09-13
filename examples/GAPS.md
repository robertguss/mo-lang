# Corpus gaps

Places where a program needed something `spec/grammar.md` and `spec/design-v0/04-syntax.md` do not define. One line per gap: the first file that needed it, what was missing, the default the corpus uses. Robert decides; the corpus only records. Gaps settled by the Session 5 decisions at the foot of `grammar.md` are gone from this list, and the files follow the decisions.

- `types/generics.mo`: no stdlib trait names exist (pick 15's `Comparable` is only an example). Default: the bound names a trait declared in the same file.
- `recipes/rate-limiter.mo`: chapter 6 uses `Limiter`, `ClientId`, and `tokens` without declaring them, and nothing names a type whose fields the implementer chooses. Default: `type ClientId = String` in the module; `tokens` and `limiter` are body-less signatures in the recipe; `Limiter` and `l.capacity` stay undeclared, as in chapter 6. The checker reads an undeclared type in a recipe signature as opaque (the implementer chooses its fields), so a field read on it is not checked at tier 1.
- `effects/timeout.mo`: grammar gives `Fs.read` the error type `FsError` but never lists its variants, and `try` needs them to match the caller's error enum. Default: `FsError` is `Missing(path: String) | Timeout`, marked corpus-only in `toolchain/PRELUDE.md`.
- `types/generics.mo`: the grammar has no syntax that declares a type parameter; `fn first(xs: List(T))` just uses `T`. Default in the checker: an undeclared one-letter type name in a function signature is a type parameter of that function; anywhere else it is an unknown type.

# Corpus gaps

Places where a program needed something `spec/grammar.md` and `spec/design-v0/04-syntax.md` do not define. One line per gap: the first file that needed it, what was missing, the default the corpus uses. Robert decides; the corpus only records. Gaps settled by the Session 5 decisions at the foot of `grammar.md` are gone from this list, and the files follow the decisions.

- `basics/strings.mo`: `starts_with?` is not among the stdlib names the corpus may assume. Default: the obvious string predicate, `s.starts_with?(prefix)`, also used by `rejects/default-parameter.mo` and `rejects/seven-parameters.mo`.
- `types/generics.mo`: no stdlib trait names exist (pick 15's `Comparable` is only an example). Default: the bound names a trait declared in the same file.
- `contracts/ensures.mo`: no call-site marker for an `inout` argument. Default: a plain `add(cart, 500)` on a `var`; chapter 3 makes the caller's name unusable until return.
- `effects/timeout.mo`: `Fs` has no operations named beyond `scoped` and `read_only`. Default: `fs.read(path, within: d)`, giving the file's text as a `String`.
- `processes/invariant.mo`: chapter 4's `invariant` block is true when the rule is broken (`state.done < old(state.done)` under "done never goes backwards"), like `never`, but nothing says so. Default: chapter 4; the block describes the broken state.
- `processes/pipeline.mo`: a `child` line now passes parameters, but nothing says how a supervisor hands one child's handle to a sibling. Default: the supervisor takes `sink: Handle(Sink)` and passes it on `child Source(sink)`; the test wires the two with `Source.start(sink)`.
- `processes/pipeline.mo`: two processes plus the required supervisor do not fit the brief's 40 lines (the grammar's smallest process is about 12). Default: no blank lines inside the processes; the file is 46 lines.
- `recipes/rate-limiter.mo`: chapter 6 uses `Limiter`, `ClientId`, and `tokens` without declaring them, and nothing names a type whose fields the implementer chooses. Default: `type ClientId = String` in the module; `tokens` and `limiter` are body-less signatures in the recipe; `Limiter` and `l.capacity` stay undeclared, as in chapter 6.

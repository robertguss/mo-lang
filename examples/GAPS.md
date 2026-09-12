# Corpus gaps

Places where a program needed something `spec/grammar.md` and `spec/design-v0/04-syntax.md` do not define. One line per gap: the first file that needed it, what was missing, the default the corpus uses. Robert decides; the corpus only records.

- `basics/bindings.mo`: bindings carry no type and nothing gives an unsuffixed literal (`1`, `1_000`) its type. Default: the literal takes its type from its use (a parameter, the return type, the other operand).
- `basics/numbers.mo`: no names are given for sized integer or float types. Default: `UInt16`, `UInt32`, `UInt64`, `Int32`, `Float64`, extending chapter 4's `UInt32` and `UInt64`.
- `basics/strings.mo`: "`bytes` is bytes" does not say whether `bytes` is a count or a sequence. Default: `word.bytes.size`, so `bytes` is the byte sequence and `size` counts it.
- `basics/tuples.mo`: `if ... else ... end` as the last line of a body can parse as `if_stmt` or as the `if` expression. Default: it is the expression and gives the body its value (the rule the grammar already relies on for `Ok(updated)`).

# jobq: what the toolchain did that surprised the program

Round 6 of the control run. Each entry has a minimal reproduction; none is fixed here.

## 1. An escape the lexer does not know is read as the letter after the backslash, with no diagnostic

The grammar (§1) lists no escapes in a string, yet `"\t"`, `"\r"`, and `"\n"` are one byte each, and `"\u0085"` is accepted too: it is the five bytes `u0085`. A test that meant to hand a payload rule the C1 control character U+0085, or a reason rule a NUL, passed plain text instead, so `!payload?("\u0085")` failed and a `test rejects` built on `"a\u0000b"` ran to its end without tripping.

```ruby
module Esc
expose sizes

intent "probe: the byte sizes of escaped string literals"

fn sizes() : List(UInt64)
  ["\t".byte_size, "\r".byte_size, "\u0085".byte_size, "\u0000".byte_size]
end

test "sizes"
  assert sizes() == [1, 1, 2, 1]
end
```

`mo test esc.mo`: `assert sizes() == [1, 1, 2, 1] failed; left = [1, 1, 5, 5]`.

Expected: either a `\u` escape, or `MO0101` at an escape the lexer does not know. Workaround: the tests build such text from bytes, `String.from_bytes([194, 133]) or ""`.

## 2. MO0101 at a parameter named `result` does not say that `result` is a keyword

`state` and `old` get a message that names the keyword and the way out (step 26); `result`, the other keyword a program meets as a name, gets only the grammar's "expected a name", at the parameter's name.

```ruby
module Took
expose took

intent "probe: a parameter named result."

fn took(result: Option(UInt64)) : UInt64
  result or 0
end
```

`mo check took.mo`: `MO0101 expected a name`, pointing at `result`. The same program with `state` says: "state is a keyword, the process's state in its update and invariants, so a binding or a parameter takes another name, such as status". Found in `Jobq.Books`, a test helper `took(result: Stored)`; one loop, renamed to `outcome`.

---
source_url: https://www.moonbitlang.com/updates/2026/06/08/moonbit-0-10-0-release
ingested: 2026-09-12
sha256: fae22b24326074b13001e5974b032be6e36cc0f4f3384de27b5b49f6ed50d45c
---
# 20260608 MoonBit v0.10.0 Release | MoonBit

20260608 MoonBit v0.10.0 Release | MoonBit

# 20260608 MoonBit v0.10.0 Release

June 8, 2026 · 8 min read

moonc version: `v0.10.0+84519ca0a`

This update is for MoonBit 0.10, an important step before the official 1.0 release. We are continuing to refine the language, toolchain, and ecosystem experience, and are currently targeting MoonBit 1.0 for Q3. The final timeline may be adjusted based on testing progress and community feedback.

## Language Updates​

1. `trait` and `impl` syntax now require the `fn` keyword: This change makes it easier to add support for polymorphic methods in traits. Existing code can be migrated automatically by running `moon fmt`. The old syntax without `fn` is still supported for now; in the next version, it will start producing warnings and will be removed in the future. `impl` entries in `.mbtp` files are also now required to include the `fn` keyword.

```
trait I {
  fn f(Self) -> Unit
//^^
}

impl I for Int with fn f(_) {}
//                  ^^
```
2. Polymorphic `trait` methods are now supported. Methods inside a `trait` can now have their own type parameters. When implementing a polymorphic trait method, the method's own type parameters do not need to be annotated explicitly. If you do annotate them, put the method type parameters after the `fn` keyword, while the type parameters of the `impl` itself still go after the `impl` keyword:

```
trait Logger {
  fn[X : Show] write_object(Self, X) -> Unit
}

impl Logger for StringBuilder with fn write_object(self, x) {
  self.write_string(x.to_string())
}
```

```
trait Poly {
  fn[X] f(Self, X) -> Unit
}

impl[A] Poly for Array[A] with fn[X] f(self, x : X) {
//  ^^^ impl type parameters      ^^^ method type parameters
  ...
}
```
3. `for .. in` loops now support default updates for state variables.

```
for i in 0..<10; p1 = 1, p2 = 0; p1 = p1 + p2, p2 = p1 {
                              // ^^^^^^^^^^^^^^^^^^^^^
                              // New in this release. The semantics are
                              // the same as default updates in regular
                              // `for` loops. When `continue` with arguments
                              // is not called explicitly, these declarations
                              // update the loop variables at the end of
                              // each iteration.
  println("fib#\{i + 1} = \{p1}")
}
```
4. List comprehensions now support extra loop variables from `for .. in`.

```
let fibs = [
  for _ in 0..<10
      p1 = 1, p2 = 0
      p1 = p1 + p2, p2 = p1 => {
    p1
  }
]
```
5. When using list comprehensions to construct types other than `Iter`, the body can contain side effects. This includes `raise` and `async`.
6. String interpolation improvements.

- String interpolation used to compile to string concatenation. It now compiles to efficient writes into a `StringBuilder`. For example, `let r = "a\{b}c"`:

```
// Previous compilation result
let r = "a" + b.to_string() + "c"

// Current compilation result
let r = {
  let builder = StringBuilder(size_hint=2)
  builder.write_string("a")
  builder.write(b)
  builder.write_string("c")
  builder.to_string()
}
```
- Inside string interpolation `\{...}`, the use of `{`, `}`, and `"` is no longer restricted, so nested string interpolation is allowed.

```
let xs = ["cd", "ef"]
let r1 = "ab\{xs.join(";")}"
assert_eq(r1, "abcd;ef")
```
- Nested anonymous functions are supported inside string interpolation and receive special handling:

```
let r = "a\{builder => builder.f()}"
// Equivalent to
let r = {
  let builder = StringBuilder()
  builder.write_string("a")
  (builder => builder.f())(builder)
  builder.to_string()
}
```
7. Added template write syntax `lhs <+ rhs`. In web backend development, a common pattern is to assemble strings through a buffer. Calling `StringBuilder::write_string` and `StringBuilder::write` manually is verbose. HTML DSLs or template engines can also be used for this scenario, but they introduce extra memory allocation and string replacement overhead. Template write syntax provides a lighter, more readable solution with zero additional overhead. The following is equivalent code using the new feature:

```
fn render(
  style : String,
  li_class : String,
  items : Array[String],
) -> String {
  let buf = StringBuilder()
  // <ul prop=foo>
  buf..write_string("<ul prop=foo>")
  //   <li class="{li_style}">{item}</li>
  for item in items {
    buf..write_string("<li class=\"")
       ..write(li_class)
       ..write_string("\">")
       ..write(item)
       .write_string("</li>")
  }
  // </ul>
  buf.write("</ul>")
  buf.to_string()
}
```

```
fn render(
  style : String,
  li_class : String,
  items : Array[String],
) -> String {
  let buf = StringBuilder()
  buf <+ "<ul prop=foo>"
  for item in items {
    buf <+ $|<li class="\{li_class}">\{item}</li>
  }
  buf <+ "</ul>"
  buf.to_string()
}
```

For `buf <+ "a\{b}"`, it is decomposed directly into `buf..write_string("a")..write(b)`.

The right-hand side of `<+` supports the following expressions:

- A string: `"abc\{x}"`
- A multiline string: `#| multiline string...`
- A multiline string interpolation: `$| multiline string with \{x}`
- A map literal: `{"k1": v1, "k2": v2}`

The left-hand side of `<+` does not have to be a `StringBuilder`; it can be any type `T` that implements the following methods:

- `T::write_string(T, String)`
- `T::write(T, X)`
- Optional, for map literals: `T::write_object_begin(T)`, `T::write_object_field(T, String, X)`, and `T::write_object_end(T)`

The syntax rules for string interpolation inside `\{...}` are the same as regular string interpolation.
8. Added conditional template write syntax `lhs ```
logger <? "[tag] message \{x}..."
// Equivalent to
if logger is Some(x) {
  x <+ "[tag] message \{x}..."
}
```

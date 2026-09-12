---
source_url: https://www.roc-lang.org/functional
ingested: 2026-09-12
sha256: 9271a459a68dd2d3711faa7137a1aa547ab5f4760eb31a2f7c8324f9af3ef4a0
---
# Functional | Roc

Functional | Roc

# Functional

Roc is best described as a pure functional programming language. Most Roc code is written with immutable values and pure functions, while effects are kept explicit and separate.

Roc also offers locally mutable variables and imperative control flow—including `for`, `while`, `break`, and `return`. These features make Roc more approachable for people coming from imperative languages and can make a few algorithms clearer even for experienced Roc developers. They do not introduce shared mutable state or sacrifice function-level purity: a variable can only be reassigned inside the function where it was declared.

## Immutable by default

Roc values are semantically immutable. Passing a list, record, or other value to a function cannot let that function modify the value seen by its caller. In languages with shared mutable values, programmers often need to clone defensively to prevent unexpected changes. Roc makes that protection the default.

A reliability benefit of semantic immutability is that it rules out data races. These concurrency bugs can be difficult to reproduce and time-consuming to debug, and they require shared mutation that Roc does not expose.

Ordinary definitions are immutable too. Once `greeting = "Hello"` has introduced `greeting` in a scope, it is not intended to be reassigned or shadowed in that scope. Experienced Roc developers will generally use this functional style, with operations such as `map`, `fold`, pattern matching, and recursion.

When local mutation makes an algorithm easier to learn or clearer to read, Roc provides an explicit alternative.

## Explicit local mutation

Writing the same ordinary definition twice is not how Roc expresses reassignment. The compiler reports a shadowing warning for code like this:

```
x = 1
x = 2

```

For intentional reassignment, declare a variable with `var` and use its `$` prefix at every subsequent reference:

```
var $count = 0
$count = $count + 1

```

The `$` makes possible reassignment visible at every use site. A variable can only be reassigned within the same function that declared it; a nested function cannot reassign a variable captured from an outer function. This restriction keeps mutation local and preserves the containing function's purity.

The same principle applies to imperative control flow. Using `for`, `while`, `break`, or `return` does not by itself make a function effectful. These constructs only control evaluation inside the current function.

### Functional and imperative styles

For example, a list can be summed in a functional style with `fold`:

```
sum : List(I64) -> I64
sum = |numbers| numbers.fold(0, |total, number| total + number)

```

The same function can use a local variable and a `for` loop:

```
sum : List(I64) -> I64
sum = |numbers| {
    var $total = 0
    for number in numbers {
        $total = $total + number
    }
    $total
}

```

Both versions are pure: given the same list, they always return the same result and have no externally visible side effects. The first is the style experienced Roc developers will generally prefer; the second can be more familiar to beginners and useful when direct control flow makes an algorithm easier to follow.

### Avoiding regressions

A benefit of this design is that it makes Roc code easier to rearrange without causing regressions. Consider this code:

```
make_message = |name| {
    greeting = "Hello"
    welcome = |recipient| "${greeting}, ${recipient}!"

    welcome(name)
}

```

Suppose I decide to extract the `welcome` function to the top level, so I can reuse it elsewhere:

```
make_message = |name| welcome("Hello", name)

welcome = |greeting, name| "${greeting}, ${name}!"

```

In warning-free Roc code, neither `greeting` nor the local `welcome` can be silently reassigned between their definitions and uses. Names that can change carry the visible `$` prefix, so refactoring immutable code requires less searching for hidden mutation.

Looping can also be expressed with `List.fold` or recursion. Roc performs tail-call optimization for eligible recursive functions.

## Pure and effectful functions

Roc makes a first-class distinction between pure and effectful functions. A pure function always returns the same answer for the same arguments and has no externally visible side effects. An effectful function may perform I/O or call another effectful function.

Pure function types use `->`. Effectful function types use `=>`, and effectful function names end in `!`:

```
format_name : Str -> Str
format_name = |name| "Hello, ${name.trim()}!"

announce! : Str => {}
announce! = |name| echo!(format_name(name))

```

Unlike the former `Task`-based design, current Roc code calls effectful functions directly. Pure functions cannot call effectful functions, while effectful functions can call both. The compiler infers effectfulness and checks annotations, making the effectful boundary visible in names and types.

The application's platform provides effectful functions and decides how each effect is implemented. A platform can use synchronous blocking I/O, asynchronous I/O, or another strategy appropriate to its domain.

This explicit separation is another reason Roc is a pure functional language: application logic can remain pure by construction, while the smaller effectful boundary is easy to identify.

## Pure functions

Pure functions have valuable properties such as referential transparency: a call can be replaced with its result without changing program behavior. They are straightforward to test because their results depend only on their arguments, and they are amenable to optimizations such as memoization and compile-time evaluation.

Local variables do not change these properties. A pure function may reassign its own `$` variables internally, but callers cannot observe those intermediate states. They can only observe the function's return value.

Roc permits `dbg` and `expect` inside pure functions as special development tools. Their output is for the programmer and is not part of the program's semantics, so program behavior must not depend on it.

Roc evaluates top-level values at compile time because they can only call pure functions. Purity can also enable optimizations such as dead-code elimination, loop fusion, and hoisting work out of loops.

## Get started

If this design sounds interesting to you, you can give Roc a try by heading over to the tutorial!

---
source_url: https://www.roc-lang.org/docs/main/langref/expressions/
ingested: 2026-09-12
sha256: 3cf0d160b31b4c2119f44df3d0d30d543d206b591607f23ee0e9bbf5335dadc6
---
# Expressions Docs

Expressions Docs

# Expressions

An expression is something that evaluates to a value.

You can wrap expressions in parentheses without changing what they do. Non-expressions can't be wrapped in parentheses without causing an error. Some examples:

- `x` is a valid expression. It evaluates to a value. `(x)` is valid.
- `foo(1)` is a valid expression. It evaluates to a value. `(foo(1))` is valid.
- `1` is a valid expression. It's already a value. `(1)` is valid.
- `import Foo` is a statement not an expression. `(import Foo)` is invalid.
- `# Something` is a comment, not an expression. `(# Something)` is invalid.
- `package […]` is a module header, not an expression. `(package […])` is invalid.

Another way to think of an expression is that you can always assign it to a name—so, you can always put it after an `=` sign.

## Types of Expressions

Here are all the different types of expressions in Roc:

- String literals, e.g. `"foo"` or `"Hello, ${name}!"`
- Number literals, e.g. `1` or `2.34` or `0.123e4`
- List literals, e.g. `[1, 2]` or `[]` or `["foo"]`
- Record literals, e.g. `{ x: 1, y: 2 }` or `{}` or `{ x, y, ..other_record }`
- Tag literals, e.g. `Foo` or `Foo(bar)`
- Tuple literals, e.g. `(a, b, "foo")`
- Function literals (aka "lambdas"), e.g. `|a, b| a + b` or `|| c + d`
- Lookups, e.g. `blah` or `(blah)` or `$blah` or `($blah)` or `blah!` or `(blah!)`
- Calls, e.g. `blah(arg)` or `foo.bar(baz)`
- Operator applications, e.g. `a + b` or `!x`, which desugar to calls
- Block expressions, e.g. `{ foo() }`

There are no other types of expressions in the language.

## Values

A Roc value is a semantically immutable piece of data.

### Value Identity

Since values take up memory at runtime, each value has a memory address. Roc treats memory addresses as behind-the-scenes implementation details that should not affect program behavior, and by design exposes no language-level way to access or compare addresses.

This implies that Roc has no concept of value identity, reference equality (also known as physical equality), or pointers, all of which are semantic concepts based on memory addresses.

> Note that platform authors can choose to implement features based on memory addresses, since platforms have access to lower-level languages which can naturally see the addresses of any Roc value the platform receives. This means it's up to a platform author to decide whether it's a good idea for users of their platform to start needing to think about memory addresses, when the rest of the language is designed to keep them behind the scenes.

### Reference Counting

Heap-allocated Roc values are automatically reference-counted (atomically, for thread-safety).

Heap-allocated values include strings, lists, boxes, and recursive tag unions. Numbers, records, tuples, and non-recursive tag unions are stack-allocated, and so are not reference counted.

### Reference Cycles

Other languages support reference cycles, which create problems for reference counting systems. Solutions to these problems include runtime tracing garbage collectors for cycles, or a concept of weak references. By design, Roc has no way to express reference cycles, so none of these solutions are necessary.

### Opportunistic Mutation

Roc's compiler does opportunistic mutation using the Perceus "functional-but-in-place" reference counting system. The way this works is:

- Builtin operations on reference-counted values will update them in place when their reference counts are 1
- When their reference counts are greater than 1, they will be shallowly cloned first, and then the clone will be updated and returned.

For example, when `List.set` is passed a unique list (reference count is 1), then that list will have the given element replaced. When it's given a shared list (reference count is not 1), it will first shallowly clone the list, and then replace the given element in the clone. Either way, the modified list will be returned—regardless of whether the clone or the original was the one modified.

## Block Expressions

A block expression is an expression with some optional statements before the expression. It has its own scope, so anything assigned in it can't be accessed outside the block. The entire block evaluates to the expression at its end.

The statements are optional, so `{ x }` is a valid block expression. This is useful stylistically in situations like conditional branches:

```
x = if foo {
    …
} else {
    fallback
}
```

> Note that `{ x, y }` is a record with two fields (it's syntax sugar for `{ x: x, y: y }`), but `{ x }` is always a block expression. That's because it's much more useful to have `{ x }` be a block expression, for situations like `else { x }`, than syntax sugar for a single-field record like `{ x: x }`. Single-field records are much less common than blocks in conditional branches.

## Evaluation

Evaluation is the process of an expression becoming a value.

Like most programming languages, Roc uses strict evaluation and does not support lazy evaluation like some non-strict languages do (such as Haskell).

Expressions that are already values (such as `4`, `"foo"`, etc.) evaluate to themselves.

More complex expressions, such as function calls or block expressions may require multiple steps to evaluate to a value.

### Side Effects during evaluation

Normally, only evaluating effectful functions can cause side effects, but evaluating any other type of expression cannot.

One exception to this rule is `dbg` statements, which perform the side effect of logging a value for debugging purposes. This is intended to be an interface for debugging, much like a step debugger, not part of a program's semantics, and so the side effect is allowed outside effectful functions (just like step debugging works on any expression, not just calling effectful functions).

The only other exception to the rule is `expect` statements, which similarly perform the side effect of reporting failed expectations. Like `dbg`, this output is intended for the programmer only, and is not part of a program's semantics.

> Note that platform authors are in charge of what happens when memory gets allocated and deallocated, and can therefore decide to perform side effects during memory allocation and deallocation. This can easily cause surprising behavior for Roc application authors, and should not be relied upon because Roc's optimizer assumes memory allocation and deallocation has no observable effect on the program (unless allocation fails), which means these side effects may be optimized away differently between patch releases of the compiler.

### Compile-Time Evaluation

When possible, Roc's compiler will evaluate expressions at compile-time instead of at runtime.

This is only possible for expressions that depend only on values known at compile-time. The following are not known at compile time:

- Values returned from effectful function calls (which can vary based on runtime state)
- Values provided by the platform

If a `crash` is encountered during compile-time evaluation, it will be reported at compile time just like any other compilation error (such as syntax errors, naming errors, and type mismatches).

Note that functions are values! If you define a top-level function by calling other top-level functions, all of that work will be done at compile time:

```
make_adder = |amount_to_add| |num| num + amount_to_add

add_one = make_adder(1)
add_two = make_adder(2)
add_three = |num| num + 3
```

Here, the `add_one`, `add_two`, and `add_three` functions will be identical in the compiled Roc binary (aside from the number being added). The fact that the first two were defined by calling other functions is irrelevant, as that work happens at build time when `add_one` and `add_two` are being evaluated.

Made by people who like to make nice things.

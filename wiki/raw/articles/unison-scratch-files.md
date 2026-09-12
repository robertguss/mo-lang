---
source_url: https://www.unison-lang.org/docs/tour/_scratch-files/
ingested: 2026-09-12
sha256: b0fc6f4984a787b060a974027a47beecc24f716bd30cc67d200fcd38ff71172f
---
# Unison's interactive scratch files

# Unison's interactive scratch files

The codebase manager listens for changes to any file ending in`.u` in the current directory. When any such file is saved (which we call a "scratch file"), Unison parses and typechecks that file.

Keep your`ucm` terminal running and open up a file,`scratch.u`(or`foo.u`, or whatever you like) in your preferred text editor.

Put the following in your scratch file:

```
square : Nat -> Nat
square x =
  use Nat *
  x * x
```

This defines a function called`square`. It takes an argument called`x` and it returns`x` multiplied by itself.

The`use Nat *` is a use clause which specifies which "*" operator we want to use. This one is from the`Nat` namespace in our`lib.base` standard library. Use clauses mean we can refer to`base.Nat` as simply`Nat` and can refer to`*` without prefixing it`Nat.*`.

When you save the file, Unison indicates whether or not the change can be applied:

```
I found and typechecked these definitions in ~/unisoncode/scratch.u. If you do an `update`, here's how your codebase would change:

  ⍟ New definitions:

    square : Nat -> Nat
```

Before we save`square` in the codebase, let's try calling it right in the`scratch.u` file, in a line starting with`>`:

```
square : Nat -> Nat
square x =
  use Nat *
  x * x

> square 4
```

Save the file, and Unison prints:

```
6 | > square 4
      ⧩
      16
```

The`> square 4` on line 6 is called a "watch expression". Unison uses watch expressions to run code inline, instead of having a separate read-eval-print-loop (REPL). Everything in your scratch file and your project is in scope, so you can test code as you go with all the features of your text editor.

Question: Should we reevaluate all watch expressions on every save, even if they're expensive? Unison avoids this by caching results, keyed by the hash of each expression. If the hash hasn't changed, Unison reuses the cached result. You can clear the cache anytime without issues. Think of your`.u` files like spreadsheets — only the cells whose dependencies change get recomputed.

🤓

There's one more ingredient that makes this work effectively, and that's functional programming. When an expression has no side effects, its result is deterministic, and you can cache it as long as you have a good key for the cache, like the Unison content-based hash. Unison's type system won't let you do I/O inside one of these watch expressions or anything else that would make the result change from one evaluation to the next.

Try out a few more watch expressions and see how the UCM responds:

```
-- A comment, ignored by Unison

> List.reverse [1,2,3,4]
> 4 + 6
> 5.0 / 2.0
> not true
```

## Deterministic

A function which is deterministic will always return the same result for the given set of input values.

## Watch expression

In a file with the`.u` extension, any line beginning with`>` is a watch expression. A watch expression tells the UCM to execute the Unison expression to the right of the symbol and render the result to the console.

Watch expressions cannot execute code whose abilities are not enclosed by a handler.

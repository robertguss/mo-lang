# The prelude

Every stdlib type, variant, function, and operator a Mo module may use without declaring it. The same rows live as data in `src/prelude.zig`; the checker reads nothing else. **Nothing outside these tables exists.** A row marked *corpus-only* is not named by `mo-wiki/spec/grammar.md` or design-v0: a corpus file needs it, and `examples/GAPS.md` records it until the stdlib chapter settles it.

Type strings: `T`, `U`, `A`, `E` are type variables fresh at each call; `N` is the receiver's own integer type; `P` is the process a handle or message belongs to; `Message(P)` is one of P's `message` lines; `Reply` is the reply type of the message passed; `none` is no value (the call is a statement).

## Types

| name | arguments | kind | origin |
|---|---|---|---|
| `Int8`, `Int16`, `Int32`, `Int64` | | signed integer | grammar |
| `UInt8`, `UInt16`, `UInt32`, `UInt64` | | unsigned integer | grammar |
| `Float32`, `Float64` | | float | grammar |
| `Bool` | | `true`, `false` | grammar |
| `String` | | UTF-8 text | grammar |
| `Time` | | an instant | grammar |
| `Duration` | | a length of time | grammar |
| `List` | `T` | list | grammar |
| `Option` | `T` | `Some(T)` or `None` | grammar |
| `Result` | `T`, `E` | `Ok(T)` or `Error(E)` | grammar |
| `(A, B, ...)` | two or more | tuple | grammar |
| `Handle` | a process name | a started process | grammar |
| `Clock` | | capability | grammar |
| `Fs` | | capability | grammar |
| `Events` | | capability | grammar |
| `Ledger` | | capability | grammar |
| `FsError` | | error enum | grammar (name); variants corpus-only |
| `AskError` | | error enum | grammar |

## Variants

| type | variant | fields | origin |
|---|---|---|---|
| `Option(T)` | `Some` | one positional `T` | grammar |
| `Option(T)` | `None` | | grammar |
| `Result(T, E)` | `Ok` | one positional `T` | grammar |
| `Result(T, E)` | `Error` | one positional `E` | grammar |
| `FsError` | `Missing` | `path: String` | corpus-only |
| `FsError` | `Timeout` | | corpus-only |
| `AskError` | `Timeout` | | grammar |
| `AskError` | `Down` | | grammar |

## Functions

Every function is called with a dot on its receiver (`xs.push(x)`), or on the type for rows marked *on type* (`Clock.fixture()`). *Waits* means the call can wait, so it takes `within: Duration` and the checker rejects it without one (MO0401); a call that cannot wait rejects `within:` (MO0402).

| receiver | name | parameters | returns | waits | where | origin |
|---|---|---|---|---|---|---|
| `List(T)` | `size` | | `UInt64` | | | grammar |
| `List(T)` | `push` | `T` | `List(T)` | | | grammar |
| `List(T)` | `map` | `fn(T) U` | `List(U)` | | | grammar |
| `List(T)` | `filter` | `fn(T) Bool` | `List(T)` | | | grammar |
| `List(T)` | `reduce` | `A`, `fn(A, T) A` | `A` | | | grammar |
| `List(T)` | `contains?` | `T` | `Bool` | | | grammar |
| `List(T)` | `first` | | `Option(T)` | | | grammar |
| `List(T)` | `last` | | `Option(T)` | | | grammar |
| `String` | `size` | | `UInt64` (graphemes) | | | grammar |
| `String` | `bytes` | | `List(UInt8)` | | | grammar |
| `String` | `starts_with?` | `String` | `Bool` | | | grammar |
| any integer `N` | `checked_add`, `checked_sub`, `checked_mul` | `N` | `Option(N)` | | | grammar |
| any integer `N` | `saturating_add`, `saturating_sub`, `saturating_mul` | `N` | `N` | | | grammar |
| any integer `N` | `wrapping_add`, `wrapping_sub`, `wrapping_mul` | `N` | `N` | | | grammar |
| any integer | `ms`, `minute`, `days` | | `Duration` | | | grammar |
| `Time` (on type) | `fixture` | | `Time` | | tests | grammar |
| `Clock` | `now` | | `Time` | | | grammar |
| `Clock` (on type) | `fixture` | | `Clock` | | tests | grammar |
| `Fs` | `read` | `String` | `Result(String, FsError)` | yes | | grammar |
| `Fs` | `scoped` | `String` | `Fs` | | | grammar |
| `Fs` | `read_only` | | `Fs` | | | grammar |
| `Fs` (on type) | `fixture` | | `Fs` | | tests | grammar |
| `Fs` (on type) | `fixture` | `delay: Duration` | `Fs` | | tests | grammar |
| `Events` | `emit` | `T` | none | | | grammar |
| `Events` (on type) | `fixture` | | `Events` | | tests | grammar |
| `Ledger` (on type) | `fixture` | | `Ledger` | | tests | grammar |
| a process `P` (on type) | `start` | the process's parameters | `Handle(P)` | | | grammar |
| `Handle(P)` | `send` | `Message(P)` | none | | | grammar |
| `Handle(P)` | `ask` | `Message(P)` | `Result(Reply, AskError)` | yes | | grammar |
| any declared type `T` (on type) | `all` | | `List(T)` | | `never` | grammar |
| none | `flows` | a type, `into:` a capability | `Bool` | | `never` | grammar |

## Operators

Numbers take `+ - * / %` and comparisons with both sides of one type; `and`, `or`, `!`, `implies` take `Bool`; `or` on `Option(T)` with a `T` gives `T`; `==` and `!=` compare any two values of one type. Beyond those:

| left | op | right | result | origin |
|---|---|---|---|---|
| `Time` | `-` | `Time` | `Duration` | grammar |
| `Time` | `+` | `Duration` | `Time` | grammar |
| `Time` | `-` | `Duration` | `Time` | grammar |
| `Duration` | `+` | `Duration` | `Duration` | grammar |
| `Duration` | `-` | `Duration` | `Duration` | grammar |

`Time` and `Duration` compare with `<`, `<=`, `>`, `>=` against their own type.

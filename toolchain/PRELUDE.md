# The prelude

Every stdlib type, variant, function, and operator a Mo module may use without declaring it. The same rows live as data in `src/prelude.zig`; the checker reads nothing else. **Nothing outside these tables exists.** A row marked *stdlib (09)* is named by `mo-wiki/spec/design-v0/09-stdlib.md`, which says what each one does; `src/stdlib.zig` runs it. A row marked *corpus-only* is not named by `mo-wiki/spec/grammar.md` or design-v0: a corpus file needs it, and `examples/GAPS.md` records it until the stdlib chapter settles it.

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
| `Platform` | | capability: `fn main`'s one parameter, and nowhere else | grammar (Q18) |
| `Env` | | capability: the process's environment variables | grammar (Q18) |
| `Out` | | capability: a standard stream, `stdout` or `stderr` | grammar (Q18) |
| `FsError` | | error enum | grammar (name); variants corpus-only |
| `AskError` | | error enum | grammar |
| `LedgerError` | | error enum | corpus-only |

## Stand-ins

Types chapter 4's refund module takes from `Payments.Ledger` and the event log, which are not written yet. A module that declares one of these names itself uses its own declaration (`contracts/flows.mo` declares `CardNumber`).

| name | is | fields | origin |
|---|---|---|---|
| `ChargeId` | `String` | | corpus-only |
| `Money` | `UInt64` | | corpus-only |
| `CardNumber` | `String` | | corpus-only |
| `Charge` | struct | `id: ChargeId`, `captured_at: Time`, `captured_amount: Money`, `refunded: Bool` | corpus-only |
| `RefundRequest` | struct | `id: ChargeId`, `amount: Money` | corpus-only |
| `RefundCompleted` | struct | `refund: T` | corpus-only |
| `RefundFailed` | struct | `request: RefundRequest`, `reason: E` | corpus-only |

`T` and `E` in a stand-in's fields are bound by the one module that builds it.

## Values

| name | type | where | origin |
|---|---|---|---|
| `t0` | `Time` (the instant `Time.fixture()` gives) | tests | corpus-only |

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
| `LedgerError` | `Timeout` | | corpus-only |

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
| `String` (on type) | `from_bytes` | `List(UInt8)` | `Option(String)` | | | stdlib (09) |
| `String` | `chars`, `lines` | | `List(String)` | | | stdlib (09) |
| `String` | `split` | `String` | `List(String)` | | | stdlib (09) |
| `String` | `trim`, `to_upper`, `to_lower` | | `String` | | | stdlib (09) |
| `String` | `ends_with?`, `contains?` | `String` | `Bool` | | | stdlib (09) |
| `String` | `index_of` | `String` | `Option(UInt64)` | | | stdlib (09) |
| `String` | `slice` | `UInt64`, `UInt64` | `String` | | | stdlib (09) |
| `String` | `replace` | `String`, `String` | `String` | | | stdlib (09) |
| `String` | `pad_left`, `pad_right` | `UInt64`, `String` | `String` | | | stdlib (09) |
| `String` | `repeat` | `UInt64` | `String` | | | stdlib (09) |
| `String` (on type) | `join` | `List(String)`, `String` | `String` | | | stdlib (09) |
| `String` | `to_u64` | | `Option(UInt64)` | | | stdlib (09) |
| `String` | `to_i64` | | `Option(Int64)` | | | stdlib (09) |
| `String` | `to_f64` | | `Option(Float64)` | | | stdlib (09) |
| any integer | `to_u8`, `to_u16`, `to_u32`, `to_u64`, `to_i64` | | that type | | | stdlib (09) |
| any integer | `checked_to_u8`, `checked_to_u16`, `checked_to_u32`, `checked_to_u64`, `checked_to_i64` | | `Option` of that type | | | stdlib (09) |
| any integer | `to_f64` | | `Float64` | | | stdlib (09) |
| `Float64` | `round` | `UInt64` | `Float64` | | | stdlib (09) |
| `Float64` | `to_string` | `UInt64` | `String` | | | stdlib (09) |
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
| `Ledger` | `find_charge` | `ChargeId` | `Result(Charge, LedgerError)` | yes | | corpus-only |
| `Ledger` | `save_charge` | `Charge` | `Result(none, LedgerError)` | yes | | corpus-only |
| `Platform` | `args` | | `List(String)` | | `main` | grammar (Q18) |
| `Platform` | `env` | | `Env` | | `main` | grammar (Q18) |
| `Platform` | `stdout`, `stderr` | | `Out` | | `main` | grammar (Q18) |
| `Platform` | `fs` | | `Fs` | | `main` | grammar (Q18) |
| `Platform` | `clock` | | `Clock` | | `main` | grammar (Q18) |
| `Platform` | `exit` | `UInt8` | none | | `main` | grammar (Q18) |
| `Env` | `get` | `String` | `Option(String)` | | | grammar (Q18) |
| `Out` | `write` | `String` | none | | | grammar (Q18) |
| `Charge` (on type) | `fixture` | `captured_amount: Money` | `Charge` | | tests | corpus-only |
| `Charge` (on type) | `fixture` | `captured_at: Time`, `captured_amount: Money` | `Charge` | | tests | corpus-only |
| `Charge` | `refunded?` | | `Bool` | | | corpus-only |
| `Money` (on type) | `cents` | `UInt64` | `Money` | | | corpus-only |
| `Money` (on type) | `zero` | | `Money` | | | corpus-only |
| a process `P` (on type) | `start` | the process's parameters | `Handle(P)` | | | grammar |
| `Handle(P)` | `send` | `Message(P)` | none | | | grammar |
| `Handle(P)` | `ask` | `Message(P)` | `Result(Reply, AskError)` | yes | | grammar |
| any declared type `T` (on type) | `all` | | `List(T)` | | `never` | grammar |
| none | `flows` | a type, `into:` a capability | `Bool` | | `never` | grammar |

### The platform

`fn main(platform: Platform)` is the only place a `Platform` exists (grammar §2, Q18). Its parts read like fields (`platform.fs`, `platform.args`) and are passed down, narrowed (`platform.fs.scoped("data").read_only`); the `Platform` itself is never passed, bound, stored, or returned (MO0407), and no other function, process, or supervisor takes one. `mo test` never holds a Platform, so these rows run only under `mo run`, on Mo.Server.

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

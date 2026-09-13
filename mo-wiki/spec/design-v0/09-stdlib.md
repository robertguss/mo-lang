# 9. Standard library

The first shelf of chapter 6: first-party, audited once, the only code in a Mo program that is not yours. This chapter is the table a reader checks a call against. Every row is a built-in of the interpreter (`toolchain/src/vm.zig`), listed again as data in `toolchain/src/prelude.zig` and `toolchain/PRELUDE.md`, and exercised by one corpus file per group under `examples/stdlib/`. **A call that is not a row here or in `PRELUDE.md` does not exist.**

This is the part of the box the first three programs need (`examples/GAPS.md`), not the whole box. Regex, HTTP, crypto, compression, and database drivers come when a program demands them.

## Rules for every row

- **Deterministic.** Given equal arguments, a row gives an equal result on every machine and every run. Nothing reads a clock, a random source, or an address unless its receiver is a capability. Replay depends on it (chapter 3).
- **Values in, values out.** A row that "changes" a list, map, set, or string returns a new value; the receiver is unchanged. On a `var` that nothing else holds, the runtime may do the work in place (`push`, `Map.set`, `Set.add`); no program can tell.
- **Rain is a value, a bug is a crash.** A row whose input comes from outside the program (text to parse, a file) returns `Option` or `Result`. A row whose failure means the caller broke a rule (an integer that does not fit its target type, a rounding to 400 places) crashes with a report, like a tripped `requires`.
- **Indices and sizes are `UInt64`.** String positions count graphemes, as `size` does; `bytes` is the escape hatch to bytes.
- **Clamped, not crashed.** `slice`, `take`, and `drop` clamp their bounds to the value they cut, so `"abc".slice(1, 99)` is `"bc"` and `[1, 2].drop(5)` is `[]`.
- **One order.** The natural order `sort`, `min`, and `max` use is the order of `<`: integers and floats by value, strings byte by byte (which is code point order for UTF-8), `Time` and `Duration` by value, and tuples of those left to right. Bools, structs, enums, lists, maps, and sets have no order, and the checker rejects them there. `sort` is stable. A float NaN sorts after every number.
- **Defined order for maps and sets.** Keys iterate in the order they were first added. Setting an existing key keeps its place; removing a key and adding it again puts it last. Two maps are equal when they hold equal entries in the same order.

Type variables: `T`, `U`, `A`, `K`, `V` are fresh at each call. `N` is the receiver's own integer type. An argument written `fn(T) U` is an anonymous function (a signature cannot name a function type, so a row that needs a comparison takes a key function instead).

## Integers and floats

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| any integer | `checked_add`, `checked_sub`, `checked_mul` | `N` | `Option(N)` | `None` when the exact result does not fit `N` |
| any integer | `saturating_add`, `saturating_sub`, `saturating_mul` | `N` | `N` | the exact result clamped to `N` |
| any integer | `wrapping_add`, `wrapping_sub`, `wrapping_mul` | `N` | `N` | the exact result's low bits |
| any integer | `to_u8`, `to_u16`, `to_u32`, `to_u64`, `to_i64` | | that type | the same number in another width; one that does not fit is a crash |
| any integer | `checked_to_u8`, `checked_to_u16`, `checked_to_u32`, `checked_to_u64`, `checked_to_i64` | | `Option` of that type | the same number, or `None` when it does not fit |
| any integer | `to_f64` | | `Float64` | the nearest `Float64` |
| `Float64` | `round` | `places: UInt64` | `Float64` | rounded to `places` decimals, half away from zero, on the number's shortest decimal spelling (so `2.675.round(2)` is `2.68`); `places` above 15 is a crash |
| `Float64` | `to_string` | `places: UInt64` | `String` | exactly `places` decimals, rounded as `round` does (`3.0.to_string(1)` is `"3.0"`); NaN is `"NaN"`, infinities `"Infinity"` and `"-Infinity"` |
| `String` | `to_u64` | | `Option(UInt64)` | ASCII digits only, at least one, no sign, no spaces, no `_`; `None` otherwise or when it does not fit |
| `String` | `to_i64` | | `Option(Int64)` | as `to_u64`, with one optional leading `-` |
| `String` | `to_f64` | | `Option(Float64)` | an optional `-`, digits, optionally `.` and digits, optionally `e` or `E`, a sign, and digits; no `NaN`, no `Infinity` |

## Strings

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| `String` | `size` | | `UInt64` | graphemes |
| `String` | `bytes` | | `List(UInt8)` | the UTF-8 bytes |
| `String` (on type) | `from_bytes` | `List(UInt8)` | `Option(String)` | the text those bytes spell; `None` when they are not valid UTF-8 |
| `String` | `chars` | | `List(String)` | one string per grapheme |
| `String` | `split` | `sep: String` | `List(String)` | the pieces between each `sep`, empty pieces kept (`"a,,b"` is three); an empty `sep` gives `chars` |
| `String` | `lines` | | `List(String)` | split on `"\n"`, each line's one trailing `"\r"` removed; a final newline does not start another line, and `""` has no lines |
| `String` | `trim` | | `String` | without leading and trailing Unicode whitespace |
| `String` | `starts_with?`, `ends_with?`, `contains?` | `String` | `Bool` | whether the text begins with, ends with, or holds the argument; every string holds `""` |
| `String` | `index_of` | `String` | `Option(UInt64)` | the grapheme position of the first occurrence |
| `String` | `slice` | `from: UInt64`, `to: UInt64` | `String` | graphemes `from` up to, not including, `to`, both clamped |
| `String` | `replace` | `a: String`, `b: String` | `String` | every non-overlapping `a`, left to right, replaced by `b`; an empty `a` changes nothing |
| `String` | `to_upper`, `to_lower` | | `String` | ASCII letters changed, every other byte kept |
| `String` | `pad_left`, `pad_right` | `n: UInt64`, `ch: String` | `String` | `ch` added before or after until the text is `n` graphemes; a longer text is unchanged; `ch` that is not one grapheme is a crash |
| `String` | `repeat` | `n: UInt64` | `String` | the text `n` times |
| `String` (on type) | `join` | `List(String)`, `sep: String` | `String` | the strings with `sep` between each two |

## Lists

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| `List(T)` | `size` | | `UInt64` | elements |
| `List(T)` | `push` | `T` | `List(T)` | the element added at the end |
| `List(T)` | `get` | `i: UInt64` | `Option(T)` | element `i`, from 0 |
| `List(T)` | `first`, `last` | | `Option(T)` | |
| `List(T)` | `contains?` | `T` | `Bool` | whether an element equals it |
| `List(T)` | `slice` | `from: UInt64`, `to: UInt64` | `List(T)` | elements `from` up to, not including, `to`, both clamped |
| `List(T)` | `take`, `drop` | `n: UInt64` | `List(T)` | the first `n`, or all but the first `n` |
| `List(T)` | `concat` | `List(T)` | `List(T)` | this list, then the other |
| `List(T)` | `reverse` | | `List(T)` | |
| `List(T)` | `map` | `fn(T) U` | `List(U)` | |
| `List(T)` | `filter` | `fn(T) Bool` | `List(T)` | the elements it keeps, in order |
| `List(T)` | `reduce` | `A`, `fn(A, T) A` | `A` | folded from the left |
| `List(T)` | `flat_map` | `fn(T) List(U)` | `List(U)` | each result concatenated in order |
| `List(T)` | `any?`, `all?` | `fn(T) Bool` | `Bool` | stops at the first element that settles it; `[]` is `false` for `any?`, `true` for `all?` |
| `List(T)` | `find` | `fn(T) Bool` | `Option(T)` | the first element it keeps |
| `List(T)` | `count` | `fn(T) Bool` | `UInt64` | how many it keeps |
| `List(T)`, `T` ordered | `sort` | | `List(T)` | in natural order, stable |
| `List(T)` | `sort_by` | `fn(T) K`, `K` ordered | `List(T)` | by the key's natural order, stable; the key is computed once per element |
| `List(T)`, `T` ordered | `min`, `max` | | `Option(T)` | the first least or greatest element |
| `List(T)`, `T` an integer | `sum` | | `T` | the total; one that does not fit `T` is a crash, like `+` |
| `List(T)` | `zip` | `List(U)` | `List((T, U))` | pairs by position, as long as the shorter list |
| `List(T)` | `enumerate` | | `List((UInt64, T))` | each element with its position |
| `List(T)` | `unique` | | `List(T)` | each first occurrence, in order |
| `List(T)` | `group_by` | `fn(T) K` | `Map(K, List(T))` | elements by key, keys in order of first appearance, each list in order |

## Maps and sets

`Map(K, V)` and `Set(T)` are values like lists. There are no map or set literals in this step: a map is built from `Map.new()` with `set`, `update`, or `group_by` (`examples/GAPS.md` records the gap).

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| `Map` (on type) | `new` | | `Map(K, V)` | the empty map; `K` and `V` come from its uses |
| `Map(K, V)` | `size` | | `UInt64` | entries |
| `Map(K, V)` | `get` | `K` | `Option(V)` | |
| `Map(K, V)` | `has?` | `K` | `Bool` | |
| `Map(K, V)` | `set` | `K`, `V` | `Map(K, V)` | with the entry; an existing key keeps its place |
| `Map(K, V)` | `update` | `K`, `default: V`, `fn(V) V` | `Map(K, V)` | the key's value, or `default` when it has none, passed through the function and set (`counts.update(path, 0, fn(n) n + 1 end)`) |
| `Map(K, V)` | `remove` | `K` | `Map(K, V)` | without the key; unchanged when it is absent |
| `Map(K, V)` | `keys` | | `List(K)` | in order |
| `Map(K, V)` | `values` | | `List(V)` | in key order |
| `Map(K, V)` | `entries` | | `List((K, V))` | in order |
| `Set` (on type) | `new` | | `Set(T)` | the empty set |
| `Set(T)` | `size` | | `UInt64` | elements |
| `Set(T)` | `add` | `T` | `Set(T)` | with the element; an existing one keeps its place |
| `Set(T)` | `remove` | `T` | `Set(T)` | without it |
| `Set(T)` | `has?` | `T` | `Bool` | |
| `Set(T)` | `to_list` | | `List(T)` | in order |

## Time

`Time` is an instant, kept to the millisecond, in UTC; `Duration` is a signed length of time in milliseconds.

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| `Time` (on type) | `parse` | `String` | `Option(Time)` | RFC 3339: `2026-09-12T10:00:02Z`, with optional fractional seconds (`.5`, `.123456`, kept to the millisecond, truncated) and `Z` or an offset `+02:00`; a date or time that does not exist (`02-30`, `24:00:00`, a leap second) is `None` |
| `Time` (on type) | `from_parts` | `year`, `month`, `day`, `hour`, `minute`, `second`, all `UInt64` | `Time` | that instant in UTC; a year above 9999 or a date or time that does not exist is a crash (use `parse` for text from outside) |
| `Time` | `to_iso8601` | | `String` | `2026-09-12T10:00:02Z`, with `.mmm` only when the milliseconds are not zero |
| `Time` | `since` | `Time` | `Duration` | this instant minus the other, `a - b` |
| `Duration` | `ms` | | `Int64` | whole milliseconds |
| `Duration` | `seconds`, `minutes` | | `Float64` | |
| any integer | `ms`, `minute`, `days` | | `Duration` | a duration of that many |
| `Time` (on type) | `fixture` | | `Time` | 2026-01-01T00:00:00Z; tests only |

`Time - Time` is a `Duration`, `Time ± Duration` a `Time`, and both compare with `<`.

## Files

Every `Fs` row can wait, so it takes `within: Duration`. A name is relative to the scope the `Fs` was narrowed to (`fs.scoped("logs").read_only`), and nothing outside the scope is reachable; a path that leaves it, or anything that is not a readable file, is `Missing(path)` with the path as the program wrote it.

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| `Fs` | `read` | `path: String` | `Result(String, FsError)` | the whole file |
| `Fs` | `read_lines` | `path: String` | `Result(List(String), FsError)` | the file split as `String.lines` splits it |
| `Fs` | `size` | `path: String` | `Result(UInt64, FsError)` | the file's length in bytes |
| `Fs` | `list` | | `Result(List(String), FsError)` | the names of the files and folders directly inside the scope, sorted byte by byte; `Missing(".")` when the scope is not a readable folder |
| `Fs` | `scoped` | `String` | `Fs` | narrowed to a folder inside this scope |
| `Fs` | `read_only` | | `Fs` | narrowed to reading |
| `Fs` (on type) | `fixture` | | `Fs` | an empty file system: every read is `Missing`, `list` is `Ok([])`; tests only |
| `Fs` (on type) | `fixture` | `delay: Duration` | `Fs` | every call that waits less than `delay` is `Timeout`; tests only |

## Output

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| `Out` | `write` | `String` | none | the text, as it is |
| `Out` | `write_line` | `String` | none | the text, then `"\n"` |

## JSON

`Json` is an ordinary enum, matched with `case` like any other:

```ruby
enum Json
  Object(fields: Map(String, Json))
  Array(items: List(Json))
  String(text: String)
  Number(value: Float64)
  Bool(value: Bool)
  Null
end

enum JsonError
  Syntax(at: UInt64)
end
```

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| `Json` (on type) | `encode` | `T` | `String` | the value as JSON text on one line, `", "` between items and `": "` after a key |
| `Json` (on type) | `decode` | `String` | `Result(Json, JsonError)` | the RFC 8259 value the whole text spells; `Syntax(at)` is the byte offset of the first thing that is not JSON |

`encode` spells each value this way:

| Mo value | JSON |
|---|---|
| a struct | an object, one key per field, in declaration order |
| an enum variant with no fields | its name as a string: `"Timeout"` |
| a variant with fields | an object with one key, its name, holding an object of its fields: `{"Missing": {"path": "a.log"}}` |
| `Some(x)`, `None` | `x`, `null` |
| `Ok(x)`, `Error(e)` | `{"Ok": x}`, `{"Error": e}` |
| a list, a tuple, a set | an array, in order |
| a map with `String` keys | an object, in key order |
| any other map | an array of `[key, value]` arrays, in key order |
| a string | a string, with `"`, `\`, and control characters escaped |
| an integer | its digits |
| a float | its shortest decimal spelling that reads back as the same float, with a `.0` when it has no fraction (`3.0`); NaN and the infinities are `null` |
| a `Bool` | `true`, `false` |
| a `Time`, a `Duration` | `to_iso8601`'s string, whole milliseconds |
| a `Json` | the JSON it holds, so `Json.encode` of a decoded value round-trips |

A function, a capability, or a handle has no JSON; encoding one is a crash. `decode` reads every number as a `Float64`; an object with a repeated key keeps the last value in the first key's place; nesting deeper than 512 is `Syntax`.

## Not in this step

Map and set literals; Unicode case mapping (`to_upper` is ASCII); full grapheme segmentation (a grapheme is a code point with the combining marks after it, as `size` counts); a float-to-integer conversion; streaming reads; writing files. Each waits for a program that needs it.

## Net

`Net` is TCP, `platform.net` in `main` (step 11). A `Listener` and a `Conn` are capabilities too: a `Net` call gives them, they travel only as parameters (a listening process hands each connection to a worker with `Worker.start(conn)`), and a `Conn` closes when the process holding it stops, restarted or not. Every row that can wait takes `within: Duration`; a call past its deadline is `Timeout`, and leaves the listener or the connection as its row says. A process waiting in a call does not hold up the others: they keep taking messages.

```ruby
enum NetError
  Timeout
  Refused
  Closed
  LineTooLong
  Busy
end
```

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| `Net` | `listen` | `port: UInt16` | `Result(Listener, NetError)` | a TCP listener on 127.0.0.1 at `port`, or at a free port the system picks when `port` is 0; `Busy` when another listener holds the port, `Refused` when the system will not bind it; binding does not wait |
| `Net` | `connect` | `host: String`, `port: UInt16` | `Result(Conn, NetError)` | a connection to an IP address or a host name; `Refused` when nothing listens there or the host is not found; `Timeout` leaves no connection |
| `Listener` | `accept` | | `Result(Conn, NetError)` | the next client; `Timeout` leaves the listener listening; `Busy` when another `accept` is already waiting on it |
| `Listener` | `port` | | `UInt16` | the port it listens on |
| `Conn` | `read_line` | | `Result(Option(String), NetError)` | the next line without its `"\n"` and one `"\r"` before it, or `None` at the end of the stream (a last line with no newline comes first); a line of more than 64 KiB (65,536 bytes before its newline) is `LineTooLong`, and the next read starts after that line; `Timeout` keeps what arrived of an unfinished line for the next read; `Busy` when another `read_line` is waiting on it |
| `Conn` | `write` | `String` | `Result(none, NetError)` | the text, as it is, all of it; `Closed` when the other side is gone; `Timeout` closes the connection, since part of the text may have gone; `Busy` when another `write` is waiting on it |
| `Conn` | `close` | | none | closes the connection: a call waiting on it ends with `Closed`, and so does every later call |
| `Net` (on type) | `fixture` | | `Net` | a network in memory, shared by every fixture in the test; tests only |

A `Net.fixture()` lets a test start a server process, connect a client, and drive the protocol with no real socket. What one end writes waits for the other end to read it, and a closed end is the end of the stream for the other. `listen(0)` picks a port from 49152 up; `connect` to a port nothing listens on is `Refused`; the host is not looked at. A simulated call cannot wait for something to happen, so a call with nothing to take (an `accept` with no client, a `read_line` with no whole line) waits its whole deadline and is `Timeout`. Under `mo test --sim`, a fixture call that can wait times out by the seed, and a `read_line` or `write` finds its connection `Closed` by the seed; each leaves the connection as the real call would.

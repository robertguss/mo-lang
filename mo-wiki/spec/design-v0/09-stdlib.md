# 9. Standard library

The first shelf of chapter 6: first-party, audited once, the only code in a Mo program that is not yours. This chapter is the table a reader checks a call against. Every row is a built-in of the interpreter (`toolchain/src/vm.zig`), listed again as data in `toolchain/src/prelude.zig` and `toolchain/PRELUDE.md`, and exercised by one corpus file per group under `examples/stdlib/`. **A call that is not a row here or in `PRELUDE.md` does not exist.**

This is the part of the box the first three programs need (`examples/GAPS.md`), and HTTP for the fourth (`## Http`), not the whole box. Regex, TLS, crypto, compression, and database drivers come when a program demands them.

## Rules for every row

- **Deterministic.** Given equal arguments, a row gives an equal result on every machine and every run. Nothing reads a clock, a random source, or an address unless its receiver is a capability. Replay depends on it (chapter 3).
- **Values in, values out.** A row that "changes" a list, map, set, or string returns a new value; the receiver is unchanged. On a `var` that nothing else holds, the runtime may do the work in place (`push`, `Map.set`, `Set.add`); no program can tell.
- **Rain is a value, a bug is a crash.** A row whose input comes from outside the program (text to parse, a file) returns `Option` or `Result`. A row whose failure means the caller broke a rule (an integer that does not fit its target type, a rounding to 400 places) crashes with a report, like a tripped `requires`.
- **Indices and sizes are `UInt64`.** String positions count graphemes, as `size` does; `bytes` is the escape hatch to bytes.
- **Clamped, not crashed.** `slice`, `take`, and `drop` clamp their bounds to the value they cut, so `"abc".slice(1, 99)` is `"bc"` and `[1, 2].drop(5)` is `[]`.
- **One order.** The natural order `sort`, `min`, and `max` use is the order of `<`: integers and floats by value, strings byte by byte (which is code point order for UTF-8), `Time` and `Duration` by value, and tuples of those left to right. Bools, structs, enums, lists, maps, and sets have no order, and the checker rejects them there. `sort` is stable. A float NaN sorts after every number.
- **Defined order for maps and sets.** Keys iterate in the order they were first added. Setting an existing key keeps its place; removing a key and adding it again puts it last. Two maps are equal when they hold equal keys with equal values, and two sets when they hold equal elements, in any order. Session 5, step 18: equality by content, where it was by order.

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
| `String` (on type) | `grouped` | any integer | `String` | the integer in Mo's own spelling, `_` between each three digits from the right: `String.grouped(1204)` is `"1_204"`, and a negative one keeps its `-`. Step 28, after program 2 built `1_204` from the digits |

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
| `String` | `byte_size` | | `UInt64` | the UTF-8 bytes, counted without building `bytes` |

## Lists

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| `List(T)` | `size` | | `UInt64` | elements |
| `List(T)` | `push` | `T` | `List(T)` | the element added at the end |
| `List(T)` | `get` | `i: UInt64` | `Option(T)` | element `i`, from 0 |
| `Option(T)` | `map` | `fn(T) U` | `Option(U)` | `Some` of the function's value for a `Some`, and `None` for a `None`. Step 28, after program 1 wrote a `case` to turn a found change into its value |
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
| `List(T)` | `sort_by_desc` | `fn(T) K`, `K` ordered | `List(T)` | by the key's natural order reversed, so a NaN key comes first; stable, so elements whose keys order level keep their order; the key is computed once per element |
| `List(T)`, `T` ordered | `min`, `max` | | `Option(T)` | the first least or greatest element |
| none: called by bare name, `min_of(a, b)` | `min_of`, `max_of` | `a: T`, `b: T`, `T` ordered | `T` | the lesser or the greater of the two in natural order; `a` when they order level |
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
| any integer | `ms`, `seconds`, `minute`, `days` | | `Duration` | a duration of that many; any other name after an integer (`1.second`) is `MO0208` when the program is checked, naming these. Step 28: `seconds`, after program 2 wrote `10_000.ms` |
| `Time` (on type) | `fixture` | | `Time` | 2026-01-01T00:00:00Z; tests only |

`Time - Time` is a `Duration`, `Time ± Duration` a `Time`, and both compare with `<`.

In a test, `Clock.fixture()`'s `now` is `Time.fixture()` moved by the simulator's time, which a fixture call that waits and a delayed send the simulator reaches both move, and inside an `update` it stays where it was when the update began (step 28, after program 1 could not watch a lease run out in a test).

`Deadline` is a point on the runtime's clock that a call may wait until: under `mo run` the process clock, and under `Mo.Sim` the run's own, which fixture waits move. Every `within:` takes a `Duration` or a `Deadline`; a `Deadline` gives the call what remains of it, and a call with nothing left is `Timeout` at once and is not made. Inside the `update` arm for a message that carries a reply, `reply_by` is the asker's `Deadline` (chapter 3); nothing else makes one outside a test, and nothing makes one later than the one it came from.

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| `Deadline` | `at_most` | `Duration` | `Deadline` | the earlier of the deadline and now plus the duration: a nested call may tighten its asker's deadline and never extend it |
| `Deadline` | `remaining` | | `Duration` | what remains of the deadline on the runtime's clock, zero once it has passed, so a reply that came after its call's deadline can be told from one in time. Session 5, step 24, after program 5 wrote `by.at_most(0.ms) == by` to ask it |
| `Deadline` (on type) | `fixture` | `Duration` | `Deadline` | now plus the duration on the test's clock, for a function that takes a deadline; tests only, since a test has no asker |

Session 5, step 22: `Deadline`, `reply_by`, `at_most`, and `fixture`, after program 1 derived three deadlines by hand as sums of literals and two of the sums were wrong.

## Files

Every `Fs` row can wait, so it takes `within: Duration`. A name is relative to the scope the `Fs` was narrowed to (`fs.scoped("logs").read_only`), and nothing outside the scope is reachable; a path that leaves it, or anything that is not a readable file, is `Missing(path)` with the path as the program wrote it. A `String` is UTF-8, so a row that gives one gives only text: a file whose bytes are not UTF-8 is `NotText`, and `read_bytes` gives any file's bytes.

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| `Fs` | `read` | `path: String` | `Result(String, FsError)` | the whole file; `NotText` when it is not UTF-8 |
| `Fs` | `read_lines` | `path: String` | `Result(List(String), FsError)` | the file split as `String.lines` splits it; `NotText` when it is not UTF-8 |
| `Fs` | `read_bytes` | `path: String` | `Result(List(UInt8), FsError)` | the whole file's bytes, UTF-8 or not, for a program that wants the bytes; `Missing` and `Timeout` as `read` answers them, and on an `Fs.fixture()` the bytes of the text written |
| `Fs` | `fold_lines` | `path: String`, `init: A`, `fn(A, String) A` | `Result(A, FsError)` | the file's lines, split as `String.lines` splits it, each handed to the function in turn with the value so far, `init` with the first, as the file is read, so no more of the file than its longest line and the value is held; the function gives the value handed with the next line, and `Ok` holds what the last line's call gave, or `init` for a file with no lines. `Missing(path)` before any line when the file cannot be read or has a line of more than 64 MiB. A line that is not UTF-8 is handed on with each byte that begins no UTF-8 character replaced by U+FFFD, so a caller counts it, as `line.contains?("\u{FFFD}")`, and folds on; the call is never `NotText` (session 6, step 27). The deadline is checked before each read of the file: past it the call is `Timeout`, and the calls already made stay made. Written `logs.fold_lines(name, 0, within: 1.minute, fn(count, line) count + 1 end)` |
| `Fs` | `size` | `path: String` | `Result(UInt64, FsError)` | the file's length in bytes |
| `Fs` | `list` | | `Result(List(String), FsError)` | the names of the files and folders directly inside the scope, sorted byte by byte; `Missing(".")` when the scope is not a readable folder |
| `Fs` | `list_kinds` | | `Result(List(Entry), FsError)` | what `list` gives, each name an `Entry(name: String, kind: EntryKind)` whose kind is `File` or `Folder`, a link counting as what it points at. Step 28, after program 2 could not tell a folder named `old.log` from a log |
| `Fs` | `scoped` | `String` | `Fs` | narrowed to a folder inside this scope |
| `Fs` | `read_only` | | `Fs` | narrowed to reading: a read-only `Fs`, its own type, which goes wherever an `Fs` goes (a `scoped` of it is read-only too) and is refused by the checker (`MO0404`) where a write reaches it, directly or through a function it is handed to |
| `Fs` (on type) | `fixture` | | `Fs` | an empty file system: every read is `Missing`; `list` on the fixture's root is `Ok([])`, and on a folder that is not there (no `mkdir` made it and no file is under it) `Missing(".")`, as the real `Fs` answers; a path whose `..` climbs above a scope's folder, the fixture's root included, is refused as the real `Fs` refuses it, `Missing(path)`, and `list` on a scope that climbed out is `Missing(".")`; tests only. Session 5, step 21: the refusal, after round 4's logstat found the fixture climbing out of a scope where the real `Fs` does not. Session 5, step 22: `Missing(".")` for a folder that is not there, after program 1 found no test could show `jobq serve` refusing one |
| `Fs` (on type) | `fixture` | `delay: Duration` | `Fs` | every call that waits less than `delay` is `Timeout`; tests only |
| `Fs` | `write` | `path: String`, `text: String` | `Result(none, FsError)` | the file holds exactly the text, created when it is not there, and is on disk (`fsync`) before `Ok`; `Missing(path)` for a path outside the scope, a folder that is not there, or anything that is not a file. On an `Fs.fixture()` the files are in memory and every read sees what was written; a call that fails changes nothing. A read-only `Fs` handed to a process as a start argument, in a message field, or on a supervisor's `child` line is followed there too (Session 5, step 24): a write through it is refused by `mo check`.start`) is not followed, and a write through it there crashes |
| `Fs` | `append` | `path: String`, `text: String` | `Result(none, FsError)` | the text added at the end of the file, created when it is not there; durable (`fsync`) before it returns `Ok`; a call past its deadline is `Timeout`, and what it wrote stays |
| `Fs` | `remove` | `path: String` | `Result(none, FsError)` | the file is gone; `Missing(path)` when no such file is in the scope |
| `Fs` | `rename` | `from: String`, `to: String` | `Result(none, FsError)` | the file at `from` is at `to`, replacing a file there; `Missing(from)` when no such file is in the scope, `Missing(to)` when `to` is outside it or in a folder that is not there |
| `Fs` | `mkdir` | `path: String` | `Result(none, FsError)` | a folder at the path, made when it is not there, in a folder that is; `Ok` when a folder is there already; `Missing(path)` for a path outside the scope, a folder that is not there, or a file at the path. The folder is not synced: a write into it syncs the file, not the folder. On an `Fs.fixture()` a folder is there once `mkdir` made it or a file is under it, and `list` names it |

Session 5, step 19: `mkdir`, after program 4 found no row that makes a folder, so `notes check` could not copy a fixture folder somewhere to write.

Session 5, step 19: `each_line` is gone. Its function could reach no capability once step 18 refused capturing one in an anonymous function, so all it could do was compute and drop a value; `fold_lines` is the row that streams a file.

## Output

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| `Out` | `write` | `String` | none | the text, as it is |
| `Out` | `write_line` | `String` | none | the text, then `"\n"` |
| `Out` | `flush` | | none | what was written goes out now, not when `main` returns |
| `Out` (on type) | `fixture` | | `Out` | an `Out` that keeps what is written to it; tests only |
| `Out` | `written` | | `List(String)` | what a fixture `Out` was given, one string per `write` or `write_line` (a line with its `"\n"`); tests only |

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
| `Json` | `to_i64` | | `Option(Int64)` | `Some(n)` when the value is a `Number` holding a whole number below 2^53 either side of 0, where every whole number is a float of its own and reads back as its text spelled it; `None` for a fraction, a number from 2^53 out, or anything that is not a `Number`. Session 5, step 22: after program 1 read every count through `to_string(0).to_u64` |

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

A function, a capability, or a handle has no JSON; encoding one is a crash. `decode` reads every number as a `Float64`, and `to_i64` gives the whole ones back; an object with a repeated key keeps the last value in the first key's place; nesting deeper than 512 is `Syntax`.

## Not in this step

Map and set literals; Unicode case mapping (`to_upper` is ASCII); full grapheme segmentation (a grapheme is a code point with the combining marks after it, as `size` counts); a float-to-integer conversion beyond `Json`'s `to_i64`; streaming reads; writing files. Each waits for a program that needs it.

## Net

`Net` is TCP, `platform.net` in `main` (step 11). A `Listener` and a `Conn` are capabilities too: a `Net` call gives them, they travel as parameters (a listening process hands each connection to a worker with `Worker.start(conn)`) and in a message whose `message` line declares them, where they move (chapter 3, processes), and a `Conn` closes when the process holding it as a start argument stops, restarted or not. Every row that can wait takes `within: Duration`; a call past its deadline is `Timeout`, and leaves the listener or the connection as its row says. A process waiting in a call does not hold up the others: they keep taking messages.

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
| `Listener` | `serve` | `into: Handle(P)`, `idle: Duration` | none | from this call on, the runtime accepts on the listener and sends `P` `Accepted(conn: Conn)` per connection, and `Idle` each time no connection came for `idle`, serving on; `P` declares both (MO0223); an `accept` on the listener is `Busy`, and serving it again is a crash |
| `Conn` | `lines` | `into: Handle(P)`, `idle: Duration` | none | from this call on, the runtime reads the connection and sends `P` `Line(text: String)` per line as `read_line` cuts it, `LineTooLong` for a line over 64 KiB (the next starts after it), `Closed` at the end of the stream, and `Idle` when no line came for `idle`, after which it closes the connection; `P` declares all four (MO0223); once this side closes the connection it is read no more, with no message; a `read_line` on it is `Busy`, and reading it into a process again is a crash |
| `Net` (on type) | `fixture` | | `Net` | a network in memory, shared by every fixture in the test; tests only |

**The runtime owns the loop.** A process never waits in a `for` around `accept` or `read_line`: `serve` and `lines` hand the waiting to the runtime, which delivers each result as a message and is itself the loop (as Erlang's active sockets are). Neither row waits, so neither takes `within:`; `idle:` is the deadline of the runtime's wait. A row's messages come from the runtime and take no reply. Backpressure: the runtime delivers while the target's mailbox holds fewer than its bound less a headroom of 4 waiting messages (half the bound, for a bound under 8), counting the requests an `HttpListener.serve` is still reading; at that it stops accepting or reading, so clients wait in the kernel's queues, and it starts again once the mailbox has drained to half its bound; while it waits for room, idle time does not run. A served listener keeps a program running after `main` returns, so a server stops when it is stopped; a `main` that calls `platform.exit` stops the runtime's loops when it returns, and the rest settles as before. A process a source sends to is never ended while the source can send (chapter 3, processes). Session 5, step 20: `serve` and `lines`, after three servers wrote `for _ in 0..10_000` twice around `accept` to satisfy the no-`while` law with a bound nobody chose.

A `Net.fixture()` lets a test start a server process, connect a client, and drive the protocol with no real socket. What one end writes waits for the other end to read it, and a closed end is the end of the stream for the other. `listen(0)` picks a port from 49152 up; `connect` to a port nothing listens on is `Refused`; the host is not looked at. A simulated call cannot wait for something to happen, so a call with nothing to take (an `accept` with no client, a `read_line` with no whole line) waits its whole deadline and is `Timeout`. Under `mo test --sim`, a fixture call that can wait times out by the seed, and a `read_line` or `write` finds its connection `Closed` by the seed; each leaves the connection as the real call would. A fixture's `serve` and `lines` deliver at the start of each round of deliveries, one message per source, in start order or the seed's, so a test's settle, an `ask` that delivers rounds, and `Http.fixture()`'s `send` all see them; nothing happens while a simulated call waits, so a source with nothing to take waits, and `Idle` comes only once fixture calls have waited past its deadline. Under `--faults`, a source about to deliver finds its connection `Closed`, or waits out its deadline and sends `Idle`, by the seed.

## Http

`Http` is HTTP/1.1 over TCP, `platform.http` in `main` (step 16): a server accepts exchanges and a client sends requests, with no new syntax. No TLS, and one request per connection: every request and response the runtime writes says `connection: close`, and the connection closes once the response is written or read. An `HttpListener` and an `Exchange` are capabilities, as a `Listener` and a `Conn` are: an `Http` call gives them, they travel as parameters (an acceptor hands each exchange to a worker with `Worker.start(exchange)`) and in a message whose `message` line declares them, and an `Exchange` closes when the process holding it as a start argument stops, restarted or not. Every row that can wait takes `within: Duration`; a call past its deadline is `Timeout`, and leaves the listener or the exchange as its row says. A process waiting in a call does not hold up the others.

```ruby
struct Request
  method: String
  path: String
  query: Map(String, String)
  headers: Map(String, String)
  body: String
end

struct Response
  status: UInt16
  headers: Map(String, String)
  body: String
end

enum HttpError
  Timeout
  Refused
  Closed
  Busy
  Malformed
  TooLarge
  Unsupported
end
```

`Request` and `Response` are prelude structs. Building one needs only what the caller has: a `Response` its `status` and `body`, a `Request` its `method` and `path`; a field left out (`headers`, `query`, a request's `body`) is empty. A module that declares its own `Request` or `Response` means its own by the name, and the `Http` rows still take and give the prelude's.

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| `Http` | `listen` | `port: UInt16` | `Result(HttpListener, HttpError)` | as `Net.listen`: 127.0.0.1 at `port`, or at a free port the system picks when `port` is 0; `Busy` when another listener holds the port, `Refused` when the system will not bind it; binding does not wait |
| `HttpListener` | `accept` | | `Result(Exchange, HttpError)` | the next client and its whole request, both within the deadline; `Timeout` when no client or no whole request arrives in time, and a client that came closes; `Malformed`, `TooLarge`, or `Unsupported` when what came is not a request this row reads, after the client is answered `400`, `413`, or `501` and closed; `Closed` when the client's stream ends first; `Busy` when another `accept` is already waiting on it; each leaves the listener listening |
| `HttpListener` | `port` | | `UInt16` | the port it listens on |
| `HttpListener` | `serve` | `into: Handle(P)`, `idle: Duration` | none | from this call on, the runtime accepts on the listener, reads each client's request on its own, and sends `P` `Accepted(exchange: Exchange)` per whole request, and `Idle` each time no client came for `idle`; a request not whole within `idle` of its connection is closed, and one that is not a request this row reads is answered `400`, `413`, or `501` and closed, each with no message; `P` declares both (MO0223); an `accept` on the listener is `Busy`, and serving it again is a crash. Session 5, step 20 |
| `Exchange` | `request` | | `Request` | the request it holds; reading it after the exchange is answered is a crash |
| `Exchange` | `reply` | `Response` | `Result(none, HttpError)` | the response, written whole, then the connection closes; `Malformed` for a status outside 100 to 599 or a header that is not one, which writes nothing and leaves the exchange unanswered; `Closed` when the client is gone or the exchange is answered already; `Timeout` closes the connection; `Busy` when another `reply` is waiting on it |
| `Http` | `send` | `Request`, `host: String`, `port: UInt16` | `Result(Response, HttpError)` | connects to an IP address or a host name, writes the request, and reads the whole response, all within the deadline; the connection closes either way; `Refused` when nothing listens there or the host is not found; `Malformed` for a request that is not one, before connecting, or a response that is not HTTP; `Closed` when the stream ends before the whole response; `TooLarge` and `Unsupported` as `accept` reads them |
| `Http` (on type) | `fixture` | | `Http` | HTTP on `Net.fixture()`'s network; tests only |

The wire, read and written the same way by both runtimes:

- **Reading.** A request line is `METHOD /target HTTP/1.1` (`HTTP/1.0` is read too; another version is `Unsupported`), a status line `HTTP/1.1 200 reason`. Each line ends in `"\n"`, with one `"\r"` before it or none, and the headers end at an empty line. A request line of more than 1 MiB, header lines of more than 1 MiB together, or a body of more than 1 MiB is `TooLarge`, the body as soon as its `content-length` says so. The body is `content-length` bytes; a request with none has an empty body, and a response with none runs to the end of the stream. A `transfer-encoding` header (chunked) is `Unsupported`. A method or header name that is not a token, a target that does not begin with `/`, a header line with no `:`, a header value with a control character, two `content-length` headers that differ, and a query `%` not followed by two hex digits are `Malformed`.
- **A request's fields.** `path` is the target before its first `?`, as it came. `query` is the target after it, split at `&` into `key=value` pairs, each decoded with `+` as a space and `%XX` as its byte; a pair with no `=` has the value `""`, an empty pair is skipped, and a repeated key keeps its last value in its first key's place. `headers` holds each header by its name lower-cased, its value without the spaces and tabs around it; a repeated header's values are joined with `", "` in the first one's place. A response's `headers` are read the same way. Every string holds the bytes as they came, as `Conn.read_line` gives them.
- **Writing.** A response is `HTTP/1.1 <status> <reason>` (the reason phrase for a common status, none for another), the response's headers as `name: value` in map order, then `content-length` and `connection: close`, then the body. A request is `METHOD <path> HTTP/1.1`, its query's keys and values percent-encoded (every byte but letters, digits, and `-._~`) after a `?`, or after an `&` when the path holds a `?`; then `host: <host>:<port>` unless the request has a `host` header, its headers, `content-length`, `connection: close`, and the body. A `content-length` or `connection` header the program gives is not written; the runtime's are. A method that is not a token, a path that does not begin with `/` or holds a space or control character, or a header whose name is not a token or whose value holds a control character is `Malformed`.

`accept` reads the whole request before it gives the exchange, so a listener waits on one slow client at a time: a server that must not keep the others waiting passes each client a short deadline, or serves the listener, which reads each request apart. The body is read by its count from the connection's buffer, so `Conn` gains no row.

An `Http.fixture()` runs on the network `Net.fixture()` does, so a test can connect with a `Net` fixture to an `HttpListener` and write a request by hand. As on `Net`, a call with nothing to take (an `accept` with no client, or with a request cut short) waits its whole deadline and is `Timeout`. `send` alone does not wait for nothing: while its response is not whole it delivers the processes' waiting messages a round at a time, as a settle does, and it is `Timeout` when no message is waiting. So a test that sends a server process a message to accept, or serves a listener into it, then sends a request in the same statement, gets the server's response. Under `mo test --sim`, `accept` and `send` time out by the seed, and `reply` and `send` find their connection `Closed` by the seed.

## Runtime

`Runtime` is the runtime surface (design-v0/03, the runtime surface; directions 37 and 40): what a running program's processes are doing, as rows a program, an agent, or an operator calls. It is a capability like `Fs`: `platform.runtime` is `Some` under `mo run`, `None` in a binary unless it was built with `mo build --surface`, and a test holds its own run's through `Runtime.fixture()`. `main` passes it down as it passes an `Fs`, narrowed by `read_only` for a process that may look but not act. A read is a snapshot taken between two updates, never inside one: every update runs on one thread, so a row sees no transaction half done, and a process whose update waits in a call is read once that update ends, within the row's deadline. Every row but `read_only` takes `within:`. `send`, `pause`, and `resume` act, each act is an event, and a read-only `Runtime` refuses them with `ReadOnly`. `Json.encode` of each struct and event is the surface's wire form.

The runtime keeps a bounded ring of events, 4,096 by default (`mo run --events N`, `MO_EVENTS=N` for a binary): each update with its duration, its time in calls that wait, and the call it waited longest in; each start, end, restart, and crash with its report's seed, clause, message, and state; a sender that found a mailbox full; a call past its deadline; a loop the runtime owns pausing or resuming at its target's bound; and each act of the surface. An event's `at` is the runtime's monotonic clock as a `Time`: under `mo run` pinned to the wall clock when the run began, and in a test the run's own clock, so a seed's events are the same every run. `took_us` and `waited_us` are microseconds. A seeded test that fails prints its last ten events after the interleaving.

```ruby
struct ProcessInfo
  id: UInt64
  name: String
  alive: Bool
  mailbox: UInt64
  bound: UInt64
  waiting_in: Option(String)
  restarts: UInt64
  region_bytes: UInt64
  paused: Bool
end

struct SourceInfo
  kind: String
  target: UInt64
  name: String
  in_flight: UInt64
  paused: Bool
end

struct MemoryInfo
  resident_bytes: UInt64
  region_bytes: UInt64
  packed_bytes: UInt64
  event_bytes: UInt64
  largest: List(ProcessInfo)
end

enum RuntimeError
  NoProcess
  Unparsed(why: String)
  ReadOnly
  MailboxFull
  Timeout
end

enum Event
  Updated(at: Time, pid: UInt64, name: String, taking: String, took_us: UInt64, waited_us: UInt64, longest: String)
  Started(at: Time, pid: UInt64, name: String)
  Ended(at: Time, pid: UInt64, name: String)
  Restarted(at: Time, pid: UInt64, name: String, restarts: UInt64)
  Crashed(at: Time, pid: UInt64, name: String, seed: UInt64, clause: String, taking: String, snapshot: String)
  Overflowed(at: Time, sender: Option(UInt64), sender_name: String, target: UInt64, name: String)
  TimedOut(at: Time, pid: Option(UInt64), name: String, call: String)
  SourcePaused(at: Time, source: String, target: UInt64, name: String, in_flight: UInt64)
  SourceResumed(at: Time, source: String, target: UInt64, name: String, in_flight: UInt64)
  Sent(at: Time, pid: UInt64, name: String, taking: String)
  Paused(at: Time, pid: UInt64, name: String)
  Resumed(at: Time, pid: UInt64, name: String)
end
```

`pid` is the process's id and `name` its name when the event happened, since a process that ended gives its id to one started later; `taking` is the message an update took, a crash's last message, or the message the surface sent, and `snapshot` a crashed process's state (Session 5, step 24: the fields were `process`, `message`, and `state`, which are keywords, so no pattern could name them); `Overflowed` and `TimedOut` name `main` or the test when no process sent or waited. The structs, `Event`, and `RuntimeError` are prelude types, and a module that declares its own `Event` or `RuntimeError` (or `ProcessInfo`, `SourceInfo`, `MemoryInfo`) means its own by the name, as with `Request`, while the `Runtime` rows still give the prelude's.

| receiver | name | parameters | returns | |
|---|---|---|---|---|
| `Platform` | `runtime` | | `Option(Runtime)` | `Some` under `mo run` and in a binary built with `mo build --surface`; `None` in any other binary |
| `Runtime` | `processes` | | `List(ProcessInfo)` | every process that has not ended, by id: its name, whether it is up, its mailbox's depth and bound, the call its update waits in (`ask`, `Fs.append`, `Conn.read_line`) or `None`, its restarts since it started, the bytes its region holds, and whether the surface holds its deliveries |
| `Runtime` | `state` | `id: UInt64` | `Result(String, RuntimeError)` | the process's state as a crash report prints it, as its last update left it; `NoProcess` for an id no process that has not ended has; `Timeout` when its update in progress does not end within the deadline, or when the caller is that update |
| `Runtime` | `recent` | `id: UInt64`, `n: UInt64` | `List(Event)` | the last `n` events the ring holds about that id, oldest first |
| `Runtime` | `events` | `since: Time`, `n: UInt64` | `List(Event)` | the first `n` events the ring holds at or after `since`, oldest first, so the last one's `at` pages on |
| `Runtime` | `crashes` | `n: UInt64` | `List(Event)` | the last `n` `Crashed` events, oldest first |
| `Runtime` | `sources` | | `List(SourceInfo)` | each loop the runtime owns (`Listener.serve`, `Conn.lines`, `HttpListener.serve`) that has not ended: its row, its target, the requests it is reading, and whether it is paused at the target's bound |
| `Runtime` | `memory` | | `MemoryInfo` | the program's resident bytes now, the bytes main's and every process's regions hold, the bytes packed into messages since the run began, the bytes the ring holds, and the five processes whose regions hold the most |
| `Runtime` | `slowest` | `n: UInt64` | `List(Event)` | the `n` longest `Updated` events the ring holds, longest first |
| `Runtime` | `send` | `id: UInt64`, `text: String` | `Result(none, RuntimeError)` | the message the text spells as a report prints it (`Vote(n: 3)`, `Total`; a message of one field may leave its name out), put in the process's mailbox now, not when the calling update commits, and recorded as `Sent`; a reply it carries is dropped; `Unparsed(why)` for text that is not a message the process declares, or that holds a map, a set, a capability, or a handle; `MailboxFull` at its bound, which crashes no one; `NoProcess`; `ReadOnly` |
| `Runtime` | `pause`, `resume` | `id: UInt64` | `Result(none, RuntimeError)` | holds the process's deliveries, or lets them go: its messages wait, an `ask` to it is `Timeout` at its deadline (at once in a test, and the message still arrives), and a loop the runtime owns into it pauses at its bound; each is an event; `NoProcess`; `ReadOnly` |
| `Runtime` | `read_only` | | `Runtime` | narrowed to reading: `send`, `pause`, and `resume` are `ReadOnly`, at run time |
| `Runtime` (on type) | `fixture` | | `Runtime` | the surface of the test's own run: the processes it started and the events they made; tests only |

Over HTTP the same rows are the development on-ramp: `mo run --surface PORT`, and `MO_SURFACE=PORT` for a binary built with `--surface`, serve them as JSON on 127.0.0.1 from a process of the toolchain's own the surface does not list, `GET /processes`, `/state/<id>`, `/recent/<id>?n=`, `/events?since=<ISO-8601>&n=`, `/crashes?n=`, `/sources`, `/memory`, `/slowest?n=`, and `POST /send/<id>` with the message's text as the body, `/pause/<id>`, `/resume/<id>`; a refusal is 404 for no process, 403 for read only, and 409 otherwise, with the `RuntimeError` as the body. An MCP wrapper is a later step.

Session 5, step 23: the runtime surface and the events, from Robert's call of 13 Sep night (the surface is a capability, on in development, off in a binary unless held) and the nine questions program 1's worker wanted to ask its service.

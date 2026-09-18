# The prelude

Every stdlib type, variant, function, and operator a Mo module may use without declaring it. The same rows live as data in `src/prelude.zig`; the checker reads nothing else. **Nothing outside these tables exists.** A row marked *stdlib (09)* is named by `mo-wiki/spec/design-v0/09-stdlib.md`, which says what each one does; `src/stdlib.zig` runs it. A row marked *corpus-only* is not named by `mo-wiki/spec/grammar.md` or design-v0: a corpus file needs it, and `examples/GAPS.md` records it until the stdlib chapter settles it.

Type strings: `T`, `U`, `A`, `E`, `K`, `V` are type variables fresh at each call (*ordered* means the checker requires the natural order of design-v0/09: numbers, strings, times, durations, and tuples of those); `N` is the receiver's own integer type; `P` is the process a handle or message belongs to; `Message(P)` is one of P's `message` lines; `Reply` is the reply type of the message passed; `none` is no value (the call is a statement).

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
| `Deadline` | | a point on the runtime's clock a call may wait until: `reply_by`, and what `at_most` gives; `within:` takes one as it takes a `Duration` | stdlib (09), Session 5, step 22 |
| `List` | `T` | list | grammar |
| `Option` | `T` | `Some(T)` or `None` | grammar |
| `Result` | `T`, `E` | `Ok(T)` or `Error(E)` | grammar |
| `Map` | `K`, `V` | map, keys in the order first added | stdlib (09) |
| `Set` | `T` | set, elements in the order first added | stdlib (09) |
| `(A, B, ...)` | two or more | tuple | grammar |
| `Handle` | a process name | a started process | grammar |
| `Clock` | | capability | grammar |
| `Fs` | | capability | grammar |
| `Events` | | capability | grammar |
| `Ledger` | | capability | grammar |
| `Platform` | | capability: `fn main`'s one parameter, and nowhere else | grammar (Q18) |
| `Env` | | capability: the process's environment variables | grammar (Q18) |
| `Out` | | capability: a standard stream, `stdout` or `stderr` | grammar (Q18) |
| `Net` | | capability: TCP, `platform.net` | stdlib (09) |
| `Listener` | | capability: a listening TCP port | stdlib (09) |
| `Conn` | | capability: a TCP connection | stdlib (09) |
| `Http` | | capability: HTTP/1.1, `platform.http` | stdlib (09) |
| `HttpListener` | | capability: a port that accepts HTTP exchanges | stdlib (09) |
| `Exchange` | | capability: one HTTP request and its one response | stdlib (09) |
| `Request`, `Response` | | struct (`## Http`) | stdlib (09) |
| `FsError` | | error enum | grammar (name); `Missing` and `Timeout` corpus-only, `NotText` stdlib (09) |
| `AskError` | | error enum | grammar |
| `LedgerError` | | error enum | corpus-only |
| `Json` | | enum: a JSON value | stdlib (09) |
| `JsonError` | | error enum | stdlib (09) |
| `NetError` | | error enum | stdlib (09) |
| `HttpError` | | error enum | stdlib (09) |
| `Runtime` | | capability: the runtime surface, `platform.runtime` | stdlib (09), Session 5, step 23 |
| `ProcessInfo`, `SourceInfo`, `MemoryInfo` | | struct (`## Runtime`) | stdlib (09), Session 5, step 23 |
| `Entry` | `name: String`, `kind: EntryKind` | struct: what `Fs.list_kinds` gives | stdlib (09), step 28 |
| `EntryKind` | `File`, `Folder` | enum | stdlib (09), step 28 |
| `RuntimeError` | | error enum | stdlib (09), Session 5, step 23 |
| `Event` | | enum: one of the runtime's events | stdlib (09), Session 5, step 23 |
| `Hash`, `AesGcm`, `ChaCha`, `X25519`, `Ed25519`, `Password` | | rows only: the crypto brick's, called on the name, with no values of their own, so none is a type a signature can name (MO0202) | stdlib (09), step 35 |
| `Random` | | capability: bytes from the OS CSPRNG, `platform.random`; `Random.fixture()` in a test | stdlib (09), step 35 |
| `Tls` | | capability: the TLS brick, both sides, `platform.tls`; `Tls.fixture()` in a test | stdlib (09), steps 36 and 37 |
| `TlsServer` | | capability: a certificate chain and its key, and its ALPN list; no authority beyond them, so a program hands one to every worker | stdlib (09), step 36 |
| `TlsClient` | | capability: the root certificates a client trusts, and its ALPN list; no authority beyond them, so it may be stored and shared | stdlib (09), step 37 |
| `TlsError` | | error enum: `BadPem`, `Handshake`, `Timeout`, `Closed`, `Untrusted` | stdlib (09), steps 36 and 37 |

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
| `FsError` | `NotText` | | stdlib (09) |
| `AskError` | `Timeout` | | grammar |
| `AskError` | `Down` | | grammar |
| `LedgerError` | `Timeout` | | corpus-only |
| `Json` | `Object` | `fields: Map(String, Json)` | stdlib (09) |
| `Json` | `Array` | `items: List(Json)` | stdlib (09) |
| `Json` | `String` | `text: String` | stdlib (09) |
| `Json` | `Number` | `value: Float64` | stdlib (09) |
| `Json` | `Bool` | `value: Bool` | stdlib (09) |
| `Json` | `Null` | | stdlib (09) |
| `JsonError` | `Syntax` | `at: UInt64` | stdlib (09) |
| `NetError` | `Timeout` | | stdlib (09) |
| `NetError` | `Refused` | | stdlib (09) |
| `NetError` | `Closed` | | stdlib (09) |
| `NetError` | `LineTooLong` | | stdlib (09) |
| `NetError` | `Busy` | | stdlib (09) |
| `HttpError` | `Timeout` | | stdlib (09) |
| `HttpError` | `Refused` | | stdlib (09) |
| `HttpError` | `Closed` | | stdlib (09) |
| `HttpError` | `Busy` | | stdlib (09) |
| `HttpError` | `Malformed` | | stdlib (09) |
| `HttpError` | `TooLarge` | | stdlib (09) |
| `HttpError` | `Unsupported` | | stdlib (09) |
| `TlsError` | `BadPem` | | stdlib (09), step 36 |
| `TlsError` | `Handshake` | | stdlib (09), step 36 |
| `TlsError` | `Timeout` | | stdlib (09), step 36 |
| `TlsError` | `Closed` | | stdlib (09), step 36 |
| `TlsError` | `Untrusted` | | stdlib (09), step 37 |
| `RuntimeError` | `NoProcess` | | stdlib (09), Session 5, step 23 |
| `RuntimeError` | `Unparsed` | `why: String` | stdlib (09), Session 5, step 23 |
| `RuntimeError` | `ReadOnly` | | stdlib (09), Session 5, step 23 |
| `RuntimeError` | `MailboxFull` | | stdlib (09), Session 5, step 23 |
| `RuntimeError` | `Timeout` | | stdlib (09), Session 5, step 23 |
| `Event` | `Updated` | `at: Time`, `pid: UInt64`, `name: String`, `taking: String`, `took_us: UInt64`, `waited_us: UInt64`, `longest: String` | stdlib (09), Session 5, step 23; Session 5, step 24: `pid`, `taking`, `snapshot` |
| `Event` | `Started` | `at: Time`, `pid: UInt64`, `name: String`, `scheduler: UInt64` | stdlib (09), Session 5, step 23; Session 5, step 24: `pid`, `taking`, `snapshot`; Session 5, step 30: `scheduler` |
| `Event` | `Ended`, `Paused`, `Resumed` | `at: Time`, `pid: UInt64`, `name: String` | stdlib (09), Session 5, step 23; Session 5, step 24: `pid`, `taking`, `snapshot` |
| `Event` | `Restarted` | `at: Time`, `pid: UInt64`, `name: String`, `restarts: UInt64` | stdlib (09), Session 5, step 23; Session 5, step 24: `pid`, `taking`, `snapshot` |
| `Event` | `Crashed` | `at: Time`, `pid: UInt64`, `name: String`, `seed: UInt64`, `clause: String`, `taking: String`, `snapshot: String` | stdlib (09), Session 5, step 23; Session 5, step 24: `pid`, `taking`, `snapshot` |
| `Event` | `Overflowed` | `at: Time`, `sender: Option(UInt64)`, `sender_name: String`, `target: UInt64`, `name: String` | stdlib (09), Session 5, step 23 |
| `Event` | `TimedOut` | `at: Time`, `pid: Option(UInt64)`, `name: String`, `call: String` | stdlib (09), Session 5, step 23; Session 5, step 24: `pid`, `taking`, `snapshot` |
| `Event` | `SourcePaused`, `SourceResumed` | `at: Time`, `source: String`, `target: UInt64`, `name: String`, `in_flight: UInt64` | stdlib (09), Session 5, step 23 |
| `Event` | `Sent` | `at: Time`, `pid: UInt64`, `name: String`, `taking: String` | stdlib (09), Session 5, step 23; Session 5, step 24: `pid`, `taking`, `snapshot` |
| `Event` | `Dropped` | `at: Time`, `sender: Option(UInt64)`, `sender_name: String`, `target: UInt64`, `name: String`, `taking: String`, `why: String` | stdlib (09), Session 5, step 29 |

## Functions

Every function is called with a dot on its receiver (`xs.push(x)`), or on the type for rows marked *on type* (`Clock.fixture()`). *Waits* means the call can wait, so it takes `within: Duration` or `within: Deadline` and the checker rejects it without one (MO0401); a call that cannot wait rejects `within:` (MO0402). Inside the `update` arm for a message that carries a reply, `reply_by` is the asker's `Deadline` (Session 5, step 22).

| receiver | name | parameters | returns | waits | where | origin |
|---|---|---|---|---|---|---|
| `List(T)` | `size` | | `UInt64` | | | grammar |
| `List(T)` | `push` | `T` | `List(T)` | | | grammar |
| `List(T)` | `map` | `fn(T) U` | `List(U)` | | | grammar |
| `List(T)` | `filter` | `fn(T) Bool` | `List(T)` | | | grammar |
| `List(T)` | `reduce` | `A`, `fn(A, T) A` | `A` | | | grammar |
| `List(T)` | `contains?` | `T` | `Bool` | | | grammar |
| `Option(T)` | `map` | `fn(T) U` | `Option(U)`: `Some` of the function's value for a `Some`, `None` for a `None` | | | stdlib (09), step 28 |
| `List(T)` | `first` | | `Option(T)` | | | grammar |
| `List(T)` | `last` | | `Option(T)` | | | grammar |
| `List(T)` | `get` | `UInt64` | `Option(T)` | | | stdlib (09) |
| `List(T)` | `slice` | `UInt64`, `UInt64` | `List(T)` | | | stdlib (09) |
| `List(T)` | `take`, `drop` | `UInt64` | `List(T)` | | | stdlib (09) |
| `List(T)` | `concat` | `List(T)` | `List(T)` | | | stdlib (09) |
| `List(T)` | `reverse`, `unique` | | `List(T)` | | | stdlib (09) |
| `List(T)` | `flat_map` | `fn(T) List(U)` | `List(U)` | | | stdlib (09) |
| `List(T)` | `any?`, `all?` | `fn(T) Bool` | `Bool` | | | stdlib (09) |
| `List(T)` | `find` | `fn(T) Bool` | `Option(T)` | | | stdlib (09) |
| `List(T)` | `count` | `fn(T) Bool` | `UInt64` | | | stdlib (09) |
| `List(T)`, `T` ordered | `sort` | | `List(T)` | | | stdlib (09) |
| `List(T)` | `sort_by` | `fn(T) K`, `K` ordered | `List(T)` | | | stdlib (09) |
| `List(T)` | `sort_by_desc` | `fn(T) K`, `K` ordered | `List(T)` | | | stdlib (09) |
| `List(T)`, `T` ordered | `min`, `max` | | `Option(T)` | | | stdlib (09) |
| none | `min_of`, `max_of` | `T`, `T`, `T` ordered | `T` | | | stdlib (09) |
| `List(T)`, `T` an integer | `sum` | | `T` | | | stdlib (09) |
| `List(T)` | `zip` | `List(U)` | `List((T, U))` | | | stdlib (09) |
| `List(T)` | `enumerate` | | `List((UInt64, T))` | | | stdlib (09) |
| `List(T)` | `group_by` | `fn(T) K` | `Map(K, List(T))` | | | stdlib (09) |
| `Map` (on type) | `new` | | `Map(K, V)` | | | stdlib (09) |
| `Map(K, V)` | `size` | | `UInt64` | | | stdlib (09) |
| `Map(K, V)` | `get` | `K` | `Option(V)` | | | stdlib (09) |
| `Map(K, V)` | `has?` | `K` | `Bool` | | | stdlib (09) |
| `Map(K, V)` | `set` | `K`, `V` | `Map(K, V)` | | | stdlib (09) |
| `Map(K, V)` | `update` | `K`, `V`, `fn(V) V` | `Map(K, V)` | | | stdlib (09) |
| `Map(K, V)` | `remove` | `K` | `Map(K, V)` | | | stdlib (09) |
| `Map(K, V)` | `keys` | | `List(K)` | | | stdlib (09) |
| `Map(K, V)` | `values` | | `List(V)` | | | stdlib (09) |
| `Map(K, V)` | `entries` | | `List((K, V))` | | | stdlib (09) |
| `Set` (on type) | `new` | | `Set(T)` | | | stdlib (09) |
| `Set(T)` | `size` | | `UInt64` | | | stdlib (09) |
| `Set(T)` | `add`, `remove` | `T` | `Set(T)` | | | stdlib (09) |
| `Set(T)` | `has?` | `T` | `Bool` | | | stdlib (09) |
| `Set(T)` | `to_list` | | `List(T)` | | | stdlib (09) |
| `String` | `size` | | `UInt64` (graphemes) | | | grammar |
| `String` | `bytes` | | `List(UInt8)` | | | grammar |
| `String` | `byte_size` | | `UInt64` | | | stdlib (09) |
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
| `String` (on type) | `grouped` | any integer | `String`: the integer with `_` between each three digits from the right, `String.grouped(1204)` is `"1_204"`, `-1_234_567` for a negative one | | | stdlib (09), step 28 |
| any integer | `to_u8`, `to_u16`, `to_u32`, `to_u64`, `to_i64` | | that type | | | stdlib (09) |
| any integer | `checked_to_u8`, `checked_to_u16`, `checked_to_u32`, `checked_to_u64`, `checked_to_i64` | | `Option` of that type | | | stdlib (09) |
| any integer | `to_f64` | | `Float64` | | | stdlib (09) |
| `Float64` | `round` | `UInt64` | `Float64` | | | stdlib (09) |
| `Float64` | `to_string` | `UInt64` | `String` | | | stdlib (09) |
| any integer `N` | `checked_add`, `checked_sub`, `checked_mul` | `N` | `Option(N)` | | | grammar |
| any integer `N` | `saturating_add`, `saturating_sub`, `saturating_mul` | `N` | `N` | | | grammar |
| any integer `N` | `wrapping_add`, `wrapping_sub`, `wrapping_mul` | `N` | `N` | | | grammar |
| any integer | `ms`, `minute`, `days` | | `Duration` | | | grammar |
| any integer | `seconds` | | `Duration`; any other name after an integer is `MO0208` when checked, naming the units (step 28) | | | stdlib (09), step 28 |
| `Time` (on type) | `fixture` | | `Time` | | tests | grammar |
| `Time` (on type) | `parse` | `String` | `Option(Time)` | | | stdlib (09) |
| `Time` (on type) | `from_parts` | `UInt64` × 6 (year, month, day, hour, minute, second) | `Time` | | | stdlib (09) |
| `Time` | `to_iso8601` | | `String` | | | stdlib (09) |
| `Time` | `since` | `Time` | `Duration` | | | stdlib (09) |
| `Duration` | `ms` | | `Int64` | | | stdlib (09) |
| `Duration` | `seconds`, `minutes` | | `Float64` | | | stdlib (09) |
| `Hash` (on type) | `sha256`, `sha512` | `List(UInt8)` | `List(UInt8)`: 32 or 64 bytes | | | stdlib (09), step 35 |
| `Hash` (on type) | `hmac_sha256` | `List(UInt8)` (key), `List(UInt8)` | `List(UInt8)`: 32 bytes | | | stdlib (09), step 35 |
| `Hash` (on type) | `hkdf_sha256` | `List(UInt8)` (ikm), `List(UInt8)` (salt), `List(UInt8)` (info), `UInt64` (size) | `List(UInt8)`; a size past 8,160 crashes | | | stdlib (09), step 35 |
| `Hash` (on type) | `hex` | `List(UInt8)` | `String`, lowercase | | | stdlib (09), step 35 |
| `Hash` (on type) | `from_hex` | `String` | `Option(List(UInt8))` | | | stdlib (09), step 35 |
| `Hash` (on type) | `equal?` | `List(UInt8)`, `List(UInt8)` | `Bool`, in constant time | | | stdlib (09), step 35 |
| `AesGcm`, `ChaCha` (on type) | `seal` | `List(UInt8)` (key, 32), `List(UInt8)` (nonce, 12), `List(UInt8)` (plain), `List(UInt8)` (aad) | `List(UInt8)`: the ciphertext, then the 16-byte tag | | | stdlib (09), step 35 |
| `AesGcm`, `ChaCha` (on type) | `open` | key, nonce, `List(UInt8)` (sealed), aad | `Option(List(UInt8))` | | | stdlib (09), step 35 |
| `X25519` (on type) | `public` | `List(UInt8)` (secret, 32) | `List(UInt8)` | | | stdlib (09), step 35 |
| `X25519` (on type) | `shared` | `List(UInt8)` (secret, 32), `List(UInt8)` (public, 32) | `Option(List(UInt8))`: `None` for a low-order point | | | stdlib (09), step 35 |
| `Ed25519` (on type) | `public` | `List(UInt8)` (seed, 32) | `List(UInt8)` | | | stdlib (09), step 35 |
| `Ed25519` (on type) | `sign` | `List(UInt8)` (seed, 32), `List(UInt8)` | `List(UInt8)`: 64 bytes | | | stdlib (09), step 35 |
| `Ed25519` (on type) | `verify?` | `List(UInt8)` (public, 32), `List(UInt8)`, `List(UInt8)` (signature, 64) | `Bool` | | | stdlib (09), step 35 |
| `Password` (on type) | `hash` | `String`, `List(UInt8)` (salt, 16) | `String`: Argon2id, a PHC string | | | stdlib (09), step 35 |
| `Password` (on type) | `verify?` | `String`, `String` (PHC) | `Bool` | | | stdlib (09), step 35 |
| `Random` | `bytes` | `UInt64` | `List(UInt8)` | | | stdlib (09), step 35 |
| `Random` (on type) | `fixture` | | `Random`: the run's seeded stream | | tests | stdlib (09), step 35 |
| `Deadline` | `at_most` | `Duration` | `Deadline`: the earlier of the deadline and now plus the duration | | | stdlib (09), Session 5, step 22 |
| `Deadline` | `remaining` | | `Duration`: what remains of the deadline, zero once it has passed | | | stdlib (09), Session 5, step 24 |
| `Deadline` (on type) | `fixture` | `Duration` | `Deadline`: now plus the duration on the test's clock | | tests | stdlib (09), Session 5, step 22 |
| `Clock` | `now` | | `Time` | | | grammar |
| `Clock` (on type) | `fixture` | | `Clock`: its `now` is `Time.fixture()` moved by the simulator's time, every wait of a fixture call and every delayed send the simulator moves to (and under `--sim` its ticks), frozen inside an update as a real clock is (step 28) | | tests | grammar, step 28 |
| `Fs` | `read` | `String` | `Result(String, FsError)`, `NotText` for a file that is not UTF-8 | yes | | grammar |
| `Fs` | `read_lines` | `String` | `Result(List(String), FsError)`, `NotText` for a file that is not UTF-8 | yes | | stdlib (09) |
| `Fs` | `read_bytes` | `String` | `Result(List(UInt8), FsError)`: the file's bytes, UTF-8 or not | yes | | stdlib (09) |
| `Fs` | `fold_lines` | `String`, `A`, `fn(A, String) A` | `Result(A, FsError)`: each line handed to the function with the value so far as the file is read, `Ok` with the last call's; a line that is not UTF-8 handed on with U+FFFD for each byte that begins no UTF-8 character, so never `NotText` (session 6, step 27). Session 5, step 19: the streaming row, `each_line` gone | yes | | stdlib (09) |
| `Fs` | `size` | `String` | `Result(UInt64, FsError)` | yes | | stdlib (09) |
| `Fs` | `list` | | `Result(List(String), FsError)` | yes | | stdlib (09) |
| `Fs` | `list_kinds` | | `Result(List(Entry), FsError)`: the names `list` gives, in its order, each an `Entry` whose `kind` is `File` or `Folder`; a link counts as what it points at | yes | | stdlib (09), step 28 |
| `Fs` | `scoped` | `String` | `Fs` | | | grammar |
| `Fs` | `read_only` | | `Fs`, read-only: its own type, going wherever an `Fs` goes, refused by the checker where a write reaches it (`MO0404`) | | | grammar |
| `Fs` | `write` | `String`, `String` | `Result(none, FsError)` | yes | | stdlib (09) |
| `Fs` | `append` | `String`, `String` | `Result(none, FsError)` | yes | | stdlib (09) |
| `Fs` | `remove` | `String` | `Result(none, FsError)` | yes | | stdlib (09) |
| `Fs` | `rename` | `String`, `String` | `Result(none, FsError)` | yes | | stdlib (09) |
| `Fs` | `mkdir` | `String` | `Result(none, FsError)`: a folder made in a folder that is there; `Ok` when a folder is there already | yes | | stdlib (09), Session 5, step 19 |
| `Fs` (on type) | `fixture` | | `Fs`: a `..` that climbs above a scope's folder, the fixture's root included, is `Missing` as on the real `Fs`; `list` on a folder that is not there is `Missing(".")` as on the real `Fs` | | tests | grammar, Session 5, step 21; Session 5, step 22: `list` |
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
| `Platform` | `net` | | `Net` | | `main` | stdlib (09) |
| `Platform` | `http` | | `Http` | | `main` | stdlib (09) |
| `Platform` | `runtime` | | `Option(Runtime)`: `Some` under `mo run` and in a binary built with `--surface` | | `main` | stdlib (09), Session 5, step 23 |
| `Platform` | `random` | | `Random` | | `main` | stdlib (09), step 35 |
| `Platform` | `tls` | | `Tls` | | `main` | stdlib (09), step 36 |
| `Platform` | `exit` | `UInt8` | none | | `main` | grammar (Q18) |
| `Env` | `get` | `String` | `Option(String)` | | | grammar (Q18) |
| `Out` | `write` | `String` | none | | | grammar (Q18) |
| `Out` | `write_line` | `String` | none | | | stdlib (09) |
| `Out` | `flush` | | none | | | stdlib (09) |
| `Out` (on type) | `fixture` | | `Out` | | tests | stdlib (09) |
| `Out` | `written` | | `List(String)` | | tests | stdlib (09) |
| `Net` | `listen` | `UInt16` | `Result(Listener, NetError)` | yes | | stdlib (09) |
| `Net` | `connect` | `String`, `UInt16` | `Result(Conn, NetError)` | yes | | stdlib (09) |
| `Listener` | `accept` | | `Result(Conn, NetError)` | yes | | stdlib (09) |
| `Listener` | `port` | | `UInt16` | | | stdlib (09) |
| `Conn` | `read_line` | | `Result(Option(String), NetError)` | yes | | stdlib (09) |
| `Conn` | `write` | `String` | `Result(none, NetError)` | yes | | stdlib (09) |
| `Conn` | `close` | | none | | | stdlib (09) |
| `Listener` | `serve` | `into: Handle(P)`, `idle: Duration` | none: the runtime accepts from here on and sends `P` `Accepted(conn: Conn)` per connection and `Idle` after `idle` with none, which `P` declares (MO0223) | | | stdlib (09), Session 5, step 20 |
| `Conn` | `lines` | `into: Handle(P)`, `idle: Duration` | none: the runtime reads from here on and sends `P` `Line(text: String)`, `LineTooLong`, `Closed` at the end, and `Idle` after `idle` with no line, closing the connection; `P` declares all four (MO0223) | | | stdlib (09), Session 5, step 20 |
| `Net` (on type) | `fixture` | | `Net` | | tests | stdlib (09) |
| `Tls` | `server` | `cert: String`, `key: String` | `Result(TlsServer, TlsError)`: PEM text, chain leaf first and a PKCS#8 key (Ed25519 or P-256); `BadPem` when either does not parse or the key is not the leaf's | | | stdlib (09), step 36 |
| `TlsServer` | `accept` | `Conn` | `Result(Conn, TlsError)`: the server's half of the TLS 1.3 handshake, giving the same connection back with its bytes now records; the connection must have had no `read_line`, `write`, or `lines` on it | yes | | stdlib (09), step 36 |
| `Tls` (on type) | `fixture` | | `Tls`: the same rows on `Net.fixture()`'s network | | tests | stdlib (09), step 36 |
| `Tls` | `client` | `trust: String` | `Result(TlsClient, TlsError)`: PEM text holding one or more root certificates; `BadPem` when none parses | | | stdlib (09), step 37 |
| `TlsClient` | `connect` | `Conn`, `host: String` | `Result(Conn, TlsError)`: the client's half of the TLS 1.3 handshake on a connection from `Net.connect`, the leaf checked for `host` and the chain up to a trusted root at the runtime's clock; `Untrusted` when the chain is refused (its alert sent); the connection must have had no `read_line`, `write`, or `lines` on it | yes | | stdlib (09), step 37 |
| `TlsClient` | `offer` | `List(String)` | `TlsClient`: a new client offering these ALPN protocols in order, the old one unchanged; a name empty, past 255 bytes, or holding a NUL is a crash | | | stdlib (09), step 37 |
| `TlsServer` | `offer` | `List(String)` | `TlsServer`: a new server accepting these ALPN protocols in its order of preference, the old one unchanged; the same crash rule | | | stdlib (09), step 37 |
| `Conn` | `protocol` | | `Option(String)`: the ALPN protocol the handshake agreed; `None` on a plain `Conn` or when none was | | | stdlib (09), step 37 |
| `Http` | `listen` | `UInt16` | `Result(HttpListener, HttpError)` | yes | | stdlib (09) |
| `HttpListener` | `accept` | | `Result(Exchange, HttpError)` | yes | | stdlib (09) |
| `HttpListener` | `port` | | `UInt16` | | | stdlib (09) |
| `HttpListener` | `serve` | `into: Handle(P)`, `idle: Duration` | none: the runtime accepts and reads each request from here on and sends `P` `Accepted(exchange: Exchange)` per whole request and `Idle` after `idle` with no client, which `P` declares (MO0223) | | | stdlib (09), Session 5, step 20 |
| `Exchange` | `request` | | `Request` | | | stdlib (09) |
| `Exchange` | `reply` | `Response` | `Result(none, HttpError)` | yes | | stdlib (09) |
| `Http` | `send` | `Request`, `host: String`, `port: UInt16` | `Result(Response, HttpError)` | yes | | stdlib (09) |
| `Http` (on type) | `fixture` | | `Http` | | tests | stdlib (09) |
| `Runtime` | `processes` | | `List(ProcessInfo)` | yes | | stdlib (09), Session 5, step 23 |
| `Runtime` | `state` | `UInt64` | `Result(String, RuntimeError)` | yes | | stdlib (09), Session 5, step 23 |
| `Runtime` | `recent` | `UInt64`, `UInt64` | `List(Event)` | yes | | stdlib (09), Session 5, step 23 |
| `Runtime` | `events` | `since: Time`, `n: UInt64` | `List(Event)` | yes | | stdlib (09), Session 5, step 23 |
| `Runtime` | `crashes` | `UInt64` | `List(Event)` | yes | | stdlib (09), Session 5, step 23 |
| `Runtime` | `sources` | | `List(SourceInfo)` | yes | | stdlib (09), Session 5, step 23 |
| `Runtime` | `memory` | | `MemoryInfo` | yes | | stdlib (09), Session 5, step 23 |
| `Runtime` | `slowest` | `UInt64` | `List(Event)` | yes | | stdlib (09), Session 5, step 23 |
| `Runtime` | `send` | `UInt64`, `String` | `Result(none, RuntimeError)` | yes | | stdlib (09), Session 5, step 23 |
| `Runtime` | `pause`, `resume` | `UInt64` | `Result(none, RuntimeError)` | yes | | stdlib (09), Session 5, step 23 |
| `Runtime` | `read_only` | | `Runtime` | | | stdlib (09), Session 5, step 23 |
| `Runtime` (on type) | `fixture` | | `Runtime` | | tests | stdlib (09), Session 5, step 23 |
| `Json` (on type) | `encode` | `T` | `String` | | | stdlib (09) |
| `Json` (on type) | `decode` | `String` | `Result(Json, JsonError)` | | | stdlib (09) |
| `Json` | `to_i64` | | `Option(Int64)`: the whole number a `Number` holds below 2^53 either side of 0, else `None` | | | stdlib (09), Session 5, step 22 |
| `Charge` (on type) | `fixture` | `captured_amount: Money` | `Charge` | | tests | corpus-only |
| `Charge` (on type) | `fixture` | `captured_at: Time`, `captured_amount: Money` | `Charge` | | tests | corpus-only |
| `Charge` | `refunded?` | | `Bool` | | | corpus-only |
| `Money` (on type) | `cents` | `UInt64` | `Money` | | | corpus-only |
| `Money` (on type) | `zero` | | `Money` | | | corpus-only |
| a process `P` (on type) | `start` | the process's parameters | `Handle(P)` | | | grammar |
| a supervisor `S` (on type) | `start` | the supervisor's parameters | its one child's `Handle`, or a tuple of its children's handles in child-line order; none when it has no child | | | grammar (step 11) |
| `Handle(P)` | `send` | `Message(P)` | none | | | grammar |
| `Handle(P)` | `send` | `Message(P)`, `delay: Duration` | none: the message goes in the mailbox no earlier than `delay` after the sending update ends (from a test or `main`, after now); a crash drops it with the update's other sends, and a target that is down when it is due, or whose mailbox is full then, drops it | | | design-v0/03, Session 5, step 24 |
| `Handle(P)` | `ask` | `Message(P)` | `Result(Reply, AskError)` | yes | | grammar |
| any declared type `T` (on type) | `all` | | `List(T)` | | `never` | grammar |
| none | `flows` | a type, `into:` a capability | `Bool` | | `never` | grammar |

### The platform

`fn main(platform: Platform)` is the only place a `Platform` exists (grammar §2, Q18). Its parts read like fields (`platform.fs`, `platform.args`) and are passed down, narrowed (`platform.fs.scoped("data").read_only`); the `Platform` itself is never passed, bound, stored, or returned (MO0407), and no other function, process, or supervisor takes one. `mo test` never holds a Platform, so these rows run only under `mo run`, on Mo.Server.

## Http

The structs the `Http` rows take and give (design-v0/09, Http). A field marked *may be left out* is empty when a construction leaves it out: an empty map, or `""`. Unlike a stand-in, a stdlib struct exists whatever a module declares: a module's own `Request` or `Response` hides the prelude's name from that module only, and the rows still mean the prelude's.

| name | field | type | |
|---|---|---|---|
| `Request` | `method` | `String` | |
| `Request` | `path` | `String` | |
| `Request` | `query` | `Map(String, String)` | may be left out |
| `Request` | `headers` | `Map(String, String)` | may be left out |
| `Request` | `body` | `String` | may be left out |
| `Response` | `status` | `UInt16` | |
| `Response` | `headers` | `Map(String, String)` | may be left out |
| `Response` | `body` | `String` | |

## Runtime

The structs the `Runtime` rows give (design-v0/09, Runtime; Session 5, step 23). A test holds a `Runtime` through `Runtime.fixture()`, since `mo test` never holds a Platform.

| name | field | type | |
|---|---|---|---|
| `ProcessInfo` | `id`, `mailbox`, `bound`, `restarts`, `region_bytes`, `scheduler` | `UInt64` | Session 5, step 30: `scheduler` |
| `ProcessInfo` | `name` | `String` | |
| `ProcessInfo` | `alive`, `paused` | `Bool` | |
| `ProcessInfo` | `waiting_in` | `Option(String)` | |
| `SourceInfo` | `kind`, `name` | `String` | |
| `SourceInfo` | `target`, `in_flight` | `UInt64` | |
| `SourceInfo` | `paused` | `Bool` | |
| `MemoryInfo` | `resident_bytes`, `region_bytes`, `region_resident_bytes`, `packed_bytes`, `event_bytes` | `UInt64` | `region_resident_bytes`: the pages the regions keep resident, the scratch region's included, so resident memory less it is what the runtime holds outside the regions (step 28) |
| `MemoryInfo` | `largest` | `List(ProcessInfo)` | |

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

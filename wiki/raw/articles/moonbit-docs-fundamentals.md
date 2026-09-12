---
source_url: https://docs.moonbitlang.com/en/latest/language/fundamentals.html
ingested: 2026-09-12
sha256: fb4015a8b8268dc602708ea1dc57444fbe9bf061a2d4413777096596949f4f80
---
# Fundamentals

Skip to main content

Back to top

Ctrl+K

 MoonBit 月兔 

- Show source 
- Suggest edit 
- Open issue 
- .md 
- .pdf

# Fundamentals

## Contents

# Fundamentals#

## Built-in Data Structures#

### Unit#

`Unit` is a built-in type in MoonBit that represents the absence of a meaningful value. It has only one value, written as `()`. `Unit` is similar to `void` in languages like C/C++/Java, but unlike `void`, it is a real type and can be used anywhere a type is expected.

The `Unit` type is commonly used as the return type for functions that perform some action but do not produce a meaningful result:

fn print_hello() -> Unit {
println("Hello, world!")
}

Unlike some other languages, MoonBit treats `Unit` as a first-class type, allowing it to be used in generics, stored in data structures, and passed as function arguments.

### Boolean#

MoonBit has a built-in boolean type, which has two values: `true` and `false`. The boolean type is used in conditional expressions and control structures. Use `!` to negate a boolean value; `not(x)` is equivalent.

let a = true
let b = false
let c = a && b
let d = a || b
let e = !a
let f = !(a && b)

### Number#

MoonBit have integer type and floating point type:

| type | description | example |
| --- | --- | --- |
| Int16 | 16-bit signed integer | (42 : Int16) |
| Int | 32-bit signed integer | 42 |
| Int64 | 64-bit signed integer | 1000L |
| UInt16 | 16-bit unsigned integer | (14 : UInt16) |
| UInt | 32-bit unsigned integer | 14U |
| UInt64 | 64-bit unsigned integer | 14UL |
| Double | 64-bit floating point, defined by IEEE754 | 3.14 |
| Float | 32-bit floating point | (3.14 : Float) |
| BigInt | represents numeric values larger than other types | 10000000000000000000000N |

MoonBit also supports numeric literals, including decimal, binary, octal, and hexadecimal numbers.

To improve readability, you may place underscores in the middle of numeric literals such as `1_000_000`. Note that underscores can be placed anywhere within a number, not just every three digits.

- Decimal numbers can have underscore between the numbers.
By default, an int literal is signed 32-bit number. For unsigned numbers, a postfix `U` is needed; for 64-bit numbers, a postfix `L` is needed.
let a = 1234
let b : Int = 1_000_000 + a
let unsigned_num : UInt = 4_294_967_295U
let large_num : Int64 = 9_223_372_036_854_775_807L
let unsigned_large_num : UInt64 = 18_446_744_073_709_551_615UL
- A binary number has a leading zero followed by a letter "B", i.e. `0b`/`0B`. Note that the digits after `0b`/`0B` must be `0` or `1`.
let bin = 0b110010
let another_bin = 0B110010
- An octal number has a leading zero followed by a letter "O", i.e. `0o`/`0O`. Note that the digits after `0o`/`0O` must be in the range from `0` through `7`:
let octal = 0o1234
let another_octal = 0O1234
- A hexadecimal number has a leading zero followed by a letter "X", i.e. `0x`/`0X`. Note that the digits after the `0x`/`0X` must be in the range `0123456789ABCDEF`.
let hex = 0XA
let another_hex = 0xA_B_C
- A floating-point number literal is 64-bit floating-point number. To define a float, type annotation is needed.
let double = 3.14 // Double
let float : Float = 3.14
let float2 = (3.14 : Float)
A 64-bit floating-point number can also be defined using hexadecimal format:
let hex_double = 0x1.2P3 // (1.0 + 2 / 16) * 2^(+3) == 9

When the expected type is known, MoonBit can automatically overload literal, and there is no need to specify the type of number via letter postfix:

let int : Int = 42
let uint : UInt = 42
let int64 : Int64 = 42
let double : Double = 42
let float : Float = 42
let bigint : BigInt = 42

See also

Overloaded Literals

### String#

`String` holds a sequence of UTF-16 code units. You can use double quotes to create a string, or use `#|` to write a multi-line string.

let a = "兔rabbit"
debug_inspect(a.code_unit_at(0).to_char(), content="Some('兔')")
debug_inspect(a.code_unit_at(1).to_char(), content="Some('r')")
let b =
#| Hello
#| MoonBit\n
#|
println(b)

Output#

Hello
MoonBit\n

In double quotes string, a backslash followed by certain special characters forms an escape sequence:

| escape sequences | description |
| --- | --- |
| \n, \r, \t, \b | New line, Carriage return, Horizontal tab, Backspace |
| \\ | Backslash |
| \u5154 , \u{1F600} | Unicode escape sequence |

MoonBit supports string interpolation. It enables you to substitute variables within interpolated strings. This feature simplifies the process of constructing dynamic strings by directly embedding variable values into the text. Variables used for string interpolation must implement the Show trait.

let x = 42
println("The answer is {x}")

Note

The interpolated expression can not contain newline, `{}` or `"`.

Multi-line strings can be defined using the leading `#|` or `$|`, where the former will keep the raw string and the latter will perform the escape and interpolation:

let lang = "MoonBit"
let raw =
#| Hello
#| ---
#| {lang}
#| ---
let interp =
$| Hello
$| ---
$| {lang}
$| ---
println(raw)
println(interp)

Output#

## Hello

## {lang}

## Hello

## MoonBit

Avoid mixing `$|` and `#|` within the same multi-line string; pick one style for the whole block.

The VSCode extension includes an action that can turn pasted documents into a plain multi-line string and switch between plain text and MoonBit multi-line strings.

When the expected type is `String` , the array literal syntax is overloaded to construct the `String` by specifying each character in the string.

test {
let c : Char = '中'
let s : String = [c, '文']
inspect(s, content="中文")
}

See also

API: https://mooncakes.io/docs/moonbitlang/core/string

Overloaded Literals

### Char#

`Char` represents a Unicode code point.

let a : Char = 'A'
let b = '兔'
let zero = '\u{30}'
let zero = '\u0030'

Char literals can be overloaded to type `Int` or `UInt16` when it is the expected type:

test {
let s : String = "hello"
let b : UInt16 = s.code_unit_at(0) // 'h'
assert_eq(b, 'h') // 'h' is overloaded to UInt16
let c : Int = '兔'
// Not ok : exceed range
// let d : UInt16 = '𠮷'
}

See also

API: https://mooncakes.io/docs/moonbitlang/core/char

Overloaded Literals

### Byte(s)#

A byte literal in MoonBit is either a single ASCII character or a single escape, have the form of `b'...'`. Byte literals are of type `Byte`. For example:

fn main {
let b1 : Byte = b'a'
println(b1.to_int())
let b2 = b'\xff'
println(b2.to_int())
}

Output#

97
255

A `Bytes` is an immutable sequence of bytes. Similar to byte, bytes literals have the form of `b"..."`. For example:

test {
let b1 : Bytes = b"abcd"
let b2 = b"\x61\x62\x63\x64"
assert_eq(b1, b2)
}

Bytes literals support interpolation with `b"...\{expression}"`. The interpolated string is encoded as UTF-8 to produce `Bytes`:

test {
let value = 42
let bytes : Bytes = b"value={value}"
assert_eq(bytes, b"value=42")
}

Template-write syntax also accepts interpolated Bytes literals.

The byte literal and bytes literal also support escape sequences, but different from those in string literals. The following table lists the supported escape sequences for byte and bytes literals:

| escape sequences | description |
| --- | --- |
| \n, \r, \t, \b | New line, Carriage return, Horizontal tab, Backspace |
| \\ | Backslash |
| \x41 | Hexadecimal escape sequence |
| \o102 | Octal escape sequence |

Note

You can use `@buffer.T` to construct bytes by writing various types of data. For example:

test "buffer 1" {
let buf : @buffer.Buffer = Buffer()
buf.write_bytes(b"Hello")
buf.write_byte(b'!')
assert_eq(buf.contents(), b"Hello!")
}

Array literals can also be overloaded to construct a `Bytes` sequence by specifying each byte in the sequence.

test {
let b : Byte = b'\xFF'
let bs : Bytes = [b, b'\x01']
inspect(
bs,
content=(
#|b"\xff\x01"
),
)
}

See also

API for `Byte`: https://mooncakes.io/docs/moonbitlang/core/byte
API for `Bytes`: https://mooncakes.io/docs/moonbitlang/core/bytes
API for `@buffer.T`: https://mooncakes.io/docs/moonbitlang/core/buffer

Overloaded Literals

#### Choosing a Byte Container#

MoonBit has several byte-oriented container types. They are related, but they serve different jobs:

| Type | Ownership / mutability | Resizable | Typical use |
| --- | --- | --- | --- |
| Bytes | owned, immutable | no | final byte payloads, API boundaries, serialized data |
| BytesView | borrowed, immutable view | no | slicing or parsing existing bytes without copying |
| Array[Byte] | owned, mutable | yes | general-purpose mutable byte storage |
| FixedArray[Byte] | owned, mutable | no | fixed-size working buffers |
| ArrayView[Byte] | borrowed array view | no | passing slices of array-backed byte storage without ownership |
| MutArrayView[Byte] | borrowed, mutable view | no | mutating borrowed array-backed byte storage in place |
| @buffer.Buffer | owned, mutable builder | yes | incrementally constructing bytes, then calling contents() |

Two common distinctions matter:

- `Bytes` versus `BytesView`: owned immutable data versus a borrowed immutable slice.
- `Array[Byte]` versus `ArrayView[Byte]` / `MutArrayView[Byte]`: owned mutable storage versus borrowed readonly or mutable views over it.

`ReadOnlyArray[Byte]` and `MutArrayView[Byte]` are the corresponding read-only and mutable view types when you need to express those constraints explicitly. Pattern matching and bitstring parsing also work on these byte containers; see Array Pattern and Bitstring Pattern.

### Tuple#

A tuple is a collection of finite values constructed using round brackets `()` with the elements separated by commas `,`. The order of elements matters; for example, `(1,true)` and `(true,1)` have different types. Here's an example:

fn main {
fn pack(
a : Bool,
b : Int,
c : String,
d : Double
) -> (Bool, Int, String, Double) {
(a, b, c, d)
}

let quad = pack(false, 100, "text", 3.14)
let (bool_val, int_val, str, float_val) = quad
println("{bool_val} {int_val} {str} {float_val}")
}

Output#

false 100 text 3.14

Tuples can be accessed via pattern matching or index:

test {
let t = (1, 2)
let (x1, y1) = t
let x2 = t.0
let y2 = t.1
assert_eq(x1, x2)
assert_eq(y1, y2)
}

### Ref#

A `Ref[T]` is a mutable reference containing a value `val` of type `T`.

It can be constructed using `{ val : x }`, and can be accessed using `ref.val`. See struct for detailed explanation.

let a : Ref[Int] = { val: 100 }

test {
a.val = 200
assert_eq(a.val, 200)
a.val += 1
assert_eq(a.val, 201)
}

See also

API: https://mooncakes.io/docs/moonbitlang/core/ref

### Option and Result#

`Option` and `Result` are the most common types to represent a possible error or failure in MoonBit.

- `Option[T]` represents a possibly missing value of type `T`. It can be abbreviated as `T?`.
- `Result[T, E]` represents either a value of type `T` or an error of type `E`.

See enum for detailed explanation.

test {
let a : Int? = None
let b : Option[Int] = Some(42)
let c : Result[Int, String] = Ok(42)
let d : Result[Int, String] = Err("error")
match a {
Some() => assert_true(false)
None => assert_true(true)
}
match d {
Ok() => assert_true(false)
Err(_) => assert_true(true)
}
}

See also

API for `Option`: https://mooncakes.io/docs/moonbitlang/core/option
API for `Result`: https://mooncakes.io/docs/moonbitlang/core/result

### Array#

An array is a finite sequence of values constructed using square brackets `[]`, with elements separated by commas `,`. For example:

let numbers = [1, 2, 3, 4]

You can use `numbers[x]` to refer to the xth element. The index starts from zero.

test {
let numbers = [1, 2, 3, 4]
let a = numbers[2]
numbers[3] = 5
let b = a + numbers[3]
assert_eq(b, 8)
}

There are `Array[T]` and `FixedArray[T]`. Views are provided by `ArrayView[T]` and `MutArrayView[T]` (see below).

`Array[T]` can grow in size, while `FixedArray[T]` has a fixed size, thus it needs to be created with initial value.

Warning

A common pitfall is creating `FixedArray` with the same initial value:

test {
let two_dimension_array = FixedArray::make(10, FixedArray::make(10, 0))
two_dimension_array[0][5] = 10
assert_eq(two_dimension_array[5][5], 10)
}

This is because all the cells reference to the same object (the `FixedArray[Int]` in this case). One should use `FixedArray::makei()` instead which creates an object for each index.

test {
let two_dimension_array = FixedArray::makei(10, fn(_i) {
FixedArray::make(10, 0)
})
two_dimension_array[0][5] = 10
assert_eq(two_dimension_array[5][5], 0)
}

When the expected type is known, MoonBit can automatically overload array, otherwise `Array[T]` is created:

let fixed_array_1 : FixedArray[Int] = [1, 2, 3]

let fixed_array_2 = ([1, 2, 3] : FixedArray[Int])

let array_3 : Array[Int] = [1, 2, 3] // Array[Int]

See also

API: https://mooncakes.io/docs/moonbitlang/core/array

Overloaded Literals

#### ArrayView#

Analogous to `slice` in other languages, the view is a reference to a specific segment of collections. You can use `data[start:end]` to create a view of array `data`, referencing elements from `start` to `end` (exclusive). Both `start` and `end` indices can be omitted.

Note

`ArrayView` is an immutable data structure on its own, but the underlying `Array` or `FixedArray` could be modified. For a mutable view, use `MutArrayView[T]` via `data.mut_view(...)`.

test {
let xs = [0, 1, 2, 3, 4, 5]
let s1 : ArrayView[Int] = xs[2:]
@test.assert_eq(s1.to_owned(), [2, 3, 4, 5])
@test.assert_eq(xs[:4].to_owned(), [0, 1, 2, 3])
@test.assert_eq(xs[2:5].to_owned(), [2, 3, 4])
@test.assert_eq(xs[:].to_owned(), [0, 1, 2, 3, 4, 5])
let mv : MutArrayView[Int] = xs.mut_view(start=1, end=3)
mv[0] = 99
inspect(xs[1], content="99")
}

See also

API: https://mooncakes.io/docs/moonbitlang/core/array

### Map#

MoonBit provides a hash map data structure that preserves insertion order called `Map` in its standard library. `Map` s can be created via a convenient literal syntax:

let map : Map[String, Int] = { "x": 1, "y": 2, "z": 3 }

Currently keys in map literal syntax must be constant. `Map` s can also be destructed elegantly with pattern matching, see Map Pattern.

See also

API: https://mooncakes.io/docs/moonbitlang/core/builtin#Map

Overloaded Literals

### Json#

MoonBit supports convenient json handling by overloading literals. When the expected type of an expression is `Json`, number, string, array and map literals can be directly used to create json data:

let moon_pkg_json_example : Json = {
"import": ["moonbitlang/core/builtin", "moonbitlang/core/coverage"],
"test-import": ["moonbitlang/core/random"],
}

Json values can be pattern matched too, see Json Pattern.

See also

API: https://mooncakes.io/docs/moonbitlang/core/json

Overloaded Literals

## Overloaded Literals#

Overloaded literals allow you to use the same syntax to represent different types of values.

An empty `{}` literal is ambiguous: it may mean an empty map, an empty JSON object, an empty record, or a block. Write the intended form explicitly: `Map([])`, `Json::empty_object()`, `Record::{}`, or `{ () }`, respectively. For example, you can use `1` to represent `UInt` or `Double` depending on the expected type. If the expected type is not known, the literal will be interpreted as `Int` by default.

fn expect_double(x : Double) -> Unit {

}

test {
let x = 1 // type of x is Int
let y : Double = 1
expect_double(1)
}

The overloaded literals can be composed. If array literal can be overloaded to `Bytes` , and number literal can be overloaded to `Byte` , then you can overload `[1,2,3]` to `Bytes` as well. Here is a table of overloaded literals in MoonBit:

| Overloaded literal | Default type | Can be overloaded to |
| --- | --- | --- |
| 10, 0xFF, 0o377, 10_000 | Int | UInt, Int64, UInt64, Int16, UInt16, Byte, Double, Float, BigInt |
| "str" | String | — |
| 'c' | Char | Int |
| 3.14 | Double | Float |
| [a, b, c] (where the types of literals a, b, and c are E) | Array[E] | FixedArray[E], String (if E is of type Char), Bytes (if E is of type Byte) |

There are also some similar overloading rules in pattern. For more details, see Pattern Matching.

Note

Literal overloading is not the same as value conversion. To convert a variable to a different type, you can use methods prefixed with `to_`, such as `to_int()`, `to_double()`, etc.

### Escape Sequences in Overloaded Literals#

Escape sequences can be used in overloaded `"..."` literals and `'...'` literals. The interpretation of escape sequences depends on the types they are overloaded to:

- Simple escape sequences
Including `\n`, `\r`, `\t`, `\\`, and `\b`. These escape sequences are supported in any `"..."` or `'...'` literals. They are interpreted as their respective `Char` or `Byte` in `String` or `Bytes`.
- Byte escape sequences
The `\x41` and `\o102` escape sequences represent a Byte. These are supported in literals overloaded to `Bytes` and `Byte`.
- Unicode escape sequences
The `\u5154` and `\u{1F600}` escape sequences represent a `Char`. These are supported in literals of type `String` and `Char`.

## Functions#

Functions take arguments and produce a result. In MoonBit, functions are first-class, which means that functions can be arguments or return values of other functions. MoonBit's naming convention requires that function names should not begin with uppercase letters (A-Z). Compare for constructors in the `enum` section below.

### Top-Level Functions#

Functions can be defined as top-level or local. We can use the `fn` keyword to define a top-level function that sums three integers and returns the result, as follows:

fn add3(x : Int, y : Int, z : Int) -> Int {
x + y + z
}

Note that the arguments and return value of top-level functions require explicit type annotations.

Top-level functions and methods can also be introduced with `declare`. A declared function has a signature but no body, and a later implementation must match that signature. This is useful when you want to make an API shape available before placing its implementation.

declare fn declared_add(x : Int, y : Int) -> Int

fn declared_add(x : Int, y : Int) -> Int {
x + y
}

struct DeclaredCounter(Int)

declare fn DeclaredCounter::value(self : Self) -> Int

fn DeclaredCounter::value(self : Self) -> Int {
self.0
}

test "declared functions" {
@test.assert_eq(declared_add(1, 2), 3)
@test.assert_eq(DeclaredCounter(4).value(), 4)
}

If a declared function has an implementation, the declaration and the implementation must agree on the function name, visibility, type parameters, parameters, return type, and effects.

### Local Functions#

Local functions can be named or anonymous. Type annotations can be omitted for local function definitions: they can be automatically inferred in most cases. For example:

fn local_1() -> Int {
fn inc(x) { // named as `inc`
x + 1
}
// anonymous, instantly applied to integer literal 6
(fn(x) { x + inc(2) })(6)
}

test {
assert_eq(local_1(), 9)
}

For simple anonymous function, MoonBit provides a very concise syntax called arrow function:

[1, 2, 3].eachi((i, x) => println("{i} => {x}"))
// parenthesis can be omitted when there is only one parameter
[1, 2, 3].each(x => println(x * x))

Although local function supports type inference for types of parameters and return value, effect inference is only supported for the arrow function syntax. If a `fn` may raise error or perform asynchronous operations, it must be explicitly annotated with `raise` or `async`.

Functions, whether named or anonymous, are lexical closures: any identifiers without a local binding must refer to bindings from a surrounding lexical scope. For example:

let global_y = 3

fn local_2(x : Int) -> (Int, Int) {
fn inc() {
x + 1
}

fn four() {
global_y + 1
}

(inc(), four())
}

test {
@test.assert_eq(local_2(3), (4, 4))
}

A local function can only refer to itself and other previously defined local functions. To define mutually recursive local functions, use the syntax `letrec f = .. and g = ..` instead:

fn f(x) {
// `f` can refer to itself here, but cannot use `g`
if x > 0 {
f(x - 1)
}
}

fn g(x) {
// `g` can refer to `f` and `g` itself
if x < 0 {
f(-x)
} else {
f(x)
}
}
// mutually recursive local functions
letrec even = x => x == 0 || odd(x - 1)
and odd = x => x != 0 && even(x - 1)

### Function Applications#

A function can be applied to a list of arguments in parentheses:

add3(1, 2, 7)

This works whether `add3` is a function defined with a name (as in the previous example), or a variable bound to a function value, as shown below:

test {
let add3 = fn(x, y, z) { x + y + z }
assert_eq(add3(1, 2, 7), 10)
}

The expression `add3(1, 2, 7)` returns `10`. Any expression that evaluates to a function value is applicable:

test {
let f = fn(x) { x + 1 }
let g = fn(x) { x + 2 }
let w = (if true { f } else { g })(3)
assert_eq(w, 4)
}

### Partial Applications#

Partial application is a technique of applying a function to some of its arguments, resulting in a new function that takes the remaining arguments. In MoonBit, partial application is achieved by using the `_` operator in function application:

fn add(x : Int, y : Int) -> Int {
x + y
}

test {
let add10 : (Int) -> Int = x => add(10, x)
println(add10(5)) // prints 15
println(add10(10)) // prints 20
}

The `_` operator represents the missing argument in parentheses. The partial application allows multiple `_` in the same parentheses. For example, `Array::fold(_, _, init=5)` is equivalent to `fn(x, y) { Array::fold(x, y, init=5) }`.

The `_` operator can also be used in enum creation, dot style function calls and in the pipelines.

Warning

The syntax `f(a, _, b)` for partial application is deprecated. Use `x => f(a, x, b)` instead.

### Labelled arguments#

Top-level functions can declare labelled argument with the syntax `label~ : Type`. `label` will also serve as parameter name inside function body:

fn labelled_1(arg1~ : Int, arg2~ : Int) -> Int {
arg1 + arg2
}

Labelled arguments can be supplied via the syntax `label=arg`. `label=label` can be abbreviated as `label~`:

test {
let arg1 = 1
assert_eq(labelled_1(arg2=2, arg1~), 3)
}

Labelled function can be supplied in any order. The evaluation order of arguments is the same as the order of parameters in function declaration.

### Optional arguments#

An argument can be made optional by supplying a default expression with the syntax `label?: Type = default_expr`, where the `default_expr` may be omitted. If this argument is not supplied at call site, the default expression will be used:

fn optional(opt? : Int = 42) -> Int {
opt
}

test {
assert_eq(optional(), 42)
assert_eq(optional(opt=0), 0)
}

The default expression will be evaluated every time it is used. And the side effect in the default expression, if any, will also be triggered. For example:

fn incr(counter? : Ref[Int] = { val: 0 }) -> Ref[Int] {
counter.val = counter.val + 1
counter
}

test {
@test.assert_eq(incr().val, 1)
@test.assert_eq(incr().val, 1)
let counter = Ref::{ val: 0 }
@test.assert_eq(incr(counter~).val, 1)
@test.assert_eq(incr(counter~).val, 2)
}

Optional argument values are regular expressions at the call site. You can pass expressions that may raise errors or call async functions when in a `raise` or `async` context:

fn may_fail(x : Int) -> Int raise Failure {
if x < 0 {
fail("negative")
}
x
}

fn add_with_optional(base : Int, extra? : Int = 1) -> Int {
base + extra
}

test {
inspect(add_with_optional(1, extra=may_fail(2)), content="3")
}

For async functions, optional argument expressions can call async functions as usual:

///|
async fn fetch_default() -> Int {
...
}

///|
async fn build(x? : Int = fetch_default()) -> Int {
...
}

///|
async fn use_value() -> Int {
build(x=fetch_default())
}

If you want to share the result of default expression between different function calls, you can lift the default expression to a toplevel `let` declaration:

let default_counter : Ref[Int] = { val: 0 }

fn incr_2(counter? : Ref[Int] = default_counter) -> Int {
counter.val = counter.val + 1
counter.val
}

test {
assert_eq(incr_2(), 1)
assert_eq(incr_2(), 2)
}

The default expression can depend on previous arguments, such as:

fn create_rectangle(a : Int, b? : Int = a) -> (Int, Int) {
(a, b)
}

test {
debug_inspect(create_rectangle(10), content="(10, 10)")
}

#### Optional arguments without default values#

It is quite common to have different semantics when a user does not provide a value. Optional arguments without default values have type `T?` and `None` as the default value. When supplying this kind of optional argument directly, MoonBit will automatically wrap the value with `Some`:

fn new_image(width? : Int, height? : Int) -> Image {
if width is Some(w) {
...
}
...
}

let img2 : Image = new_image(width=1920, height=1080)

Sometimes, it is also useful to pass a value of type `T?` directly, for example when forwarding optional argument. MoonBit provides a syntax `label?=value` for this, with `label?` being an abbreviation of `label?=label`:

fn image(width? : Int, height? : Int) -> Image {
...
}

fn fixed_width_image(height? : Int) -> Image {
image(width=1920, height?)
}

### Autofill arguments#

MoonBit supports filling specific types of arguments automatically at different call site, such as the source location of a function call. To declare an autofill argument, simply declare a labelled argument, and add a function attribute `#callsite(autofill(param_a, param_b))`. Now if the argument is not explicitly supplied, MoonBit will automatically fill it at the call site.

Currently MoonBit supports two types of autofill arguments, `SourceLoc`, which is the source location of the whole function call, and `ArgsLoc`, which is an array containing the source location of each argument, if any:

#callsite(autofill(loc, args_loc))
fn f(_x : Int, loc~ : SourceLoc, args_loc~ : ArgsLoc) -> String {
(
$|loc of whole function call: {loc}
$|loc of arguments: {args_loc}
)
// loc of whole function call: :7:3-7:10
// loc of arguments: [Some(:7:5-7:6), Some(:7:8-7:9), None, None]
}

Autofill arguments are very useful for writing debugging and testing utilities.

### Function alias#

MoonBit allows calling functions with alternative names via function alias. Function alias can be declared as follows:

#alias(g)
#alias(h, visibility="pub")
fn k() -> Bool {
true
}

You can also create function alias that has different visibility with the field `visibility`.

## Control Structures#

### Conditional Expressions#

A conditional expression consists of a condition, a consequent, and an optional `else` clause or `else if` clause.

if x == y {
expr1
} else if x == z {
expr2
} else {
expr3
}

The curly brackets around the consequent are required.

Note that a conditional expression always returns a value in MoonBit, and the return values of the consequent and the else clause must be of the same type. Here is an example:

let initial = if size < 1 { 1 } else { size }

The `else` clause can only be omitted if the return value has type `Unit`.

### Match Expression#

The `match` expression is similar to conditional expression, but it uses pattern matching to decide which consequent to evaluate and extracting variables at the same time.

fn decide_sport(weather : String, humidity : Int) -> String {
match weather {
"sunny" => "tennis"
"rainy" => if humidity > 80 { "swimming" } else { "football" }
_ => "unknown"
}
}

test {
assert_eq(decide_sport("sunny", 0), "tennis")
}

If a possible condition is omitted, the compiler will issue a warning, and the program will terminate if that case were reached.

### Guard Statement#

The `guard` statement is used to check a specified invariant. If the condition of the invariant is satisfied, the program continues executing the subsequent statements and returns. If the condition is not satisfied (i.e., false), the code in the `else` block is executed and its evaluation result is returned (the subsequent statements are skipped).

fn guarded_get(array : Array[Int], index : Int) -> Int? {
guard index >= 0 && index < array.length() else { None }
Some(array[index])
}

test {
debug_inspect(guarded_get([1, 2, 3], -1), content="None")
}

#### Guard statement and is expression#

The `let` statement can be used with pattern matching. However, `let` statement can only handle one case. And using is expression with `guard` statement can solve this issue.

In the following example, `getProcessedText` assumes that the input `path` points to resources that are all plain text, and it uses the `guard` statement to ensure this invariant while extracting the plain text resource. Compared to using a `match` statement, the subsequent processing of `text` can have one less level of indentation.

enum Resource {
Folder(Array[String])
PlainText(String)
JsonConfig(Json)
}

fn getProcessedText(
resources : Map[String, Resource],
path : String,
) -> String raise Error {
guard resources.get(path) is Some(resource) else { fail("{path} not found") }
guard resource is PlainText(text) else { fail("{path} is not plain text") }
process(text)
}

An ordinary `guard` that may fail must have an `else` clause. If the compiler cannot prove that a `guard` without `else` always succeeds, it reports E0087, because failure would implicitly terminate the program. Use `guard!` when termination is intended. Unlike `guard`, `guard!` cannot have an `else` clause.

guard! condition // <=> guard condition else { panic() }
guard! expr is Some(x)
// <=> guard expr is Some(x) else { _ => panic() }

When a condition or pattern is exhaustive, use plain `guard` without an `else`. The compiler reports a warning for a redundant `!` or `else` clause.

fn require_some(value : Int?) -> Int {
guard! value is Some(result)
result
}

### While loop#

In MoonBit, `while` loop can be used to execute a block of code repeatedly as long as a condition is true. The condition is evaluated before executing the block of code. The `while` loop is defined using the `while` keyword, followed by a condition and the loop body. The loop body is a sequence of statements. The loop body is executed as long as the condition is true.

fn main {
let mut i = 5
while i > 0 {
println(i)
i = i - 1
}
}

Output#

5
4
3
2
1

The loop body supports `break` and `continue`. Using `break` allows you to exit the current loop, while using `continue` skips the remaining part of the current iteration and proceeds to the next iteration.

fn main {
let mut i = 5
while i > 0 {
i = i - 1
if i == 4 {
continue
}
if i == 1 {
break
}
println(i)
}
}

Output#

3
2

The `while` loop also supports an optional `nobreak` clause. When the loop condition becomes false, the `nobreak` clause will be executed, and then the loop will end.

fn main {
let mut i = 2
while i > 0 {
println(i)
i = i - 1
} nobreak {
println(i)
}
}

Output#

2
1
0

When there is an `nobreak` clause, the `while` loop can also return a value. The return value is the evaluation result of the `nobreak` clause. In this case, if you use `break` to exit the loop, you need to provide a return value after `break`, which should be of the same type as the return value of the `nobreak` clause.

fn main {
let mut i = 10
let r = while i > 0 {
i = i - 1
if i % 2 == 0 {
break 5
}
} nobreak {
7
}
println(r)
}

Output#

5

fn main {
let mut i = 10
let r = while i > 0 {
i = i - 1
} nobreak {
7
}
println(r)
}

Output#

7

### For Loop#

MoonBit also supports C-style For loops. The keyword `for` is followed by variable initialization clauses, loop conditions, and update clauses separated by semicolons. They do not need to be enclosed in parentheses. For example, the code below creates a new variable binding `i`, which has a scope throughout the entire loop and is immutable. This makes it easier to write clear code and reason about it:

fn main {
for i = 0; i < 5; i = i + 1 {
println(i)
}
}

Output#

0
1
2
3
4

The variable initialization clause can create multiple bindings:

for i = 0, j = 0; i + j < 100; i = i + 1, j = j + 1 {
println(i)
}

It should be noted that in the update clause, when there are multiple binding variables, the semantics are to update them simultaneously. In other words, in the example above, the update clause does not execute `i = i + 1`, `j = j + 1` sequentially, but rather increments `i` and `j` at the same time. Therefore, when reading the values of the binding variables in the update clause, you will always get the values updated in the previous iteration.

Variable initialization clauses, loop conditions, and update clauses are all optional. For example, the following two are infinite loops:

for i = 1; ; i = i + 1 {
println(i)
}
for ;; {
println("loop forever")
}

The `for` loop also supports `continue`, `break`, and `nobreak` clauses. Like the `while` loop, the `for` loop can also return a value using the `break` and `nobreak` clauses.

The `continue` statement skips the remaining part of the current iteration of the `for` loop (including the update clause) and proceeds to the next iteration. The `continue` statement can also update the binding variables of the `for` loop, as long as it is followed by expressions that match the number of binding variables, separated by commas.

For example, the following program calculates the sum of even numbers from 1 to 6:

fn main {
let sum = for i = 1, acc = 0; i <= 6; i = i + 1 {
if i % 2 == 0 {
println("even: {i}")
continue i + 1, acc + i
}
} nobreak {
acc
}
println(sum)
}

Output#

even: 2
even: 4
even: 6
12

### `for .. in` loop#

MoonBit supports traversing elements of different data structures and sequences via the `for .. in` loop syntax:

for x in [1, 2, 3] {
println(x)
}

`for .. in` loop is translated to the use of `Iter` in MoonBit's standard library. Any type with a method `.iter() : Iter[T]` can be traversed using `for .. in`. For more information of the `Iter` type, see Iterator below.

`for .. in` loop also supports iterating through a sequence of integers, such as:

test {
let mut i = 0
for j in 0..<10 {
i += j
}
assert_eq(i, 45)
let mut k = 0
for l in 0..<=10 {
k += l
}
assert_eq(k, 55)
}

In addition to sequences of a single value, MoonBit also supports traversing sequences of two values, such as `Map`, via the `Iter2` type in MoonBit's standard library. Any type with method `.iter2() : Iter2[A, B]` can be traversed using `for .. in` with two loop variables:

for k, v in { "x": 1, "y": 2, "z": 3 } {
println(k)
println(v)
}

Another example of `for .. in` with two loop variables is traversing an array while keeping track of array index:

fn main {
for index, elem in [4, 5, 6] {
let i = index + 1
println("The {i}-th element of the array is {elem}")
}
}

Output#

The 1-th element of the array is 4
The 2-th element of the array is 5
The 3-th element of the array is 6

Control flow operations such as `return`, `break` and error handling are supported in the body of `for .. in` loop:

fn main {
let map = { "x": 1, "y": 2, "z": 3, "w": 4 }
for k, v in map {
if k == "y" {
continue
}
println("{k}, {v}")
if k == "z" {
break
}
}
}

Output#

x, 1
z, 3

If a loop variable is unused, it can be ignored with `_`.

### Range expression in `for .. in` loop#

`for .. in` loops can also be used with range expressions for iterating over a number range:

fn main {
for x in 0..<5 {
println(x)
}
}

Output#

0
1
2
3
4

There are four kinds of range expressions available in `for .. in` loop:

- `a..<b`: iterate from `a` to `b` in increasing order, excluding `b`
- `a..<=b`: iterate from `a` to `b` in increasing order, including `b`
- `a>..b`: iterate from `a` to `b` in decreasing order, excluding `a`
- `a>=..b`: iterate from `a` to `b` in decreasing order, including `a`

### List comprehension#

MoonBit supports list comprehension syntax for constructing a collection by iterating over another collection or range:

let squares = [ for x in 1..<=5 => x * x ]
let even_numbers = [ for x in 0..<100 if x % 2 == 0 => x ]
let labelled = [ for i, x in ["a", "b", "c"] => "{i}: {x}" ]
let map = { 1: 2, 2: 4, 3: 8 }
let present = [ for x in [1, 2, 3] if map.get(x) is Some(y) => y ]

The syntax is `[ for ... => ... ]`. The part before `=>` follows the same iteration rules as `for .. in`: one binder uses `Iter`, two binders use `Iter2`, and range expressions such as `0..<10` are supported. An optional `if` guard filters elements before evaluating the result expression. Names introduced by an `is` expression in the guard, such as `y` above, can be used in the result expression.

The result defaults to `Array[T]` when there is no expected type. When the expected type is known, a list comprehension can also construct `FixedArray[T]`, `ReadOnlyArray[T]`, `String`, `Bytes`, or `Json`:

let text : String = [ for x in 0..<3 => (x + 'a').unsafe_to_char() ]
let bytes : Bytes = [ for x in 0..<3 => x.to_byte() ]
let fixed : FixedArray[_] = [ for x in 1..<=3 => x ]

For lazy or infinite sequences, create an `Iter[T]` directly. The following iterator keeps Fibonacci state in captured variables and is limited before collection:

let mut p1 = 1
let mut p2 = 0
let fib_numbers : Iter[Int] = Iter::new(fn() {
let next = p1
p1 = p1 + p2
p2 = next
Some(next)
})
let first_six = fib_numbers.take(6).collect()

Control flow operations such as `return`, `break`, and `continue` are not allowed inside list comprehensions.

### Labelled Continue/Break#

When a loop is labelled, it can be referenced from a `break` or `continue` from within a nested loop. For example:

Once a loop has a label, use that label for `break` or `continue` statements that directly target the loop as well. An unlabelled `break` or `continue` directly inside a labelled loop is deprecated because it leaves the target implicit.

test "break label" {
let mut count = 0
let xs = [1, 2, 3]
let ys = [4, 5, 6]
let res = outer~: for i in xs {
for j in ys {
count = count + i
break outer~ j
}
} nobreak {
-1
}
assert_eq(res, 4)
assert_eq(count, 1)
}

test "continue label" {
let mut count = 0
let init = 10
let res = outer~: for i = init {
if i == 0 {
break outer~ 42
}
for ;; {
count = count + 1
continue outer~ i - 1
}
}
assert_eq(res, 42)
assert_eq(count, 10)
}

### Labelled Blocks#

A block can also have a label. `break label~ value` exits the block immediately and makes `value` the result of the block. This is useful for returning early from nested control flow without returning from the enclosing function.

fn absolute(n : Int) -> Int {
result~: {
if n < 0 {
break result~ -n
}
n
}
}

An unlabelled `break` cannot exit or pass through a labelled block, and `continue` can only target a labelled loop, not a labelled block.

Block and loop labels share the same namespace. Reusing an enclosing label on a nested block or loop shadows the outer label and produces E0036. Use distinct names so that each labelled `break` or `continue` has an unambiguous target.

### `defer` and `errdefer` expressions#

`defer` expression can be used to perform reliable resource cleanup. The syntax for `defer` is as follows:

defer

Whenever the program leaves `body`, `expr` will be executed. For example, the following program:

defer println("perform resource cleanup")
println("do things with the resource")

will first print `do things with the resource`, and then `perform resource cleanup`. `defer` expression will always get executed no matter how its body exits. It can handle error, as well as control flow constructs including `return`, `break` and `continue`.

Consecutive `defer` will be executed in reverse order, for example, the following:

defer println("first defer")
defer println("second defer")
println("do things")

will output first `do things`, then `second defer`, and finally `first defer`.

`return`, `break` and `continue` are disallowed in the right-hand side of `defer`. The cleanup expression may otherwise raise an error and, in async code, perform async operations. If it raises, its error replaces any error that caused the body to exit. The following test confirms that the cleanup error replaces the body error:

let message = try {
defer {
raise Failure("cleanup error")
}
raise Failure("body error")
} 

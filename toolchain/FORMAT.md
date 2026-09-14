# The formatter's rules

`mo fmt` owns every byte of whitespace in a Mo file (chapter 2: "Column limits, indent width, blank lines, and ordering are the formatter's job and never a choice"). It parses the file, then prints it again from the tree plus the comments and blank lines it kept. A file that does not parse is never touched. Each row below is something a reader can check a file against by eye; `mo fmt --check` checks all of them at once. `src/fmt.zig` implements the table.

## Lines

| # | rule | right | wrong |
|---|---|---|---|
| L1 | Indent is two spaces per level, spaces only. | `··x = 1` | `→x = 1`, `····x = 1` at level 1 |
| L2 | No trailing whitespace on any line. | `x = 1` | `x = 1··` |
| L3 | The file ends with exactly one newline. | `end⏎` | `end`, `end⏎⏎` |
| L4 | The column limit is 100, counted in characters, with the indent and without a trailing comment. | | |
| L5 | A line over the limit breaks after a comma inside parentheses or brackets opened on that line; each continuation line is indented one level deeper than the line it continues. A line with no such comma stays long. | `··f(aaa, bbb,`⏎`····ccc)` | `··f(aaa,`⏎`ccc)` |
| L6 | The breaks go after the outermost commas first, each as late as still fits. A piece that still does not fit breaks after the commas one level in, and only then: a nested call is never split across lines by itself. | `··g(aaa, bbb,`⏎`····h(ccc, ddd))` | `··g(aaa, bbb, h(ccc,`⏎`····ddd))` |
| L7 | A list literal that breaks after one of its commas breaks after all of them, one element per line; the first element stays after the `[`. A list that fits on its piece does not break. | `··xs = ["aaa",`⏎`····"bbb",`⏎`····"ccc"]` | `··xs = ["aaa", "bbb",`⏎`····"ccc"]` |

## Blank lines

| # | rule |
|---|---|
| B1 | Never two blank lines in a row. |
| B2 | No blank line at the start or end of a block: after a line that opens one (`fn`, `if`, `else`, `for`, `case`, an arm, `test`, `state`, ...), or before its `end` or `else`. |
| B3 | No blank line between `module` and `expose`; exactly one after the `expose` line. |
| B4 | `use` lines sit together with no blanks; one blank line after the group. |
| B5 | Exactly one blank line before `intent`, before each `never`, between top-level declarations, between tests, and before `verified:`. The author's blank lines at the top level are not kept: this row decides them all. |
| B6 | One blank line between the contract lines (`requires`, `ensures`) and the body. The contract lines follow the signature with no blank. |
| B7 | Inside a block, between two statements, one blank line where the author left one or more, none where the author left none. |
| B8 | Inside a process: the `state` block, a blank line, each `invariant` block followed by a blank line, the `message` lines together with no blanks, a blank line, then `fn update`. |
| B9 | No blank lines inside `state`, `struct`, `enum`, `trait`, `supervisor`, or `recipe`; between the arms of a `case`; or between the `message` lines. |
| B10 | One blank line between the functions of an `impl`. |

## Spacing

| # | rule | right | wrong |
|---|---|---|---|
| S1 | A parameter, field, or named argument is `name: value`, no space before the colon. | `amount: Money`, `within: 200.ms` | `amount : Money` |
| S2 | A return type or a message's reply type has a space on both sides of the colon. | `) : Bool`, `message Done : UInt32` | `): Bool` |
| S3 | One space around `=`, `+=`, `-=`, `==`, `!=`, `<`, `<=`, `>`, `>=`, `+`, `-`, `*`, `/`, `%`, `and`, `or`, `implies`, `is`, `where`. | `a + b` | `a+b` |
| S4 | No space around `.` and `..`, after unary `-` or `!`, or inside `()`, `[]`, `{}`. One space after `try`. | `0..n`, `!charge.refunded?`, `[1, 2]` | `0 .. n`, `( a )` |
| S5 | No space before a comma, one after. | `f(a, b)` | `f(a ,b)`, `f(a,b)` |
| S6 | No space between a name and its `(`: calls, signatures, variants, `old(`, `any(`, `fn(`. `use` braces follow the path directly. | `use A.B{X, Y}` | `f (x)`, `use A.B {X}` |
| S7 | Everything else is separated by exactly one space. | `ensures result is Ok(c)` | `ensures··result` |
| S8 | An anonymous function whose body is one expression is written on one line, `fn(x) x > 0 end`, when that line fits the limit and no comment sits inside it, and is never broken inside. When its line is over the limit, the line breaks around it (L5) if every piece then fits, so a long call puts the function on a continuation line of its own; otherwise it is the block form, body on the lines below, `end` at the indent of the line that opened it. | `··xs.reduce(start,`⏎`····fn(acc, x) acc + x end)` | `··xs.reduce(start, fn(acc, x)`⏎`····acc + x`⏎`··end)` for a call that fits once broken |
| S9 | Parentheses that only group an expression or a pattern stay exactly as the author wrote them; the formatter neither adds nor removes any. | | |
| S10 | A supervisor or `child` line with no arguments has no parentheses. | `child Counter, restart: :always` | `child Counter(), restart: :always` |

## Case arms

| # | rule |
|---|---|
| C1 | An arm whose body is one expression is `Pattern: expr` on one line when that line fits the limit and no comment sits inside it. |
| C2 | Otherwise the arm is `Pattern:` alone, and the body is the block below it, one level deeper. |
| C3 | An arm written `Pattern: case ...` or `Pattern: if ...` that does not fit on one line keeps its value on the arm line and continues below it; moving it down would turn the expression into a statement. |
| C4 | Arms are never separated by blank lines (B9). |
| C5 | A grouped arm keeps its alternatives on the arm line, one space either side of each `\|`: `Get(_) \| Stats \| Quit: ...`. |

## One-line if values

An `if` where a value goes is written on one line, `if cond: a else: b` (grammar §6, step 25), or as the block. The two forms are one tree, so the formatter picks the shape, whichever form the author wrote.

| # | rule | right | wrong |
|---|---|---|---|
| I1 | An `if` value whose branches are one expression each, the else branch possibly an `if` value of the same shape (`else: if ...`), is one line when that line fits the limit and no comment sits inside it. A block-form `if` value of that shape is written on one line too. | `··word = if n == 1: "line" else: "lines"` | `··word = if n == 1`⏎`····"line"`⏎`··else`⏎`····"lines"`⏎`··end` |
| I2 | A comment on the condition's line, after the first branch, or on a line of its own anywhere inside keeps the block form. One comment after the else branch or after `end` ends the one line (K3), as it does when the author wrote the one line; two keep the block. | `··x = if a: 1 else: 2··# why` | |
| I3 | When its line is over the limit, the line breaks around it (L5) if every piece then fits, as S8 does for an anonymous function; otherwise it is the block form. A branch holding a statement, or more than one line, is always the block form. | `··f(aaa, bbb,`⏎`····if ok: 1 else: 2)` | `··f(aaa, bbb, if ok`⏎`····1` ... for a call that fits once broken |
| I4 | A block `if` value followed on its `end` line by more of an expression (`end.size`, `end + 1`) keeps the block form: on one line, the else branch would take what follows. An `if` that starts a line is a statement and always the block form; the one-line form there is `MO0101`. | | |

## Ordering

| # | rule |
|---|---|
| O1 | A file is `module`, `expose`, the `use` lines, `intent`, the `never` blocks, the declarations, the `test` and `property` blocks, then `verified:`. The parser rejects any other order, so the formatter never has to move a declaration. |
| O2 | `use` lines are sorted by module path, byte order. The names inside a `use` line's braces keep the author's order. |
| O3 | Declarations, tests, and properties keep the author's order. |
| O4 | The `expose` list keeps the author's order: it is the module's table of contents. |

## Comments

| # | rule |
|---|---|
| K1 | A `#` comment on a line of its own stays attached to the line below it: it is printed directly above that line, at that line's indent, with no blank line between them. A blank line the author left above the comment follows the blank-line rules of the line below. |
| K2 | A comment above an `end` or `else` is printed at the indent of the block it closes. A comment at the end of the file stays at the end. |
| K3 | A comment after code stays on its line, after the code and two spaces. |
| K4 | Comment text is never changed, apart from trailing whitespace (L2). |
| K5 | The formatter never moves or drops a comment. A comment inside what would be a one-line anonymous function, arm, or `if` value keeps that construct in block form. A comment inside parentheses that span lines, which the formatter joins, refuses the file with `MO0502` and leaves it unchanged. |
| K6 | A `use` line moves with its comments when O2 sorts it. |

## Never changed

| # | rule |
|---|---|
| N1 | Strings, including `"""` blocks and interpolation holes, and numbers are printed byte for byte as written. |
| N2 | Names and the `verified:` line's text are printed as written. |

## Loops (MO0501)

Chapter 4's rule: a pure body is written with `map`, `filter`, or `reduce`; `for` is for effects, `try`, `break`, or `return`. `mo check` and `mo fmt --check` report a `for` statement whose body is pure as `MO0501` ("this for has a pure body; write it as map, filter, or reduce"). The formatter does not rewrite it. A body is pure when it contains no capability call, no `try`, no `break`, no `return`, and no assignment to a name declared outside the loop. A capability call is a call on a capability or a process handle, or a call that passes one as an argument. The comprehension `for` of a `never` or a `property` is not a `for` statement and is not checked.

The rule also reports three loops over a list whose one statement builds a `var` declared outside the loop, and `mo fix` rewrites them (`src/fix.zig`):

| loop body | becomes |
|---|---|
| `acc = acc.push(e)` | `acc = acc.concat(xs.map(fn(x) e end))` |
| `if c` around `acc = acc.push(x)` | `acc = acc.concat(xs.filter(fn(x) c end))` |
| `acc = e` where `e` reads `acc`; `acc += e`; `acc -= e` | `acc = xs.reduce(acc, fn(so_far, x) e end)` with `acc` read as `so_far`; `so_far + e`; `so_far - e` |

A loop is one of the three only when the rewrite means the same and compiles: `xs` is a list, not a range; the loop reads its element; `e` and `c` are pure, fit on one line, and read no `var` but `acc` (an anonymous function cannot capture one, `MO0314`); map and filter do not read `acc`; and no comment sits in the loop. Any other pure body is reported with no fix.

## The two properties

`zig build test` checks both over every file in `examples/` and over unformatted inputs in `src/fmt.zig`:

- **Idempotent.** Formatting a formatted file changes nothing.
- **Faithful.** Parsing the output gives a tree equal to parsing the input: the same nodes, the same token text, in the same order.

# Mo grammar, v0

Draft, 12 Sep 2026. Covers every construct in `design-v0/04-syntax.md`. EBNF: `x*` zero or more, `x+` one or more, `x?` optional, `|` alternatives, `"…"` literal tokens. `NL` is a newline; the lexer joins lines that end inside an open paren. The formatter owns all whitespace, so indentation carries no meaning.

## 1. Lexical

```
comment     = "#" any* NL
ident       = lower (alnum | "_")* "?"?        # snake_case; "?" only on predicates
TypeName    = Upper (alnum)*                   # CapCase; also enum variants, modules
path        = TypeName ("." TypeName)*         # Payments.Refund, Money
int         = digit (digit | "_")*             # 10_000
float       = int "." digit+
string      = '"' (char | "#{" expr "}")* '"'
            | '"""' NL (line NL)* '"""'        # common indentation stripped
atom        = ":" ident                        # only where the grammar names it
keyword     = module use intent never expose fn requires ensures var inout if else end
              case for in break return try and or implies is old result assert
              struct enum type where trait impl process state invariant message
              supervisor child per recipe needs test rejects property any
              verified true false
```

No block comments, no single-quoted strings, no literal type suffixes. Every string interpolates.

## 2. Module

```
module      = "module" path NL expose? use* intent? never* decl* test* verified?
expose      = "expose" name ("," name)* NL     # the exposed surface; everything else is private
name        = ident | TypeName
use         = "use" path "{" name ("," name)* "}" NL      # types and functions from the expose line; no bare use, no wildcards, no aliases
intent      = "intent" string NL
never       = "never" string NL (comprehension | expr NL) "end" NL   # a comprehension, or one checkable call such as flows(...)
verified    = "verified:" any* NL                # toolchain-owned; hand edits are errors
decl        = struct | enum | typedef | trait | impl | fn | main | process | supervisor | recipe
main        = "fn" "main" "(" ident ":" "Platform" ")" NL block "end" NL   # no return type, like update; once per program
```

One module per file; the file path equals the module path.

## 3. Types

```
typeexpr    = path ("(" typeexpr ("," typeexpr)* ")")?      # Result(Charge, RefundError)
            | "(" typeexpr ("," typeexpr)+ ")"              # tuple
            | typeexpr "where" expr                         # refinement: List(T) where size <= 1_000
struct      = "struct" TypeName NL field+ "end" NL
field       = ident ":" typeexpr NL
enum        = "enum" TypeName NL variant+ "end" NL
variant     = TypeName ("(" field_list ")")? NL
field_list  = ident ":" typeexpr ("," ident ":" typeexpr)*
typedef     = "type" TypeName "=" typeexpr NL         # type Money = UInt64 where value <= ...
trait       = "trait" TypeName NL signature+ "end" NL
impl        = "impl" TypeName "for" typeexpr NL fn+ "end" NL
```

## 4. Functions and contracts

```
fn          = signature NL contract* NL? block "end" NL
params_untyped = ident ("," ident)*                       # anonymous function parameters: fn(acc, x)
signature   = "fn" ident "(" params? ")" ":" typeexpr generics?
params      = param ("," param)*
param       = "inout"? ident ":" typeexpr
generics    = "where" TypeName ":" path ("," TypeName ":" path)*
contract    = ("requires" | "ensures") expr NL
```

Contracts sit directly under the signature; a blank line separates them from the body. `result` is valid only inside `ensures`; `old(expr)` inside `ensures` and `invariant`.

## 5. Statements

```
block       = stmt*
stmt        = binding | assign | return | for | if_stmt | case | assert | "break" NL | expr NL
assert      = "assert" expr NL                                # test, rejects, and property blocks only
binding     = "var"? ident "=" expr NL
assign      = place ("=" | "+=" | "-=") expr NL              # place must root at a var, inout, or state
place       = ident ("." ident)*
return      = "return" expr ("if" expr)? NL                   # trailing if only here
for         = "for" (ident | "_") "in" expr NL block "end" NL   # _ when the index is unused
if_stmt     = "if" expr NL block ("else" NL block)? "end" NL
case        = "case" expr NL arm+ "end" NL
arm         = pattern ("if" expr)? ":" (expr NL | NL block)   # runs until the next arm or end
```

## 6. Expressions

```
expr        = or_expr ("implies" or_expr)?
or_expr     = and_expr ("or" and_expr)*                      # on Option(T): default
and_expr    = not_expr ("and" not_expr)*
not_expr    = "!" not_expr | cmp
cmp         = range (("==" | "!=" | "<" | "<=" | ">" | ">=") range | "is" pattern)?
range       = add (".." add)?                                # a..b is a up to and excluding b
add         = mul (("+" | "-") mul)*                         # left-associative: a - b - c is (a - b) - c
mul         = unary (("*" | "/" | "%") unary)*
unary       = "-" unary | "try" unary | postfix
postfix     = primary ( "." ident call_args?                 # dot call: x.f(a) is f(x, a); 200.ms
                      | "." int                              # tuple field: result.0
                      | call_args )*
call_args   = "(" (arg ("," arg)*)? ")"
arg         = (ident ":")? expr                              # named args: within: 200.ms
primary     = literal | ident | path call_args?              # Money.cents(500), Charge.fixture(...)
            | TypeName call_args?                            # Ok(x), Some(x), None, Refund(charge: id, ...)
            | "(" expr ("," expr)* ")"                       # group or tuple
            | "[" (expr ("," expr)*)? "]"
            | "if" expr NL block "else" NL block "end"       # if as expression
            | "case" expr NL arm+ "end"
            | "fn" "(" params_untyped? ")" (expr | NL block) "end"   # anonymous, call-argument only
            | "old" "(" expr ")" | "result"
            | "any" "(" typeexpr ")"                         # generators, property only
literal     = int | float | string | "true" | "false"
```

Anonymous functions may appear only as an `arg`. Construction is always by named fields; positional construction does not parse.

## 7. Patterns

```
pattern     = "_" | ident | literal
            | TypeName ("(" pattern ")")?                    # one-field variant, positional: Ok(c), Some(x), Enqueue(request)
            | TypeName "(" ident ":" pattern ("," ident ":" pattern)* ")"   # named fields: WindowExpired(now: n)
            | "(" pattern ("," pattern)* ")"
```

`_` is allowed inside a pattern, never as a whole arm on a closed enum (a semantic rule).

## 8. Comprehensions (never, property)

```
comprehension = "for" gen ("," gen)* ("if" expr)? NL block "end"      # every for closes with end; in never the block is one expr
gen           = ident "in" expr                                # r in Refund.all, x in any(Money)
```

## 9. Processes and supervisors

```
process     = "process" TypeName "(" params? ")" ("mailbox:" int)? NL
              state invariant* message+ update "end" NL
state       = "state" NL state_field+ "end" NL
state_field = ident ":" typeexpr ("=" expr)? NL              # "= expr" required when the type has no zero value
invariant   = "invariant" string NL expr NL "end" NL
message     = "message" TypeName ("(" field_list ")")? (":" typeexpr)? NL   # reply type for ask
update      = "fn" "update" "(" "state" "," "message" ")" NL case "end" NL
supervisor  = "supervisor" TypeName ("(" params? ")")? NL child+ "end" NL
child       = "child" TypeName call_args? "," "restart:" atom ("," "max_restarts:" int "per" expr)? NL   # args are the process's parameters
```

`state` is mutable inside `update` and nowhere else. Restart atoms: `:always`, `:on_crash`, `:never`.

## 10. Tests

```
test        = "test" "rejects"? string NL block "end" NL
            | "property" string NL comprehension "end" NL
assert      = "assert" expr NL                                  # a stmt inside test blocks only
```

## 11. Recipes

```
recipe      = "recipe" TypeName NL intent needs signature_only* test* "end" NL
needs       = "needs" (TypeName ("," TypeName)* | "nothing") NL
signature_only = signature NL contract* "end" NL         # no body
```

## Semantic rules the grammar does not express

- A name binds once per scope; rebinding and unused bindings are errors. Only `var`, `inout`, and `state` places may be assigned.
- `case` is exhaustive. `try` applies only to `Result` and `Option`. `or` on an `Option(T)` yields `T`.
- Function bodies are at most 70 lines, nesting at most 3, parameters at most 6, files at most 500 lines, process state at most 12 fields.
- Every `requires` has a `test rejects` that trips it. Every capability call that can wait passes `within:` and returns a `Result`; `clock.now` and `events.emit` cannot wait and return plain values.
- The `expose` line, the exposed signatures, contracts, `never`, and `verified:` form the spec altitude; changing them is a breaking change. Every name on `expose` must be declared in the module; an undeclared or duplicated name is an error.
- Session 4: `pub` replaced by the `expose` line (Robert: `pub` has OOP vibes). `use A.B{X, Y}` lost the dot before the braces (Robert). Comprehensions close with `end` (Robert: no implicit block ends). Formatter rule: a `for` whose body is a pure expression is rewritten to `map`/`filter`/`reduce`; `for` stays for effects, `try`, `break`, `return`.

## Session 5 decisions (the productions above already reflect them)

Three workers wrote the 50-file corpus from this grammar and recorded where it ran out (`examples/GAPS.md`, the bake-off branches). Claude (Fable) decided each gap here, on Robert's instruction to decide and build; every decision is provisional and **first tested by the interpreter milestone** unless another test is named. Robert overturns any of them on sight.

Grammar bugs found by the corpus, fixed above: `cmp` demanded an operand after `is pattern`; `assert` was missing from `stmt`; `old` was allowed only in `ensures` but `invariant` needs it; `never` allowed only a comprehension, yet `flows(...)` is a bare call; `add` was right-recursive; `params_untyped` was used but never defined; a comprehension body is a block, so `property` can `assert`.

- **Literals.** An integer literal is typed from its uses inside the function (Rust-style inference); with no constraint it is `Int64`. Float literals are `Float64`. Integer types: `Int8`…`Int64`, `UInt8`…`UInt64`; floats `Float32`, `Float64`. `size` on any collection or string is `UInt64`; named conversions (`n.to_u32`) cross widths, never implicit ones.
- **Ranges.** `a..b` excludes `b`, so `0..n` has `n` items.
- **Strings.** `s.size` counts graphemes; `s.bytes` is the byte sequence, `s.bytes.size` counts it.
- **Body value.** The last statement of a body is its value; an `if`/`case` in that position is the expression form.
- **Patterns.** A one-field variant is matched positionally (`Ok(c)`, `Some(x)`, `Enqueue(request)`); variants with two or more fields are matched by name. Construction is always by name. A name bound by `is` inside `assert` is in scope for the rest of the test; inside `if x is Some(v)` it is in scope for the then-block.
- **Anonymous functions.** `fn(acc, x) ... end`; `reduce(start, fn(acc, x) ... end)` is the argument order.
- **Traits.** `Self` names the implementing type in a trait's signatures.
- **Refinements.** A base-type value is checked when it crosses into a refined parameter or field; a failed check is a tripped contract, so `test rejects` covers it.
- **`Type.all`.** In `never` only; means every value of that type the program holds. Tier 2 skips such a `never`, tier 3 checks it in `Mo.Sim`.
- **Deadlines (amends the chapter 2 law).** Only capability calls that can wait take `within:` and return a `Result`; the platform marks which ones. `clock.now` and `events.emit` cannot wait and return plain values, so chapter 4's example stands as written.
- **`try` across error types.** `try` on `Result(T, E1)` inside a function returning `Result(_, E2)` requires every variant of `E1` to exist in `E2` with the same name and fields; the value is re-tagged, nothing is converted. Platform errors are ordinary enums (`Timeout`, `NotFound(id: ChargeId)`). First tested by the checker on the refund module.
- **Time.** `Time` and `Duration` are stdlib types; `10.ms`, `90.days`, `1.minute` are `Duration`; `Time - Time` is `Duration`; `Time + Duration` is `Time`.
- **Platforms.** `mo test` always runs on `Mo.Sim`, `mo run` on the real platform; a module never names its platform, so the `use Mo.Sim` line in chapter 3 is withdrawn. In tests, every capability has a `fixture` constructor (`Clock.fixture()`, frozen; `Fs.fixture()`, empty; `Fs.fixture(delay: 1.minute)`, times out) and `Time.fixture()` is a fixed instant. Narrowing (`fs.scoped(...).read_only`) is pure and keeps the type.
- **Processes.** `state` fields start at the type's zero value (`0`, `""`, `[]`, `None`); a field whose type has no zero (an enum, a refinement excluding zero) must write `= expr`. `Name.start(args)` gives `Handle(Name)`; `h.send(Msg)` is a statement; `h.ask(Msg, within: d)` returns `Result(Reply, AskError)` with `AskError` = `Timeout | Down`. The arm for a message with a reply type evaluates to the reply. Messages from one sender arrive in order. A test may `start` a process without a supervisor; the test runner is its supervisor.
- **Supervisors.** A supervisor takes parameters like a process and passes them on the `child` line: `supervisor Payments(db: Ledger, clock: Clock, events: Events)` … `child RefundQueue(db, clock, events), restart: :always`. The one piece of new syntax in this list; nothing else could say where a child's capabilities come from. First tested by program 1's `main`.
- **`main`.** Robert (Q18): `fn main(platform: Platform)` with no return type, like `update`; exit code 0, or the last `platform.exit(code)`, or 70 on a crash. `Platform` holds `args`, `env`, `stdout`, `stderr`, `fs`, `clock`, `exit`. `mo run file.mo -- args` runs it on `Mo.Server`.
- **Files.** A CapCase module segment maps to a lowercase, hyphen-separated file name: `Basics.AnonymousFunctions` is `basics/anonymous-functions.mo`.
- **Recipes.** A recipe's tests are the file's tests. A `test rejects` inside a recipe must trip a `requires` declared in the recipe (chapter 6's example is corrected).
- **Stdlib names the corpus may assume.** Lists: `size`, `push`, `map`, `filter`, `reduce`, `contains?`, `first`, `last`. Strings: `size`, `bytes`, `starts_with?`. `Fs`: `read(path, within:)` giving `Result(String, FsError)`. Integers: `checked_add`, `saturating_sub`, `wrapping_mul` and their siblings (`checked_` returns `Option`). Everything else is a gap until the stdlib chapter exists.
- **`invariant` reads like `never`.** The block is true when the invariant is broken (`state.done < old(state.done)` under "done never goes backwards"), so the sentence and the block say the same thing. Decided after step 1; first tested by tier 2.
- **Sibling handles.** A supervisor that must give one child another's handle takes it as a parameter (`supervisor Line(sink: Handle(Sink))`, `child Source(sink)`); who starts `Sink` first is `main`'s job. First tested by program 1.
- **Line budget.** A corpus file with two processes may exceed 40 lines; the 70-line function law is the real bound.
- **`for _ in 0..n`.** `_` as the loop binder says the index is unused; the unused-binding law does not fire. Found by Fable testing mailbox bounds in step 4.
- **`use` names functions too.** `use A.B{X, y}` brings the named types and functions into scope by bare name; every name must be on `A.B`'s `expose` line; a bare `use A.B` is `MO0321`. A program is a tree of files under a `mo.root` marker (or the main file's directory); `A.B` is `a/b.mo`. Found by program 2 (toolchain bug 1). First tested by step 7.
- **Program root and module files (step 7).** `mo.root` marks the program root (`examples/programs/mo.root` for the corpus). `MO0322`: a `use` names something not on the module's `expose` line. `MO0323`: the module has no file under the root, or its file declares a different module. A `use` of a module with no file is allowed only when every name is a prelude stand-in.

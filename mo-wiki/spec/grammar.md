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
keyword     = module use intent never expose fn requires ensures var if else end
              case for in break return try and or implies is old result
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
use         = "use" path ("{" TypeName ("," TypeName)* "}")? NL
intent      = "intent" string NL
never       = "never" string NL comprehension NL "end" NL          # comprehension carries its own end
verified    = "verified:" any* NL                # toolchain-owned; hand edits are errors
decl        = struct | enum | typedef | trait | impl | fn | process | supervisor | recipe
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
signature   = "fn" ident "(" params? ")" ":" typeexpr generics?
params      = param ("," param)*
param       = "inout"? ident ":" typeexpr
generics    = "where" TypeName ":" path ("," TypeName ":" path)*
contract    = ("requires" | "ensures") expr NL
```

Contracts sit directly under the signature; a blank line separates them from the body. `result` and `old(expr)` are valid only inside `ensures`.

## 5. Statements

```
block       = stmt*
stmt        = binding | assign | return | for | if_stmt | case | "break" NL | expr NL
binding     = "var"? ident "=" expr NL
assign      = place ("=" | "+=" | "-=") expr NL              # place must root at a var, inout, or state
place       = ident ("." ident)*
return      = "return" expr ("if" expr)? NL                   # trailing if only here
for         = "for" ident "in" expr NL block "end" NL
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
cmp         = range (("==" | "!=" | "<" | "<=" | ">" | ">=" | "is" pattern) range)?
range       = add (".." add)?
add         = mul (("+" | "-") add)*
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
            | TypeName ("(" (ident ":" pattern) ("," ident ":" pattern)* ")")?   # Ok(c), WindowExpired(now: n)
            | "(" pattern ("," pattern)* ")"
```

`_` is allowed inside a pattern, never as a whole arm on a closed enum (a semantic rule).

## 8. Comprehensions (never, property)

```
comprehension = "for" gen ("," gen)* ("if" expr)? NL expr NL "end"    # every for closes with end
gen           = ident "in" expr                                # r in Refund.all, x in any(Money)
```

## 9. Processes and supervisors

```
process     = "process" TypeName "(" params? ")" ("mailbox:" int)? NL
              state invariant* message+ update "end" NL
state       = "state" NL field+ "end" NL
invariant   = "invariant" string NL expr NL "end" NL
message     = "message" TypeName ("(" field_list ")")? (":" typeexpr)? NL   # reply type for ask
update      = "fn" "update" "(" "state" "," "message" ")" NL case "end" NL
supervisor  = "supervisor" TypeName NL child+ "end" NL
child       = "child" TypeName "," "restart:" atom ("," "max_restarts:" int "per" expr)? NL
```

`state` is mutable inside `update` and nowhere else. Restart atoms: `:always`, `:on_crash`, `:never`.

## 10. Tests

```
test        = "test" "rejects"? string NL block "end" NL
            | "property" string NL comprehension NL "end" NL
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
- Every `requires` has a `test rejects` that trips it. Every effectful call passes `within:`.
- The `expose` line, the exposed signatures, contracts, `never`, and `verified:` form the spec altitude; changing them is a breaking change. Every name on `expose` must be declared in the module; an undeclared or duplicated name is an error.
- Session 4: `pub` replaced by the `expose` line (Robert: `pub` has OOP vibes). `use A.B{X, Y}` lost the dot before the braces (Robert). Comprehensions close with `end` (Robert: no implicit block ends). Formatter rule: a `for` whose body is a pure expression is rewritten to `map`/`filter`/`reduce`; `for` stays for effects, `try`, `break`, `return`.

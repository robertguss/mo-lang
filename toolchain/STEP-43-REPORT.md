# Step 43 report: every number in source is validated before a runtime sees it

Worker: Claude Opus 5 (fresh session, Herdr pane, bypass permissions), branch
`toolchain/step-43-numbers`, base `d85154cf`. Brief:
`mo-wiki/plans/interpreter-step-43.md`. Every mo, build, bench and test process
ran under `toolchain/bench/step36/guard.py`. No subagents, no push. **The
unfiltered full suite and Linux were not run; they are the lead's.**

## Commits (RED before GREEN)

| commit     | what                                                                                                                                                         |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `eede860d` | RED: `src/number.zig` tests (checker and end to end), two corpus rejects. **9 of 13 fail** on the base                                                       |
| `dde37f7a` | RED: a finding from the sweep: float literals `1_.5` and `1__0.25` run as `0`. The end-to-end boundary test fails (`1000.5 0 0 -2.5` in both runtimes)       |
| `80c477e1` | GREEN: one reader of numbers (`number.zig`); MO0217 for literals, mailbox bounds, `max_restarts`, `N.unit` Durations, floats; both lowerings read through it |
| `8cffc5b0` | Spec: the mailbox bound's range, one line in `mo-wiki/spec/design-v0/03-semantics.md` (line 34)                                                              |
| `ee4ae80c` | RED: `bench/step37/test_fuzz.py`, the fuzz driver's own tests. **1 failure, 7 errors** on the old driver                                                     |
| `dacc7582` | GREEN: `fuzz.py` refuses bad `--minutes` and `--batch` with exit 2 before setup; a campaign that ran no input exits 1                                        |
| `4fe26b9f` | The checker's last two readers of literal text (tuple position, zero value) go through `number.int`                                                          |
| (this)     | this report                                                                                                                                                  |

## Results (final tree, `4fe26b9f` plus this report)

- `zig build`: **exit 0**.
- `zig build test -Dtest-filter=number: -Dtest-filter=check.test -Dtest-filter=bytecode.test -Dtest-filter=emit_c.test -Dtest-filter=lexer.test -Dtest-filter=parser.test -Dtest-filter=fmt.test -Dtest-filter=vm.test -Dtest-filter=runner.test -Dtest-filter=contracts.test -Dtest-filter=sim.test -Dtest-filter=stdlib.test -Dtest-filter=types.test --summary all`:
  **exit 0, `Build Summary: 5/5 steps succeeded; 121/121 tests passed`**.
- `zig build test -Dtest-filter=number: --summary all` (at `80c477e1`): **exit
  0, `5/5 steps succeeded; 15/15 tests passed`** (26 s, with the builds and
  native runs).
- `python3 -m unittest test_fuzz` in `bench/step37`: **exit 0,
  `Ran 5 tests ... OK`**.
- Corpus, with the new `mo` over all 199 `examples/**/*.mo` files: `mo check`
  passes on all 168 files outside `rejects/`. All 31 rejects, the 2 new ones
  included, fail with exit 1, and each one's first diagnostic is its `# expect`
  line. `mo fmt --check` passes on every file but six rejects that expect an
  MO01xx parse error (`is-inside-comparison`, `old-parameter`,
  `one-line-if-without-else`, `positional-variant`, `unknown-escape`,
  `var-state`). They cannot be formatted because they do not parse, and
  `corpus.zig:515` exempts exactly those. That is unchanged from the base. **The
  stricter checker refuses no corpus program, and no corpus file was edited.**
- No orphaned test binaries or `mo` processes of this worktree after the runs
  (`pgrep`).

## Parts 1 and 2: the probes, and one reader of numbers

`toolchain/src/number.zig` is the one reader:

- `int(raw) ?u64`: the exact value of a literal's digits and underscores, or
  null ("too large") past UInt64's largest. It has no digit buffer and does not
  saturate.
- `float(gpa, raw) ?f64`: underscores are stripped first, then `parseFloat`; the
  result is null when it would be infinity.
- `lowered(raw)` and `loweredFloat(gpa, raw)` are what the lowerings call. They
  may assume the checker passed, and panic with a named message if it did not.

The checker (`checkLiteral`, `check.zig:674`) uses `number.int`, and a null fits
nothing. The saturating `parseInt`s in `bytecode.zig` and `emit_c.zig` are gone,
and so is `parseFloat ... catch 0`. The message prints the literal as written,
underscores and leading zeros included.

The probes, from `audit/evidence/2026-09-19-repo/core/` and
`audit/evidence/2026-09-19/fable-repo-reading/`, were rerun with the new `mo`
through check, run, build and the native binary:

| probe                                              | before (base)                       | after                                                                                    |
| -------------------------------------------------- | ----------------------------------- | ---------------------------------------------------------------------------------------- |
| `oversized` UInt64 18446744073709551616            | check 0, run and binary print it    | check/run/build exit 1, `MO0217 18446744073709551616 does not fit in UInt64`             |
| `leading-zero` UInt8, 32 zeros then 256            | check 0, prints 256                 | exit 1, `MO0217 00000000000000000000000000000000256 does not fit in UInt8`               |
| `lz-int8` Int8, leading zeros then 200             | check 0, prints 200                 | exit 1, MO0217                                                                           |
| `huge` 54 digits as UInt64                         | check 0, prints 2^127-1 (saturated) | exit 1, MO0217                                                                           |
| `u64-plus` (untyped, Int64)                        | MO0217                              | MO0217 (unchanged)                                                                       |
| `literal-control` UInt64 max                       | prints it                           | prints `18446744073709551615`, run and binary                                            |
| `literal-rejected-control`                         | MO0217                              | MO0217 (unchanged)                                                                       |
| `mailbox-overflow` 4294967296                      | check 0, run and build SIGABRT      | exit 1, `MO0217 mailbox: 4294967296 does not fit in a mailbox bound, 1 to 4,294,967,295` |
| `mailbox-huge` 26 digits                           | check 0, SIGABRT                    | exit 1, MO0217                                                                           |
| `mailbox-zero`                                     | check 0, runs                       | exit 1, MO0217 (see part 3)                                                              |
| `mailbox-u32max` 4294967295, `mailbox-control` 100 | ok                                  | ok, run and binary                                                                       |
| `neg-duration`                                     | MO0206                              | MO0206 (unchanged)                                                                       |

In `number.zig`, the checker tests cover every sized type at its largest
(accepted) and one past (refused), each with and without 32 leading zeros, and a
54-digit literal against each type. They cover negative patterns at each signed
smallest (accepted, also with leading zeros) and one below (refused), and `-1`
against each unsigned type. They cover underscores anywhere the lexer takes them
(`2__5_5_`, `18_446_744_073_709_551_615`, `-1_2_8`), and mailbox and
`max_restarts` bounds. The end-to-end tests write the programs to a temp folder.
They require exit 1 and the MO0217 line from `mo check`, `mo run` and `mo build`
for 10 programs. They also build one boundary program and run it both ways. It
uses mailbox 4,294,967,295, max_restarts 4,294,967,294, Int8 `-128` and Int64
`-9_223_372_036_854_775_808` as patterns, UInt64's largest with 32 leading
zeros, `2_5_5`, and `106751991167.days`. Its output is identical under `mo run`
and as a binary.

## Part 3: the mailbox bound

**Decision: 1 to 4,294,967,295, and 0 refused.** This is the lead's default, and
nothing gives 0 a meaning. The spec (design-v0/03 line 34) says only that every
mailbox is bounded and that a full mailbox crashes the sender. With a bound of
0, every send would crash its sender and the process could never take a message.
No corpus program uses 0 (the corpus bounds are 5 to 100,000), and both runtimes
hold the bound in a `uint32_t` (`mo_rt.h:646`, `bytecode.zig`
`Process.mailbox: u32`).

**Code: MO0217, reused.** Its row reads "`<literal> does not fit in <Type>`",
and its why reads "a literal must fit the type it is given, and overflow is
never implicit". A mailbox bound is a literal given a 32-bit count. Reusing the
code keeps `errors.md` (checked by the corpus test) and `check.zig`'s diagnostic
table unchanged, and step 41 is editing that same table now, so a new code could
collide with one of theirs. The message names the range:
`mailbox: N does not fit in a mailbox bound, 1 to 4,294,967,295`. It is checked
in `checkCounts` (`check.zig:703`), called once per item from `checkModule`
(`check.zig:1463`).

**Found with it: `max_restarts`.** It is narrowed with the same `@intCast`
(`bytecode.zig:1370`, `emit_c.zig:1003`), and 4294967296 panicked both paths.
Worse, `max_restarts: 4294967295` checked, and then read as _no budget_, i.e. 3
restarts. The lowering marks a line with no `max_restarts` by `maxInt(u32)`
(`bytecode.none`; `sim.zig:616`, `mo_rt.c:5613`). **Decision: 0 to
4,294,967,294, else MO0217.** 0 keeps its meaning (give up at the first crash,
`sim.zig:1466`). Refusing the mark is a smaller change than giving the runtimes
a separate flag in both languages.

## Part 4: the sweep

Every place the compiler reads a number or size from source text, or narrows one
from a wider integer:

| where                                                                                                                         | what                                                                                                                                       | before                                                                                                       | now                                                                                                              | test                                                                                   |
| ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `check.zig:674` `checkLiteral`                                                                                                | integer literals, expression and pattern                                                                                                   | 32-digit buffer; overflow read as `maxInt(u64)`                                                              | `number.int`, exact                                                                                              | `number:` checker tests, e2e                                                           |
| `bytecode.zig:1702`, `:1813`; `emit_c.zig:1349`, `:1506`                                                                      | integer constants                                                                                                                          | saturating i128 `parseInt`                                                                                   | `number.lowered`                                                                                                 | e2e boundary program                                                                   |
| `bytecode.zig:1703`, `:1814`; `emit_c.zig:1350`, `:1507`                                                                      | float constants and float patterns                                                                                                         | `parseFloat catch 0`: **`1_.5`, `1__0.25`, `-2__5.0` read as 0**; a 400-digit float read as `inf`            | underscores stripped, then parsed; infinity refused with MO0217 (`check.zig:723`, called at `:2561` and `:2798`) | `number: a float literal past Float64's largest`, e2e `float-underscores`, e2e `float` |
| `bytecode.zig:1319`; `emit_c.zig:951`                                                                                         | `mailbox:`                                                                                                                                 | `@intCast` of saturated value: panic                                                                         | checked 1..2^32-1 first, then read                                                                               | `number: a mailbox bound`, e2e                                                         |
| `bytecode.zig:1370`; `emit_c.zig:1003`                                                                                        | `max_restarts:`                                                                                                                            | `@intCast`: panic; 2^32-1 silently read as the default                                                       | checked 0..2^32-2                                                                                                | `number: a restart budget`, e2e `restarts`                                             |
| `check.zig:3117` `dotCall` → `checkUnitLiteral` (`:729`)                                                                      | `N.ms`, `N.seconds`, `N.minute`, `N.days` on a literal (durations and their units; `within:`, `delay:` and `per` windows written this way) | checked; trapped at run time (`9223372036854775807.days`)                                                    | MO0217 `N.days does not fit in Duration`, when N in that unit passes Int64 milliseconds                          | `number: a Duration written as a literal and a unit`, e2e `days`                       |
| `check.zig:2894`                                                                                                              | tuple position `t.N`                                                                                                                       | `parseInt(u32) catch maxInt(u32)`: safe                                                                      | `number.int`; past the arity is MO0208 as before                                                                 | `number: a port and a tuple position`                                                  |
| `bytecode.zig:1944`, `:2007`; `emit_c.zig:1645`, `:1709`                                                                      | tuple position, lowering                                                                                                                   | saturating read, `@intCast`                                                                                  | `number.lowered`; the checker bounds it by the arity                                                             | as above                                                                               |
| `check.zig:1652` `zeroValue`                                                                                                  | a contract's literal folded at check time                                                                                                  | own i128 loop, null on overflow: safe                                                                        | `number.int`                                                                                                     | focused `check.test`                                                                   |
| `bytecode.zig:276-277` `Bounds.intOf`                                                                                         | a `where`'s literal bounds                                                                                                                 | saturating read                                                                                              | `number.int`, and a value past UInt64 states no bound (runs before or after checking, so it cannot panic)        | `bytecode.test` "a where's bounds"                                                     |
| ports (`Net.listen`, `Net.connect`, `Http.listen`, `Http.send`'s `port:`)                                                     | `UInt16` parameters                                                                                                                        | already MO0217 through `checkLiteral`, positional and named                                                  | unchanged                                                                                                        | `number: a port ...` (positional and named `port: 65536`)                              |
| `lexer.zig:337` `unicodeEscape`                                                                                               | `\u{...}`                                                                                                                                  | at most 6 hex digits, ≤ U+10FFFF, no surrogates: MO0101                                                      | unchanged                                                                                                        | existing `lexer.zig:476-478` (7 digits, D800, 110000)                                  |
| repeat counts, budgets                                                                                                        | none in the grammar: no `repeat`, and `property` takes no count; the only "budget" is `max_restarts`                                       | n/a                                                                                                          | n/a                                                                                                              | n/a                                                                                    |
| every other `@intCast` in `check.zig`, `parser.zig`, `lexer.zig`, `caps.zig`, `moves.zig`, `recipe.zig`, `fix.zig`, `ids.zig` | array indices and byte offsets into the source                                                                                             | a source file is read with `.limited(1 << 20)` (`program.zig:101`, `main.zig:223`), so every offset fits u32 | unchanged                                                                                                        | n/a                                                                                    |

**Negating a smallest.** The answer is no. The checker accepts no route that
negates Int64's smallest or Duration's smallest without a runtime trap:

| route                                                        | checker                                      | `mo run`                                                                      | binary              |
| ------------------------------------------------------------ | -------------------------------------------- | ----------------------------------------------------------------------------- | ------------------- |
| Int64 `-n`                                                   | accepts                                      | exit 70, `overflow in -n; value = -9223372036854775808`                       | same, byte for byte |
| Int64 `0 - n`                                                | accepts                                      | exit 70, `overflow in 0 - n; left = 0, right = -9223372036854775808`          | same                |
| Int64 `n * -1`                                               | accepts                                      | exit 70, overflow                                                             | same                |
| Int64 `n.abs`                                                | MO0208: integers have no `abs`               | -                                                                             | -                   |
| Duration `-d`                                                | MO0206                                       | -                                                                             | -                   |
| Duration `0.ms - d`                                          | accepts                                      | exit 70, `overflow in 0.ms - d; left = 0.ms, right = -9223372036854775808.ms` | same                |
| Duration `d * -1`                                            | MO0206: Duration * an integer is not defined | -                                                                             | -                   |
| Int64 `0.wrapping_sub(n)` / `checked_sub` / `saturating_sub` | accept                                       | min / `None` / max, as named                                                  | same                |

The checker tests (`number: Int64's and Duration's smallest ...`) and the
end-to-end test (`int-sub`, `int-mul`, `int-neg`, `dur-sub`: exit 70 in both
runtimes, identical stderr) pin this.

## Part 5: the fuzz driver

`bench/step37/fuzz.py`: `--minutes` goes through `minutes()`, which accepts only
a finite number above 0, and `--batch` through `batch()`, which accepts only a
whole number above 0. argparse reports anything else with exit 2, before
`ensure_tools` or any folder. A campaign whose count of inputs is 0 prints
`no input ran: the campaign tested nothing` and exits 1. The docstring says so.
`test_fuzz.py` has 5 tests with the TLS driver mocked, as in the PR's
`fuzz-controls.py`:

- `--minutes` 0, -1, -0, nan, inf, -inf and `ten` exit 2 with nothing built or
  made.
- `--batch` 0, -3, 1.5 and `many` exit 2 with nothing built or made.
- A budget spent before the first batch exits non-zero.
- A failed batch exits 1.
- A clean campaign with inputs exits 0.

On the fixed driver, the auditor's
`audit/evidence/2026-09-19-repo/fuzz-controls.py` now stops at its second case
with
`fuzz.py: error: argument --minutes: 0 is not a finite number of minutes above 0`,
exit 2. Its asserts describe the old behaviour, which is the defect. I did not
edit it (`audit/` is out of scope).

## Decisions the brief left open

1. **MO0217 for every range, no new code** (part 3 has the reasons). The catalog
   page is unchanged.
2. **Mailbox 1..4,294,967,295; `max_restarts` 0..4,294,967,294** (part 3).
3. **A float literal that would be infinity is refused (MO0217 "... does not fit
   in Float64").** One that rounds to 0 or to a nearby double is accepted, since
   every float literal rounds.
4. **Duration literals.** When the receiver is itself a literal too large for
   Int64, only the literal's own MO0217 is reported, not a second one.
5. **`-128` as an Int8 _expression_ stays refused**
   (`128 does not fit in Int8`), as on the base. In a pattern it is accepted.
   Accepting it in an expression would be a new rule, not a range fix: `-` is an
   operator there, and the VM negates a 128 its type cannot hold. So each signed
   type's smallest is written as `-127 - 1`, or as a pattern. This is
   conservative (refused, never wrong), and I left it for the lead to decide.
6. **The lowerings panic with a named message** if a refused literal ever
   reaches them (`number.lowered`). This follows the brief ("lowering may assume
   the checker has passed"). The alternatives were a silent value or
   `unreachable`.
7. **Spec line:** `mo-wiki/spec/design-v0/03-semantics.md`, line 34:
   "`mailbox: N` in the header, N from 1 to 4,294,967,295, else MO0217". No line
   stated the range before.

## Not done, and noticed outside scope

- **Not run: the unfiltered `zig build test` and Linux** (the lead's). The new
  corpus rejects (`rejects/oversized-literal.mo`, `rejects/mailbox-bound.mo`)
  and `number.zig`'s end-to-end tests are in that suite. I ran them filtered
  here.
- A crash report's source span overruns: `n * -1` inside `"#{n * -1}\n"` is
  reported as `overflow in n * -1}\n");`, identically in both runtimes. The
  clause text runs to the end of the line, not the end of the expression. Not
  touched.
- A `per` window of 0 or less (`per 0.ms`) is an in-range Duration, and the
  checker does not refuse it. It is an expression evaluated at start
  (`sim.zig:637`), not a number narrowed from source. Its meaning is left to the
  lead.
- **Merge notes for step 41.** My `check.zig` changes are local:
  - one import line (`number`)
  - the body of `checkLiteral`
  - three new functions after it (`checkCounts`, `checkFloat`,
    `checkUnitLiteral`)
  - one line in `checkModule`'s item loop and one at the top of `dotCall`
  - the float arms in `pattern` and `infer`
  - `zeroValue`'s int arm and `tuple_index`'s parse

  `types.zig`, `vm.zig`, `caps.zig` and `prelude.zig` are untouched. `root.zig`
  gains one line (`number`).

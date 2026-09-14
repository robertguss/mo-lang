# 2. Laws

A law is a rule the compiler enforces as an error, with no override in the language. The platform is the only escape hatch: anything the laws forbid is written once inside a platform, audited, and exposed as a capability.

## Shape laws (numbers are hypotheses until the corpus measures them)

- A function body is at most **70 lines**. At most **6 parameters** (beyond that, a struct). Nesting depth at most **3**. A process state has at most **12 fields**.
- Projects may tighten these numbers, never loosen them.
- One module per file, file path equals module path, no import cycles.

## Bounding laws

- Loops iterate a finite collection or a range. No `while`, no `loop`; a wait that would need one is a message the runtime delivers (chapter 3, step 20). Recursion is bounded by depth: calls nest at most 10,000 deep, past which the process crashes with a report, in every build. Termination is a proof obligation for `mo prove`, never a syntax rule.
- Every effectful call that can wait carries a deadline (`within:`) and returns a `Result`; the platform marks which calls can wait (`clock.now` and `events.emit` cannot). Timeout is an ordinary error variant the caller must handle. A deadline is a `Duration` or a `Deadline`: inside the `update` arm that answers an `ask`, `reply_by` is the asker's deadline, so a call on it waits only what remains of the ask, and `reply_by.at_most(d)` may tighten it but nothing extends it. Session 5, step 22: after program 1 derived three deadlines by hand as sums of literals and two of the sums were wrong.
- Every mailbox has a declared bound. Overflow is a bug (see chapter 3).
- Integers are explicitly sized. Overflow is a bug and crashes, in every build. Named `checked_`, `saturating_`, `wrapping_` variants state any other intent.

## Honesty laws

- No exceptions, no try-catch, no unwrap, no expect. `try` propagates an error upward and nothing else turns an `Error` or a `None` into a crash.
- Every `Result` and `Option` is consumed. Every `case` is exhaustive. No catch-all arm on a closed enum.
- No warnings. Every diagnostic is an error.
- A function's signature is the complete list of what it can touch. Effects never hide in a value: an anonymous function is a call argument only, never stored or returned, and captures read-only.
- A rebound name, an unused binding, and a hand-edited `verified:` line are all compile errors.
- No default parameters, no implicit numeric conversion, no implicit nil.
- No log statements. The runtime traces calls, arguments, results, and messages for replay. Domain events go through a typed `Events` capability so information flow is checkable.

## Contract laws

- A `never` is a quoted sentence plus a block that evaluates true when the bad thing has happened. Both are mandatory. A `never` that cannot be checked does not compile. A `never` reads a value where it rests: a binding, a field, a return, a message, an assertion; a `var` between two statements of one body is not a value the run held, so chapter 4's `var copy = x` then `copy.field = v` cannot trip it (session 6, round 6).
- Every `requires` has a `rejects` test that trips it. The compiler checks the pair exists.
- Any change to an exposed signature or the `expose` line, a contract, or a `never` is a breaking change, and the toolchain pulls a human in. Agents may change bodies freely.

## The formatter

Ruby offers five ways to write everything. Mo offers one. Column limits, indent width, blank lines, and ordering are the formatter's job and never a choice.

## Session 5 changes

The rules above already reflect this; this section is the changelog.

Claude (session 5, deciding on Robert's instruction): the deadline law now reads "every effectful call that can wait". The corpus showed that `clock.now(within: 10.ms)` returning a `Result` made every clock read a `try`, and chapter 4 had never written it that way. First tested by `Mo.Sim`, which marks which operations wait.

Fable (session 5, night, after the research agenda's Dijkstra and SPARK pages): the recursion line said "structural only, proved terminating", which no stage ever checked; since step 18 the toolchain bounds depth at 10,000 and crashes. The law now says that, and names termination as `mo prove`'s obligation. First tested by program 1.

## Session 6 changes

- **The file-length law is gone** (Robert, 14 Sep 2026, on round 6). Round 6 was the first round where a shape law cost a loop (`MO0302` split a 500-line `board.mo`), and no check in any language earned one; Fable recommended a warning, but the honesty laws forbid warnings, so the law is dropped and `MO0302` retired. The function law stays: jobq's longest function was 20 lines. First tested by round 7. Built by step 27.
- **A `never` reads values at rest** (Robert, 14 Sep 2026). Round 6's logstat tripped a `never` over `Summary.all` on the `var` copy between two field assignments, the idiom chapter 4 prescribes. Built by step 27, first tested by its corpus file and round 7.
- **`state`, `result`, and `old` are ordinary names** everywhere but the positions the grammar reserves (Robert, 14 Sep 2026; step 25 began this for fields). Three of round 6's ten loops were these words refused as parameters and bindings. Chapter 4 and the grammar say which positions stay reserved. Built by step 27.

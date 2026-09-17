---
title: "The closure audit: what direction 31 cost round 7's job queue"
created: 2026-09-14
updated: 2026-09-17
type: deep-dive
tags: [syntax, effects, meta, research]
sources: [plans/control-run-7.md, deep-dives/outside-review-2026-09-14-response.md, spec/design-v0/03-semantics.md, spec/design-v0/09-stdlib.md]
confidence: medium
---

# The closure audit: what direction 31 cost round 7's job queue

The outside review of 14 Sep ([[outside-review-2026-09-14]]) predicted that direction 31 (an anonymous function is a call argument only: never stored, returned, or capturing a `var`) would cost programs in shapes no loop ever records, and its reply asked for two columns: the mechanical count of sites that exist only because a closure could not be stored or returned, and a judgment column of sites shaped at a coarser altitude than a fluent Elixir or Rust author would choose. Fable had a reader (a fresh general-purpose session, read-only) go through round 7's Mo job queue, `../mo-lang-control7-mo/examples/programs/jobq/`, all seven modules, 2,843 non-blank lines, on 14 Sep evening.

## The count

71 anonymous functions, every one a call argument to a stdlib combinator (`map`, `filter`, `reduce`, `find`, `sort_by`, `fold_lines`), none capturing a `var`, none wanted as a value.

**Mechanical column: 17 sites, 12 lines, 0.4 percent of the program.**

| shape | sites | cost |
|---|---|---|
| eta-expansion, `fn(j) shown(j) end` where `.map(shown)` would do, because a named function cannot be passed by name | 13 | 2 lines in all |
| a `Bool` flag and a dead argument choosing between two moves (`settled(..., failing:)`), where a passed move would do | 1 pair | 3 lines |
| a fold accumulator struct (`Replay`, five fields) because a `fold_lines` lambda may capture only read-only values | 1 | 7 lines against a Rust `for` with mutable locals; 0 against Elixir |
| the queue holding worker handles and sending `Done`, where a callback language would store closures | 1 | 17 lines if charged; 0 against Elixir (the GenServer `from`/`reply` idiom) or Rust (a oneshot channel); not charged |

**Judgment column (Fable's reader's, marked as such): 3 sites, about 18 lines**, all of which Mo's stdlib already covers: `Map.update(key, default, fn)` unused four times in `board.mo` and twice in `store.mo` where get-page, set-entry, set-page is written out by hand; an `Option` flatten hand-rolled in `main.mo`. A vocabulary gap in the author, not a rule in the language. About 50 further lines of coarse shape (five handlers repeating the method and bearer guards, a flush-then-reset block three times, a `compact` that copies `rewritten` whole, a chunked recursion around `find`) are not closure-shaped: a named helper, a `try`, or a lazy range fixes each.

## What the audit found instead

The constraint shaping this program is not d31's storing ban but the sentence in `09-stdlib.md`: "a signature cannot name a function type", so only stdlib combinators can take a function and a user's function never can. And `03-semantics.md` says the opposite in the same breath as d31: "Named functions are first-class values and carry their capabilities in their own signatures." The toolchain implements neither reading fully: a named function cannot be passed by name anywhere (hence the 13 eta-expansions), and no signature can take one.

## Reading

Direction 31 cost this program 12 lines. The bet the review said would be lost is, on this program, won: closures as values were never wanted, and the actor idiom carried the one place a callback would have lived. The audit is one program by one worker; the ledger (program 6) is the second sample.

The contradiction in the spec is the finding. Fable's recommendation, a row for Robert: a named function may be passed by name where an anonymous function goes (`xs.map(shown)`), which is what chapter 3 already says and what removes the 13 sites; a signature still cannot name a function type, so d31's rule stands and nothing new can be stored or returned. Chapter 3's sentence is narrowed to that.

## Related
- [[outside-review-2026-09-14-response]]
- [[control-run-7]]
- [[d31-effects-never-hide-in-a-value]]
- [[decision-log]]

---
title: "Safety-critical coding standards"
created: 2026-09-13
updated: 2026-09-13
type: concept
tags: [research, laws, verification]
sources: [raw/research-runs/2026-09-13-manifestos-safety-reliability.pplx.md]
confidence: high
---

# Safety-critical coding standards

Tiger Style and the Power of Ten already have a page. This one covers the wider family of rulebooks those two were distilled from: JPL's full standard, MISRA C, CERT C, DO-178C, Ravenscar and SPARK, seL4, Cleanroom, and the static-allocation rulebooks. The interest is less in individual rules than in how each standard decides which rules are binding.

## Levels of compliance, not one rulebook

The JPL Institutional Coding Standard is organised into six Levels of Compliance — LOC-1 Language Compliance, LOC-2 Predictable Execution, LOC-3 Defensive Coding, LOC-4 Code Clarity, LOC-5 MISRA Shall Rules, LOC-6 MISRA Should Rules — across 120 rules ([JPL standard](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf)).

Where a rule sits matters. The bounding rules are "shall" rules in LOC-2. The shape numbers are "should" rules in LOC-4: a function "should be no longer than 60 lines of text" and "should be declared with no more than 6 parameters" ([JPL standard](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf)).

Judgment: the document Mo's shape laws descend from already treats shape as advisory and bounding as mandatory.

## Three categories and a deviation record

MISRA's machinery is the most reusable thing here. Mandatory guidelines admit no deviation; Required guidelines need "a formal deviation"; Advisory guidelines "should be followed as far as is reasonably practical" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)). The ratchet is one-way: "An organization or project may choose to treat any required guideline as if it were mandatory" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)). Deviations are recorded artifacts with fixed fields, alongside an enforcement plan and a re-categorization plan ([MISRA Compliance:2020](https://misra.org.uk/app/uploads/2021/06/MISRA-Compliance-2020.pdf)).

Every MISRA rule also carries two analysis labels. A rule is decidable if a program can answer compliance "with a 'yes' or a 'no' in every case" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)), and separately is checkable per translation unit or only across the whole system ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)).

Judgment: these two labels predict which Mo tier a law can live in. Only decidable, single-unit rules belong in a 50 ms `mo check`.

## Loops: nobody banned the infinite one

Three standards independently permit the non-terminating loop and constrain the bounded one instead.

JPL requires a statically determinable upper bound but allows an intentionally non-terminating loop when annotated with `/* @non-terminating@ */` ([JPL standard](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf)). MISRA Rule 14.2 requires a well-formed `for` loop with exactly one counter not modified in the body, then exempts the empty form "so as to allow for infinite loops", and Rule 14.3 adds that "Invariants that are used to create infinite loops are permitted" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)).

Ravenscar inverts it entirely: under `No_Task_Termination`, "all tasks are non-terminating", and "real-time tasks normally have an infinite loop as their last outermost statement" ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

Astrée supports annotations "for supplying external knowledge and fine-tuning the analysis precision for individual loops" ([AbsInt Astrée](https://www.absint.com/astree/index.htm)) — the industrial version of JPL's comment.

## Risk scoring instead of argument

CERT C scores every rule on severity, likelihood and remediation cost, each 1 to 3, producing a priority from 1 to 27 in three levels; remediation cost derives from whether a violation is detectable and repairable ([CERT C](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/front-matter/introduction/how-this-coding-standard-is-organized/)). Undetected signed overflow scores High/Likely and lands at priority 18, level L1 ([INT32-C](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/rules/integers-int/int32-c/)).

Google's meta-rule points the same way: "The benefit of a style rule must be large enough to justify asking all of our engineers to remember it" ([Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html)). Their exceptions ban is defended "not predicated on philosophical or moral grounds, but practical ones" ([Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html)).

## A concurrency subset you can analyse

Ravenscar is a language subset requested by one pragma and defined in the Ada standard, expanding to restrictions including `No_Task_Hierarchy`, `No_Task_Allocators`, `No_Abort_Statements`, `No_Select_Statements`, `Simple_Barriers`, `Max_Protected_Entries => 1` and `Max_Entry_Queue_Length => 1` ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

```ruby
# Ravenscar's queue bound is 1, enforced at runtime by failing the caller.
# Mo's bounded mailbox is the same mechanism with a larger constant.
```

The queue bounds exist to avoid "the associated non-determinism of the length of the waiting time in the queue" and to enable "a tight time bound" ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)). `No_Relative_Delay` bans duration-based delays because a relative delay "exhibits non-determinism with respect to the absolute time at which the delay expires" when preemption intervenes, while "the delay_until_statement is deterministic" ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

SPARK excludes side-effecting functions, aliasing and backward `goto`, requires function termination as a proof obligation, and reports violations as errors ([SPARK 2014 User's Guide](https://docs.adacore.com/spark2014-docs/html/ug/en/source/language_restrictions.html)).

Ada's general mechanism, `pragma Restrictions`, "expresses the user's intent to abide by certain restrictions", and a partition obeys a restriction if the pragma applies to any unit in it ([Ada RM 13.12](https://www.adaic.org/resources/add_content/standards/05rm/html/RM-13-12.html)). The page does not state that restrictions can only remove features — n.a.

## Proof has a price and a CI gate

seL4's functional correctness took about 12 person-years, the whole initial project about 25, from roughly 12 people over 4 years ([NICTA full text](https://trustworthy.systems/publications/nicta_full_text/8066.pdf)), with later security proofs far cheaper on that base — integrity under 8 person-months ([NICTA full text](https://trustworthy.systems/publications/nicta_full_text/8066.pdf)). Klein's cost figure is "<$400 per line of code" with ">20 lines of proof per line of C" ([Heiser](https://microkerneldude.org/2016/06/16/verified-software-can-and-will-be-cheaper-than-buggy-stuff/)).

The governance rule is one line: "Commits to the mainline kernel source are only allowed if they do not break proofs" ([seL4 whitepaper](https://sel4.systems/About/seL4-whitepaper.pdf)). The proofs assume correct hardware, a specification matching intent, and a correct theorem prover, and do not cover timing channels ([seL4 whitepaper](https://sel4.systems/About/seL4-whitepaper.pdf)).

## Cleanroom's numbers

Cleanroom substitutes "human mathematical verification in place of program debugging" ([Mills et al.](http://www.cs.toronto.edu/~chechik/courses07/csc410/mills.pdf)), reporting that "more than 90 percent of total product defects were found before first execution" and that developers "essentially never resorted to debugging (less than 0.1 percent of the cases)" ([Mills et al.](http://www.cs.toronto.edu/~chechik/courses07/csc410/mills.pdf)).

The survey data: a weighted average of 2.3 errors per KLOC against a traditional baseline of 25 to 35 or more, with one drive-firmware comparison where unit testing took 1.5 person-weeks and found 7 errors while correctness verification took 1.5 hours and found 10 ([DTIC ADA326485](https://apps.dtic.mil/sti/tr/pdf/ADA326485.pdf)).

Judgment: these are uncontrolled industrial comparisons with selection effects. The direction is credible; the magnitudes are soft.

The design heuristic is the durable part: "If a program looks hard to verify, it is the program that should be revised" ([Mills et al.](http://www.cs.toronto.edu/~chechik/courses07/csc410/mills.pdf)).

## What Mo could take

| idea | maps to | status |
|---|---|---|
| Six levels of compliance a module declares | [[q08-verification-tiers]] | new idea for Mo |
| Mandatory / required / advisory with recorded deviations | [[q12-law-numbers]] | new idea for Mo |
| Projects may promote a rule, never demote it | [[q16-escape-hatch]] | new idea for Mo |
| Label each law decidable and single-unit or system | [[q09-compiler-diagnostics]] | new idea for Mo |
| Score each law on severity, likelihood, remediation cost | [[d04-style-rules-become-laws]] | strengthens Mo |
| Shape numbers are "should" rules at JPL | [[d04-style-rules-become-laws]] | contradicts Mo |
| Annotated non-terminating loop instead of a ban | [[d17-mandatory-deadlines]] | contradicts Mo |
| Termination as a proof obligation, not a syntax rule | [[d32-proving-is-a-separate-tool]] | strengthens Mo |
| Absolute deadlines instead of relative delays | [[d17-mandatory-deadlines]] | strengthens Mo |
| Bounded entry queues with runtime failure | [[d33-bounded-mailboxes]] | already in Mo |
| No asynchronous abort of another task | [[d14-processes-are-the-only-identity]] | new idea for Mo |
| Breaking a proof fails the build | [[d32-proving-is-a-separate-tool]] | new idea for Mo |
| Restrictions bind a whole partition | [[d30-supply-chain-security]] | new idea for Mo |
| Revise the program when it is hard to verify | [[d03-source-carries-its-evidence]] | already in Mo |

## Related

- [[tiger-style-and-power-of-ten]]
- [[spark-ada-and-dafny]]
- [[q08-verification-tiers]]
- [[q12-law-numbers]]
- [[d04-style-rules-become-laws]]
- [[prompts-research-agenda-2026-09]]

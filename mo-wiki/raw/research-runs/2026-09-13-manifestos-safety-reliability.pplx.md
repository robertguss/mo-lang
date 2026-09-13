---
tool: Perplexity Computer
prompt: prompts-research-agenda-2026-09 / R6 (manifestos, safety and reliability)
run: 2026-09-13
run_by: Perplexity Computer, at Robert's request
sha256: f38c6d04841e3cfc11c9cb96227024d47408274b8084de4d3689387c2b697ec1
---
# R6 — Safety-critical coding standards and reliability philosophies beyond Tiger Style and Power of Ten

Research run, 2026-09-13. Every rule, number and quotation below comes from a primary source fetched during this session; the URL follows the claim. Where a claim could not be confirmed from a primary source it is marked "n.a." rather than guessed. "Judgment:" marks my own reasoning, never a source's claim.

Tiger Style and the Power of Ten are deliberately not re-summarised here; both already have a Mo wiki page. This dossier is the surrounding literature: the full standards those two documents were distilled from, the standards that took different turns, and the testing philosophies that decide whether any of it is working.

---

## Part 1 — Safety-critical coding standards

### 1. JPL Institutional Coding Standard for the C Programming Language

#### Origin and structure

The Power of Ten is the ten-rule popularisation; the JPL Institutional Coding Standard is the thing itself. The standard is organised into six Levels of Compliance, described in the document as LOC-1 "Language Compliance", LOC-2 "Predictable Execution", LOC-3 "Defensive Coding", LOC-4 "Code Clarity", LOC-5 "MISRA Shall Rules" and LOC-6 "MISRA Should Rules", carrying 120 rules in total ([JPL Institutional Coding Standard for the C Programming Language](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf)).

Judgment: this layering is the most directly transferable structural idea in the whole dossier, and Mo does not have it. Mo has verification tiers (`mo check`, `mo test`, `mo test --sim N`) that separate how hard you look, but it does not separate how much of the rulebook a given module has signed up to. JPL separates both axes. A module can be LOC-4 clean while a driver sits at LOC-2, and the level is a declared, checkable property rather than a per-rule waiver argument.

#### The rules a language designer should read

The bounding rules are the ones Mo turns into laws, and the JPL wording is more careful than the Power of Ten's compression suggests. Rule 3 requires that "all loops shall have a statically determinable upper-bound on the maximum number of iterations" and that a loop that is intentionally non-terminating "shall be annotated with the comment `/* @non-terminating@ */`" ([JPL standard](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf)).

Judgment: that annotation is the critical detail. JPL did not ban unbounded loops. It banned unannotated ones. The scheduler loop, the event loop and the top-level task body are all permitted, provided the author states in a machine-greppable form that this loop is meant to run forever, at which point the static analyser stops trying to bound it and a reviewer knows to check it by other means. This is the single strongest piece of evidence in Part 1 against Mo's unconditional ban on `while`, and it comes from the exact document Mo's while-ban traces back to.

Rule 5 forbids dynamic memory allocation after task initialisation ([JPL standard](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf)). Rule 11 states that "the goto statement shall not be used" and extends the same prohibition to `setjmp` and `longjmp` ([JPL standard](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf)) — that is, the ban is not aesthetic hostility to `goto` but hostility to non-local control transfer generally, which is the same argument Mo makes against exceptions.

Rule 16 requires the use of assertions, and the standard reports a measured assertion density from a real flight project: "The MSL flight software has an assertion density of 2.26%" ([JPL standard](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf)).

Rule 25 is the shape rule: a function "should be no longer than 60 lines of text" and "should be declared with no more than 6 parameters" ([JPL standard](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf)).

Judgment: note the modal verb. In the JPL document these numeric shape limits are "should" rules, sitting in the clarity level, not the predictable-execution level. The bounding rules are "shall". The standard itself draws exactly the line that Mo's dispute 1 is arguing about, and it draws it in favour of shape-as-policy and bounding-as-law.

#### Evidence of effect: Mars Code

Holzmann's account of the Curiosity flight software is the best published evidence that these rules were actually applied rather than merely written down. The review process he describes ran "145 code reviews" between 2008 and 2012, producing "about 10,000 peer comments and 30,000 tool reports", of which "84% led to code changes" and "12.3%" of tool reports were disagreed with ([Mars Code, CACM](https://cacm.acm.org/research/mars-code/)).

The model-checking practice is also concrete: the team used Spin and Modex, ran verification jobs across "120 parallel tasks", and reduced a "45,000-line module" to a "1,600-line Spin model" for exhaustive checking ([Mars Code](https://cacm.acm.org/research/mars-code/)). Assertions were not stripped for flight; they were left enabled and wired into the spacecraft's fault-protection response ([Mars Code](https://cacm.acm.org/research/mars-code/)).

Judgment: the assertions-enabled-in-flight decision is the opposite of SQLite's (see §13) and the tension between the two is real. JPL keeps assertions on because on a spacecraft a detected-and-safed fault is survivable and an undetected corrupt state is not; SQLite turns them off because a library crashing the host application is worse than continuing. Mo's `never` clauses inherit the JPL position by default, and that is defensible, but the SQLite counter-argument deserves to be written down rather than assumed away.

There is no defect-rate-per-KLOC figure in either the standard or the Mars Code article that would let anyone attribute a measured defect reduction to the rules. The evidence is process evidence, not outcome evidence.

---

### 2. MISRA C

#### The category system and the deviation process

MISRA C's contribution to this dossier is not its individual rules but its machinery for living with rules. Guidelines are categorised. For Mandatory guidelines, "C code which is claimed to conform to this document shall comply with every mandatory guideline — deviation from mandatory guidelines is not permitted" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)). For Required guidelines, code "shall comply with every required guideline, with a formal deviation required ... where this is not the case" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)). Advisory guidelines "are recommendations", and "the status of 'advisory' does not mean that these items can be ignored, but rather that they should be followed as far as is reasonably practical" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)).

Crucially, the ratchet only turns one way: "An organization or project may choose to treat any required guideline as if it were mandatory", and likewise any advisory guideline as required or mandatory ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)).

MISRA Compliance:2020 makes the surrounding process explicit: a project needs a guideline enforcement plan, a recorded re-categorization plan, deviation records with a fixed set of required fields, and a compliance summary; the additional category "Disapplied" exists for guidelines a project has formally decided not to apply ([MISRA Compliance:2020](https://misra.org.uk/app/uploads/2021/06/MISRA-Compliance-2020.pdf)).

Judgment: this is Mo's dispute 1 solved by someone else, thirty years earlier, in a domain with higher stakes and auditors. The answer MISRA reached is that a rulebook needs three tiers and a paper trail, not one tier and an escape hatch. Mo's current design has laws plus `q16-escape-hatch`; what it lacks is the re-categorization plan — the ability for a project to say "in this repository, the advisory shape limits are mandatory" — and the deviation record as a first-class artifact the compiler emits rather than a comment the agent writes.

#### Decidable versus undecidable

MISRA classifies every rule as decidable or undecidable, where "a rule is decidable if it is possible for a program to answer the question with a 'yes' or a 'no' in every case and undecidable otherwise", and notes a rule is likely undecidable if detecting violations depends on run-time properties such as "the value that an object holds" or "whether control reaches a particular point in the program" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)). The consequences are spelled out: for a decidable rule, "a reported violation ... indicates a real violation" and "no reported violation ... indicates there are no violations"; for an undecidable rule, a report "may not necessarily indicate a real violation" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)).

A parallel axis, analysis scope, marks each rule as checkable per "Single Translation Unit" or only across the whole "System", and "all undecidable rules need to be checked on a 'System' basis" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)).

Judgment: Mo promises `mo check` in under 50 ms. That promise is only keepable for decidable, single-translation-unit rules. Mo should adopt MISRA's two labels verbatim as metadata on every law, because they predict which tier a law can live in: decidable + single-unit goes in `mo check`; undecidable or system-scope goes in `mo test` or the prover. Shipping a law without that label is how a fast checker silently becomes a slow one.

#### The specific rules Mo should read

Recursion: Rule 17.2, Required, Undecidable, System — "Functions shall not call themselves, either directly or indirectly", because "recursion carries with it the danger of exceeding available stack space" and "unless recursion is very tightly controlled, it is not possible to determine before execution what the worst-case stack usage could be" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)).

Dynamic memory: Dir 4.12, Required — "Dynamic memory allocation shall not be used", covering the standard library and third-party packages, with the rationale listing unpredictable allocation failure and "a high variance in the execution time required to perform allocation or deallocation" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)). Rule 21.3 is the decidable, single-unit instance of it: `calloc`, `malloc`, `realloc` and `free` "shall not be used" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)).

Error handling: Dir 4.7, Required — "If a function returns error information, then that error information shall be tested", and the error "shall be tested in a meaningful manner" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)). Rule 17.7, Required and decidable — "The value returned by a function having non-void return type shall be used", with an explicit `(void)` cast as the compliant way to discard ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)).

Unions: Rule 19.2, Advisory — "The union keyword should not be used", because reading a different member than was written yields unspecified or implementation-defined values ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)).

Loops: the loop rules are the most instructive. Rule 14.2 requires that "a for loop shall be well-formed", with a three-clause amplification that the first clause may only set the loop counter, the second may have "no persistent side effects" and may use only the counter and boolean control flags, and the third may only modify the counter; there is exactly "one loop counter in a for loop, which shall not be modified in the for loop body" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)). Rule 14.1 bans essentially-floating loop counters because "accumulation of rounding errors may result in a mismatch between the expected and actual number of iterations" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)). Rule 14.3 forbids invariant controlling expressions — but with an explicit carve-out: "Invariants that are used to create infinite loops are permitted" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)). Rule 14.2's exception says the same thing from the other side: "All three clauses may be empty, for example `for ( ; ; )`, so as to allow for infinite loops" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)).

Judgment: MISRA, like JPL, does not ban unbounded loops. It constrains the shape of bounded ones tightly — much more tightly than Mo does, since Mo's `for x in collection` is already well-formed by construction — and then explicitly legalises `for(;;)` and `while(true)`. Two of the three canonical safety-critical C standards agree that the right move is "make the bounded form the ergonomic default and make the unbounded form explicit", not "make the unbounded form unsayable".

Rule 14.4 is worth one more note: controlling expressions of `if` and iteration statements "shall have essentially Boolean type" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)). Mo gets this free from its type system.

#### Versions and scale

MISRA C:2012 comprises 17 directives and 156 rules ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)). It was published on 18 March 2013; MISRA C:2023 was released in April 2023 and adds C11/C18 coverage; MISRA C:2025 followed in March 2025 ([MISRA C:2023 release note](https://misra.org.uk/misra-c2023-released/), [MISRA C overview](https://misra.org.uk/misra-c/)). Addendum 3 maps MISRA C against CERT C and reports coverage of 99 of 99 CERT C guidelines ([MISRA C:2023 Addendum 3](https://misra.org.uk/app/uploads/2025/03/MISRA-C-2023-ADD3-CERT.pdf)).

No controlled study attributing defect-rate reduction to MISRA conformance was located from a primary MISRA source in this session. n.a.

---

### 3. CERT C Secure Coding Standard

#### The shape of the standard

CERT C splits its content into rules and recommendations. The standard is organised into "17 rules" chapters and "17 recommendations" chapters, and the distinction is normative: rules are requirements whose violation is a defect, recommendations are guidance ([SEI CERT C Coding Standard](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/)). Conformance can be assessed with SCALe ([SEI CERT C](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/)).

#### The risk metric

This is the part worth stealing. Every rule carries three scored attributes — severity, likelihood and remediation cost — each on a 1-to-3 scale, and their product yields a priority from 1 to 27, bucketed into three levels: L1 covers priorities 12, 18 and 27; L2 covers 6, 8 and 9; L3 covers 1 through 4 ([How this coding standard is organized](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/front-matter/introduction/how-this-coding-standard-is-organized/)). Remediation cost is itself derived from two binary axes, whether the violation is Detectable and whether it is Repairable ([How this coding standard is organized](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/front-matter/introduction/how-this-coding-standard-is-organized/)).

Worked examples: INT32-C, on ensuring signed integer operations do not overflow, scores High severity, Likely likelihood, "Not detectable" and "Repairable" — priority 18, level L1 ([INT32-C](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/rules/integers-int/int32-c/)). ARR30-C, on not forming out-of-bounds pointers or array subscripts, scores High severity and Likely likelihood — priority 9, level L2 ([ARR30-C](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/rules/arrays-arr/arr30-c/)).

Judgment: CERT's scheme answers the question Mo's dispute 1 keeps stumbling over, which is not "law or policy?" but "on what evidence?". CERT forces each rule to declare, in public, how bad a violation is, how often it happens, and how expensive the fix is. A rule that is cheap to detect, cheap to repair and catastrophic when violated is obviously a law. A rule that is undetectable and expensive to repair for a low-severity issue obviously is not. Mo's `q12-law-numbers` page should carry a three-column score per law rather than a paragraph of justification, and the detectability axis in particular is the one that should decide whether a rule belongs in `mo check`.

The CERT integer position also validates Mo's choice of sized ints with crashing overflow: CERT rates undetected signed overflow at the top priority band it uses ([INT32-C](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/rules/integers-int/int32-c/)), and Mo removes the whole class by making overflow a crash rather than a silent wrap.

No published defect-rate study from CERT's own materials was located in this session. n.a.

---

### 4. DO-178C and MC/DC

#### What the levels require

The clearest primary statement of the structural-coverage ladder is the NASA MC/DC tutorial, which reproduces the DO-178B definitions that DO-178C carries forward. At Level A the objective is modified condition/decision coverage; Level A and B require decision coverage; Levels A, B and C require statement coverage ([A Practical Tutorial on Modified Condition/Decision Coverage, NASA](https://ntrs.nasa.gov/api/citations/20010057789/downloads/20010057789.pdf)).

The definition itself: MC/DC requires that "every point of entry and exit in the program has been invoked at least once, every condition in a decision in the program has taken all possible outcomes at least once, every decision in the program has taken all possible outcomes at least once, and each condition in a decision has been shown to independently affect that decision's outcome" ([NASA MC/DC tutorial](https://ntrs.nasa.gov/api/citations/20010057789/downloads/20010057789.pdf)). The cost is near-linear rather than exponential: for a decision with n conditions, MC/DC can generally be satisfied with a minimum of n+1 test cases ([NASA MC/DC tutorial](https://ntrs.nasa.gov/api/citations/20010057789/downloads/20010057789.pdf)).

#### The traceability discipline

The more important half for Mo is that structural coverage in DO-178 is not a target you chase directly. Coverage is measured while executing requirements-based tests; the tests come from requirements, and structural coverage analysis then asks which code was not exercised by those requirements-based tests ([NASA MC/DC tutorial](https://ntrs.nasa.gov/api/citations/20010057789/downloads/20010057789.pdf)). Unexercised code is then resolved as one of a small set of categories — including dead code, which must be removed, and deactivated code, which must be shown to be disabled in the target configuration ([NASA MC/DC tutorial](https://ntrs.nasa.gov/api/citations/20010057789/downloads/20010057789.pdf)).

Judgment: this is the strongest external validation of Mo's rule that every `requires` needs a `test rejects`. DO-178 does not accept a coverage number on its own; it accepts a coverage number produced by tests that trace to requirements, and it treats leftover coverage as a requirements defect first and a testing defect second. Mo's `requires`/`rejects` pairing is a miniature of exactly that: the contract is the requirement, the rejection test is the requirements-based test, and a contract with no rejection test is code with no traced requirement.

The gap Mo has is the other direction. DO-178 also asks the inverse question — is there code with no requirement? — and Mo currently has no analogue. A `verified:` line that recorded which contracts a given function's tests actually exercised, and flagged functions whose behaviour no contract constrains, would close that loop. The DO-178 machinery for dead and deactivated code is the same idea applied to a codebase rather than a function.

---

### 5. Ravenscar, SPARK, and Ada's pragma Restrictions

#### Ravenscar as a profile, not a style guide

Ravenscar is the best-worked example in this dossier of the thing Mo is: a language subset chosen so that static analysis becomes possible, expressed as compiler-enforced restrictions rather than review guidance. It is requested with a single configuration pragma, `pragma Profile(Ravenscar);`, and is defined in the Ada standard itself ([Guide for the Use of the Ada Ravenscar Profile in High Integrity Systems, ISO/IEC JTC1/SC22/WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

The profile expands to a fixed list of restrictions, including `No_Task_Hierarchy`, `No_Task_Allocators`, `No_Task_Termination`, `No_Abort_Statements`, `No_Select_Statements`, `No_Requeue_Statements`, `No_Relative_Delay`, `No_Dynamic_Priorities`, `No_Implicit_Heap_Allocations`, `No_Local_Protected_Objects`, `Simple_Barriers`, `Max_Entry_Queue_Length => 1`, `Max_Protected_Entries => 1` and `Max_Task_Entries => 0`, together with `pragma Task_Dispatching_Policy(FIFO_Within_Priorities)`, `pragma Locking_Policy(Ceiling_Locking)` and `pragma Detect_Blocking` ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

#### Why each restriction exists

The rationales are stated per restriction, and they read like a design review of Mo's process model.

Static task set: the restrictions "ensure that the set of tasks and interrupts to be analysed is fixed and has static properties (in particular, base priority) after program elaboration", because "if a variable task set were to exist, then it would be impractical to perform static timing analysis of the program" ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)). `No_Task_Hierarchy` means tasks "may only be created at the library level" ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

Non-termination: under `No_Task_Termination`, "all tasks are non-terminating", which "attempts to mitigate the hazard that may be caused by tasks terminating silently", and the guide notes plainly that "real-time tasks normally have an infinite loop as their last outermost statement" ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

Judgment: that sentence is a third independent safety-critical standard saying the infinite loop is the normal, correct shape for a long-lived task. Ravenscar goes further than JPL or MISRA — it does not merely permit the non-terminating loop, it mandates that tasks not terminate. Mo's processes are exactly these long-lived tasks, and Mo's ban on `while` means a Mo process's outer loop must be expressed as recursion or as a runtime-provided receive loop. That is a legitimate design choice, but it is a choice Mo makes alone against the practice of the field.

No abort: `No_Abort_Statements` "ensures that tasks cannot be aborted", which "significantly reduces the size and complexity of the run-time system" and "reduces non-determinacy" ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

Bounded queues: `Max_Protected_Entries => 1` and `Max_Entry_Queue_Length => 1` together "ensure that at most one task can be suspended waiting on a closed entry barrier for each protected object", which "avoids the possibility of queues of task calls forming on an entry, with the associated non-determinism of the length of the waiting time in the queue" and "enables a tight time bound on the epilogue code to be determined" ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)). Violation of the queue-length restriction "results in the raising of the Program_Error exception at the point of the call" — that is, it is a runtime check, not a static one ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

Judgment: Ravenscar's bound is 1, and it is enforced at runtime by failing the caller. Mo's bounded mailboxes are the same mechanism with a larger constant. The Ravenscar rationale tells you what the bound is for — a computable blocking time — which suggests Mo's mailbox bound should be justified by, and ideally derived from, a latency budget rather than picked as a round number.

Deadlines: `No_Relative_Delay` bans relative delays in favour of `delay_until`, because a relative delay "exhibits non-determinism with respect to the absolute time at which the delay expires in the case when the delaying task is preempted after calculating the required relative delay, but before actual suspension occurs", whereas "the delay_until_statement is deterministic" ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

Judgment: this is the sharpest primary-source evidence found anywhere in this run for Mo's dispute 5. Ravenscar bans the duration form and requires the absolute-instant form, for a reason that is purely about composition and preemption. Mo's `within: 500ms` is a duration — a relative delay by another name — and every nested `within:` restarts the clock from wherever the caller happened to be when it got there. Ravenscar's answer is to make the deadline an absolute instant computed once and passed down. See §18 for the Go and gRPC side of the same argument.

Deadlock: the profile "assures absence of deadlocks by requiring use of an appropriate locking policy", namely ceiling locking, which "requires a ceiling priority to be assigned to each protected object that is no lower than the highest priority of all its calling tasks", eliminating "the unbounded priority inversion problem" ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

The payoff is stated directly: the profile is "restricted to meet the real-time community requirements for determinism, schedulability analysis and memory-boundedness", and eliminating features such as "abort, asynchronous transfer of control, multiple entry queues each with a list of waiting tasks, requeue statements, task hierarchy and dependency, and finalization actions of local protected objects" makes it "possible to create not only a small and highly efficient run-time system implementation, but also one that is amenable to the forms of verification applicable to sequential code" ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

The guide also states the general case for this whole dossier as cleanly as anyone has: "Static analysis as a technology has a fundamental advantage over dynamic testing. If a program property is shown to hold using static analysis, then the property is guaranteed for all scenarios. Testing, on the other hand, may demonstrate the presence of an error, but the correct execution of a test only indicates that the program behaves correctly for the specific set of inputs provided by the test" ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

One acknowledged cost: a Ravenscar runtime "can monitor the execution time of tasks, but it does not support the sharing of a CPU budget within a group of tasks. Neither does it require a handler to be executed if a task executes beyond a defined level of execution time. This simplifies the runtime but makes it harder to construct programs that can recover from timing errors" ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

Judgment: Mo should read that as a warning. Mandatory `within:` deadlines without a group budget and without a defined overrun handler give you the same gap — you can detect that a deadline was blown but you have no compositional story for who pays.

#### SPARK's exclusions

SPARK is the other half: a subset of Ada chosen for provability. Its documented language restrictions exclude side-effecting functions, aliasing of names, and backward `goto` statements; access types are handled through an ownership discipline; controlled types are excluded; functions must be shown to terminate; and generics are analysed only at their instantiations ([SPARK 2014 User's Guide, language restrictions](https://docs.adacore.com/spark2014-docs/html/ug/en/source/language_restrictions.html)). Violations are reported as errors, not warnings ([SPARK 2014 User's Guide](https://docs.adacore.com/spark2014-docs/html/ug/en/source/language_restrictions.html)).

Judgment: three of those land directly on Mo. Errors-not-warnings is already Mo's honesty law. Function termination as a proof obligation is exactly what Mo's structural-recursion-only rule buys syntactically — but SPARK gets it as a proof obligation the prover discharges, which permits far more programs than a syntactic structural-recursion check does. That is the shape of the compromise available to Mo's while-ban: keep the syntactic rule for `mo check`, and let `mo prove` admit a general loop with a discharged termination obligation.

#### pragma Restrictions as a tighten-only mechanism

Ada's general mechanism is `pragma Restrictions`, a configuration pragma that "expresses the user's intent to abide by certain restrictions", where "the set of restrictions is implementation defined", and "a partition shall obey the restriction if a pragma Restrictions applies to any compilation unit included in the partition" ([Ada Reference Manual 13.12](https://www.adaic.org/resources/add_content/standards/05rm/html/RM-13-12.html)).

The brief asks whether this is a "tighten only" mechanism. The reference manual section fetched does not explicitly state that restrictions can only remove features. n.a. What it does state is the partition-wide propagation rule above, which has the practical effect that a restriction applied anywhere binds everywhere, and that restrictions are expressed as a fixed vocabulary of named restriction identifiers rather than as arbitrary predicates ([Ada RM 13.12](https://www.adaic.org/resources/add_content/standards/05rm/html/RM-13-12.html)).

Judgment: the partition-wide propagation rule is the transferable part. It means a library cannot loosen the restrictions of the program that links it. For Mo, whose `d30-supply-chain-security` and `d34-packages-are-recipes` directions care exactly about what a dependency can do to you, a per-partition restriction vocabulary that a dependency can tighten but never loosen is worth designing deliberately.

---

### 6. seL4's proof discipline

#### What the proof actually says

seL4 is the extreme end of the spectrum: a kernel written so it can be proved. The whitepaper is careful about the claim. Functional correctness means the C implementation refines an abstract specification; a separate binary translation validation extends the result to the compiled binary; on top of functional correctness sit proofs of confidentiality, integrity and availability properties ([seL4 whitepaper](https://sel4.systems/About/seL4-whitepaper.pdf)).

Equally careful about the assumptions: the proof rests on the correctness of the hardware, on the specification matching what was intended, and on the theorem prover ([seL4 whitepaper](https://sel4.systems/About/seL4-whitepaper.pdf)). Timing channels are not covered by the proofs ([seL4 whitepaper](https://sel4.systems/About/seL4-whitepaper.pdf)).

#### How the code is written to be provable

The kernel is written in a restricted, well-defined subset of C ([seL4 whitepaper](https://sel4.systems/About/seL4-whitepaper.pdf)). The SOSP paper spells the subset out. The address-of operator on local variables is disallowed, "because, for better automation, we make the assumption that local variables are separate from the heap", and the team notes this "is the most far-reaching restriction we implement" ([seL4: Formal Verification of an OS Kernel, SOSP 2009](https://web.eecs.umich.edu/~ryanph/jhu/cs718/spring18/readings/seL4.pdf)). Side effects in expressions are limited, and where more than one function call occurs in an expression "a proof obligation is generated to show that these functions are side-effect free" ([seL4 SOSP 2009](https://web.eecs.umich.edu/~ryanph/jhu/cs718/spring18/readings/seL4.pdf)). Calls through function pointers are disallowed, as are `goto` statements and "switch statements with fall-through cases" ([seL4 SOSP 2009](https://web.eecs.umich.edu/~ryanph/jhu/cs718/spring18/readings/seL4.pdf)). Unions are not used directly; "all unions in seL4 are tagged" ([seL4 SOSP 2009](https://web.eecs.umich.edu/~ryanph/jhu/cs718/spring18/readings/seL4.pdf)).

Memory: "the model guarantees all memory allocation in the kernel is explicit and authorised", with physical memory represented by untyped capabilities that are retyped into kernel objects, and the allocation policy pushed out of the kernel to userland so that "we only need to prove that the mechanism works, not that the user-level policy makes sense" ([seL4 SOSP 2009](https://web.eecs.umich.edu/~ryanph/jhu/cs718/spring18/readings/seL4.pdf)).

Concurrency: "proofs about concurrent programs are hard, much harder than proofs about sequential programs", so the team "side-step[s] addressing the verification complexity of yield by using an event-based kernel execution model, with a single kernel stack, and a mostly atomic application programming interface" ([seL4 SOSP 2009](https://web.eecs.umich.edu/~ryanph/jhu/cs718/spring18/readings/seL4.pdf)). Their analysis of why: "Yielding at X results in the potential execution of any reachable activity in the system. This implies A must establish the preconditions required for all reachable activities" ([seL4 SOSP 2009](https://web.eecs.umich.edu/~ryanph/jhu/cs718/spring18/readings/seL4.pdf)).

Judgment: this is the argument for `d12-concurrency-at-the-edges` stated by people who paid for the alternative in person-years. An event-based, single-stack, run-to-completion core with explicit yield points is what makes sequential reasoning survive. Mo's process model should preserve that property deliberately: within a process, no interleaving; between processes, only message boundaries.

#### Cost

The numbers are the reason this section exists. Functional correctness took approximately 12 person-years; the whole initial project, including tools and proof libraries, about 25 person-years, from roughly 12 people over 4 years, around 7 full-time-equivalent ([seL4: Formal Verification of an Operating-System Kernel, CACM/NICTA full text](https://trustworthy.systems/publications/nicta_full_text/8066.pdf)). The later security proofs were much cheaper on top of the functional-correctness base: integrity under 8 person-months, non-interference under 21 person-months, and adding a separation scheduler cost about 21 person-months including proof updates ([NICTA full text](https://trustworthy.systems/publications/nicta_full_text/8066.pdf)). The proof grew from roughly 200,000 to 400,000 lines over that period ([NICTA full text](https://trustworthy.systems/publications/nicta_full_text/8066.pdf)); the whitepaper puts the current total above one million lines ([seL4 whitepaper](https://sel4.systems/About/seL4-whitepaper.pdf)).

Klein's cost analysis is the most quotable: seL4's verification came in at "<$400 per line of code", against a Green Hills figure of roughly $1,000 per line for conventionally developed high-assurance code, with productivity of 1.4 person-years per thousand lines for seL4 and 0.6 py/kLOC for the later BilbyFS work, and a ratio of ">20 lines of proof per line of C" ([Verified software can and will be cheaper than buggy stuff, Gernot Heiser](https://microkerneldude.org/2016/06/16/verified-software-can-and-will-be-cheaper-than-buggy-stuff/)).

#### Maintaining proofs under change

The governance rule is one line and it is the most important sentence in this section: "Commits to the mainline kernel source are only allowed if they do not break proofs" ([seL4 whitepaper](https://sel4.systems/About/seL4-whitepaper.pdf)).

Judgment: proof maintenance is a CI gate, not a research activity. That is the transferable practice, and it is cheap for Mo to copy at a much lower assurance level: `d32-proving-is-a-separate-tool` should still be wired so that a change which invalidates an existing proof fails the build rather than silently downgrading the module to "tested only".

The sound WCET analysis story is a caution in the other direction: the whitepaper describes sound worst-case execution time analysis achieved on Arm v6 but now in abeyance ([seL4 whitepaper](https://sel4.systems/About/seL4-whitepaper.pdf)). Verification results are perishable when hardware moves.

---

### 7. Cleanroom software engineering

#### The core claim

Cleanroom is the oldest and strangest entry here, and it is the one that speaks most directly to agent-authored code. Mills, Dyer and Linger's statement of the method is that it substitutes "human mathematical verification in place of program debugging" ([Cleanroom Software Engineering, Mills, Dyer and Linger](http://www.cs.toronto.edu/~chechik/courses07/csc410/mills.pdf)). Developers do not unit test their own code; correctness is argued, and testing is statistical usage testing performed by a separate certification team against an operational profile, yielding an MTTF certification rather than a pass/fail ([Mills et al.](http://www.cs.toronto.edu/~chechik/courses07/csc410/mills.pdf)).

The reported effects, in the authors' words: "more than 90 percent of total product defects were found before first execution", against a customary figure of 60 percent, and developers "essentially never resorted to debugging (less than 0.1 percent of the cases)"; corrections took about one fifth the time of conventional debugging-driven correction ([Mills et al.](http://www.cs.toronto.edu/~chechik/courses07/csc410/mills.pdf)).

The design heuristic that follows is the one Mo should tattoo somewhere: "If a program looks hard to verify, it is the program that should be revised" ([Mills et al.](http://www.cs.toronto.edu/~chechik/courses07/csc410/mills.pdf)).

#### The defect numbers

The strongest quantitative evidence in Part 1 comes from the DTIC survey of Cleanroom projects. Across the surveyed projects the weighted average was 2.3 errors per KLOC found in testing, against a traditional-development baseline the report characterises as 25 to 35 or more errors per KLOC ([Cleanroom Software Engineering, DTIC ADA326485](https://apps.dtic.mil/sti/tr/pdf/ADA326485.pdf)).

Project-level figures: IBM's COBOL Structuring Facility, 85 KLOC of PL/I, 3.4 errors per KLOC and 740 lines per person-month, with 7 errors reported in three years of field use; NASA's CFADS, 40 KLOC, 4.5 errors per KLOC at 780 lines per person-month with an 80 percent productivity improvement; Ericsson's OS32, 350 KLOC, 1 error per KLOC ([DTIC ADA326485](https://apps.dtic.mil/sti/tr/pdf/ADA326485.pdf)). Overall the report characterises quality improvements of 10 to 20 times and productivity improvements of 1.5 to 5 times ([DTIC ADA326485](https://apps.dtic.mil/sti/tr/pdf/ADA326485.pdf)).

The single most interesting datum for Mo is the IBM 3490E tape drive comparison: unit testing consumed 1.5 person-weeks and found 7 errors, while correctness verification of the same material took 1.5 hours and found 10 ([DTIC ADA326485](https://apps.dtic.mil/sti/tr/pdf/ADA326485.pdf)).

Judgment: these are uncontrolled industrial comparisons from the late 1980s and early 1990s, with obvious selection effects — the teams that adopted Cleanroom were not random teams. Treat the direction as credible and the magnitudes as soft. But the direction matters enormously for Mo, because the hypothesis Cleanroom tested is precisely Mo's: that if you make code cheap to reason about and expensive to write sloppily, reading beats running.

#### Does "no developer debugging" map to agents?

Judgment: partially, and the mismatch is instructive. Cleanroom removed debugging from developers because debugging encouraged writing code you did not understand and then poking it until it passed. An agent has the opposite failure mode — it is extremely good at poking until green and has no shame about it, so the incentive Cleanroom was worried about is strictly worse. The Cleanroom answer, separating the person who argues correctness from the person who certifies it statistically, translates cleanly: the agent writes the code and the contracts, and an independent generator it does not control produces the usage-profile tests. Mo's `mo test --sim N` is closer to Cleanroom's statistical usage testing than to unit testing, and framing it that way suggests it should report a reliability estimate over an operational profile, not just pass or fail.

What does not transfer is "no unit tests". Cleanroom's substitute for unit tests was a human writing a correctness argument in a stepwise-refinement discipline. Mo's substitute is machine-checked contracts. Mo already has the better half of that trade.

---

### 8. Static allocation and "no allocation after init"

#### The rule as written

TigerBeetle's version, verbatim: the system should "allocate all memory at startup" and perform "no dynamic memory allocation after initialization" ([TIGER_STYLE.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md)). The surrounding principle is broader — "put a limit on everything" — and the assertion discipline asks for at least two assertions per function and for paired assertions checking the same property from both the caller's and callee's side ([TIGER_STYLE.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md)). Explicitly-sized integer types are required ([TIGER_STYLE.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md)).

The negative-space framing and the fuzzing caveat are both there: assertions should check the negative space as well as the positive, and "a fuzzer can prove only the presence of bugs, not their absence" ([TIGER_STYLE.md](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md)).

NASA's F Prime says the same in flight-software terms. Its coding standard bans exceptions, templates, the STL and RTTI, states "No recursion; No GOTOs", requires that "Loops must have a fixed-bound", and forbids dynamic allocation after initialisation, with `FW_ASSERT` as the assertion mechanism and defined WARNING_LO / WARNING_HI / FATAL severities ([F Prime code style guide](https://nasa.github.io/fprime/v3.1.0/UsersGuide/dev/code-style.html)). The memory-management documentation describes the pattern concretely: allocation happens at initialisation, and runtime variability is served by pre-sized buffer pools rather than heap allocation ([F Prime memory management](https://fprime.jpl.nasa.gov/latest/docs/user-manual/framework/memory-management/)).

JPL Rule 5 and MISRA Dir 4.12 say the same thing again, from §1 and §2 above.

#### What it is for and what it costs

The stated rationales converge: allocation can fail at an inconvenient time, allocation time varies with fragmentation, and a system that has already allocated everything has a memory footprint that can be computed rather than measured. MISRA states the variance concern explicitly ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)).

The cost is that every bound becomes a design decision made early and a failure mode when exceeded. F Prime's buffer pools are the honest version of this: you do not avoid the question of what happens when demand exceeds supply, you move it from the allocator to your own pool and handle it explicitly ([F Prime memory management](https://fprime.jpl.nasa.gov/latest/docs/user-manual/framework/memory-management/)).

Judgment: Mo already inherits most of this through bounded mailboxes, sized ints and no unbounded loops. The piece it has not committed to is the accounting: a static-allocation discipline is only worth its cost if the toolchain can tell you the total. A `mo check` that reported per-process worst-case mailbox memory and per-module static footprint would convert a stylistic rule into a computed guarantee, which is what the flight-software standards are actually buying.

---

### 9. Other standards worth a paragraph

#### Astrée and Airbus

Astrée is the counter-example to "static analysis always drowns you in false positives". AbsInt describe it as "a static analyzer for safety-critical software written or generated in C or C++" that "statically analyzes whether the programming language is used correctly and whether there can be any runtime errors during any execution in any environment" ([AbsInt Astrée](https://www.absint.com/astree/index.htm)). The soundness claim: "Astrée is sound — that is, if no errors are signaled, the absence of errors has been formally proved", and it "always exhaustively considers all possible runtime errors. It will never omit pointing out a potential runtime error" ([AbsInt Astrée](https://www.absint.com/astree/index.htm)). Alongside that, "Astrée is capable of producing exactly zero false alarms" ([AbsInt Astrée](https://www.absint.com/astree/index.htm)). AbsInt report that NIST in 2020 determined Astrée to be "one out of only two tools in total that satisfy their criteria for sound static code analysis" ([AbsInt Astrée](https://www.absint.com/astree/index.htm)).

Judgment: the zero-false-alarms claim is a vendor claim about specific analysed programs, and it is achieved partly because the target domain — generated, statically allocated, loop-bounded control code — is exactly the domain the analyser was specialised for. That is the real lesson for Mo. Astrée is not a general C analyser that happens to be precise; it is precise because the code it analyses already obeys the restrictions in §1, §2 and §5. Mo's bet is the same bet: restrict the language so the analysis can be both sound and quiet. Astrée is the best existence proof that the bet pays off, and it is also the reason Mo's 50 ms `mo check` budget is plausible only for decidable rules.

Astrée also supports checking against MISRA, CWE, ISO/IEC, SEI CERT and AUTOSAR rule sets through an integrated RuleChecker, and it offers annotation mechanisms "for supplying external knowledge and fine-tuning the analysis precision for individual loops or data structures" ([AbsInt Astrée](https://www.absint.com/astree/index.htm)).

Judgment: per-loop precision annotations are the industrial version of JPL's `/* @non-terminating@ */` comment. Two independent tools in this domain concluded that the right interface for a loop the analyser cannot bound is an annotation, not a prohibition.

#### Barr Group Embedded C Coding Standard

The only Barr Group source located in this session is the book's product page, which states that the standard is harmonised with MISRA C:2012 but does not reproduce rule text ([Barr Group, Embedded C Coding Standard](https://barrgroup.com/embedded-systems/books/embedded-c-coding-standard)). The rule-level content is behind the book. Thin source; no rule-level claim is made here. n.a.

#### Google's C++ style rules that became bans

Google's guide is the best-argued example of style rules hardening into prohibitions, and it states its own meta-rules first. The goals include "Style rules should pull their weight" — "the benefit of a style rule must be large enough to justify asking all of our engineers to remember it" — and "Optimize for the reader, not the writer", on the grounds that "more time will be spent reading most of our code than writing it" ([Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html)). The guide notes that this weight principle "mostly explains the rules we don't have, rather than the rules we do: for example, `goto` contravenes many of the following principles, but is already vanishingly rare, so the Style Guide doesn't discuss it" ([Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html)).

The exceptions ban is the famous one, and Google's own framing of it is unusually honest: "Our advice against using exceptions is not predicated on philosophical or moral grounds, but practical ones", and "Things would probably be different if we had to do it all over again from scratch" ([Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html)). RTTI gets "Avoid using run-time type information" ([Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html)).

Judgment: Mo's no-exceptions law is the same conclusion reached from a much better starting position. Google banned exceptions because retrofitting them into a hundred-million-line exception-unsafe codebase was impractical; Mo bans them because it never had them. The transferable piece is not the ban, it is the "pull their weight" test and the public admission that a rule is contingent on circumstances. A law page that cannot say what it costs and under what conditions it would be wrong is a law page nobody can revise.

#### SQLite's coding rules

SQLite's testing regime is covered in §13. A primary SQLite document setting out coding style rules, separate from the testing and assert documentation, was not located in this session. n.a. The closest primary statements about how SQLite code is shaped come from its assertion documentation, covered in §13, which is really a rule about defensive code rather than a style guide.

---

## Part 2 — Reliability and testing philosophies

### 10. FoundationDB's deterministic simulation testing

#### The mechanism

FoundationDB's testing story starts with a language. Flow is a C++ extension providing an actor model with single-threaded, deterministic execution, and the simulator exploits that determinism to run a whole cluster — many "machines" — inside one process on one thread ([FoundationDB testing documentation](https://apple.github.io/foundationdb/testing.html), [FoundationDB: A Distributed Unbundled Transactional Key Value Store, SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)).

Because everything is deterministic, faults can be injected reproducibly. The paper lists the injected fault classes, which include machine and process failures, network partitions, disk failures and corruption, clock skew, and swizzle-clogging — a pattern that clogs and unclogs network connections in a rotating order to stress reconfiguration paths ([FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)).

BUGGIFY is the second mechanism and the more interesting one for Mo. The paper describes it as a macro that marks code locations where the simulator may inject unusual-but-legal behaviour — delaying, reordering, returning an error, choosing a pathological parameter value — biasing the system towards rare paths rather than waiting for them to arise naturally ([FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)). Swarm testing varies configuration across runs so that different runs exercise different feature combinations ([FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)). `TEST()` macros mark conditionally-interesting states so the harness can report whether a given situation was ever reached ([FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)).

Simulation runs roughly ten times faster than real time, and the documentation reports the cumulative investment as "roughly one trillion CPU-hours of simulation" ([FoundationDB testing documentation](https://apple.github.io/foundationdb/testing.html)).

#### The claims, in their exact words

The "we never found a bug in production first" claim is real but hedged. The paper's wording is that bugs are found in the wild only "in the rare circumstances" that simulation missed them ([FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)) — not a categorical never. The strongest quantitative reliability result cited is operational rather than about the testing itself: CloudKit ran FoundationDB for "more than 0.5M disk years without a single data corruption event" ([FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)). The team also reports that Zookeeper was replaced after fault injection found two bugs in it ([FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)).

#### The limits, in their exact words

This is the part that matters most for Mo's tier 3, and it is stated by the authors against their own technique: "Simulation is not able to reliably detect performance issues"; and it is "unable to test third-party libraries or dependencies, or even first-party code not implemented in Flow" ([FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)).

Judgment: three consequences for Mo. First, deterministic simulation is a property of the whole execution stack, not of a test harness — FoundationDB got it by writing the language. Mo is in the rare position of being able to make the same choice from the start, and should, because bolting determinism on later is what forces the "not implemented in Flow" caveat. Second, latency and deadline behaviour are exactly what simulation does not validate, which means Mo's mandatory `within:` deadlines cannot be verified by `--sim` and need a separate story. Third, BUGGIFY is the direct answer to Mo's dispute 3, and §11 sharpens it.

---

### 11. Antithesis and "sometimes assertions"

#### The idea

Antithesis's contribution to this dossier is a single inversion: most assertions say a bad state never happens, and the interesting ones say a good state sometimes does. Their framing is that "code coverage only covers locations, while sometimes assertions cover situations" ([Antithesis, Sometimes assertions](https://antithesis.com/docs/best_practices/sometimes_assertions/)).

The assertion vocabulary is `always`, `alwaysOrUnreachable`, `reachable`, `unreachable` and `sometimes`, with properties keyed by a message string so the platform can track a named property across runs ([Antithesis, Assertions](https://antithesis.com/docs/properties_assertions/assertions/)).

The mechanism that makes `sometimes` more than a coverage counter is checkpointing and replay. Antithesis describe amplifying rare-event conjunctions: if two independent situations each occur with probability one in a thousand, waiting for both is hopeless, but a system that can snapshot the state just before the first and replay forward repeatedly can drive the conjunction ([Antithesis, Sometimes assertions](https://antithesis.com/docs/best_practices/sometimes_assertions/)).

The brief asks how they define safety versus liveness. The fetched assertion documentation does not use the terms "safety" and "liveness". n.a.

#### Why this resolves Mo's dispute 3

Mo's live dispute 3 is that mandatory fault injection will produce vacuous tests: inject a fault, the process crashes, the supervisor restarts it, the test passes, and nothing was actually verified. The evidence says this is a real failure mode and that the field has a specific, deployable answer to it.

The answer is that a fault-injection test is only meaningful if it is paired with a reachability obligation. FoundationDB's `TEST()` macros exist for exactly this reason — to report whether an interesting situation was ever reached ([FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)) — and Antithesis generalises it into a first-class assertion form whose failure mode is "this never happened" rather than "this went wrong" ([Antithesis, Sometimes assertions](https://antithesis.com/docs/best_practices/sometimes_assertions/)).

Judgment: Mo should not make fault injection mandatory. It should make reachability obligations mandatory for fault-injection tests. Concretely: a `test` that runs under `--sim` with injected faults should be required to declare at least one `sometimes` obligation — the recovery path ran, the retry fired, the mailbox actually filled — and `mo test --sim N` should fail the run if any declared obligation was never observed across N seeds. That converts "we injected a fault and nothing broke" from a pass into a diagnostic, and it is the cheapest thing in this entire dossier to implement.

The second transferable piece is the property-name key. Antithesis track properties by message across runs ([Antithesis, Assertions](https://antithesis.com/docs/properties_assertions/assertions/)); Mo's `never` clauses and `rejects` tests should carry stable identifiers for the same reason, so that "this property stopped being exercised three commits ago" is a detectable event. That pairs naturally with `d29-edit-by-declaration-id`.

---

### 12. Jepsen

#### Methodology and its stated limits

Jepsen is the adversarial complement to simulation: black-box, against real deployments, with nemeses inducing partitions and other faults, checking recorded histories against a consistency model. Kingsbury states both the strength and the trade honestly: "Opaque-box systems testing ... Bugs reproduced in Jepsen are observable in production, not theoretical. However, we sacrifice some of the strengths of formal methods: tests are nondeterministic, and we cannot prove correctness, only find errors" ([Jepsen analyses](https://jepsen.io/analyses)).

The model side is explicit about what a consistency model is: "A consistency model is a safety property which declares what a system can do" ([Jepsen consistency models](https://jepsen.io/consistency)).

Judgment: that is the sentence Mo's `d19-negative-space-is-the-contract` page should quote. A consistency model is not a description of behaviour; it is a bound on the set of permitted behaviours. Mo's `never` clauses are the same construct at function scale. The generalisation Jepsen makes that Mo has not is that the interesting properties are about histories, not states — Mo can say a process never holds a negative balance, but it has no way to say that a sequence of operations across processes never exhibits a given anomaly.

#### Elle and the anomaly taxonomy

Elle is the checker, and it is where Jepsen becomes a language-design input rather than a QA service. Elle infers Adya-style transactional dependency graphs from observed histories and detects a named taxonomy of anomalies: G0 write cycles, G1a aborted reads, G1b intermediate reads, G1c read-write cycles, G-single, G2 and G2-item anti-dependency cycles, plus dirty updates, garbage reads and internal inconsistency ([Elle: Inferring Isolation Anomalies from Experimental Observations, VLDB](http://www.vldb.org/pvldb/vol14/p268-alvaro.pdf)).

The result: "Elle revealed anomalies in every system we tested", across TiDB 2.1.7 through 3.0.0-beta.1, YugaByte 1.3.1, FaunaDB 2.6.0 and Dgraph 1.1.1, and "almost all of these anomalies were previously unknown" ([Elle, VLDB](http://www.vldb.org/pvldb/vol14/p268-alvaro.pdf)).

Judgment: the design insight in Elle is that it recovers the dependency graph from the observed values by making the workload self-describing — list-append operations whose values record their own history. Mo could apply the same trick to processes. If message payloads carried a cheap causal token in `--sim` builds, `mo test --sim` could check cross-process history properties with an Elle-style checker rather than only per-process assertions. That is a bigger project than the `sometimes` obligation, but it is the thing that would let Mo say anything at all about multi-process correctness.

---

### 13. SQLite's testing regime

#### The numbers

SQLite reports 155.8 thousand source lines in the core library against 92,053.1 thousand lines of test code and scripts, a ratio of roughly 590 to 1 ([How SQLite Is Tested](https://www.sqlite.org/testing.html)).

There are several independent harnesses. The TCL test suite carries about 51,445 distinct test cases. TH3 is the proprietary harness used for the certification-grade runs: it achieves 100 percent branch coverage and 100 percent MC/DC over the core, with about 50,362 test cases that expand to roughly 2.4 million test instances in full configuration, and 248.5 million during soak testing. SQL Logic Test runs about 7.2 million queries comparing SQLite against other engines. dbsqlfuzz applies roughly one billion mutations per day across 16 cores ([How SQLite Is Tested](https://www.sqlite.org/testing.html)).

Beyond coverage, the regime includes out-of-memory testing, I/O error testing, and crash and power-loss anomaly testing that simulates failures at arbitrary points ([How SQLite Is Tested](https://www.sqlite.org/testing.html)).

#### The sentence Mo needs to read twice

SQLite documents a direct conflict between two of its own quality mechanisms: "MC/DC testing discourages defensive code with unreachable branches, but without defensive code, a fuzzer is more likely to find a path that causes problems" ([How SQLite Is Tested](https://www.sqlite.org/testing.html)).

Their resolution is the `ALWAYS()` / `NEVER()` macro pair. The assert documentation sets out the semantics across three build types — a condition wrapped in `ALWAYS()` or `NEVER()` behaves as an assertion in debug builds, as a constant in coverage-measurement builds so the unreachable branch does not count against MC/DC, and as the plain condition in release builds — with `testcase()` used to force coverage of specific boundary conditions ([SQLite assert documentation](https://sqlite.org/assert.html)).

Two further positions from the same page. On what assertions are for: "An assert(X) should not be seen as a safety-net" ([SQLite assert](https://sqlite.org/assert.html)). And assertions are disabled in release builds, because leaving them on costs roughly a threefold slowdown ([SQLite assert](https://sqlite.org/assert.html)).

Judgment: this is the most directly applicable finding in Part 2 for Mo's `never`. SQLite discovered that a codebase with contracts has a coverage problem — the defensive branches are, by construction, unreachable, and any coverage metric will either punish you for having them or be fooled into ignoring real gaps. Mo will hit this the moment it reports coverage alongside contracts. The `ALWAYS`/`NEVER` three-build design is the known-good answer: a `never` clause should be a checked assertion under `mo test`, excluded from coverage denominators under coverage measurement, and configurable at release.

That last part puts SQLite in direct opposition to JPL, which leaves assertions enabled in flight and wires them to fault protection ([Mars Code](https://cacm.acm.org/research/mars-code/)). The two are reconcilable by context: a library that crashes its host is a worse outcome than a degraded query, whereas a spacecraft that continues on corrupt state is worse than one that safes itself. Judgment: Mo's default should follow JPL, since Mo's failure model is process-level crash-and-restart rather than whole-application termination, but the fact that the most heavily tested C library in the world went the other way belongs on the `errors-and-failure` page, not omitted from it.

The 590-to-1 test ratio deserves one more note. It is achieved on a codebase with a stable, narrow interface and no concurrency inside the core. Judgment: quoting the ratio as an aspiration is a mistake; quoting the four-independent-harnesses structure is not. SQLite's real insight is harness diversity — hand-written cases, coverage-driven cases, differential testing against other implementations, and fuzzing — because each finds a class the others miss.

---

### 14. Let-it-crash as engineering practice, and what the AXD301 numbers actually were

#### The philosophy in Armstrong's words

Armstrong's thesis states the discipline as a set of slogans: "Let some other process do the error recovery. If you can't do what you want to do, die. Let it crash. Do not program defensively." ([Making reliable distributed systems in the presence of software errors, Joe Armstrong, 2003](https://www.cs.otago.ac.nz/cosc441/armstrong_thesis_2003.pdf)).

The error kernel is the structural half: the part of the system that must be correct is made as small as possible, and everything outside it is allowed to fail and be restarted ([Armstrong thesis](https://www.cs.otago.ac.nz/cosc441/armstrong_thesis_2003.pdf)). The thesis distinguishes exceptions from errors, sets out six requirements R1 through R6 for a language supporting this style, and describes AND and OR supervision structures ([Armstrong thesis](https://www.cs.otago.ac.nz/cosc441/armstrong_thesis_2003.pdf)).

The restart-intensity mechanism is the operationally important detail and is often skipped: a supervisor specification such as `{one_for_one,5,1000}` means that "if the supervisor has to restart the processes which it is monitoring more than 5 times in 1000 seconds then it itself will fail" ([Armstrong thesis](https://www.cs.otago.ac.nz/cosc441/armstrong_thesis_2003.pdf)).

Judgment: restart intensity is the piece of let-it-crash that makes it an engineering practice rather than an infinite retry loop, and it is the piece Mo must not omit. Without it, `d21-autonomous-crash-fixing` and supervised restart together produce a system that cheerfully masks a deterministic bug forever. With it, a persistent fault escalates and eventually surfaces. It is also the direct answer to Mo's dispute 4 on update-as-transaction and restart semantics: a restart budget converts "restart fixes everything" into "restart fixes transient things, and we can tell the difference".

#### The AXD301 system, measured

The AXD301 is the flagship example, and the thesis gives its scale: about 1.7 million lines of Erlang as of 2003, with the studied version comprising 1,136,150 lines across 2,248 modules, 141 nodes in the supervision tree, 191 instances of OTP behaviours, written by more than 40 programmers over 4 years, with a documented limit of 120 call setups per second ([Armstrong thesis](https://www.cs.otago.ac.nz/cosc441/armstrong_thesis_2003.pdf)).

#### The nine nines, resolved

The nine-nines claim is the most-repeated reliability statistic in the functional-programming world and it does not survive contact with its sources.

Armstrong's own thesis is explicitly uncertain about it: "For the Ericsson AXD301 the only information on the long-term stability of the system came from a power-point presentation showing some figures claiming that a major customer had run an 11 node system with a 99.9999999% reliability, though how these figure had been obtained was not documented" ([Armstrong thesis](https://www.cs.otago.ac.nz/cosc441/armstrong_thesis_2003.pdf)).

Mats Cronqvist, who worked on the AXD 301, addressed it directly in a 2010 Erlang Factory talk. His account: "The customer (British Telecom) claimed nine nines service availability integrated over about 5 node-years." He adds, "As far as I know, no one in the AXD 301 project claimed that this was normal, or even possible," and, flatly, "For the record, Joe Armstrong was not part of the AXD 301 team." His assessment of the figure is that "the claim is pretty bogus", noting that the system in question contained more C than Erlang, had experienced no restarts and no upgrades in the measured period, and had very well defined functionality. He also declines to abandon the underlying point: "nevertheless ... the system was very reliable ... I have been unable to find any publicly available reference to this. An ancdote will have to do!" ([Mats Cronqvist, Erlang Factory SF Bay 2010](https://www.erlang-factory.com/upload/presentations/243/ErlangFactorySFBay2010-MatsCronqvist.pdf)).

Judgment: the honest summary is that nine nines was a customer's availability figure integrated over roughly five node-years on a system that never restarted or upgraded during the measurement window, disclaimed by a member of the project team as not normal and not possible as a general claim, and recorded by Armstrong himself as an undocumented PowerPoint number. It is not evidence that let-it-crash yields nine nines. Mo's wiki should cite the practice — supervision trees, error kernel, restart intensity — and should not cite the number. This matters beyond pedantry: `d08-beam-qualities-without-the-beam` is a load-bearing page, and resting it on a debunked statistic gives a reviewer a free win.

The defensible version of the claim, from the same sources, is narrower and still strong: a 1.1-million-line telecom switch was built by 40-plus programmers in 4 years using supervision trees and 191 behaviour instances ([Armstrong thesis](https://www.cs.otago.ac.nz/cosc441/armstrong_thesis_2003.pdf)), and a team member who was there describes it as very reliable while explicitly saying he cannot find a public reference for the figure ([Cronqvist](https://www.erlang-factory.com/upload/presentations/243/ErlangFactorySFBay2010-MatsCronqvist.pdf)).

---

### 15. The property-based testing lineage

#### QuickCheck

Claessen and Hughes's original paper defines the model Mo's `rejects` tests should grow into: properties are written as ordinary functions in the host language, and the tool generates inputs and checks the property holds ([QuickCheck: A Lightweight Tool for Random Testing of Haskell Programs](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quick.pdf)). Generation is under the tester's control through the `Arbitrary` class and the `Gen` monad, so the distribution of inputs is a design decision rather than an accident ([QuickCheck](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quick.pdf)).

The paper defends random testing against partition testing by citing the empirical literature of the time, including Duran and Ntafos and Hamlet's summary that "by taking 20% more points in a random test, any advantage a partition test might have had is wiped out" ([QuickCheck](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quick.pdf)).

#### Industrial QuickCheck: the AUTOSAR result

Hughes's industrial experience report is the strongest evidence in Part 2 that property-based testing scales to a real specification. Testing AUTOSAR basic software modules, the Quviq team wrote "20,000 lines of QuickCheck code" against a specification of "around 3,000 pages of PDFs", and used it to test "a million lines of C code ... from 6 different suppliers, finding more than 200 problems—of which well over 100 were ambiguities or inconsistencies in the standard itself!" ([Experiences with QuickCheck: Testing the Hard Stuff and Staying Sane, John Hughes](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quviq-testing.pdf)).

The comparison against the conventional approach is stated: the QuickCheck model was "an order of magnitude smaller" than the corresponding TTCN3 test suite ([Experiences with QuickCheck](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quviq-testing.pdf)). The approach is model-based and stateful — a state machine model of the component, against which random command sequences are generated ([Experiences with QuickCheck](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quviq-testing.pdf)).

Judgment: over half the defects found were defects in the specification, not the code. That is the single most relevant fact in this dossier to Mo's dispute 7 on spec altitude. Writing an executable model at a higher altitude than the implementation does not merely test the implementation; it is the mechanism by which specification ambiguity becomes visible. Mo's `requires`/`never`/`rejects` triple is a low-altitude version of this — per-function, not per-component. A state-machine property form at process level, where the agent writes a model of what a process is supposed to do and `--sim` generates command sequences against it, is the natural next tier and is well-evidenced.

#### Shrinking

Shrinking is what makes random failures usable. Hughes describes it as "extracting the signal from the noise", and reports that a minimal counterexample produced by shrinking was found and fixed in under a day ([Experiences with QuickCheck](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quviq-testing.pdf)).

Judgment: for Mo this is a requirement, not a nicety. `mo test --sim N` produces failures from seeded schedules and injected faults, and a raw failing seed is close to useless to an agent — it is a 10,000-step interleaving. A shrunk schedule, with the minimal set of injected faults and reorderings that still fails, is a debuggable artifact. Shrinking should be designed into `--sim` from the beginning, because retrofitting it means retrofitting a representation of the schedule that can be reduced.

#### Hypothesis

Hypothesis's design contribution is exactly that representation. Its paper describes a universal internal representation of generated data that allows reduction to work without any user intervention, so shrinking is a property of the framework rather than something each generator must implement ([Hypothesis: A new approach to property-based testing, JOSS](https://joss.theoj.org/papers/10.21105/joss.01891.pdf)). It also supports targeted property-based testing, steering generation toward a user-supplied score ([Hypothesis, JOSS](https://joss.theoj.org/papers/10.21105/joss.01891.pdf)).

Adoption and results: over 100,000 downloads per week, used by more than 4 percent of Python users per the PSF's 2018 survey, with bugs found in astropy and numpy among others ([Hypothesis, JOSS](https://joss.theoj.org/papers/10.21105/joss.01891.pdf)). The paper does not use the term "choice sequence" for the internal representation. n.a.

Judgment: the transferable design rule is "make the thing you generate reducible by construction". For Mo, the thing generated by `--sim` is a schedule plus a fault list; if that is a flat byte sequence in a canonical form, generic shrinking comes free, exactly as it did for Hypothesis. This is a decision that must be made before the simulator exists.

#### Coverage of the negative space

Judgment: the lineage as a whole says something Mo's `d19-negative-space-is-the-contract` should absorb. A `requires` clause with a paired `test rejects` is a single hand-written point in the rejected region. Property-based testing replaces that point with a generator over the rejected region, and shrinking reports the boundary. The highest-value version of Mo's rule is therefore not "every `requires` needs a `test rejects`" but "every `requires` needs a generator for its complement", with the hand-written rejection test as the degenerate case where the complement is a single value.

---

### 16. Error budgets and chaos engineering

#### Google SRE: budgets as the failure model

The SRE book's premise is that perfect reliability is the wrong target: 100 percent is the wrong reliability target for basically everything, and the supporting argument is that the user's own stack dominates — "a user on a 99% reliable smartphone cannot tell the difference between 99.99% and 99.999%" ([Embracing Risk, Google SRE book](https://sre.google/sre-book/embracing-risk/)). 99.99 percent availability corresponds to 52.56 minutes of unavailability per year ([Embracing Risk](https://sre.google/sre-book/embracing-risk/)).

The error budget is the control loop: "An error budget is 1 minus the SLO" ([Error budget policy, SRE Workbook](https://sre.google/workbook/error-budget-policy/)). The workbook attributes roughly 70 percent of outages to changes, and gives a concrete enforcement clause: "If the service has exceeded its error budget for the preceding four-week window, we will halt all changes and releases other than P0 issues or security fixes" ([Error budget policy](https://sre.google/workbook/error-budget-policy/)). The book describes the budget being consumed and reset over a quarterly cycle ([Embracing Risk](https://sre.google/sre-book/embracing-risk/)). The fetched pages do not state a requirement for stakeholder sign-off on the policy. n.a.

Judgment: the structural idea Mo can take is not the SLO but the budget-as-quantity. A budget is a number that is allocated at the top, consumed by the parts, and whose exhaustion triggers a defined action. Mo already has one such quantity — the deadline — and one where the analogy is exact: the supervisor restart intensity from §14 is an error budget with a four-week window replaced by a 1000-second one, and a "halt all changes" action replaced by "escalate to the parent supervisor". Judgment: naming these the same thing in Mo's docs, and giving both the same shape (quantity, window, action on exhaustion), would make the failure model considerably more teachable than treating deadlines and restart limits as unrelated features.

#### Chaos engineering

The Principles of Chaos Engineering define it as the discipline of experimenting on a system in order to build confidence in its capability to withstand turbulent conditions in production, and set out advanced principles: build a hypothesis around steady-state behaviour, vary real-world events, run experiments in production, automate experiments to run continuously, and minimize blast radius ([Principles of Chaos Engineering](https://principlesofchaos.org/)).

Judgment: two of those five bear on Mo. "Build a hypothesis around steady-state behavior" is the same instruction as Antithesis's `sometimes` — state what should still be true, not merely what should not go wrong. "Minimize blast radius" is the operational form of the error kernel. The in-production principle does not transfer to a language, but it does transfer to `--sim`: the argument for running experiments in production is that staging does not contain the real fault distribution, which is exactly why FoundationDB's BUGGIFY biases toward rare-but-legal behaviour rather than sampling naturally ([FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf)).

---

### 17. Mutation testing as evidence of test strength

This is the one item in the dossier where the primary literature genuinely disagrees with itself, and Mo should treat it accordingly.

#### The case for

Just, Jalali, Inozemtseva, Ernst, Holmes and Fraser studied 357 real faults across 5 projects totalling about 321,000 lines of code, and found a statistically significant correlation between mutant detection and real fault detection that persisted even when test suite coverage was controlled for ([Are Mutants a Valid Substitute for Real Faults in Software Testing?, FSE 2014](https://dada.cs.washington.edu/research/tr/2014/02/UW-CSE-14-02-02.PDF)). The same study reports its own limits: 95 of the 357 faults, about 27 percent, were not coupled to any mutant, and 118 of 480 fault-triggering tests killed no additional mutants ([Just et al., FSE 2014](https://dada.cs.washington.edu/research/tr/2014/02/UW-CSE-14-02-02.PDF)).

PIT's own framing is the practitioner's argument: mutation testing is described as the gold standard against which other coverage measures are judged, because traditional coverage "does not check that your tests are actually able to detect faults" ([PIT Mutation Testing](https://pitest.org/)). The fetched PIT page makes no claim about equivalent mutants. n.a.

#### The case against

Papadakis, Shin, Yoo and Bae's replication is the counterweight. Using CoREBench and Defects4J across 420 faults, they found uncontrolled correlations between mutation score and real-fault detection in the range 0.35 to 0.75, but these dropped to roughly 0.05 to 0.20 once test suite size was controlled for ([Are Mutation Scores Correlated with Real Fault Detection?, ICSE 2018](https://orbilu.uni.lu/bitstream/10993/34950/1/ICSE-main18b%20(1).pdf)). Their conclusion is that "using mutants as substitutes of real faults ... can be problematic", and they report that under 1 percent of mutants represent real-fault behaviour ([Papadakis et al., ICSE 2018](https://orbilu.uni.lu/bitstream/10993/34950/1/ICSE-main18b%20(1).pdf)).

They do not discard the technique: "mutation score is actually helpful, to testers for improving test suites ... but it is not that good at representing the actual test effectiveness" ([Papadakis et al., ICSE 2018](https://orbilu.uni.lu/bitstream/10993/34950/1/ICSE-main18b%20(1).pdf)).

#### What this means for Mo

Judgment: the two studies are reconcilable. Mutation score is a good instrument for improving a test suite and a bad instrument for grading one, because most of the apparent correlation with fault detection is mediated by suite size. That is a precise answer to the outside review's demand that Mo mutation-test its contract machinery.

The right use is diagnostic and targeted: mutate the contract machinery itself — flip a `requires` comparison, weaken a `never` clause, remove an exhaustiveness arm — and check that some `rejects` test fails. A surviving mutant in that narrow domain is an actionable gap, because the contract's complement is exactly what the `rejects` test is supposed to cover. The wrong use is a repository-wide mutation score as a quality gate, which the ICSE 2018 result says would mostly measure how many tests Mo's agents wrote. Mo status: measure first, scoped to the contract machinery.

---

### 18. Structured concurrency and deadlines as budgets

#### Structured concurrency

Nathaniel Smith's argument is the cleanest statement of the position: "go statements are a form of goto statement", and like `goto` they destroy the ability to reason locally — "Go statements break abstraction" ([Notes on structured concurrency, or: Go statement considered harmful](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/)).

The nursery is the replacement: a syntactic scope that owns its child tasks, where "the nursery block doesn't exit until all the tasks inside it have exited", restoring the black box rule — you can read a function call and know that when it returns, it is done ([Notes on structured concurrency](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/)).

Kotlin implements the same shape: coroutines can only be launched inside a `CoroutineScope`, a parent coroutine waits for its children, and the failure of a child cancels the others recursively ([Kotlin coroutines basics](https://kotlinlang.org/docs/coroutines-basics.html)). The fetched page does not state explicit guarantees phrased as "no leaked coroutines" or "errors are never lost". n.a.

Judgment: Mo's `d12-concurrency-at-the-edges` and `d14-processes-are-the-only-identity` put it in a different family — Erlang-style processes with supervision rather than lexical nurseries. The two solve overlapping problems: a supervision tree gives you ownership and failure propagation, but not the black box rule, because a supervised process outlives the call that started it. Judgment: Mo already has the structured-concurrency benefit at process granularity through supervision, and should say so explicitly rather than leaving readers to wonder whether nurseries are missing. What it lacks is the lexical form for the narrow case of "fan out three requests and wait", which is common enough in agent-written code to deserve its own construct.

#### Deadlines versus timeouts, and the inherited-budget question

Go's `context` package is the most widely deployed answer. A `Context` carries `Done`, `Err` and `Deadline`; derived contexts form a tree, and cancelling a parent cancels its descendants; the documented convention is to "pass a Context parameter as the first argument to every function on the call path" ([Go Concurrency Patterns: Context](https://go.dev/blog/context)).

gRPC's guidance draws the distinction Mo's dispute 5 turns on: "TL;DR: Always set a deadline", and a deadline is a point in time while a timeout is a duration; the rationale given is avoiding resource exhaustion from calls that never complete ([gRPC and Deadlines](https://grpc.io/blog/deadlines/)). The fetched gRPC page does not state that deadlines propagate across services or that downstream budgets are computed by subtraction. n.a. on that specific mechanism from this source.

The strongest primary support for the inherited-budget position therefore comes from two other places in this dossier. Go's context tree makes the deadline an inherited property of a call tree rather than a per-call parameter: a derived context inherits its parent's deadline and cancellation propagates down the tree ([Go context](https://go.dev/blog/context)). And Ravenscar bans the relative-delay form outright in favour of the absolute `delay_until`, because a relative delay is non-deterministic with respect to the instant it actually expires when the task is preempted between computing the delay and suspending ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

Judgment: the evidence favours inherited budgets over deadline literals, with two independent lines of support and none found for the literal-per-call position. Ravenscar's argument is that a duration is not a well-defined thing to wait for once preemption exists; Go's is that the deadline belongs to the call tree, not the call. Mo's `within: 500ms` written at each call site has a concrete bug built into it: a caller with a 500 ms budget that makes three calls each written `within: 500ms` can take 1.5 seconds while every individual annotation was honoured. The fix consistent with both sources is to make `within:` establish an absolute deadline at the entry point, have nested calls inherit the remaining budget by default, and treat a nested `within:` literal as a tightening — it may shorten the inherited budget and may never extend it. That also makes the rule uniform with Ada's restriction propagation from §5 and with MISRA's re-categorization direction from §2: every budget-like quantity in Mo tightens downward and never loosens.

The remaining gap, from §5, is that Ravenscar deliberately does not provide group budgets or overrun handlers and names that as a cost ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)). Mo should decide explicitly what happens when a deadline is exceeded — crash the process and let the supervisor handle it is a defensible answer, and it composes with the restart-intensity budget from §14 — rather than leaving it as a runtime detail.

---

## Rules ranked for Mo

Evidence strength is graded against what the primary sources actually establish: "strong" means a controlled study or a large industrial result with numbers; "moderate" means consistent, independently-arrived-at practice in multiple safety-critical standards with stated rationale but no outcome measurement; "weak" means a single source, a vendor claim, or a contested literature. Mo status uses the four values the brief specifies.

| Rule | Source | Evidence strength | Mo status |
|---|---|---|---|
| Loops must have a statically determinable upper bound | [JPL Rule 3](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf) | moderate | already |
| Non-terminating loops are permitted when explicitly annotated | [JPL Rule 3](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf), [MISRA Rule 14.2 exception and 14.3 exception](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf), [Ravenscar No_Task_Termination](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf) | moderate | contradicts |
| No dynamic memory allocation after initialisation | [JPL Rule 5](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf), [MISRA Dir 4.12](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf), [TigerBeetle](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md), [F Prime](https://nasa.github.io/fprime/v3.1.0/UsersGuide/dev/code-style.html) | moderate | already |
| Report static memory footprint and per-process mailbox worst case | [F Prime memory management](https://fprime.jpl.nasa.gov/latest/docs/user-manual/framework/memory-management/) | weak | adopt |
| Levels of compliance: modules declare which tier of the rulebook they meet | [JPL LOC-1..LOC-6](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf) | moderate | adopt |
| Three guideline categories with a formal deviation record | [MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf), [MISRA Compliance:2020](https://misra.org.uk/app/uploads/2021/06/MISRA-Compliance-2020.pdf) | moderate | adopt |
| Projects may re-categorize a rule stricter, never looser | [MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf), [Ada RM 13.12 partition propagation](https://www.adaic.org/resources/add_content/standards/05rm/html/RM-13-12.html) | moderate | adopt |
| Every rule labelled decidable/undecidable and single-unit/system | [MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf) | moderate | adopt |
| Every rule scored on severity, likelihood and remediation cost | [CERT C risk assessment](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/front-matter/introduction/how-this-coding-standard-is-organized/) | moderate | adopt |
| Signed integer overflow must not go undetected | [CERT INT32-C, priority 18, L1](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/rules/integers-int/int32-c/) | moderate | already |
| Returned error information must be tested | [MISRA Dir 4.7](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf), [MISRA Rule 17.7](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf) | moderate | already |
| No untagged unions | [MISRA Rule 19.2](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf), [seL4](https://web.eecs.umich.edu/~ryanph/jhu/cs718/spring18/readings/seL4.pdf) | moderate | already |
| No non-local control transfer (goto, setjmp, exceptions) | [JPL Rule 11](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf), [seL4](https://web.eecs.umich.edu/~ryanph/jhu/cs718/spring18/readings/seL4.pdf), [Google C++](https://google.github.io/styleguide/cppguide.html), [SPARK](https://docs.adacore.com/spark2014-docs/html/ug/en/source/language_restrictions.html) | moderate | already |
| Violations are errors, not warnings | [SPARK](https://docs.adacore.com/spark2014-docs/html/ug/en/source/language_restrictions.html) | weak | already |
| Coverage must be produced by requirements-traced tests, not chased directly | [DO-178B/C via NASA MC/DC tutorial](https://ntrs.nasa.gov/api/citations/20010057789/downloads/20010057789.pdf) | strong | already |
| Code exercised by no requirement must be classified and justified | [NASA MC/DC tutorial, dead and deactivated code](https://ntrs.nasa.gov/api/citations/20010057789/downloads/20010057789.pdf) | strong | adopt |
| MC/DC as the coverage target for the highest criticality | [NASA MC/DC tutorial](https://ntrs.nasa.gov/api/citations/20010057789/downloads/20010057789.pdf), [SQLite TH3](https://www.sqlite.org/testing.html) | strong | measure first |
| Contract branches excluded from the coverage denominator | [SQLite ALWAYS/NEVER](https://sqlite.org/assert.html), [How SQLite Is Tested](https://www.sqlite.org/testing.html) | moderate | adopt |
| Static task set: processes created only at known points, no dynamic hierarchy | [Ravenscar](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf) | moderate | measure first |
| Bounded queues with runtime failure on overflow | [Ravenscar Max_Entry_Queue_Length](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf) | moderate | already |
| No abort: a process cannot be asynchronously killed by another | [Ravenscar No_Abort_Statements](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf) | moderate | adopt |
| Absolute deadlines, not relative delays; nested budgets inherit and may only tighten | [Ravenscar No_Relative_Delay](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf), [Go context](https://go.dev/blog/context), [gRPC](https://grpc.io/blog/deadlines/) | moderate | adopt |
| Function termination as a discharged proof obligation, not only a syntactic rule | [SPARK](https://docs.adacore.com/spark2014-docs/html/ug/en/source/language_restrictions.html) | moderate | adopt |
| No aliasing; no side-effecting functions | [SPARK](https://docs.adacore.com/spark2014-docs/html/ug/en/source/language_restrictions.html) | moderate | already |
| Event-based, single-stack execution with explicit yield points | [seL4 SOSP 2009](https://web.eecs.umich.edu/~ryanph/jhu/cs718/spring18/readings/seL4.pdf) | moderate | already |
| Changes that break an existing proof fail the build | [seL4 whitepaper](https://sel4.systems/About/seL4-whitepaper.pdf) | moderate | adopt |
| Verification claims must state their assumptions | [seL4 whitepaper](https://sel4.systems/About/seL4-whitepaper.pdf) | moderate | adopt |
| Revise the program when it looks hard to verify | [Mills et al.](http://www.cs.toronto.edu/~chechik/courses07/csc410/mills.pdf) | strong | already |
| Statistical usage testing against an operational profile, certifying MTTF | [Mills et al.](http://www.cs.toronto.edu/~chechik/courses07/csc410/mills.pdf), [DTIC ADA326485](https://apps.dtic.mil/sti/tr/pdf/ADA326485.pdf) | strong | adopt |
| At least two assertions per function, checking both sides of an interface | [TigerBeetle](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md) | weak | measure first |
| Function ≤60 lines, ≤6 parameters | [JPL Rule 25, a "should" in the clarity level](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf) | weak | measure first |
| A style rule must pull its weight to justify being remembered | [Google C++](https://google.github.io/styleguide/cppguide.html) | weak | adopt |
| Deterministic whole-system simulation built into the language runtime | [FoundationDB testing](https://apple.github.io/foundationdb/testing.html), [FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf) | strong | already |
| BUGGIFY-style biased injection of unusual-but-legal behaviour | [FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf) | strong | adopt |
| Swarm testing: vary configuration across simulation runs | [FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf) | moderate | adopt |
| Fault-injection tests must declare reachability obligations that fail when unmet | [Antithesis sometimes assertions](https://antithesis.com/docs/best_practices/sometimes_assertions/), [FDB TEST() macros](https://www.foundationdb.org/files/fdb-paper.pdf) | strong | adopt |
| Properties carry stable identifiers tracked across runs | [Antithesis assertions](https://antithesis.com/docs/properties_assertions/assertions/) | weak | adopt |
| Do not claim simulation validates performance or latency | [FDB SIGMOD 2021](https://www.foundationdb.org/files/fdb-paper.pdf) | strong | adopt |
| History-level properties, not only state-level assertions | [Jepsen consistency](https://jepsen.io/consistency), [Elle](http://www.vldb.org/pvldb/vol14/p268-alvaro.pdf) | strong | adopt |
| Harness diversity: hand-written, coverage-driven, differential, fuzz | [How SQLite Is Tested](https://www.sqlite.org/testing.html) | strong | adopt |
| Assertions are not a safety net; decide their release-build status deliberately | [SQLite assert](https://sqlite.org/assert.html) vs [Mars Code](https://cacm.acm.org/research/mars-code/) | moderate | measure first |
| Supervisor restart intensity: a restart budget that escalates on exhaustion | [Armstrong thesis](https://www.cs.otago.ac.nz/cosc441/armstrong_thesis_2003.pdf) | moderate | adopt |
| Error kernel: minimise the part that must be correct | [Armstrong thesis](https://www.cs.otago.ac.nz/cosc441/armstrong_thesis_2003.pdf), [Principles of Chaos, minimize blast radius](https://principlesofchaos.org/) | moderate | already |
| Do not program defensively; let it crash | [Armstrong thesis](https://www.cs.otago.ac.nz/cosc441/armstrong_thesis_2003.pdf) | moderate | already |
| Generate properties, do not only write examples; model-based state machine testing | [QuickCheck](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quick.pdf), [Experiences with QuickCheck](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quviq-testing.pdf) | strong | adopt |
| Counterexamples must be shrunk before they reach the author | [Experiences with QuickCheck](https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quviq-testing.pdf), [Hypothesis](https://joss.theoj.org/papers/10.21105/joss.01891.pdf) | strong | adopt |
| Generated artifacts use a canonical reducible representation | [Hypothesis](https://joss.theoj.org/papers/10.21105/joss.01891.pdf) | moderate | adopt |
| 100% reliability is the wrong target; budget the failure | [Embracing Risk](https://sre.google/sre-book/embracing-risk/), [Error budget policy](https://sre.google/workbook/error-budget-policy/) | moderate | adopt |
| Hypothesise about steady state, then perturb | [Principles of Chaos](https://principlesofchaos.org/) | moderate | adopt |
| Mutation score as a repository-wide quality gate | [Just et al. FSE 2014](https://dada.cs.washington.edu/research/tr/2014/02/UW-CSE-14-02-02.PDF) vs [Papadakis et al. ICSE 2018](https://orbilu.uni.lu/bitstream/10993/34950/1/ICSE-main18b%20(1).pdf) | contested | contradicts |
| Mutation testing scoped to the contract machinery as a diagnostic | [Just et al. FSE 2014](https://dada.cs.washington.edu/research/tr/2014/02/UW-CSE-14-02-02.PDF), [Papadakis et al. ICSE 2018](https://orbilu.uni.lu/bitstream/10993/34950/1/ICSE-main18b%20(1).pdf), [PIT](https://pitest.org/) | contested | measure first |
| Concurrency introduced only in lexically scoped, joined regions | [Notes on structured concurrency](https://vorpus.org/blog/notes-on-structured-concurrency-or-go-statement-considered-harmful/), [Kotlin coroutines](https://kotlinlang.org/docs/coroutines-basics.html) | moderate | measure first |
| Restrictions, once applied anywhere in a partition, bind everywhere | [Ada RM 13.12](https://www.adaic.org/resources/add_content/standards/05rm/html/RM-13-12.html) | moderate | adopt |
| Sound static analysis is achievable and quiet only on a restricted language | [AbsInt Astrée](https://www.absint.com/astree/index.htm) | weak | already |
| Per-loop precision annotations rather than prohibition | [AbsInt Astrée](https://www.absint.com/astree/index.htm), [JPL Rule 3 annotation](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf) | moderate | contradicts |

---

## What the evidence says about the shape-law and while-ban disputes

### Dispute 1: shape numbers as laws or as policy

The evidence does not support shape numbers as hard laws, and the source Mo derives them from does not treat them that way.

JPL's own standard places the numeric shape limits — 60 lines, 6 parameters — in LOC-4, the code-clarity level, and states them as "should" rules, while the bounding rules that Mo also enforces sit in LOC-2, Predictable Execution, as "shall" rules ([JPL standard](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf)). The document that Mo's shape laws descend from already made the distinction Mo's dispute is about, and put shape on the softer side.

MISRA supplies the general machinery for handling exactly this: three categories with different deviation requirements, an explicit statement that advisory guidelines "should be followed as far as is reasonably practical", and the one-way ratchet that lets a project promote any advisory guideline to required or mandatory ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)). MISRA Compliance:2020 makes the deviation a recorded artifact with required fields rather than an ad-hoc argument ([MISRA Compliance:2020](https://misra.org.uk/app/uploads/2021/06/MISRA-Compliance-2020.pdf)).

CERT supplies the criterion for deciding which side a rule belongs on: score it on severity, likelihood and remediation cost, where remediation cost is itself determined by whether a violation is detectable and repairable ([CERT C](https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/front-matter/introduction/how-this-coding-standard-is-organized/)). A body over 70 lines is highly detectable, trivially repairable, and of low severity in isolation. That combination scores low and lands in the advisory band.

Google supplies the last piece, the weight test: a rule's benefit "must be large enough to justify asking all of our engineers to remember it", and the guide is candid that the existence of a rule can be contingent on circumstances that might not recur ([Google C++ Style Guide](https://google.github.io/styleguide/cppguide.html)).

No primary source located in this run offers a controlled study linking a specific function-length or parameter-count threshold to a defect-rate reduction. The one number in this area that is measured rather than asserted is JPL's MSL assertion density of 2.26 percent ([JPL standard](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf)), and that is a density, not a limit.

Judgment: Mo should keep the shape numbers, keep them on by default, and move them from "law" to a "required" category with a recorded, machine-readable deviation — a declaration on the function that names the reason, in the style of a MISRA deviation record rather than a blanket escape hatch. The bounding laws stay mandatory. A project that wants shape limits to be mandatory can promote them, and cannot demote them below default. This costs Mo almost nothing, because the checker already computes the violation; what changes is what happens next, and it removes the weakest argument available to a critic — that Mo's most visible laws are its least evidenced ones.

### Dispute 2: whether the while-ban produces fictional bounds

Here the evidence is more uncomfortable, because three independent safety-critical standards all declined to do what Mo does.

JPL requires a statically determinable bound but permits the intentionally non-terminating loop when it carries the `/* @non-terminating@ */` annotation ([JPL standard](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf)). MISRA constrains `for` loop shape very tightly and then carves out infinite loops twice, once in Rule 14.2's exception permitting `for ( ; ; )` "so as to allow for infinite loops" and once in Rule 14.3's exception that "invariants that are used to create infinite loops are permitted" ([MISRA C:2012](https://www.misra.org.uk/app/uploads/woocommerce_uploads/2021/06/pdf2-3zxsfw-lnbvtq.pdf)). Ravenscar goes furthest in the opposite direction to Mo: `No_Task_Termination` requires that "all tasks are non-terminating", and the guide observes matter-of-factly that "real-time tasks normally have an infinite loop as their last outermost statement" ([WG9 N575](https://www.open-std.org/jtc1/sc22/wg9/n575.pdf)).

The failure mode the dispute names — fictional bounds — is the predictable consequence. If the only way to express "serve requests until shut down" is a loop with a bound, the author will write a bound, and the bound will be a number chosen to be large enough not to matter. A fictional bound is worse than an annotated infinite loop in three specific ways: it cannot be distinguished by a tool from a real bound, so every downstream analysis that trusts bounds is now unsound; it silently changes behaviour at the limit, turning a liveness property into an unexplained termination; and it teaches the agent that bounds are a syntactic tax rather than a claim.

The mechanism the field converged on is an annotation, and two independent lines support it. JPL's is a comment convention that the static analyser and the reviewer both key on ([JPL standard](https://yurichev.com/mirrors/C/JPL_Coding_Standard_C.pdf)). Astrée's is a supported annotation mechanism "for supplying external knowledge and fine-tuning the analysis precision for individual loops or data structures" ([AbsInt Astrée](https://www.absint.com/astree/index.htm)). In both cases the loop the tool cannot bound is marked, not forbidden, and the marking is what makes the remaining analysis sound.

SPARK shows the other available move. Rather than a syntactic termination rule, SPARK makes function termination a proof obligation ([SPARK 2014 User's Guide](https://docs.adacore.com/spark2014-docs/html/ug/en/source/language_restrictions.html)). That admits every terminating program whose termination can be argued, rather than only those whose termination is structurally obvious, and it does so without weakening the guarantee.

Judgment: the defensible position for Mo is a three-way split rather than a ban. Keep the default: iteration is over finite collections and ranges, and structural recursion is the general form. Add an explicit, grep-able non-terminating construct — a named `loop forever` form permitted only in a process's top-level body, which is the exact place Ravenscar says it belongs, and which `mo check` records so that any analysis depending on termination knows to exclude it. And route the genuinely-bounded-but-not-structurally-obvious case to `mo prove` with a termination obligation, in SPARK's style, rather than forcing the author to invent a counter.

That preserves everything the while-ban was protecting. An agent still cannot write an accidental infinite loop, because the non-terminating form is a distinct construct that is illegal outside a process body. What changes is that the system no longer manufactures bounds it does not believe, which is the precise harm the dispute identified. Judgment: of the two disputes, this is the one where the primary sources most clearly point away from Mo's current position, and where the fix is cheapest — one construct and one checker rule.


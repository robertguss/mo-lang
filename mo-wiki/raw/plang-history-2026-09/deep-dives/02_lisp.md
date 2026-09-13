# Lisp / Common Lisp / Scheme — The Language That Ate Its Own Tail

## Origin story

### Designers, institution, year

John McCarthy began developing Lisp in **1958** at the **Massachusetts Institute of Technology (MIT)**. He wanted an artificial-intelligence programming language for the IBM 704 and believed that "IBM looked like a good bet to pursue Artificial Intelligence research vigorously" ([Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))). His original 1960 paper — "Recursive Functions of Symbolic Expressions and Their Computation by Machine, Part I," published April 1, 1960 in *Communications of the ACM* — showed that a Turing-complete language could be built from a few simple operators plus a notation for anonymous functions borrowed from Alonzo Church ([Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))).

Common Lisp was standardized by ANSI as **ANSI X3.226-1994** (now designated ANSI INCITS 226-1994 (S2018)) in **1994**, with Guy L. Steele Jr. having given the first overview of Common Lisp at the 1982 ACM Symposium ([Wikipedia: Common Lisp](https://en.wikipedia.org/wiki/Common_Lisp)). **Scheme** was born in **1975** when Gerald Jay Sussman and Guy L. Steele at MIT AI Lab published "SCHEME: An Interpreter For Extended Lambda Calculus" — an interpreter for a LISP-like language "based on the lambda calculus and extended for side effects, multiprocessing, and process synchronization… inspired by ACTORS" ([The Lambda Papers](https://research.scheme.org/lambda-papers/)).

### The motivating problem

McCarthy was dissatisfied with the Information Processing Language (IPL) and with the Fortran List Processing Language he had helped design, because the latter lacked recursion and a modern if-then-else ([Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))). McCarthy's original notation was bracketed **M-expressions** intended to be translated into **S-expressions**, e.g. `car[cons[A,B]]` → `(car (cons A B))`. But after implementation, programmers immediately chose the S-expression form and M-expressions were abandoned ([Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))).

### Initial reception

The pivotal moment: **Steve Russell**, working for McCarthy, realized the `eval` function in McCarthy's paper could itself be implemented in machine code. McCarthy "initially thought Russell was confusing theory with practice because `eval` was intended for reading rather than computing," but Russell "compiled the `eval` described in McCarthy's paper into IBM 704 machine code, fixed bugs, and advertised the result as a Lisp interpreter" ([Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))). Two IBM 704 assembly macros — `car` ("Contents of the Address part of Register") and `cdr` ("Contents of the Decrement part of Register") — survive to this day. The first complete Lisp compiler was written in Lisp and implemented in **1962** by Tim Hart and Mike Levin at MIT; it "produced machine-code output that ran with a 40-fold improvement in speed over the interpreter" and introduced the model of incremental compilation in which compiled and interpreted functions freely intermix ([Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))).

## Design philosophy

### Core principles

- **Code is data.** Lisp was "the first language in which the structure of program code was represented faithfully and directly in a standard data structure" — a property later called **homoiconicity** ([Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))).
- **The language extends itself.** Because code is lists, macros can generate code using the language's list-processing functions; Lisp macros "can perform on code anything Lisp can perform on a data structure" ([Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))).
- **Interactive, incremental development.** From the Hart–Levin compiler onward, Lisp assumed a running image into which compiled and interpreted definitions are added incrementally ([Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))).
- **First-class functions and closures.** Directly borrowed from Church's lambda calculus.

### What Lisp rejected

Lisp abandoned M-expressions and traditional infix mathematical notation in favor of prefix S-expressions — a decision that has been simultaneously its greatest strength (uniform syntax makes macros trivial) and its greatest reputational obstacle ([Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))). Scheme deliberately rejected Common Lisp's kitchen-sink pragmatism in favor of "minimalism": Scheme's core language is roughly 50 pages while Common Lisp's is over 1,000.

### Cultural values

Lispers value expressive power, meta-programming, and the ability to grow the language toward the problem rather than shrinking the problem to the language. Alan Kay's oft-quoted line — "Lisp is the greatest single programming language ever designed" — captures the reverence. Paul Graham argued that using Lisp gave his startup Viaweb a competitive advantage that competitors could not match ("Beating the Averages").

## Language features

### Syntax

S-expressions everywhere: `(f arg1 arg2 arg3)` for both function calls and syntactic forms. Uniform prefix notation, aggressive parenthesization, no operator precedence to memorize.

### Type system

Common Lisp is dynamically typed with optional type declarations that a compiler like SBCL uses for optimization. Every CLOS class is integrated into the Common Lisp type system, and many Common Lisp types have a corresponding class ([Wikipedia: Common Lisp](https://en.wikipedia.org/wiki/Common_Lisp)). Scheme is likewise dynamically typed. Typed variants exist (Typed Racket, Coalton for Common Lisp).

### Memory model and GC

Garbage-collected from the start: "Garbage-collection routines were developed by MIT graduate student Daniel Edwards" before 1962 ([Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))). Modern implementations use generational, precise GCs (SBCL's generational GC, CCL's ephemeral GC).

### Concurrency

Not standardized in ANSI CL 1994. Modern Common Lisp implementations provide native threads via portability libraries (Bordeaux-Threads). Scheme via SRFIs. Notable historical: Sussman/Steele's 1975 Scheme paper was already "extended for side effects, multiprocessing, and process synchronization" ([Lambda Papers](https://research.scheme.org/lambda-papers/)).

### Error handling — the condition system

Common Lisp's **condition system** is unusually powerful. When a condition is signaled, "the Common Lisp system searches for a handler for the condition type… the handler can search for restarts… the handler can use a restart to automatically repair the problem." Critically, "a condition handler is called in the context of the error **without unwinding the stack**. Full error recovery is possible in many cases where other exception-handling systems would already have terminated the current routine" ([Wikipedia: Common Lisp](https://en.wikipedia.org/wiki/Common_Lisp)).

The example in the Wikipedia entry — a nonexistent file producing four restarts (`Retry OPEN`, `Retry OPEN using a different pathname`, `Return to Lisp Top Level`, `Restart process`) that the user selects interactively — captures the model. This design has been widely admired but rarely copied (Dylan and Racket are the main heirs).

### Metaprogramming and macros

Common Lisp macros are functions that receive source, bind it to parameters, compute a new source form, and expand recursively until no macro remains ([Wikipedia: Common Lisp](https://en.wikipedia.org/wiki/Common_Lisp)). Typical uses include new control structures, scoping constructs, embedded DSLs (SQL, HTML, Prolog), and top-level defining forms with compile-time side effects. Standard features like `setf`, `with-open-file`, `loop`, `when`, `unless` are all macros.

Common Lisp macros are **non-hygienic** by default. Variable capture is a real hazard; the workaround is `gensym` to produce guaranteed-unique symbols, and packages to control name visibility ([Wikipedia: Common Lisp](https://en.wikipedia.org/wiki/Common_Lisp)). **Scheme's `syntax-rules`** (and later `syntax-case`) introduced **hygienic macros**, which prevent accidental capture automatically and became the model for Racket, Rust's `macro_rules!`, and much subsequent macro work.

### CLOS — the object system

The Common Lisp Object System is dynamic and unusually expressive. It supports "multiple dispatch, multimethods, method combinations, multiple inheritance, mixins, metaclasses… often implemented with a metaobject protocol" ([Wikipedia: Common Lisp](https://en.wikipedia.org/wiki/Common_Lisp)). CLOS allows runtime changes to generic functions, classes, methods, and objects; methods can be added or removed; classes can be added or redefined; and objects can be updated for class changes or changed from one class to another. The `defgeneric` and `defmethod` macros are the primary interface; generic functions are themselves first-class instances of classes.

### Continuations and call/cc

Scheme provides first-class continuations via `call-with-current-continuation` (`call/cc`) — the ability to capture the "rest of the computation" as a callable object. This has been used for cooperative multitasking, backtracking, generators, and web programming (Christian Queinnec's "continuation-based web servers" and PLT/Racket's continuation servers).

### Module system

Common Lisp uses **packages** — namespaces for symbols. R6RS Scheme introduced a formal module/library system; earlier Schemes and R5RS had none. Racket introduced a rich module system with `require`/`provide`.

## Implementation

### Reference implementations

Lisp has never had a single reference implementation; it has many. Notable Common Lisps:

- **SBCL** (Steel Bank Common Lisp) — a branch from CMUCL emphasizing maintainability. "SBCL does not use an interpreter by default. Unless the user switches the interpreter on, all expressions are compiled to native code" ([Wikipedia: Common Lisp](https://en.wikipedia.org/wiki/Common_Lisp)). SBCL is the most-used open-source high-performance Common Lisp.
- **CCL** (Clozure CL, formerly OpenMCL) — originally a fork of Macintosh Common Lisp, runs on macOS, Linux, FreeBSD, Windows on 32- and 64-bit x86 and PowerPC ([Wikipedia: Common Lisp](https://en.wikipedia.org/wiki/Common_Lisp)).
- **CLISP**, **ECL** (Embeddable Common Lisp), **ABCL** (Armed Bear on the JVM), **Allegro Common Lisp** (Franz Inc., commercial), **LispWorks** (commercial).

Notable Schemes: **Racket** (originally PLT Scheme), **Chez Scheme** (Cadence Research Systems, then Cisco, open-sourced 2016), **Guile** (GNU embedded scripting), **Gambit**, **Chicken**, **MIT/GNU Scheme**.

### Lexer/parser

Trivially simple: the reader is essentially a single recursive descent over parentheses, integers, strings, and symbols. This is a direct benefit of homoiconicity — parsing and syntax analysis are the same operation.

### IR and optimization

SBCL uses a Compiler Intermediate Representation ("IR1" and "IR2") and generates fast native code — "according to a prior version of The Computer Language Benchmarks Game," SBCL "generates fast native code" ([Wikipedia: Common Lisp](https://en.wikipedia.org/wiki/Common_Lisp)). Racket uses Chez's incremental compiler after the 2019 Racket-on-Chez migration.

### Backend

Native code (SBCL, CCL, Chez, Allegro), JVM (ABCL, Clojure), .NET (Clojure CLR), JavaScript (ClojureScript, BiwaScheme), C (ECL, Chicken).

### Bootstrapping

The Hart–Levin 1962 compiler set the template: Lisp compilers are typically written in Lisp and bootstrapped through prior versions of themselves ([Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))).

### Historical dialects

**Maclisp** at MIT Project MAC (a direct descendant of LISP 1.5, ran on PDP-10 and Multics); **Interlisp** at BBN Technologies (adopted as a "West coast" Lisp for Xerox Lisp machines as InterLisp-D); **ZetaLisp / Lisp Machine Lisp** on Lisp machines, whose descent into Common Lisp was major; **Franz Lisp** at UC Berkeley; **muLISP** (1979, ran on CP/M in 64KB RAM); **Standard Lisp** and **Portable Standard Lisp** (used with the REDUCE computer-algebra system); **LeLisp** (French) ([Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language))).

## Ecosystem

### Package manager

Common Lisp: **Quicklisp** (created 2010 by Zach Beane) is the de-facto package manager, distributing thousands of libraries via a curated set of "dists." Scheme: fragmented — Racket has `raco pkg`, R7RS Scheme has `snow-fort`.

### Standard library

ANSI Common Lisp specifies a large standard library (sequences, streams, formatting, condition system, CLOS, packages, pathnames). Scheme R5RS is famously tiny; R7RS-small is likewise minimal, with R7RS-large adding more.

### Tooling

**SLIME** (Superior Lisp Interaction Mode for Emacs, by Luke Gorrie and others) is the historical premier IDE; its Common Lisp backend is **SWANK**. **Sly** is a modernized fork. **DrRacket** is Racket's IDE — one of the most polished interactive language IDEs ever built. Common LSP servers exist (`cl-lsp`, `alive`).

### Community and governance

There is **no living standards body** for Common Lisp — the ANSI committee dissolved after 1994. Community coordination happens through Quicklisp, the ELS conference, and implementation maintainers. Racket has an active BDFL-style leadership (Matthew Flatt and colleagues at PLT). R7RS is developed by a small volunteer working group.

## Adoption

### Where it has been used

- **AI research** (McCarthy's original purpose; heavy use through the 1970s–1980s)
- **Emacs Lisp** (Emacs's extension language — arguably the most-used Lisp in the world)
- **AutoCAD's AutoLISP**
- **Symbolics Genera** on Lisp machines
- **ITA Software's Orbitz airfare-search engine** — a famous Common Lisp production system, acquired by Google in 2010
- **Grammarly's core** was written in Common Lisp for many years
- **Clojure** (Rich Hickey, 2007) — a modern JVM Lisp — is used at Nubank, Walmart, CircleCI, Netflix
- **Racket** — used in Bootstrap curriculum, Naughty Dog game scripting, and academic research
- **Guile** as GNU extension language (GnuCash, GNU Make extensions)

### Where it failed to penetrate

Mainstream commercial application development. The AI Winter and the collapse of the Lisp machine market (Symbolics, LMI, TI Explorer) in the late 1980s stripped Lisp of its industrial base, and the language never recovered mass adoption. Richard Gabriel's "Worse Is Better" essay — arguing that C and Unix beat Lisp because "worse is better" — is the classic diagnosis.

### Current momentum (2026)

Common Lisp is a niche but stable ecosystem: SBCL sees regular releases, Quicklisp is maintained, and a small but active commercial layer (Franz, LispWorks) persists. Clojure remains the most commercially active Lisp descendant. Racket continues as a research and education platform. Emacs Lisp underpins one of the two dominant text editors.

## Criticism and open problems

- **Syntax remains a barrier** to broad adoption despite genuine ergonomic advantages once learned.
- **No standards update since 1994** — Common Lisp is essentially frozen, forcing implementation-specific extensions for threads, networking, and Unicode.
- **Startup time and image size** compared to modern runtimes; slow to become "cloud-native."
- **Community fragmentation** across Common Lisp, Scheme variants, Clojure, and Racket dilutes ecosystem depth.

## Influence on other languages

Nearly every language that supports first-class functions, closures, garbage collection, dynamic typing, macros, homoiconicity, REPL-driven development, or metacircular evaluation traces some influence to Lisp:

- **Scheme** directly (a Lisp).
- **Common Lisp** directly (a Lisp).
- **Clojure**, **Racket**, **Emacs Lisp**, **Hy**, **Fennel** — modern Lisps.
- **JavaScript** — Brendan Eich's original mandate was "Scheme in the browser"; first-class functions and closures came from Scheme ([Eich HOPL](https://www.cs.tufts.edu/comp/150FP/archive/brendan-eich/js-hopl.pdf)).
- **ML, Haskell, OCaml** — first-class functions, algebraic data via tagged pairs.
- **Ruby**, **Python** — dynamic typing, first-class functions, list comprehensions, garbage collection.
- **Julia** — Lisp-1 style scoping, homoiconic macros, multiple dispatch (from CLOS lineage).
- **Rust** — `macro_rules!` is a hygienic macro system in the Scheme tradition.

## Key sources

- John McCarthy, ["Recursive Functions of Symbolic Expressions and Their Computation by Machine, Part I"](https://pages.cs.wisc.edu/~horwitz/CS704-NOTES/PAPERS/mccarthy.pdf), *Communications of the ACM*, April 1960.
- Guy L. Steele Jr. and Gerald Jay Sussman, ["The Lambda Papers"](https://research.scheme.org/lambda-papers/), 1975–1980 — the foundational Scheme documents.
- Guy L. Steele Jr., *Common Lisp the Language*, second edition (CLtL2), 1990 — the informal precursor to ANSI CL.
- ANSI INCITS 226-1994 (formerly X3.226-1994) — the Common Lisp standard.
- [Wikipedia: Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language)) and [Wikipedia: Common Lisp](https://en.wikipedia.org/wiki/Common_Lisp) — comprehensive overviews.
- Paul Graham, *On Lisp* (1993) and *ANSI Common Lisp* (1995).
- Richard P. Gabriel, "Worse Is Better" essay (1991).

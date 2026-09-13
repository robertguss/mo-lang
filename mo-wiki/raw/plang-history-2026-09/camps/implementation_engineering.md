# Implementation Engineering for New Programming Languages

*A comprehensive reference for the engineering menu — compilers, runtimes, verification, tooling — with tradeoffs and starting points.*

---

## Introduction and how to read this report

Every new programming language is a stack of engineering decisions. Some are visible (syntax, type system, memory model); most are invisible (parser strategy, IR choice, GC algorithm, package resolver). The invisible ones determine whether the language ships, whether it scales, and whether developers actually want to use it.

This document is organized as an engineering menu. Each section surveys the techniques in current production use, cites the foundational papers, and identifies the tradeoffs a language implementer must confront. It is meant to be read alongside the actual papers and code: every claim is linked back to a primary source that you should read before you commit.

The eleven sections mirror the natural order of a language project — front end, middle end, back end, runtime, then the concentric rings of tooling, verification, bootstrapping, and community.

---

## Section 1: Lexing and Parsing

The front end has stabilized around a small number of proven techniques. The single most useful fact for a new-language author: **almost every successful modern compiler uses a hand-written recursive-descent parser**, sometimes augmented with Pratt-style operator precedence for expressions. Parser generators still have their place (mostly for prototypes, DSLs, and languages with genuinely LALR-friendly grammars), but the industry has voted with its feet.

### 1.1 Hand-written lexers versus lex/flex generators

A lexer's job is small: convert a stream of characters into a stream of tokens. This is one of the few tasks in a compiler where a generator (`lex`/`flex`) can save real work — the output is a compact deterministic finite automaton driven by regular expressions.

Yet the vast majority of production compilers ship hand-written lexers. The reasons are practical rather than theoretical: hand-written lexers give better error messages, integrate more cleanly with incremental tooling, handle context-sensitive tokens (like Python's significant indentation or C's typedef ambiguity — see §1.9), and produce faster, more debuggable code. The lexer is small enough that "just write it" wins on nearly every axis except the initial keystroke count. Compiler-construction texts have documented recursive-descent front ends since Wirth's *Compiler Construction* text, which teaches the entire technique end-to-end using Oberon as the vehicle ([Wirth, ETH Zürich](https://people.inf.ethz.ch/wirth/CompilerConstruction/CompilerConstruction1.pdf)).

### 1.2 Recursive descent (Wirth-style)

Recursive descent is the dominant top-down parsing strategy in modern compilers. Each nonterminal in the grammar becomes a mutually recursive procedure that consumes tokens and returns an AST node. The technique traces to Niklaus Wirth's work on Pascal, Modula, and Oberon; Wirth's compiler-construction text presents the full method with worked examples ([Wirth, *Compiler Construction*](https://people.inf.ethz.ch/wirth/CompilerConstruction/CompilerConstruction1.pdf)).

Advantages that keep it dominant:

- Direct correspondence between grammar and code (readable, debuggable, greppable).
- Trivial to produce great error messages: you know exactly what you expected at each call site.
- Trivial to add error recovery, tentative parsing, backtracking, and semantic actions.
- Fast: no interpretation layer, no table lookups.

The classic weakness — left recursion — is handled by rewriting into iteration or by combining recursive descent with an operator-precedence loop for expression parsing. Which brings us to Pratt.

### 1.3 Pratt parsing (top-down operator precedence)

Vaughan Pratt introduced top-down operator precedence parsing in 1973 at the first *Principles of Programming Languages* symposium in Boston, implementing it in his CGOL language ([Crockford, *Top Down Operator Precedence*](https://www.crockford.com/javascript/tdop/tdop.html)). Pratt claimed the technique was "simple to understand, trivial to implement, easy to use, extremely efficient, and very flexible," and combined the strengths of recursive descent with Floyd's operator-precedence method ([Crockford, *Top Down Operator Precedence*](https://www.crockford.com/javascript/tdop/tdop.html)). Douglas Crockford revived attention with a chapter in *Beautiful Code* and the JSLint parser, arguing that the method had been "completely neglected" during decades of BNF and automata theory infatuation ([Crockford, *Top Down Operator Precedence*](https://www.crockford.com/javascript/tdop/tdop.html)).

The core idea is elegant. Each token carries a *left binding power* (`lbp`). Expression parsing is a single loop: parse a prefix (nud, "null denotation"), then repeatedly consume operators whose `lbp` exceeds the caller's right-binding-power, applying each operator's *led* ("left denotation") to combine the accumulated left tree with a freshly parsed right subexpression ([Crockford, *Top Down Operator Precedence*](https://www.crockford.com/javascript/tdop/tdop.html)). Precedence, associativity (via `bp − 1` vs `bp` in the right recursion), and mixfix operators fall out for free.

Pratt's technique has enjoyed a renaissance in modern language design. Zig, Carbon, Odin, and countless bytecode-language books (notably Nystrom's *Crafting Interpreters*) use Pratt parsing for expressions atop hand-written recursive descent for statements. It is one of the clearest wins in front-end engineering: **use recursive descent for the grammar's outer skeleton and a Pratt table for the expression sub-language** ([maxgcoding, *The Heart of Pratt Parsing*](https://www.maxgcoding.com/pratt-parsing-tdop)). The three-procedure structure — a prefix dispatcher, an infix dispatcher, and a driver loop — is small enough to type in a single sitting.

Operator-precedence parsing pre-dates Pratt in a different (bottom-up) form; the *shunting-yard algorithm* of Edsger Dijkstra is the canonical implementation of the classical operator-precedence idea, and is still used inside calculators to convert infix to RPN ([Wikipedia, *Operator-precedence parser*](https://en.wikipedia.org/wiki/Operator-precedence_parser)).

### 1.4 LL and LR parser generators

The classical generator families remain important, mostly for teaching and for tools where a formal, machine-verifiable grammar is the deliverable.

- **yacc / bison** — LALR(1) generators originating with Stephen C. Johnson at Bell Labs; ported into essentially every Unix. Grammar written in a specialized DSL, semantic actions inlined in C.
- **ANTLR** — Terence Parr's tool, which switched from LL(*) to *ALL(\*)* in v4. ALL(*) is an "adaptive LL(*)" algorithm that combines the simplicity of top-down parsing with dynamic grammar analysis to handle arbitrary context-free grammars, resolving conflicts at parse time by launching sub-parsers that race through the alternatives ([Parr, Harwell, Fisher, *Adaptive LL(\*) Parsing*](https://www.antlr.org/papers/allstar-techreport.pdf)). ALL(*) is *O(n^4)* in the worst case but linear on real grammars ([ALL(\*) tech report](https://www.antlr.org/papers/allstar-techreport.pdf)).
- **Menhir** — François Pottier's LR(1) generator for OCaml, an evolution of ocamlyacc. Menhir supports parameterized nonterminals, precise position tracking, and (crucially) inspection of the LR automaton for interactive error-message generation ([Menhir home](https://gallium.inria.fr/~fpottier/menhir/)). Modern Menhir is the standard for serious OCaml front ends and provides a *table back-end* alongside a *code back-end*, letting you trade compile time for parse time ([Menhir home](https://gallium.inria.fr/~fpottier/menhir/)).
- **LALRPOP** — Niko Matsakis's LR(1) generator for Rust, written in Rust itself. LALRPOP prioritizes usable error messages and clean integration with `nom`-like semantic actions; grammar files use a familiar EBNF-like DSL. LALRPOP is the parser generator most likely to appear in Rust-language projects today ([lalrpop/lalrpop](https://github.com/lalrpop/lalrpop)).
- **Happy** — the Haskell yacc analogue, used by GHC.

The Wikipedia catalog of parser generators is a useful cross-reference; it lists dozens of tools and classifies them by algorithm and target language ([*Comparison of parser generators*](https://en.wikipedia.org/wiki/Comparison_of_parser_generators)). An empirical evaluation of Lex/Yacc versus ANTLR found different tradeoffs in memory use, parse speed, and grammar readability across the two families ([PLOS ONE, *An empirical evaluation of Lex/Yacc and ANTLR parser generation*](https://journals.plos.org/plosone/article/file?id=10.1371/journal.pone.0264326&type=printable)).

### 1.5 PEGs and packrat parsing

Parsing Expression Grammars (PEGs) were introduced by Bryan Ford at MIT in a POPL 2004 paper, *Parsing Expression Grammars: A Recognition-Based Syntactic Foundation* ([Ford, POPL 2004](https://pdos.csail.mit.edu/~baford/packrat/popl04/)). PEGs differ from CFGs in two crucial ways: alternatives are **ordered** (`e1 / e2` tries `e1` first and only backtracks to `e2` if `e1` fails), and there is no ambiguity — a PEG always parses one specific derivation ([Ford, *Packrat Parsing and PEGs*](https://bford.info/packrat/)). Ford's companion technique, *packrat parsing*, memoizes every intermediate result and thereby guarantees linear time even for grammars that would otherwise backtrack exponentially ([Ford, *Packrat Parsing and PEGs*](https://bford.info/packrat/)).

The design tension is real: PEG's ordered-choice semantics is easy to reason about locally but can hide global surprises (an early alternative that succeeds on a prefix will silently mask a later alternative that would have matched the whole thing). PEGs also require left-recursion to be encoded specially — direct left recursion needs the seed-parsing trick of Warth et al., extended by Tratt for the general case ([Tratt, *Direct Left-Recursive Parsing Expression Grammars*](https://tratt.net/laurie/research/pubs/html/tratt__direct_left_recursive_parsing_expression_grammars/)).

PEGs have deeply influenced modern tooling. Ford's paper lists Rats!, LEG, Aurochs, Nemerle-Peg, and dozens of others as descendants ([Ford, *Packrat Parsing and PEGs*](https://bford.info/packrat/)); Rust's *Pest* and Python's PEG-based `pegen` (which replaced the LL(1) grammar in Python 3.9 following PEP 617) are the widely used modern examples. tree-sitter's grammar language is superficially a PEG variant — its `choice` operator is ordered like PEG's `/`, though its underlying algorithm is GLR, not packrat.

### 1.6 Parser combinators

Parser combinators are a functional-programming counter-tradition. Rather than a generator that reads a grammar file and emits code, combinators are ordinary functions in the host language that compose into parsers using a small set of operators (sequence, choice, many, optional). Daan Leijen and Erik Meijer's *Parsec* library was the canonical presentation for Haskell, presented as *"Direct Style Monadic Parser Combinators For The Real World"* ([Leijen & Meijer, Microsoft Research](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/parsec-paper-letter.pdf)). Parsec's key contributions were making backtracking explicit (the `try` combinator), producing useful error messages by threading token-position information through the monad, and demonstrating that a direct-style implementation could be efficient without continuation-passing tricks ([Parsec paper](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/parsec-paper-letter.pdf)).

Descendants dominate certain ecosystems: *attoparsec* and *megaparsec* in Haskell, *FParsec* in F#, *nom* in Rust (arguably the dominant Rust parser library for network protocols and binary formats), *combine* and *chumsky* in Rust, *Parsimmon* in JavaScript. The Scala community's parser-combinators library was originally in the standard library. Optimizing parser combinators via staging (macro-expansion of the combinator graph at compile time) is an active research area ([Jonnalagedda et al., *Optimizing Parser Combinators*](https://dl.acm.org/doi/10.1145/2991041.2991042)).

The tradeoff: parser combinators give you the maximum host-language leverage (types, IDEs, tests) but tend to be slower than generators or hand-written parsers and typically produce weak error messages unless you invest in the infrastructure to salvage them.

### 1.7 tree-sitter and incremental parsing

Max Brunsfeld's *tree-sitter* was the first tool to make **incremental, error-tolerant parsing** a mainstream capability of editor tooling ([tree-sitter README](https://github.com/tree-sitter/tree-sitter)). The design goals were "fast enough to parse on every keystroke in a text editor, robust enough to provide useful results even in the presence of syntax errors, dependency-free so that the runtime library (which is written in pure C11) can be embedded in any application" ([tree-sitter README](https://github.com/tree-sitter/tree-sitter)). Grammars are written in a JavaScript DSL; tree-sitter compiles them to C, uses a GLR-based algorithm internally, and reuses subtrees on edits so that only the touched region needs re-parsing.

The impact on editor tooling has been dramatic. GitHub uses tree-sitter for code navigation and syntax highlighting; Neovim, Emacs, Zed, and Helix use it for highlighting and structural navigation; hundreds of community-maintained grammars exist. For a new language, providing a tree-sitter grammar is now a near-requirement for editor adoption, because it delivers highlighting, folding, and structural selection in every tree-sitter-enabled editor at once ([tree-sitter README](https://github.com/tree-sitter/tree-sitter)).

Research on incremental PEG parsing (*gPEG*) extends the same idea to PEG grammars ([Yedidia, *Fast Incremental PEG Parsing*](https://zyedidia.github.io/preprints/gpeg_sle21.pdf)); scannerless generalized LR (*SGLR*) has a long history in the Stratego/XT and Spoofax lineage ([Sijm, SPLASH SRC](https://src.acm.org/binaries/content/assets/src/2020/maarten-p.-sijm.pdf)).

### 1.8 Ambiguity handling and error recovery

For CFG-based tools, ambiguity is a real risk. GLR parsers explore all possible parses in parallel; the resulting parse forest is then filtered by disambiguation rules (associativity, priority, semantic predicates). SGLR does this without a separate lexing phase, which lets it handle grammar composition (embedding SQL inside Java, HTML inside JavaScript) cleanly ([Sijm, SPLASH SRC](https://src.acm.org/binaries/content/assets/src/2020/maarten-p.-sijm.pdf)).

Error recovery in recursive descent has a rich literature going back to the 1970s panic-mode and phrase-level techniques ([Wirth's compiler book](https://people.inf.ethz.ch/wirth/CompilerConstruction/CompilerConstruction1.pdf); [ACM DL, *A note on error recovery in recursive descent parsers*](https://dl.acm.org/doi/pdf/10.1145/947902.947905)). Modern practice combines several techniques:

- **Synchronization tokens**: on an error inside an expression, skip tokens until you see a `;` or `}`.
- **Insertion/deletion of a single token** based on the follow set of the current nonterminal.
- **Error-productions**: explicit grammar rules for common mistakes ("missing semicolon before `if`"), typed with intentional error nodes.
- **Statement/definition-boundary anchoring**: parsers like rustc and Roslyn assume that even in broken code, definition boundaries are visible; they parse the outer structure first, then descend into each item independently.

For LR generators, the canonical modern approach is the *incremental error-message generation* method of Pottier used in Menhir: each LR state that can be encountered on an error is annotated with a human-written diagnostic, and the generator checks that every reachable error state is covered ([Menhir home](https://gallium.inria.fr/~fpottier/menhir/)).

### 1.9 Grammar formalisms

BNF, EBNF, and ABNF are the standard notations for context-free grammars. EBNF adds convenient postfix operators for optionality (`?`), repetition (`*`, `+`), and grouping (`{ ... }`); it was standardized as ISO/IEC 14977:1996 with Wirth as principal author ([Wikipedia, *EBNF*](https://en.wikipedia.org/wiki/Extended_Backus%E2%80%93Naur_form)). ABNF (RFC 5234) is the IETF's variant, used in nearly every network-protocol specification. W-grammars (also called two-level or affix grammars) were used to specify ALGOL 68's syntax and semantics simultaneously; they were powerful enough to encode context-sensitive rules like "an identifier declared as `int` must be used as an `int`", but the resulting definition was famously difficult to read and W-grammars have not been widely adopted since.

### 1.10 The lexer hack

C's grammar contains a decades-old ambiguity: `A * B;` is either a multiplication expression statement (if `A` is a variable) or a declaration of a pointer variable `B` (if `A` is a typedef name) ([Wikipedia, *Lexer hack*](https://en.wikipedia.org/wiki/Lexer_hack)). C's grammar is not context-free without knowing which identifiers are typedef names — so the *lexer hack* has the lexer consult a symbol table maintained by the parser and emit different tokens (`IDENTIFIER` vs `TYPEDEF_NAME`) for the same lexical form ([Wikipedia, *Lexer hack*](https://en.wikipedia.org/wiki/Lexer_hack)).

This produces a circular dependency (lexer needs parser state; parser drives lexer) that is one of the recurring sources of bugs in C compilers. The lesson for new-language authors is straightforward: **do not let identifiers be reserved words in some contexts and not others**, and **do not let type/value distinctions leak into lexical structure**. The CMU 15-411 compiler-design course uses C0 (a stripped-down C) partly so students confront the lexer hack directly ([15-411 Lab 4](https://www.cs.cmu.edu/~janh/courses/411/23/labs/lab4.pdf)).

### 1.11 Islands parsing for embedded DSLs

*Islands grammars* (Moonen, 2001) allow parsing only the interesting bits ("islands") of a language, treating everything else ("water") as opaque. They are used for source-code analysis of legacy systems and for parsing polyglot files (SQL embedded in Java strings, Regex embedded in Python). Extensions to typed foreign function interfaces and DSL macro systems are documented in Ellison and Rosu's work and later in the TFP island-parsing literature ([Erdweg et al., *Islands parsing*](https://www.khoury.northeastern.edu/home/ejs/papers/tfp12-island.pdf)).

### 1.12 Recommendation for a new language

For 90% of new languages, the right front end is: **hand-written scanner + hand-written recursive-descent parser + Pratt table for expressions**, with tree-sitter grammar shipped alongside for editors. Parser generators are appropriate for prototypes, for research languages where the grammar itself is the artifact, or when a proof of parser correctness matters (verified LR(1) generators exist for Coq/Rocq, and Menhir's disambiguation checker is machine-mechanized). PEGs and parser combinators are appropriate for embedded DSLs and configuration languages where composability matters more than error messages.

---

## Section 2: Intermediate Representations

An IR is a compiler's currency. Choosing an IR — or a stack of IRs — determines what optimizations are cheap, what analyses are possible, and how much of somebody else's compiler infrastructure you can reuse. The last twenty years have converged on three shapes: **SSA-based IRs** for general-purpose optimization, **CPS/ANF-based IRs** for functional languages, and **bytecode** for portable interpreters and VMs. LLVM's dominance for AOT compilation, MLIR's rise for domain-specific compilation, and the emergence of Cranelift as a serious LLVM alternative are the three most important IR-level trends of the past decade.

### 2.1 Three-address code and SSA

Three-address code (TAC) is the classical low-level IR: every instruction has at most one operator and three operands, of the form `x = y op z`. It maps directly to RISC assembly and has been the *lingua franca* of textbook compilers since the Dragon Book.

**Static Single Assignment (SSA)** is TAC with the additional invariant that each virtual register is assigned exactly once. Where a variable is assigned in multiple predecessor blocks, an SSA IR inserts a special *phi function* at the join point to pick the right definition ([Wikipedia, *Static single-assignment form*](https://en.wikipedia.org/wiki/Static_single-assignment_form)). This invariant makes almost every dataflow analysis dramatically simpler: def-use chains are trivial, dead code elimination is a mark-and-sweep on definitions, constant propagation is a graph walk. SSA was introduced by Cytron, Ferrante, Rosen, Wegman, and Zadeck at IBM in 1991 ([Cytron et al., original construction algorithm](http://www.cri.mines-paristech.fr/classement/doc/A-379.pdf)); simpler construction methods followed, notably Braun et al.'s "Simple and Efficient Construction of SSA" ([Braun et al.](https://link.springer.com/content/pdf/10.1007/3-540-46423-9_8.pdf)).

Nearly every modern optimizing compiler uses SSA internally: LLVM, GCC's GIMPLE-SSA, HotSpot's C1/C2, V8's TurboFan, Cranelift, Go's SSA backend (added in 1.7). A "verified construction of static single assignment form" was published at POPL 2016 ([ACM DL](https://dl.acm.org/doi/10.1145/2892208.2892211)), and the *sea-of-nodes* variant used in V8, HotSpot's C2, and Cliff Click's dissertation eliminates explicit control flow altogether by encoding it as data dependencies.

### 2.2 Continuation-passing style and A-normal form

CPS turns every function call into a tail call that receives an explicit continuation ([Wikipedia, *Continuation-passing style*](https://en.wikipedia.org/wiki/Continuation-passing_style)). It has been used as a compiler IR since the 1970s Rabbit compiler for Scheme (Guy Steele) and the ML/NJ compiler (Andrew Appel's *Compiling with Continuations*). The appeal is that CPS makes every intermediate value explicit and every control-flow operation a call, which unifies optimization passes: tail calls, non-local returns, exceptions, coroutines all become instances of the same primitive.

**A-normal form (ANF)** is CPS's more ergonomic cousin, introduced by Sabry and Felleisen in 1993. ANF requires every argument to a call or primitive to be trivial (a variable or constant), forcing intermediate results into `let`-bound temporaries. ANF preserves CPS's uniqueness of intermediate values without the visual overhead of explicit continuations ([UBC, *Compilation as Normalization*](https://open.library.ubc.ca/media/stream/pdf/24/1.0445241/4); [CS 400 Syracuse, *A-Normal Form and ANF Conversion*](https://kmicinski.com/cis400-f21/assets/slides/anf.pdf)). The debate between CPS and ANF for functional-language backends has been running for thirty years; Kennedy's "Compiling with Continuations, Continued" (2007) is the canonical modern defense of CPS ([Kennedy, ICFP 2007](https://www.ccs.neu.edu/home/shivers/cs6983/papers/compilingwithcontinuationscontinued.pdf)). Recent work at PLDI 2024 examines the low-level implications of ANF ([*A Low-Level Look at A-Normal Form*](https://dl.acm.org/doi/pdf/10.1145/3689717)).

Modern examples: OCaml's Flambda IR uses ANF-like conventions; GHC's Core is a variant of System F with `let`-bindings that plays a similar role; Guile Scheme uses CPS internally; the Racket compiler switched to CPS-Chez in 2019.

### 2.3 LLVM IR: dominance and its costs

LLVM is the closest thing to a shared middle-end that the industry has. LLVM IR is a strongly-typed, three-address, SSA-based virtual instruction set with a well-documented text and bitcode encoding; LLVM ships hundreds of optimization passes, target back-ends for every important ISA, and a huge ecosystem of tools (Clang, `opt`, `llc`, LLDB, sanitizers) ([LLVM Tutorial](https://llvm.org/docs/tutorial/MyFirstLanguageFrontend/index.html)). The Kaleidoscope tutorial walks a new-language author from lexer to JIT in a few hundred lines and remains the fastest way to get a language on LLVM ([LLVM Kaleidoscope tutorial](https://llvm.org/docs/tutorial/MyFirstLanguageFrontend/index.html)).

Languages built on LLVM include Rust, Swift, Julia, Zig, Crystal, Pony, Chapel, and Clang itself for C/C++/ObjC. The value is enormous: as soon as your front end produces valid LLVM IR, you inherit competitive code generation for every supported target and every optimization pass LLVM ever adds.

The costs are real too. LLVM compile times are notoriously long — Rust's compiler famously spends most of its time inside LLVM, which motivated the addition of a Cranelift backend for debug builds. LLVM IR is C-shaped: it assumes integer wraparound is undefined, encodes exceptions and unwinding in a specific way, and has spent years growing type-system extensions (`opaque` pointers, typed GEPs then untyped GEPs) that reflect its origin as a C++ IR rather than a universal one. Higher-level abstractions (closures, sum types, garbage-collected pointers) do not lower cleanly. And LLVM assumes AOT compilation — its JIT machinery (ORC, MCJIT) exists but is not the primary use case.

### 2.4 MLIR: the multi-level answer

MLIR ("Multi-Level Intermediate Representation") was announced in 2019 by Chris Lattner (then at Google) and has since become the substrate for a growing family of domain-specific compilers ([Lattner et al., *MLIR: A Compiler Infrastructure for the End of Moore's Law*](https://arxiv.org/pdf/2002.11054)). The paper's motivating observation is that modern compilation happens at many levels of abstraction — TensorFlow graphs, HLO, LLVM IR, GPU kernels, custom ASIC ISAs — and each level had its own ad-hoc compiler, all of which reinvented rewriting, verification, pass management, and printing/parsing infrastructure ([MLIR paper, arXiv](https://arxiv.org/pdf/2002.11054)).

MLIR provides a shared framework in which each abstraction level is a *dialect*: a set of ops, types, and attributes with declared semantics. Rewrites can cross dialect boundaries; the same infrastructure handles TensorFlow ops, linear-algebra tiling, LLVM IR, and SPIR-V. Adopters include TensorFlow (via the TF dialect), Mojo (built by Lattner's company Modular on top of MLIR), Torch-MLIR (bridging PyTorch models to MLIR), and multiple ASIC vendors' compiler stacks ([MLIR paper](https://arxiv.org/pdf/2002.11054)). For a new language that will target more than one back end (CPU + GPU + accelerator), MLIR is now a serious alternative to committing everything to LLVM IR.

### 2.5 Cranelift

Cranelift is a modern code generator written in Rust with three headline goals: **fast compilation, predictable performance, and correctness by construction** ([Cranelift home](https://cranelift.dev/)). It uses its own SSA-based IR ("CLIF") and a novel *ISLE* (Instruction Selection/Lowering Expressions) DSL for backend rules that is checked for exhaustiveness and translated to Rust code at compile time ([Cranelift README](https://github.com/bytecodealliance/wasmtime/blob/main/cranelift/README.md)).

Cranelift's primary use case is WebAssembly compilation inside Wasmtime and Firefox's WebAssembly engine, but it is also used as an experimental rustc backend for faster debug builds ([Cranelift home](https://cranelift.dev/)). The formal-methods emphasis is unusual: Cranelift's authors have published work on end-to-end verification of instruction lowering via symbolic execution against ISLE rules, and the project uses Wasmtime as its "test vehicle" ([Cranelift README](https://github.com/bytecodealliance/wasmtime/blob/main/cranelift/README.md)).

For a new-language author, Cranelift is compelling when: you want fast compilation (JIT or debug), you cannot tolerate LLVM's build-time footprint, and you are willing to give up some peak-performance optimization for correctness guarantees. The Cranelift roadmap explicitly targets the "middle 80%" of code quality — competitive with `-O1`, not `-O3`.

### 2.6 GCC's IRs, custom bytecodes, and specialty IRs

**GCC** uses a stack of IRs: GENERIC (language-independent tree form), GIMPLE (three-address, SSA), and RTL (a low-level, target-specific IR modeled on the register-transfer languages of the 1970s). GCC's stability, target coverage, and the enormous investment in RTL back-ends make it the right choice when LLVM is unavailable (older or embedded targets) or when you need political independence from Apple/Google-driven priorities.

**SPIR-V** is Khronos's binary IR for graphics and compute shaders, replacing the older text-based GLSL/SPIR at the driver interface ([Khronos SPIR-V Registry](https://registry.khronos.org/SPIR-V/)). It is used by Vulkan, OpenCL 2.1+, and WebGPU (via a transpile to WGSL). SPIR-V's SSA-based, statically-typed design is congenial to compilers, and multiple tools (`glslang`, `naga`, `slang`) can generate it. If your language targets GPUs, SPIR-V is a target you cannot avoid; MLIR has a SPIR-V dialect precisely to make this bridge easier.

**WebAssembly** occupies an interesting middle ground — it is a specified virtual ISA with a portable binary encoding, but structurally it is closer to a stack-machine bytecode than a hardware ISA. Wasm modules are the target of a growing number of language back ends (Rust, C/C++, Zig, Kotlin/JS, AssemblyScript, Go via TinyGo, .NET). The core specification is maintained by the W3C ([WebAssembly specifications](https://webassembly.org/specs/)), with feature-level proposals for GC, exception handling, threads, and SIMD progressing through a well-defined community-group process.

**Custom bytecodes** remain the right choice for pure interpreters and VMs. Python's CPython bytecode, Erlang's BEAM, Lua 5, JVM class files, and the CLR's CIL are all bespoke instruction sets tuned to their languages' semantics. Register-based (Lua 5, Dalvik) versus stack-based (JVM, CLR, Wasm) is a live design axis; see §5.

### 2.7 Tradeoffs: LLVM vs. custom

The decision tree, roughly:

| Situation | Recommended IR strategy |
|---|---|
| AOT-compiled systems language, one CPU family | LLVM |
| AOT + multiple hardware backends (CPU + GPU + accelerator) | MLIR, lower to LLVM/SPIR-V from your dialect |
| JIT-heavy dynamic language | Custom SSA IR + own back end, or Cranelift |
| Portable bytecode VM | Custom bytecode, register- or stack-based |
| Research language exploring exotic features | Small custom IR, no LLVM until later |
| Browser-first / Wasm target | Compile to Wasm; let the browser JIT do the work |
| Fast debug builds, need production LLVM later | LLVM release, Cranelift debug |

There is no universally correct choice. Zig's decision to eventually replace its LLVM dependency with self-hosted backends, Rust's investment in the Cranelift backend, and the growth of MLIR-based projects all reflect real dissatisfaction with LLVM-as-monoculture. But **for a new language shipping in the next two years, LLVM remains the fastest path to a production-quality code generator**.

---

## Section 3: Type Checking Algorithms

Type-checking algorithms have accumulated in layers. Any modern static language draws from at least three: a base checker (typically bidirectional or Hindley-Milner), a resolver for overloading (type classes, traits, or ad-hoc), and a checker for the exotic features that make the language interesting (GADTs, refinement types, linear types, effects, ownership).

### 3.1 Simply typed lambda calculus and Hindley-Milner

The simplest usable type checker is *type-checking the simply typed lambda calculus (STLC) by structural induction*. Given a context, look up variables; check that lambdas' arguments match their annotations; check that applications' function and argument types agree. This is what CS 302 teaches, and it is genuinely the core of what many modern type checkers do.

**Hindley-Milner** (also called Damas-Milner) extends STLC with implicit universal quantification and full type inference. The system was independently discovered by J. Roger Hindley (1969), Robin Milner (1978), and formally proved sound and complete by Damas and Milner in 1982 ([Wikipedia, *Hindley-Milner type system*](https://en.wikipedia.org/wiki/Hindley%E2%80%93Milner_type_system)). Milner's *Algorithm W* infers a principal type for any expression in the simply-typed lambda calculus with `let`-generalization, using constraint solving via unification. Algorithm J is a slightly more efficient variant that threads a mutable substitution rather than constructing constraints explicitly.

The core insight of HM is that if you restrict polymorphism to `let`-bindings (predicative, prenex quantification only), then unification is enough to infer every type without annotations. HM is decidable in polynomial time in practice (DEXPTIME in the worst case, but pathological cases don't arise in real code). Its offspring include ML, OCaml, Haskell, Elm, PureScript, Roc, and Grain ([HM Wikipedia article](https://en.wikipedia.org/wiki/Hindley%E2%80%93Milner_type_system)).

HM's limitations shape the modern type-system landscape:

- **Impredicativity**: HM can only quantify at the top level of a type. `∀a. (a → a) → int` is HM-legal; `(∀a. a → a) → int` is not without extensions (rank-2 or rank-N polymorphism; see §3.9).
- **Subtyping**: HM extends poorly to subtyping — unification wants exact equations, subtyping wants inequalities. Systems like MLsub reconcile the two with polar types.
- **Ad-hoc polymorphism**: HM does not natively express overloading; type classes (§3.7) are the standard extension.

### 3.2 Bidirectional type checking

The dominant type-checking paradigm for the last two decades — everything from Idris to Rust to TypeScript to Elm draws on it — is **bidirectional typing** ([Dunfield & Krishnaswami, *Bidirectional Typing*, arXiv:1908.05839](https://arxiv.org/abs/1908.05839)). The idea, formalized by Pierce and Turner in *Local Type Inference* (2000) but with earlier antecedents, is to split typing into two mutually recursive judgments: a **checking** judgment `Γ ⊢ e ⇐ A` (given expected type `A`, verify that `e` has that type) and a **synthesis** judgment `Γ ⊢ e ⇒ A` (from `e`, produce a type `A`) ([Dunfield & Krishnaswami](https://arxiv.org/abs/1908.05839)).

The magic is in how the two judgments interlock. `λx. body` is naturally checked (against a given `A → B` we know what `x` must be); function applications are naturally synthesized (from `f e`, we synth `f`'s type, then check `e` against its argument type). Annotations pivot between modes. The result is a checker that requires far fewer annotations than STLC, produces excellent error messages (mode information tells you what "should have been" the expected type), and scales to features like higher-rank polymorphism (Dunfield-Krishnaswami's "complete and easy bidirectional typechecking for higher-rank polymorphism" is the canonical reference: [Dunfield & Krishnaswami, *Complete and Easy Bidirectional Typechecking*](https://www.cl.cam.ac.uk/~nk480/bidir.pdf)) and dependent types (Coquand's version is the ancestor of every modern proof-assistant elaborator).

Bidirectional typing coexists happily with local inference within expressions — as long as annotations at function boundaries provide the "checking" context, the algorithm rarely needs to guess a polymorphic type from scratch. This is the theoretical basis for the annotation discipline of Rust, Scala, Swift, Kotlin, Idris, Agda, Lean, Roc, and F#.

### 3.3 Local vs. global inference; constraint-based inference

**Global inference** — the OCaml/Haskell tradition — collects constraints from the whole program (or module) and solves them together. This maximizes inference power (no annotations needed anywhere) but has known drawbacks: error messages can point far from the actual mistake ("type variable `α` unified in expression E1 was later required to satisfy constraint from E2, so..."), and type-directed programming (asking "what is the type of this?") is fragile.

**Local inference** — bidirectional typing with mandatory annotations at function boundaries — trades a little verbosity for enormous engineering wins: error locality, incremental type checking (change one function, only re-check it and its callers), IDE-friendly hover-and-jump, and support for features that break global inference (subtyping, higher-rank polymorphism, GADTs).

Modern OCaml and Haskell use hybrid strategies: HM as the default, with local annotations required for features (GADTs, RankNTypes) that break inference. Constraint-based inference in Haskell is implemented via the OutsideIn(X) algorithm; OCaml uses a level-based generalization scheme originally due to Didier Rémy that is remarkably efficient.

### 3.4 Unification and the occurs check

Unification is the algorithmic heart of every HM-style inference engine. Given two type terms, unification finds the most general substitution that makes them equal — or fails. Robinson's original 1965 algorithm is quadratic; Martelli-Montanari's improved algorithm is near-linear; Paterson and Wegman's is truly linear. The most important subtlety is the **occurs check**: unifying variable `α` with a type containing `α` (like `α = α → int`) must fail, or you produce an infinite type ([HM Wikipedia](https://en.wikipedia.org/wiki/Hindley%E2%80%93Milner_type_system)).

Prolog historically omitted the occurs check for performance; type inference engines cannot. Skipping it once (as a subtle bug in the early ML implementation) allowed inference of `omega = λx. x x`, which loops forever at runtime — a cautionary tale in the folklore.

### 3.5 Type classes and trait resolution

**Type classes** were introduced by Wadler and Blott in 1989 as a principled solution to ad-hoc polymorphism, first shipping in Haskell 1.0. A type class is a set of operations parameterized by a type; an *instance* declaration provides those operations for a specific type. At compile time, the compiler resolves each use of a class method by finding the appropriate instance and either inserting a dictionary parameter (the standard implementation) or specializing the code monomorphically.

Rust's *traits* are the same idea with a different design emphasis: Rust monomorphizes trait resolution by default (no runtime dictionary), which trades binary size and compile time for zero-cost abstraction and predictable performance. The comparison is a well-worn topic — see the StackOverflow discussion contrasting Rust traits with Haskell type classes ([SO: *Difference between Rust traits and Haskell type classes*](https://stackoverflow.com/questions/28123453/what-is-the-difference-between-traits-in-rust-and-typeclasses-in-haskell)) and Terbium's side-by-side ([Terbium, *Comparing Traits and Typeclasses*](https://terbium.io/2021/02/traits-typeclasses/)).

Both systems face the *coherence problem*: if two crates provide instances for the same (class, type) pair, which wins? Haskell's answer is "orphan instances are allowed but discouraged" with a warning; Rust's is stricter — the *orphan rule* requires that either the trait or the type be defined in the current crate, guaranteeing at most one impl for any (trait, type) globally. This has ecosystem-level consequences: Rust can offer stronger guarantees but sometimes forces awkward newtype wrappers.

Modern extensions include multi-parameter type classes, functional dependencies (Jones 2000), associated types (in both languages), higher-kinded polymorphism (Haskell yes, Rust no, still under RFC), and specialization (both languages, both incomplete).

### 3.6 Row polymorphism vs. subtyping

For record types, there are two main design axes: **width subtyping** (a record with fields `{a: int, b: bool, c: string}` can be used where `{a: int, b: bool}` is expected) versus **row polymorphism** (a function taking `{a: int | ρ}` accepts any record with an `a: int` field and any additional fields captured in the row variable `ρ`) ([Wikipedia, *Row polymorphism*](https://en.wikipedia.org/wiki/Row_polymorphism)).

Row polymorphism, introduced by Wand in 1987 and refined by Rémy, gives principal types and clean inference — properties subtyping-based systems struggle to preserve. Elm, PureScript, Roc, and OCaml's polymorphic variants use row polymorphism; TypeScript, Flow, and Scala use structural subtyping; Java, C#, and Swift use nominal subtyping.

The subtyping approach maps naturally to inheritance and interfaces but breaks HM inference (unification wants equations, subtyping wants inclusions). Systems like MLsub (Dolan and Mycroft 2017) recover principal-type inference in the presence of subtyping using *polar types* — a technique that has re-emerged in TypeScript and Flow's engines to handle their large type systems.

### 3.7 Higher-rank polymorphism

HM's `let`-polymorphism is *rank-1*: quantifiers appear only at the outermost level of a type. Rank-2 allows `∀`s inside a function argument's type; rank-N allows arbitrary nesting ([Wikipedia, *Higher-rank polymorphism*](https://en.wikipedia.org/wiki/Higher-rank_polymorphism)). Inference is *undecidable* for rank ≥ 3 (Wells 1994), so any language wanting higher-rank types must require annotations at the boundary — which is exactly what bidirectional typing enables (Dunfield-Krishnaswami's algorithm is complete for higher-rank types given the annotations bidirectional typing already asks for).

Rank-2 has a killer app: the ST monad in Haskell, whose `runST :: (∀s. ST s a) → a` uses rank-2 quantification to ensure that a mutable computation cannot leak its state token. Ordinary rank-2/N polymorphism appears in GHC (`RankNTypes` extension), OCaml (explicit polymorphic record fields), and effectively in Rust's higher-ranked trait bounds (`for<'a> Fn(&'a T)`).

### 3.8 GADTs

Generalized Algebraic Data Types generalize ordinary ADTs by letting each constructor specify a *specific instantiation* of the datatype's type parameters, encoding type equations that are usable when pattern-matching ([Wikipedia, *GADT*](https://en.wikipedia.org/wiki/Generalized_algebraic_data_type); [OCaml manual, *GADTs tutorial*](https://ocaml.org/manual/5.2/gadts-tutorial.html)). The canonical example is a strongly-typed AST:

```ocaml
type _ expr =
  | Int  : int  -> int expr
  | Bool : bool -> bool expr
  | Add  : int expr * int expr -> int expr
  | If   : bool expr * 'a expr * 'a expr -> 'a expr
```

Now `eval : 'a expr -> 'a` can be written by structural recursion, and the compiler will check that `eval (If (Bool true, Int 1, Int 2))` returns an `int`.

GADTs shatter HM inference: the constructor's *specific* type can flow information *into* the match branches, so an unrestricted inference algorithm has too little information at match sites. The remedy in OCaml is to require type annotations on any function that pattern-matches on a GADT ([OCaml GADTs tutorial](https://ocaml.org/manual/5.2/gadts-tutorial.html)); GHC's *OutsideIn(X)* algorithm does the same in Haskell. Rust does not have GADTs directly but the same effect can be achieved with type-level constraints on associated types.

### 3.9 Dependent type checking

Dependent types let types depend on values: `Vec n a` for "vectors of length `n`", `Ordered xs` for "the list `xs` is sorted". They subsume most of the type-system menu (GADTs, refinement types, first-class type equalities) at the cost of a much more complex checker. Modern dependently-typed languages — Agda, Idris 2, Lean 4, Rocq (formerly Coq), F* — all use an **elaboration** style checker: user syntax is progressively transformed into a small core language, with *unification*, *metavariables*, and *normalization* handling the hard parts ([CMU 15-814, *Bidirectional*](http://www.cs.cmu.edu/~fp/courses/15814-f25/lectures/09-bidirectional.pdf); [Christiansen, *Checking Dependent Types with Normalization by Evaluation*](https://davidchristiansen.dk/tutorials/nbe/)).

The three technical pillars:

1. **Normalization** (definitional equality via reduction): when comparing types, you must reduce them to normal form. Fast normalization — normalization by evaluation (NbE), typed reduction, or bytecode compilation in Lean 4 — is critical for tolerable check times.
2. **Elaboration**: user code has holes and implicit arguments; elaboration fills them by higher-order unification (Miller's *pattern unification* is the tractable fragment).
3. **Tactics** (for interactive proof): a metaprogramming language for building proofs. Coq's `Ltac`, Lean's `tactic` monad, Agda's *interaction* mode.

**Idris 2** ships *Quantitative Type Theory* — each variable carries a multiplicity annotation (`0`, `1`, or unrestricted) encoding whether the variable is erased at runtime, used exactly once (linear), or unconstrained ([Idris 2 multiplicities docs](https://github.com/idris-lang/Idris2/blob/27780073c8631826d846499840b3857d9b9a4fd5/docs/source/tutorial/multiplicities.rst)). This gives Idris 2 first-class runtime erasure of proof-only content and linear types in one system.

### 3.10 Refinement types

Refinement types constrain base types with predicates: `{v: int | v ≥ 0}` for non-negative integers, `{v: list a | length v > 0}` for non-empty lists. Type checking is decidable when the refinement logic is decidable — historically restricted to linear arithmetic and uninterpreted functions, decidable via SMT solvers like Z3 or CVC5.

Liquid Haskell is the canonical modern refinement-type system, ported from OCaml (Liquid Types by Rondon, Kawaguchi, Jhala; PLDI 2008) and shown to scale to substantial programs including a verified Haskell prelude ([Vazou, *Liquid Haskell: Haskell as a Theorem Prover*](https://goto.ucsd.edu/~nvazou/thesis/main.pdf); [Vazou et al., Haskell Symposium 2013 demo](https://www.haskell.org/haskell-symposium/2013/liquid.pdf); [Vazou et al., PL-meets-PV 2014](https://dl.acm.org/doi/10.1145/2541568.2541569)). The design tension is between expressiveness and decidability: adding quantifiers or nonlinear arithmetic pushes checking outside SMT's sweet spot, so refinement systems tend to expose escape hatches (axioms, uninterpreted symbols) that break soundness if misused.

### 3.11 Effect inference

Effect systems track *what* an expression does in addition to *what value it returns*: it might read a mutable cell, throw an exception, do I/O, allocate. Effect inference algorithms parallel type inference: the effect system is usually a lattice, effects propagate up through applications, and generalization is analogous to HM's `let`-polymorphism.

Modern examples: OCaml 5's algebraic effects and effect handlers, Koka (Daan Leijen's language, *effect types* first-class), Frank, Eff, Unison (algebraic effects called *abilities*), Effekt. Rust's *async* is a specific effect (asynchronous computation) that the compiler treats with special elaboration into state machines; Rust's *keyword generics* proposal explores generalizing the treatment to `const`, `unsafe`, and `async`.

### 3.12 Borrow checking

Rust's borrow checker is the most successful production-scale linear/affine type system in industry. Ownership rules — every value has one owner, references are either shared (`&T`, unlimited) or mutable (`&mut T`, exclusive) — are enforced by a flow-sensitive checker on Rust's MIR ([Rust MIR docs](https://rustc-dev-guide.rust-lang.org/mir/index.html); [Rust blog, *Introducing MIR*](https://blog.rust-lang.org/2016/04/19/MIR/)).

Two generations of the checker have shipped:

- **NLL (Non-Lexical Lifetimes)** — the current default checker. Introduced in Rust 2018, it uses a graph-based dataflow analysis over MIR to compute the actual span of each borrow, not the lexical span of its scope. NLL accepts many programs that the original AST-based checker rejected (notably, borrows that "end early" before their lexical scope ends).
- **Polonius** — the next-generation checker, "an experimental version of the Rust borrow checker rewritten to use Datalog and to implement a new formulation of the borrow check" ([Polonius repo](https://github.com/rust-lang/polonius); [Rust blog, *Enabling Polonius alpha*](https://blog.rust-lang.org/2026/08/04/enabling-polonius-alpha-on-nightly/)). Polonius reformulates the analysis as a Datalog program, giving both a cleaner mathematical description and the ability to detect additional legitimate patterns that NLL rejects. The blog announcement notes that Polonius is being staged in on nightly with an "alpha" feature flag, enabling additional patterns that NLL cannot express while preserving all NLL-accepted programs ([Polonius alpha blog](https://blog.rust-lang.org/2026/08/04/enabling-polonius-alpha-on-nightly/)).

The formal correctness of Rust's borrow-checker discipline is the subject of the RustBelt project (§4.9).

### 3.13 Practical tips

Two engineering rules from watching many language projects:

- **Design for incrementality from day one.** A type checker that must re-check the world on every edit is unusable in an IDE. Track the file-level dependency graph, cache per-item results, and design your type system so that renaming a local variable in function `foo` never requires re-checking module `bar`.
- **Optimize error messages before optimizing checker speed.** Users are more sensitive to *understandable* errors than to *fast* errors. Elm's famous friendly errors, Rust's `--explain` codes, and Roc's hyperlinked errors set the modern bar; a language that stops at "type error at line 42" is a language that people quietly stop using.

---

## Section 4: Memory Management Deep Dive

Memory management is where language design most visibly touches machine reality. A new language must choose a model — manual, reference-counted, tracing, region-based, ownership-based, or hybrid — and every subsequent decision (concurrency, C interop, real-time capability, footprint) will be shaped by that choice. This section surveys the menu.

### 4.1 Manual allocation strategies

Even languages with automatic memory management use manual strategies internally. The four common patterns:

- **Bump allocator** ("linear" or "arena"): a pointer into a large region, incremented by each allocation. Deallocation is impossible per-object; the whole region is freed at once. Extremely fast; used inside young-generation GC nurseries, per-request arenas in web servers, and Zig/Rust `bumpalo`-style short-lived contexts.
- **Freelist**: allocated blocks are recycled into a singly-linked list on free. `malloc` implementations (dlmalloc, jemalloc, mimalloc) are elaborate freelists with size classes.
- **Arena**: a bump allocator whose lifetime matches a *scope* (a request, a game tick, a compiler pass). Trades peak memory for allocation speed.
- **Slab allocator**: introduced by Bonwick in SunOS 5.4 (1994), a slab pre-allocates a slab of same-sized objects and initializes them once at pool creation. Amortizes constructor cost when the same object type is repeatedly allocated and freed. Used in the Linux kernel (`SLAB`, `SLUB`, `SLOB` allocators) and in some VM garbage collectors.

### 4.2 Reference counting

Reference counting attaches a counter to every heap object; each new reference increments, each drop decrements, and the object is freed when the counter reaches zero. It has ancient roots (Collins 1960) and remains attractive because of its **prompt deallocation** (memory reclaimed at the moment the last reference dies), **incremental cost profile** (no stop-the-world pauses), and **simple integration with foreign code** (any refcount can be pinned by an external reference).

Its two well-known problems:

1. **Cycles are not collected.** A cyclic structure keeps itself alive: `a → b → a` has both counts at 1 with no external references.
2. **Update cost.** Each refcount adjustment is a memory write, and in concurrent code an atomic RMW. Deutsch and Bobrow's 1976 *deferred reference counting* postpones counting local (stack) references to amortize the cost.

The canonical modern solution to cycles is **Bacon and Rajan's cycle collector** (2001, refined 2003), a concurrent tri-color algorithm that periodically scans "candidate roots" (objects whose refcount was decremented but did not reach zero) and looks for cycles by trial-deleting internal edges ([Bacon et al., *A Unified Theory of Garbage Collection*](https://web.eecs.umich.edu/~weimerw/2012-4610/reading/bacon-garbage.pdf); [Bacon-Rajan on-the-fly cycle collection paper](https://scispace.com/pdf/an-efficient-on-the-fly-cycle-collection-45a6fngtue.pdf)). CPython uses this algorithm; PHP, Perl, and Objective-C historically used ref-counting without cycle collection and relied on programmer discipline to break cycles with weak references.

Bacon, Cheng, and Rajan's *A Unified Theory of Garbage Collection* (OOPSLA 2004) is essential background reading: it shows that "reference counting and tracing are two dual approximations of a single ideal garbage collector," with hybrid systems occupying a continuous space between the extremes ([*Unified Theory of GC*](https://web.eecs.umich.edu/~weimerw/2012-4610/reading/bacon-garbage.pdf)).

### 4.3 Tracing GC: mark-sweep, mark-compact, copying, generational

The tracing family walks the object graph from roots (registers, stack, globals) and reclaims whatever is not reached.

- **Mark-sweep** (McCarthy 1960): mark reachable objects; sweep the heap freeing unmarked ones. Simple, but fragments the heap and touches every object during sweep.
- **Mark-compact**: after marking, slide live objects together to compact the heap. Eliminates fragmentation; requires updating every pointer. Two-finger, lisp2, and threaded variants exist ([Wikipedia, *Mark-compact algorithm*](https://en.wikipedia.org/wiki/Mark%E2%80%93compact_algorithm)).
- **Copying / Cheney (1970)**: divide the heap into two semispaces; on collection, copy all reachable objects from `from-space` to `to-space` and flip the roles. Bandwidth cost is proportional to live data (not heap size), and compaction is automatic. Cheney's algorithm uses `to-space` itself as the BFS queue via two pointers (`scan` and `free`), so the algorithm needs no auxiliary stack ([Wikipedia, *Cheney's algorithm*](https://en.wikipedia.org/wiki/Cheney's_algorithm)).
- **Generational** (Ungar 1984): allocate everything in a *young generation*; promote survivors to an *old generation*. The *weak generational hypothesis* — most objects die young — makes young-generation collection extremely cheap. Nearly every modern GC is at least two-generation.

Wilson's 1992 survey *Uniprocessor Garbage Collection Techniques* remains a standard reference ([Wilson survey](https://courses.grainger.illinois.edu/CS426/fa2022/Papers/wilson.gc.bigsurv.pdf)); the Jones-Hosking-Moss *Garbage Collection Handbook* is the current canonical treatment ([Kent GC handbook page](https://www.cs.kent.ac.uk/people/staff/rej/gc.html)).

### 4.4 Modern production GCs

**HotSpot G1** (Garbage-First, JDK 9 default) is a region-based, incremental, mostly-concurrent, generational collector. G1 divides the heap into 2048 regions of 1–32 MB each and collects the "garbage-first" regions preferentially to meet a soft pause-time target.

**Shenandoah** (Red Hat, first shipped 2016 in OpenJDK) is a *concurrent compacting* GC with a soft goal of <10 ms pauses ([Red Hat, *A beginner's guide to Shenandoah*](https://developers.redhat.com/articles/2024/05/28/beginners-guide-shenandoah-garbage-collector)). Shenandoah is region-based like G1 but **not generational** (originally; a generational Shenandoah landed later), and it "compacts concurrently, thus avoiding fragmentation issues" ([Red Hat blog](https://developers.redhat.com/articles/2024/05/28/beginners-guide-shenandoah-garbage-collector)). The concurrent compaction uses *Brooks forwarding pointers* (extra word per object) and *snapshot-at-the-beginning (SATB)* marking, borrowed from CMS and G1 ([Red Hat blog](https://developers.redhat.com/articles/2024/05/28/beginners-guide-shenandoah-garbage-collector); [Shipilev's Shenandoah slides](https://shipilev.net/talks/jfokus-Feb2018-shenandoah.pdf)).

**ZGC** (Oracle, OpenJDK JEP 333) targets pause times below 10 ms on multi-terabyte heaps ([JEP 333](https://openjdk.org/jeps/333)). Its key innovations are *colored pointers* (unused high bits of the pointer encode GC state — marked, remapped, finalizable) and *load barriers* that consult those bits on every read. Pause-time goals in the JEP: sub-10 ms; heap sizes from a few MB to many TB; throughput cost under 15% ([JEP 333](https://openjdk.org/jeps/333)). Details of the implementation are covered in Per Lidén's FOSDEM 2018 slides ([FOSDEM slides](https://cr.openjdk.org/~pliden/slides/ZGC-FOSDEM-2018.pdf)).

**Azul C4** ("Continuously Concurrent Compacting Collector") is a generational, "pauseless" GC descended from the Azul Systems Vega and Zing JVMs; it uses read barriers (via GPGC / LVB — loaded value barrier) to concurrent-relocate objects and maintain pause times independent of heap size ([Azul C4 docs](https://docs.azul.com/prime/c4-garbage-collection.html)). C4 has run production JVMs with heaps of 2+ TB with sub-millisecond pauses.

**Go's tri-color concurrent GC** is a *non-generational, non-moving, mostly-concurrent mark-sweep* collector. Non-moving simplifies interoperation with Go's *stack maps* (each goroutine's stack is precisely typed) and with C code accessed via cgo. Tri-color marking uses white/gray/black object colors and a write barrier to maintain the invariant that black objects never point to white ones during collection. Recent evolution has cut pause times to well below 1 ms in most workloads.

**.NET Server GC** is generational (three generations plus a Large Object Heap), with per-CPU heap segments and background collection for gen2. Recent .NET versions added *POH* (Pinned Object Heap) to isolate pinned objects that hurt compaction.

**V8's Orinoco** is the Chrome/Node.js GC, a generational, mostly-concurrent, mostly-parallel collector ([V8 blog, *Orinoco*](https://v8.dev/blog/orinoco); [V8 blog, *Trash talk*](https://v8.dev/blog/trash-talk)). Orinoco's young generation (Scavenger) is a copying collector; the old generation is mark-compact with concurrent marking. Orinoco moved the GC largely off the JavaScript thread, shrinking main-thread GC time from ~100 ms to a few ms in typical browsing.

Comparison of major production GCs:

| Collector | Ships in | Generational | Moving | Concurrent | Pause goal | Notes |
|---|---|---|---|---|---|---|
| HotSpot Parallel | OpenJDK | Yes | Yes | No (STW) | throughput-first | Legacy default |
| HotSpot G1 | OpenJDK (default) | Yes | Yes | Mostly | soft <200ms | Region-based |
| Shenandoah | OpenJDK (Red Hat) | Optional | Yes (concurrent compaction) | Yes | <10ms soft | Brooks pointers ([Red Hat](https://developers.redhat.com/articles/2024/05/28/beginners-guide-shenandoah-garbage-collector)) |
| ZGC | OpenJDK | Now yes | Yes | Yes | <10ms hard | Colored pointers, load barrier ([JEP 333](https://openjdk.org/jeps/333)) |
| Azul C4 | Azul Prime JDK | Yes | Yes (concurrent) | Yes | sub-ms | LVB read barrier ([Azul](https://docs.azul.com/prime/c4-garbage-collection.html)) |
| Go GC | Go runtime | No | No | Yes | <1ms typical | Tri-color, write barrier |
| .NET Server | .NET runtime | Yes (3+POH) | Yes | Bg for gen2 | tunable | Per-CPU heaps |
| V8 Orinoco | Chrome, Node | Yes | Yes | Mostly | main-thread ~ms | Scavenger + M-C ([V8 blog](https://v8.dev/blog/orinoco)) |

### 4.5 Nim's ARC/ORC hybrid

Nim's default memory model since 1.4 is **ARC**: deterministic reference counting inserted by the compiler, with *move semantics* eliding refcount operations on obvious transfers ([Nim blog, *Introduction to ARC/ORC*](https://nim-lang.org/blog/2020/10/15/introduction-to-arc-orc-in-nim.html)). Aliases are counted at compile time using owned/borrowed distinctions similar to Rust's, but with less compiler enforcement.

**ORC** extends ARC with a cycle collector for the (small subset of) types that can form cycles — types that mention `ref` are marked "acyclic" or "possibly-cyclic" via a static analysis, and the collector runs only over the possibly-cyclic subset ([Nim blog](https://nim-lang.org/blog/2020/10/15/introduction-to-arc-orc-in-nim.html)). The result is deterministic-in-common-case, GC-in-worst-case behavior — one of the more interesting recent memory-management designs.

### 4.6 Swift's ARC and its limitations

Swift inherits Automatic Reference Counting from Objective-C. The compiler inserts `retain` and `release` operations at ownership boundaries; the reference-counting overhead is real but generally acceptable, and cycles are broken by programmer-declared `weak` and `unowned` references ([Swift docs, *ARC*](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/automaticreferencecounting/)).

Swift's ARC has three practical limitations:

- **Cost**: retain/release are atomic on threading-shared objects; the aggregate cost is measurable in tight loops, and Swift has invested heavily in optimizations (ARC elision, non-atomic refcounts on value types, ownership annotations under `swift-experimental-string-processing` and OwnershipSSA).
- **Cycles**: cycle detection is manual; forgetting to `weak` a delegate is a common memory leak.
- **Determinism vs. concurrency**: refcount operations serialize otherwise-independent threads. Swift 5.9+ introduced *ownership* keywords (`consuming`, `borrowing`) to let programmers opt into Rust-like non-copyable types, sidestepping ARC entirely for performance-critical code.

### 4.7 Erlang's per-process heap approach

The BEAM VM runs a *per-process heap*: each Erlang process has its own private heap and its own garbage collector ([Erlang docs, *Garbage collection*](https://www.erlang.org/doc/apps/erts/garbagecollection.html)). Data is either copied between processes on message send (small messages), or stored in a shared *binary heap* (large binaries are reference-counted by the binary sub-allocator, small ones are copied).

The design gives Erlang two remarkable properties:

- **Isolation**: collection of one process cannot pause another. On a 100-CPU machine, 100 collections can run in parallel with zero contention.
- **Predictable pauses**: process heaps are typically small (~200 words to a few MB), so collection is fast; the BEAM uses a generational two-generation copying collector per process ([Erlang GC docs](https://www.erlang.org/doc/apps/erts/garbagecollection.html)).

The tradeoff is memory: many processes replicate common data, and the shared binary heap requires reference-counting logic separate from the tracing collector.

### 4.8 Region-based memory (Tofte/Talpin, Cyclone, Vale)

Tofte and Talpin's *region-based memory management* (POPL 1994, later journal versions) was an ambitious attempt to replace GC entirely with a *region inference* algorithm that assigns each allocation to a region whose lifetime is a well-defined program scope ([Wikipedia, *Region-based memory management*](https://en.wikipedia.org/wiki/Region-based_memory_management)). The ML Kit compiler implemented the technique; regions are pushed on scope entry and popped on scope exit, and every allocation goes into some enclosing region.

Cyclone (Grossman, Hicks, Jim, Morrisett, Wang; USENIX 2002 and later) took the idea into a C-like language: programmers *annotate* regions and pointers with region-of information, and the compiler's static rules ensure that no pointer escapes its region ([Cyclone regions paper](https://www.cs.cornell.edu/Projects/cyclone/papers/cyclone-regions.pdf)). Cyclone influenced Rust directly.

**Vale** revived and modernized the idea. Vale's core mechanism is *generational references*: every heap allocation gets a per-allocation *generation counter*, and pointers into it carry an expected generation; on deref, mismatched generations trigger a fault ([Vale, *Generational references*](https://verdagon.dev/blog/generational-references)). This gives memory safety without GC and without Rust-style ownership discipline, at the cost of one extra word per pointer and one comparison per deref. Vale's region system layers on top, allowing programmers to move computation into *sub-regions* with different memory-management strategies ([Vale, *Regions*](https://vale.dev/guide/regions)). The Vale author's blog posts on the design ([verdagon.dev](https://verdagon.dev/blog/generational-references)) are among the clearest explorations of hybrid memory management in the literature.

### 4.9 Rust's ownership model and RustBelt

Rust's ownership discipline can be viewed as a *linear/affine* type system for memory: every value has exactly one owner (affine — can be dropped early but not duplicated), and borrows (references) are second-class, statically scoped, and either aliased-immutable or exclusive-mutable. Ownership plus borrowing plus lifetimes plus the borrow checker (§3.12) is enough to guarantee both memory safety *and* data-race freedom without a garbage collector.

The formal-semantics investigation of Rust's guarantees is the **RustBelt project** (Jung, Jourdan, Krebbers, Dreyer; POPL 2018). RustBelt gives a machine-checked (in Coq) proof of soundness for a "realistic subset of Rust" including unsafe internals of `Cell`, `RefCell`, `Rc`, `Arc`, `Mutex`, `RwLock`, and `mem::swap` ([RustBelt POPL18 paper](https://plv.mpi-sws.org/rustbelt/popl18/paper.pdf)). The technique: introduce a *lifetime logic* built on the Iris separation-logic framework and prove that each `unsafe` primitive is *safely encapsulated* — its exported (safe) interface respects a semantic invariant even though its internals violate the surface-syntactic borrow rules.

RustBelt is the single most important piece of formal work on any modern industrial language. It shifted the intellectual center of gravity on Rust from "we hope the borrow checker is right" to "the encapsulated `unsafe` idiom has a rigorous soundness argument."

### 4.10 Linear and affine types for memory

Linear types (Girard 1987) demand each value be used *exactly once*; affine types allow at most once. Both give a static handle on resource management, of which memory is just one instance. Linear Haskell (a language extension since GHC 9), Clean's uniqueness types, and Rust's ownership are the production-scale examples. A survey of the design landscape connects the dots between substructural type systems and safe memory management ([Borretti, *Type systems and memory safety*](https://borretti.me/article/type-systems-memory-safety)).

Idris 2's *Quantitative Type Theory* (§3.9) is a natural marriage: multiplicities on binders let the type system express linear, affine, and unrestricted values in one framework, with linear used for resource-like values and 0 for compile-time-erased content ([Idris 2 multiplicities](https://github.com/idris-lang/Idris2/blob/27780073c8631826d846499840b3857d9b9a4fd5/docs/source/tutorial/multiplicities.rst)).

### 4.11 Concurrent GC challenges

Any concurrent GC must solve two related problems: keeping the mutator (application) running while collecting, and correctly tracking objects the mutator is creating or overwriting during the collection.

- **Write barriers** intercept every heap store and record ("remember") the modification so the collector can re-scan. Dijkstra's, Steele's, and Yuasa's are the classic tri-color barriers; SATB (snapshot-at-the-beginning) records the *old* value being overwritten, standing in for a snapshot; incremental-update barriers record the *new* value.
- **Read barriers** intercept loads; used by Shenandoah (Brooks pointer load barrier) and ZGC (colored-pointer load barrier) to redirect stale pointers.
- **Safepoints**: places where the collector can inspect a mutator thread's stack. HotSpot and Go both use polling safepoints; getting the polling frequency right is a major engineering effort.

### 4.12 Real-time GC

**Metronome** (Bacon, Cheng, Rajan; PLDI 2003) is the canonical real-time collector: it interleaves collection with mutator execution at fine granularity to bound worst-case pause times ([Metronome paper](https://dl.acm.org/doi/10.1145/780732.780744)). The key idea is *time-based scheduling*: rather than "collect when full", the collector runs periodically and does exactly the amount of work required to keep up with allocation. IBM's WebSphere Real Time and the DoD's mission-critical Java uses draw on Metronome descendants.

**Baker's Treadmill** (Henry Baker 1992) is an earlier real-time collector: allocation and reclamation both consume constant time by maintaining objects on a doubly-linked list and moving them between color regions in constant work.

### 4.13 Practical memory safety: sanitizers and hardware

For languages compiled to native code, dynamic sanitizers catch most memory bugs in testing:

- **AddressSanitizer (ASan)**: use-after-free, buffer overflow, memory leaks; ~2× slowdown, ~2–3× memory. Standard in Clang and GCC.
- **MemorySanitizer (MSan)**: uninitialized reads.
- **ThreadSanitizer (TSan)**: data races.
- **UBSan**: undefined behavior in C/C++.

Hardware assists have started to appear:

- **ARM PAC (Pointer Authentication)**: signs pointer values with a per-process key, catching most ROP/JOP attacks. Ships in iOS since A12, in production Linux on Apple Silicon.
- **ARM MTE (Memory Tagging Extension)**: tags every 16 bytes of memory with a 4-bit tag and every pointer with the same 4-bit tag; a mismatch traps. Ships on Pixel 8+ in developer preview form; a hardware-accelerated ASan-equivalent at ~1.1× overhead. Widespread deployment is expected on Android in the second half of this decade.

---

## Section 5: Runtimes and VMs

Once the compiler stops, the runtime begins. For interpreted or JITted languages, the runtime is the whole show; for AOT languages, it is a smaller-but-critical layer (allocator, exception unwinder, coroutine scheduler, syscall wrappers). This section surveys the interpreter/VM/JIT design menu.

### 5.1 Bytecode interpreter dispatch

A bytecode interpreter is fundamentally a loop over instructions, and the loop's dispatch style is one of the highest-leverage engineering choices in an interpreter's performance.

- **Switch dispatch**: the naive `while(true) switch(*ip++) { case OP_ADD: ...; case OP_MUL: ...; }`. Simple, portable, generates poor branch predictions (one shared indirect branch).
- **Threaded code (direct threading)**: each bytecode carries the address of its handler; each handler ends with `goto *next->handler`. First described by Bell (1973); Anton Ertl's *Threaded Code* survey remains the reference. Improves branch prediction because each opcode has its own indirect jump site.
- **Computed goto** (`&&label` in GCC): a portable-ish way to get threaded code in C. Eli Bendersky's tutorial is the standard introduction ([Bendersky, *Computed goto for efficient dispatch tables*](https://eli.thegreenplace.net/2012/07/12/computed-goto-for-efficient-dispatch-tables)); CPython adopted computed goto in 3.1 for a 15–20% speedup and again with the specializing adaptive interpreter in 3.11+.
- **Superinstructions**: fuse common opcode pairs into a single opcode. Reduces dispatch cost per "logical" operation.
- **Inline threading** and **subroutine threading**: variants with different tradeoffs between call/return overhead and code size.

The literature on dispatch is deep (Ertl, Piumarta, Vitale). For a new bytecode interpreter, the practical recipe: start with `switch` for portability, switch to computed goto behind a feature flag, add superinstructions once the hot path is known.

### 5.2 Register-based vs. stack-based VMs

The two families:

- **Stack-based**: instructions implicitly consume and produce values on an evaluation stack. Simple encoding (opcodes have no register operands), simple compilation from AST. JVM, .NET CIL, WebAssembly, Python bytecode.
- **Register-based**: instructions name their operands via virtual register numbers. Fewer instructions per operation (`add r1, r2, r3` versus `push r1; push r2; add; pop r3`), fewer dispatch loops, generally faster in interpreters. Lua 5, Dalvik, LuaJIT bytecode.

The Ierusalimschy/Figueiredo/Celes paper *The Implementation of Lua 5.0* is the canonical explanation of why Lua's switch to a register-based VM in 5.0 was a large speedup ([Lua paper](https://www.lua.org/doc/jucs05.pdf)). Their measurements showed the switch reduced dispatch overhead and, more importantly, eliminated many "shuffling" instructions that stack VMs need to arrange operands.

Stack VMs win on encoding compactness (crucial for JVM class files) and on ease of verification (each stack slot's type is derivable statically); register VMs win on interpreter throughput.

### 5.3 Tracing JITs vs. method JITs

**Method JIT**: compile whole methods. HotSpot's C1 and C2, V8's TurboFan, .NET's RyuJIT. Simpler mental model; benefits from decades of static-compiler optimization work.

**Tracing JIT**: record a linear trace of executed instructions across function boundaries, then compile the trace as a single optimized block with guards. LuaJIT (Mike Pall) and PyPy (Bolz et al.) are the canonical modern examples. Tracing JITs excel at hot loops that call many small functions — the trace inlines all the calls automatically — but pay a cost when execution leaves the trace (a *guard failure* deopts back to the interpreter).

PyPy's authors published *Tracing the Meta-Level: PyPy's Tracing JIT Compiler* (Bolz et al., 2009) introducing *meta-tracing*: rather than tracing the Python program directly, PyPy's tracer traces the PyPy interpreter running the Python program. The result is that PyPy gets a fast JIT for essentially free from writing a straightforward interpreter in RPython — a design idea that has since been reused in several projects ([Bolz et al., original meta-tracing paper](https://www.dom.parnaiba.pi.gov.br/assets/diarios-anteriores/bolz-tracing-jit-final.pdf); [PyPy blog, *Musings on tracing*](https://www.pypy.org/posts/2025/01/musings-tracing.html)). A 2025 PyPy reflection notes that the meta-tracing approach has now been running in production for over a decade and continues to yield 2–10× speedups on numeric and object-heavy Python workloads ([PyPy blog](https://www.pypy.org/posts/2025/01/musings-tracing.html)).

### 5.4 Tiered compilation

Nearly every serious JIT today is tiered: an initial fast baseline tier gets code running quickly; a slower optimizing tier recompiles hot code with the benefit of runtime profiling. The tiers vary:

- **HotSpot**: interpreter → C1 (client, fast) → C2 (server, expensive optimizations) → back to interpreter on deopt.
- **V8**: Ignition (interpreter) → Sparkplug (baseline JIT, unoptimized machine code) → Maglev (mid-tier) → TurboFan (top-tier optimizing) ([V8 TurboFan blog](https://v8.dev/blog/turbofan-jit); [V8 TurboFan docs page](https://v8.dev/docs/turbofan)).
- **.NET**: interpreter (rare in .NET) or tier-0 JIT → tier-1 JIT with instrumentation feedback. Modern .NET (7+) uses *dynamic PGO* to feed profile data from tier-0 into tier-1.
- **WebAssembly in V8**: Liftoff (baseline, single-pass template compiler with function-level parallelism) → TurboFan (optimizing) ([V8 Liftoff blog](https://v8.dev/blog/liftoff); [V8 wasm compilation pipeline](https://v8.dev/docs/wasm-compilation-pipeline)).

Microsoft's dev blog explains OpenJDK's tiered compilation in detail: five tiers numbered 0–4, from interpreter through C1-with-profiling to C2, with clear transitions based on invocation counts and back-edge counts ([Microsoft, *How tiered compilation works in OpenJDK*](https://devblogs.microsoft.com/java/how-tiered-compilation-works-in-openjdk/)).

### 5.5 Deoptimization and OSR

**Deoptimization** ("deopt") is the runtime capability to *undo* an optimization when its assumptions are violated. If TurboFan compiled `foo` assuming argument `x` was always an integer, and someone now calls `foo("hello")`, the JIT must bail out to the interpreter mid-execution — reconstructing the interpreter state (bytecode PC, expression stack) from the optimized machine state ([V8 TurboFan blog](https://v8.dev/blog/turbofan-jit)). This is one of the hardest engineering problems in a modern VM.

**On-Stack Replacement (OSR)** is the mirror image: begin execution in the interpreter, then swap in optimized code *for a currently-executing function*. Essential for long-running loops that never leave a single function invocation.

### 5.6 Inline caching and polymorphic dispatch

Inline caches (ICs) accelerate dynamic dispatch by remembering, at each call site, what the receiver's shape was last time. First introduced in the *Self* language (Chambers, Ungar, Lee 1989; Hölzle, Chambers, Ungar 1991), inline caching turns a hash-table lookup into a shape-check plus a direct call for the common case ([Hölzle et al., *Optimizing Dynamically-Typed Object-Oriented Languages*](https://research.google.com/pubs/archive/37204.pdf)).

- **Monomorphic IC**: remember one shape.
- **Polymorphic IC** (PIC): remember up to N shapes with a small chain of shape-check-and-dispatch.
- **Megamorphic**: too many shapes; fall back to a dictionary lookup.

Every JavaScript engine, PyPy, LuaJIT, and modern JVM dispatch machinery (`invokedynamic` and `invokevirtual`) use some form of inline caching. Hidden classes (V8's *Maps*, JavaScriptCore's *Structures*) are the data structure that makes ICs effective for dynamic property access: the compiler assigns each object a "shape" descriptor that captures its property layout, so an IC can check shape identity rather than property presence.

### 5.7 Adaptive optimization

Urs Hölzle's PhD work at Self and later at Sun (Java HotSpot) established the modern *adaptive-optimization* discipline: profile in the baseline tier, identify hot methods, inline aggressively guided by profile, use speculation guarded by deoptimization. Hölzle's *Optimizing Dynamically-Typed Object-Oriented Languages* thesis remains a foundational reference ([Hölzle Google paper archive](https://research.google.com/pubs/archive/37204.pdf)). Every production JIT today — HotSpot, V8, TurboFan, RyuJIT, GraalVM, JavaScriptCore — is a refinement of this basic idea.

### 5.8 Escape analysis and stack allocation

*Escape analysis* determines whether an allocation can be replaced with stack allocation because no reference to it escapes the current function. First formalized for object-oriented languages by Choi et al. and Blanchet in 1999 ([Wikipedia, *Escape analysis*](https://en.wikipedia.org/wiki/Escape_analysis)), escape analysis reduces GC pressure by moving short-lived allocations onto the stack.

The Go compiler uses escape analysis pervasively: developers can inspect the analysis with `-gcflags=-m`. HotSpot performs *scalar replacement* — an even more aggressive form that decomposes an object into its scalar fields, allocated in registers or stack slots. LLVM's `promotable_alloca`/mem2reg does the same for `alloca` in C-like languages.

### 5.9 The BEAM VM architecture

The BEAM (Bogdan/Björn's Erlang Abstract Machine, in the Erlang OTP distribution) is one of the most distinctive VM designs in production. Robert Virding's and Björn Gustavsson's design, documented at length in *The BEAM Book* (Stenman) ([The BEAM Book](https://blog.stenmans.org/theBeamBook/)):

- **Per-process everything**: each Erlang process has its own heap, its own stack, its own GC, its own mailbox.
- **Reduction counting for preemption**: the BEAM does not use OS preemption. Each process is granted a *reduction budget* (typically 2000 reductions ≈ function calls); when the budget is exhausted, the scheduler swaps the process out. This gives *soft real-time* behavior without OS-level context-switch costs ([AppSignal, *Deep diving into the Erlang scheduler*](https://blog.appsignal.com/2024/04/23/deep-diving-into-the-erlang-scheduler.html)).
- **Message passing**: sends copy data (except large binaries and off-heap references) into the receiver's heap, preserving isolation.
- **SMP schedulers**: one scheduler thread per hardware core, each with its own run queue; work-stealing balances between them.

The result: Erlang systems run millions of concurrent processes at low latency with no explicit thread management, no data races, and per-process GC pauses bounded by the process's tiny heap.

### 5.10 WebAssembly runtimes

WebAssembly is a portable binary instruction format designed for near-native execution speed in a sandbox. The core specification is maintained by the W3C ([Webassembly specifications](https://webassembly.org/specs/)); each runtime chooses its own engine.

- **Wasmtime** — Bytecode Alliance's runtime, backed by Cranelift for compilation. Focus on standalone (server, edge) execution.
- **Wasmer** — commercial runtime with multiple backends (Cranelift, LLVM, Singlepass).
- **WAMR** (WebAssembly Micro Runtime) — Intel-led project targeting embedded systems, with interpreter, ahead-of-time, and just-in-time modes.
- **V8**: uses Liftoff for baseline compilation (single-pass, function-level parallelism, small memory footprint) and TurboFan for optimizing tier ([V8 Liftoff blog](https://v8.dev/blog/liftoff); [V8 wasm pipeline docs](https://v8.dev/docs/wasm-compilation-pipeline)). Liftoff generates code "one WebAssembly instruction at a time" and skips register allocation for the sake of compilation speed ([V8 Liftoff blog](https://v8.dev/blog/liftoff)); TurboFan takes over for hot functions.

For a new language targeting the browser or the growing serverless-Wasm ecosystem, compiling to Wasm and inheriting one of these engines is now a serious alternative to bringing your own VM.

---



### 5.11 Interpreter dispatch techniques in depth

The choice of dispatch mechanism in a bytecode interpreter is a factor-of-two performance decision made once, at the start of implementation, and difficult to change later. The four common choices:

**Switch dispatch.** The interpreter is a `while(true) switch(*ip++) { case OP_ADD: ... case OP_SUB: ... }`. Portable to any C-family language; usually 2–4x slower than the alternatives because the CPU's branch predictor sees one indirect branch per bytecode, and every branch-mispredict costs 10–20 cycles.

**Direct threaded code.** Each bytecode is replaced with the address of its handler; the interpreter is `goto *ip[0]`. This requires GCC/Clang's *labels as values* extension (`&&label` syntax) and computed goto (`goto *ptr`). Eli Bendersky's canonical explanation with benchmarks shows a ~2x speedup over switch on typical bytecode workloads ([Computed goto for efficient dispatch tables](https://eli.thegreenplace.net/2012/07/12/computed-goto-for-efficient-dispatch-tables)). The reason is that the CPU branch predictor now sees one branch per handler *per opcode kind*, dramatically improving prediction accuracy.

**Indirect threaded code.** Each bytecode contains a pointer to a data cell holding the handler pointer. Slightly slower than direct threaded but more relocatable — historically important on architectures where code couldn't easily hold arbitrary addresses.

**Subroutine threaded code.** Each bytecode is a call to a handler. Modern predictors handle this well, and stack traces preserve information, but function call overhead is nonzero.

**Superinstructions.** Combine frequently-occurring bytecode sequences into a single opcode. If `LOAD_CONST 0; ADD` is common, add a `LOAD_CONST_0_ADD` opcode. Reduces dispatch overhead proportionally to how many originals it replaces. CPython experimented with this; PyPy's meta-tracing effectively synthesizes superinstructions dynamically ([PyPy tracing post](https://www.pypy.org/posts/2025/01/musings-tracing.html)). Wasm interpreters use superinstructions aggressively.

Register-based versus stack-based is an orthogonal dimension. The Lua paper reports that switching Lua 5 from stack-based to register-based bytecode reduced instruction count by about 45% while adding only modestly to per-instruction cost, for a net speed win ([Lua paper](https://www.lua.org/doc/jucs05.pdf)). The general lesson: register-based bytecode has larger instructions but fewer of them; stack-based is more compact and simpler to compile *to*, hence its dominance on hostile hardware and on VMs that expect user-portable bytecode (JVM, CLR, Wasm).

### 5.12 The BEAM in depth: reduction counting and preemption

The Erlang BEAM VM's approach to concurrency deserves its own treatment because it solves a hard problem (preemptive scheduling of millions of tasks) with an elegant idiomatic trick.

Every function invocation costs one *reduction*. A process is scheduled until it either blocks (waiting on a message), calls out to a NIF that yields, or accumulates 4000 reductions ([BEAM Book](https://blog.stenmans.org/theBeamBook/); [Erlang scheduler dive](https://blog.appsignal.com/2024/04/23/deep-diving-into-the-erlang-scheduler.html)). At 4000 reductions the scheduler swaps the process out and picks another runnable one. Because reductions are a compile-time-observable quantity — the compiler knows exactly how many reductions each bytecode consumes — the scheduler can be preemptive *without* preemption interrupts. The runtime cost is a decrement-and-compare at every function-call site, comparable to the overhead of an inline cache check in a JIT.

Long-running work that isn't function-heavy (a big regex match, a cryptographic hash) is a threat to this model: it would starve the scheduler. BEAM handles this in two ways: NIF functions that intend to run long *must* yield explicitly (via `enif_schedule_nif` and reduction bumps), and the runtime's *dirty scheduler* pool absorbs NIFs that can't yield.

Per-process heaps make the whole scheme viable. Because each process's heap is disjoint from every other's, GC on one process is invisible to the rest of the system — no whole-VM STW pause. Message-send between processes copies the message; the target's heap grows a bit, the source's shrinks; nothing needs to be paused ([Erlang GC docs](https://www.erlang.org/doc/apps/erts/garbagecollection.html)).

The tradeoff: message-passing copy cost is nonzero, and huge messages hurt. But for real Erlang workloads (short-lived, small-message-rate-limited processes), the model produces astonishingly good latency profiles: BEAM systems routinely hold p99 latencies under 10 ms with millions of concurrent connections, on modest hardware.

### 5.13 Wasm as a target language

WebAssembly deserves special attention as a *runtime target* because it changes the deployment story for a language substantially.

Every major browser ships a production Wasm engine — V8 in Chrome and Node, JavaScriptCore in Safari, SpiderMonkey in Firefox — and each engine is a tiered JIT: V8 uses `Liftoff` (a single-pass baseline compiler that produces machine code in one pass over the Wasm) as the baseline, then hands hot functions to `TurboFan` for full optimization ([V8 Liftoff](https://v8.dev/blog/liftoff); [V8 Wasm pipeline](https://v8.dev/docs/wasm-compilation-pipeline)). Server-side, Wasmtime and Wasmer (both Cranelift-based), WasmEdge (LLVM-based), and WAMR (interpreter + optional JIT/AOT) are the leading standalone runtimes.

For a new language, targeting Wasm gets you:

- **Portability**: one binary runs on x86, ARM, RISC-V, and in browsers.
- **A sandbox**: capability-based isolation via the *WebAssembly System Interface* (WASI) means the platform provides fine-grained access to files, sockets, and clocks.
- **A formal specification**: Wasm is one of the few widely-deployed platforms with a machine-checked semantics ([WebAssembly specifications](https://webassembly.org/specs/)).
- **A JIT for free**: skip the JIT-engineering entirely.

Trade-offs: Wasm's memory model is currently linear-address-only (no native GC in Wasm 1.0; a *GC proposal* is now shipping in browsers), which makes garbage-collected languages awkward without the GC extension. And crossing the JS↔Wasm boundary has real overhead, penalizing highly interoperable code. But for a numerical DSL, a plugin runtime, or a smart-contract language, Wasm is often the best available target.

## Section 6: Concurrency Implementation

Concurrency implementation choices are inseparable from language design: async/await syntax implies a state-machine transformation in the compiler; message-passing implies runtime scheduling; STM implies compiler-inserted logging. This section is organized bottom-up: threads, then scheduling, then higher abstractions.

### 6.1 Threads: kernel, green, fiber

**Kernel threads** are the OS's unit of scheduling. Each thread has its own stack (typically 1–8 MB reserved virtual address space), context switches cost ~1–2 µs, and creation costs ~10–100 µs. Kernel threads scale to thousands, not millions.

**Green threads** are user-mode threads scheduled by the language runtime, not the kernel. Java originally shipped green threads (before switching to 1:1 kernel threads in JDK 1.3); Rust experimented with them before removing the runtime in 1.0; Java's Project Loom brought them back as *virtual threads* in JDK 21.

**Fibers** are user-mode threads with explicit yield points, no preemption. Boost.Fiber, Windows fibers, and many C++ coroutine libraries fall here.

The tradeoffs: kernel threads are semantically simplest (any I/O just blocks; the OS handles scheduling), but expensive; user threads are cheap (Go and Erlang both routinely run 1M+ concurrent tasks) but require the runtime to intercept blocking I/O and preempt long-running tasks.

### 6.2 M:N scheduling

M:N scheduling multiplexes M user-mode tasks over N kernel threads. Go's **GMP scheduler** is the current canonical example: *G*oroutines are user-mode tasks, *M*achines are OS threads, *P*rocessors are logical execution contexts (defaulting to `GOMAXPROCS`, typically the number of CPUs) ([golang.design internals, *Model*](https://golang.design/under-the-hood/en/part3concurrency/ch09sched/model/)). Each P has a local run queue; when a P's queue is empty, it *steals* work from another P.

Erlang's BEAM scheduler is another M:N design (§5.9). Older Java green-thread implementations were user-mode-only (M:1). The tradeoffs are well-understood: local run queues eliminate contention; work-stealing balances load; but preemption of tight computational loops requires compiler cooperation — Go inserted safepoints at function preludes and, since 1.14, uses signal-based *asynchronous* preemption.

### 6.3 Stackful vs. stackless coroutines

**Stackful coroutines** allocate a per-coroutine stack (like a thread's, but smaller and grown on demand). Yielding is a stack switch (a handful of instructions). Go's goroutines, Erlang's processes, most fiber libraries.

**Stackless coroutines** transform each `async` function into a state machine — the local variables live in a heap-allocated state struct, and `.await` marks a state transition. No per-coroutine stack; each pending coroutine is at most as large as its captured variables. C#'s `async/await`, Rust's `async fn`, JavaScript's `async/await`, C++20 coroutines, Kotlin's suspend functions, Python's `async def`.

The tradeoffs:

- Stackful: uniform code (any function can suspend), but each coroutine costs ≥ a few KB of stack.
- Stackless: minimal memory per pending task, but *function coloring* (only `async` functions can `.await` other `async` functions), and the state-machine transform can produce large Types with duplicated code.

### 6.4 Async/await implementation

Rust's async/await lowers each `async fn` into an anonymous type implementing `Future`; the state machine is a `poll` method that resumes at the last suspension point ([Phil Opperman, *Async/Await*](https://os.phil-opp.com/async-await/); [EventHelix, *Rust to assembly: async/await*](https://www.eventhelix.com/rust/rust-to-assembly-async-await/)). Executors (Tokio, async-std, smol, embedded-async) run these futures by repeatedly polling them until they return `Ready`.

C#'s `async/await` compiles to a state machine built by `AsyncTaskMethodBuilder`. Each `await` on an incomplete task registers a continuation with the awaited task and returns control to the executor.

The interoperation problem — mixing sync and async code, blocking calls inside async contexts, cancellation semantics — is the source of most async pain in every language. Rust's zero-cost `Future` design has particularly harsh consequences (function coloring, `Send + Sync` requirements on shared state, complex trait bounds), but delivers extraordinary performance: a Tokio task is typically < 100 bytes and can be spawned in nanoseconds.

### 6.5 Work-stealing schedulers

The **work-stealing** scheduler was popularized by Cilk (MIT, Blumofe, Leiserson et al., 1995). The seminal paper is *The Implementation of the Cilk-5 Multithreaded Language* (PLDI 1998), which introduces the *THE (Top-Head-Exception) protocol* for lock-free work-stealing dequeues ([Cilk PLDI 98](https://people.csail.mit.edu/matei/courses/2015/6.S897/readings/cilk.pdf)). The claim to fame: "Cilk-5's performance depends on the efficiency of its work-stealing scheduler... The Cilk-5 runtime system organizes the multi-threaded execution using a work-stealing scheduler and executes serialized C code without any overhead beyond a simple function call" ([Cilk PLDI 98](https://people.csail.mit.edu/matei/courses/2015/6.S897/readings/cilk.pdf)).

Descendants are everywhere: Intel TBB, Java's `ForkJoinPool`, .NET's TPL, Go's scheduler, Rust's Rayon and Tokio, OCaml 5's runtime. Each worker has a local deque; workers push and pop from the local end; when a worker is idle, it steals from the *remote end* of another worker's deque. The design minimizes contention (local operations are lock-free), balances load (idle workers steal), and preserves cache locality (work runs close to where it was created).

**Tokio's scheduler** is a mature implementation for async I/O. The 2019 rewrite ([Tokio blog, *Making the Tokio scheduler 10x faster*](https://tokio.rs/blog/2019-10-scheduler)) removed a global lock, added per-worker local queues, changed the sleep-and-notify strategy, and introduced batched operations. The blog post reports 10× throughput improvements on the standard benchmarks and remains one of the best writeups of a production async scheduler.

**Rayon** brings work-stealing to CPU-bound Rust code with a `par_iter()` combinator API. Same THE-protocol lineage, different domain.

### 6.6 Actor implementations

Actors (Hewitt 1973; Agha 1986) are stateful, autonomous entities that communicate by asynchronous message passing. Erlang and Elixir are the canonical languages; Akka (JVM), Orleans (.NET), CAF (C++), Pony (a research language with reference capabilities for statically ensuring race-freedom in actor communication) implement the pattern in various flavors.

Design choices in an actor runtime:

- **Mailbox**: unbounded, bounded, prioritized?
- **Scheduler**: shared thread pool (Akka) or per-actor OS thread (rare)?
- **Message delivery**: at-most-once (Erlang) or at-least-once (many Java frameworks)?
- **Location transparency**: can messages cross process/machine boundaries transparently (Erlang, Akka Cluster)?

### 6.7 Software Transactional Memory

STM (Shavit and Touitou 1995; Herlihy and Moss 1993) offers concurrency control by *optimistic transactions*: run speculatively, log reads/writes, at commit-time verify no conflicts and commit atomically. Haskell's STM (Peyton Jones, Harris et al., PPoPP 2005) is the most successful practical implementation ([Harris, Marlow, Peyton Jones, Herlihy, *Composable Memory Transactions*](https://simonmar.github.io/bib/papers/stm.pdf)).

The Haskell STM paper's main contribution was *composability*: `atomically (do a; b)` composes two transactions into one, with automatic retry (`retry`) and choice (`orElse`) combinators. Purity plus the type system's tracking of the `STM` monad guarantee no I/O leaks into a transaction — the fundamental correctness constraint most other STM designs relax and pay for.

Clojure's STM shipped with the language in 2008. It uses *snapshot isolation* rather than serializable transactions, and coordinates with Clojure's immutable data structures to make transaction retries cheap.

STM's adoption has been narrower than early enthusiasm predicted. Cache-line contention on transaction metadata, the cost of tracking read/write sets, and the difficulty of integrating STM with I/O have kept it a niche technique — except in Haskell, where the type system's I/O tracking removes the largest obstacle.

### 6.8 Lock-free data structures

Lock-free (and wait-free) algorithms use atomic primitives (CAS, LL/SC) to make progress without locks. The canonical modern reference is Michael and Scott's queue (PODC 1996), Herlihy's *The Art of Multiprocessor Programming* (textbook, 2008), and the extensive folkloric knowledge captured in libraries like `crossbeam` in Rust and `java.util.concurrent`. Lock-free structures are essential inside GCs, schedulers, and hot-path libraries; every language runtime designer must be conversant with at least Michael-Scott queues, Treiber stacks, and hazard pointers or epoch-based reclamation.

### 6.9 Memory models

A memory model specifies the observable behavior of concurrent memory accesses. Three canonical models:

- **Sequential consistency** (Lamport 1979): all threads see all operations in a single global order consistent with each thread's program order. The strongest model; hard to implement without expensive fences on modern hardware.
- **Total store order (TSO)**: x86's model; each core's stores are buffered but writes become globally visible in program order.
- **Weakly-ordered / relaxed**: ARM, POWER, RISC-V; loads and stores may be reordered aggressively unless explicit barriers are inserted.

The **C++11 memory model** is the highest-impact language-level memory model of the past twenty years. Its `memory_order_relaxed` / `acquire` / `release` / `acq_rel` / `seq_cst` vocabulary has propagated into C, Rust, Swift, and (partly) into the Java memory model's more informal specification. Java's memory model (JSR-133, 2004) preceded C++11 but is less finely graded; the JMM guarantees a *happens-before* relation defined via synchronization actions on volatile fields, monitors, and thread starts/joins.

For a new language, the design choice cascades: promise SC and pay the fence cost, or expose relaxed operations and inherit C++11's complexity. Rust took the C++11 path essentially unchanged (with atomic types matching the C++11 memory-order enum); Java took a bespoke path decoupled from the underlying hardware.

---



### 6.11 Async/await state machines in depth

Rust's `async fn` compiles to a state machine implementing the `Future` trait. Consider:

```
async fn read_two(a: &Socket, b: &Socket) -> (Vec<u8>, Vec<u8>) {
    let x = a.read().await;
    let y = b.read().await;
    (x, y)
}
```

The compiler generates a struct roughly like:

```
enum ReadTwoState<'a> {
    Start { a: &'a Socket, b: &'a Socket },
    WaitingA { b: &'a Socket, fut: SocketRead<'a> },
    WaitingB { x: Vec<u8>, fut: SocketRead<'a> },
    Done,
}
impl<'a> Future for ReadTwoState<'a> { fn poll(...) { ... } }
```

Each `.await` becomes a state transition and a suspension point. Because state is stored in the enum, the future is *stackless* — its total size is the size of its largest state, not the sum of all its stack frames. This is what lets Rust futures live in `Vec<Pin<Box<dyn Future>>>` at heap sizes measured in bytes rather than kilobytes per task.

The state machine's inability to hold pointers to its own interior (because those pointers would be invalidated if the future were moved) motivated `Pin` — a wrapper that prohibits moves. Rust futures are `!Unpin` if they contain self-references; the runtime pins them before polling. This is one of Rust's more subtle language features and directly serves the async-state-machine implementation.

C#'s `async` uses a similar state-machine transformation (`AsyncTaskMethodBuilder` is the compiler's target), but because C# has a tracing GC, the state machine can hold pointers to itself freely. Python's `asyncio` uses generator-based coroutines (`yield from`) plus a scheduler; JavaScript's `async` compiles to Promise chains internally.

### 6.12 Work-stealing schedulers in depth

The work-stealing scheduler — introduced by Blumofe and Leiserson at MIT and productized in Cilk — is now the dominant parallel-task-scheduling algorithm ([Cilk-5 paper](https://people.csail.mit.edu/matei/courses/2015/6.S897/readings/cilk.pdf)). The idea:

1. Each worker thread has a *deque* (double-ended queue) of tasks.
2. When a worker spawns a child task, it pushes the *child* onto its own deque and continues executing the *parent*.
3. When a worker's deque is empty, it becomes a *thief*: it picks a random other worker and steals a task from the *opposite end* of that worker's deque.

Two properties make this both efficient and provably good:

- **Local pushes/pops are lock-free**: the owning worker pushes and pops from the *bottom* using no synchronization; only the *top* is contested by thieves. The THE protocol from the Cilk-5 paper makes this work with two words of state and one memory barrier per steal ([Cilk-5 paper](https://people.csail.mit.edu/matei/courses/2015/6.S897/readings/cilk.pdf)).
- **Theoretical bound**: the scheduler achieves time T_1/P + O(T_∞), where T_1 is single-threaded work and T_∞ is the critical-path length. That is: near-optimal parallel speedup with a small serial overhead.

Modern work-stealing schedulers appear in Cilk Plus, Intel TBB, Rayon (Rust), Java's ForkJoinPool, .NET's Task Parallel Library, and — with an M:N twist — Go's runtime and Tokio's multi-threaded scheduler. Tokio's 2019 scheduler rewrite adopted a per-worker LIFO slot on top of a work-stealing queue to shorten common message-passing paths ([Tokio 2019 scheduler](https://tokio.rs/blog/2019-10-scheduler)).

### 6.13 STM in depth

Composable Memory Transactions (Harris, Marlow, Peyton Jones, Herlihy 2005) introduced software transactional memory as a *first-class* language primitive in Haskell ([Composable Memory Transactions](https://simonmar.github.io/bib/papers/stm.pdf)). The abstraction is arresting: any block of reads and writes to `TVar`s can be enclosed in `atomically { ... }`; the STM runtime records the reads and writes in a per-thread log; on commit it validates that no observed value has changed since it was read; if any has, the transaction *restarts*. The `retry` primitive blocks until any read `TVar` changes.

The winning property is *composability*: `atomically (transferFunds a b)` and `atomically (transferFunds c d)` compose to `atomically (transferFunds a b >> transferFunds c d)` — a single transaction — with no lock-ordering effort. Fine-grained locking cannot do this.

The catch: STM's runtime cost is nontrivial (log allocation, log validation, occasional restarts) and it doesn't compose with side effects (STM in Haskell is enforced via the type system to reject `IO` inside `atomically`). Clojure's STM implementation follows the same design; Scala's ScalaSTM library brought a similar approach to the JVM.

The current industry position: STM is not the default concurrency primitive in any mainstream language, but it's the right tool for specific workloads (in-memory-only, well-bounded transaction size, high contention on shared state). Rust's `crossbeam` epoch-based reclamation and lock-free data structure library is a related, lower-level toolkit for the same class of problems.

## Section 7: Package Managers and Dependency Systems

A package manager is one of the two or three highest-leverage pieces of a language ecosystem (alongside the compiler and the primary editor tooling). Get it wrong and every user of your language suffers on every project, forever. Get it right and you inherit an ecosystem.

### 7.1 Resolution algorithms

The core problem is *dependency resolution*: given a root project's constraints and each package's own constraints on its dependencies, find a set of concrete versions that satisfies everyone — or report a useful reason why no such set exists.

**SAT-based resolution** encodes the problem as boolean satisfiability. `npm`'s original resolver, `pip` before 20.3, `apt`'s dpkg resolver, and Cargo initially all used SAT-adjacent backtracking search. The problem is genuinely NP-complete, but real-world instances are usually easy; when they aren't, the failure mode is a solver timeout or an incomprehensible error.

**PubGrub** (Natalie Weizenbaum for Dart's `pub` in 2017) is a different approach based on *conflict-driven clause learning*. When PubGrub finds a conflict, it "learns" a new constraint (an *incompatibility*) that summarizes the conflict, then uses it to prune further search. The learned incompatibilities also serve as the basis for excellent error messages that trace the exact chain of constraints leading to failure ([PubGrub Rust implementation](https://github.com/pubgrub-rs/pubgrub)). The Rust `pubgrub` crate is now used by `uv` (Astral's Python installer), by `poetry`, by Dart's `pub` and (increasingly) by Cargo — the Cargo team has been staging a PubGrub migration under a project goal for 2025H1 ([Cargo PubGrub project goal](https://rust-lang.github.io/rust-project-goals/2025h1/pubgrub-in-cargo.html)). The PubGrub project page describes the algorithm as "a high performance version resolution algorithm with good error messages, it finds a set of packages and versions that satisfy all the constraints of a set of packages and their transitive dependencies" ([pubgrub-rs README](https://github.com/pubgrub-rs/pubgrub)).

**Minimum Version Selection** (MVS) is Go modules' distinctive strategy, designed by Russ Cox. In Russ Cox's own description: "For each module, the build lists the *oldest* version that satisfies all of the module's requirements. This choice makes builds highly reproducible without a lock file, and it drastically simplifies the algorithm — MVS is not a SAT problem, just a shortest-path computation over the requirement graph" ([Russ Cox, *Minimal Version Selection*](https://research.swtch.com/vgo-mvs)). Cox's blog series (*Go & Versioning*) is required reading; it argues that the industry accepted a false dichotomy between "pick the newest" and "let the user pin exactly" and that "pick the oldest satisfying" is a better default because it minimizes surprise: your build is exactly the versions you asked for or a specific `require` line's minimum, nothing else ([research.swtch.com/vgo-mvs](https://research.swtch.com/vgo-mvs)). The Go modules reference documents the semantics in normative form ([Go modules reference](https://go.dev/ref/mod)).

### 7.2 Content-addressed storage

**Nix** (Eelco Dolstra, 2003 thesis; NixOS since 2003) stores every package under a hash-of-inputs derived path in `/nix/store`. Two packages built from the same inputs (source, dependencies, build script, compiler) produce the same output path; different inputs produce different paths; nothing is ever mutated after being written ([Nix store content-address docs](https://nix.dev/manual/nix/2.26/store/store-object/content-address)).

The properties this buys are extraordinary:

- **Perfect atomic upgrades and rollbacks**: switching an environment is a symlink flip.
- **Parallel installations of different versions**: no shared mutable global state.
- **Reproducibility**: two independent Nix rebuilds produce byte-identical outputs (mostly; there are still non-reproducible edge cases the Reproducible Builds project tracks).

**Unison** takes content-addressing further: *every function in a Unison program is identified by the hash of its normalized AST*. There are no filenames, no imports; you refer to a function by its hash (usually via a short name in a codebase index). This eliminates dependency version conflicts entirely — a rename is not an incompatible change, because the hash is unchanged.

### 7.3 Lockfiles

A lockfile pins the exact versions used in a build. Nearly every modern package manager ships one: `Cargo.lock`, `package-lock.json`, `yarn.lock`, `Pipfile.lock`, `Gemfile.lock`, `poetry.lock`, `uv.lock`, `go.sum`. The philosophy:

- Libraries do *not* commit lockfiles (they must remain compatible with a range of dependency versions).
- Applications *do* commit lockfiles (reproducible builds require identical inputs).

Go's `go.sum` is a per-module cryptographic checksum file, distinct from a version-pinning lockfile — MVS eliminates the need for the latter. The reproducibility property is delivered by `go.sum` verifying that the content of each downloaded module matches what was originally recorded.

### 7.4 Registry design

Package registries have converged on a common shape: a central catalog with per-package metadata (name, version, license, dependencies, author, description), a content store for the actual archives, an authentication layer for publishers, and a query API for clients. Notable variations:

- **npm** (JavaScript): CommonJS/ESM package format, scoped names (`@org/pkg`) added later ([npm scopes docs](https://docs.npmjs.com/about-scopes/)), the largest registry by count.
- **crates.io** (Rust): opinionated, no yanking recovery, strict semver, PubGrub in flight.
- **PyPI** (Python): wheel binary format + sdist source format; historically weak on isolation, improved with PEP 517/518 (build isolation) and PEP 621 (project metadata).
- **Maven Central** (Java, Kotlin, Scala): GPG-signed artifacts, groupId/artifactId/version coordinates, immutable once published.
- **Hex** (Erlang/Elixir): dependency solver written in Elixir, GPG signing, tightly integrated with Mix/Rebar.

### 7.5 Security features

Supply-chain security has become an existential concern for package ecosystems after high-profile compromises (event-stream 2018, colors/faker 2022, xz-utils 2024, ua-parser-js 2021).

**SLSA** ("Supply-chain Levels for Software Artifacts", pronounced "salsa") is a framework of security levels for build systems and artifacts. The v1.0 specification defines four *build track* levels: L1 (documented build process), L2 (hosted build with authenticated provenance), L3 (hardened build with tamper-resistant provenance), L4 (in flight) ([SLSA v1.0 levels](https://slsa.dev/spec/v1.0/levels)). SLSA is agnostic about the signing technology.

**Sigstore** is the corresponding signing infrastructure: a free, keyless code-signing service using short-lived certificates issued by OIDC identity providers (GitHub, Google, Microsoft accounts). *Cosign*, the client tool, can "sign container images" and other artifacts, storing signatures in transparency logs so they cannot be quietly rewritten ([Sigstore Cosign docs](https://docs.sigstore.dev/cosign/signing/signing_with_containers/)).

**Provenance attestations** (in-toto's model, adopted by SLSA) record who built an artifact, what source it was built from, and what dependencies went into it. A verifying downloader can then check the attestation against the actual artifact and reject mismatches.

**Checksum enforcement** (Go's `go.sum`, Cargo's checksum in `Cargo.lock`, `npm`'s `integrity`) is the minimum viable defense: even without signatures, if the checksum in your lockfile matches what you downloaded, no one has swapped the archive out from under you.

**Vendoring** — checking dependencies into the project repo — is common in Go (`go mod vendor`), was common in Rust (`cargo vendor`), and is Google's default for Bazel projects. It shifts trust from network availability of the registry to trust in the version-control system.

**Minimum-release-age** policies (recently added to `uv`, `pip`, and Cargo proposals) reject any dependency version published in the last N days. The rationale: most supply-chain attacks are caught within days; waiting a week eliminates the vast majority.

### 7.6 Attack classes and defenses

The SLSA blog on *dependency confusion and typosquatting* categorizes the modern threat landscape ([SLSA blog, *Dep confusion and typosquatting*](https://slsa.dev/blog/2024/08/dep-confusion-and-typosquatting)):

- **Typosquatting**: an attacker publishes `reqeusts` (misspelled) hoping to catch users who typo the popular `requests` package. Defenses: registry-level name-similarity checks; user-side scanning tools; typo-detection in the CLI itself.
- **Dependency confusion**: internal package names published to a public registry are automatically pulled by misconfigured private-first resolvers. Defenses: namespace reservations, registry priority ordering, explicit scope for internal packages.
- **Slopsquatting**: LLM-generated code hallucinates package names; attackers pre-register those names. A new class of attack; defenses are the same as typosquatting plus explicit LLM-code review.
- **Compromised maintainer accounts**: MFA on registry accounts, mandatory 2FA for large-download packages (npm, PyPI now enforce), and short-lived credentials via Sigstore-style OIDC.

### 7.7 Monorepo build systems

Bazel (Google), Buck2 (Meta), Pants (Twitter/Toolchain), Nx (Nrwl), and Turbo (Vercel) are monorepo-first build tools. Common properties:

- **Hermetic builds**: inputs are declared, sandboxed, and cache-keyed.
- **Remote caching**: outputs are stored in a distributed cache keyed by input hashes.
- **Remote execution**: builds run on a distributed farm, not the developer's laptop.
- **Fine-grained targets**: individual libraries, tests, and binaries are separately buildable and cacheable.

The distinction between "language package manager" (Cargo, npm, Go modules) and "monorepo build system" (Bazel, Buck2) is real: language package managers are optimized for pulling third-party dependencies over the network; monorepo build systems are optimized for building thousands of internal targets fast. Many organizations run both — Rust code inside a Bazel monorepo, with `cargo` used only to build dependency crates.

### 7.8 Semver and its critics

Semantic versioning (`MAJOR.MINOR.PATCH`) is the near-universal convention: major bumps for breaking changes, minor for additions, patch for bug fixes ([semver.org spec](https://en.wikipedia.org/wiki/Semantic_versioning)). Every modern package manager assumes semver in its resolution semantics.

Critics point out that semver is a *promise about intent* that is easily broken in practice: "no change is truly non-breaking" (a bugfix may be depended upon *because* it's a bug), and hyrum's-law observation applies aggressively ("with a sufficient number of users, all observable behaviors of your system will be depended on by somebody"). The classic critique — "Semantic Versioning Is a Terrible Mistake" — argues that mechanical version numbering hides real information behind an insufficient contract and that better tooling (change logs, migration guides, canary rollouts) would serve users better than a false-precision number ([Reprog, *Semantic Versioning Is a Terrible Mistake*](https://reprog.wordpress.com/2023/12/27/semantic-versioning-is-a-terrible-mistake/)).

Practical mitigations: Rust's `cargo semver-checks` (mechanical detection of semver violations), Elm's fully-enforced semver (the compiler refuses to publish a minor bump if it detected any breaking API changes), and detailed changelogs as the actual source of truth.

### 7.9 Namespacing

Every language must decide how to name things across packages. The two dominant strategies:

- **Global flat namespace**: crates.io, PyPI (partially), npm's unscoped packages. First-come-first-served ownership; risk of squatting; no way to have two `foo` packages.
- **Hierarchical namespace**: Java packages (`com.example.foo`), npm scopes (`@org/foo`), Rust modules (within a crate). Ownership implicit in the hierarchy; typically enforced at the DNS or registry-account level.

Go modules take a distinctive approach: **module paths are URLs** (`github.com/user/repo`), making the source repository directly the identifier. Compromises between control (`go get` fetches directly from the URL) and centralization (Go's default proxy `proxy.golang.org` caches everything anyway).

---

## Section 8: Tooling Ecosystem

An honest observation: modern developers judge a language's ecosystem in the first hour, and most of what they judge is tooling. Compiler quality is a distant second to a working autoformatter, jump-to-definition, and one-command `run tests`.

### 8.1 Language Server Protocol

The **Language Server Protocol** (LSP), introduced by Microsoft in 2016 for Visual Studio Code, is arguably the single most important tooling development of the last decade. LSP standardizes the messages between editors and language-analysis backends: hover, jump to definition, find references, code actions, diagnostics, completions, semantic tokens, and more, all over JSON-RPC ([LSP home](https://microsoft.github.io/language-server-protocol/); [LSP Wikipedia](https://en.wikipedia.org/wiki/Language_Server_Protocol)).

Before LSP, every language needed a per-editor plugin — N languages × M editors. LSP made it N + M: implement a server once, get support in every LSP-capable editor. The protocol was co-developed by Microsoft, Red Hat, and Codenvy ([LSP Wikipedia](https://en.wikipedia.org/wiki/Language_Server_Protocol)); the specification is maintained in the open at `microsoft/language-server-protocol`. Adoption is now near-universal: VS Code, Neovim, Emacs (`lsp-mode` and `eglot`), Sublime, Vim (with plugins), Zed, Helix, IntelliJ (via a bridge), and Xcode (Swift-only).

For a new language, publishing an LSP server is now second only to publishing the compiler itself in importance for adoption. `rust-analyzer` (Rust), `gopls` (Go), `pyright` (Python), `roslyn` (C#), `HLS` (Haskell), and `tsc`/`typescript-language-server` are exemplary implementations to study.

### 8.2 Formatters and formatter culture

**gofmt** (2009, Rob Pike and colleagues) established a new cultural expectation: **there is one formatting, and it is enforced**. gofmt's design gets rid of every stylistic degree of freedom the language allows to be automatic; the community expectation is that all Go code is `gofmt`-clean, and CI systems reject non-conforming code. The tradeoffs were debated ("some styles are objectively better") but the productivity win — no style bikeshedding, ever, in any Go codebase — was decisive.

Every subsequent language ecosystem has aspired to this: **rustfmt** (Rust), **Prettier** (JavaScript/TypeScript/CSS/JSON/etc.), **Black** (Python, with the tagline "the uncompromising formatter"), **ktfmt** (Kotlin, Google's take), **swift-format** (Swift), **dprint** (multi-language). The debate about whether rustfmt should be less/more configurable is ongoing in the Rust community — a proxy for the broader question of how much stylistic diversity a language ecosystem should tolerate ([Rust users forum, *gofmt vs rustfmt*](https://users.rust-lang.org/t/what-do-you-think-about-gofmt-vs-rustfmt/51605)).

### 8.3 Linters and static analyzers

Linters occupy the space between "the compiler accepts it" and "the code is good."

- **clang-tidy** (C++): the closest to a canonical linter for C++, with ~500 checks, integration into every LSP-based editor and every CI system.
- **ESLint** (JavaScript): plugin ecosystem is the main asset; every framework ships its own rule set.
- **Clippy** (Rust): shipped with rustc, ~700 checks, actively maintained by the Rust team. Clippy is unusual in that its recommendations are typically actionable and its false-positive rate is low.
- **Semgrep** (multi-language): pattern-based static analysis, rules written as code snippets with metavariables. Positioned between traditional linters and full static-analysis tools like Coverity.

### 8.4 Documentation generators

**rustdoc** is the current gold standard. Built into rustc, it extracts doc comments (Markdown), runs example code as tests (`#[test]`), produces cross-linked HTML with type-aware links, and is deployed automatically for every crate on `docs.rs` ([rustdoc docs](https://deepwiki.com/rust-lang/rust/5.2-documentation-generation-(rustdoc))). The combination — first-class doc comments in the language, mandatory testable examples, and a universal hosted deployment — is the strongest single-package documentation experience in any language.

**godoc** (`pkg.go.dev` since 2019) mirrors the pattern for Go: extract comments, cross-link, host. **Sphinx** (Python) is the classic reStructuredText-based generator, extremely powerful (LaTeX/PDF output, cross-project references) but heavier. **Javadoc** (Java, C#'s XML docs) is the classic Enterprise-grade tool.

### 8.5 Testing and property-based testing

QuickCheck (Koen Claessen and John Hughes, ICFP 2000) introduced *property-based testing* to a mainstream language ([Claessen and Hughes original paper series and later revisions](https://link.springer.com/chapter/10.1007/978-3-642-17685-2_6)). Instead of writing individual test cases, a QuickCheck user writes *properties* — statements like "reverse(reverse(xs)) == xs" — and QuickCheck generates random inputs that try to falsify the property, then *shrinks* any counter-example to a minimal failing case.

The lineage has since spread: Hypothesis (Python) is arguably the best in-class implementation, with sophisticated shrinking; Erlang's QuickCheck (commercial, Quviq) and PropEr (open source) sit at the heart of the Erlang testing culture; Rust's `proptest` and `quickcheck`; Scala's ScalaCheck; Java's jqwik. Every serious modern language now ships some form of property-based testing library, and many have integration test frameworks that support both example-based and property-based testing.

### 8.6 Fuzzing

Fuzzing has moved from "specialty tool for security researchers" to "part of every serious library's CI." The transformation was driven by **AFL** (Michał Zalewski, 2013+) — a coverage-guided greybox fuzzer that instruments the target for edge coverage and evolves inputs to explore new paths — and its successors **libFuzzer**, **HonggFuzz**, **AFL++**.

Language integration is now table stakes:

- **cargo-fuzz** (Rust, wrapping libFuzzer) — one command to fuzz a target, with sanitizer integration.
- **go fuzz** — Go's native fuzzing (stable in Go 1.18) integrates with `go test`.
- **Atheris** (Python), **Jazzer** (JVM), **JuliaFuzz** — coverage-guided fuzzers for their respective ecosystems.

OSS-Fuzz (Google) continuously fuzzes hundreds of open-source projects, filing bugs as they're found; the aggregate impact on software quality is substantial.

### 8.7 Debuggers and DAP

The **Debug Adapter Protocol** (DAP), introduced by Microsoft in 2018, does for debuggers what LSP does for language servers: standardize the protocol between editors and debug backends ([DAP home](https://microsoft.github.io/debug-adapter-protocol/); [DAP specification](https://microsoft.github.io/debug-adapter-protocol//specification.html)). DAP is now supported by VS Code, Neovim, Emacs, Sublime, and others; a DAP adapter for LLDB, GDB, or a language-specific debugger works everywhere.

At the C++/systems level, **LLDB** and **GDB** remain the two dominant debuggers; both now expose stable Python APIs and both work over DAP. Modern debugger UX includes: source-level stepping with correct optimized-code source maps (a hard problem), watchpoints, conditional breakpoints, reverse debugging (rr on Linux, Time Travel Debugging on Windows), and remote debugging.

### 8.8 Build systems

The evolution:

1. **make** (1976): declare targets and dependencies; run when files change. Still the substrate of many builds, but limited (no caching across machines, imprecise dependency tracking).
2. **Autotools, CMake, Meson**: cross-platform build meta-systems, mostly for C/C++.
3. **Language-integrated**: `cargo` (Rust), `go build`, `stack`/`cabal` (Haskell), `mix` (Elixir), `npm`/`yarn`/`pnpm` (JS), `dune` (OCaml). One command does dependency resolution, compilation, testing, and packaging.
4. **Monorepo scale**: Bazel, Buck2, Pants, Nx (§7.7).

The general trend is toward *integrated tools that do more*. Newly-designed languages that ship without a canonical build tool (or that ship with `make`) will struggle to attract users.

### 8.9 Cross-compilation

Cross-compilation is the ability to build for a target machine different from the host. Compilers that use LLVM inherit LLVM's target multiplicity almost for free — Rust's `rustup target add aarch64-apple-darwin` on an x86_64 Linux is trivially supported. Zig has made cross-compilation a headline feature: `zig build -Dtarget=aarch64-linux-musl` produces a working binary from any host.

The harder problems are always *the standard library* (does it exist for the target?), *system libraries* (do you have `libc`, `libSystem`, `WindowsSDK`?), and *dynamic linking versus static* (musl vs. glibc; static linking is much easier to cross-compile).

### 8.10 Reproducible builds

The Reproducible Builds project ([reproducible-builds.org](https://reproducible-builds.org/)) is a cross-project effort with a single goal: given source code, build instructions, and a known set of tools, produce **byte-for-byte identical** binaries anywhere, any time ([Reproducible builds Wikipedia](https://en.wikipedia.org/wiki/Reproducible_builds)). The value is huge: it lets independent parties verify that a distributed binary was actually built from the claimed source.

The project maintains tooling (`diffoscope`, `disorderfs`, `strip-nondeterminism`), best-practices documentation, and per-distribution status pages (Debian, Fedora, NixOS, Arch, F-Droid) that show what fraction of their packages currently reproduce.

Sources of non-reproducibility are surprisingly many: timestamps in metadata, filesystem ordering, `__DATE__`/`__TIME__` macros, PGO profile fingerprints, random-seed use in stripping and archive formats, non-determinism in the compiler itself (parallel compilation, ASLR-affected code layout).

For a new language, a small investment early (deterministic hash-map iteration, sorted filesystem walks, stripping of build timestamps) pays for itself many times over in the reproducibility of downstream binaries.

---



### 8.11 LSP in depth

The Language Server Protocol, released by Microsoft in 2016 alongside Visual Studio Code, is a JSON-RPC 2.0 protocol between an editor and a language-specific server ([LSP home](https://microsoft.github.io/language-server-protocol/); [LSP Wikipedia](https://en.wikipedia.org/wiki/Language_Server_Protocol)). The core insight: instead of every editor implementing every language's smarts and every language authoring plugins for every editor (the O(M×N) problem), an *n+m* architecture — one server per language, one client per editor — reduces the work dramatically.

The protocol defines request/response and notification types for:

- Document lifecycle (`textDocument/didOpen`, `didChange`, `didClose`).
- Navigation (`definition`, `references`, `implementation`, `typeDefinition`).
- Editing assistance (`completion`, `hover`, `signatureHelp`, `codeAction`).
- Semantic feedback (`publishDiagnostics`, `semanticTokens`).
- Refactoring (`rename`, `formatting`).
- Workspace features (`symbol`, `executeCommand`, workspace file operations).

Implementing an LSP well requires *incremental* analysis — the server must handle typing latency in the tens of milliseconds. `rust-analyzer`, `gopls`, `pyright`, `clangd`, and `HLS` (Haskell Language Server) are the reference implementations to study. Each has, in the process of building an LSP, discovered that their compiler's front end had to be substantially rearchitected to be incrementally re-runnable — one of the strongest arguments for planning incremental analysis into your compiler from day one.

### 8.12 DAP: the LSP for debuggers

The Debug Adapter Protocol was introduced by Microsoft in 2018 as a parallel effort for debuggers ([DAP home](https://microsoft.github.io/debug-adapter-protocol/)). Similar architecture: one adapter per debuggee runtime, one client per editor. The protocol defines requests for launching/attaching, setting breakpoints, evaluating expressions, stack traces, variables, and stepping.

Adopted by VS Code, Eclipse, Neovim (via `nvim-dap`), Emacs (`dap-mode`), and IntelliJ. The tooling win is that a language now only needs *one* debug adapter to be first-class in most editors.

### 8.13 Formatter culture

`gofmt` (Go, 2009) established the norm: one canonical style, no options, run automatically before commit. The design decision — no configuration knobs at all — foreclosed style bikeshedding at the language level. Rust followed with `rustfmt` and largely-conservative default settings; JavaScript, with Prettier; Python, with Black ("The Uncompromising Code Formatter"). The pattern is now expected: a new language without a formatter is judged incomplete.

The engineering is surprisingly nontrivial. A formatter must preserve program semantics exactly (no reordering that changes evaluation order, no comment loss); handle preprocessor directives, string interpolation, and doc comments; be fast enough to run on every save. Prettier's implementation, based on the Wadler pretty-printing algorithm, remains the state of the art for JavaScript-family syntax.

### 8.14 Property-based testing

QuickCheck (Claessen and Hughes, ICFP 2000) introduced property-based testing to a wide audience ([QuickCheck at 15](https://link.springer.com/chapter/10.1007/978-3-642-17685-2_6)). The user writes properties (`∀xs. reverse(reverse(xs)) == xs`); the framework generates random inputs; shrinkage finds a minimal counterexample when a property fails.

The lineage is now enormous: Haskell QuickCheck, Erlang's PropEr, Elixir's StreamData, Rust's `proptest`, Python's `hypothesis` (the state-of-the-art shrinker), Java's `jqwik`. Every serious language now ships a property-based tester in its testing ecosystem. For a language creator: adopt QuickCheck-style property testing from day one, and ideally build it into the standard test framework rather than as a third-party addon.

### 8.15 Fuzzing integration

Fuzzing — feeding random or structured-random inputs to a program to look for crashes — has moved from a specialist activity to a routine part of language toolchains. Rust ships `cargo-fuzz` (backed by `libFuzzer`) and `cargo-afl` (backed by American Fuzzy Lop). Go added native `go test -fuzz` in Go 1.18. Both integrate with coverage-guided input generation and continue-on-crash minimization.

The ecosystem win is that hosting a project on OSS-Fuzz (Google's public fuzzing service) is one config file away for supported languages; the service will fuzz your project continuously for years, filing issues when it finds crashes.

### 8.16 Cross-compilation

A modern language ships with cross-compilation support: `cargo build --target x86_64-pc-windows-gnu`, `zig build -Dtarget=aarch64-linux-musl`, `GOOS=windows GOARCH=arm64 go build`. Getting there requires:

- A target-descriptor system (LLVM triples, Zig's `Target`).
- Portable standard-library implementations (Zig's stdlib is famously portable; Rust's `std` requires libc but has `no_std` for bare-metal).
- Tooling for linking to target-appropriate libc (musl, glibc, MSVCRT).

Zig ships a bundled cross-compilation toolchain that can produce Windows PE, macOS Mach-O, and Linux ELF from any host — arguably the best cross-compile developer experience of any language. Go was the first mainstream language to make cross-compile trivial (Go 1.5, 2015); before then, cross-compiling C or C++ required a full sysroot setup that took hours.

## Section 9: Verification and Formal Methods Integration

Verification has left the ivory tower. In 2026, several production Rust codebases use SMT-based verification tools; the seL4 microkernel, the CompCert C compiler, and the Astrée/Verasco pipelines have been in production for over a decade. This section is a menu of what integrations are possible.

### 9.1 Type systems as lightweight verification

Every type system is a verifier for the properties expressible in its type language. The Curry-Howard correspondence — types are propositions, programs are proofs — makes this precise for pure functional languages. Rust's ownership system verifies "no data races" and "no use-after-free" in safe code; Haskell's `IO` type verifies "no I/O in pure code"; TypeScript's discriminated unions verify "handled all cases".

The point is that the type-system decision *is* a verification-system decision. Any expressive type system is doing verification; the question is how much and at what interactive cost.

### 9.2 SMT solvers

Satisfiability Modulo Theories (SMT) solvers accept formulas in first-order logic extended with theories (linear arithmetic, arrays, bit-vectors, uninterpreted functions, quantifiers) and decide satisfiability or provide a model. **Z3** (Microsoft Research, Nikolaj Bjørner and Leonardo de Moura, 2007–) is the dominant tool ([Z3 internals paper](https://z3prover.github.io/papers/z3internals.html)); **CVC5** (Iowa/Stanford, formerly CVC4) is the leading alternative. The Z3 internals paper documents the solver's architecture — a *Nelson-Oppen combination* of theory solvers coordinated by a SAT engine, with dedicated theories for linear real/integer arithmetic, bit-vectors, arrays, and (with less-complete decision procedures) quantifiers, nonlinear arithmetic, and floating point ([Z3 internals](https://z3prover.github.io/papers/z3internals.html)).

SMT solvers underpin most modern verification tools: refinement types (Liquid Haskell, F*, Dafny), Rust verifiers (Verus, Prusti, Kani), model checkers (nuXmv, ESBMC), and program analyzers (Facebook's Infer, Amazon's Automated Reasoning group). Understanding what SMT can decide and what it can't (undecidable in the general case for FOL + quantifiers + nonlinear arithmetic) is the essential skill for anyone building an SMT-based verifier.

### 9.3 Model checking

Model checkers exhaustively explore the reachable states of a specification (or a program abstracted as a specification) and verify safety or liveness properties.

**TLA+** (Leslie Lamport, 1993+) is a specification language based on temporal logic of actions ([TLA+ Wikipedia](https://en.wikipedia.org/wiki/TLA+)). TLA+ specifications describe *what a system may do* rather than *how it does it*; the TLC model checker explores all reachable states (up to a bound) and reports counter-examples for violated properties. TLA+ has been used at Amazon for AWS (documented in a well-known ACM article), at Microsoft for Azure, and by many distributed-systems teams for pre-implementation design verification. Lamport's *Specifying Systems* book is the definitive tutorial.

**Alloy** (Daniel Jackson, MIT, ~2000) is a lightweight formal-methods language for structural modeling — think "TLA+ for data structures rather than behaviors." Alloy's semantics is bounded relational logic; the Analyzer translates specifications to SAT and finds instances or counter-examples up to a bound. Alloy has been used for security-protocol design, filesystem semantics, and access-control policies.

**Spin** (Gerard Holzmann, Bell Labs 1980+) is the classic model checker for concurrent-system verification, using the PROMELA language. Used in real critical-systems work (Curiosity Mars rover, Cassini). Verified NASA JPL flight software.

### 9.4 Proof assistants

**Coq / Rocq** (INRIA, 1984+; renamed Rocq in 2024): the dependently-typed proof assistant with the largest ecosystem of verified software. CompCert (§9.7) is a Coq development; the Mathematical Components library (Feit-Thompson theorem formalization by Gonthier et al.), FCF (crypto library), and countless PL formalizations live in Coq. Coq supports *extraction* to OCaml, Haskell, or Scheme, letting you write and prove code in Coq and then run the extracted version ([Rocq extraction docs](https://rocq-prover.org/doc/V8.18.0/refman/addendum/extraction.html)).

**Lean 4** (Leonardo de Moura and community, 2021+): dependent type theory with a modern implementation. Lean 4 has a compiler to native code (via LLVM) — you can literally write executable programs in Lean, with proofs interleaved, and run them ([Lean 4 code generation](https://deepwiki.com/leanprover/lean4/6.3-code-generation)). This is a departure from Coq/Rocq's "prove then extract" model. The Lean mathlib community has formalized enormous parts of undergraduate and graduate mathematics.

**Agda** (Chalmers, 2007+): another dependently-typed proof assistant, with strong emphasis on interactive editing (holes filled in incrementally) and a purely functional executable language. Agda is compilable to Haskell or JavaScript, but is more commonly used as a proof-checker.

**Idris 2** (Edwin Brady, 2019+): the closest of the dependent-type family to a *programming language first, proof assistant second*. Quantitative Type Theory gives Idris 2 first-class linearity and erasure ([Idris 2 multiplicities](https://github.com/idris-lang/Idris2/blob/27780073c8631826d846499840b3857d9b9a4fd5/docs/source/tutorial/multiplicities.rst)); the compiler can compile Idris 2 programs to Chez Scheme, Racket, JavaScript, and (experimentally) C.

**F\*** (Microsoft Research + INRIA, 2011+): dependently-typed language explicitly designed for verification, with SMT-solver integration (Z3) for automating proof obligations that are within SMT's reach ([F* Wikipedia](https://en.wikipedia.org/wiki/F*_(programming_language))). F* is used for verified crypto (Project Everest — verified TLS 1.3 in HACL* and miTLS), verified low-level networking code, and Tezos smart contracts. F* extraction targets OCaml, F#, C (via KaRaMeL), and Wasm.

### 9.5 Verified Rust: Verus, Prusti, Kani, Creusot, Aeneas

The Rust verification ecosystem is one of the most active in industry-facing PL research.

**Verus** ([Verus guide](https://verus-lang.github.io/verus/guide/)) is an SMT-based verifier for Rust. It adds pre/postconditions, invariants, and pure functions ("spec functions") to Rust; verifies them by translating to SMT (currently Z3). Verus targets sequential and (increasingly) concurrent Rust and has been used to verify substantial systems (Verus itself, portions of the Vale storage system).

**Prusti** (ETH Zürich, Alexander Summers and Peter Müller's group) is a Rust verifier built on the Viper verification infrastructure ([Prusti at ETH](https://www.pm.inf.ethz.ch/research/prusti.html)). Prusti's distinctive design uses Rust's ownership guarantees to *simplify* verification — the borrow checker's aliasing discipline means Prusti doesn't need heavyweight separation logic for many properties. The tool is open-source and integrates with rustc.

**Kani** (Amazon Web Services) is a bounded model checker for Rust ([Kani repo](https://github.com/model-checking/kani)). Kani translates Rust MIR to CBMC (C Bounded Model Checker) format and lets developers write property checks that Kani verifies exhaustively up to a bound. Amazon has used Kani on the Firecracker VMM, S3 storage, and several kernel modules. Because it's bounded, Kani catches bugs but doesn't prove full absence — the tradeoff is much greater automation than Verus/Prusti.

**Creusot** (INRIA) verifies Rust using a WhyML backend (translating to SMT/proof-assistant proofs); **Aeneas** (INRIA, Son Ho and colleagues) translates Rust to a pure functional language for proof in Lean/Coq/F*.

### 9.6 Dafny

**Dafny** (Microsoft Research, Rustan Leino, 2008+) is a verification-aware programming language, not a verifier for an existing language ([Dafny home](https://dafny.org/)). Dafny's syntax is Java/C#-like; pre- and postconditions, invariants, and termination measures are first-class; a build compiles the program to C#, Go, Java, JavaScript, or Python after verification. Amazon's *Automated Reasoning* group has used Dafny extensively for AWS internal work, including verified components of the AWS Cryptographic Verification pipeline. Dafny's mature IDE integration (VS Code plugin, `verified? yes/no` in the gutter) is exemplary.

### 9.7 Certified compilers: CompCert

**CompCert** (Xavier Leroy, INRIA; started 2005, first production release 2008) is a *formally verified* optimizing C compiler ([CompCert Wikipedia](https://en.wikipedia.org/wiki/CompCert); [CompCert doc](https://compcert.org/doc/); [CompCert publications](https://compcert.org/publi.html)). Every intermediate representation of the compiler (Clight, C#minor, Cminor, RTL, LTL, PPC/ARM/x86 assembly) has a formal semantics in Coq; every optimization pass is proven to preserve the semantics; the whole chain gives an end-to-end theorem: **if CompCert compiles a program without error, the resulting assembly's observable behavior is one of the behaviors permitted by the C source's semantics.**

CompCert is used in avionics (Airbus DO-178B/C-certified components), space, and rail. It is slower than GCC/Clang and does not implement all C99/C11 features, but the correctness guarantee has real economic value in safety-critical settings ([CompCert publications](https://compcert.org/publi.html)).

CompCert has spawned an ecosystem: CakeML (verified ML implementation, from source semantics to x86/ARM assembly), CertiKOS (verified concurrent OS kernel), Verified Software Toolchain (VST, Andrew Appel's Coq-based Hoare-logic tool for C).

### 9.8 K Framework and machine-checked semantics

The **K Framework** (Grigore Roșu and collaborators, 2003+) is a semantics definition framework in which you write a language's operational semantics as rewrite rules; the framework then generates an interpreter, a symbolic execution engine, a program verifier, and a model checker automatically ([K Framework home](https://kframework.org/)). K has been used to give complete formal semantics to C (KCC/RV-Match), Java, JavaScript, EVM (the Ethereum Virtual Machine), and x86-64. The verified EVM semantics has been used by industry security firms to check smart contracts for correctness.

Related tools: **PLT Redex** (Felleisen et al., Racket-based), **Ott** (LaTeX-friendly semantics formalization, used in POPL papers), **Lem** (Sewell et al., Cambridge, used in the POWER/ARM memory-model formalizations).

### 9.9 Extraction pipelines

Getting from a verified proof/spec to running code is the *extraction* problem. Options:

- **Extraction** (Coq/Rocq, Isabelle/HOL): translate the proof-language program to a target functional language (OCaml, Haskell, Scheme). Efficient but constrained: extracted code has the shape of the source proof, and idiomatic extraction requires care ([Rocq extraction](https://rocq-prover.org/doc/V8.18.0/refman-prover.org/doc/V8.18.0/refman/addendum/extraction.html)).
- **Compilation** (Lean 4, Idris 2, Agda): the theorem-proving language is itself compiled to native code or a runtime. Lean 4 compiles to C and can run at competitive speeds; Idris 2 targets Scheme (Chez) by default; Agda has a GHC backend ([Lean 4 code generation](https://deepwiki.com/leanprover/lean4/6.3-code-generation)).
- **F* extraction**: F* extracts to OCaml or F# by default; the *Low\** subset extracts to C via the KaRaMeL tool. This is how the Project Everest team produces verified C for cryptography (HACL\*, EverCrypt) that ships in Firefox, Linux kernel, and Windows ([F\* wiki](https://en.wikipedia.org/wiki/F*_(programming_language))).

The pipeline design matters: the extraction/compilation step itself must be trusted (or verified). CompCert bootstraps this problem by having the *compiler* verified against a formal C semantics; Lean 4 does not verify its own compiler but has a small trusted kernel that re-checks proofs.

### 9.10 Model checkers as language tools

Beyond SMT-based type systems, general-purpose model checkers see programming use:

- **TLA+** (Leslie Lamport, 1999) — a specification language, not a programming language. TLC checks finite-state instances; TLAPS proves theorems. Amazon and Microsoft use TLA+ heavily for distributed systems specifications ([TLA+ Wikipedia](https://en.wikipedia.org/wiki/TLA%2B)).
- **Alloy** (Daniel Jackson, MIT) — a relational modeling language with a SAT-based analyzer, good for finding counterexamples in structural specifications ([Alloy Wikipedia](https://en.wikipedia.org/wiki/Alloy_(specification_language))).
- **Spin/Promela** — an older explicit-state model checker, historically dominant for protocol verification.
- **CBMC** — a C bounded model checker (behind Kani).
- **Java PathFinder** — an explicit-state model checker for Java bytecode.

For a new language, the pragmatic play is: type system does the easy 80 percent (nulls, mutation, aliasing), refinement types or contracts push into the next 15 percent (arithmetic bounds, protocol correctness), and a verifier framework (Verus-style) handles the last 5 percent for critical libraries.

---

## Section 10: Bootstrapping

### 10.1 Self-hosting: the milestone

A compiler is *self-hosted* when it can compile itself. This is a common language milestone: it validates the language is expressive enough to build production software, and it eliminates dependence on the bootstrap language. Every mature systems language has done it — but the *path* to self-hosting varies widely.

**Rust**: The first Rust compiler was written in **OCaml** by Graydon Hoare starting in 2006 ([Factory.ai Rust lore](https://factory.ai/open-source-wikis/rust?page=lore.md); [Language Lineage — Rust](https://www.languagelineage.org/languages/rust)). In 2010, the OCaml compiler was retired and replaced with a self-hosted compiler written in Rust; Mozilla announced sponsorship the same year. Since then, every rustc release is built by the previous release — this is the "stage 0 → stage 1 → stage 2" bootstrap now documented in `src/bootstrap` ([Rustc dev guide — Bootstrapping](https://rustc-dev-guide.rust-lang.org/building/bootstrapping/intro.html)).

The three-stage build:

- **Stage 0**: download a prebuilt "beta" rustc (or use a local rustc) — the *bootstrap compiler*.
- **Stage 1**: use stage 0 to compile the current rustc source. This binary uses stage 0's standard library.
- **Stage 2**: use stage 1 to compile rustc again. This is the *distributable* compiler; because it and its libstd were both built by the current source, it is self-consistent.

The three-stage discipline exists to handle the case where the current-source compiler adds new features that the compiler must itself use — stage 1 compiles current source *with* new features but *targets* old-format libstd; stage 2 is fully consistent.

**Go**: Go was originally written in C (the `gc` compiler in `cmd/{5,6,8}c`) and used a C-based runtime ([Dave Cheney — How Go uses Go](https://dave.cheney.net/2013/06/04/how-go-uses-go-to-build-itself)). In the Go 1.5 release (2015), the compiler and runtime were mechanically translated from C to Go using a custom tool (`grind`), a project led by Russ Cox and Rob Pike. Since Go 1.5, Go bootstraps itself: to build the current Go compiler you first build Go 1.4 (or later) from C sources, then use it to build the current Go — a chain that grows by one link per release. Go 1.20 tightened this: only Go 1.17.13 or later can bootstrap current versions, letting the C-era code be dropped.

**Zig** self-hosted in 2022, after starting as a C++ compiler; the current build uses `zig1.wasm`, a Wasm-encoded stage-0 compiler committed to the repo, so the bootstrap trust root is a small file plus any Wasm runtime.

**GHC** was famously bootstrapped from another Haskell — it has never had a non-Haskell implementation, using a chain of older GHCs (or `nhc98`/`hbc` historically) as bootstrap compilers.

### 10.2 Ken Thompson's "Reflections on Trusting Trust"

The bootstrap dependency chain is not just a curiosity — it has a serious security implication. Ken Thompson's 1984 Turing Award lecture ([Reflections on Trusting Trust — Thompson 1984](https://www.cs.cmu.edu/~rdriley/487/papers/Thompson_1984_ReflectionsonTrustingTrust.pdf)) describes an attack in three stages:

1. Write a compiler that inserts a backdoor into `login` (the Unix authentication program) when compiling it.
2. Enhance the compiler further: when the compiler compiles *itself*, insert code that re-inserts both of these behaviors.
3. Compile the modified compiler, capture its binary, and *remove the source-code changes*.

Now: the source code of the compiler looks entirely clean. Yet every future compiler built from that clean source contains the backdoor, because it was built by the compromised binary, which re-inserts the trojan into any compiler-source it processes.

Thompson concludes: *"You can't trust code that you did not totally create yourself. (Especially code from companies that employ people like me.)"* This creates an obligation for any long-lived compiler: someone, somewhere, needs to be able to independently rebuild the tool from source using tools that predate the compromise. In practice this justifies the *diverse double-compilation* technique (David A. Wheeler's PhD dissertation) and the *Bootstrappable Builds* project below.

### 10.3 Bootstrappable Builds project

The **Bootstrappable Builds** project ([bootstrappable.org](https://www.bootstrappable.org/projects/mes.html)) aims to reduce every widely used compiler binary's bootstrap trust root to a small auditable seed.

**GNU Mes** (Guile-based Maxwell Equations of Software) is the flagship: a small Scheme interpreter and a C compiler *written in that Scheme*, itself compiled from a hand-audited assembler binary of about **357 bytes** ([GNU Mes manual](https://www.gnu.org/software/mes/)). The `stage0` project by Jeremiah Orians provides that seed: a hand-encoded x86 hex program that assembles a slightly larger assembler, that assembles a slightly larger one, etc., up through M2-Planet (a C-subset compiler), MesCC (Mes's C compiler), then TinyCC, then GCC 4.x, then modern GCC.

**GNU Guix** now uses this chain: the full-source bootstrap of Guix — announced in 2023 — replaced its prior binary-seed dependency on GCC and glibc with a bootstrap that starts from **stage0 (357 bytes) → Mes → TinyCC → GCC → glibc → the rest of GNU** ([Guix full-source bootstrap](https://guix.gnu.org/en/blog/2023/the-full-source-bootstrap-building-from-source-all-the-way-down/)). The Guix team calls this "an important defense against low-level compiler backdoors": if you audit the 357-byte seed and can inspect every stage's source, no Trusting-Trust attack can survive without being present in that visible chain.

**mrustc** (John Hodge/thepowersgang) is an alternate Rust compiler written in C++ that compiles Rust ~1.19, ~1.29, ~1.39, ~1.54, ~1.74 releases — enough to break the "you need a Rust compiler to build a Rust compiler" chain ([mrustc GitHub](https://github.com/thepowersgang/mrustc)). Building rustc via mrustc from 1.19 forward, one release at a time, produces a stage-0 rustc without ever needing a preexisting rustc binary. mrustc has been the basis of Debian and Guix Rust packaging in the past.

**tcc** (Tiny C Compiler, Fabrice Bellard) plays a similar role for C: a small, fast, single-pass C compiler that can serve as a bootstrap step before jumping to GCC/Clang.

### 10.4 Nix and reproducible bootstrapping

**Nix**'s content-addressed store (discussed in Section 7) is a natural fit for reproducible bootstrapping: every derivation's hash includes the hash of every input, so a bootstrap chain is a Merkle-like tree of package builds. If two independent parties compute the same output hash from the same source, they've each independently verified the build.

Combined with Bootstrappable-Builds tooling, Nix and Guix can now express a bootstrap that anyone can audit, reproduce byte-for-byte, and start with a **~357-byte seed** — a fundamental improvement over the historical practice of downloading a multi-hundred-megabyte "stage-0 GCC" binary and trusting it.

### 10.5 Practical guidance for a new language

- **Start with a small existing language** for your first compiler (OCaml, Rust, Python are common). Once the language is expressive enough (has strings, hash maps, some kind of ADT), rewrite in itself.
- **Do the three-stage build early**: it forces you to notice non-determinism and version-skew bugs. Rust's stage 1 vs stage 2 discipline has caught many bugs that would have manifested only in release.
- **Publish stage-0 binaries in a form that can be rebuilt**: at minimum, snapshot the source at the version the stage-0 was built from. Better: publish a Wasm-encoded stage-0 (Zig's pattern), which is a much smaller trust root.
- **Talk to Guix/Nix packagers early** if you want your compiler to be part of a reproducible ecosystem. mrustc-style side-channel implementations are a real gift; encouraging them (and stabilizing versions of your language at which the side-channel targets) helps.

---



### 10.6 Diverse double-compilation

David A. Wheeler's PhD dissertation formalized a defense against the Thompson trojan: *diverse double-compilation*. If you have two independent compilers for the same language (say, GCC and Clang), you can:

1. Use compiler A to build compiler A's source, producing binary A'.
2. Use compiler B to build compiler A's source, producing binary A''.
3. Use A' to build A's source again, producing A_bin_1.
4. Use A'' to build A's source again, producing A_bin_2.
5. Compare A_bin_1 and A_bin_2. If bit-identical, no Thompson trojan can be present in *both* A and B — because the trojan would have to be present in whichever compiler was used at step 1 or 2, and would then propagate identically through both routes.

For this defense to work, the compiler must be *reproducible* — deterministic output byte-for-byte. This is one of the strong motivators for the Reproducible Builds project. A compiler that emits nondeterministic output (differing paths, embedded timestamps, non-deterministic hashmaps) forecloses this defense.

### 10.7 The trust chain visualized

A modern reproducible bootstrap for Guix reads:

```
stage0 hex (357 bytes, hand-audited)
    → M0 assembler
    → M1 macro assembler
    → M2-Planet (C-subset compiler)
    → MesCC (Mes's C compiler, ~5 MB)
    → TinyCC
    → GCC 4.7
    → GCC 4.9
    → GCC 10
    → glibc, binutils, coreutils
    → the rest of Guix
```

Every step's source is auditable; every output's hash is content-addressed. If you trust the 357 bytes of stage0 (small enough that a human can audit it in an afternoon), you can trust the entire chain up to modern glibc — a chain of ~30 build steps ([Guix full-source bootstrap](https://guix.gnu.org/en/blog/2023/the-full-source-bootstrap-building-from-source-all-the-way-down/); [Bootstrappable Mes](https://www.bootstrappable.org/projects/mes.html); [GNU Mes home](https://www.gnu.org/software/mes/)).

This is a substantial improvement over the historical situation: in 2015, "install GCC" meant "download a 200-MB binary from your distro and trust that binary and everyone who built it." A Trusting Trust attack that predated your download was undetectable. Under the Guix chain it is not undetectable — the chain is transparent all the way down.

### 10.8 Wasm as a bootstrap seed

An interesting emerging pattern: use a Wasm-encoded stage-0 compiler as the seed. Zig has done this for years; each `zig1.wasm` in the tree is a Wasm module containing a stage-0 Zig compiler compiled from the prior version. The trust surface is: any Wasm interpreter (there are many, including `wasm-interp` from WABT that is small and readable) plus the current source.

The Wasm-seed approach is attractive because Wasm has a formal semantics, tiny reference interpreters, and a portable execution model. If the language creator commits to producing a Wasm stage-0 on each release, the reproducible-bootstrap community can consume that seed directly rather than needing a separate C++/OCaml alternate compiler like mrustc.

## Section 11: Documentation and community engineering

A programming language is a social artifact as much as a technical one. The engineering of *how the community works* — proposals, documentation, playgrounds, governance — is a discipline in its own right.

### 11.1 The Rust documentation standard

The Rust team, starting around 2014 with the first edition of *The Rust Programming Language*, set a new benchmark for language documentation. Rust ships three distinct, cross-linked, versioned documents:

- **The Rust Programming Language** ("The Book") — a narrative tutorial for beginners.
- **The Rust Reference** — an in-depth, normative but not fully formal specification.
- **The Rustonomicon** — *"The Dark Arts of Advanced and Unsafe Rust Programming"* ([Rustonomicon](https://doc.rust-lang.org/nomicon/)). The Nomicon is a rare artifact: an official document that acknowledges the language has sharp corners (unsafe, FFI, aliasing invariants, custom allocators) and teaches how to handle them safely. Its opening declaration — *"This book is not for the faint of heart"* — set a tone few languages have matched.

Additionally: **Rust by Example** (executable examples), **The Cargo Book**, **The rustc Book**, **The Edition Guide**, and per-crate `rustdoc`-generated API references. Every stable version's documentation is preserved and reachable at a URL.

The design choices worth stealing:

1. **Documentation is part of the CI**. rustdoc failures are compile failures.
2. **Doctests**: `///` comments' code blocks are compiled and executed. Documentation cannot silently rot.
3. **Explicit audience segmentation** (beginner tutorial vs. reference vs. advanced) — no single doc has to serve every reader.
4. **Version pinning** ("This is documentation for Rust 1.80"). Fixes URL rot when major changes happen.

### 11.2 Interactive playgrounds

**Rust Playground** and **Go Playground** were the two influential examples. Both let a visitor paste code, run it in a sandbox, and share a URL that reproduces the exact session. Rust's Playground supports multiple compiler channels (stable, beta, nightly) and multiple optimization levels; Go's serves as the runnable snippet source in `go.dev/doc/effective_go` and many blog posts.

The engineering matters: both playgrounds run untrusted user code in tight sandboxes (Docker + seccomp historically), rate-limit compilation, and cache compilations aggressively. Their existence has become a de-facto expectation for new languages — a language that ships without a playground is judged less approachable, regardless of technical merit.

### 11.3 Formal language-evolution processes

Different languages have adopted structured processes for language changes.

**Python — PEPs (Python Enhancement Proposals)**, introduced by Barry Warsaw and Jeremy Hylton in PEP 1 (2000; still current) ([PEP 1](https://peps.python.org/pep-0001/)). A PEP is a design document; types are Standards Track, Informational, and Process. The process:

1. Discuss on `python-ideas`.
2. Submit a draft PEP as a pull request.
3. A **PEP editor** assigns a number.
4. Discussion moves to `python-dev`.
5. A **PEP delegate** (a topic expert designated by the Steering Council) accepts or rejects the PEP.

Notable PEPs: PEP 8 (style), PEP 20 (Zen of Python), PEP 484 (type hints), PEP 572 (walrus operator — famously contentious, its acceptance precipitated Guido's resignation as BDFL).

**Rust — RFCs**, since 2014, modeled loosely on IETF RFCs. An RFC is a markdown document in a git repository; it goes through a discussion period, then a **Final Comment Period** (FCP) declared by a team; then the responsible team either merges or closes. The RFC process is the entry point for anything user-visible: syntax, standard library API, or major internal changes with cross-team impact. The Leadership Council's 2023 RFC ([RFC 3392](https://rust-lang.github.io/rfcs/3392-leadership-council.html)) formalized governance atop the RFC process itself.

**Go — Go Proposals**, since 2014. Proposals are GitHub issues in `golang/go` tagged `Proposal`. A small **Proposal Review Committee** meets weekly and decides accept/reject; historically Rob Pike, Russ Cox, and Robert Griesemer were the deciders, now with a broader committee.

**Swift — Swift Evolution**, since Swift open-sourced in 2015 ([Swift Evolution](https://swift.org/swift-evolution/)). A proposal is a markdown file in a public repo; discussion happens on the Swift Evolution Forums; the **Language Steering Group** (formerly the Core Team) accepts, returns for revision, or rejects. Swift-Evolution's public review with dated deadlines and named reviewers is often cited as the most transparent language-evolution process.

Common patterns across these:

- A **public, versioned document** captures the design.
- A **fixed-length final comment period** prevents infinite discussion.
- A **small named group** ultimately decides — no infinite consensus-seeking.
- **Rejected proposals stay around** so the same discussion doesn't repeat.

### 11.4 Foundations and governance structures

The mature model is: engineering happens inside a technical governance structure (teams, committees) that is legally hosted by a **foundation** which owns trademarks, provides infrastructure funding, and offers legal indemnity.

- **Rust Foundation** (2021) — hosts trademarks, funds infrastructure, employs a Rust Project Directors slate. The **Leadership Council** (RFC 3392, 2023, effective mid-2023) is the top-level technical governance body: one representative from each top-level team, deciding by consensus on cross-team issues ([Leadership Council RFC](https://rust-lang.github.io/rfcs/3392-leadership-council.html)).
- **Python Software Foundation** — hosts CPython, PyPI, PyCon. The **Python Steering Council** (5 elected members, established in PEP 13 after Guido's resignation) makes technical decisions.
- **OpenJS Foundation** — hosts Node.js, jQuery, and many JavaScript projects.
- **Linux Foundation** — hosts many language-adjacent projects (Sigstore, OpenSSF, various runtime standards).
- **Eclipse Foundation** — hosts Jakarta EE, MicroProfile, and many JVM tools.
- **Haskell Foundation** (2021) — infrastructure and funding for GHC and the ecosystem.

The **OCaml** community has taken a different route: no foundation, but a well-oiled release process centered on INRIA/Tarides and a small compiler team.

### 11.5 The BDFL model and its collapse

Historically, several languages had a **Benevolent Dictator For Life** (BDFL) — a single person with final authority on all decisions.

- **Python**: Guido van Rossum, until July 2018.
- **Perl**: Larry Wall.
- **Ruby**: Yukihiro Matsumoto ("Matz") — still active but decisions are collaborative.
- **Lua**: Roberto Ierusalimschy.
- **Erlang**: Joe Armstrong (deceased 2019).

Guido's resignation was the loudest end of the model. After the acrimonious PEP 572 (walrus operator, `:=`) debate, Guido stepped down as BDFL and imposed no successor ([LWN — Van Rossum's resignation](https://lwn.net/Articles/759654/)). In his email, Guido wrote he was going on a "permanent vacation from being BDFL" and told the community *"I'm not going to appoint a successor... you're all responsible for this."* Python established the Steering Council within a year.

Why the model collapses:

1. **Scale**: modern language communities are too large for one person to serve as final decision-maker on every technical question.
2. **Burnout**: the BDFL takes disproportionate personal criticism during any controversial change.
3. **Bus factor**: a language whose future depends on one person is fragile.
4. **Legitimacy**: as languages become foundations of critical infrastructure, corporate stakeholders demand governance they can predict.

The successor model — steering councils elected by contributors, plus topical teams with delegated authority — is more resilient. Rust's council (representatives from each top-level team), Python's council (five elected), and Swift's Language Steering Group are the mature patterns.

### 11.6 Documentation tooling as ecosystem infrastructure

Language communities increasingly bundle documentation tooling:

- **rustdoc** — generates HTML/JSON docs from `///` comments; runs doctests; supports theming. Every crate on crates.io gets an auto-built docs.rs page.
- **godoc** — Go's docs are just formatted comments; `pkg.go.dev` renders them for every module.
- **Javadoc** — the granddaddy; the format influenced doxygen, rustdoc, godoc, and many others.
- **Sphinx** — Python's docs tool; extensible via reStructuredText and MyST-Markdown; used by CPython, Read the Docs, and thousands of projects.
- **Docusaurus** / **VitePress** / **Mintlify** — modern JavaScript-based site generators, often adopted for language landing pages.

The design decision: is documentation a *first-class* feature (rustdoc, godoc — auto-built, uniformly styled, cross-linked) or a *third-party* concern (C++, Python before Sphinx)? First-class documentation dramatically improves the ecosystem's average quality.

### 11.7 Community engineering as compiler engineering

The takeaway: for a language creator, community and documentation engineering is *not* a soft-skills afterthought. The differentials that make Rust, Go, and Swift succeed against equally-technical predecessors are largely: excellent errors (compiler engineering), excellent docs (documentation engineering), a working playground (tooling engineering), and a functional proposal process (governance engineering). Each of these is a design problem with real tradeoffs, worth as much thought as the type system.

---




### 11.8 The compiler-error-message revolution

A meta-observation: over the past ten years, the *quality of compiler error messages* has become a competitive differentiator, and the tooling to produce those messages has become a distinct engineering sub-discipline.

The Elm compiler (Evan Czaplicki) was one of the first to invest heavily. Rust's error messages — with their multi-line span-highlighted messages, suggestions ("did you mean `foo`?"), and structured JSON output for machine consumption — set a new bar. `rustc`'s error infrastructure (`DiagnosticBuilder`, `Suggestion`, `MultiSpan`) has been influential; GHC's error messages have improved dramatically since GHC 8.0's introduction of type-hole suggestions.

The engineering pattern:

- Errors are structured, not printf'd. Every diagnostic has a code (`E0308`), a primary span, secondary labels, and optional suggestions.
- Errors serialize to JSON for editor consumption (`rustc --error-format=json`).
- Every error has a documentation page (rustc's `--explain E0308`) with a longer explanation and worked example.
- The team runs error-message *user tests*. Rust holds "diagnostic-message" sprints where volunteers polish specific errors.

Any new language should invest here from day one. Bad errors don't just annoy users; they train users to reach for Stack Overflow (or now, LLMs) instead of learning the language.

### 11.9 Community infrastructure checklist

Beyond the technical proposals process, a mature language community typically maintains:

- **A discussion forum** (Discourse is dominant: Rust Users, Rust Internals, Swift, Julia, and dozens more all run Discourse; some use Zulip or Discord).
- **A weekly newsletter** (This Week in Rust, Go Weekly, Rails Weekly, TL;DR Sec).
- **A chat channel** (Discord/Zulip/Slack — the correct choice depends on the community's preferences).
- **A conference** (RustConf, GopherCon, PyCon, KotlinConf, ScalaConf).
- **A GSoC/mentorship program** for pipelining new contributors.
- **A style guide, contributor guide, and Code of Conduct.**
- **A public roadmap** with quarterly or annual updates.
- **A publicly-tracked backlog** of known bugs, RFCs in progress, and edition-in-progress work.

None of this is optional for a modern language project of any scale. Communities that skip any of it suffer for the omission.

### 11.10 The "edition" pattern for evolution

Rust introduced *editions* (2015, 2018, 2021, 2024) as a mechanism to make small language-level backward-incompatible changes without breaking existing code. Every crate declares an edition; each edition can introduce new keywords, change parsing rules, and reserve syntax; because editions are per-crate, mixing crates on different editions works. `cargo fix --edition` automates the mechanical migration.

This pattern has been adopted (with variations) by TypeScript (target versions), Python (`from __future__ import ...`), and Ruby (via `frozen_string_literal` and similar pragmas). It solves a real problem: **how to evolve a language without stranding the existing corpus**. For a language creator, the edition mechanism is worth building into the tooling from day one; it's much harder to retrofit an edition system than to include a `syntax = "1"` header in every source file from release 0.1.

## Cross-cutting: comparative tables and depth

The preceding sections surveyed each engineering area vertically. This section pulls the material sideways into comparison tables and adds targeted depth on topics that recur across the language stack.

### GC strategies compared

| Strategy | Pause model | Throughput | Memory overhead | Concurrency-safe | Compaction | Real examples |
|---|---|---|---|---|---|---|
| Reference counting (naive) | Fully incremental; individual decrements can cascade | Moderate; every write is a counter update | Header word per object | Requires atomic RMW | No | Python; historical Perl; Objective-C pre-ARC |
| Deferred / coalesced RC | Amortized decrements; near-zero pauses | Better than naive | Header word | With write-barriers | No | Recycler (IBM); Bacon-Rajan style |
| Reference counting + cycle collector | Small pauses for trial deletion | Moderate | Header + colors | Yes (Bacon-Rajan) | No | CPython + gc module; Nim ORC |
| Mark-sweep | Stop-the-world; O(heap) marking | High | ~1 mark bit / object | With write barriers | No | Historical HotSpot serial; Ruby MRI up to 2.x |
| Mark-compact | STW; O(heap) | High | 1–2 bits | With barriers | Yes | HotSpot Serial Old; Ruby's compact |
| Copying (Cheney) | STW; O(live) | Very high on small heaps | 2× live-set space needed | With barriers | Yes | Old MLton; historical HotSpot young-gen |
| Generational (2-space young + tenured) | Short young pauses + rare full pauses | Very high | 2× young space + tenured | With write barrier | Young gen compacted | HotSpot parallel; V8 Orinoco young gen |
| G1 (region-based generational) | Predictable STW target | High | ~10% for remembered sets | Yes (barriers) | Yes | OpenJDK G1 (default since Java 9) |
| Shenandoah | ~10 ms soft target; concurrent copying | Slight throughput cost vs G1 | 1 forward pointer per object | Yes; SATB + Brooks pointers | Concurrent | Red Hat OpenJDK ([Red Hat's Shenandoah guide](https://developers.redhat.com/articles/2024/05/28/beginners-guide-shenandoah-garbage-collector)) |
| ZGC | Sub-10 ms (originally <10, now <1 ms) | Very high | Colored 64-bit pointers | Yes; load barrier | Concurrent | OpenJDK 15+ ([JEP 333](https://openjdk.org/jeps/333)) |
| Azul C4 | Bounded, sub-ms | Very high | Loaded value barrier | Yes | Concurrent | Azul Prime JVM ([Azul C4 docs](https://docs.azul.com/prime/c4-garbage-collection.html)) |
| Go tri-color concurrent | Sub-ms typical | High | Small write-barrier cost | Yes | No (non-compacting) | Go runtime since 1.5 |
| Erlang per-process | Per-process STW; no whole-VM pause | High | Copies data on message send | N/A (isolated heaps) | Compacting per process | BEAM ([Erlang GC docs](https://www.erlang.org/doc/apps/erts/garbagecollection.html)) |
| ARC (Swift-style) | Deterministic; retain/release on assignment | Predictable; extra atomic ops | Retain count word | Yes (atomic ops) | No | Swift; Objective-C |
| ORC (Nim) | RC + backup cycle collector | High | RC + collector state | With acyclic optimizations | No | Nim ARC/ORC ([Nim ARC/ORC intro](https://nim-lang.org/blog/2020/10/15/introduction-to-arc-orc-in-nim.html)) |
| Metronome real-time | Hard real-time; fixed 1 ms slices | Somewhat lower than G1 | Time-slicing overhead | Yes | Incremental | IBM Metronome (embedded J9) |
| Ownership + regions (Rust) | None — all deterministic | Highest; no runtime cost | None | With unsafe | Static | Rust; Vale |

The trade curve is clear: fewer/shorter pauses cost some throughput (barriers, forwarding), and complete pause-elimination requires either an ownership discipline (Rust) or a per-actor isolation (Erlang). The "sub-ms concurrent" collectors (ZGC, C4, Shenandoah) close much of the gap but add colored-pointer or read-barrier costs.

### Parser strategy comparison

| Strategy | Grammar class | Error recovery | Left recursion | Speed | Ambiguity handling | Typical use |
|---|---|---|---|---|---|---|
| Hand-written recursive descent | LL(k), context-sensitive tweaks | Excellent (bespoke) | Manual rewriting | Fast | Manual | Rust, Go, Swift, Zig, TypeScript |
| Recursive descent + Pratt | LL + operator precedence | Excellent | Handled by Pratt loop | Fast | Precedence table | Zig, Carbon, most Lox implementations |
| LR / LALR (yacc, bison, Menhir) | LR(1)/LALR(1) | Fair (Menhir gives better) | Native | Fast | Table conflicts | OCaml, Ruby, PHP, historical GCC |
| ANTLR ALL(\*) | Any CFG | Good | Native | Linear typical, O(n^4) worst ([ALL(\*) paper](https://www.antlr.org/papers/allstar-techreport.pdf)) | Runtime disambiguation | ANTLR-hosted DSLs |
| PEG / Packrat (Ford) | Ordered-choice CFG | Fair | Requires special handling ([Tratt on PEG left recursion](https://tratt.net/laurie/research/pubs/html/tratt__direct_left_recursive_parsing_expression_grammars/)) | Linear (with memoization); linear in space | Ordered-choice (no ambiguity by construction) | Pest, tree-sitter (base), Python's new parser |
| Parser combinators (Parsec, nom) | Backtracking LL | Ok | Manual | Slower than table-driven | Explicit `try`/`choice` | Haskell DSLs; Rust nom for binary formats |
| Tree-sitter (GLR + PEG-like) | Ambiguous CFG | Excellent (partial-tree preservation) | Native | Linear incremental | Multi-tree merging | Editor tooling (Neovim, GitHub Atom lineage, Zed) |

The industry consensus for a *language* front end is: hand-written RD + Pratt. The industry consensus for *editor tooling* is: tree-sitter or a custom incremental parser. These are complementary, not competing choices; several languages (Rust with `rust-analyzer`) end up maintaining both.

### JIT strategies compared

| JIT model | Compilation unit | Speculation | Typical warm-up | Systems |
|---|---|---|---|---|
| Method JIT | Whole method | Type feedback via inline caches | Seconds | HotSpot C1/C2, V8 TurboFan, .NET RyuJIT |
| Tracing JIT | Hot loop trace | Guards on trace entry | Sub-second on hot code | LuaJIT, PyPy (meta-tracing), historical Firefox TraceMonkey |
| Baseline JIT | Bytecode 1:1 | Minimal | Immediate | V8 Sparkplug, JSC Baseline JIT, Wasm Liftoff |
| Baseline + optimizing (tiered) | Both above | Feedback flows tier-to-tier | Progressive | HotSpot C1→C2, V8 Ignition→Sparkplug→TurboFan, Wasm Liftoff→TurboFan |
| AOT with PGO | Whole program | Optional | None at run time | .NET NativeAOT with PGO, GraalVM native-image, Go with PGO |

Modern JIT engines are essentially all *tiered*. The V8 pipeline shows the full form: `Ignition` bytecode interpreter → `Sparkplug` baseline compiler → `Maglev` mid-tier optimizer → `TurboFan` optimizer, with `Liftoff` and `TurboFan` on the Wasm side ([V8 Wasm compilation pipeline](https://v8.dev/docs/wasm-compilation-pipeline); [Liftoff](https://v8.dev/blog/liftoff); [TurboFan](https://v8.dev/blog/turbofan-jit)). HotSpot's C1/C2 tiered arrangement was the earliest to formalize this pattern; the RedHat OpenJDK team's breakdown of tiered compilation remains the clearest introduction ([OpenJDK tiered compilation](https://devblogs.microsoft.com/java/how-tiered-compilation-works-in-openjdk/)).

### Verification-tool matrix

| Tool | Language | Underlying tech | Effort model | Typical use |
|---|---|---|---|---|
| CompCert | C | Coq; verified passes | Verified by proof engineers | Avionics, safety-critical ([CompCert doc](https://compcert.org/doc/)) |
| CakeML | ML | HOL4; verified compiler | Verified | Research-grade verified ML |
| Dafny | Dafny (verification-aware) | Z3 | Write specs; auto-verify | Cloud, cryptography ([Dafny home](https://dafny.org/)) |
| Verus | Rust subset | Z3, MIR-based | Write specs; auto-verify | Systems Rust ([Verus guide](https://verus-lang.github.io/verus/guide/)) |
| Prusti | Rust | Viper; Z3 | Write specs; auto-verify | Rust libraries ([Prusti at ETH](https://www.pm.inf.ethz.ch/research/prusti.html)) |
| Kani | Rust | CBMC bounded model check | Add proofs; run harness | AWS Firecracker, kernels ([Kani repo](https://github.com/model-checking/kani)) |
| F* | F* | Z3 + higher-order | Write specs; extract | Firefox HACL, EverCrypt ([F\* Wikipedia](https://en.wikipedia.org/wiki/F*_(programming_language))) |
| Lean 4 | Lean 4 | Type theory; auto/tactics | Interactive proof | Mathlib; recent industry projects ([Lean 4 codegen](https://deepwiki.com/leanprover/lean4/6.3-code-generation)) |
| Coq / Rocq | Gallina | Type theory; tactics | Interactive proof | CompCert; Iris/RustBelt; academic verification ([Rocq extraction](https://rocq-prover.org/doc/V8.18.0/refman/addendum/extraction.html)) |
| Idris 2 | Idris 2 | Dependent types + linear ([Idris 2 multiplicities](https://github.com/idris-lang/Idris2/blob/27780073c8631826d846499840b3857d9b9a4fd5/docs/source/tutorial/multiplicities.rst)) | Type-driven programming | Research, embedded DSLs |
| TLA+ | TLA+ | Explicit-state model check | Spec + model check | AWS, Microsoft distributed systems ([TLA+ Wikipedia](https://en.wikipedia.org/wiki/TLA%2B)) |
| Alloy | Alloy | SAT (Kodkod) | Structural spec | Modeling ([Alloy Wikipedia](https://en.wikipedia.org/wiki/Alloy_(specification_language))) |
| K framework | K rewrite rules | Rewrite + SMT | Language semantics | EVM semantics; C, Java ([K framework](https://kframework.org/)) |

### The IR menu, condensed

For a new language backend, the practical choices boil down to five buckets:

1. **Emit your own bytecode and interpret it.** Simplest to build; sufficient for many DSLs and scripting languages. See CPython, Ruby MRI, Lua's register VM ([Lua paper](https://www.lua.org/doc/jucs05.pdf)), and Erlang BEAM ([BEAM Book](https://blog.stenmans.org/theBeamBook/)).
2. **Emit your own bytecode and add a JIT.** LuaJIT is the poster child; PyPy through meta-tracing; V8's Ignition + Sparkplug + TurboFan as the industrial full form ([TurboFan](https://v8.dev/blog/turbofan-jit)).
3. **Emit LLVM IR.** Get the world's best optimizing backend, at the cost of significant compile time, a large dependency, and constrained memory-model expressiveness. Rustc, Swift, Julia, Clang, and dozens of research languages.
4. **Emit Cranelift IR.** Faster compilation and smaller footprint; production-grade for JIT (Wasmtime, Firefox Wasm) but fewer optimizations than LLVM ([Cranelift](https://cranelift.dev/); [Cranelift README](https://github.com/bytecodealliance/wasmtime/blob/main/cranelift/README.md)).
5. **Emit WebAssembly.** Gets you a target with a formal spec, an efficient JIT already implemented in every browser, and near-portability. Not always the right long-run target, but often a great intermediate.

The MLIR play — used by Mojo, IREE, and TensorFlow — is a sixth option: build your language on MLIR dialects and progressively lower to LLVM at the bottom ([MLIR paper](https://arxiv.org/pdf/2002.11054)). MLIR is uniquely well-suited to languages with heterogeneous compilation targets (CPU + GPU + accelerator).

### Runtime cost breakdown across memory models

| Model | Per-write cost | Per-alloc cost | Per-deref cost | Reclamation cost |
|---|---|---|---|---|
| Manual | Zero | Free-list traversal | Zero | Manual free() |
| Arena | Zero | Bump pointer | Zero | Bulk free per arena |
| Naive RC | Two atomic RMW (old, new) | Header init | Zero | Immediate on refcount=0 |
| Bacon-Rajan RC + cycle collect | Coalesced RMW | Header init | Zero | Immediate + rare cycle scans |
| Rust ownership | Zero | Allocator call | Zero | Deterministic drop on scope exit |
| Tracing GC (STW) | Zero | Bump pointer (in young gen) | Zero | Periodic pauses |
| Tracing GC (concurrent) | Small write-barrier | Bump pointer | Small load-barrier (Shenandoah/ZGC) | Continuous concurrent work |

This is why the choice is a language-design decision, not an implementation detail. A language with a naive RC design bakes a two-atomic-RMW cost into every field write; a language with a mark-compact GC bakes STW pauses into every program; a Rust-style ownership language bakes a training cost into every developer. There is no free lunch — only different bills.

### Concurrency primitives compared

| Primitive | Preemption model | Stack | Scheduler | Composable | Examples |
|---|---|---|---|---|---|
| Kernel thread | Preemptive | Large (default 1–8 MB) | OS | Yes | pthreads |
| Green thread (M:N) | Cooperative or hybrid | Configurable | Language runtime | Yes | Erlang; Go pre-1.14 |
| Goroutine (Go post-1.14) | Preemptive (async safepoints) | Segmented, grows to demand | Go runtime GMP | Yes | Go |
| Stackful coroutine | Explicit yield | Configurable | User | Yes | Kotlin coroutines; Lua; Wren |
| Stackless coroutine | Compiler-generated state machine | Heap-allocated frame | User via runtime | Yes | Rust async; C# async; Python asyncio |
| Actor | Message-passing | Isolated heap | Runtime | Yes | Erlang; Akka; Pony |
| Fork/join with work-stealing | Cooperative | Reused | Work-stealing deque | Yes | Cilk; Rayon; TPL; Java ForkJoinPool |
| STM | Optimistic transactions | N/A | Retry loop | Yes | Haskell STM; Clojure refs |
| Data-parallel (SIMD/GPU) | None | N/A | Compiler-lifted | Sometimes | CUDA; SPIR-V shaders; Halide |

The winning modern architecture — used by Go, Erlang, Rust+Tokio, .NET, and node.js — is: **stackless or shallow-stack coroutines multiplexed over a work-stealing thread pool by an M:N scheduler**, with I/O completions routed via an OS-level event loop (epoll/kqueue/io_uring/IOCP). The specifics vary; the pattern is universal.

## Cross-cutting: modern developer-experience baselines

A working new language in 2026 is expected to ship, on day one, most of the following:

- **A tree-sitter grammar or full LSP** so that editors have syntax highlighting and go-to-definition.
- **A formatter** with a documented style guide and no options ([gofmt](https://en.wikipedia.org/wiki/Language_Server_Protocol) set the norm).
- **A test framework** with an assertion library and a way to run only failed tests.
- **A property-based tester** in the QuickCheck lineage ([Koen Claessen's QuickCheck papers](https://link.springer.com/chapter/10.1007/978-3-642-17685-2_6)).
- **A fuzzer** with sensible integration into the standard test runner.
- **A package manager** with a lockfile, reproducible resolution, and (increasingly) content-addressed distribution.
- **A documentation tool** that runs at build time and fails CI on broken doctests.
- **A cross-compilation story** — a `--target` flag that produces binaries for common triples without a full second toolchain install.
- **A playground URL** where visitors can run examples in the browser.
- **A reproducible-builds story** that hashes deterministically ([Reproducible Builds project](https://reproducible-builds.org/); [Reproducible builds Wikipedia](https://en.wikipedia.org/wiki/Reproducible_builds)).
- **A supply-chain security posture**: signed releases, ideally through Sigstore's Cosign ([Sigstore container signing](https://docs.sigstore.dev/cosign/signing/signing_with_containers/)) or GPG, and an SBOM.
- **A public proposal process** with a written charter, review cadence, and archived decisions.

Falling short of this list is not an implementation failure; it is a *product* failure that will manifest in growth curves years later. Most of these deliverables are conservative engineering, well-documented, and cheaply built if planned for early. Retrofitting them onto an established codebase is much harder — the LSP requirement, in particular, often forces a major front-end refactor if a language shipped without one.

## Cross-cutting: what changes when the language is for AI

A closing note on a category the earlier sections did not treat directly. Several currently-visible new languages — Mojo, Bend, Hydra, and various DSLs embedded in mainstream languages — target AI / accelerator / heterogeneous compute. Their engineering priorities shift:

- **IR choice**: MLIR is the near-mandatory answer, because the language must lower to CPU, GPU, and neural-accelerator instruction sets simultaneously ([MLIR paper](https://arxiv.org/pdf/2002.11054)).
- **Memory model**: often a hybrid — an ownership discipline for user-facing safety, plus explicit device-memory regions or ownership types for the accelerator layer.
- **JIT**: often absent (compile once, deploy to accelerator) or heavily specialized (autotuning of kernels).
- **Concurrency**: dominated by data-parallel constructs (SPMD, `vmap`, tensor loops) rather than task parallelism.
- **Package management**: dominated by huge pretrained-artifact distribution (Hugging Face, ONNX Model Zoo) rather than source packages.

Most of the surveyed engineering menu still applies — a language for AI still needs lexing, parsing, type checking, error messages, tooling — but the weightings differ. The IR choice becomes decisive early; the memory-management choice becomes decisive later; the front-end choices are often the least distinctive.


## Where to start: a synthesis

For someone building a new language, the practical order of attack is roughly:

1. **Front end first**: recursive descent + Pratt for expressions, hand-written lexer. Emit a tree. Get something running by week two.
2. **Static core**: a bidirectional type checker over a small AST. Skip Hindley-Milner unless your language is explicitly ML-family.
3. **Interpreter before compiler**: build a tree-walking interpreter or a stack-based bytecode VM. This runs code end-to-end and unblocks language-design iteration.
4. **Backend when the design is stable**: choose Cranelift for fast iteration (Wasmtime/Rust bindings are the cleanest onboarding), LLVM for maximum performance and portability, or a custom bytecode VM if your semantics are unusual (Erlang, Python, Lua-style dynamism).
5. **Memory model choice is a decision, not a default**: pick one deliberately. Tracing GC, ARC, Rust-style ownership, region-based, or something newer (Vale's generational references). Every choice constrains what your language can express and what runtime cost it has.
6. **Ship an LSP by version 0.1**. Modern developer experience expectations require it.
7. **Formatter, doc generator, package manager, playground** — treat these as first-class engineering, not afterthoughts.
8. **Governance early**: publish a proposal process before you have your first painful decision to make. Even a stripped-down copy of Python's PEP 1 or Rust's RFC template is better than ad-hoc.
9. **Bootstrap discipline**: even if you use a mainstream host language for the first compiler, plan the self-hosting transition. Publish stage-0 seeds in an auditable form.
10. **Documentation is compiler output**: build docs at CI time, fail the build on broken doctests, and version the docs alongside the language.

The engineering menu described in this report is deep — but almost all of it can be adopted incrementally. The important early decisions are the ones that are hard to reverse: syntax (once used, it lives forever), memory model (shapes the entire runtime and standard library), and the type system's expressiveness (constrains what standard-library APIs can do). Compiler backends, package managers, formatters, and even parsing strategies can be replaced piecewise over years. Choose the reversible tools first, and let those pick be your prototypes; commit to the irreversible ones only after seeing them at scale in your own code.

---

## Appendix: further reading

For depth beyond this report, the following primary references were essential:

- **Parsing**: Crockford's "Top Down Operator Precedence" ([Crockford TDOP](https://www.crockford.com/javascript/tdop/tdop.html)); Ford's packrat papers ([Bryan Ford's PEG page](https://bford.info/packrat/)); Parr's ALL(*) paper ([ANTLR ALL(*)](https://www.antlr.org/papers/allstar-techreport.pdf)); the Parsec paper ([Leijen & Meijer Parsec](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/parsec-paper-letter.pdf)).
- **IRs**: the MLIR paper ([Lattner et al. MLIR](https://arxiv.org/pdf/2002.11054)); the LLVM Kaleidoscope tutorial ([LLVM tutorial](https://llvm.org/docs/tutorial/MyFirstLanguageFrontend/index.html)); the Cranelift docs ([Cranelift](https://cranelift.dev/)); the WebAssembly core spec ([Wasm specs](https://webassembly.org/specs/)).
- **Types**: the DK bidirectional paper ([Dunfield & Krishnaswami](https://www.cl.cam.ac.uk/~nk480/bidir.pdf)); the *Bidirectional Typing* survey ([Dunfield & Krishnaswami 2019](https://arxiv.org/abs/1908.05839)); the RustBelt paper ([Jung et al.](https://plv.mpi-sws.org/rustbelt/popl18/paper.pdf)).
- **Memory**: Bacon's *Unified Theory of Garbage Collection* ([Bacon et al.](https://web.eecs.umich.edu/~weimerw/2012-4610/reading/bacon-garbage.pdf)); the *Garbage Collection Handbook* (Jones/Hosking/Moss); the Cyclone regions paper ([Grossman et al.](https://www.cs.cornell.edu/Projects/cyclone/papers/cyclone-regions.pdf)).
- **Runtimes**: the Lua implementation paper ([Ierusalimschy et al.](https://www.lua.org/doc/jucs05.pdf)); V8's Liftoff and TurboFan posts ([Liftoff](https://v8.dev/blog/liftoff), [TurboFan](https://v8.dev/blog/turbofan-jit)); the BEAM Book ([BEAM Book](https://blog.stenmans.org/theBeamBook/)).
- **Concurrency**: the Cilk-5 paper ([Frigo/Leiserson/Randall](https://people.csail.mit.edu/matei/courses/2015/6.S897/readings/cilk.pdf)); the Tokio scheduler post ([Tokio 2019 scheduler](https://tokio.rs/blog/2019-10-scheduler)); the Composable Memory Transactions paper ([Harris et al.](https://simonmar.github.io/bib/papers/stm.pdf)).
- **Packages**: Russ Cox's MVS series ([research.swtch.com](https://research.swtch.com/vgo-mvs)); the PubGrub docs ([PubGrub-rs](https://github.com/pubgrub-rs/pubgrub)); SLSA levels ([SLSA v1.0](https://slsa.dev/spec/v1.0/levels)).
- **Tooling**: LSP spec ([microsoft.github.io/language-server-protocol](https://microsoft.github.io/language-server-protocol/)); DAP spec ([Debug Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/)); Reproducible Builds ([reproducible-builds.org](https://reproducible-builds.org/)).
- **Verification**: RustBelt; CompCert docs and publications ([CompCert doc](https://compcert.org/doc/); [CompCert publications](https://compcert.org/publi.html)); K Framework home ([kframework.org](https://kframework.org/)).
- **Bootstrapping**: Thompson's *Trusting Trust* ([Thompson 1984](https://www.cs.cmu.edu/~rdriley/487/papers/Thompson_1984_ReflectionsonTrustingTrust.pdf)); Guix full-source bootstrap ([Guix 2023 blog](https://guix.gnu.org/en/blog/2023/the-full-source-bootstrap-building-from-source-all-the-way-down/)); the rustc bootstrap docs ([Bootstrapping intro](https://rustc-dev-guide.rust-lang.org/building/bootstrapping/intro.html)); the Rust project's own historical lore ([Factory.ai Rust wiki](https://factory.ai/open-source-wikis/rust?page=lore.md)).
- **Community**: PEP 1 ([peps.python.org/pep-0001](https://peps.python.org/pep-0001/)); Rust Leadership Council RFC ([RFC 3392](https://rust-lang.github.io/rfcs/3392-leadership-council.html)); Swift Evolution ([swift.org/swift-evolution](https://swift.org/swift-evolution/)); LWN on Guido's resignation ([LWN 759654](https://lwn.net/Articles/759654/)).

Beyond these, the *Dragon Book* (Aho/Lam/Sethi/Ullman, *Compilers: Principles, Techniques, and Tools*), the *Tiger Book* (Appel, *Modern Compiler Implementation*), and Bob Nystrom's *Crafting Interpreters* remain the essential text-length references. For a language creator, working through Nystrom's second Lox implementation end-to-end is time spent as well as any equivalent-hour investment in this field.

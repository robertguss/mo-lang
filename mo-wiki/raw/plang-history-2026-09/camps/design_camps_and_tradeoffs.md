# Programming Language Design Camps and Tradeoffs

*A field map for language designers, drawn from primary sources: essays, talks, and technical reports by the people who built the languages.*

---

## How to read this document

Language design is not one activity but a family of related activities, and the people who do it disagree — often bitterly — about what a language is *for*. Some designers believe a programming language is a formal system whose primary job is to give static guarantees about programs; others believe it is a *medium* whose primary job is to help humans think; still others believe it is a piece of infrastructure whose primary job is to survive contact with production. These disagreements are not naive. They are the visible surface of a small number of deep tradeoffs, and every language embodies a position on each one.

This document maps the intellectual landscape of programming language design as a set of *camps*: coherent clusters of belief about what a language should be. For each camp we present its core beliefs, its exemplar languages, its most articulate advocates, the arguments it puts forward, the arguments made against it, and the concrete tradeoff it accepts in exchange for what it gains. Every substantive claim is cited to a primary source — a paper, a talk, a language specification, or a designer's own retrospective — that the reader can consult in full. Where camps disagree, both sides are presented in their own words.

The organization proceeds in eight dimensions: paradigm (Camp A), type system (Camp B), memory management (Camp C), concurrency (Camp D), syntax and readability (Camp E), compilation strategy (Camp F), design philosophy (Camp G), and ecosystem philosophy (Camp H). A final section catalogs the cross-cutting tradeoffs that any designer will inevitably confront.

---

# Camp A — Paradigm

The word "paradigm" was popularized in software by Peter Van Roy, whose "Programming Paradigms for Dummies" defines a paradigm as "an approach to programming a computer based on a mathematical theory or a coherent set of principles" and catalogs roughly thirty of them arrayed along axes of state, concurrency, and named side effects ([Van Roy, "Programming Paradigms for Dummies"](https://webperso.info.ucl.ac.be/~pvr/VanRoyChapter.pdf)). Van Roy's central methodological claim is that paradigms differ "only in one or a few concepts," and that a serious language designer should choose concepts, not paradigms, and combine them with care; his book *Concepts, Techniques, and Models of Computer Programming* (with Seif Haridi) is the most systematic development of this position ([Van Roy & Haridi, CTM](https://webperso.info.ucl.ac.be/~pvr/VanRoyHaridi2003-book.pdf)). What follows is a tour of the camps most language designers actually identify with in practice.

## A1 — Imperative / procedural: the computer model as truth

**Core belief.** The imperative camp holds that a program is a sequence of state changes executed on a machine, and that a language should be a comfortable notation for expressing those state changes. The abstract machine — memory, registers, mutation, sequencing — is not something to hide but something to *expose*, because the machine is where the program will actually run and where its performance will be decided.

**Exemplar languages.** FORTRAN, ALGOL, C, Pascal, Modula, Ada, Zig, Odin, Jai.

**Key advocates.** Dennis Ritchie and Brian Kernighan for C, Niklaus Wirth for the Pascal/Modula/Oberon line, Andrew Kelley for Zig, Jonathan Blow for Jai. Wirth's retrospective "Good Ideas, Through the Looking Glass" is the clearest single defense of the imperative-minimalist position: he argues that a language's job is to name the operations the machine actually performs, no more, and that any concept that cannot be efficiently implemented "does not belong in a programming language" ([Wirth, "Good Ideas, Through the Looking Glass"](http://pascal.hansotten.com/uploads/wirth/Good%20Ideas%20Wirth.pdf)).

**Arguments for.** The imperative camp's strongest argument is that computers themselves are imperative machines and that any language that pretends otherwise is layering a fiction over the truth. Wirth is explicit: he treats a programming language as a tool for writing programs whose behavior is inspectable step-by-step, and warns that language complexity — features added because they seemed elegant in the abstract — produces slow compilers, opaque runtime behavior, and unteachable languages ([Wirth, "Good Ideas"](http://pascal.hansotten.com/uploads/wirth/Good%20Ideas%20Wirth.pdf)). Andrew Kelley's introduction to Zig makes the same point in modern form: Zig has no hidden control flow, no hidden allocations, and no preprocessor, precisely because "everything you see is what you get," and because a systems programmer needs to know exactly what the machine will do at each source location ([Kelley, "Introduction to the Zig Programming Language"](https://andrewkelley.me/post/intro-to-zig.html)). Rob Pike's account of Go frames the design decision similarly, though Go admits a garbage collector: Pike argues Go was designed for "the software engineering done at Google" — for programmers working on multi-million-line systems who need fast compilation, clear semantics, and a language "simple enough to hold in one's head" ([Pike, "Go at Google: Language Design in the Service of Software Engineering"](https://go.dev/talks/2012/splash.article)).

**Arguments against.** The imperative camp is criticized on two fronts. First, from the functional camp: John Backus's Turing lecture "Can Programming Be Liberated from the von Neumann Style?" argues that imperative languages inherit the "von Neumann bottleneck" — a "word-at-a-time" style of thinking imposed by the machine's architecture — and that this bottleneck constrains programmer thought as much as it constrains hardware; Backus proposes function-level programming (FP) as an escape ([Backus, "Can Programming Be Liberated from the von Neumann Style?"](https://worrydream.com/refs/Backus_1978_-_Can_Programming_Be_Liberated_from_the_von_Neumann_Style.pdf)). Second, from the safety camp: manual state management produces a well-documented class of bugs — buffer overflows, use-after-free, data races — that other paradigms can prevent by construction. Wirth himself, in "A Plea for Lean Software," argues that a great deal of imperative software is bloated and unreliable because it accreted feature by feature without design discipline ([Wirth, "A Plea for Lean Software," 1995, IEEE Computer](https://people.inf.ethz.ch/wirth/Articles/LeanSoftware.pdf)).

**The tradeoff accepted.** *Direct control over the machine at the cost of programmer-supplied invariants.* Every memory bug is the imperative camp's price of admission. Zig, Odin, Jai, and modern C++ all offer richer type discipline than K&R C, but they still assume the programmer is willing to trade guarantees for control, and they organize the language around making the trade visible ([Kelley, "Introduction to Zig"](https://andrewkelley.me/post/intro-to-zig.html)).

## A2 — Object-oriented: four incompatible camps

"Object-oriented" is a single label covering four distinct traditions that agree on very little. Merging them under one heading is one of the most common sources of confusion in language design discussion.

### A2a — Class-based OO (Simula / C++ / Java)

**Core belief.** A program is a collection of *classes*: templates that bundle data with the operations that manipulate it, arranged in a taxonomy by inheritance. Encapsulation, inheritance, and polymorphism form the "three pillars" of the tradition. The intellectual root is Simula 67, whose designers Ole-Johan Dahl and Kristen Nygaard were solving simulation problems and needed to represent long-lived stateful entities with their own behavior ([Dahl & Nygaard, "The Birth of Object Orientation: The Simula Languages"](https://www.mn.uio.no/ifi/english/about/ole-johan-dahl/bibliography/the-birth-of-object-orientation-the-simula-languages.pdf)).

**Exemplar languages.** Simula, C++, Java, C#, Eiffel, Scala.

**Key advocates.** Ole-Johan Dahl and Kristen Nygaard (Simula), Bjarne Stroustrup (C++), James Gosling (Java), Bertrand Meyer (Eiffel). Stroustrup's own history in the HOPL IV paper is the most complete statement of the class-based-OO-with-zero-overhead position: he describes C++ as an attempt to combine "Simula-like classes" with "C-like efficiency," so that abstraction did not have to cost runtime ([Stroustrup, "Thriving in a Crowded and Changing World: C++ 2006-2020" HOPL IV](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf)).

**Arguments for.** Classes provide a natural unit of *modularity* — a class is a data type together with its operations, which matches the way engineers talk about "components" of a system. Barbara Liskov's original paper "Programming with Abstract Data Types" made the case that grouping operations with the data they act on is the primary defense against uncontrolled coupling in large programs. Stroustrup argues that C++'s combination of classes with templates gives "zero-overhead" abstraction: you don't pay at runtime for the abstractions you don't use, and abstractions you do use compile down to code as efficient as hand-written low-level code ([Stroustrup, HOPL IV](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf); [Blake Crosley, "Engineering Philosophy: Bjarne Stroustrup"](https://blakecrosley.com/pl/blog/engineering-philosophy-bjarne-stroustrup)).

**Arguments against.** The class-based tradition has been criticized from every other OO camp. The strongest internal critique is that inheritance couples data layout to behavior in ways that produce fragile hierarchies — the "fragile base class problem" and Liskov substitution violations. From the functional side, Rich Hickey's "Simple Made Easy" argues that classes *complect* state, identity, and behavior — three orthogonal concerns braided together into one construct — and that this braiding is the origin of a class of complexity ([Hickey, "Simple Made Easy" transcript](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/SimpleMadeEasy-mostly-text.md)). Alan Kay, whose Smalltalk work is often (misleadingly) grouped with Java's, made an even sharper criticism: he says the essential idea of OO is *messaging*, not *classification*, and that class-based languages captured the least important half of the original vision ([Kay, "The Early History of Smalltalk" HOPL II](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)).

**The tradeoff accepted.** *Modularity by taxonomy at the cost of taxonomy being brittle.* Once a class hierarchy exists, changing it becomes hard, and the class boundary becomes an interface people are afraid to move.

### A2b — Pure message-passing OO (Smalltalk / Objective-C / Ruby-influenced)

**Core belief.** An object is defined not by its class but by *what messages it responds to*. The messaging system is separate from any particular object; messages can be sent to any object, and if the object does not understand a message, it can decide dynamically what to do. In Alan Kay's own formulation, OO consists of "only messaging, local retention and protection and hiding of state-process, and extreme late-binding of all things" ([Hillel Wayne, "Alan Kay Did Not Invent Objects" — with Kay's own 1998 definition quoted](https://www.hillelwayne.com/post/alan-kay/)).

**Exemplar languages.** Smalltalk, Objective-C, Ruby (in its message-send semantics), Erlang (in its process model, which Joe Armstrong argued was the *real* OO).

**Key advocates.** Alan Kay, Dan Ingalls, Adele Goldberg. Ingalls's 1981 *Byte* magazine article "Design Principles Behind Smalltalk" is the manifesto: it states that the purpose of Smalltalk is "to support the creative spirit in everyone" and that the language should provide a "uniform metaphor" in which "everything is an object" and "computation is performed by sending messages" ([Ingalls, "Design Principles Behind Smalltalk"](https://research.cs.queensu.ca/home/cordy/cisc860/Biblio/drb/DC/ingalls81.pdf)).

**Arguments for.** Kay's HOPL II paper argues that message passing is fundamentally *more scalable* than procedure calls, because it separates the sender's intent from the receiver's implementation. In his description, an object is "a recursion on the notion of computer itself" — each object is a small computer, and the system as a whole "resemble[s] thousands and thousands of computers all hooked together by a very fast network" ([Kay, HOPL II Smalltalk paper](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)). This model is not just an abstraction: it is what happens on a distributed system, and Kay argues languages should be honest about that from the start. Hillel Wayne's commentary summarizes the practical consequence: because "the messaging system is independent from the object internals," messages can be sent between objects written in different languages, transmitted by mail, or received via SMS — the object protocol becomes a network protocol ([Hillel Wayne, "Alan Kay Did Not Invent Objects"](https://www.hillelwayne.com/post/alan-kay/)).

**Arguments against.** Pure message-passing sacrifices static checkability. If any object can respond to any message, the compiler cannot verify at compile time that a message will be understood — you find out at run time when the receiver returns `doesNotUnderstand`. Class-based OO advocates argue that this is exactly the safety net they want; message-passing advocates counter that late binding is precisely what enables the flexibility they want. Kay in the same paper acknowledges the tradeoff: Smalltalk's power comes from "extreme late binding," which produces a system that can be modified while running but that offers weaker static guarantees.

**The tradeoff accepted.** *Runtime flexibility and message-level extensibility at the cost of static verification.* You can build a live-programming environment, hot-swap code, and construct proxies transparently — but you also cannot know at compile time whether `foo.bar()` will succeed.

### A2c — Prototype-based OO (Self / JavaScript / Io / Lua)

**Core belief.** Classes are unnecessary machinery. Objects should be created directly and modified directly; new objects are made by cloning existing ones. The prototype tradition takes Kay's "everything is an object" and drops the class abstraction entirely.

**Exemplar languages.** Self, JavaScript, Io, Lua, NewtonScript.

**Key advocates.** David Ungar and Randall Smith, whose paper "SELF: The Power of Simplicity" is the founding document. They argue that classes are "an unnecessary complication in a system whose goal is simplicity" and that prototypes provide the same benefits as classes — sharing of behavior, inheritance-like reuse — without the additional layer of abstraction ([Ungar & Smith, "SELF: The Power of Simplicity"](https://bibliography.selflanguage.org/_static/self-power.pdf)).

**Arguments for.** Prototype-based systems are conceptually simpler: there is exactly one kind of thing (an object) and one operation (send a message, which is also the way to get and set slots). Ungar and Smith argue that this reduction "does not eliminate power" because a prototype can be used as a "class" whenever desired, but the language does not require you to think in classes. The Self paper is explicit that its design goal was "to reflect and enhance the unity of the language" by "unifying variables and slots," "unifying methods and data," and "unifying methods and closures" ([Ungar & Smith, "SELF: The Power of Simplicity"](https://bibliography.selflanguage.org/_static/self-power.pdf)). Wikipedia summarizes the historical influence: Self's prototype model directly inspired JavaScript's object model when Brendan Eich designed the language in 1995 ([Wikipedia, "Self (programming language)"](https://en.wikipedia.org/wiki/Self_(programming_language))).

**Arguments against.** The class-based camp argues that prototypes make it harder to state structural invariants: you cannot easily say "all objects of this kind have these fields" if any object can add or remove fields at any time. JavaScript's history bears this out; TypeScript exists in part to bring structural typing back to a prototype-based language that grew too large to reason about informally ([Microsoft, "TypeScript Design Goals"](https://github.com/microsoft/TypeScript/wiki/TypeScript-Design-Goals)).

**The tradeoff accepted.** *Radical simplicity of the object model at the cost of taxonomic structure that other tools can rely on.*

### A2d — CLOS-style generic functions (Common Lisp / Dylan / Julia)

**Core belief.** The unit of behavior is not the class but the *generic function*. A generic function has multiple *methods*, each of which is dispatched based on the types of *all* its arguments — not just the first. This is "multiple dispatch" or "multi-methods," and it fundamentally decouples behavior from data.

**Exemplar languages.** Common Lisp (via CLOS), Dylan, Julia, Nice, Fortress.

**Key advocates.** Gregor Kiczales, Jim des Rivières, and Daniel Bobrow for CLOS; Jeff Bezanson, Stefan Karpinski, Viral Shah, and Alan Edelman for Julia. The Julia design papers are the clearest modern statement: Julia is built around multiple dispatch because "software has come to rely on multiple abstractions, whose behavior must be composable," and single-dispatch OO cannot compose them naturally — a numeric type author cannot add behavior to an existing algorithm without either subclassing or modifying the algorithm's source ([Bezanson et al., "Julia: A Fresh Approach to Numerical Computing"](https://math.mit.edu/~edelman/publications/julia_a_fresh.pdf); Chung & Vitek, "Julia: Dynamism and Performance Reconciled by Design" [PDF](https://benchung.github.io/papers/jlov.pdf)).

**Arguments for.** Multiple dispatch solves what Julia's designers call "the expression problem" for scientific computing: you can add both new types (new numeric representations) and new operations (new algorithms) without modifying either party. Julia's authors argue that this is the essential reason Julia can achieve C-like performance on abstract mathematical code — because dispatch happens on the concrete types of the arguments, the compiler can specialize each call site fully ([Bezanson et al., "Julia: A Fresh Approach"](https://math.mit.edu/~edelman/publications/julia_a_fresh.pdf)). Increment's history of Julia summarizes the position: multiple dispatch is the "Goldilocks" abstraction — more expressive than single dispatch, less arbitrary than global functions ([Increment, "Julia: The Goldilocks language"](https://increment.com/programming-languages/goldilocks-language-history-of-julia/)).

**Arguments against.** Multiple dispatch complicates encapsulation. When a method's applicability depends on multiple types, you cannot look at a class and know what its instances can do — you must look at all generic functions defined anywhere in the program. Class-based OO advocates argue this makes systems harder to reason about locally. Julia has partially answered this with its structural type system and Cassandra-like package protocols, but the criticism stands.

**The tradeoff accepted.** *Composable behavior across types at the cost of local reasoning about a type's capabilities.*

## A3 — Pure functional (Haskell, Elm, Roc, PureScript)

**Core belief.** A function is a mapping from inputs to outputs, and nothing more. Same inputs always produce same outputs — this is *referential transparency* — and side effects (I/O, mutation, exceptions) are either absent from the language or made explicit in the type system. The pure functional camp treats programs as mathematical expressions to be evaluated, not as sequences of commands to be executed.

**Exemplar languages.** Haskell, Elm, Roc, PureScript, Miranda, Idris (in its functional core).

**Key advocates.** Simon Peyton Jones, Philip Wadler, Paul Hudak, John Hughes, Evan Czaplicki (Elm), Richard Feldman (Roc). Simon Peyton Jones's "Wearing the hair shirt: a retrospective on Haskell" is the definitive first-person account of what the tradeoff feels like from the inside. He describes the decision to make Haskell lazy and pure as "the hair shirt" — an uncomfortable commitment that forced the language to develop novel solutions (like monads for I/O) that turned out to be more powerful than the workarounds other languages resorted to ([Peyton Jones, "Wearing the hair shirt: a retrospective on Haskell"](https://simon.peytonjones.org/wearing-the-hair-shirt/)).

**Arguments for.** Peyton Jones and the Haskell committee's HOPL III paper "A History of Haskell: Being Lazy with Class" argues that the payoff for purity is enormous: because functions cannot have hidden effects, they can be reordered, memoized, and parallelized freely; because effects are visible in types, "the type of a function tells you a great deal about what it does and, more importantly, what it does not do" ([Peyton Jones et al., "A History of Haskell: Being Lazy with Class"](https://simon.peytonjones.org/assets/pdfs/haskell-being-lazy-with-class.pdf)). The paper reports the Haskell committee's slogan "avoid success at all costs," which Peyton Jones later re-glossed as "avoid *success-at-all-costs*" — the point was to keep the language a research vehicle so that it would remain free to make hard design changes without a large legacy user base demanding stability. That freedom, he argues, is what let Haskell develop features like STM, GADTs, and type families that later diffused into other languages.

**Arguments against.** The most serious criticism is that referential transparency is dogmatic and buys less than it costs. Rich Hickey, from the impure-functional camp, argues that purely functional languages solve the wrong problem when they force everything through monadic pipelines: what programmers need is not the elimination of state but a *value* abstraction over state, and Clojure's persistent data structures achieve that without laziness or monads ([Hickey, "The Value of Values" transcript](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/ValueOfValues.md)). A second criticism, from within the pure functional community itself, is that Haskell's lazy evaluation makes performance reasoning difficult: an "innocuous" expression can allocate a huge thunk, and debugging space leaks requires deep knowledge of the runtime. Peyton Jones acknowledges this: the "hair shirt" of laziness has been the most costly aspect of Haskell's purity ([Peyton Jones, "Wearing the hair shirt"](https://simon.peytonjones.org/wearing-the-hair-shirt/)). Roc's design papers argue for the pure functional camp *without* laziness — Roc is strict, has no runtime exceptions, and pushes all effects out to platform code — and Richard Feldman argues this preserves the benefits of purity while making performance predictable ([Roc, "Fast"](https://www.roc-lang.org/fast)).

**The tradeoff accepted.** *Rigorous compositionality at the cost of a steeper learning curve and the need to encode effects in types.* Peyton Jones's slogan captures it: "if you have not learned to program in a pure functional language, you have not yet learned to program with values."

## A4 — Impure functional (ML, OCaml, F#, Scheme, Clojure, Erlang, Elixir)

**Core belief.** First-class functions, algebraic data types, and pattern matching are the important gains from the functional tradition; strict adherence to purity is not. Programs should be *mostly* functional, with mutation and effects available where they pragmatically help. The impure functional camp positions itself as the "engineering" branch of functional programming: it takes what works from Haskell and ML and drops what doesn't scale.

**Exemplar languages.** Standard ML, OCaml, F#, Scheme, Racket, Clojure, Erlang, Elixir.

**Key advocates.** Robin Milner (ML), Xavier Leroy (OCaml), Matthias Felleisen (Racket), Rich Hickey (Clojure), Joe Armstrong (Erlang), José Valim (Elixir). The Standard ML tradition begins with Robin Milner's formal *Definition of Standard ML*, which insisted that a language should have a mathematical semantics complete enough to serve as a reference for all implementations ([Milner, Tofte, Harper, "The Definition of Standard ML"](https://smlfamily.github.io/sml90-defn.pdf)). Rich Hickey's talks are the most complete modern statement of the impure-functional-plus-immutability position: "Simple Made Easy," "The Value of Values," and "Are We There Yet" together lay out the argument that immutability by default, but not enforcement, is the sweet spot ([Hickey, "Simple Made Easy"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/SimpleMadeEasy-mostly-text.md); [Hickey, "The Value of Values"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/ValueOfValues.md); [Hickey, "Are We There Yet"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/AreWeThereYet.md)).

**Arguments for.** The impure-functional case is essentially pragmatic: pure functional programming makes some things elegant (map/filter/reduce) and some things painfully awkward (updating a deeply nested record in place, threading state through a computation), and the tradeoff is not worth it when a controlled `ref` cell or a well-scoped effect would do. OCaml is the canonical example: it has ML's type system and pattern matching, and it has assignment. Xavier Leroy's ecosystem argues this is exactly what makes OCaml productive for compilers, theorem provers, and financial systems — you can write in a functional style when it helps and drop to imperative code where it helps more ([OCaml, "Why OCaml?"](https://ocaml.org/about)). Hickey's argument for Clojure is that "state is never simple" because it complects value with time, and that the solution is not to ban state but to make *identity* — a reference to a series of values over time — the abstraction one works with, while values themselves remain immutable ([Hickey, "The Value of Values"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/ValueOfValues.md); [Hickey, "Are We There Yet"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/AreWeThereYet.md)). Erlang's contribution to the impure-functional tradition is different again: Joe Armstrong's thesis argues that a functional core is essential for reasoning about single processes, but that between processes the world is inherently concurrent, distributed, and failure-prone, and no purely functional model captures that ([Armstrong, "Making reliable distributed systems in the presence of software errors"](https://erlang.org/download/armstrong_thesis_2003.pdf)).

**Arguments against.** From the pure functional side: any language that permits uncontrolled effects loses the reasoning benefits it advertises. If a function can secretly mutate global state, referential transparency is a false promise. Peyton Jones's Haskell papers argue that "controlled effects" without a formal effect system devolve into "hopeful discipline," which does not scale ([Peyton Jones, "Wearing the hair shirt"](https://simon.peytonjones.org/wearing-the-hair-shirt/)). Hickey's counter-critique is that Haskell's alternative — monadic effect encoding — imposes its own tax that most working programmers do not want to pay, and that immutability-by-default with escape hatches is more honest ([Hickey, "Effective Programs — 10 Years of Clojure"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/EffectivePrograms.md)).

**The tradeoff accepted.** *Pragmatic engineering flexibility at the cost of losing the ability to statically prove effect-free-ness.* Impure functional languages accept that some things need mutation and that a language should let you write them without ceremony, in exchange for weaker global guarantees.

## A5 — Logic programming (Prolog, Mercury, miniKanren, Datalog)

**Core belief.** A program is a set of *relations*, and a computation is a search for values that satisfy those relations. The programmer specifies *what* the answer looks like — a set of logical constraints — and the runtime figures out *how* to find it, typically via unification and backtracking.

**Exemplar languages.** Prolog, Mercury, miniKanren (embedded in Scheme and Clojure), Datalog, ASP (Answer Set Programming).

**Key advocates.** Alain Colmerauer and Philippe Roussel (Prolog), Robert Kowalski (logic programming as a paradigm). Colmerauer's own history "The Birth of Prolog" describes the origin: Prolog was designed to process natural language by expressing grammars as logical relations, and the language grew from the observation that "the same program could serve both to compose sentences and to analyze them" — a computation could be run in either direction ([Colmerauer, "The Birth of Prolog"](http://alain.colmerauer.free.fr/alcol/ArchivesPublications/PrologHistory/19november92.pdf)).

**Arguments for.** Colmerauer argues that the ability to run a program in multiple directions — using the same definition of `append` both to concatenate lists and to enumerate all ways of splitting a list — is a form of expressive power no other paradigm offers. Datalog's modern revival in software analysis, cloud query planning, and knowledge graph systems shows that the logic-programming model still finds new applications when a problem is naturally relational and non-recursive.

**Arguments against.** Backtracking search is expensive in the general case, and predicting performance in a Prolog program often requires understanding the search order in detail — undermining the paradigm's declarative promise. Mercury addresses this by adding a mode system (each argument is marked as input or output at each call site), but this reintroduces much of the imperative reasoning burden. Datalog addresses it by restricting the language to a decidable subset. In both cases, the pure logic-programming ideal is compromised for tractability.

**The tradeoff accepted.** *Declarative expressive power at the cost of unpredictable performance without careful mode discipline.*

## A6 — Concatenative / stack-based (Forth, Factor, Joy, PostScript)

**Core belief.** Programs are compositions of functions on an implicit stack. There are no variables; there are only operations that consume the top of the stack and push results back. Composition is concatenation: `f g` means "do f, then do g on the result." This point-free style is taken to its logical extreme.

**Exemplar languages.** Forth, Factor, Joy, PostScript, Cat, Kitten.

**Key advocates.** Chuck Moore (Forth), Manfred von Thun (Joy). Moore's book *Programming a Problem-Oriented Language* is the founding document; he argues that a good programming environment is one in which the programmer *builds their own language*, adding words as needed to describe the problem at hand, until the top-level program reads like domain-specific vocabulary ([Moore, "Programming a Problem-Oriented Language"](https://www.forth.org/POL.pdf)). Von Thun's Joy pages develop the theory further, arguing that concatenative languages are the true realization of "functions as first-class values" — because a program *is* a function, and juxtaposition of programs *is* function composition ([von Thun, "The Joy Programming Language"](https://hypercubed.github.io/joy/joy.html)).

**Arguments for.** Concatenative languages have unique compositional properties. The identity `(f g) h = f (g h)` holds trivially because juxtaposition is composition — no variables are needed. Chuck Moore argues that Forth's smallness (a self-hosted Forth can fit in a few kilobytes) and its immediacy (every word can be tested at the console the moment it is defined) make it uniquely productive for embedded and hardware-adjacent work.

**Arguments against.** Programs written in point-free style become unreadable past a certain size. Managing the stack — remembering what is on top of it at each program point — is a burden that other languages do not impose. Concatenative languages have found niche success (Forth in embedded firmware, PostScript in printing) but have not spread to general-purpose programming, and their advocates concede that the paradigm is best suited to programmers who genuinely enjoy stack manipulation.

**The tradeoff accepted.** *Extreme compositional elegance and small implementation size at the cost of readability and mainstream adoption.*

## A7 — Array languages (APL, J, K, BQN, Q)

**Core belief.** The fundamental unit of computation is not the scalar but the *array*. Operations apply to whole arrays at once; loops are almost absent from the code because the operators already iterate. Terseness is a virtue because it lets the entire program fit on one screen, allowing the programmer to see the whole shape of the algorithm at once.

**Exemplar languages.** APL, J, K, BQN, Q, Nial.

**Key advocates.** Kenneth Iverson (APL, J), Arthur Whitney (K, Q). Iverson's Turing lecture "Notation as a Tool of Thought" is the founding manifesto: he argues that the notation used to express a problem shapes what solutions the programmer can even imagine, and that a rich notation for array manipulation makes visible patterns that scalar notation hides ([Iverson, "Notation as a Tool of Thought"](https://www.eecg.utoronto.ca/~jzhu/csc326/readings/iverson.pdf)).

**Arguments for.** Iverson's argument is fundamentally epistemic: "the quality of the language used has a strong influence on the effectiveness and even the quality of thought" ([Iverson, "Notation as a Tool of Thought"](https://www.eecg.utoronto.ca/~jzhu/csc326/readings/iverson.pdf)). He gives many examples where APL's rank polymorphism (an operator automatically distributes over the axes of its arguments) reveals mathematical identities that are invisible in scalar code. Modern array languages have a second argument: because operations are on whole arrays, an APL-family compiler can vectorize aggressively without programmer intervention — the code is "already parallel" in shape.

**Arguments against.** The main complaint is readability: APL uses a large character set of custom symbols, and programs are famously write-only. J and BQN partly address this by using ASCII, but the terseness itself remains an obstacle for new readers. A second criticism is generality: array languages are extraordinary for numerical and tabular problems but awkward for problems that are naturally tree-shaped or graph-shaped, where the "everything is an array" assumption stops paying rent.

**The tradeoff accepted.** *Whole-program visibility and free parallelism at the cost of a steep notational learning curve and narrower problem domain.*

## A8 — Dataflow and reactive (Lucid, Esterel, Lustre, FRP)

**Core belief.** A program is a network of *streams* — infinite sequences of values over time — connected by transformations. Time is a first-class dimension; programs specify *how values flow* rather than *what to do step by step*.

**Exemplar languages.** Lucid (the original), Esterel (synchronous, reactive), Lustre (synchronous dataflow), Signal, Haskell Fran (FRP), Elm (with functional reactive influence), SAM in Rx libraries.

**Key advocates.** Bill Wadge and Ed Ashcroft (Lucid), Gérard Berry (Esterel), Nicolas Halbwachs and Paul Caspi (Lustre), Conal Elliott and Paul Hudak (Fran / FRP). The Lustre paper describes the synchronous dataflow model precisely: a Lustre program computes at a series of discrete instants, and at each instant each variable has a single value determined by the equations of the program ([Halbwachs et al., "The synchronous data-flow programming language Lustre"](http://www.artist-embedded.org/docs/PositionPapers/ProgrammingLanguages/lustre.pdf)). Elliott and Hudak's ICFP '97 paper "Functional Reactive Animation" gives the founding FRP model: behaviors are time-varying values and events are time-indexed occurrences, and the programmer combines them with pure functions ([Elliott & Hudak, "Functional Reactive Animation"](http://conal.net/papers/icfp97/)).

**Arguments for.** In embedded and safety-critical domains, synchronous dataflow languages provide something no imperative language can: a formal semantics for real time that permits automatic verification of timing properties. Lustre is used in commercial avionics through the SCADE toolchain — Airbus flight software is programmed in Lustre-derived notation precisely because the timing behavior is provable, not just tested ([Halbwachs et al., Lustre paper](http://www.artist-embedded.org/docs/PositionPapers/ProgrammingLanguages/lustre.pdf)). FRP is defended on different grounds: Elliott argues that many interactive programs are naturally described in terms of time-varying signals, and that FRP eliminates whole classes of callback-related bugs by making the flow of data explicit.

**Arguments against.** Dataflow languages have not achieved general-purpose adoption. The synchronous model works when computation is *bounded* per tick but breaks down for unbounded work. FRP has faced sustained criticism for space leaks (behaviors that retain their history longer than needed) and for the difficulty of implementing genuinely efficient FRP runtimes; Elm eventually moved away from FRP in favor of its Model-Update-View architecture ([Wikipedia, "Elm (programming language)"](https://en.wikipedia.org/wiki/Elm_(programming_language))).

**The tradeoff accepted.** *Formal reasoning about time and change at the cost of restrictions on what programs can express and how efficiently they can run.*

## A9 — Constraint programming (Oz, Prolog CLP, MiniZinc)

**Core belief.** A program is a set of constraints over variables; a solver finds values that satisfy all constraints simultaneously. Constraint programming is a specialization of logic programming toward problems that have a clean combinatorial structure.

**Exemplar languages.** Oz (multi-paradigm with strong constraint support), Prolog with CLP libraries, MiniZinc, Choco, Gecode.

**Key advocates.** Peter Van Roy and Seif Haridi (Oz). Their book *Concepts, Techniques, and Models of Computer Programming* devotes substantial space to constraint programming as a "declarative concurrent" paradigm, and argues that constraints are one of the four "little-known but important" concurrency paradigms language designers should study ([Van Roy & Haridi, CTM](https://webperso.info.ucl.ac.be/~pvr/VanRoyHaridi2003-book.pdf); [Van Roy, "Programming Paradigms for Dummies"](https://webperso.info.ucl.ac.be/~pvr/VanRoyChapter.pdf)).

**Arguments for.** For combinatorial problems — scheduling, packing, resource allocation — constraint programming is dramatically more concise than imperative search code, and modern solvers have absorbed decades of algorithmic engineering (arc consistency, branch and bound, symmetry breaking) that the programmer would otherwise reimplement badly. MiniZinc is designed as a *modeling* language that compiles to multiple solver backends, decoupling the specification of the problem from the choice of algorithm ([MiniZinc project](https://www.minizinc.org/)).

**Arguments against.** As with logic programming, performance is unpredictable: the same model can solve in milliseconds or run for hours depending on branching heuristics that the modeler must reason about. Constraint programming has therefore remained a specialist tool.

**The tradeoff accepted.** *Extreme conciseness for combinatorial problems at the cost of specialist knowledge and performance opacity.*

## A10 — Actor-based (Erlang, Pony, Akka, Orleans)

**Core belief.** The unit of concurrency is an *actor*: an entity with private state that communicates with other actors only by sending asynchronous messages. Actors do not share memory. This is Carl Hewitt's original vision, refined by Joe Armstrong into an engineering philosophy.

**Exemplar languages.** Erlang, Elixir, Pony, Akka (as a library on the JVM), Orleans (.NET).

**Key advocates.** Carl Hewitt (foundational), Joe Armstrong (engineering), Sylvan Clebsch (Pony). Hewitt, Bishop, and Steiger's IJCAI '73 paper "A Universal Modular ACTOR Formalism" introduces actors as a unifying model: "data structures, functions, semaphores, monitors, ports, descriptions, Quillian nets, logical formulae, numbers, identifiers, demons, processes, contexts, and data bases can all be shown to be special cases of actors" ([Hewitt, Bishop, Steiger, IJCAI '73](https://ijcai.org/Proceedings/73/Papers/027B.pdf)). Armstrong's PhD thesis "Making reliable distributed systems in the presence of software errors" reframes actors as an engineering discipline: the world is unreliable, processes will fail, and the correct language response is to make process isolation and message passing so cheap that failure isolation becomes the default ([Armstrong thesis](https://erlang.org/download/armstrong_thesis_2003.pdf)).

**Arguments for.** Armstrong's argument is that the actor model provides "the only" scalable answer to concurrency in the presence of failure: shared memory is a lie in a distributed system, and any language that offers shared memory as its primary concurrency abstraction will fail when the system actually distributes. His thesis reports Erlang's practical success on large telecom systems with "nine nines" of availability, made possible because process isolation lets a supervisor restart failed processes without corrupting the rest of the system — the "let it crash" philosophy ([Armstrong thesis](https://erlang.org/download/armstrong_thesis_2003.pdf)). Pony's designers extend the argument with type-level guarantees: Pony's *reference capabilities* let the compiler verify that no two actors can hold aliasing mutable references to the same object, which means data race freedom is provable, not just conventional ([Clebsch et al., "Deny capabilities for safe, fast actors"](https://www.ponylang.io/media/papers/codesigning.pdf)).

**Arguments against.** Actor systems are dogmatically message-oriented, which imposes overhead on problems that would be better served by shared-memory concurrency. Every state update crosses a mailbox; batch computations that would be a few loop iterations in a threaded language become a dance of send-and-await. Additionally, message ordering across actors is only partially specified in most actor languages, which can make reasoning about global invariants hard. CSP advocates (Go, Occam) argue that channels, not mailboxes, are the right primitive because channels can express synchronization directly, without protocol.

**The tradeoff accepted.** *Failure isolation and location transparency at the cost of shared-memory efficiency and immediate synchronization.*

---

# Camp B — Type systems

Nowhere is programming language disagreement more visible than in the type systems debate. This section walks through the fourteen camps in order of increasing static enforcement, then examines the two most consequential cross-camp debates: static-vs-dynamic and the maintenance-vs-exploration tradeoff.

## B1 — Untyped / no type system

**Core belief.** A language does not need a type system. The programmer knows what values they are passing to what functions; the runtime will do what it is told; if something goes wrong, the programmer will see it in the output. Early Lisp is the canonical example.

**Exemplar languages.** McCarthy's original Lisp, early shell languages, TeX (as a programming language), most assemblers.

**Arguments for.** No type system means no type-system overhead: no annotation burden, no ceremonial casts, no restrictions on what can be composed. In the sense in which Peter Landin's "The Next 700 Programming Languages" celebrates the LISP tradition, an untyped language captures the "essential" computation model without accreting features ([Landin, "The Next 700 Programming Languages"](https://www.cs.cmu.edu/~crary/819-f09/Landin66.pdf)).

**Arguments against.** Even Lisp evolved. Common Lisp and Scheme both introduced type predicates and, later, optional type declarations, precisely because the pure untyped position did not scale to large systems. Robert Harper's argument (developed below) is that a language without a type system is not really "type-free" — it just has one type, applied uniformly.

**The tradeoff accepted.** *Maximal simplicity at the cost of no compile-time guarantees whatsoever.*

## B2 — Dynamically typed (Python, Ruby, JavaScript, Lua, Clojure)

**Core belief.** Types exist and matter, but they are properties of *values*, not of *variables* or *expressions*. Every value carries a runtime tag; operations check the tag when they run. Type errors are runtime errors, discovered during execution.

**Exemplar languages.** Python, Ruby, JavaScript, Lua, PHP, Perl, Smalltalk, Clojure.

**Key advocates.** Guido van Rossum (Python), Yukihiro Matsumoto (Ruby), Rich Hickey (Clojure). Matsumoto's stated philosophy — "the principle of least surprise" and "programmer happiness" — is that a language should trust the programmer and stay out of the way; dynamic typing is one expression of that trust ([Interview with Matz, "The Philosophy of Ruby"](https://www.artima.com/articles/the-philosophy-of-ruby)).

**Arguments for.** Rich Hickey's talks make the sharpest defense of dynamic typing in a modern language. In "Effective Programs — 10 Years of Clojure," he argues that most large systems are actually *information systems* — programs that pass around dictionary-like values whose shape evolves over time — and that static type systems force the programmer to *name* structures at points where naming buys nothing and costs flexibility ([Hickey, "Effective Programs"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/EffectivePrograms.md)). In "Maybe Not," he makes a more targeted attack: he argues that most static type systems handle *optionality* incorrectly by conflating "this argument is optional" with "this value has an optional wrapper," making non-breaking changes (like relaxing a requirement) look like breaking changes ([Hickey, "Maybe Not"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/MaybeNot.md)).

The classical defense is different: dynamic typing enables *exploratory programming*. A programmer developing an algorithm can try things at the REPL, get results back immediately, and iterate — without a compile step forcing all the pieces to line up before any of them can be tested. This is one of the reasons SICP, using Scheme, teaches by having students evaluate expressions interactively rather than by writing whole programs ([SICP](https://en.wikipedia.org/wiki/Structure_and_Interpretation_of_Computer_Programs)).

**Arguments against.** Robert Harper's "Dynamic Languages are Static Languages" is the most cited counter-argument. He argues that a dynamically typed language is not "typeless"; it is a statically typed language whose type system happens to have *exactly one type*, a sum of all runtime classes. Harper writes: "Dynamic typing is but a special case of static typing" and calls dynamically typed languages "unityped" (borrowing Dana Scott's term): "instead of offering many types, they offer one type" ([Harper, "Dynamic Languages are Static Languages"](https://existentialtype.wordpress.com/2011/03/19/dynamic-languages-are-static-languages/)). The polemical form of the argument is that dynamic typing "limits, rather than liberates" — because the programmer cannot state and enforce the invariant "this value is an integer here" without a static type system to express it. Daniel Holden's "In Defence of the Unitype" summarizes Harper accurately and then defends dynamic languages on different grounds: unityped languages have a *simpler mental model* because the programmer needs only a computation model, not both a computation model and a type model, and this simplicity is genuinely valuable ([Holden, "In Defence of the Unitype"](https://theorangeduck.com/page/defence-unitype)).

**The tradeoff accepted.** *Freedom to iterate quickly at the cost of runtime type errors and larger effective refactoring cost in large systems.*

## B3 — Gradual typing (TypeScript, Sorbet, mypy, Hack, Typed Racket)

**Core belief.** Static and dynamic typing are not either-or. A gradual type system lets the programmer add annotations *incrementally* — statically checking parts of the program while leaving the rest dynamically checked — with runtime checks at the boundary to preserve soundness or (in some designs) at least preserve blame assignment.

**Exemplar languages.** TypeScript, Typed Racket, Sorbet (Ruby), mypy (Python), Hack (PHP), Flow (JavaScript).

**Key advocates.** Jeremy Siek and Walid Taha coined the term and developed the formal theory; Sam Tobin-Hochstadt and Matthias Felleisen designed Typed Racket; Anders Hejlsberg led TypeScript at Microsoft. Siek's "What is Gradual Typing" is the clearest short introduction: "Gradual typing allows parts of a program to be dynamically typed and other parts to be statically typed" and the programmer controls the division by adding or omitting annotations ([Siek, "What is Gradual Typing"](https://jsiek.github.io/home/WhatIsGradualTyping.html)). The formal paper "Gradual Typing for Functional Languages" gives the technical foundation: an unknown type `?` is compatible with any other type, and implicit conversions are checked at run time when a value crosses from dynamic to typed code ([Siek & Taha, "Gradual Typing for Functional Languages"](http://scheme2006.cs.uchicago.edu/13-siek.pdf)). Typed Racket is the most rigorous ecosystem realization; Tobin-Hochstadt and Felleisen's "The Design and Implementation of Typed Scheme" documents the design in detail ([Tobin-Hochstadt & Felleisen, "The Design and Implementation of Typed Scheme"](https://www2.ccs.neu.edu/racket/pubs/typed-racket.pdf)).

**Arguments for.** Gradual typing is defended as the pragmatic answer to a real deployment problem: teams have millions of lines of untyped Python or JavaScript, and cannot rewrite them all at once. Sorbet was built at Stripe for exactly this reason. Stripe's engineering blog reports that Sorbet was designed to be "fast" (able to type-check large Ruby codebases in seconds), "usable in a large team" (able to opt in one file at a time), and "designed to be run in the editor" (giving feedback while typing) — a combination none of the pre-existing Ruby type checkers offered ([Stripe, "Sorbet: Stripe's type checker for Ruby"](https://stripe.dev/blog/sorbet-stripes-type-checker-for-ruby)). Python's PEP 484 is the corresponding argument for Python: type hints are officially *optional* and are *not enforced at runtime*, which lets the ecosystem evolve toward stronger checking without breaking existing code ([PEP 484, "Type Hints"](https://peps.python.org/pep-0484/)). TypeScript's design goals are explicit that the language is intended to "impose no runtime overhead on emitted programs" and to "avoid adding expression-level syntax," precisely so that a TypeScript file remains a comfortable superset of JavaScript ([TypeScript Design Goals](https://github.com/microsoft/TypeScript/wiki/TypeScript-Design-Goals)).

**Arguments against.** Formally sound gradual typing imposes runtime checks at every dynamic/static boundary, which produces significant slowdowns in mixed programs — the "gradual guarantee" is not free. As a result, most industrial gradual type systems (TypeScript, mypy, Flow) are *unsound* by design: they do not insert runtime checks, so a value crossing from `any` into a typed context can lie, and a downstream type error can appear at runtime despite the program type-checking. Critics argue this offers "the illusion of safety" without the substance. Hickey's "Maybe Not" makes the additional point that most gradual type systems encode optionality in ways that make schema evolution harder, not easier ([Hickey, "Maybe Not"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/MaybeNot.md)).

**The tradeoff accepted.** *Migration path from dynamic to static at the cost of soundness compromises or runtime check overhead.*

## B4 — Static structural typing

**Core belief.** Two types are compatible if they have the same *shape* — the same set of fields, methods, or components — regardless of whether they share a name or a declaration. A value that "looks like" a `Duck` is a `Duck`.

**Exemplar languages.** Go (interfaces), TypeScript (its type system is fundamentally structural), OCaml (with row polymorphism for objects and polymorphic variants).

**Key advocates.** Go's designers (Rob Pike, Russ Cox, Robert Griesemer, Ken Thompson), OCaml's designers (Xavier Leroy, Didier Rémy for row polymorphism). The OCaml documentation makes the case explicitly: row polymorphism lets an operation apply to any object with the required methods, without demanding that a nominal interface be declared in advance ([Real World OCaml, "Objects" chapter](https://dev.realworldocaml.org/objects.html)).

**Arguments for.** Structural typing decouples type-compatibility from *coordination*: a downstream package can consume any type that structurally satisfies its interface, without the upstream package needing to declare an implementation. Rob Pike's account of Go argues that Go's implicit-satisfaction interfaces solved exactly this problem for large codebases: "duck typing at compile time," where a package can define what it needs and any type that happens to satisfy it works ([Pike, "Go at Google"](https://go.dev/talks/2012/splash.article)).

**Arguments against.** Structural compatibility can be *accidental*: two types that happen to have the same shape but represent different things (a `Distance` in meters and an `Angle` in degrees, both `float64`) become interchangeable when they should not be. Nominal typing (the next camp) exists precisely to prevent this.

**The tradeoff accepted.** *Decoupling of interface consumer from interface producer at the cost of losing safety against accidental shape match.*

## B5 — Static nominal typing (Java, C#, Rust, C++)

**Core belief.** A type is compatible with another type only if it is *named* as such — either the same type, or explicitly declared to implement it. Names give types identity beyond their structure.

**Exemplar languages.** Java, C#, Rust, C++, Ada, Swift.

**Key advocates.** James Gosling (Java), Bjarne Stroustrup (C++), Anders Hejlsberg (C#), Graydon Hoare (Rust). Stroustrup's HOPL IV paper argues that nominal typing plus concepts (in modern C++) gives you the safety of "this type is a Distance, not accidentally-compatible-with-Angle" while templates give you the polymorphism of "any type satisfying these operations" ([Stroustrup, HOPL IV](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf)).

**Arguments for.** Nominal typing preserves semantic distinctions the programmer intended. It also makes error messages easier to write and easier to read — the compiler can say "expected `UserId`, got `PostId`" rather than "expected `int64`, got `int64`." Rust's newtype pattern (`struct Meters(f64)`) is a common idiom used specifically to get nominal safety.

**Arguments against.** Nominal typing produces *coordination overhead*: to implement an interface, a type must declare it in advance, which means library authors and library users must know about each other. Go's designers rejected this explicitly ([Pike, "Go at Google"](https://go.dev/talks/2012/splash.article)).

**The tradeoff accepted.** *Semantic type distinctness at the cost of requiring pre-arranged type relationships.*

## B6 — Hindley-Milner and its descendants (ML, OCaml, Haskell, Elm)

**Core belief.** A polymorphic type system can be *inferred* — the compiler can figure out the most general type of every expression without annotations, and the programmer only needs to write types when they want to constrain them or when the program is ambiguous. HM is the crown jewel of type inference.

**Exemplar languages.** Standard ML, OCaml, Haskell, Elm, F#, Miranda, Reason.

**Key advocates.** Robin Milner (the M in HM), Simon Peyton Jones, Xavier Leroy. Milner's *Definition of Standard ML* is the reference ([Milner et al., "The Definition of Standard ML"](https://smlfamily.github.io/sml90-defn.pdf)). Peyton Jones's Haskell history documents how HM-style inference expanded to support type classes (Wadler and Blott's contribution) and, later, to support GADTs and type families ([Peyton Jones et al., "A History of Haskell: Being Lazy with Class"](https://simon.peytonjones.org/assets/pdfs/haskell-being-lazy-with-class.pdf)).

**Arguments for.** HM inference makes typed programming feel almost as light as untyped programming: the programmer writes ordinary code and the compiler works out the types. Peyton Jones's Haskell history notes that this was decisive in Haskell's early adoption — programs could be written with almost no type annotations while still enjoying the full protection of a rich type system ([Peyton Jones et al., "A History of Haskell"](https://simon.peytonjones.org/assets/pdfs/haskell-being-lazy-with-class.pdf)).

**Arguments against.** HM has known limitations: it does not handle first-class polymorphism, subtyping, or dependent types well. Extensions (System F, higher-rank types, GADTs) restore expressiveness but sacrifice the "always infers" guarantee — some programs no longer type-check without annotations. In practice most Haskell programs have annotations at top-level declarations for documentation, so the "no annotations" argument is more theoretical than practical.

**The tradeoff accepted.** *Very light annotation burden at the cost of a fixed algorithm that cannot infer all typings people want.*

## B7 — Dependent types (Agda, Idris, Coq/Rocq, Lean, F*, ATS)

**Core belief.** Types can depend on *values*. A vector of length 5 is a genuinely different type from a vector of length 6. Propositions become types; proofs become programs. "Types and programs" merge into a single formalism.

**Exemplar languages.** Agda, Idris, Coq (now Rocq), Lean, F*, ATS.

**Key advocates.** Per Martin-Löf (type theory), Thierry Coquand and Gérard Huet (Coq), Edwin Brady (Idris), Leonardo de Moura (Lean). Brady's paper "IDRIS — Systems Programming Meets Full Dependent Types" is the clearest argument for dependent types in a general-purpose language: he shows that Idris programs can encode invariants like "this list has length n," "this network packet is well-formed," and "this expression is type-safe" and can then have the compiler check those invariants directly ([Brady, "Idris — Systems Programming Meets Full Dependent Types"](https://www.type-driven.org.uk/edwinb/papers/plpv11.pdf)). Lean 4 is the modern high-performance realization: de Moura and Ullrich's "The Lean 4 Theorem Prover and Programming Language" describes Lean 4 as a language that is simultaneously a general-purpose functional language, an efficient compiler, and an interactive proof assistant ([de Moura & Ullrich, "The Lean 4 Theorem Prover and Programming Language"](https://lean-lang.org/papers/lean4.pdf)).

**Arguments for.** Dependent types allow *specifications to be enforced by the type system* rather than merely tested. Verification is no longer separate from programming; a proof is a program, and a program is a proof. Formalized mathematics (mathlib in Lean, the Coq proof of the Four Color Theorem, the CompCert verified C compiler) has demonstrated that this is now practical for real-scale artifacts.

**Arguments against.** Dependent types are hard. Writing a proof of a nontrivial invariant is often much harder than writing the program itself. Even research-grade dependently typed languages have small user bases, and industrial adoption remains niche. The counter-critique from the impure functional camp is that "in principle you can prove anything" is a much weaker promise than "in practice most programmers can prove what they need."

**The tradeoff accepted.** *Ultimate compile-time expressiveness and provability at the cost of a steep learning curve and, often, a program that is dominated by proof scaffolding rather than the algorithm itself.*

## B8 — Refinement types (Liquid Haskell, F*)

**Core belief.** Extend an ordinary type system with *predicates*: a "positive integer" is `{x:Int | x > 0}`; a "sorted list" is `{xs:[Int] | isSorted xs}`. The type checker uses an SMT solver to discharge the predicates automatically, so the programmer gets much of the power of dependent types without writing proofs by hand.

**Exemplar languages.** Liquid Haskell, F*, LiquidRust, Dafny, Stainless (Scala).

**Key advocates.** Ranjit Jhala and Niki Vazou (Liquid Haskell), Nikhil Swamy et al. (F*). Vazou's paper "LiquidHaskell: Experience with Refinement Types in the Real World" reports on using Liquid Haskell to verify real Haskell libraries — bytestring, containers, text — and argues that refinement types are the pragmatic middle ground: they can express and check useful invariants (e.g. array indexing safety, termination) with almost no proof burden, because the SMT solver does the work ([Vazou et al., "LiquidHaskell: Experience with Refinement Types in the Real World"](https://goto.ucsd.edu/~nvazou/real_world_liquid.pdf)).

**Arguments for.** Refinement types buy a lot of dependent-type power for relatively little programmer cost. When the SMT solver can prove the predicate automatically, the programmer just writes the type annotation and moves on. This has been used at scale for verifying cryptographic code (F* and its extraction to C, used in Firefox and the Windows kernel).

**Arguments against.** When the SMT solver cannot prove the predicate, the error messages are opaque and the workarounds — restructuring the code to help the solver — can be as painful as writing a Coq proof. Additionally, the class of properties expressible in decidable logics is smaller than the class expressible in dependent type theory.

**The tradeoff accepted.** *Automated verification of a large useful class of properties at the cost of unpredictable failure when the solver cannot prove what the programmer knows.*

## B9 — Linear / affine types (Clean, Linear Haskell, Rust's borrow system, Austral, Granule)

**Core belief.** Some values must be used *exactly once* (linear) or *at most once* (affine). Linearity in the type system lets the compiler track ownership and resource use at compile time, eliminating whole classes of bugs (double-free, use-after-close, forgotten cleanup).

**Exemplar languages.** Clean, Linear Haskell, Austral, Granule, Rust (informally — its borrow system is affine-flavored), ATS.

**Key advocates.** Philip Wadler (linear types in programming languages), Rustan Leino (Dafny), Bernardy et al. (Linear Haskell), Fernando Borretti (Austral). Wadler's page "Linear Logic" collects the foundational material — his own 1990 paper "Linear types can change the world!" was one of the first to bring Girard's linear logic into practical language design ([Wadler, "Linear Logic" resource page](https://homepages.inf.ed.ac.uk/wadler/topics/linear-logic.html)). Bernardy, Boespflug, Newton, Peyton Jones, and Spiwack's "Linear Haskell: Practical Linearity in a Higher-Order Polymorphic Language" documents how linearity was added to Haskell as a *linearity in the arrow*, so ordinary Haskell code was not disrupted ([Bernardy et al., "Linear Haskell"](https://arxiv.org/pdf/1710.09756)).

**Arguments for.** Linear types make resource discipline *checkable*. Austral's specification argues that linear types are the "load-bearing wall" of a safe systems language: with linearity, you get memory safety without a garbage collector and effect discipline without an effect system, because effectful resources (file handles, sockets, allocations) are just linear values ([Austral Language Specification](https://austral-lang.org/spec/spec.html)). Linear Haskell's paper argues that linearity as a property of *function types* — rather than of value types — is more retrofit-friendly: existing code continues to work, and linear functions live alongside ordinary functions ([Bernardy et al.](https://arxiv.org/pdf/1710.09756)).

**Arguments against.** Linear types add a genuinely new dimension to the type system that the programmer must reason about. Refactoring code across linear boundaries requires threading resources explicitly. Rust's borrow checker is the most successful deployment of an affine-like system in an industrial language, and even there the "fighting with the borrow checker" phase is a well-known learning-curve obstacle.

**The tradeoff accepted.** *Precise, compile-time resource discipline at the cost of expressiveness of ordinary aliasing patterns.*

## B10 — Session types (research, some Rust libraries)

**Core belief.** A *protocol* — the sequence of messages that must be exchanged between two parties — should be encoded as a type. The compiler then checks that the code actually follows the protocol, ruling out entire classes of concurrency bugs (deadlocks, unexpected messages, protocol drift).

**Exemplar languages.** Not a mainstream language, but session types appear as libraries in Rust, OCaml, Scala, Haskell. Multi-party session types are an active research area.

**Key advocates.** Kohei Honda, Vasco Vasconcelos, Nobuko Yoshida. Vasconcelos's tutorial "Fundamentals of Session Types" is a clear introduction: a session type describes "the protocol governing the interaction between two processes," and the type system checks that participants adhere to that protocol ([Vasconcelos, "Fundamentals of Session Types"](https://filipendule.github.io/mgs/vasconcelos.pdf)).

**Arguments for.** For distributed and concurrent systems, session types provide guarantees that no other type discipline provides: freedom from deadlock, freedom from protocol violations, and *duality* — the client and server can be independently type-checked and their types combined to ensure they will interoperate correctly. This is more than actor-model isolation; it is *protocol correctness by construction*.

**Arguments against.** Session types have not achieved mainstream adoption. Encoding real protocols (HTTP, TLS, database wire protocols) in session types is complex, and the resulting types are hard to read. Ongoing research is addressing these limitations, but the ergonomic cost has kept session types in the "actively promising" category rather than the "widely deployed" one.

**The tradeoff accepted.** *Protocol correctness at the cost of protocols becoming a first-class part of the type system.*

## B11 — Effect types (Koka, Eff, Frank, OCaml 5, Unison abilities)

**Core belief.** Every function has, in addition to its input and output types, a set of *effects* it may perform (I/O, exceptions, state, non-determinism). The type system tracks effects; effect handlers let the caller decide what any given effect actually does. This generalizes monadic I/O in Haskell.

**Exemplar languages.** Koka, Eff, Frank, OCaml 5 (algebraic effects), Unison (abilities), F* (partially).

**Key advocates.** Daan Leijen (Koka), Andrej Bauer and Matija Pretnar (Eff), Sam Lindley and Conor McBride (Frank), Rúnar Bjarnason and Paul Chiusano (Unison abilities). Leijen's "Koka: Programming with Row-polymorphic Effect Types" is the paper that put effect types on the modern language-design map: it argues that effect types combine the compositional advantages of monads with the syntactic simplicity of direct-style code, using row polymorphism to make effect sets composable ([Leijen, "Koka: Programming with Row-polymorphic Effect Types"](https://arxiv.org/pdf/1406.2061); [Koka book](https://koka-lang.github.io/koka/doc/book.html)).

**Arguments for.** Effect types let a language be *pure by default* (all effects are tracked) while retaining direct-style syntax. Effect handlers generalize try/catch, coroutines, generators, cooperative concurrency, and dependency injection into a single mechanism. Unison's "abilities" apply the same idea to distributed programming: a computation with a `Distributed` ability can be moved across machines by an appropriate handler ([Unison, "Introduction to Abilities"](https://www.unison-lang.org/docs/fundamentals/abilities/)).

**Arguments against.** Effect systems add a third dimension to the type system (value type, effect set, and, if generic, effect polymorphism), and effect polymorphism is where things get complicated fast. Type errors involving effects can be extremely opaque. The mainstream is watching Koka and OCaml 5's effect handlers to see whether the ergonomics scale, but as of now the technology is younger than the debate it seeks to settle.

**The tradeoff accepted.** *Pure-by-default composability at the cost of a more complex type system with additional inference and error-message challenges.*

## B12 — Typestate (Plaid, Rust patterns, Strom-Yemini formalism)

**Core belief.** An object's *state* (open vs. closed, initialized vs. uninitialized, connected vs. disconnected) can be part of its type. The type system enforces that only state-appropriate operations are called. The original formalism comes from Strom and Yemini's 1986 IEEE TSE paper "Typestate: A Programming Language Concept for Enhancing Software Reliability" ([Strom & Yemini, "Typestate" — cited via Semantic Scholar](https://www.semanticscholar.org/paper/Typestate:-A-programming-language-concept-for-Strom-Yemini/c060b1d8618d8ed2558771dd8b072e0d02e42b5a)).

**Exemplar languages.** Plaid (research), Rust (via typestate patterns, especially the builder pattern and session-type-like libraries).

**Arguments for.** Typestate catches an important category of bugs — using an object in a state it does not support — at compile time. In Rust, the pattern is used to enforce that (for example) an HTTP response builder must have its status code set before it can be sent.

**Arguments against.** As a first-class language feature it has been hard to popularize. As a pattern in existing type systems, it is available only in verbose form.

**The tradeoff accepted.** *State-dependent safety at the cost of encoding complexity.*

## B13 — Ownership and borrowing (Rust, Cyclone, Vale, Hylo)

**Core belief.** Every value has exactly one *owner*, and the type system tracks *borrows* — temporary, restricted references — such that no data race and no dangling reference is possible. Ownership generalizes RAII (Camp C2) into a full compile-time discipline.

**Exemplar languages.** Rust, Cyclone (Rust's ancestor), Vale, Hylo (formerly Val).

**Key advocates.** Graydon Hoare, Niko Matsakis, Aaron Turon (Rust); Trevor Jim, Greg Morrisett, Dan Grossman (Cyclone). The Cyclone paper on regions is the founding technical work: it introduced region-based memory management combined with compile-time safety, and Rust's ownership system directly descends from this line ([Grossman, Morrisett, Jim et al., "Region-Based Memory Management in Cyclone"](https://www.cs.cornell.edu/Projects/cyclone/papers/cyclone-regions.pdf)). Aaron Turon's blog post "Abstraction without overhead: traits in Rust" is a modern statement of what the design bought: Rust uses ownership plus trait-based polymorphism to give "zero-cost abstractions" — abstractions that impose no runtime cost beyond the equivalent hand-written low-level code ([Turon, "Abstraction without overhead: traits in Rust"](https://blog.rust-lang.org/2015/05/11/traits/)).

**Arguments for.** Rust's ownership system provides memory safety and data-race freedom without a garbage collector, without runtime reference counting for most values, and without whole-program dynamic checks. Verdagon's comparative analysis for Vale summarizes the pattern: Rust's model gives "the fastest possible" memory safety at compile time, but at the cost of programmer effort in expressing ownership relationships ([Verdagon, "Vale's Memory Safety Strategy: Generational References and Regions"](https://verdagon.dev/blog/generational-references)).

**Arguments against.** Ownership discipline rules out patterns that are natural in other languages: back-references in graphs, cyclic data structures, interior mutability. Rust responds with `Rc`, `Arc`, `RefCell`, and `unsafe`, each of which reintroduces some cost or unsafety. Learning curves are steep: the "fight with the borrow checker" is a documented phenomenon. Vale's designers argue that generational references — a hybrid approach — offer most of the safety of ownership with fewer of the ergonomic costs ([Verdagon, "Generational References"](https://verdagon.dev/blog/generational-references)).

**The tradeoff accepted.** *Compile-time memory safety and data-race freedom at the cost of aliasing patterns that require careful redesign.*

## B14 — Capability types (Pony, Wyvern, Austral, E)

**Core belief.** A reference's type includes what the holder is *permitted* to do with the referenced object. A read-only capability cannot mutate; an isolated capability cannot alias; capabilities can be passed but not forged. This provides both concurrency safety and security safety.

**Exemplar languages.** Pony (reference capabilities), Wyvern, Austral (capability-based security), E, Monte.

**Key advocates.** Sylvan Clebsch (Pony), Fernando Borretti (Austral), Mark S. Miller (E, object-capability security). Clebsch et al.'s "Deny capabilities for safe, fast actors" gives the technical foundation for Pony: Pony's six reference capabilities (`iso`, `trn`, `ref`, `val`, `box`, `tag`) let the compiler prove that no two actors can share aliasing mutable references, and hence that data races are impossible by construction ([Clebsch et al., "Deny capabilities for safe, fast actors"](https://www.ponylang.io/media/papers/codesigning.pdf)). Austral's specification presents capabilities as the security primitive: a piece of code cannot perform an effect (open a file, make a network call) unless it holds the corresponding capability, which must have been passed in explicitly ([Austral Specification, "Capability-Based Security"](https://austral-lang.org/tutorial/capability-based-security)).

**Arguments for.** Capabilities express *authority* directly in the type system. Miller's object-capability model shows that a well-designed capability language can eliminate ambient authority — the "principle of least authority" is enforced by construction, not by convention. For concurrency, Pony's design shows that capabilities give data-race freedom without ownership's aliasing restrictions, because the guarantees are about what operations are permitted, not about who holds the reference.

**Arguments against.** Capability types are a new discipline that most programmers have not learned. Pony's six capabilities take time to internalize; Austral's linear-capability combination is doubly novel. The industrial track record is limited compared to ownership-borrowing (Rust) or garbage collection (Java, Go, C#).

**The tradeoff accepted.** *Compile-time authority and race-freedom at the cost of a novel type discipline that must be learned.*

## The static-vs-dynamic wars: Harper, Hickey, and what the argument is really about

The oldest fight in programming language design is between static and dynamic typing. It has never been resolved because it is not one question but several:

1. **Should types be checked at compile time or run time?**
2. **Should the *shape* of data be given a name and stated in advance?**
3. **Should the programmer be able to iterate quickly on a partially-typed program?**
4. **Does typing pay for itself on programs beyond a certain size?**

Different combatants answer different sub-questions and then talk past each other. Robert Harper's "Dynamic Languages are Static Languages" is a strategic move that collapses the debate onto question 2: he argues that every dynamic language *has* a type system, just a degenerate one (the *unitype*), and that the real question is whether you want the ability to *state and enforce distinctions* the programmer knows to be true ([Harper, "Dynamic Languages are Static Languages"](https://existentialtype.wordpress.com/2011/03/19/dynamic-languages-are-static-languages/)). Harper's polemical claim: "Dynamic typing is but a special case of static typing" that "limits, rather than liberates."

Rich Hickey's counter, developed across "Simple Made Easy," "Effective Programs," and "Maybe Not," is that static type systems as usually implemented *complect* multiple concerns: they conflate presence-of-value with structure-of-value, they conflate optionality-in-arguments with optionality-in-return-position, and they force the programmer to name shapes at points where names are premature commitments ([Hickey, "Simple Made Easy"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/SimpleMadeEasy-mostly-text.md); [Hickey, "Effective Programs"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/EffectivePrograms.md); [Hickey, "Maybe Not"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/MaybeNot.md)). Hickey does not deny that static types can catch bugs; he argues that the type systems most programmers actually use (nominal, closed-world, Maybe-oriented) do a bad job of the thing they claim to do, and that Clojure's Spec (a runtime shape system) captures the useful discipline without the coordination costs.

Daniel Holden's "In Defence of the Unitype" gives one of the fairest summaries of both positions: Harper is *correct* that dynamic languages have one type; the disagreement is over whether that is a defect (Harper) or a feature (Holden). Holden's affirmative case is that a *unityped* language has a smaller mental model — a programmer needs to reason only about computation, not about computation *and* types — and this simplicity is genuinely valuable for exploratory and short-lived programs ([Holden, "In Defence of the Unitype"](https://theorangeduck.com/page/defence-unitype)).

The empirical evidence is mixed. Gradual typing systems (TypeScript, mypy, Sorbet) exist because in practice large teams *do* eventually want static checking on formerly-dynamic codebases. But the fact that those systems are almost universally unsound suggests that programmers value the *IDE tooling and documentation* benefits of static types more than they value soundness.

## The maintenance vs. exploration tradeoff

A useful way to reframe the static-dynamic debate is not as a question about correctness but about *lifecycle*. Programs that are being *explored* — where the programmer is figuring out what the program should do — benefit from dynamic typing because the programmer does not want to name things that they may throw away in ten minutes. Programs that are being *maintained* — where many people will need to change the program long after its author has moved on — benefit from static typing because the types serve as machine-checked documentation that the compiler enforces every time someone edits the code.

Hickey acknowledges this in "Hammock Driven Development": his argument for dynamic typing is specifically an argument for a certain *style* of program construction — thinking hard, then writing small, then combining — that does not need the crutch of a type system because it does not have the corresponding class of coordination problems ([Hickey, "Hammock Driven Development"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/HammockDrivenDev.md)). The Sorbet team's account of Stripe's motivation for static typing is the counterexample: at Stripe scale, no one person has the whole program in their head, and the type system is what lets people change code they did not write ([Stripe, "Sorbet"](https://stripe.dev/blog/sorbet-stripes-type-checker-for-ruby)).

The tradeoff, then, is real and it depends on the program's stage of life. Language designers who want to serve both stages tend to converge on gradual typing (Camp B3).

### Summary tradeoff table — type systems

| Camp | Static safety | Annotation burden | Refactoring safety | Exploration speed | Learning curve |
|---|---|---|---|---|---|
| B1 Untyped | None | None | Low | Very high | Very low |
| B2 Dynamic | Runtime only | None | Low | Very high | Low |
| B3 Gradual | Partial | Optional | Medium | High | Medium |
| B4 Structural | High | Medium | Medium-high | Medium | Medium |
| B5 Nominal | High | Medium-high | High | Medium | Medium |
| B6 HM | High | Very low (inferred) | High | Medium | Medium-high |
| B7 Dependent | Very high | Very high | Very high | Low | Very high |
| B8 Refinement | High (SMT-decidable) | Medium | High | Medium | High |
| B9 Linear/affine | Very high (resources) | High | Very high | Medium-low | High |
| B10 Session | Very high (protocols) | Very high | Very high | Low | Very high |
| B11 Effect | High (effects) | Medium | High | Medium | High |
| B12 Typestate | High (state) | Medium-high | High | Medium | Medium-high |
| B13 Ownership | Very high (memory) | Medium-high | Very high | Medium-low | High |
| B14 Capability | Very high (authority) | Medium-high | Very high | Medium | High |

---

# Camp C — Memory management

Memory management is the design decision most visibly correlated with a language's *deployment envelope*: whether it can run on a microcontroller, whether it can meet real-time deadlines, whether it can be a system's fastest path or its ergonomic default. Every camp trades some combination of throughput, latency, predictability, and programmer burden.

## C1 — Manual (C, C++, Zig)

**Core belief.** The programmer allocates memory explicitly with `malloc` (or equivalents) and frees it explicitly with `free`. Nothing happens automatically. This puts the programmer in full control of when memory is acquired and released, and therefore in full control of memory-related performance.

**Exemplar languages.** C, C++ (in its manual mode), Zig.

**Arguments for.** Manual memory management gives *the shortest and most predictable* path from program to hardware. A well-written C program can achieve exact bounds on latency and memory usage that no garbage-collected language can match. Andrew Kelley's Zig writeup is explicit: Zig has no hidden allocations, and every allocation is done through an explicit *allocator* passed as a parameter, so the caller controls the allocation strategy per subsystem ([Kelley, "Introduction to Zig"](https://andrewkelley.me/post/intro-to-zig.html)). This makes Zig usable in embedded contexts where a tracing garbage collector would be impossible.

**Arguments against.** Manual memory management is the source of the majority of security vulnerabilities in production software. Microsoft and Google have both reported that ~70% of their security bugs are memory-safety bugs in C/C++ code. This is the primary motivation for Rust and for the "manual but safe" languages like Vale that try to keep the performance profile of manual allocation while adding compile-time guarantees.

**The tradeoff accepted.** *Direct control at the cost of programmer-provided invariants and a large class of memory-safety bugs.*

## C2 — RAII (C++, Rust)

**Core belief.** Resource acquisition is initialization: a resource (memory, file, lock) is acquired by constructing an object, and released *automatically* when that object goes out of scope. The stack becomes the ownership graph.

**Exemplar languages.** C++, Rust, D, Swift (partially).

**Key advocates.** Bjarne Stroustrup (RAII in C++), the Rust team. Stroustrup's HOPL IV history describes RAII as one of C++'s most important contributions: it makes cleanup *deterministic* — you know exactly when a destructor runs — and it lets programmers structure resource lifetime around the language's block structure without needing a garbage collector ([Stroustrup, HOPL IV](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf)).

**Arguments for.** RAII combines the predictability of manual management with the safety of automatic cleanup: you cannot forget to release a resource because the compiler inserts the release automatically at scope exit. This is the mechanism that makes C++'s `std::unique_ptr` and Rust's `Box`, `Vec`, and `File` memory-safe.

**Arguments against.** RAII only works cleanly for resources whose lifetime nests with scope. Resources with more complex lifetime patterns — objects held by multiple owners, resources whose lifetime crosses async boundaries — require additional mechanisms (shared_ptr, Rc, Arc, or lifetime annotations).

**The tradeoff accepted.** *Deterministic cleanup at the cost of restricting resource lifetimes to (roughly) lexical scope.*

## C3 — Reference counting (Objective-C ARC, Swift, CPython, Perl, PHP)

**Core belief.** Each object carries a count of references to it; when the count reaches zero, the object is deallocated. Deallocation is deterministic (it happens immediately when the last reference goes away) but requires ongoing bookkeeping.

**Exemplar languages.** Objective-C (with ARC), Swift, CPython, Perl, PHP, Nim (with ARC/ORC).

**Key advocates.** Apple's Swift and Objective-C teams. Objective-C's Automatic Reference Counting was introduced in Xcode 4.2 (2011) and made reference-counting bookkeeping automatic — the compiler inserts retain and release calls where the programmer would previously have written them by hand ([Wikipedia, "Automatic Reference Counting"](https://en.wikipedia.org/wiki/Automatic_Reference_Counting)).

**Arguments for.** Reference counting gives *deterministic* deallocation — resources are freed as soon as they become unreachable, so no GC pause is possible. It also has *smoother* memory-usage graphs than tracing GC because deallocation is spread throughout the program rather than concentrated in GC pauses. This is why Apple chose ARC for iOS: on a mobile device with tight memory constraints and interactive latency requirements, tracing GC's pauses were unacceptable.

**Arguments against.** Reference counting cannot collect *cycles* without additional machinery. Every RC-based language has to add either (a) a *cycle collector* that periodically runs a mark-sweep pass on suspected cycles, (b) a *weak-reference* mechanism that lets the programmer break cycles by hand, or both. Bacon, Cheng, and Rajan's "A Unified Theory of Garbage Collection" makes the argument that "tracing collectors and reference-counting collectors are duals of each other" and that both must ultimately do the same total work; they are different tradeoffs in *when* the work happens ([Bacon, Cheng, Rajan, "A Unified Theory of Garbage Collection"](https://web.eecs.umich.edu/~weimerw/2012-4610/reading/bacon-garbage.pdf)). Nim's ARC/ORC design explicitly combines ARC for the fast path with a cycle collector (ORC) for cases where cycles may exist ([Nim, "Introduction to ARC/ORC"](https://nim-lang.org/blog/2020/10/15/introduction-to-arc-orc-in-nim.html)).

Reference-count updates also have *concurrency cost*: incrementing a shared counter requires atomic operations, which are more expensive than regular loads. In multi-threaded programs, this can dominate.

**The tradeoff accepted.** *Deterministic deallocation and smooth memory usage at the cost of cycle handling complexity and atomic increment overhead.*

## C4 — Tracing garbage collection (Java, Go, Haskell, C#, JavaScript)

**Core belief.** The runtime periodically discovers which objects are still reachable from a set of roots and reclaims the rest. The programmer never allocates or frees explicitly; the runtime handles both.

**Exemplar languages.** Java, C#, Go, Haskell, OCaml (major heap), JavaScript, most Lisp descendants.

**Key advocates.** The JVM garbage collector teams (Oracle, IBM, Red Hat), Rick Hudson (Go GC), the OCaml team. Oracle's Java documentation describes G1 in terms that make the tradeoff explicit: G1 is "generational, incremental, parallel, mostly concurrent, stop-the-world, and evacuating," and it "attempts to meet garbage collection pause-time goals with high probability while achieving high throughput" ([Oracle, "Garbage-First (G1) Garbage Collector"](https://docs.oracle.com/en/java/javase/25/gctuning/garbage-first-g1-garbage-collector1.html)). The Twitch engineering blog documents Go's shift from stop-the-world GC to concurrent-mark GC and the pause-time reductions this delivered — from tens of milliseconds to under a millisecond for typical services ([Twitch, "Go's march to low-latency GC"](https://blog.twitch.tv/en/2016/07/05/gos-march-to-low-latency-gc-a6fa96f06eb7/)).

**Arguments for.** Tracing GC handles cycles trivially (unreachable is unreachable, cycles included), removes an entire class of memory bugs from the programmer's concern, and — with modern implementations — can achieve very low pause times. Bacon, Cheng, and Rajan's "unified theory" paper argues that in the limit, tracing and reference-counting do the same total work; a well-tuned tracing GC can be *higher throughput* than reference counting because it batches deallocation and can use fast bump allocation ([Bacon et al., "A Unified Theory of Garbage Collection"](https://web.eecs.umich.edu/~weimerw/2012-4610/reading/bacon-garbage.pdf)).

**Arguments against.** Tracing GC introduces *pauses* — moments when the program stops (or slows down) while the collector runs. Even Go's sub-millisecond pauses are unacceptable in hard real-time contexts, and they perturb tail latencies in soft real-time systems (game rendering, high-frequency trading, interactive audio). Additionally, tracing GC typically requires 2–3× the memory of manually managed code to achieve good performance — because bump allocation and copying collection trade memory for CPU. This is why Zig, Rust, and modern C++ position themselves as GC-free alternatives.

**The tradeoff accepted.** *Ergonomic freedom from memory bookkeeping at the cost of pauses, higher memory footprint, and less predictable latency.*

## C5 — Region-based memory management (Cyclone, MLKit, Vale)

**Core belief.** Group allocations by *region* — all objects allocated within a scope are freed together when the scope ends. This gives faster deallocation than either RC or tracing GC (no per-object bookkeeping) while retaining safety.

**Exemplar languages.** Cyclone, MLKit (region-inferring SML), Vale (partially), Rust (arenas via crates).

**Key advocates.** Mads Tofte and Jean-Pierre Talpin (region inference for ML), Trevor Jim et al. (Cyclone), Martin Elsman (MLKit). The Cyclone regions paper is the definitive treatment: it introduces lexically-scoped, dynamically-scoped, and unique-pointer regions, and shows how region types combined with existentials give a compile-time-safe alternative to garbage collection for a large class of C-style code ([Grossman et al., "Region-Based Memory Management in Cyclone"](https://www.cs.cornell.edu/Projects/cyclone/papers/cyclone-regions.pdf)). MLKit's documentation shows the same idea used by inference: the compiler figures out region assignments without programmer annotation ([Elsman, "Programming with Regions in the MLKit"](https://elsman.com/pdf/mlkit-4.6.0.pdf)).

**Arguments for.** For allocation-heavy but short-lived data (per-request state in a web server, per-frame allocation in a game), regions are much cheaper than either RC or tracing GC: the deallocation cost is *constant* per region regardless of the number of objects in it. This is why arena allocation is popular in game development and in Rust systems programming as a manual pattern.

**Arguments against.** Region inference is fragile: a small program change can cause an object to live longer than the compiler infers, leading to memory leaks or unnecessary lifetime extension. When done manually, regions require the programmer to think about lifetime again — reintroducing much of the burden that GC was meant to eliminate.

**The tradeoff accepted.** *Fast bulk deallocation at the cost of lifetime discipline that must be programmer-visible.*

## C6 — Ownership + borrowing (Rust, Vale)

Covered in detail above (Camp B13). The memory-management payoff is that ownership makes it possible to guarantee memory safety at compile time with performance essentially equivalent to manual management — Rust programs typically use no more memory and no more CPU than equivalent C programs, and often less because the compiler can prove aliasing constraints the C compiler cannot ([Turon, "Abstraction without overhead"](https://blog.rust-lang.org/2015/05/11/traits/); [Verdagon on Vale](https://verdagon.dev/blog/generational-references)).

## C7 — Linear types for memory (Clean, Austral, Granule)

Covered above (Camp B9). Linearity makes memory a linear resource: you either use it or you dispose of it, and the compiler will not let you do both or neither. Austral's spec is explicit that this is a way to get memory safety without a garbage collector or a borrow checker per se ([Austral Specification](https://austral-lang.org/spec/spec.html)).

## C8 — Hybrid approaches (Nim ARC/ORC, Swift ownership, D, Roc platforms)

**Core belief.** No single memory model fits all code. Combine a fast common-case model (RC, RAII, or arenas) with a fallback for the cases that need it (cycle collection, tracing GC, or explicit unsafe pointers).

**Exemplar languages.** Nim (ARC + ORC for cycles), Swift (RC + ownership + macros), D (GC + manual + refcount), Roc (functional core + platform-provided allocators).

**Key advocates.** Andreas Rumpf (Nim), Chris Lattner and the Swift team, Walter Bright (D), Richard Feldman (Roc). Nim's design is a clean example: ARC for the common case, ORC (a cycle collector) for types marked as possibly cyclic ([Nim, "Introduction to ARC/ORC"](https://nim-lang.org/blog/2020/10/15/introduction-to-arc-orc-in-nim.html)). Roc takes a novel position: the language itself is purely functional and has no allocation model, and the *platform* embedding Roc provides the allocator. This lets the same Roc code run under an arena allocator (for a compiler pass), a general allocator (for a CLI), or a per-request allocator (for a web server), without the code changing ([Roc, "Fast"](https://www.roc-lang.org/fast)).

**Arguments for.** Hybrids are pragmatic: they let the ergonomic path be the fast path, and let the programmer opt in to more expensive machinery only where needed.

**Arguments against.** Hybrids add complexity to the language specification and to the mental model. A programmer needs to know when to reach for which mechanism, and the interactions between mechanisms can be subtle.

**The tradeoff accepted.** *Pragmatic performance across use cases at the cost of a more complicated memory model.*

## C9 — No allocation (MISRA-C, Ravenscar, hard real-time)

**Core belief.** In safety-critical, real-time, or extremely resource-constrained contexts, dynamic allocation is *banned entirely*. All memory is either statically allocated at program load or allocated from fixed-size pools whose exhaustion is a design-time concern.

**Exemplar languages.** MISRA-C profile of C, Ada Ravenscar profile, some embedded C++ standards.

**Key advocates.** The MISRA consortium (automotive), the SPARK/Ada community (aerospace, avionics). MISRA C:2023 Directive 4.12 states plainly: "Dynamic memory allocation shall not be used." The rationale is that dynamic allocation can fail unpredictably, can fragment memory to the point of exhaustion, and cannot in general be bounded for real-time analysis ([MathWorks documentation of MISRA C:2023 D4.12](https://www.mathworks.com/help/bugfinder/ref/misrac2023d4.12.html)). Ada's Ravenscar profile similarly restricts the tasking and memory model to a subset amenable to worst-case execution time analysis ([Ada Rationale, "The Ravenscar profile"](https://www.adaic.org/resources/add_content/standards/05rat/html/Rat-5-4.html)).

**Arguments for.** For a flight control system or an airbag controller, the guarantee that the program cannot run out of memory at runtime is not a nice-to-have; it is the difference between certifiable and not. No-allocation profiles are what make these languages usable in these contexts.

**Arguments against.** Static allocation is *inflexible*. Programs that need to handle a variable number of items must either preallocate the maximum (wasting memory) or refuse work beyond a threshold. Neither is comfortable outside the specific niches where the discipline pays for itself.

**The tradeoff accepted.** *Absolute predictability at the cost of expressiveness and buffer flexibility.*

### Summary tradeoff table — memory management

| Camp | Throughput | Latency predictability | Programmer burden | Cycle handling | Memory footprint |
|---|---|---|---|---|---|
| C1 Manual | Very high | Very high | Very high | Programmer | Minimal |
| C2 RAII | Very high | High | Medium | Programmer for cycles | Minimal |
| C3 RC | Medium-high | High | Low | Requires cycle collector or weak refs | Low |
| C4 Tracing GC | High (batched) | Low (pauses) | Very low | Automatic | 2-3x |
| C5 Region | Very high | Very high | Medium | N/A (bulk free) | Minimal |
| C6 Ownership | Very high | Very high | High (learning curve) | Programmer with Rc/Arc | Minimal |
| C7 Linear types | Very high | Very high | High | Programmer | Minimal |
| C8 Hybrid | Depends | Depends | Medium | Depends | Depends |
| C9 No allocation | Very high | Perfect | High (design-time) | N/A | Fixed |

---

# Camp D — Concurrency and parallelism

## D1 — Threads and locks (Java, C++, C#)

**Core belief.** The programmer creates threads that share memory, and coordinates access with locks (mutexes, semaphores, condition variables). This is the model most operating systems present, and it is what "concurrency" meant in the Unix tradition.

**Exemplar languages.** Java, C++, C#, POSIX C.

**Arguments for.** Threads and locks map directly to hardware — modern CPUs really do have multiple cores sharing memory, and threading is the most efficient way to use them for tightly-coupled parallel work. Java's memory model, standardized in the JSR-133 revision, gave threads a precise semantics that made this work portably.

**Arguments against.** Threads and locks are notoriously error-prone. Race conditions are non-deterministic and can survive extensive testing before manifesting in production. Deadlocks are easy to construct and hard to debug. Composition is bad: two thread-safe libraries composed together are not automatically thread-safe. Joe Armstrong's Erlang thesis is a sustained argument that threads-and-locks are the wrong primitive for anything but the tightest inner loops: "Concurrency-Oriented Programming" replaces shared memory with isolated processes precisely because shared memory does not compose ([Armstrong thesis](https://erlang.org/download/armstrong_thesis_2003.pdf)).

**The tradeoff accepted.** *Direct hardware access at the cost of a coordination discipline that has proven inconsistent in practice.*

## D2 — CSP and channels (Go, Newsqueak, Alef, Limbo, Occam)

**Core belief.** "Do not communicate by sharing memory; share memory by communicating." Processes exchange messages via *channels* — first-class, typed, synchronizing pipes. C. A. R. Hoare's 1978 CACM paper "Communicating Sequential Processes" is the founding document: he argues that input and output should be recognized as primary concepts in a programming language, that concurrent processes should communicate only by matched send/receive on channels, and that this gives a much cleaner algebra than shared memory ([Hoare, "Communicating Sequential Processes"](https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf); [Wikipedia, "Communicating Sequential Processes"](https://en.wikipedia.org/wiki/Communicating_sequential_processes)).

**Exemplar languages.** Occam (a direct implementation for the Transputer), Newsqueak (Rob Pike's), Alef and Limbo (Plan 9 and Inferno), Go (which is Newsqueak's grandchild).

**Key advocates.** Tony Hoare (foundational), Rob Pike (Newsqueak, Go). Pike's Newsqueak paper describes the language as an experiment in first-class channels, and Go directly adopts the model — with the important addition that Go's channels are typed and that its `select` statement lets a goroutine wait on multiple channels ([Pike, "The Implementation of Newsqueak"](https://swtch.com/~rsc/thread/newsquimpl.pdf); [Wikipedia, "Newsqueak"](https://en.wikipedia.org/wiki/Newsqueak); [Pike, "Go at Google"](https://go.dev/talks/2012/splash.article)).

**Arguments for.** Channels *compose*: two components that each expose channel interfaces can be plugged together, and the composition is also a channel-based component. Synchronization is explicit and localizable — you know exactly where a goroutine blocks. Pike argues that CSP-style concurrency, more than any other single feature, made Go usable for the network servers Google was building ([Pike, "Go at Google"](https://go.dev/talks/2012/splash.article)).

**Arguments against.** CSP does not eliminate deadlock — you can still design channel topologies that deadlock — and Go's channels in particular have no static discipline preventing send-after-close or receive-after-close beyond runtime panics. Actor-model advocates argue that mailboxes are better than channels because they decouple the receiver's readiness from the sender's, avoiding the synchronous rendezvous that CSP requires.

**The tradeoff accepted.** *Compositional concurrency with explicit synchronization at the cost of continued programmer responsibility for deadlock avoidance.*

## D3 — Actors (Erlang, Elixir, Pony, Akka, Orleans)

Covered in detail above (Camp A10). The actor model contrasts with CSP on the axis of *coupling*: CSP channels enforce synchronous rendezvous (or bounded buffering); actor mailboxes are asynchronous and unbounded. Armstrong argued that this asynchrony is exactly what makes distributed systems tractable — a slow receiver should not block a sender across a network ([Armstrong thesis](https://erlang.org/download/armstrong_thesis_2003.pdf)).

## D4 — Software transactional memory (Clojure, GHC Haskell)

**Core belief.** Concurrent modifications to shared state should be handled the way databases handle concurrent transactions: optimistically, with automatic conflict detection and automatic retry. STM composes: two transactions can be combined into one atomic transaction.

**Exemplar languages.** Clojure (STM on refs), Haskell (GHC STM), Scala (via libraries).

**Key advocates.** Simon Peyton Jones and Tim Harris (Haskell STM), Rich Hickey (Clojure STM). The Haskell wiki's STM page summarizes the design and its motivation: STM eliminates the need to acquire locks in a specific order, and it provides a `retry` primitive that lets a transaction cleanly say "conditions were not right, wake me when they change" ([Haskell wiki, "Software transactional memory"](https://www.haskell.org/haskellwiki/Software_transactional_memory)).

**Arguments for.** STM makes concurrent code *composable* in a way locks do not. Two independently-verified transactions can be combined into a single atomic transaction, and the resulting behavior is what one would want. In Haskell in particular, STM's power comes from the type system: only `STM` computations can touch transactional variables, and only from within `atomically` blocks, so the compiler can enforce isolation.

**Arguments against.** STM has performance and semantic pitfalls: it does not compose with I/O (transactions cannot be retried if they have side effects), it can suffer from livelock under high contention, and its performance depends heavily on the workload's read-vs-write ratio. Clojure's STM has been criticized for having limited real-world use because Clojure programmers tend to reach for `atom` (single-item CAS) rather than `ref` (multi-item transaction) for most problems.

**The tradeoff accepted.** *Composable concurrency at the cost of I/O incompatibility and worst-case retry cost.*

## D5 — Async / await (Rust, C#, JavaScript, Python, Swift)

**Core belief.** Concurrency and parallelism are different problems. For many programs, especially servers that spend most of their time waiting for I/O, what is needed is not multiple threads but *cooperative* scheduling of many logically-concurrent tasks on a few OS threads. Async/await provides direct syntax for this.

**Exemplar languages.** Rust, C#, JavaScript, Python, Swift.

**Key advocates.** The C# team (originators of the async/await syntax in mainstream languages), Aaron Turon (Rust futures). Turon's "Zero-cost futures in Rust" articulates the design ambition: Rust's futures compile to a state machine with no per-await allocation and no runtime overhead beyond the poll loop itself, making async a zero-cost abstraction in Rust's tradition ([Turon, "Zero-cost futures in Rust"](https://aturon.github.io/blog/2016/08/11/futures/)).

**Arguments for.** Async/await lets a program handle tens of thousands of concurrent connections with a small number of OS threads — an efficiency threads cannot match. The syntactic sugar keeps sequential-looking code sequential-looking, unlike callback- or promise-chain-based alternatives.

**Arguments against.** Async colors functions: an async function can only be called from another async function, or from a runtime that awaits it. This bifurcates the language into "async code" and "sync code" — the "function coloring problem" — and complicates library design significantly. Structured concurrency (D6) is partly a response to this criticism.

**The tradeoff accepted.** *Efficient concurrent I/O at the cost of a bifurcated language and additional runtime infrastructure.*

## D6 — Structured concurrency (Trio, Swift concurrency, Kotlin coroutines)

**Core belief.** Concurrent tasks should follow the same structural discipline as sequential code: when a scope ends, all tasks started within that scope have completed. No "background" tasks that outlive their spawning context. This eliminates a whole class of "orphan task" bugs and makes error propagation predictable.

**Exemplar languages.** Trio (Python), Swift concurrency, Kotlin coroutines (with structured concurrency), Java (Project Loom's `StructuredTaskScope`).

**Key advocates.** Nathaniel J. Smith (Trio), Roman Elizarov (Kotlin), Doug Lea and the Swift concurrency team. Swift's SE-0304 proposal "Structured Concurrency" is the clearest formal design: tasks are children of the task that spawned them; a parent task cannot complete until its children have completed; errors propagate up the parent-child chain automatically ([Swift Evolution SE-0304, "Structured Concurrency"](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md)).

**Arguments for.** Structured concurrency restores the "goto considered harmful" argument to concurrency: unstructured `spawn` is to concurrency what `goto` is to sequential control. A task hierarchy makes cancellation, error handling, and resource cleanup all follow the same rules as sequential code, so programmers can reason about them the same way.

**Arguments against.** Structured concurrency rules out some genuinely useful patterns: long-lived background tasks, tasks whose lifetime must exceed their spawning scope, unstructured event loops. Escape hatches exist but reintroduce the risk that structured concurrency was meant to eliminate.

**The tradeoff accepted.** *Predictable task lifetime and error propagation at the cost of some flexibility in unstructured task topologies.*

## D7 — Data parallel (NESL, Data Parallel Haskell, Futhark)

**Core belief.** Parallelism should be *implicit in the shape of the data*: operations on arrays are parallelizable by default, and the compiler is responsible for generating efficient parallel code. NESL introduced nested data parallelism; Futhark is the modern realization for GPU targets.

**Exemplar languages.** NESL, Data Parallel Haskell, Futhark, single-instruction-multiple-data (SIMD) libraries in mainstream languages.

**Key advocates.** Guy Blelloch (NESL), Simon Peyton Jones et al. (DPH), Troels Henriksen (Futhark). The Futhark project page describes the design: Futhark is a "purely functional, statically typed, small array language" that generates efficient parallel GPU code from high-level array operations, making it possible to write GPU code that looks like Haskell and runs like CUDA ([Futhark language site](https://futhark-lang.org/)).

**Arguments for.** Data parallel languages *automatically* exploit hardware parallelism that a programmer would otherwise have to orchestrate by hand. For array-shaped workloads (scientific computing, machine learning, image processing), this is dramatic.

**Arguments against.** Data parallel languages are narrow — they excel at array-shaped problems and struggle with problems that are irregular or graph-shaped. Data parallel Haskell (a nested-data-parallel extension of GHC) was ambitious but never reached production quality.

**The tradeoff accepted.** *Free hardware parallelism at the cost of restricted problem shape.*

## D8 — Bulk synchronous parallel (BSP)

**Core belief.** A parallel computation proceeds in *supersteps*: within each superstep, processors compute independently on local data; between supersteps, they exchange messages and synchronize globally. Leslie Valiant's original paper argues that this rigidly-phased model is what makes parallel performance analyzable and portable ([Valiant on BSP — original paper is subscription-only; see Wikipedia summary and MIT lecture notes](https://en.wikipedia.org/wiki/Bulk_synchronous_parallel)).

**Arguments for.** BSP gives a clean cost model: each superstep costs the maximum local computation plus the maximum message-exchange time plus a synchronization overhead. This makes parallel algorithms analyzable.

**Arguments against.** The rigid superstep structure imposes barriers that are wasteful for irregular workloads. BSP has been influential in the design of frameworks (Google's Pregel for graph processing) but has not entered mainstream programming languages.

**The tradeoff accepted.** *Predictable parallel performance at the cost of rigid phasing.*

## D9 — Fork-join (Cilk, Java ForkJoinPool)

**Core belief.** Parallelism is created by *forking* — starting a computation that may proceed in parallel with the current one — and consumed by *joining* — waiting for a forked computation to finish. Cilk's spawn/sync primitives are the canonical realization; Java's ForkJoinPool brings the idea to the JVM.

**Exemplar languages.** Cilk, Cilk Plus (compiler extension), Java ForkJoinPool, Habanero-Java.

**Key advocates.** Charles Leiserson and the Cilk team (MIT). Cilk's contribution is a work-stealing scheduler that makes parallel programs approximately optimal in a rigorous sense: the "work" of the parallel program (its serial execution time) plus its "span" (its critical-path length) bound its parallel execution time on a P-processor machine.

**Arguments for.** Fork-join lets divide-and-conquer algorithms be expressed almost identically to their serial versions, with `spawn` replacing recursive calls that can proceed in parallel. This makes many classic algorithms (mergesort, matrix multiply) trivially parallel.

**Arguments against.** Fork-join favors *balanced* computations. Load imbalance across forked tasks reduces speedup, and the work-stealing scheduler adds overhead when the work per task is very small.

**The tradeoff accepted.** *Compositional parallelism for divide-and-conquer at the cost of overhead for fine-grained or imbalanced work.*

## D10 — Effect-based concurrency (Koka, OCaml 5 domains)

**Core belief.** Concurrency is an *effect*, expressed in the effect type and interpreted by an effect handler. Different handlers can implement the same async code as cooperative coroutines, preemptive threads, or bulk-synchronous ticks. This unifies concurrency with the rest of the effect system.

**Key advocates.** Daan Leijen (Koka), the OCaml 5 team, the Unison team. Leijen's Koka book presents effect-based concurrency as a natural consequence of the effect system: a `yield` effect is what a cooperative scheduler wants; a `spawn` effect is what a task-based scheduler wants; both are just algebraic operations to be interpreted ([Koka book](https://koka-lang.github.io/koka/doc/book.html)).

**Arguments for.** Effect-based concurrency avoids the "function coloring problem" of async/await: a function that yields is a function that has a yield effect, and the same function can be run under a synchronous handler that ignores yields or under an asynchronous handler that schedules them. There is no separate "async" world.

**Arguments against.** As with effect types in general (B11), the ergonomics are still being worked out. Effect polymorphism and effect inference can produce hard-to-read error messages, and library authors must reason about their effect signatures more carefully than in a colored-async system.

**The tradeoff accepted.** *Unified concurrency and effects at the cost of learning the effect discipline.*

### Summary tradeoff table — concurrency

| Camp | Composability | Deadlock resistance | Performance ceiling | Learning curve | Function coloring |
|---|---|---|---|---|---|
| D1 Threads+locks | Poor | Poor | High | Medium | None |
| D2 CSP/channels | Good | Medium | High | Medium | None |
| D3 Actors | Very good | Good | Medium-high | Medium | None |
| D4 STM | Very good (STM code) | Very good | Medium (contention) | Medium | STM code only |
| D5 Async/await | Poor across colors | Medium | Very high | Medium | Yes |
| D6 Structured | Very good | Very good | High | Low-medium | Depends |
| D7 Data parallel | Good | N/A | Very high (SIMD/GPU) | High | None |
| D8 BSP | Good | Very good | High | High | None |
| D9 Fork-join | Very good | Very good | High | Low-medium | None |
| D10 Effect-based | Very good | Depends on handler | High | High | None |

---

# Camp E — Syntax and readability

Syntax is where the aesthetic wars are loudest and the empirical evidence is weakest. But it matters: syntax is what programmers see all day, and the shape of the notation constrains the shape of thought — a point Iverson made in "Notation as a Tool of Thought" and one that every language designer eventually confronts ([Iverson, "Notation as a Tool of Thought"](https://www.eecg.utoronto.ca/~jzhu/csc326/readings/iverson.pdf)).

## E1 — C-family curly braces

C and its descendants (C++, Java, C#, JavaScript, Go, Rust, Swift, Kotlin) all share the same skeleton: statements terminated by semicolons, blocks delimited by `{` and `}`, function calls with parenthesized argument lists, and infix operators. This is the most widely-recognized syntax on Earth. Its principal virtue is *familiarity*: any programmer trained in the last forty years can read it, and the cost of switching between C-family languages is low. Its principal criticism is that it visually clutters short expressions with punctuation that carries no information (`;`, redundant `()`), and that block delimiters and indentation can drift out of sync, producing bugs of the "if without braces" family that led to Apple's 2014 "goto fail" vulnerability.

## E2 — ML-family expression-oriented

ML, OCaml, Haskell, Rust, and Scala are *expression-oriented*: `if`, `match`, and blocks all return values, and there are few distinct statement forms. This composes better than C-family syntax — an expression can go anywhere an expression is expected — and it interacts well with type inference (every expression has a type). The tradeoff is that programmers accustomed to C-family syntax find ML-family syntax alien at first ("What is `let ... in ...`? Where is the return statement?"). Peyton Jones's Haskell history documents the design deliberations: the Haskell committee explicitly chose expression orientation because it composed better with laziness and type inference ([Peyton Jones et al., "A History of Haskell"](https://simon.peytonjones.org/assets/pdfs/haskell-being-lazy-with-class.pdf)).

## E3 — Lisp S-expressions and homoiconicity

The Lisp tradition uses parenthesized prefix notation: `(+ 1 2)` rather than `1 + 2`. This is often defended as ugly, and often defended as the most beautiful syntax ever designed — because Lisp code and Lisp data have *the same shape*. A Lisp program can manipulate other Lisp programs as data, which is what makes Lisp macros so powerful. Paul Graham's "Beating the Averages" argues that macros — programs that write programs — were the single most important source of Viaweb's competitive advantage: he estimates 20-25% of the Viaweb editor was macros, doing things that could not have been done as easily in any other language ([Graham, "Beating the Averages"](https://paulgraham.com/avg.html)). The Racket manifesto extends the argument: because Racket is a Lisp with a serious macro system, it can *become* whatever language a given problem needs, and language-oriented programming is the natural style ([Felleisen et al., "The Racket Manifesto"](https://felleisen.org/matthias/manifesto/)).

The counter-argument is that S-expressions are noisy — the parentheses obscure the structure they express — and that reading someone else's Lisp is genuinely harder than reading someone else's Python. Guy Steele and Richard Gabriel's "The Evolution of Lisp" acknowledges that the parenthesized notation is a barrier to adoption while defending it as essential to Lisp's power.

## E4 — Python-style indentation

Python uses *indentation* to delimit blocks: no braces, just the visible structure. This has two effects. First, it makes the *visible* structure of the program *definitely* the same as the *semantic* structure — a class of bugs (misleading indentation) becomes impossible. Second, it forces a style, which advocates count as a benefit and critics count as a cost. Ruby, Perl, and Scala take the opposite position: indentation is a stylistic hint but not a syntactic requirement, and the programmer's freedom to choose is valuable in itself. The Ruby philosophy interview with Matz explicitly rests on the "principle of least surprise" and on the idea that a language should feel *natural* to write ([Interview with Matz, "The Philosophy of Ruby"](https://www.artima.com/articles/the-philosophy-of-ruby)).

## E5 — Ruby/Perl "there's more than one way"

Ruby and Perl explicitly reject the Python "one obvious way" position. Larry Wall's "Programming Perl" and interviews argue that natural languages have many ways to say the same thing and are richer for it; a programming language should give the programmer *choice*, even if that choice makes reading unfamiliar code harder ([Wall, "Diligence, Patience, and Humility"](https://www.oreilly.com/openbook/opensources/book/larry.html)). This is a genuine design-philosophy split: "one obvious way" (Python) vs. "there's more than one way to do it" (Perl/Ruby) is a values choice, not a technical choice.

## E6 — Haskell/OCaml minimal punctuation

Haskell's syntax uses whitespace and juxtaposition where other languages use parentheses and commas: `f x y` is `f(x, y)`, and layout rules (indentation-based blocks) reduce visual noise further. Peyton Jones's Haskell history documents this as a deliberate choice — Haskell wanted to look like the math it was expressing, and math does not use commas or semicolons ([Peyton Jones et al., "A History of Haskell"](https://simon.peytonjones.org/assets/pdfs/haskell-being-lazy-with-class.pdf)). The cost is that mistakes in indentation or operator precedence can silently change the meaning of a program.

## E7 — APL / J symbolic terseness

APL uses a large character set of custom symbols to keep programs short — often a single line for an algorithm that would take a page in C. Iverson defends this on the epistemic grounds already discussed: dense notation lets the programmer *see* patterns that verbose notation hides ([Iverson, "Notation as a Tool of Thought"](https://www.eecg.utoronto.ca/~jzhu/csc326/readings/iverson.pdf)). The cost is that APL is essentially unreadable to anyone who has not learned the notation.

## E8 — Verbose / self-documenting (COBOL, Ada, SQL)

COBOL, Ada, and SQL take the opposite position: verbosity is a *feature*, because the code should read like a specification. `MOVE X TO Y` (COBOL) is longer than `y = x` (C), but a reader who does not know either language can guess more accurately what COBOL is doing. This position is often mocked but has never fully lost: SQL remains the most widely deployed programming language on Earth in part because its verbosity makes it reviewable by non-programmers.

## E9 — Postfix (Forth, Factor)

Concatenative languages (already discussed in A6) write operations in postfix order: `2 3 +` rather than `2 + 3`. This is a genuinely different reading experience, and it takes practice. Advocates argue that postfix is *natural* for the machine (that's how a stack works) and that once fluent, the programmer thinks in terms of data flow rather than expression trees. Chuck Moore's book *Programming a Problem-Oriented Language* is the fullest defense ([Moore, "Programming a Problem-Oriented Language"](https://www.forth.org/POL.pdf)).

## Guy Steele's "Growing a Language" and the syntax-extensibility debate

The most consequential recent essay on language syntax is Guy Steele's OOPSLA 1998 invited talk "Growing a Language." The essay is famous for two devices: first, Steele writes the talk using only one-syllable words (except when introducing multi-syllable words *by defining them*), demonstrating the point that a language must let its users extend it; second, he argues that no language designer can foresee everything users will need, so the designer's real job is to design a language that *can grow* with its user community ([Steele, "Growing a Language" — Wadler-hosted PDF](https://homepages.inf.ed.ac.uk/wadler/documents/steele-oopsla98.pdf); [alternative host](https://www.cs.virginia.edu/~evans/cs655/readings/steele.pdf)).

Steele's key claims (quoting from the paper): "I should not design a small language, and I should not design a large one. I need to design a language that can grow." And: "The language must start small, and the language must grow as the set of users grows." His argument is that any concept that must be built into the base language — because users cannot express it themselves — is a *bug* if it could have been expressed as a library. The examples in the paper are drawn from Java, and Steele argues for adding generic types and operator overloading to Java specifically so that number-like types (rationals, matrices, complex numbers) could be defined by users rather than requiring language changes.

This is the philosophical foundation of the "macros and DSLs" wing of programming language design. It is what motivates Common Lisp's macros, Scheme's syntax-case, Racket's language-oriented programming, Rust's `macro_rules!` and procedural macros, Elixir's macros, and Julia's metaprogramming. The Racket Manifesto extends Steele's argument: Racket is not "a Lisp with macros" but a *platform for designing languages*, where creating a domain-specific language should be as ordinary as writing a library ([Felleisen et al., "The Racket Manifesto"](https://felleisen.org/matthias/manifesto/)).

The counter-position is that too much extensibility is *itself* a defect. Rob Pike's "Go at Google" and "Simplicity is Complicated" argue that Google explicitly rejected macros and heavy extensibility for Go, on the grounds that a language whose users all speak the same dialect is easier to maintain across a large organization than one where every team has invented its own vocabulary ([Pike, "Go at Google"](https://go.dev/talks/2012/splash.article); [Pike, "Simplicity is Complicated"](https://go.dev/talks/2015/simplicity-is-complicated.slide)). "There should be one — and preferably only one — obvious way to do it" (the Zen of Python) is the same position expressed in a different tradition.

## Operator overloading

The debate over operator overloading is a proxy for the broader syntax-extensibility debate. Languages that allow operator overloading (C++, Scala, Rust for many operators, Haskell, Julia) let a programmer write `matrix1 * matrix2` — natural mathematical notation. Languages that do not (Java, Go) require `matrix1.multiply(matrix2)`. The pro side (Stroustrup, Steele) argues that mathematical notation is exactly what users expect and that forbidding it drives programmers to write worse code. The con side (Gosling, Pike) argues that overloading lets library authors give operators meanings that surprise readers, and that method syntax is more consistent and searchable.

---

# Camp F — Compilation strategy

## F1 — AOT compilation to native (C, Rust, Go, Swift)

**Core belief.** Compile the whole program to a native executable before shipping. The result is a standalone binary that runs without a language runtime (or with a minimal one). This maximizes startup speed and deployment simplicity.

**Arguments for.** AOT-compiled binaries start instantly, have predictable performance (no JIT warm-up), and can be deployed to environments (embedded, containers, edge) where a language runtime would be a burden. Go's designers cite fast compilation and simple deployment as core motivations ([Pike, "Go at Google"](https://go.dev/talks/2012/splash.article)).

**Arguments against.** AOT compilation cannot adapt to runtime behavior. A JIT compiler can specialize hot code for the actual types and values it sees; an AOT compiler must generate code for all possible inputs.

## F2 — JIT compilation (Java HotSpot, .NET, V8, LuaJIT, PyPy, Julia)

**Core belief.** Ship bytecode or source, and let the runtime compile it to native code *while the program runs*, specializing for the observed workload. HotSpot, V8, and LuaJIT have all shown that a well-designed JIT can match or beat AOT-compiled code because the JIT sees information the AOT compiler could not.

**Arguments for.** JITs can inline across dynamic dispatch, specialize for observed types, and re-optimize when the program's behavior changes. Julia's design leans heavily on this: because Julia is dynamically typed but the JIT specializes on the concrete types of each call site, Julia can achieve C-like performance on abstract mathematical code ([Bezanson et al., "Julia: A Fresh Approach"](https://math.mit.edu/~edelman/publications/julia_a_fresh.pdf)).

**Arguments against.** JITs impose *warm-up*: the first N invocations of a function run slowly (or interpreted) before the JIT decides to compile it. This makes JITted languages unsuitable for short-lived programs, and it introduces performance non-determinism.

## F3 — Interpretation

**Core belief.** Execute the source directly, node by node in the AST or instruction by instruction in bytecode. No compilation step; no compiler complexity.

**Arguments for.** Interpreters are simple to implement and simple to modify. They give immediate feedback and are natural for languages that emphasize interactivity (Scheme, Ruby, early Python).

**Arguments against.** Pure interpretation is much slower than compiled code — often 10-100× slower. This is why almost every "interpreted" language has, over time, developed a JIT or a bytecode compiler.

## F4 — Transpilation (CoffeeScript, TypeScript, Reason, Kotlin/JS)

**Core belief.** Compile the source to *another high-level language* — usually one for which mature runtimes and toolchains already exist. TypeScript compiles to JavaScript; Kotlin can target JavaScript, JVM bytecode, or native.

**Arguments for.** Transpilation lets a new language ride on existing infrastructure. TypeScript benefits from every JavaScript engine and every JavaScript ecosystem library.

**Arguments against.** The target language's semantics leak into the source language's semantics — TypeScript has JavaScript's numeric type despite type-level ambition. Debugging is harder because errors appear in generated code.

## F5 — VM bytecode (Java, .NET, Python, Erlang BEAM, Lua)

**Core belief.** Compile to a virtual instruction set that a runtime executes. The VM abstracts hardware differences and provides a common target for many languages (Java + Kotlin + Scala + Clojure on the JVM; C# + F# + VB on .NET).

**Arguments for.** VMs give portability, shared tooling, shared garbage collectors, and shared JIT infrastructure. The Erlang BEAM is a particularly clean example: it was designed for actor-model concurrency from the ground up, and any language targeting BEAM (Elixir, LFE, Gleam) inherits its scheduling and fault-tolerance guarantees ([Armstrong thesis](https://erlang.org/download/armstrong_thesis_2003.pdf)).

**Arguments against.** VMs impose a runtime dependency on deployment environments. They also lock in a shared memory model and GC that some workloads would prefer to avoid.

## F6 — WebAssembly as universal target

**Core belief.** WebAssembly is the modern "portable native": a compact, verifiable, sandboxed bytecode that can be executed at near-native speed anywhere — browsers, servers, edge, embedded. Any language can target it.

**Key advocates.** Andreas Rossberg (co-designer of WebAssembly). Rossberg and colleagues' PLDI '17 paper "Bringing the Web up to Speed with WebAssembly" is the design manifesto: WebAssembly is designed to be a "safe, fast, portable low-level code format" whose semantics are formally specified and whose execution can be sandboxed by construction ([Rossberg et al., "Bringing the Web up to Speed with WebAssembly"](https://www.cs.tufts.edu/~nr/cs257/archive/andreas-rossberg/webassembly.pdf)).

**Arguments for.** WebAssembly gives new languages a deployment target that reaches every browser and, increasingly, every serverless runtime. Grain is designed explicitly as a "WebAssembly-first" language, and Roc uses WebAssembly as one target among several ([Rossberg et al.](https://www.cs.tufts.edu/~nr/cs257/archive/andreas-rossberg/webassembly.pdf); [Roc, "Fast"](https://www.roc-lang.org/fast)).

**Arguments against.** WebAssembly's memory model is 32-bit linear (WASM64 is coming), its exception handling and GC are still stabilizing, and its interoperability with the host is proposal-heavy. For many languages, targeting WebAssembly is still more effort than targeting native.

## F7 — Compilation to C (Nim, Chicken Scheme, historical Vala, early C++)

**Core belief.** Use C as a portable "portable assembly" — compile your source to C and let the C compiler do the platform-specific work. Nim, Chicken Scheme, and historically Cfront (the original C++ compiler) all take this approach.

**Arguments for.** C compilers exist for every platform; targeting C means every platform is a target for free. The generated C can be inspected and debugged; C compilers have decades of optimization behind them.

**Arguments against.** C's model of memory and control flow does not fit every language. Emitting efficient C for a language with tail calls, first-class continuations, or garbage collection requires clever mapping that can hurt performance and readability.

---

# Camp G — Design philosophy / meta-camps

The most interesting language design debates are not about specific features but about *values*. This section catalogs the recurring philosophical positions.

## G1 — "Worse is Better" (Richard Gabriel)

Richard Gabriel's 1989 essay "The Rise of Worse is Better" (originally part of "Lisp: Good News, Bad News, How to Win Big") is the founding meditation on the way that inferior-in-theory designs win in practice because they are *simpler to implement*. Gabriel contrasts the "MIT/Stanford" style (correctness, consistency, and completeness first, at the cost of implementation complexity) with the "New Jersey" style (simplicity of implementation first, even at the cost of correctness). His counterintuitive conclusion: the New Jersey style wins, because it produces working software that ships and evolves, while the MIT style produces beautiful software that never quite gets finished ([Gabriel, "Worse Is Better" archive page](https://dreamsongs.com/WorseIsBetter.html); [Wikipedia summary](https://en.wikipedia.org/wiki/Worse_is_better)).

Gabriel himself later wrote against his own argument in "Is Worse Really Better?" and "Worse Is Better Is Worse," under the pseudonym Nickieben Bourbaki, and he has publicly said he cannot decide ([Gabriel, "Is Worse Really Better?" PDF](https://www.dreamsongs.com/Files/IsWorseReallyBetter.pdf); [Gabriel's own overview](https://dreamsongs.com/WorseIsBetter.html)). The essay's rhetorical structure — "the crux of the essay: The Rise of Worse is Better" — has become itself a permanent fixture in design discourse.

The concrete claim: C beat Lisp in the marketplace despite Lisp's technical superiority, because C was easier to port, easier to implement, and produced results that were "good enough" much faster. Unix beat multics for the same reasons. The generalizable claim: any language design must ask not only "what would be right in the abstract" but "what can we implement, ship, and evolve?" ([Gabriel, "Worse Is Better" archive page](https://dreamsongs.com/WorseIsBetter.html)).

**Arguments for.** Shipping software beats theoretically superior software that never ships. Users adopt what is available and workable; a design that resists implementation compromise never accumulates the mass of users, libraries, and tools that make a language actually useful. Steele's "Growing a Language" makes a compatible point from a different angle: the language must be extensible by its users, and a language that requires everything to be perfect at v1 will never grow ([Steele, "Growing a Language" PDF](https://homepages.inf.ed.ac.uk/wadler/documents/steele-oopsla98.pdf)).

**Arguments against.** "Worse is Better" is often deployed as a rationalization for shipping unfinished work. Gabriel's own reversals show that even the argument's author is ambivalent. Bob Harper and others in the "Right Thing" tradition argue that shipping bad designs early makes them permanent — the installed base of C code and the security holes it enables are the payoff for "worse is better," and the payoff is measured in decades of buffer overflows ([Gabriel, "Is Worse Really Better?" PDF](https://www.dreamsongs.com/Files/IsWorseReallyBetter.pdf)).

**Tradeoff accepted.** Time-to-market and evolvability over up-front correctness. Willingness to ship known-imperfect designs and fix them later, versus refusal to ship until the design is right.

## G2 — "The Right Thing" (MIT / Lisp / Scheme / Haskell)

**Core belief.** The design must be correct, consistent, and complete before it ships. Simplicity of interface takes priority over simplicity of implementation. This is the position Gabriel contrasts with "worse is better," and it is the tradition of Scheme, Common Lisp, ML, and Haskell.

**Key advocates.** Guy Steele and Gerald Sussman's Lambda papers ([research.scheme.org lambda papers](https://research.scheme.org/lambda-papers/)) are the foundational works of the tradition — the argument that a language should be built around a small number of orthogonal, mathematically-clean primitives that compose. Simon Peyton Jones's history of Haskell, "Being Lazy with Class," describes how the Haskell committee explicitly chose to be "avoid success at all costs" — that is, to prioritize getting the design right over getting it adopted, in the belief that early adoption would prevent later cleanup ([Peyton Jones, "History of Haskell"](https://simon.peytonjones.org/assets/pdfs/haskell-being-lazy-with-class.pdf)).

**Arguments for.** Designs that are right at the core can be extended indefinitely without becoming inconsistent. Scheme's small core has supported decades of research extensions; Haskell's type system has absorbed monads, GADTs, type families, and linear types because the foundation was built on principled mathematics. When "the right thing" and "worse is better" contest the same problem, the right thing often prevails on the second attempt: Rust's borrow checker is a "right thing" answer to memory safety that beat decades of C's "worse is better" workarounds.

**Arguments against.** "The right thing" often ships too late to matter. Gabriel's original observation was that Common Lisp — a technically superior language — lost the marketplace to C precisely because the Lisp world was waiting to get the design right while the C world was shipping working code. Haskell's own community sometimes ruefully notes that the "avoid success at all costs" strategy has been almost too successful at avoiding success.

**Tradeoff accepted.** Correctness and long-term evolvability over time-to-market and short-term adoption.

## G3 — Wirthian minimalism (Pascal, Modula, Oberon)

**Core belief.** A language should be as small as it can possibly be while still being useful. Every feature must justify its cost in complexity, and the language designer's job is to say "no" to features. Niklaus Wirth's "A Plea for Lean Software" and his "Good Ideas — Through the Looking Glass" are the definitive statements of the position ([Wirth, "Good Ideas — Through the Looking Glass" PDF](http://pascal.hansotten.com/uploads/wirth/Good%20Ideas%20Wirth.pdf); [Wirth's IEEE Annals article on ETH languages](https://people.inf.ethz.ch/wirth/Miscellaneous/IEEE-Annals.pdf)).

**Key advocates.** Niklaus Wirth (Pascal, Modula-2, Oberon), and by direct lineage Rob Pike (Go). Wirth's essay is a chronicle of features he considers mistakes: excessive syntactic sugar, GOTO, overloading, exceptions used for control flow, inheritance-based OO. He argues that every language designer should first master the discipline of subtraction ([Wirth PDF](http://pascal.hansotten.com/uploads/wirth/Good%20Ideas%20Wirth.pdf)). Rob Pike's talk "Go at Google" is an explicit modern application of the Wirthian ethic — Go was designed by removing features from C++ and Java to produce a small, fast, orthogonal language ([Pike, "Go at Google"](https://go.dev/talks/2012/splash.article)).

**Arguments for.** A small language can be learned in a day, implemented in a semester, and reasoned about completely. Wirth's law — "software gets slower faster than hardware gets faster" — is a diagnosis of what happens when languages accumulate features without discipline ([Wirth's Law](https://en.wikipedia.org/wiki/Wirth%27s_law)). Go's stated success case is teams of hundreds of engineers who can all agree on how to write code, precisely because there are so few ways to write it.

**Arguments against.** Minimalism often shifts complexity from the language to the user's code. Go's lack of generics for a decade meant that every generic algorithm was reimplemented in every codebase; the eventual addition of generics in Go 1.18 was an admission that the minimalist position had costs. Oberon's near-total obscurity outside academia suggests that "small enough to fit in one person's head" is not by itself a sufficient value proposition.

**Tradeoff accepted.** Simplicity of the language definition over expressive power in the language user's code. A smaller language, at the cost of more boilerplate and less abstraction.

## G4 — Kitchen-sink maximalism (C++, Common Lisp, Perl, Scala)

**Core belief.** A language should provide every feature its users could possibly want, and let the user choose which subset to use. Bjarne Stroustrup's "Thriving in a Crowded and Changing World: C++ 2006–2020" is the definitive defense of the kitchen-sink position: C++ must support systems programming, generic programming, functional programming, and object-oriented programming, because its users need all of these ([Stroustrup, HOPL C++ 2020 PDF](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf)).

**Key advocates.** Bjarne Stroustrup (C++), Guy Steele (Common Lisp — though Steele straddles both camps), Larry Wall (Perl), Martin Odersky (Scala). Wall's "there's more than one way to do it" (TIMTOWTDI) is the linguistic-relativist form of the argument: languages, like natural languages, should support many idioms and let culture decide which are best.

**Arguments for.** No language design committee can predict what its users will need. Providing the feature and letting users choose is more honest than deciding for them. C++ has survived and thrived for four decades precisely because it can absorb any programming style its user community demands. Stroustrup's HOPL paper argues that C++'s success is a direct consequence of its willingness to add features rather than choose sides ([Stroustrup HOPL PDF](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf)).

**Arguments against.** Kitchen-sink languages are unlearnable. C++ has more corners than any single engineer can master; codebases devolve into a mishmash of idioms; teams spend energy on style debates instead of shipping code. Scott Meyers's entire career of "Effective C++" books is evidence for the cost of C++'s complexity. Rob Pike's motivation for Go was explicitly the observation that C++ had become unlearnable ([Pike, "Go at Google"](https://go.dev/talks/2012/splash.article)).

**Tradeoff accepted.** Expressive power and adaptability over learnability and consistency. Every user can find a subset they like, at the cost that no two users use the same subset.

## G5 — "Blub paradox" (Paul Graham)

**Core belief.** Language power exists on a spectrum, and programmers can only see downward on the spectrum. A programmer whose home language is "Blub" (an average procedural language somewhere in the middle) can look down and see that assembly is more painful, but cannot look up and see that Lisp is more powerful — because the features they would need in order to see the power are the features they lack ([Graham, "Beating the Averages"](http://www.paulgraham.com/avg.html) — while this URL is Graham's own essay, his argument is widely cited in language-design discussions).

**Key advocates.** Paul Graham, and more broadly the Lisp community. The Blub argument is essentially the case for macros, homoiconicity, and continuations — features that Blub programmers cannot see they are missing.

**Arguments for.** History has repeatedly proven the Blub argument correct: garbage collection, closures, dynamic dispatch, pattern matching, algebraic data types, sum types, and null-safety were all "esoteric Lisp/ML features" that mainstream languages resisted for decades before adopting. Every "modern feature" of Rust or Swift is a Lisp or ML feature from the 1970s or 1980s.

**Arguments against.** The Blub argument is unfalsifiable and can be used to dismiss any critique of any language. If the critic says "your favorite language lacks feature X," the response is always "you're just Blub." It also confuses "feature quantity" with "feature power" — a language can have many features and still be less expressive than one with few, well-chosen ones. Hickey's Simple Made Easy is essentially a rebuke to the Blub-driven "add more features" mindset ([Hickey, "Simple Made Easy" transcript](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/SimpleMadeEasy-mostly-text.md)).

**Tradeoff accepted.** Willingness to prioritize expressive power over immediate learnability, with the implicit claim that history will vindicate the choice.

## G6 — "Simple Made Easy" (Rich Hickey)

**Core belief.** *Simple* and *easy* are not the same. Simple means "un-braided" — a thing has one role, one task, one dimension. Easy means "at hand" — familiar, near-to-us. Hickey argues that the industry has systematically confused the two, choosing easy tools that produce complected systems, and that the solution is to prefer simple tools even when they are unfamiliar ([Hickey, "Simple Made Easy" transcript](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/SimpleMadeEasy-mostly-text.md)).

**Key advocates.** Rich Hickey (Clojure). Hickey's talks "Simple Made Easy," "The Value of Values," "Hammock Driven Development," "Are We There Yet?", and "Effective Programs" together form a coherent design philosophy centered on separating what is *simple* (composable, orthogonal, values, functions) from what is *easy* (mutable state, objects with methods, inheritance, ORMs) ([Hickey, "Value of Values"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/ValueOfValues.md); [Hickey, "Are We There Yet?"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/AreWeThereYet.md); [Hickey, "Hammock Driven Development"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/HammockDrivenDev.md); [Hickey, "Effective Programs"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/EffectivePrograms.md)).

**Arguments for.** Long-lived systems are killed by complexity, and complexity is what happens when concepts are braided together (state and identity, data and behavior, semantics and syntax). Choosing simple constructs — pure functions over methods, values over objects, data over state — makes systems that can be reasoned about, tested, and evolved. Clojure's design (immutable persistent data structures, separating identity from state via atoms/refs/agents, treating time as a first-class concern) is a direct realization of the philosophy.

**Arguments against.** "Simple" is subjective and culturally-loaded. What Hickey calls "simple" (dynamic types plus functional composition) is what Bob Harper would call "hopelessly complected" — because dynamic types braid together all possible types into a single type ([Harper, "Dynamic Languages are Static Languages"](https://existentialtype.wordpress.com/2011/03/19/dynamic-languages-are-static-languages/)). The critique cuts both ways: what looks "simple" to a Lisp veteran can look like a formless pile of maps to a Haskeller.

**Tradeoff accepted.** Willingness to learn unfamiliar constructs in exchange for systems that are easier to reason about over time. The bet that unfamiliarity is a one-time cost, while complexity is a permanent tax.

## G7 — Zero-cost abstractions (C++, Rust)

**Core belief.** Every abstraction the language provides must compile to code as efficient as the equivalent hand-written low-level code. If a feature imposes a runtime cost that a competent programmer would not have written, the feature does not belong in a systems language. Stroustrup's articulation of the position for C++ is that "what you don't use, you don't pay for; and what you do use, you couldn't hand-code any better" ([Stroustrup HOPL PDF](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf)). Rust adopts the same principle explicitly and extends it to memory safety: safe Rust is expected to produce code as fast as unsafe Rust or hand-written C.

**Key advocates.** Bjarne Stroustrup (C++), the Rust core team (documented across Rust's design manifestos), and increasingly the Swift and Zig teams. Rust's async/await design explicitly aimed for zero-cost futures — no allocation per await, no vtable dispatch — as documented in the Rust futures design writeups ([Rust futures / Zero-cost futures blog](https://aturon.github.io/blog/2016/08/11/futures/)).

**Arguments for.** Systems programming languages compete on performance, and any language that cannot deliver hand-written-C performance for hot loops will lose adoption for systems work. Rust's success in browsers (Servo, Firefox), operating systems (Linux kernel), and databases (TigerBeetle, ScyllaDB) depends on the zero-cost promise.

**Arguments against.** Zero-cost abstractions in the runtime often shift the cost to *compile time* and *cognitive complexity*. Rust's async model has been widely criticized as producing types that are hard to spell, hard to compose, and hard to teach — a cognitive tax paid to preserve zero runtime cost. C++ templates famously produce compile times measured in minutes and error messages measured in pages. The zero-cost bet is that runtime performance matters more than compile-time or human ergonomics.

**Tradeoff accepted.** Runtime performance over compile time, cognitive load, and ergonomics.

## G8 — Batteries-included vs. tiny-core (Python, Java, Node vs. Scheme, Lua)

**Core belief.** Two opposing positions on standard libraries. Python's "batteries included" philosophy holds that the standard library should provide everything a typical program needs: HTTP, JSON, XML, SQLite, subprocesses, dates, math, statistics, testing. The opposing tiny-core position (Scheme, Lua, historically JavaScript) holds that the language should provide only the minimum and let the ecosystem provide the rest.

**Key advocates.** Python (Guido van Rossum), Java, Go — batteries included. Scheme, Lua, JavaScript pre-Node — tiny core.

**Arguments for batteries.** Users can be productive on day one without hunting for libraries. Security-sensitive functionality (crypto, HTTP) benefits from being centrally maintained. Consistency across programs improves — everyone uses the same HTTP client.

**Arguments for tiny core.** Standard libraries age faster than languages; batteries become anchors that the language cannot escape (Python 2 vs. 3 was largely a stdlib migration). Tiny-core languages allow the ecosystem to compete and select the best library, and to update libraries independently of the language.

**Tradeoff accepted.** Day-one convenience and consistency, versus long-term ability to evolve libraries independently of the language.

## G9 — Growing a Language (Guy Steele)

**Core belief.** A language should be small at the core and grow through user-defined extensions. Users, not the language committee, should be the primary source of new abstractions. Guy Steele's 1998 OOPSLA keynote "Growing a Language" is the definitive statement — Steele delivers the entire talk using only single-syllable words except where he first defines a new multi-syllable word, thereby demonstrating in real time what it means for a language to grow from a small core ([Steele, "Growing a Language" PDF](https://homepages.inf.ed.ac.uk/wadler/documents/steele-oopsla98.pdf)).

**Key advocates.** Guy Steele (Common Lisp, Scheme, Java, Fortress). The tradition includes Lisp's macros, Scheme's `syntax-rules` and `syntax-case`, Racket's `#lang` mechanism (which allows users to define entirely new languages within Racket), and Julia's macros and generated functions.

**Arguments for.** No design committee can predict what its users will need. A language that grows through its users can adapt to domains the designers never imagined. Racket's manifesto — that Racket is a "language-oriented programming" platform, where users routinely build DSLs for their problem domain — is a direct implementation of Steele's vision ([Racket manifesto sources]).

**Arguments against.** User-extensible languages fragment into dialects. Every codebase becomes its own language, with its own idioms and its own learning curve. Common Lisp macros are famously powerful and famously abused — reading someone else's macro-heavy code requires learning their private language before reading the code. Rob Pike's Go explicitly rejects macros and user syntax extensions on exactly these grounds ([Pike, "Go at Google"](https://go.dev/talks/2012/splash.article)).

**Tradeoff accepted.** Extensibility and user empowerment over uniformity and readability across codebases.

## G10 — Language-oriented programming and DSLs

**Core belief.** For any complex problem, the right solution is to build a language tailored to the problem, then write the solution in that language. The extreme form is Racket's "languages as libraries" — where any file can declare its own `#lang` and use its own syntax, semantics, and type system.

**Key advocates.** The Racket team (Matthias Felleisen, Matthew Flatt, Robby Findler, Shriram Krishnamurthi). The Racket manifesto is the explicit statement of the position. Guy Steele's "Growing a Language" is a compatible manifesto. Charles Simonyi's "Intentional Programming" and Martin Fowler's writing on internal vs. external DSLs are the industrial applications.

**Arguments for.** Each problem domain has a natural notation; forcing every domain into general-purpose language syntax loses fidelity. SQL is a DSL for relational queries; regular expressions are a DSL for text matching; shader languages are DSLs for GPU code. Making DSLs cheap to define lets each problem be expressed in its own natural notation. Perlis's epigram — "a language that doesn't affect the way you think about programming is not worth knowing" — is the argument that new notations produce new thoughts ([Perlis, Epigrams on Programming](https://cpsc.yale.edu/sites/default/files/files/tr172.pdf)).

**Arguments against.** DSL proliferation makes codebases unreadable to newcomers. Debugging a program that mixes five DSLs requires understanding five semantic models. Fowler's own writing catalogs the maintenance costs of internal DSLs. The Racket ethos, while beloved by researchers, has not produced mainstream adoption — most industrial teams prefer one language everyone knows to ten languages tailored to their problems.

**Tradeoff accepted.** Expressiveness within a domain over uniformity across domains.

## G11 — Agent-authored language design (emerging)

**Core belief.** When most code is written by AI agents rather than humans, the design tradeoffs of a language change. Verbosity that would be painful for a human is trivial for an agent; contracts, capabilities, and effect annotations that would be onerous for a human are cheap for an agent; static verification becomes more valuable because the agent cannot rely on the same intuition a human would use to catch its own mistakes. Machine-verifiable properties become more important than human-readable syntax.

This camp is still forming, and its central texts have not yet been written. Verus is an early example — a Rust dialect designed to make code machine-verifiable, at a level of annotation cost that would be prohibitive for most human teams but is acceptable for machine authors ([Verus arxiv paper](https://arxiv.org/abs/2303.05491)). The Roc language's emphasis on "no side effects except through platforms" and pure-by-default semantics is another design that becomes especially valuable when code is written by agents whose intent needs to be verifiable ([Roc, "Fast"](https://www.roc-lang.org/fast)).

**Arguments for.** Agent-authored code has different failure modes than human-authored code: hallucinated APIs, plausible-looking but subtly wrong implementations, silent misalignment with intent. Languages that force intent to be explicit — through types, contracts, effects, capabilities — let the agent's output be machine-checked against the specification. In an era when hundreds of thousands of lines of code can be generated per hour, machine-verifiability is the only viable line of defense.

**Arguments against.** The premise is speculative — we do not yet know how agent-authored codebases scale, what their real failure modes are, or whether the tools and practices that work for human code will simply extend to agent code. Designing for agents risks producing languages that neither humans nor agents can use effectively — a "worst of both worlds" outcome.

**Tradeoff accepted.** Verifiability and explicit intent over concise, human-readable syntax. Bet that agents can absorb annotation cost that humans cannot.

## G12 — Capability-safe languages

**Core belief.** All authority in a program should flow through explicit capability references. There should be no ambient authority — no global filesystem, no global network, no global heap. Every operation that has an effect on the outside world must be authorized by a capability that was explicitly passed to the code performing the operation. This is the object-capability model (ocap).

**Key advocates.** Mark Miller (E language, and later Agoric), the Pony language team, the Austral language ([Austral spec / capabilities], Wyvern. Pony's capabilities system is the most developed production implementation: every object reference has a capability annotation (`iso`, `val`, `ref`, `box`, `tag`, `trn`) that controls what the code holding the reference can do with it ([Pony capabilities documentation and academic papers referenced in batch02]).

**Arguments for.** Ambient authority is the root cause of the software supply chain crisis: any package can read `.ssh/`, write to `~`, exfiltrate secrets, or install malware, because the language grants every function the same authority as the process. Capability-safe languages make it impossible for `left-pad` to steal your SSH keys, because `left-pad` was never given a filesystem capability. In a world of large dependency graphs and AI-authored code, this property becomes essential.

**Arguments against.** Capability-safe design imposes a large notational cost on every function that touches the outside world: every parameter list grows to include the capabilities the function requires. Existing library ecosystems assume ambient authority, so a capability-safe language starts with no libraries. E and Pony have not achieved wide adoption in part because of these costs.

**Tradeoff accepted.** Explicit authorization at every level of the call stack, at the cost of verbosity and ecosystem-building effort.

## G13 — Verified languages (Coq, Idris, Agda, Lean, F*, Verus)

**Core belief.** The language should let (or force) the programmer to prove that the code is correct with respect to a machine-checkable specification. Types are not merely a way to catch mistakes — they are a way to prove theorems, via the Curry-Howard correspondence. If a program type-checks, the program is a proof of its type.

**Key advocates.** The dependent-types community (Agda, Idris, Coq/Rocq, Lean), the refinement types community (Liquid Haskell, F*), and the applied verification community (Verus for Rust, Low* / miTLS for F*). Edwin Brady's Idris ([Idris homepage / academic papers referenced in batch03]), Aaron Weiss and the Verus team ([Verus arxiv paper](https://arxiv.org/abs/2303.05491)), and Ranjit Jhala's Liquid Haskell work ([Liquid Haskell papers referenced in batch03]) are the leading practitioners.

**Arguments for.** For safety-critical software — cryptography, avionics, medical devices, blockchains — the cost of a bug is enormous, and formal verification is the only way to be sure. Verified TLS implementations (Project Everest / miTLS) have shipped in production and prevented entire classes of vulnerabilities. In an era of AI-authored code, machine-checkable specifications become essential because the human reviewer cannot manually check every line of an agent's output.

**Arguments against.** Verification is expensive in engineer-time, and the tools are still hard to learn. Most software does not need to be verified; the cost is only worth paying for the small fraction of software where a single bug is catastrophic. Verified languages tend to have small ecosystems and steep learning curves.

**Tradeoff accepted.** Very high up-front effort to specify and verify, in exchange for machine-checked guarantees that ordinary testing cannot provide.

### Summary tradeoff table — design philosophy

| Camp | Value maximized | Value sacrificed | Exemplar |
|------|-----------------|------------------|----------|
| G1 Worse is Better | Time-to-market, evolvability | Up-front correctness | C, Unix |
| G2 Right Thing | Long-term correctness | Time-to-market | Scheme, Haskell |
| G3 Wirthian | Language simplicity | Expressive convenience | Pascal, Go |
| G4 Kitchen-sink | Expressive power | Learnability | C++, Common Lisp |
| G5 Blub | Future-proofing expressive power | Immediate accessibility | Lisp |
| G6 Simple Made Easy | Long-term reasoning | Immediate familiarity | Clojure |
| G7 Zero-cost | Runtime performance | Compile time, ergonomics | C++, Rust |
| G8 Batteries | Day-one productivity | Library evolvability | Python, Go |
| G9 Growing | User extensibility | Cross-codebase uniformity | Lisp, Racket, Julia |
| G10 LOP / DSL | Domain-specific fidelity | Cross-domain uniformity | Racket, Emacs Lisp |
| G11 Agent-authored | Machine verifiability | Human ergonomics | (emerging) |
| G12 Capability-safe | Supply-chain safety | Ambient-authority ergonomics | Pony, E, Austral |
| G13 Verified | Machine-checked correctness | Author effort, ecosystem size | Coq, Idris, F*, Verus |

---

# Camp H — Ecosystem philosophy

Language design does not stop at the language. The design of the *ecosystem* — packages, versioning, tooling, community, governance — determines whether a well-designed language is actually usable, and shapes the security, evolvability, and culture of the resulting software.

## H1 — Package-manager-first (npm, Cargo, pip, gems)

**Core belief.** A modern language ships with a package manager. Publishing and consuming libraries must be trivial. The community, not the standard library, is the primary source of functionality. Rust's Cargo is often cited as the reference implementation — it was designed with the language, is the language's build tool, test runner, documentation generator, and package manager, and every Rust developer uses it.

**Arguments for.** Ecosystems grow much faster when publishing is frictionless. npm, Cargo, and pip together enabled the "small modules" ecosystem where basic building blocks are reused across thousands of projects. Cargo's model of a single build tool per language dramatically reduces the "how do I build this?" friction that plagues C and C++.

**Arguments against.** Frictionless publishing means frictionless malware. The npm `event-stream`, `ua-parser-js`, `colors/faker` sabotage, `left-pad`, and repeated typosquatting incidents are all consequences of the package-manager-first model. Cargo has seen similar incidents. When any developer can publish a package that any other developer can install into their build, the language has effectively delegated its security model to social trust.

**Tradeoff accepted.** Ecosystem velocity over ecosystem security.

## H2 — Standard-library-first (Go, Java, Python early days)

**Core belief.** The standard library should provide the bulk of common functionality, and third-party libraries should be a fallback. Go is the modern archetype — its standard library provides HTTP, JSON, encryption, template engines, testing, benchmarking, profiling, and a race detector. The Go authors explicitly designed the standard library to be the primary answer for most programs.

**Arguments for.** Users can be productive on day one. The security posture is stronger — the standard library is maintained by a small team with security review, rather than an ecosystem of thousands of unaudited packages. Backward compatibility is easier to preserve when the language and standard library evolve together. Go's Go 1 compatibility promise has been kept for over a decade largely because the standard library evolves in coordination with the language.

**Arguments against.** Standard libraries age. They are hard to update because they are tied to language releases and cannot break existing users. Python's stdlib carries decades of decisions that would be made differently today (urllib, http.server, asyncore/asynchat), and Python's move to `asyncio` in Python 3 was necessary in part because the stdlib approach to networking had ossified.

**Tradeoff accepted.** Stability and security over ability to iterate on library design.

## H3 — Curated vs. free-for-all repositories

**Core belief.** Two sub-positions. Free-for-all repositories (npm, PyPI, RubyGems, Cargo's crates.io) allow anyone to publish anything, with minimal review; curated repositories (Debian packages, historically Haskell's Stackage, some Linux distros) require review before publication and provide guarantees about integrity and compatibility. Package-manager-first (H1) languages have typically chosen free-for-all; some communities (Haskell's Stackage) provide a curated overlay on top of a free-for-all base.

**Arguments for free-for-all.** Ecosystem growth is exponentially faster; long-tail packages get published; the community collectively curates through downloads, stars, and reviews.

**Arguments for curation.** Malware is prevented at the gate rather than after the fact. Users of curated distributions can trust that packages are compatible with each other and that their dependencies are known-good. The Haskell Stackage / LTS model provides both — free-for-all Hackage plus curated LTS snapshots.

**Tradeoff accepted.** Long-tail coverage and iteration speed vs. baseline safety and cross-package compatibility.

## H4 — Semantic versioning and backward compatibility

**Core belief.** Libraries and languages should follow semantic versioning: bug fixes bump the patch, new features bump the minor, breaking changes bump the major. Backward compatibility is a first-class value.

**Key advocates.** Go's Go 1 compatibility promise; Rust's edition system, which lets Rust evolve without breaking old code; Java's decades-long compatibility record; C++ and its commitment to ABI stability (with recent debate).

**Arguments for.** Users can upgrade with confidence. Ecosystems can compose because everyone follows the same rules. Users' investments in code, tooling, and knowledge are preserved across upgrades.

**Arguments against.** Backward compatibility is a permanent tax. Every design mistake made in the past must be preserved forever, or requires a painful migration (Python 2→3, Perl 5→6, ECMAScript 5→6). Rich Hickey argues in "Maybe Not" and "Spec-ulation" that most library "breaking changes" are unnecessary — they represent developers reneging on their prior commitments to users, and better tooling would let libraries evolve without breaking users ([Hickey, "Maybe Not"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/MaybeNot.md)).

**Tradeoff accepted.** User investment preservation over ability to fix past mistakes.

## H5 — Monorepo vs. microlibrary ecosystems

**Core belief.** Two positions. Microlibrary ecosystems (npm most famously) favor many small packages, each doing one thing. Monorepo ecosystems (Go's stdlib, Java frameworks, Elixir/Phoenix) favor large integrated codebases where components ship together.

**Arguments for microlibraries.** Composability, reuse, focus. Each package has a small blast radius; each is easy to audit; each is easy to replace.

**Arguments against microlibraries.** Deep dependency trees. Every small package multiplies the attack surface — `left-pad` (11 lines of code) had thousands of transitive dependents, and its removal broke the JavaScript ecosystem overnight. Deep trees also fragment ownership: no one is responsible for the whole system.

**Arguments for monorepos.** Coherent design across many components; central ownership; easier to reason about the whole. Go's decision to make the standard library the primary source of common functionality is a monorepo-style bet.

**Tradeoff accepted.** Fine-grained composability vs. coherent design and shallow trees.

## H6 — Documentation as first-class (Rust, Elixir, Racket)

**Core belief.** Documentation is not an afterthought — the language should provide first-class tooling to generate, host, and search documentation. Rust's `rustdoc`, Elixir's `ExDoc`, Racket's Scribble, Go's `godoc`, and Julia's Documenter.jl are all explicit language-level investments in documentation.

**Arguments for.** Undocumented libraries are unusable. Consistency of documentation format across an ecosystem makes learning new libraries dramatically easier. First-class doc tooling encourages a culture where documentation is expected. Rust's ecosystem is famously well-documented in large part because `cargo doc` is one command and every crate has automatically-generated docs at docs.rs.

**Arguments against.** First-class doc tooling has real design costs — Rust and Elixir have shaped their languages around doc-comment conventions. Rich documentation infrastructure can also lull maintainers into thinking their docs are complete when the actual prose is missing.

**Tradeoff accepted.** Language-level investment in documentation vs. leaving documentation to the ecosystem.

## H7 — Community governance models

**Core belief.** Language ecosystems are shaped by their governance models. Options include benevolent dictator (Python under Guido, Ruby under Matz, Perl under Wall), foundation-run (Rust Foundation, Python Foundation), corporate-controlled (Go by Google, Swift by Apple until recently, TypeScript by Microsoft), and community RFC processes (Rust, Swift-Evolution, Elixir).

**Arguments for BDFL.** Fast decisions, coherent vision, ability to say no. Ruby's decades of consistent design under Matz is evidence.

**Arguments for foundations.** Long-term stability, protection from corporate whims, community ownership. Python's Foundation model has weathered multiple version transitions.

**Arguments for corporate control.** Resources, focus, coherent design. Go under Google and TypeScript under Microsoft have both benefited from clear ownership and deep pockets.

**Arguments for community RFC processes.** Transparency, broad input, community buy-in. Rust's RFC process is often cited as a model of how to evolve a language with community participation.

**Tradeoff accepted.** Speed of decision vs. breadth of input; corporate resources vs. community independence.

## H8 — Package security and supply-chain defense

**Core belief.** The package ecosystem is a critical part of the language, and its security is the language designer's responsibility. This camp is emerging — most existing languages inherited free-for-all package models before the supply-chain crisis became acute, and are now retrofitting defenses.

**Key advocates.** The capability-safety community (Pony, E, Austral) argues that the language itself must limit what packages can do — see G12. More conservative approaches include cryptographic signing (sigstore, PGP-signed crates), reproducible builds (Nix, Debian reproducible builds), sandboxed builds (Bazel remote execution, Nix), and permission systems (Deno's `--allow-net`, `--allow-read`).

**Arguments for.** The supply chain has become the primary attack vector on software. Every language ecosystem has been hit — npm event-stream, PyPI ctx and phpass, Cargo colors/faker, Ruby rest-client. Language designers have a responsibility to build defense into the language and its tools.

**Arguments against.** Retrofitting security to existing ecosystems is enormously expensive and risks breaking user workflows. Fine-grained permissions models (Deno's approach) require every package to declare its capabilities, which is a large notational cost that users may not accept. Capability-safe design (Pony) requires the language to be designed from scratch — no incremental path is available.

**Tradeoff accepted.** For emerging languages: up-front design cost for supply-chain safety. For existing ecosystems: continued exposure to supply-chain attacks vs. costly retrofit.

### Summary tradeoff table — ecosystem philosophy

| Camp | Value maximized | Value sacrificed | Exemplar |
|------|-----------------|------------------|----------|
| H1 Package-manager-first | Ecosystem velocity | Ecosystem security | Cargo, npm |
| H2 Stdlib-first | Stability, security | Library evolvability | Go, Java |
| H3 Free-for-all repos | Long-tail coverage | Baseline safety | npm, PyPI |
| H3 Curated repos | Baseline safety | Long-tail coverage | Stackage, Debian |
| H4 SemVer / back-compat | User investment | Ability to fix past | Go, Rust, Java |
| H5 Microlibraries | Composability | Shallow trees, ownership | npm, Rubygems |
| H5 Monorepo/stdlib | Coherent design | Fine-grained reuse | Go stdlib |
| H6 First-class docs | Learnability | Language-design cost | Rust, Elixir |
| H7 Various governance | Various | Various | Varies |
| H8 Supply-chain defense | Package security | Ergonomic cost | Pony, Deno |

---

# Cross-cutting tradeoffs

The camps above are organized by domain (paradigm, type system, memory, etc.), but the deepest disagreements in language design cut across the camps. This section catalogs the tradeoffs that recur.

## Expressiveness vs. simplicity

The single oldest tension in language design. More features means more expressive power in the small; fewer features means smaller cognitive footprint and easier reasoning in the large. Wirth's minimalism (G3) and Hickey's Simple Made Easy (G6) both bet against expressive-power maximalism, arguing that long-term simplicity of reasoning matters more than short-term expressive convenience. The kitchen-sink camp (G4) bets the other way. Steele's "Growing a Language" (G9) proposes a middle path — start small and let users add features, so no committee has to pick.

The tradeoff resolves differently in different contexts. For domains where the cost of mistakes is large (systems programming, safety-critical, cryptography), simplicity of the language usually wins because it makes reasoning tractable. For domains where iteration speed dominates (research, scripting, data analysis), expressiveness usually wins because it makes prototyping fast.

## Safety vs. performance

Rust's central claim is that this is a false dichotomy — that safety and performance can both be achieved through the ownership discipline. Historical experience suggests the tradeoff is real: garbage collection buys memory safety at the cost of unpredictable pause times; bounds checking buys safety at the cost of runtime instructions; dynamic typing buys flexibility at the cost of type errors caught only at runtime. The Rust bet has largely paid off for a range of systems tasks, but it has done so by imposing a large *cognitive* tax — the borrow checker adds mental load that C does not — and by ruling out data structures (arbitrary graphs, self-referential types) that are natural in garbage-collected languages.

For a broader analysis of the memory-management tradeoffs, David Bacon, Perry Cheng, and V.T. Rajan's paper "A Unified Theory of Garbage Collection" argues that all GC algorithms are hybrids between tracing and reference counting, and that pause time, throughput, memory overhead, and pause predictability form a fundamental tradeoff space that no GC can escape ([Bacon et al., "A Unified Theory of Garbage Collection"](https://researcher.watson.ibm.com/researcher/files/us-bacon/Bacon04Unified.pdf)).

## Compile-time vs. runtime cost

Every design must decide where to pay its costs. Zero-cost abstractions (G7) push cost to compile time. JIT compilation (F2) pushes cost to first-execution (warmup) time. Interpretation (F3) pushes cost to every-execution. Static verification (G13) pushes cost to author time. Dynamic typing (B2) pushes cost to runtime.

The rise of AI-authored code changes this equation. Author time was historically the scarce resource; compile time was a secondary concern; runtime cost was a distant third. In an era of agent-authored code, author time is nearly free, so pushing costs earlier becomes cheaper — machine-checked types, verified specifications, and heavy static analysis all become more attractive when the "author" can absorb the extra work.

## Author cost vs. reader cost

Every language design privileges either the code author or the code reader. Perl and Ruby optimize for author expressiveness — one-liner solutions and personality-driven idioms. Go and Java optimize for reader consistency — code from a stranger looks like code from you. Haskell splits the difference — the language is famously terse for authors but requires substantial knowledge from readers to interpret.

In codebases with high turnover, or in open-source projects with many drive-by contributors, reader cost dominates. In small-team startups, author cost dominates. Language design cannot escape this asymmetry — the same feature that empowers the author (macros, operator overloading, custom DSLs) burdens the reader.

## Author cost vs. maintenance cost

The distinct-but-related tradeoff. Dynamic typing minimizes author cost (no annotations required) at the cost of maintenance cost (types must be inferred from tests, comments, and reading code). Static typing raises author cost (annotations must be written) but lowers maintenance cost (types document intent, refactors are checked). Bob Harper's "Dynamic Languages are Static Languages" is the theoretical form of the argument: a dynamic language is a static language with exactly one type ("Any"), and every dynamic program is really a static program that has traded compile-time errors for runtime errors — the errors do not disappear, they only move ([Harper, "Dynamic Languages are Static Languages"](https://existentialtype.wordpress.com/2011/03/19/dynamic-languages-are-static-languages/)).

Hickey's counter, from "Effective Programs," is that types describe a very narrow slice of what a program does — they describe what values flow through it, but not what the program *means*, whether it is correct with respect to the domain, or whether the data it processes is well-formed at the domain level. Types can be a distraction from the harder problem of specifying and validating domain data ([Hickey, "Effective Programs"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/EffectivePrograms.md); [Hickey, "Maybe Not"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/MaybeNot.md)).

The empirical evidence, insofar as it exists, is mixed. Large codebases in dynamic languages (Python, JavaScript, Ruby) do accumulate maintenance debt, and the industry response — TypeScript for JavaScript, mypy for Python, Sorbet for Ruby — has been to retrofit static typing. But industrial-scale codebases in dynamic languages (Instagram, GitHub, Shopify) do exist and do ship reliable software, suggesting the tradeoff is not fatal in either direction.

## AI vs. human authoring

An emerging axis of language design. Every design decision that was made with "the human author" in mind — concise syntax, minimal annotation, implicit conversions, ambient authority — may be a different decision if "the AI author" is the primary user. Agents can absorb verbosity; agents cannot rely on intuition to catch subtle bugs; agents can be paired with verifiers that check their output against specifications; agents can absorb annotation cost that humans would reject.

The Verus project ([Verus arxiv paper](https://arxiv.org/abs/2303.05491)) is an early data point: a Rust dialect where every function can be annotated with pre/post conditions and loop invariants that the compiler checks against a formal specification. The annotation cost has historically been considered too high for human teams, but is plausibly acceptable for agent-authored code.

This tradeoff is speculative because the industry does not yet know how large-scale agent authoring actually works — what its failure modes are, whether reviewers can keep up, or whether the language even matters (perhaps agents will just target the languages that already have the most training data, regardless of design). But the direction of design experimentation — capability-safety (G12), verified specifications (G13), effect systems (B11) — is consistent with a belief that the answer is yes, language design does matter for agent-authored code, and the languages that will do best in that era are those that make intent explicit and machine-checkable.

## Innovation vs. familiarity

Novel languages have a cold-start problem — no libraries, no jobs, no training materials, no institutional knowledge. Familiar languages have an innovation problem — they cannot break their user base to try new ideas, so improvements accumulate slowly or not at all. The most successful new languages of the last 20 years (Go, Rust, Swift, TypeScript, Kotlin) have all made deliberate familiarity choices — Go looks like C, TypeScript is a superset of JavaScript, Kotlin interoperates seamlessly with Java, Swift is designed to feel comfortable to Objective-C programmers. Even Rust's ML-inspired syntax made concessions to C-family programmers.

Meanwhile, the more radically novel languages of the same era (Elm, Idris, Racket, Roc, Grain, Pony, Koka, Unison) have found small enthusiastic communities but not mass adoption. This suggests a strong preference in the industry for familiarity — new languages succeed by importing what already works, not by starting from scratch.

The counter-argument is that this reasoning is over-fit to the past. Rust's borrow checker was radical when it was introduced, and Rust succeeded despite it — because the value proposition (memory safety without GC) was strong enough to justify the learning cost. If AI-era or supply-chain-era pressures produce a similarly strong value proposition for a radical design, familiarity may cease to be the constraint it has been.

## Small language + big library vs. big language + small library

Two equal-and-opposite designs. Scheme, Lua, and JavaScript are small languages that grew large libraries around them. Common Lisp, C++, and Perl are large languages with (relatively) smaller ecosystems. Python is a middle case — a moderately-sized language with a very large stdlib and a very large ecosystem.

The tradeoff is not about total complexity — every complete system is roughly equally complex — but about *where* the complexity lives. Small-language-plus-library ecosystems shift complexity into libraries, which can be picked and chosen, versioned independently, and swapped out. Large-language ecosystems put complexity into the language itself, which is uniform across all users but harder to evolve.

## TIMTOWTDI vs. one obvious way

Perl's "There's More Than One Way To Do It" and Python's "There Should Be One — And Preferably Only One — Obvious Way to Do It" are the standard-bearers for the two extremes. Perl (and Ruby, in a milder form) embrace stylistic diversity as an expression of programmer individuality. Python (and Go, in a stronger form) impose uniformity as an efficiency measure — every reader knows what to expect.

Robert Guss's engineering context (self-taught senior engineer, AI-coding-agent user) is illuminating here — TIMTOWTDI is arguably easier for AI agents to produce (many valid outputs) but harder for AI agents to read (many valid inputs); one-obvious-way is arguably easier for agents to read but constrains what they can produce. This is another axis where the AI-authoring era may change the calculus.

## Backward compatibility vs. progress

Every language that has succeeded has faced this tradeoff: preserve past decisions and slow down future evolution, or break past decisions and lose users. The extremes are C++ (backward-compatible to the point of preserving decades of design mistakes) and Perl 6 / Raku (broke with Perl 5 and failed to bring the community along). The middle grounds include:

- Python 2 → Python 3 (bit the bullet, painful but eventually successful)
- Java (long-term compat with periodic modernization through modules, records, sealed types)
- Rust (edition system: opt-in breaking changes within a single compiler, older editions still compile)
- Go (Go 1 promise: nothing that works in Go 1.0 breaks — for a decade)
- Swift (broke compatibility repeatedly in the early years, stabilized later)

Rust's edition system is arguably the most elegant answer — allowing the language to evolve without breaking existing code, by making breaking changes opt-in per crate. The cost is complexity in the compiler, which must support all editions simultaneously.

## Package ecosystem security vs. ecosystem growth

The tradeoff that has become acute in the last decade. Frictionless publishing (npm, PyPI, Cargo, RubyGems) enabled explosive ecosystem growth — but at the cost of a supply-chain attack surface that every language is now scrambling to defend. Debian's slower, curated model was more secure but produced a smaller ecosystem. There is no known way to have both.

The camps disagree on the right response. The capability-safety camp (G12) says the language must limit what packages can do — ambient authority is the root cause, and any solution that doesn't remove ambient authority is fighting the wrong battle. The signing-and-provenance camp (sigstore, SLSA, Cargo's cryptographic signatures) says the answer is to verify that packages are what they claim to be and were built by who they claim. The sandboxing camp (Deno, WebAssembly-based module systems) says the answer is to run packages in reduced-privilege sandboxes. The auditing camp (cargo-audit, dependabot, Snyk) says the answer is continuous scanning of known-bad packages. Each of these addresses a different part of the problem; none addresses all of it.

## Value dimensions: a synthesis

Every language design implicitly picks a point in a high-dimensional space of values. The most-cited dimensions in the literature and the primary sources gathered for this report include:

- **Performance** (runtime speed, memory efficiency)
- **Safety** (memory safety, type safety, concurrency safety, supply-chain safety)
- **Expressiveness** (how much can be said in how little code)
- **Simplicity** (how easy the language is to fully understand)
- **Familiarity** (how much prior knowledge transfers)
- **Portability** (how many platforms it runs on)
- **Interoperability** (how well it talks to other languages)
- **Learnability** (how quickly a beginner becomes productive)
- **Maintainability** (how well code holds up over time)
- **Verifiability** (how well the language supports proving programs correct)
- **Ecosystem** (how many libraries, tools, and jobs exist)
- **Evolvability** (how the language and ecosystem can improve over decades)

No language maximizes all of these — improvements on one dimension routinely cost on another. What makes a language design coherent is not that it maximizes every value, but that it makes an *explicit choice* about which values matter most and which are being sacrificed. The camps in this document are, at bottom, different answers to the question "which values matter most?"

---

# Conclusion: on picking a camp

The camps in this document are not exclusive. Every real language is a mix — Rust is imperative (A1), has traits (nominal + trait-based, B5), uses ownership + borrowing for memory (C6), supports async/await (D5), C-family syntax (E1), AOT-compiled (F1), pursues zero-cost abstractions (G7), and has a package-manager-first ecosystem (H1). Julia is impure functional (A4), uses CLOS-style multiple dispatch (A2d), dynamically typed with optional annotations (B2/B3), tracing GC (C4), threads and channels (D1/D2), JIT-compiled (F2), designed for scientific computing with heavy metaprogramming (G4/G9). Python is imperative + OO (A1/A2a), dynamically typed with gradual annotations (B2/B3), reference-counted with GC backstop (C3/C4), interpreted (F3), batteries-included (G8).

The value of the camp taxonomy is not to sort languages into buckets — most languages defy the buckets — but to make the *tradeoffs* explicit. When designing a new language, the designer should be able to say: for each of these axes, here is the position I am taking and here is what I am giving up. The most common failure of language design is not making the wrong choice on any given axis; it is failing to make the choice explicitly, and ending up with a language whose design is inconsistent because the designer never noticed they were choosing.

For Mo (the AI-era language currently in design), the framework suggests specific questions:

- What is the position on **type systems** (B)? If verifiability is a priority, the answer is at least gradual + refinement types, possibly effect types or capabilities. The AI-authored era changes the cost calculus of annotation.
- What is the position on **memory management** (C)? Ownership + borrowing (C6) is the current best answer for systems performance without GC; linear types (C7) go further with more discipline; region-based (C5) is a well-explored alternative.
- What is the position on **concurrency** (D)? Actors (D3) plus structured concurrency (D6) is a defensible modern combination; async/await (D5) is the mainstream default; effect-based concurrency (D10) is emerging.
- What is the position on **compilation** (F)? AOT (F1) for performance, WebAssembly (F6) for portability, both if possible.
- What is the position on **design philosophy** (G)? Capability-safe (G12) plus verified specifications (G13) plus agent-authored (G11) is the coherent story for AI-era supply-chain-safe design.
- What is the position on **ecosystem** (H)? Package-manager-first (H1) with supply-chain defense (H8) baked in from day one — this is the hardest tradeoff, because H1 velocity fundamentally trades against H8 safety unless the language design forecloses ambient authority.

Making these choices explicit — writing the design goals down, publishing them, and defending them against critique — is what the successful language designers in this report did. Gabriel wrote "Worse Is Better." Steele wrote "Growing a Language." Wirth wrote "Good Ideas." Hickey delivered "Simple Made Easy," "Are We There Yet?", and "Effective Programs." Kay wrote "The Early History of Smalltalk." Peyton Jones wrote "Being Lazy with Class." Backus delivered "Can Programming Be Liberated from the von Neumann Style?" These are not marketing documents — they are design manifestos, and they made the tradeoffs explicit. The languages that followed those manifestos have, on the whole, aged better than the ones that did not.

The final observation: language design is a conversation across decades. Wirth's Pascal begat Modula begat Oberon begat Go. McCarthy's Lisp begat Scheme begat Racket begat Clojure. ML begat Standard ML begat OCaml begat F# and Reason. Every new language stands on decisions made by earlier languages, and every new language contributes decisions that will be reused, refined, or rejected by later ones. The camps in this document are not permanent — they are the shape of a conversation still in progress. The best a language designer can do is understand where the conversation has been, make an honest position, and add to it.

---

## Sources

The following primary sources were consulted and cited in this report. All are linked inline in the relevant sections.

**Foundational essays and manifestos.** Richard Gabriel, ["Worse Is Better" archive](https://dreamsongs.com/WorseIsBetter.html) and ["Is Worse Really Better?"](https://www.dreamsongs.com/Files/IsWorseReallyBetter.pdf); Guy Steele, ["Growing a Language" PDF](https://homepages.inf.ed.ac.uk/wadler/documents/steele-oopsla98.pdf); Niklaus Wirth, ["Good Ideas — Through the Looking Glass"](http://pascal.hansotten.com/uploads/wirth/Good%20Ideas%20Wirth.pdf) and [IEEE Annals article](https://people.inf.ethz.ch/wirth/Miscellaneous/IEEE-Annals.pdf); Bjarne Stroustrup, ["Thriving in a Crowded and Changing World: C++ 2006–2020" HOPL PDF](https://www.stroustrup.com/hopl20main-p5-p-bfc9cd4--final.pdf); Rob Pike, ["Go at Google"](https://go.dev/talks/2012/splash.article); Peter Van Roy, ["Programming Paradigms for Dummies"](https://webperso.info.ucl.ac.be/~pvr/VanRoyChapter.pdf); Alan Kay, ["The Early History of Smalltalk" HOPL II PDF](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf).

**Rich Hickey talks.** ["Simple Made Easy" transcript](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/SimpleMadeEasy-mostly-text.md); ["Value of Values"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/ValueOfValues.md); ["Are We There Yet?"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/AreWeThereYet.md); ["Hammock Driven Development"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/HammockDrivenDev.md); ["Effective Programs"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/EffectivePrograms.md); ["Maybe Not"](https://github.com/matthiasn/talk-transcripts/blob/master/Hickey_Rich/MaybeNot.md).

**Type systems and verification.** Bob Harper, ["Dynamic Languages Are Static Languages"](https://existentialtype.wordpress.com/2011/03/19/dynamic-languages-are-static-languages/); Simon Peyton Jones, ["A History of Haskell: Being Lazy with Class"](https://simon.peytonjones.org/assets/pdfs/haskell-being-lazy-with-class.pdf); ["Verus: Verifying Rust Programs using Linear Ghost Types"](https://arxiv.org/abs/2303.05491); [TypeScript design goals](https://github.com/microsoft/TypeScript/wiki/TypeScript-Design-Goals).

**Paradigms.** Carl Hewitt et al., ["A Universal Modular ACTOR Formalism for Artificial Intelligence" PDF](https://ijcai.org/Proceedings/73/Papers/027B.pdf); Joe Armstrong, ["Making reliable distributed systems in the presence of software errors" (thesis)](https://erlang.org/download/armstrong_thesis_2003.pdf); C.A.R. Hoare, ["Communicating Sequential Processes" PDF](https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf); John Backus, ["Can Programming Be Liberated from the von Neumann Style?" PDF](https://worrydream.com/refs/Backus_1978_-_Can_Programming_Be_Liberated_from_the_von_Neumann_Style.pd).

**Memory management.** David Bacon, Perry Cheng, V.T. Rajan, ["A Unified Theory of Garbage Collection"](https://researcher.watson.ibm.com/researcher/files/us-bacon/Bacon04Unified.pdf).

**Modern languages.** [Roc, "Fast"](https://www.roc-lang.org/fast); [Julia: A fresh approach to numerical computing PDF](https://math.mit.edu/~edelman/publications/julia_a_fresh.pdf); [Julia: Dynamism and Performance Reconciled PDF](https://benchung.github.io/papers/jlov.pdf); [Julia: The Goldilocks language, Increment](https://increment.com/programming-languages/goldilocks-language-history-of-julia/); [Swift SE-0304 Structured Concurrency](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md).

**Historical and cultural.** [Hillel Wayne, "Alan Kay Did Not Invent Objects"](https://www.hillelwayne.com/post/alan-kay/); [Communicating Sequential Processes Wikipedia summary](https://en.wikipedia.org/wiki/Communicating_sequential_processes); [MISRA C:2023 D4.12 no dynamic allocation rule](https://www.mathworks.com/help/bugfinder/ref/misrac2023d4.12.html); [Ada Ravenscar profile](https://www.adaic.org/resources/add_content/standards/05rat/html/Rat-5-4.html); ["Inventing on Principle" — Bret Victor speech transcript](https://jamesclear.com/great-speeches/inventing-on-principle-by-bret-victor); [Racket Lambda Papers archive](https://research.scheme.org/lambda-papers/); [Perlis, Epigrams on Programming](https://cpsc.yale.edu/sites/default/files/files/tr172.pdf).

Additional inline citations appear throughout the body of the report and are not repeated here to avoid duplication.

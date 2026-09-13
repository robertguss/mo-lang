# Smalltalk — Objects All the Way Down

## Origin story

### Designers, institution, year

Smalltalk was created at **Xerox PARC** by the Learning Research Group (LRG). Wikipedia lists **Alan Kay**, **Dan Ingalls**, **Adele Goldberg**, **Ted Kaehler**, **Diana Merry**, and **Scott Wallace** among the creators, with "the language designed by Adele Goldberg, Dan Ingalls, Alan Kay" ([Wikipedia: Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)). Development began in **1969**; Kay coined "Smalltalk" as the language for his **KiddiKomp/miniCOM** design in **1971**. **Dan Ingalls implemented the first Smalltalk interpreter in about 700 lines of BASIC in October 1972** for the Data General Nova ([Wikipedia: Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)).

The pivotal moment came in the fall of 1972 when "Kay, Dan Ingalls, and Ted Kaehler discussed whether a highly powerful language could be defined in 'a page of code.' Kay accepted the challenge and worked for two weeks on the interpreter" ([Kay, HOPL-II Smalltalk paper](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)). Kay presented the work to the MIT AI Laboratory in November 1972, where "the work later influenced Carl Hewitt's Actor model."

### The motivating problem

Kay's motivation was not another programming language but the **Dynabook** — "a personal, notebook-sized computer intended for 'children of all ages'" ([Kay HOPL-II](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)). Kay identified "two central motivations for OOP: a better module scheme for complex systems with hidden details, and a more flexible version of assignment, eventually eliminating assignment altogether." He drew on the Burroughs 220 file system, the B5000, Sketchpad, Simula, LISP, JOSS, and later Carl Hewitt's PLANNER. Kay built a cardboard Dynabook mock-up with lead pellets to determine desired weight ("less than two pounds") ([Kay HOPL-II](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)).

### Initial reception and the pivotal releases

- **Smalltalk-72** (October–November 1972): Ingalls's 700-line BASIC interpreter on the Nova; ported to the Xerox Alto in **April 1973** — the same month the first Alto units began operation ([Wikipedia: Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)).
- **Smalltalk-74 ("FastTalk")**: added a real messenger object, class message dictionaries, and Diana Merry's bitblt (redesigned by Ingalls and implemented in microcode) ([Kay HOPL-II](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)).
- **Smalltalk-76** (November 1976): "Dan Ingalls, Dave Robson, Ted Kaehler, and Diana Merry implemented it from scratch in seven months… approximately 50 classes described in about 180 pages of source code," including operating-system functions, Ethernet services, editors, graphics, painting, browsers, and debugging contexts. Presented at POPL in January 1978.
- **Smalltalk-80** (1980, then Version 1 in November 1981, Version 2 in 1983): "the first version made publicly available; it added metaclasses and became the basis for future commercial versions" ([Wikipedia: Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)). Xerox distributed Version 1 to Apple, DEC, HP, and Tektronix for review and debugging on their platforms.

**Steve Jobs**, Jeff Raskin, and Apple engineers famously visited PARC in **1979** and saw Smalltalk running on the Dorado; "Dan Ingalls changed bit-style scrolling to smooth continuous scrolling in less than a minute" ([Kay HOPL-II](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)). The visit informed the Lisa and Macintosh designs.

The **1981 Byte magazine special issue on Smalltalk**, edited by Adele Goldberg, "generated requests from universities and commercial organizations to purchase Smalltalk." **ANSI Smalltalk** was ratified in **1998** ([Wikipedia: Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)).

## Design philosophy

### Core principles

- **Everything is an object.** Integers, classes, methods, blocks — all objects.
- **Objects communicate only by sending messages.** Kay in his 1997 OOPSLA talk: "I actually made up the term object-oriented, and I can tell you I did not have C++ in mind… I have apologized profusely over the last twenty years for making up the term object-oriented, because as soon as it started to be misapplied, I realized that I should have used a much more process-oriented term for it" ([Kay OOPSLA 1997](https://tinlizzie.org/IA/index.php/Alan_Kay_at_OOPSLA_1997:_The_Computer_Revolution_has_not_Happened_Yet)).
- **Encapsulation as an inviolable membrane.** "You must, must not let the interior of any one of these things to be a factor in the computation of the whole" ([Kay OOPSLA 1997](https://tinlizzie.org/IA/index.php/Alan_Kay_at_OOPSLA_1997:_The_Computer_Revolution_has_not_Happened_Yet)).
- **Late binding of everything.** Class structure, methods, even the syntax can change while the system runs.

### What Smalltalk rejected

Static types, syntactic separation of code and data, batch compilation, and (per Kay's stated regret) the notion that "objects" were about state and data structures rather than about *processes* communicating. Kay: "The Japanese have an interesting word, which is called *ma*. Spelled in English, just *ma*. *Ma* is the stuff in-between what we call objects… It's the stuff we don't see, because we're focused on the nounness of things rather than the processness of things" ([Kay OOPSLA 1997](https://tinlizzie.org/IA/index.php/Alan_Kay_at_OOPSLA_1997:_The_Computer_Revolution_has_not_Happened_Yet)).

### Cultural values

Live coding, exploratory development, image persistence, personal computing. Kay: "The thing I am most proud of about Smalltalk, pretty much the only thing, from my standpoint, that I am proud of, is that it has been so good at getting rid of previous versions of itself, until it came out into this world" ([Kay OOPSLA 1997](https://tinlizzie.org/IA/index.php/Alan_Kay_at_OOPSLA_1997:_The_Computer_Revolution_has_not_Happened_Yet)). The Squeak project was "an attempt to give the world a bootstrapping mechanism for something much better than Smalltalk."

## Language features

### Syntax

Minimal and unusual. Messages come in three kinds: **unary** (`aNumber factorial`), **binary** (`a + b`), and **keyword** (`aDictionary at: key put: value`). Statements end in `.`, blocks are `[ ... ]`, and cascades chain messages with `;`. The result is a syntax that a child can learn in a page — Kay taught Smalltalk to 20 nonprogramming adults in Spring 1974 who "could learn the initial material but had difficulty designing a simple database" ([Kay HOPL-II](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)).

### Type system

Dynamically typed with structural duck-typing at the message level; every message send is a dynamic dispatch on the receiver's class.

### Memory model and GC

Fully garbage-collected. Objects live in an image; the runtime manages memory transparently.

### Concurrency

Green threads (`Process`, `Semaphore`, `SharedQueue`) in the image; the language does not expose OS threads directly, though modern implementations (Pharo, VisualWorks) offer FFI to OS concurrency.

### Error handling

Exception classes with `on:do:` and `ensure:` (analogous to try/catch/finally). Modern implementations support resumable exceptions similar in spirit to Common Lisp's condition system, though less elaborate.

### Metaprogramming

Extraordinary. Classes are first-class objects; you can modify methods, add classes, redefine primitives at runtime. `doesNotUnderstand:` allows arbitrary handling of missing messages — the basis for proxies, DSLs, and remote object systems. Compiled methods are themselves objects that can be inspected.

### Module system

Historically Smalltalk shipped code in "parcels" (VisualWorks), "packages" (Pharo), or "changesets" (older systems); the image itself was the module boundary. Modern Pharo uses **Metacello** for versioned package management.

### Image-based development

"Most Smalltalk systems store the entire program state in an image file, including class objects, non-class objects, program state. The image can be loaded by the Smalltalk virtual machine to restore a Smalltalk-like system to a prior state" ([Wikipedia: Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)). This provides delayed debugging, remote debugging, full state access at time of error, and preservation of undo history and cursor position. It is also a common criticism: images are opaque to source-control tools and version-controlled workflows.

### Notable innovations

- Bitmap displays and windowing directly integrated with the language.
- **BitBlt** — Diana Merry's bit-block-transfer primitive, redesigned by Ingalls, implemented in microcode ([Kay HOPL-II](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)).
- The **class browser** — a graphical view of the class hierarchy that seeded every modern IDE.
- **Morphic** — the direct-manipulation UI framework, first in Self and then in Squeak.

## Implementation

### Reference implementations

- **Smalltalk-80** was the first widely released implementation. The 1983 release process "enabled programmers to implement the virtual machine without reinventing it" — Xerox published a **VM specification** ([Kay HOPL-II](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf)).
- **Squeak** (1996, Alan Kay, Dan Ingalls, Ted Kaehler at Apple, then Disney) — open-source Smalltalk-80 descendant, self-hosted, VM written in a subset of Smalltalk called **Slang** and translated to C.
- **Pharo** — a modern fork of Squeak focused on industrial use.
- **VisualWorks** (Cincom, commercial) and **VA Smalltalk** (Instantiations, commercial) descend from ObjectWorks and IBM VisualAge Smalltalk.
- **GemStone/S** — a Smalltalk-based object database.
- **GNU Smalltalk** — a command-line implementation.

### Lexer, parser, IR, backend

The classic Smalltalk-80 VM used **bytecodes** interpreted by a stack machine. Modern implementations (Cog VM used by Pharo/Squeak, VisualWorks) add a **JIT** that produces native code from bytecodes at runtime.

### Bootstrapping

Squeak is famously self-hosted: the VM is written in Slang and translated to C for compilation.

## Ecosystem

### Package manager

**Metacello** in Pharo; **Store** in VisualWorks; **Monticello** for source-code versioning within images.

### Standard library

Rich: collections, streams, graphics, networking, persistence. The class library was, until Java's arrival, a competitive advantage.

### Tooling

The Smalltalk IDE — the **class browser**, **inspector**, **debugger**, **workspace** — was the archetype every modern IDE followed. Pharo, Squeak, VisualWorks, and VA Smalltalk all ship polished environments.

### Community and governance

Small but devoted. Pharo is coordinated by the Pharo Consortium; ESUG (European Smalltalk User Group) organizes an annual conference; ANSI Smalltalk (1998) provided a portability baseline but is essentially frozen ([Wikipedia: Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)).

## Adoption

### Historical usage

- **Xerox internal**, then commercial licenses to Apple, DEC, HP, Tektronix (1981–1983).
- **JPMorgan Chase's Kapital** trading system was a landmark Smalltalk deployment.
- **OTI/IBM VisualAge Smalltalk** was widely used for financial and enterprise systems in the 1990s.
- **Cincom VisualWorks** continues to be sold commercially.
- **GemStone/S** persists in a small number of high-transaction systems.

### Where it dominates

Nowhere at large scale today. Where it survives, it survives because rewriting legacy systems is expensive: financial services (JPMorgan Kapital), manufacturing, and a small number of research groups (INRIA's RMOD team maintains Pharo).

### Where it failed to penetrate

Mainstream commercial development. **Java in 1995** captured the object-oriented commercial market: Java offered familiar C-like syntax, static typing, JVM portability, and Sun's marketing muscle. Smalltalk was priced out of the mainstream by VisualWorks and VisualAge licensing, and by the time open Squeak arrived in 1996, Java had won the mindshare battle.

### Current momentum (2026)

Pharo continues active development with a small dedicated community. Squeak remains a research and educational vehicle. Commercial VisualWorks and VA Smalltalk continue to serve legacy customers. There is no meaningful growth curve.

## Criticism and open problems

- **Insularity**: Smalltalk's image-based development is at odds with file-based version control, CI/CD, and containerized deployment.
- **Weak text-tool integration**: everything happens in the image; command-line ergonomics are poor by modern standards.
- **Kay's own critique**: Kay's OOPSLA 1997 talk is a sustained argument that the OOP the world got is not the OOP he intended. "I think this is the most pernicious thing about languages a lot like C++ and Java, is that they think they're helping the programmer by looking as much like the old thing as possible, but in fact they are hurting the programmer terribly by making it difficult for the programmer to understand what's really powerful about this new metaphor" ([Kay OOPSLA 1997](https://tinlizzie.org/IA/index.php/Alan_Kay_at_OOPSLA_1997:_The_Computer_Revolution_has_not_Happened_Yet)).
- **Performance**: modern Cog JITs are competitive but never became a HotSpot-class effort.

## Influence on other languages

Wikipedia's Smalltalk page lists as influenced: AppleScript, CLOS, Dart, Dylan, Erlang, Etoys, Go, Groovy, Io, Ioke, Java, Lasso, Logtalk, Newspeak, NewtonScript, Object REXX, Objective-C, PHP 5, Python, Raku, Ruby, Scala, Scratch, Self, Swift ([Wikipedia: Smalltalk](https://en.wikipedia.org/wiki/Smalltalk)). "Virtually all object-oriented languages that came after Smalltalk were influenced by it, including Objective-C, Java, Python, Ruby, Flavors, CLOS, many others."

The direct heirs:

- **Objective-C** — Brad Cox explicitly modeled the object system on Smalltalk's message passing; the `[receiver selector:arg]` syntax mirrors Smalltalk's keyword messages. The Objective-C runtime remains one of the most Smalltalk-like OO systems in production use.
- **Self** — David Ungar and Randall Smith at PARC/Sun (1987) — Smalltalk pushed to prototypes; Self's `Morphic` UI and JIT techniques informed both Squeak and JavaScript.
- **Ruby** — Yukihiro Matsumoto has consistently cited Smalltalk (and Lisp) as a primary influence; the pure-object semantics, everything-is-an-object model, and blocks all trace to Smalltalk.
- **Java** — took the object model and garbage collector, dropped the image-based development, dropped the small syntax, dropped the pervasive message-passing metaphor.
- **JavaScript** — Wikipedia does not list JavaScript as directly influenced, but Brendan Eich's original design took prototypes from Self, which itself is a Smalltalk derivative.
- **Erlang** — Joe Armstrong cited Kay's message-passing formulation of OO as directly relevant to Erlang's actor model.

## Key sources

- Alan C. Kay, ["The Early History of Smalltalk"](https://www.cs.tufts.edu/comp/150FP/archive/alan-kay/smalltalk-hopl-ii.pdf), HOPL-II, 1993 — the primary historical source.
- Adele Goldberg and David Robson, *Smalltalk-80: The Language and its Implementation*, 1983 (the "Blue Book").
- Adele Goldberg, *Smalltalk-80: The Interactive Programming Environment*, 1984 (the "Orange Book").
- Glenn Krasner (ed.), *Smalltalk-80: Bits of History, Words of Advice*, 1983 (the "Green Book").
- Alan Kay, ["The Computer Revolution Hasn't Happened Yet"](https://tinlizzie.org/IA/index.php/Alan_Kay_at_OOPSLA_1997:_The_Computer_Revolution_has_not_Happened_Yet), OOPSLA 1997 keynote.
- [Wikipedia: Smalltalk](https://en.wikipedia.org/wiki/Smalltalk).
- Byte magazine, August 1981 — the Smalltalk special issue edited by Adele Goldberg.

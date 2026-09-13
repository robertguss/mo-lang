---
tool: Perplexity Computer
prompt: prompts-research-agenda-2026-09 / R3 (authors, the elders)
run: 2026-09-13
run_by: Perplexity Computer, at Robert's request
sha256: 6362dd5eba7ffec238ae52f82fecf7c5d0098c93a7f1c4e7b681d871ad0b3aeb
---
# R3 — The elders: ethos, decisions, and how they played out

Research run for Robert Guss, 2026-09-13. Eight language designers whose ideas sit under Mo: Thompson, Ritchie, Kernighan, Pike, Hoare, Dijkstra, Wirth, Armstrong.

Ground rules for this dossier: every quotation below was fetched from a primary source in this session and carries a link to the exact URL. Where a source could not be reached or a famous line could not be verified in a primary source, the entry says "n.a." Secondary sources are marked as such and are used only for attribution or dates. Everything labelled "Judgment:" is mine, not the source's.

Terms used below, each defined once:
- Trusting-trust attack: a compiler that inserts a backdoor into programs it compiles, including into its own future versions, so the backdoor survives even when the compiler source is clean.
- CSP (Communicating Sequential Processes): a model where independent processes share nothing and interact only by synchronous message passing over channels.
- Guarded command: a statement prefixed by a boolean guard; only guards that are true are eligible to run, and which true guard runs is deliberately unspecified.

---

## 1. Ken Thompson — B, C, Unix, Plan 9, UTF-8, Go

### Ethos in his own words

"I am a programmer. On my 1040 form, that is what I put down as my occupation." ([Reflections on Trusting Trust, CACM 27(8), 1984](https://dl.acm.org/doi/pdf/10.1145/358198.358210))

"The moral is obvious. You can't trust code that you did not totally create yourself." ([Reflections on Trusting Trust](https://dl.acm.org/doi/pdf/10.1145/358198.358210))

"No amount of source-level verification or scrutiny will protect you from using untrusted code." ([Reflections on Trusting Trust](https://dl.acm.org/doi/pdf/10.1145/358198.358210))

"As the level of program gets lower, these bugs will be harder and harder to detect. A well-installed microcode bug will be almost impossible to detect." ([Reflections on Trusting Trust](https://dl.acm.org/doi/pdf/10.1145/358198.358210))

"The three of us got together and decided that we hated C++." ([Q&A: Ken Thompson, Creator Of Unix, InformationWeek, 2011](https://www.informationweek.com/software-services/q-a-ken-thompson-creator-of-unix))

"[In developing Go,] we started off with the idea that all three of us had to be talked into every feature in the language, so there was no extraneous garbage put into the language for any reason." ([InformationWeek Q&A, 2011](https://www.informationweek.com/software-services/q-a-ken-thompson-creator-of-unix))

"There are obviously too many features if you can do something that many ways—and they are more or less equivalent." ([Interview with Ken Thompson, Computer, May 1999](https://www.cs.princeton.edu/courses/archive/spring03/cs333/thompson))

"It was written for Dennis and me and our group to do its work, and I thought it would be useful to anybody who did the kind of work that we did." ([InformationWeek Q&A, 2011](https://www.informationweek.com/software-services/q-a-ken-thompson-creator-of-unix))

On the minimalism aphorisms: "When in doubt, use brute force" is attributed to Thompson by Eric Raymond, who writes that Thompson "reinforced Pike's rule 4 with a gnomic maxim worthy of a Zen patriarch" ([The Art of Unix Programming, Basics of the Unix Philosophy](http://www.catb.org/esr/writings/taoup/html/ch01s06.html)). That is a secondary attribution; no primary Thompson text carrying the sentence was found in this session. The line "one of my most productive days was throwing away 1000 lines of code" could not be verified in any primary Thompson source: n.a. Treat it as folklore.

### Defining decisions

Decision 1: demonstrate that source review cannot establish trust. Stated reasoning: "In demonstrating the possibility of this kind of attack, I picked on the C compiler. I could have picked on any program-handling program such as an assembler, a loader, or even hardware microcode." ([Reflections on Trusting Trust](https://dl.acm.org/doi/pdf/10.1145/358198.358210)) How it played out: the attack stood uncountered in practice for twenty-five years, then acquired a concrete defence. David A. Wheeler's diverse double-compiling thesis states: "The 'Trusting Trust' attack is an incredibly nasty attack in computer security; up to now it's been presumed to be the essential uncounterable attack," and proposes that "source code is compiled twice: once with a second (trusted) compiler (using the source code of the compiler's parent), and then the compiler source code is compiled using the result of the first compilation. If the result is bit-for-bit identical with the untrusted executable, then the source code accurately represents the executable." ([Fully Countering Trusting Trust through Diverse Double-Compiling](https://dwheeler.com/trusting-trust/)) DDC needs determinism: "DDC does require that the parent compiler must be deterministic when it compiles the compiler under test." ([DDC](https://dwheeler.com/trusting-trust/)) That determinism requirement is exactly what the Reproducible Builds project industrialised: "Reproducible builds are a set of software development practices that create an independently-verifiable path from source to binary code," and "First, the build system needs to be made entirely deterministic: transforming a given source must always create the same result." ([reproducible-builds.org](https://reproducible-builds.org/))

Decision 2: keep the bugged compiler's payload out of the source entirely. Reasoning: "We can now remove the bugs from the source of the compiler and the new binary will reinsert the bugs whenever it is compiled." ([Reflections on Trusting Trust](https://dl.acm.org/doi/pdf/10.1145/358198.358210)) How it played out: the 2024 xz/liblzma backdoor is the same shape at the distribution layer rather than the compiler layer. Andres Freund reported: "The upstream xz repository and the xz tarballs have been backdoored," and, crucially, "One portion of the backdoor is solely in the distributed tarballs. This injects an obfuscated script to be executed at the end of configure." ([oss-security, 29 March 2024](https://www.openwall.com/lists/oss-security/2024/03/29/4)) Freund also noted the attacker's patience: "Given the activity over several weeks, the committer is either directly involved or there was some quite severe compromise of their system." ([oss-security](https://www.openwall.com/lists/oss-security/2024/03/29/4)) Judgment: xz validated Thompson's structural claim — the artefact people run was not the artefact people read — while showing the modern attack surface is build scripts and release tarballs, not only compilers.

Decision 3: co-design Go so that no feature enters without unanimous agreement of three people. Reasoning: "we started off with the idea that all three of us had to be talked into every feature in the language, so there was no extraneous garbage put into the language for any reason." ([InformationWeek Q&A, 2011](https://www.informationweek.com/software-services/q-a-ken-thompson-creator-of-unix)) How it played out: Go shipped small and stayed small for a decade; the same unanimity rule also delayed generics by twelve years, a cost Go's own team eventually acknowledged (see the Pike section).

Decision 4: reject C++'s way of offering many equivalent mechanisms. Reasoning: "In C++ and Java I experience a certain amount of angst when you ask how to do this and they say, 'Well, you do it like this or you could do it like that.' There are obviously too many features if you can do something that many ways—and they are more or less equivalent." ([Computer, 1999](https://www.cs.princeton.edu/courses/archive/spring03/cs333/thompson)) How it played out: this became the "one way to do it" discipline that Go's error-handling decision reaffirmed in 2025: "Not adding extra syntax is in line with one of Go's design rules: do not provide multiple ways of doing the same thing." ([Robert Griesemer, go.dev blog, 3 June 2025](https://go.dev/blog/error-syntax))

Decision 5: expect adoption to be slow and voluntary. Reasoning: "It's hard to adopt it to a project inside of Google because of the learning curve," and "It's expanding every day and not being forced down anybody's throat." ([InformationWeek Q&A, 2011](https://www.informationweek.com/software-services/q-a-ken-thompson-creator-of-unix))

On the 2023–2026 shell/xz-era reflections asked for in the brief: Thompson gave a closing keynote at SCaLE 20x on 12 March 2023, listed in the Go documentary bibliography ([golang.design/history](https://golang.design/history/)), but no transcript with verbatim remarks on supply-chain attacks was reachable in this session: n.a.

### Opinions that contradict Mo's current design

- Thompson's trust argument cuts against Mo's "source carries its evidence" posture. Mo puts the evidence in the source: contracts, never clauses, tests, a verified line. Thompson's claim is that source-level evidence is exactly the layer an attacker can render meaningless: "No amount of source-level verification or scrutiny will protect you from using untrusted code." ([Reflections on Trusting Trust](https://dl.acm.org/doi/pdf/10.1145/358198.358210)) Mo compiles to C via Zig, so Mo inherits at least two compilers it did not write.
- Thompson's Go experience says a small language spreads slowly and on a learning curve even inside one friendly company. Mo assumes agents absorb the learning curve. That is an untested substitution.
- Judgment: the brute-force maxim, if genuine, argues against Mo's shape laws. Brute force often means a long straightforward function rather than three short indirections.

### What Mo could take

| idea | maps to | status |
|---|---|---|
| Treat the toolchain, not only the source, as the trust boundary; publish a bit-for-bit reproducible build of the Mo compiler | [[d30-supply-chain-security]] | strengthens Mo |
| Apply diverse double-compiling to the Zig/C path before claiming source-level evidence | [[d03-source-carries-its-evidence]] | new idea for Mo |
| Recipes (regenerated packages) answer the tarball-versus-repository gap that xz exploited | [[d34-packages-are-recipes]] | already in Mo |
| Unanimity rule for new features, with the delay cost accepted openly | [[q12-law-numbers]] | strengthens Mo |
| Expect a learning curve even with a small language; measure it in the control runs | [[d28-nothing-final-until-measured]] | strengthens Mo |

---

## 2. Dennis Ritchie — C and Unix

### Ethos in his own words

"C is quirky, flawed, and an enormous success." is the line usually attributed to this paper's abstract; the fetched body text did not surface it, so it is recorded here as n.a. rather than quoted. What the fetched text does say is plainer and more useful.

"At the time we did not put much weight on portability; interest in this arose later." ([The Development of the C Language, 1993](https://www.bell-labs.com/usr/dmr/www/chist.html))

"Other issues, particularly type safety and interface checking, did not seem as important then as they became later." ([The Development of the C Language](https://www.bell-labs.com/usr/dmr/www/chist.html))

"B can be thought of as C without types; more accurately, it is BCPL squeezed into 8K bytes of memory and filtered through Thompson's brain." ([The Development of the C Language](https://www.bell-labs.com/usr/dmr/www/chist.html))

"The central notion I captured from Algol was a type structure based on atomic types (including structures), composed into arrays, pointers (references), and functions (procedures)." ([The Development of the C Language](https://www.bell-labs.com/usr/dmr/www/chist.html))

"despite its frequent surface inconsistency, so colorfully annotated by Don Norman in his Datamation article [4] and despite its richness, UNIX is a simple coherent system that pushes a few good ideas and models to the limit." ([Reflections on Software Research, Turing lecture, 1983](http://rkka21.ru/docs/turing-award/dr1983e.pdf))

"Our intent was to create a pleasant computing environment for ourselves, and our hope was that others liked it." ([Reflections on Software Research](http://rkka21.ru/docs/turing-award/dr1983e.pdf))

"More than anything else, the greatest danger to good computer science research today may be excessive relevance." ([Reflections on Software Research](http://rkka21.ru/docs/turing-award/dr1983e.pdf))

### Defining decisions

Decision 1: add types to a typeless language, driven by hardware rather than theory. Reasoning: "For all these reasons, it seemed that a typing scheme was necessary to cope with characters and byte addressing, and to prepare for the coming floating-point hardware," and the array/pointer resolution "constituted the crucial jump in the evolutionary chain between typeless BCPL and typed C." ([The Development of the C Language](https://www.bell-labs.com/usr/dmr/www/chist.html)) How it played out: the same rule, that "values of array type are converted, when they appear in expressions, into pointers to the first of the objects making up the array" ([chist](https://www.bell-labs.com/usr/dmr/www/chist.html)), is the root of decades of buffer overflows. Ritchie himself flags it: "The other characteristic feature of C, its treatment of arrays, is more suspect on practical grounds, though it also has real virtues." ([chist](https://www.bell-labs.com/usr/dmr/www/chist.html)) Hoare, twenty years earlier, had already said what the cost would be; see section 5.

Decision 2: keep the compiler able to compete with assembly. Reasoning: "Thus the transition from B to C was contemporaneous with the creation of a compiler capable of producing programs fast and small enough to compete with assembly language." ([chist](https://www.bell-labs.com/usr/dmr/www/chist.html)) How it played out: C won the systems niche outright and is still the portability floor; Mo compiles to C for exactly that reason.

Decision 3: deliberately leave out support for programming in the large. Reasoning, stated as a retrospective criticism: "Chief among these is that the language and its generally-expected environment provide little help for writing very large systems." ([chist](https://www.bell-labs.com/usr/dmr/www/chist.html)) How it played out: Kernighan independently reached the same verdict — "I think that the real problem with C is that it doesn't give you enough mechanisms for structuring really big programs, for creating ``firewalls'' within programs so you can keep the various pieces apart." ([An Interview with Brian Kernighan, 2000](https://ioi.di.unimi.it/kernighan.php)) Pike's Go work is in a straight line from this complaint: "We also wanted to address the problem of 'programming in the large' head on." ([Less is exponentially more, 2012](https://commandcenter.blogspot.com/2012/06/less-is-exponentially-more.html))

Decision 4: standardise conservatively rather than redesign. Reasoning: "From the beginning, the X3J11 committee took a cautious, conservative view of language extensions," and "Thus, the Standard emerged more as a better, careful codification than a new invention." ([chist](https://www.bell-labs.com/usr/dmr/www/chist.html)) The one real change was typed parameters: "it incorporated the types of formal arguments in the type signature of a function, using syntax borrowed from C++." ([chist](https://www.bell-labs.com/usr/dmr/www/chist.html)) How it played out: prototypes closed a whole class of interface errors; the rest of C's unsafety was left in place because the committee's charter was codification, not repair.

Decision 5: accept a known precedence mistake rather than break code. Reasoning: "Today, it seems that it would have been preferable to move the relative precedences of & and ==, and thereby simplify a common C idiom: to test a masked value against another value, one must write if ((a&mask) == b) ..." ([chist](https://www.bell-labs.com/usr/dmr/www/chist.html)) How it played out: it is still there in 2026. Judgment: this is the cleanest small case study of Hoare's rule that an included feature can never be removed.

### Opinions that contradict Mo's current design

- Ritchie's stated design method is evolution under daily use by its authors, not specification-first design: "Our intent was to create a pleasant computing environment for ourselves." ([Reflections on Software Research](http://rkka21.ru/docs/turing-award/dr1983e.pdf)) Mo is designed spec-first, for a reader (the agent) who is not the author.
- Ritchie explicitly deprioritised type safety and interface checking at the moment of design because of the era's pressures ([chist](https://www.bell-labs.com/usr/dmr/www/chist.html)). Mo inverts that ordering entirely. The contradiction is historical rather than live, but it is a reminder that C's flaws were choices under constraint, not oversights.
- "The greatest danger to good computer science research today may be excessive relevance." ([Reflections on Software Research](http://rkka21.ru/docs/turing-award/dr1983e.pdf)) Mo's justification is almost entirely relevance: agent loops, compile latency, control runs. Judgment: Ritchie would ask what Mo is doing that is not simply downstream of a 2026 tooling fashion.

### What Mo could take

| idea | maps to | status |
|---|---|---|
| Name the thing the language will not help with, in the design doc, as Ritchie named "programming in the large" | [[d19-negative-space-is-the-contract]] | strengthens Mo |
| Keep the compile-to-C floor, justified as Ritchie justified it: compete with the layer below on speed and size | [[d24-compile-to-c-via-zig]] | already in Mo |
| Record the known-bad decisions you are keeping for compatibility, with the reason, as the & / == note does | [[d28-nothing-final-until-measured]] | new idea for Mo |
| C's array-to-pointer decay is the canonical case of a convenience that became a security class; Mo's no-aliasing rule is the counter-move | [[d10-immutable-by-default]] | already in Mo |
---

## 3. Brian Kernighan — Unix philosophy, Software Tools, AWK, The Practice of Programming

### Ethos in his own words

"C is perhaps the best balance of expressiveness and efficiency that has ever been seen in programming languages." ([Interview with Brian Kernighan, Linux Journal, 2003](https://www.linuxjournal.com/article/7035))

"C is the best balance I've ever seen between power and expressiveness." ([An Interview with Brian Kernighan, 2000](https://ioi.di.unimi.it/kernighan.php))

"I think that the real problem with C is that it doesn't give you enough mechanisms for structuring really big programs, for creating ``firewalls'' within programs so you can keep the various pieces apart." ([Interview, 2000](https://ioi.di.unimi.it/kernighan.php))

"C++ I think is basically too big a language, although there's a reason for almost everything that's in it." ([Interview, 2000](https://ioi.di.unimi.it/kernighan.php))

"The languages that succeed are very pragmatic, and are very often fairly dirty because they try to solve real problems." ([Interview, 2000](https://ioi.di.unimi.it/kernighan.php))

"There are only two real problems in computing: computers are too hard to use and too hard to program." ([Linux Journal, 2003](https://www.linuxjournal.com/article/7035))

"The purpose of style is to make the code easy to read for yourself and others, and good style is crucial to good programming." ([The Practice of Programming, Kernighan and Pike](https://theswissbay.ch/pdf/Gentoomen%20Library/Software%20Engineering/B.W.Kernighan,%20R.Pike%20-%20The%20Practice%20of%20Programming.pdf))

"Code should be clear and simple-straightforward logic, natural expression, conventional language use, meaningful names, neat formatting, helpful comments-and it should avoid clever tricks and unusual constructions." ([The Practice of Programming](https://theswissbay.ch/pdf/Gentoomen%20Library/Software%20Engineering/B.W.Kernighan,%20R.Pike%20-%20The%20Practice%20of%20Programming.pdf))

The four principles of the book are stated as: "These include simpliciry, which keeps programs short and manageable; clariry, which makes sure they are easy to understand, for people as well as machines; generality, which means they work well in a broad range of situations and adapt well as new situations arise; and automation, which lets the machine do the work for us, freeing us from mundane tasks." ([The Practice of Programming](https://theswissbay.ch/pdf/Gentoomen%20Library/Software%20Engineering/B.W.Kernighan,%20R.Pike%20-%20The%20Practice%20of%20Programming.pdf) — OCR of the scanned page renders "simplicity" and "clarity" with typos; the wording is otherwise verbatim.)

### Defining decisions

Decision 1: attack Pascal in print, on the specific ground that a teaching language cannot be scaled into a production language by goodwill. Reasoning: "Comparing C and Pascal is rather like comparing a Learjet to a Piper Cub - one is meant for getting something done while the other is meant for learning - so such comparisons tend to be somewhat farfetched." ([Why Pascal is Not My Favorite Programming Language, 1981](https://www.lysator.liu.se/c/bwk-on-pascal.html)) And on the fixed-size-array flaw: "This botch is the biggest single problem with Pascal," with "I believe that if it could be fixed, the language would be an order of magnitude more usable." ([Why Pascal is Not My Favorite Programming Language](https://www.lysator.liu.se/c/bwk-on-pascal.html)) How it played out: Wirth's own successors (Modula-2, Oberon) kept shrinking and kept fixing; Kernighan's verdict — "I feel that it is a mistake to use Pascal for anything much beyond its original target" ([same](https://www.lysator.liu.se/c/bwk-on-pascal.html)) — matched the market outcome.

Decision 2: name the specific things a safe language must not make impossible. Kernighan's list against Pascal is a list of escape hatches: "Pascal has no such storage class" (static/own variables), "There is no guaranteed order of evaluation of the logical operators 'and' and 'or' - nothing like && and || in C," "Pascal's built-in I/O has a deservedly bad reputation," and the summary judgement, "There is no escape." ([Why Pascal is Not My Favorite Programming Language](https://www.lysator.liu.se/c/bwk-on-pascal.html)) How it played out: this is the single most-cited argument in favour of a deliberate escape hatch in strict languages, and it is directly relevant to Mo's [[q16-escape-hatch]] question. Judgment: Kernighan's complaint is not about strictness; it is about strictness with no way to express a legitimate program that the rule did not anticipate.

Decision 3: teach languages by writing complete runnable programs, not fragments. Reasoning, from his Limbo tutorial: "The examples in this section are each complete, in the sense that they will run as presented; I have tried to avoid code fragments that merely illustrate syntax." ([A Descent into Limbo](https://www.vitanuova.com/inferno/papers/descent.html)) How it played out: this is the tutorial style of K&R and of most language documentation since. For Mo, whose primary reader is an agent trained on documentation, the choice of complete programs over fragments is a measurable decision, not an aesthetic.

Decision 4: judge a language by what it removes as much as what it adds. In Limbo he lists the removals approvingly: "Pointers, created with ref, are very restricted and there is no & (address of) operator; there is no address arithmetic and pointers can only point to adt objects," "There are no implicit coercions between types, and only a handful of explicit casts," "There is no preprocessor," and on abstract data types, "an adt does not provide information hiding (all member names are visible if the adt itself is visible), does not support inheritance, and has no constructors, destructors or overloaded method names." ([A Descent into Limbo](https://www.vitanuova.com/inferno/papers/descent.html)) How it played out: Limbo's removals became Go's removals; its channels became Go's channels. Kernighan documents the lineage himself: "Limbo borrows from, among other things, C (expression syntax and control flow), Pascal (declarations), Winterbottom's Alef (abstract data types and channels), and Hoare's CSP and Pike's Newsqueak (processes)." ([A Descent into Limbo](https://www.vitanuova.com/inferno/papers/descent.html))

Decision 5: keep the Unicode failure mode visible in a teaching text. "Warning: The word count program above tacitly assumes that its input is in the ASCII subset of Unicode, since it reads input one byte at a time instead of one Unicode character at a time. If the input contains any multi-byte Unicode characters, this code is plain wrong." ([A Descent into Limbo](https://www.vitanuova.com/inferno/papers/descent.html)) Judgment: this is a model for Mo's diagnostics culture — say the wrong thing is wrong, in the tutorial, at the point where a reader would copy it.

### What he thinks makes a language teachable

Kernighan separates teaching from production and refuses to let universities become trade schools: "I don't think universities should be in the business of teaching things that you should learn at a trade school," and the role is "to help students understand the issues and trade-offs that go into families of languages, like C, C++ and Java, and how those relate to languages which slice it in a different way, like functional languages." ([Interview, 2000](https://ioi.di.unimi.it/kernighan.php)) He is candid about functional languages not winning: "I honestly don't know why the functional languages don't succeed." ([Interview, 2000](https://ioi.di.unimi.it/kernighan.php))

### Opinions that contradict Mo's current design

- "There is no escape." ([Why Pascal is Not My Favorite Programming Language](https://www.lysator.liu.se/c/bwk-on-pascal.html)) Mo's laws are compiler errors with no override in the language. Kernighan's Pascal essay is the canonical demonstration that this design fails not on the intended programs but on the unanticipated ones.
- "The languages that succeed are very pragmatic, and are very often fairly dirty because they try to solve real problems." ([Interview, 2000](https://ioi.di.unimi.it/kernighan.php)) Mo is deliberately clean. Kernighan's historical claim is that clean loses.
- Judgment: Kernighan's praise of C is praise for expressiveness per unit of machinery, which is a different axis from Mo's "spec altitude" axis. Mo trades reader expressiveness for reader auditability. That trade needs its own evidence, and Kernighan supplies none in its favour.

### What Mo could take

| idea | maps to | status |
|---|---|---|
| Simplicity, clarity, generality, automation as the four judging criteria for every law | [[d04-style-rules-become-laws]] | strengthens Mo |
| Pascal's "no escape" failure as the strongest argument for a narrow, auditable escape hatch | [[q16-escape-hatch]] | contradicts Mo |
| Every doc example is a complete runnable program, because the main reader is a model | [[d01-agents-write-the-code]] | new idea for Mo |
| Show the wrong-but-plausible version and label it wrong, in the tutorial | [[q09-compiler-diagnostics]] | new idea for Mo |
| Limbo's removals (no address arithmetic, no coercions, no preprocessor, no inheritance) as a precedent list | [[d06-never-oop]] | already in Mo |

---

## 4. Rob Pike — Newsqueak, Limbo, Go, gofmt, UTF-8

### Ethos in his own words

"The answer can be summarized like this: Do you think less is more, or less is less?" ([Less is exponentially more, 2012](https://commandcenter.blogspot.com/2012/06/less-is-exponentially-more.html))

"Less can be more. The better you understand, the pithier you can be." ([Less is exponentially more](https://commandcenter.blogspot.com/2012/06/less-is-exponentially-more.html))

"And yet, with that long list of simplifications and missing pieces, Go is, I believe, more expressive than C or C++. Less can be more." ([Less is exponentially more](https://commandcenter.blogspot.com/2012/06/less-is-exponentially-more.html))

"If C++ and Java are about type hierarchies and the taxonomy of types, Go is about composition." ([Less is exponentially more](https://commandcenter.blogspot.com/2012/06/less-is-exponentially-more.html))

"Type hierarchies are just taxonomy." ([Less is exponentially more](https://commandcenter.blogspot.com/2012/06/less-is-exponentially-more.html))

"Go's purpose is therefore not to do research into programming language design; it is to improve the working environment for its designers and their coworkers." ([Go at Google: Language Design in the Service of Software Engineering, 2012](https://go.dev/talks/2012/splash.article))

"Dependency hygiene trumps code reuse." ([Go at Google](https://go.dev/talks/2012/splash.article))

"Features add complexity. We want simplicity." and "Features hurt readability. We want readability." ([Simplicity is Complicated, dotGo 2015](https://go.dev/talks/2015/simplicity-is-complicated.slide))

"Simplicity is complicated but the clarity is worth the fight." ([Simplicity is Complicated](https://go.dev/talks/2015/simplicity-is-complicated.slide))

Go proverbs, verbatim from the page that collects Pike's Gopherfest SV 2015 talk: "Don't communicate by sharing memory, share memory by communicating."; "Concurrency is not parallelism."; "The bigger the interface, the weaker the abstraction."; "Make the zero value useful."; "A little copying is better than a little dependency."; "Clear is better than clever."; "Errors are values."; "Don't just check errors, handle them gracefully."; "Gofmt's style is no one's favorite, yet gofmt is everyone's favorite."; "Don't panic." ([Go Proverbs](https://go-proverbs.github.io/))

Pike's numbered rules of programming, as quoted from his Notes on C Programming: "Rule 1. You can't tell where a program is going to spend its time."; "Rule 2. Measure."; "Rule 3. Fancy algorithms are slow when n is small, and n is usually small."; "Rule 4. Fancy algorithms are buggier than simple ones, and they're much harder to implement. Use simple algorithms as well as simple data structures."; "Rule 5. Data dominates. If you've chosen the right data structures and organized things well, the algorithms will almost always be self-evident."; "Rule 6. There is no Rule 6." ([reproduced in The Art of Unix Programming](http://www.catb.org/esr/writings/taoup/html/ch01s06.html) — secondary reproduction of Pike's text)

### Defining decisions

Decision 1: machine-formatted source, no options. Reasoning: "From the beginning of the project, we intended Go programs to be formatted by machine, eliminating an entire class of argument between programmers: how do I lay out my code?" and "Time not spent on formatting is time saved." ([Go at Google](https://go.dev/talks/2012/splash.article)) The no-options part is stated by the Go team on the tracker: "It is an intentional design choice that there are no configuration options for gofmt," with the rationale "The benefit of eliminating bike shed discussion about formatting choices is considered to be more important than the cost of not permitting people to use their preferred style." ([golang/go issue 40028, Ian Lance Taylor, 2020](https://github.com/golang/go/issues/40028)) How it played out: the unexpected dividend was refactoring. "The program works by parsing the source code and reformatting it from the parse tree itself. This makes it possible to edit the parse tree before formatting it, so a suite of automatic refactoring tools sprang up." ([Go at Google](https://go.dev/talks/2012/splash.article)) One concrete result: "The entire Go source tree was updated to use this default with the single command: gofmt -r 'a[b:len(a)] -> a[b:]'" ([Go at Google](https://go.dev/talks/2012/splash.article)). Judgment: this is the strongest empirical support in the whole dossier for Mo's one-shape formatter and for [[d29-edit-by-declaration-id]] — canonical form is what makes mechanical edits safe.

Decision 2: make unused dependencies a compile error, not a warning. Reasoning: "The first step to making Go scale, dependency-wise, is that the language defines that unused dependencies are a compile-time error (not a warning, an error)." ([Go at Google](https://go.dev/talks/2012/splash.article)) The motivating data: "By the time the #includes had been expanded, over 8 gigabytes were being delivered to the input of the compiler, a blow-up of 2000 bytes for every C++ source byte." ([Go at Google](https://go.dev/talks/2012/splash.article)) How it played out: Go builds are fast; the rule is also the most-complained-about beginner friction in Go. It is the direct ancestor of Mo's "no warnings, only errors."

Decision 3: leave generics out at v1. Reasoning at the time: Pike's dismissal of the demand — "Early in the rollout of Go I was told by someone that he could not imagine working in a language without generic types. As I have reported elsewhere, I found that an odd remark," and "I spend very little of my programming time struggling with those issues, even in languages without generic types." ([Less is exponentially more](https://commandcenter.blogspot.com/2012/06/less-is-exponentially-more.html)) How it played out: Go reversed. Ian Lance Taylor, arguing for generics in 2019: "In three years of Go surveys, lack of generics has always been listed as one of the top three problems to fix in the language," and "What some people new to Go find surprising is that there is no way to write a simple Reverse function that works for a slice of any type." ([Why Generics?, go.dev blog, 2019](https://go.dev/blog/why-generics)) The constraint on the fix was Pike-shaped: "We should add as few new concepts to the language as possible," and "generics can bring a significant benefit to the language, but they are only worth doing if Go still feels like Go." ([Why Generics?](https://go.dev/blog/why-generics)) Judgment: twelve years of "no" followed by a careful "yes" cost Go a generation of library design. Mo ships generics with bounds from the start, which is the corrected version of this decision.

Decision 4: explicit error values, no exceptions — then close the question permanently. Original reasoning: "Explicit error checking forces the programmer to think about errors—and deal with them—when they arise." ([Go at Google](https://go.dev/talks/2012/splash.article)) The 2025 close-out, by Griesemer for the Go team: "None of the error handling proposals reached anything close to a consensus, so they were all declined," "If Go had introduced specific syntactic sugar for error handling early on, few would argue over it today. But we are 15 years down the road, the opportunity has passed," and "For the foreseeable future, the Go team will stop pursuing syntactic language changes for error handling." ([go.dev blog, 3 June 2025](https://go.dev/blog/error-syntax)) The admission of cost: "Lack of better error handling support remains the top complaint in our user surveys." ([go.dev blog](https://go.dev/blog/error-syntax)) And the engineering reason that matters for Mo: "When debugging error handling code, being able to quickly add a println or have a dedicated line or source location for setting a breakpoint in a debugger is helpful." ([go.dev blog](https://go.dev/blog/error-syntax))

Decision 5: concurrency as composition, from the Newsqueak/CSP line. "The technical one is first-class support for concurrent computation." ([Rob Pike interview, Evrone](https://evrone.com/blog/rob-pike-interview)) The distinction he insisted on: "In programming, concurrency is the composition of independently executing processes, while parallelism is the simultaneous execution of (possibly related) computations," "Concurrency is about dealing with lots of things at once," "Parallelism is about doing lots of things at once." ([Concurrency is not parallelism, go.dev blog by Andrew Gerrand summarising Pike's Waza talk, 2013](https://go.dev/blog/waza-talk)) On limits: "Go enables simple, safe concurrent programming but does not forbid bad programming." ([Go at Google](https://go.dev/talks/2012/splash.article)) Judgment: that last sentence is where Mo departs from Go on purpose — Mo forbids shared mutable state rather than merely discouraging it.

Decision 6: freeze the language. "As of Go 1, the language is fixed," and "Adding features to Go would not make it better, just bigger." ([Simplicity is Complicated](https://go.dev/talks/2015/simplicity-is-complicated.slide)) Pike names the compatibility promise as the political success of the project: "The political success was the firm promise made about compatibility for Go version 1." ([Evrone interview](https://evrone.com/blog/rob-pike-interview))

### Opinions that contradict Mo's current design

- Pike's type stance is lukewarm in both directions: "I am a big fan of static typing because of the stability and safety it brings. I am a big fan of dynamic typing because of the fun and lightweight feel it brings. I am not a fan of type-driven programming, type hierarchies and classes and inheritance." ([Evrone interview](https://evrone.com/blog/rob-pike-interview)) Mo's refinement types on primitives and contract machinery are type-driven in a way Pike distrusts.
- "Go enables simple, safe concurrent programming but does not forbid bad programming." ([Go at Google](https://go.dev/talks/2012/splash.article)) Mo forbids. Pike's position is that forbidding does not scale to real programs.
- The 2025 error-syntax reasoning includes an argument against Mo's no-log-statements rule: debugging benefits from "being able to quickly add a println or have a dedicated line or source location for setting a breakpoint" ([go.dev blog](https://go.dev/blog/error-syntax)). Mo removes print-style debugging and replaces it with runtime tracing; that substitution has not been measured.
- Judgment: Pike's generics reversal is the best available evidence against Mo's confidence in its own omissions. The feature the designers do not personally need is the feature the users need most.

### What Mo could take

| idea | maps to | status |
|---|---|---|
| Canonical machine formatting is what makes mechanical refactors and agent edits safe | [[d29-edit-by-declaration-id]] | already in Mo |
| A gofmt-style rewrite flag (mo fix -r pattern) so laws can be enforced by rewriting, not only by rejecting | [[q09-compiler-diagnostics]] | new idea for Mo |
| Unused dependency = error, not warning, as the scaling rule that pays for compile speed | [[d23-compile-speed-first-class]] | already in Mo |
| The generics reversal: publish what Mo is leaving out and what evidence would change it | [[d28-nothing-final-until-measured]] | strengthens Mo |
| Go's own reason for keeping error handling verbose (debuggability, breakpoints, one line per failure) | [[d18-two-kinds-of-failure]] | strengthens Mo |
| Compatibility promise as a political instrument, published before v1 | [[d20-human-pulled-in-when-shape-changes]] | new idea for Mo |
---

## 5. Tony Hoare — CSP, Algol W, quicksort, Hoare logic

### Ethos in his own words

"I have regarded it as the highest goal of programming language design to enable good ideas to be elegantly expressed." ([The Emperor's Old Clothes, Turing lecture 1980](https://dl.acm.org/doi/pdf/10.1145/358549.358561))

"The price of reliability is the pursuit of the utmost simplicity. It is a price which the very rich find most hard to pay." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561))

"I conclude that there are two ways of constructing a software design: One way is to make it so simple that there are obviously no deficiencies and the other way is to make it so complicated that there are no obvious deficiencies. The first method is far more difficult." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561))

"A feature which is omitted can always be added later, when its design and its implications are well understood. A feature which is included before it is fully understood can never be removed later." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561))

"If our basic tool, the language in which we design and code our programs, is also complicated, the language itself becomes part of the problem rather than part of its solution." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561))

"I was eventually persuaded of the need to design programming notations so as to maximize the number of errors which cannot be made, or if made, can be reliably detected at compile time." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561))

"The readability of programs is immeasurably more important than their writeability." ([Hints on Programming Language Design, 1973](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf))

"Without simplicity, even the language designer himself cannot evaluate the consequences of his design decisions." ([Hints on Programming Language Design](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf))

"The previous two sections have argued that the objective criteria for good language design may be summarized in five catch phrases: simplicity, security, fast translation, efficient object code, and readability." ([Hints on Programming Language Design](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf))

"His task is consolidation, not innovation." ([Hints on Programming Language Design](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf), on the language designer)

### Defining decisions

Decision 1: define security as a property of the language, and check every array subscript. Stated reasoning: "The first principle was security: The principle that every syntactically incorrect program should be rejected by the compiler and that every syntactically correct program should give a result or an error message that was predictable and comprehensible in terms of the source language program itself. A consequence of this principle is that every occurrence of every subscript of every subscripted variable was on every occasion checked at run time against both the upper and the lower declared bounds of the array." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561)) How it played out, in his own account: "Many years later we asked our customers whether they wished us to provide an option to switch off these checks in the interests of efficiency on production runs. Unanimously, they urged us not to—they already knew how frequently subscript errors occur on production runs where failure to detect them could be disastrous. I note with fear and horror that even in 1980, language designers and users have not learned this lesson." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561)) And the sentence Mo should put on a wall: "In any respectable branch of engineering, failure to observe such elementary precautions would have long been against the law." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561))

Decision 2: budget the cost of safety instead of arguing about it. "The second principle in the design of the implementation was brevity of the object code produced by the compiler and compactness of run time working data," and "If as a result of care taken in implementation the available hardware remains more powerful than may seem necessary for a particular application, the applications programmer can nearly always take advantage of the extra capacity to increase the quality of his program, its simplicity, its ruggedness, and its reliability." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561)) The fourth principle was a hard compile-time constraint: "The fourth principle was that the compiler should use only a single pass." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561)) Judgment: Hoare's four principles are Mo's compile-speed-and-checks position, thirty years earlier and with the same ordering.

Decision 3: introduce the null reference. Stated reasoning and verdict, from the QCon London 2009 talk: "This led me to suggest that the null value is a member of every type, and a null check is required on every use of that reference variable, and it may be perhaps a billion dollar mistake." ([Null References: The Billion Dollar Mistake, InfoQ](https://www.infoq.com/presentations/Null-References-The-Billion-Dollar-Mistake-Tony-Hoare/)) In the same talk he puts responsibility on the designer: "A programming language designer should be responsible for the mistakes made by programmers using the language," and he generalises to C: "If the billion dollar mistake was the null pointer, the C gets function is a multi-billion dollar mistake that created the opportunity for malware and viruses to thrive." ([InfoQ](https://www.infoq.com/presentations/Null-References-The-Billion-Dollar-Mistake-Tony-Hoare/)) He also reports the customer behaviour that mirrors his Algol experience in reverse: "Fortran programmers preferred to risk disaster; in fact, experience disaster, rather than check subscripts." ([InfoQ](https://www.infoq.com/presentations/Null-References-The-Billion-Dollar-Mistake-Tony-Hoare/)) How it played out: option and result types are now standard in new languages; Mo has no nil at all, which is the maximal form of Hoare's own correction.

Decision 4: propose CSP — processes, no sharing, synchronous channels. Reasoning: "This paper suggests that input and output are basic primitives of programming and that parallel composition of communicating sequential processes is a fundamental program structuring method," and the mechanism: "Such communication occurs when one process names another as destination for output and the second process names the first as source for input," with "There is no automatic buffeting: In general, an input or output command is delayed until the other process is ready with the corresponding output or input." ([Communicating Sequential Processes, CACM 1978](https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf)) He also declared the boundaries: "It is consequently a rather static language: The text of a program determines a fixed upper bound on the number of processes operating concurrently; there is no recursion and no facility for process-valued variables," and "However, this paper also ignores many serious problems. The most serious is that it fails to suggest any proof method to assist in the development and verification of correct programs." ([CSP](https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf)) How it played out: Newsqueak, Alef, Limbo and Go took the channel model; Erlang took the isolation and failure-detection half with asynchronous messages instead (see section 8). Kernighan records the lineage explicitly for Limbo ([A Descent into Limbo](https://www.vitanuova.com/inferno/papers/descent.html)). Mo takes the isolation and mailbox half, with bounds, which is closer to Erlang than to CSP.

Decision 5: make verified code a research grand challenge rather than a product feature. "A verifying compiler uses mathematical and logical reasoning to check the correctness of the programs that it compiles," where "The criterion of correctness is specified by types, assertions, and other redundant annotations associated with the code of the program." ([The Verifying Compiler: A Grand Challenge for Computing Research, 2003](https://www.csl.sri.com/users/shankar/GC04/hoare-compiler.pdf)) His expectation about behaviour change: "Availability of a verifying compiler will encourage programmers to formulate assertions as specifications in advance of code, and many of them will be verifiable by automated or semi-automated mathematical techniques." ([The Verifying Compiler](https://www.csl.sri.com/users/shankar/GC04/hoare-compiler.pdf)) He also wanted it kept separate from the ordinary compiler's own correctness: "The verifying compiler does not itself have to be verified, though it would be desirable to do so, at least partially." ([The Verifying Compiler](https://www.csl.sri.com/users/shankar/GC04/hoare-compiler.pdf)) Judgment: that sentence is a direct precedent for Mo's [[d32-proving-is-a-separate-tool]].

Decision 6: warn, loudly and in public, against committee-grown languages. On Algol 68: "I gave desperate warnings against the obscurity, the complexity, and overambition of the new design, but my warnings went unheeded." On PL/I: "I knew that it would be impossible to write a wholly reliable compiler for a language of this complexity and impossible to write a wholly reliable program when the correctness of each part of the program depends on checking that every other part of the program has avoided all the traps and pitfalls of the language." On Ada: "If you want a language with no subsets, you must make it small." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561))

### Opinions that contradict Mo's current design

- "A good programming language should give assistance in expressing not only how the program is to run, but what it is intended to accomplish; and it should enable this to be expressed at various levels, from the overall strategy to the details of coding and data representation." ([Hints](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf)) Mo's spec altitude fixes one level (signatures, contracts, effects) as the human level. Hoare wants the expression of intent available at every level, including inside bodies.
- "The principles of modularity, or orthogonality, insofar as they contribute to overall simplicity, are an excellent means to an end; but as a substitute for simplicity they are very questionable." ([Hints](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf)) Mo has many orthogonal mechanisms: laws, capabilities, refinements, contracts, processes, recipes, tiers. Hoare's test is whether the whole is simple, not whether the parts are separable. Judgment: Mo currently fails that test on a count of concepts.
- "If anyone is to be allowed to introduce inefficiency it should be the user programmer, not the language designer." ([Hints](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf)) Mo's mandatory deadlines, mandatory Result consumption and mandatory fault injection move that choice to the designer.
- CSP as published is static and unbounded-free by construction: "there is no recursion and no facility for process-valued variables" ([CSP](https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf)). Mo's processes are dynamic and supervised. Hoare's own warning applies: the paper "fails to suggest any proof method." Mo's simulation tier is the substitute, and it is not a proof.

### What Mo could take

| idea | maps to | status |
|---|---|---|
| "A feature which is included before it is fully understood can never be removed later" as the admission test for every law | [[q12-law-numbers]] | strengthens Mo |
| Five criteria (simplicity, security, fast translation, efficient object code, readability) as the published scorecard | [[d23-compile-speed-first-class]] | strengthens Mo |
| Bounds checks always on, no option to disable, justified by his customer story | [[tiger-style-and-power-of-ten]] | already in Mo |
| Verifying compiler kept separate from the compiler, and not itself required to be verified | [[d32-proving-is-a-separate-tool]] | already in Mo |
| Intent expressible at several levels, not only at the signature | [[d02-spec-altitude]] | contradicts Mo |
| CSP's honest list of what the model does not solve, copied as a Mo "does not solve" section | [[d19-negative-space-is-the-contract]] | new idea for Mo |

---

## 6. Edsger Dijkstra — structured programming, guarded commands, THE

### Ethos in his own words

"Program testing can be used to show the presence of bugs, but never to show their absence!" ([Notes on Structured Programming, EWD249](https://www.cs.utexas.edu/~EWD/ewd02xx/EWD249.PDF))

"The art of programming is the art of organizing complexity, of mastering multitude and avoiding its bastard chaos as effectively as possible." ([EWD249](https://www.cs.utexas.edu/~EWD/ewd02xx/EWD249.PDF))

"The human mind is a very poor mechanism for dealing with complexity." ([EWD249](https://www.cs.utexas.edu/~EWD/ewd02xx/EWD249.PDF))

"The competent programmer is fully aware of the strictly limited size of his own skull; therefore he approaches the programming task in full humility, and among other things he avoids clever tricks like the plague." ([The Humble Programmer, EWD340, 1972](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html))

"Program testing can be a very effective way to show the presence of bugs, but is hopelessly inadequate for showing their absence." ([EWD340](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html))

"On the contrary: the programmer should let correctness proof and program grow hand in hand." ([EWD340](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html))

"The purpose of abstracting is not to be vague, but to create a new semantic level in which one can be absolutely precise." ([EWD340](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html))

"The tools we are trying to use and the language or notation we are using to express or record our thoughts, are the major factors determining what we can think or express at all!" ([EWD340](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html))

"I see a great future for very systematic and very modest programming languages." ([EWD340](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html))

"The tools we use have a profound (and devious!) influence on our thinking habits, and, therefore, on our thinking abilities." ([How do we tell truths that might hurt?, EWD498, 1975](https://www.cs.utexas.edu/~EWD/transcriptions/EWD04xx/EWD498.html))

"In the discrete world of computing, there is no meaningful metric in which "small" changes and "small" effects go hand in hand, and there never will be." ([On the cruelty of really teaching computing science, EWD1036, 1988](https://www.cs.utexas.edu/~EWD/transcriptions/EWD10xx/EWD1036.html))

"For instance, we know that for the sake of reliability and intellectual control we have to keep the design simple and disentangled, and in individual cases we have been remarkably successful, but we do not know how to reach simplicity in a systematic manner." ([Computing Science: Achievements and Challenges, EWD1284, 1999](https://www.cs.utexas.edu/~EWD/transcriptions/EWD12xx/EWD1284.html))

### Defining decisions

Decision 1: abolish the go to. Reasoning, in full: "My second remark is that our intellectual powers are rather geared to master static relations and that our powers to visualize processes evolving in time are relatively poorly developed. For that reason we should do (as wise programmers aware of our limitations) our utmost best to shorten the conceptual gap between the static program and the dynamic process, to make the correspondence between the program (spread out in text space) and the process (spread out in time) as trivial as possible." ([A Case against the GO TO Statement, EWD215, 1968](https://www.cs.utexas.edu/~EWD/transcriptions/EWD02xx/EWD215.html)) The mechanism: "The unbridled use of the go to statement has as an immediate consequence that it becomes terribly hard to find a meaningful set of coordinates in which to describe the process progress," and the verdict, "The go to statement as it stands is just too primitive, it is too much an invitation to make a mess of one's program." ([EWD215](https://www.cs.utexas.edu/~EWD/transcriptions/EWD02xx/EWD215.html)) He added a warning against mechanical compliance: "The exercise to translate an arbitrary flow diagram more or less mechanically into a jumpless one, however, is not to be recommended." ([EWD215](https://www.cs.utexas.edu/~EWD/transcriptions/EWD02xx/EWD215.html)) How it played out: structured control flow won completely. Judgment: the warning is the part Mo needs. A ban that is satisfied by mechanically rewriting a while loop as "for _ in 0..10_000" is exactly the mechanical translation Dijkstra said not to do — the text changes, the process does not, and the reader's coordinate system gets worse, not better.

Decision 2: require an independent coordinate system for reasoning about progress. "With the inclusion of procedures we can characterize the progress of the process via a sequence of textual indices, the length of this sequence being equal to the dynamic depth of procedure calling," and "The main point is that the values of these indices are outside programmer's control." ([EWD215](https://www.cs.utexas.edu/~EWD/transcriptions/EWD02xx/EWD215.html)) Judgment: Mo's deterministic simulation with seeded scheduling and a replayable message log is a modern instance of precisely this idea: a coordinate system for the dynamic process that the programmer cannot fake.

Decision 3: guarded commands and deliberate nondeterminism. Reasoning from the abstract: "So-called 'guarded commands' are introduced as a building block for alternative and repetitive constructs that allow non-deterministic program components for which at least the activity evoked, but possibly even the final state, is not necessarily uniquely determined by the initial state. For the formal derivation of programs expressed in terms of these constructs, a calculus will be shown." ([Guarded commands, nondeterminacy and formal derivation of programs, EWD472](https://www.cs.utexas.edu/~EWD/transcriptions/EWD04xx/EWD472.html)) Why nondeterminism helps: "The potential non-determinacy allows us to map otherwise (trivially) different programs on the same program text, a circumstance that seems largely responsible for the fact that now programs can be derived in a more systematic manner then before." ([EWD472](https://www.cs.utexas.edu/~EWD/transcriptions/EWD04xx/EWD472.html)) And what the calculus is for: "we do not present 'an algorithm' for the derivation of programs: we have used the term 'a calculus' for a formal discipline —a set of rules— such that, if applied successfully 1) it will have derived a correct program 2) it will tell us that we have reached such a goal." ([EWD472](https://www.cs.utexas.edu/~EWD/transcriptions/EWD04xx/EWD472.html)) How it played out: guarded commands are the ancestor of Erlang's receive, Go's select, and of Promela/TLA-style modelling; Hoare built CSP's alternatives on them, saying so directly: "When combined with a development of Dijkstra's guarded command, these concepts are surprisingly versatile." ([CSP](https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf))

Decision 4: teach programming as formula manipulation, not as an empirical craft. "It really helps to view a program as a formula," and "The statement that a given program meets a certain specification amounts to a statement about all computations that could take place under control of that given program." ([EWD1036](https://www.cs.utexas.edu/~EWD/transcriptions/EWD10xx/EWD1036.html)) His view of the discipline's alternative: "software engineering has accepted as its charter 'How to program if you cannot.'" ([EWD1036](https://www.cs.utexas.edu/~EWD/transcriptions/EWD10xx/EWD1036.html)) How it played out: as a teaching programme it lost; as a tooling programme it won slowly through model checkers, SMT solvers and proof assistants. Mo sits on the tooling side: contracts checked by tests at tier 2, proving pushed to a separate tool.

Decision 5: insist that elegance is an economic property, not decoration. "Simple, elegant solutions are more effective" is Wirth's phrasing (section 7); Dijkstra's own is the admission that we cannot systematise it: "we do not know how to reach simplicity in a systematic manner." ([EWD1284](https://www.cs.utexas.edu/~EWD/transcriptions/EWD12xx/EWD1284.html)) The widely quoted "elegance is not a dispensable luxury" sentence appears on EWD1284's landing summary in search results but was not located verbatim in the fetched transcription: n.a.

### Opinions that contradict Mo's current design

- Testing. Mo's verified line is computed from tests, contracts and properties at tier 2, plus seeded simulation at tier 3. Dijkstra: "Program testing can be used to show the presence of bugs, but never to show their absence!" ([EWD249](https://www.cs.utexas.edu/~EWD/ewd02xx/EWD249.PDF)) A verified marker derived from tests is, in his terms, a confidence marker, and Mo should not let its name suggest otherwise.
- Mechanical conformance. "The exercise to translate an arbitrary flow diagram more or less mechanically into a jumpless one, however, is not to be recommended." ([EWD215](https://www.cs.utexas.edu/~EWD/transcriptions/EWD02xx/EWD215.html)) This is the dispute-2 objection in Mo's own review, stated in 1968.
- Simplicity cannot be legislated: "we do not know how to reach simplicity in a systematic manner." ([EWD1284](https://www.cs.utexas.edu/~EWD/transcriptions/EWD12xx/EWD1284.html)) Mo's shape laws are an attempt to legislate it with numbers. Judgment: Dijkstra would accept them as a hypothesis to measure and reject them as a definition of simplicity.
- Discrete systems admit no continuity: "there is no meaningful metric in which 'small' changes and 'small' effects go hand in hand." ([EWD1036](https://www.cs.utexas.edu/~EWD/transcriptions/EWD10xx/EWD1036.html)) Mo's premise that bodies can change freely while signatures and contracts hold assumes small body edits have bounded consequences. That assumption is exactly what Dijkstra denies, unless the contract is strong enough to carry the whole obligation.

### What Mo could take

| idea | maps to | status |
|---|---|---|
| Rename or qualify the verified line so it never implies proof from tests | [[q08-verification-tiers]] | strengthens Mo |
| Bounded loops must produce a real termination argument, not a fictional constant | [[d19-negative-space-is-the-contract]] | contradicts Mo |
| Deterministic replay as the programmer-independent coordinate system for process progress | [[d21-autonomous-crash-fixing]] | already in Mo |
| Guarded-command style nondeterminism in the simulator: all admissible interleavings, not one seed | [[q08-verification-tiers]] | new idea for Mo |
| Contracts as the formula that carries the body's obligation, since small edits are not small | [[d02-spec-altitude]] | strengthens Mo |
---

## 7. Niklaus Wirth — Pascal, Modula-2, Oberon, Euler, Lilith

### Ethos in his own words

"Software is getting slower more rapidly than hardware becomes faster." ([A Plea for Lean Software, IEEE Computer, February 1995](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf))

"A primary cause of complexity is that software vendors uncritically adopt almost any feature that users want." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf))

"But it is not the inherent complexity that should concern us; it is the self-inflicted complexity." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf))

"Increasingly, people seem to misinterpret complexity as sophistication, which is baffling—the incomprehensible should cause suspicion rather than admiration." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf))

"Time pressure is probably the foremost reason behind the emergence of bulky software." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf))

"A programmer's competence should be judged by the ability to find simple solutions, certainly not by productivity measured in "number of lines ejected per day."" ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf))

"Actually, a language is not so much characterized by what it allows to program, but more so by what it prevents from being expressed." ([Good Ideas, Through the Looking Glass, 2005](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf))

"At the very least, their cost to the user must be known before a language is released, published, and propagated. This cost must be commensurate with the advantages gained by the feature." ([Good Ideas, Through the Looking Glass](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf))

"A chain is only as strong as its weakest member." ([Good Ideas, Through the Looking Glass](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf), on type-system loopholes)

"Simple, elegant solutions are more effective, but they are harder to find than complex ones, and they require more time, which we too often believe to be unaffordable." ([From Programming Language Design to Computer Construction, Turing lecture, CACM February 1985](https://www.arabou.edu.kw/faculties/computer/Documents/ReadingList/ITC/a1984-wirth.pdf))

"I never could separate the design of a language from its implementation, for a rigid definition without the feedback from the construction of its compiler would seem to me presumptuous and unprofessional." ([Turing lecture](https://www.arabou.edu.kw/faculties/computer/Documents/ReadingList/ITC/a1984-wirth.pdf))

"It is my belief that a tool should be commensurate with the product; it must be as simple as possible, but no simpler." ([Turing lecture](https://www.arabou.edu.kw/faculties/computer/Documents/ReadingList/ITC/a1984-wirth.pdf))

### Defining decisions

Decision 1: shrink the language on each iteration instead of growing it. Reasoning: "It led to Oberon, a language derived from Modula-2 by eliminating less essential features (like subrange and enumeration types) in addition to features known to be unsafe (like type transfer functions and variant records)." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf)) The general rule: "First, we concentrated on the essentials. We omitted anything that didn't fundamentally contribute to power and flexibility," and "Reducing complexity and size must be the goal in every step—in system specification, design, and in detailed programming." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf)) How it played out: measurably. "The Oberon core occupies fewer than 200 Kbytes, including editor and compiler," and the system was "Designed and implemented—from scratch—by two people within three years." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf)) In Project Oberon, the compiler figure is stated directly: "It now measures less than 2900 lines of program and compiles itself in about 3 seconds, which is proof of its efficiency," with "The entire system compiles itself in less than 10 seconds." ([Project Oberon, 2013 edition](https://people.inf.ethz.ch/~wirth/ProjectOberon/PO.System.pdf))

Decision 2: make self-compilation time the compiler's quality metric. Wirth's papers state the goal ("Speed is an essential and easily measurable criterion, and we believed the validity of the high-level language concept would be accepted in industry only if the performance penalty were to vanish or at least diminish," [Turing lecture](https://www.arabou.edu.kw/faculties/computer/Documents/ReadingList/ITC/a1984-wirth.pdf)); the explicit budget rule is recorded by Michael Franz, his student, as a second-hand account: "He used the compiler's self-compilation speed as a measure of the compiler's quality," and "Under the self-compilation speed benchmark, only those optimizations were allowed to be incorporated into a compiler that accelerated it by so much that the intrinsic cost of the new code addition was fully compensated." ([Oberon — The Overlooked Jewel, Michael Franz](https://dcreager.net/pdf/Franz2000.pdf) — secondary). Franz adds the consequence: "And true to his quest for simplicity, Wirth continuously kept improving his compilers according to this metric, even if this meant throwing away a perfectly workable, albeit more complex solution." ([Franz](https://dcreager.net/pdf/Franz2000.pdf)) Note for the record: a verbatim statement of the rule in Wirth's own words was not found in the sources fetched here; the primary sources give the goal, the secondary source gives the rule. How it played out: three-second self-compilation with runtime checks always generated: "Considered extravagant and hardly necessary only years ago, run-time checks are generated automatically. Due to their efficiency they hardly affect run-time speed, but are a great benefit to programmers." ([Project Oberon](https://people.inf.ethz.ch/~wirth/ProjectOberon/PO.System.pdf))

Decision 3: constrain manpower on purpose. "The constraint of severely limited manpower is sometimes an advantage." ([Turing lecture](https://www.arabou.edu.kw/faculties/computer/Documents/ReadingList/ITC/a1984-wirth.pdf)) In Project Oberon: "The consciously planned shortage of manpower enforced a single, but healthy, guideline: Concentrate on essential functions and omit embellishments that merely cater to established conventions and passing tastes," and "The primary goal, to personally obtain first-hand experience, and to reach full understanding of every detail, inherently determined our manpower: two part-time programmers." ([Project Oberon](https://people.inf.ethz.ch/~wirth/ProjectOberon/PO.System.pdf)) Judgment: this is the one Wirth lever Mo cannot pull. Agents remove the manpower constraint that produced Wirth's discipline; Mo's laws are an attempt to reinstate the constraint artificially.

Decision 4: single language, single system, no linker. "To keep the project within reasonable dimensions, I stuck to three dogmas: Aim for a single-processor computer to be operated by a single user and programmed in a single language." ([Turing lecture](https://www.arabou.edu.kw/faculties/computer/Documents/ReadingList/ITC/a1984-wirth.pdf)) In the system: "The system features no separate linker," and "Prelinked mega-files do not occur in the Oberon System, and every module is freely reusable." ([Project Oberon](https://people.inf.ethz.ch/~wirth/ProjectOberon/PO.System.pdf)) How it played out: Oberon stayed comprehensible and small; it never won a market. Franz's framing — "Oberon — The Overlooked Jewel" ([Franz](https://dcreager.net/pdf/Franz2000.pdf)) — is the epitaph.

Decision 5: charge every feature for its cost before shipping it. "At the very least, their cost to the user must be known before a language is released, published, and propagated. This cost must be commensurate with the advantages gained by the feature." ([Good Ideas, Through the Looking Glass](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf)) The corollary about over-general constructs: "The generality of Algol's for statement should have been a warning signal to all future designers to always keep the primary purpose of a construct in mind, and to be weary of exaggerated generality and complexity, which may easily become counter-productive." ([Good Ideas](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf)) And on measuring optimisations: "The main lesson here is that when implementing an optimization facility, one must first find out whether it is worth while." ([Good Ideas](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf))

Decision 6: refuse loopholes in the type system. "The loophole lets the programmer breach the type checking by the compiler," followed by "A chain is only as strong as its weakest member." ([Good Ideas](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf)) How it played out: the no-loophole position is now mainstream in safety-focused languages, and it is Mo's [[q16-escape-hatch]] position. Kernighan's Pascal critique is the counter-argument (section 3), and both men are partly right: Wirth removed the loophole and also removed the need for it by adding modules with typed interfaces.

### Opinions that contradict Mo's current design

- Wirth's method is build-the-whole-stack-yourself with two people; Mo's method is a design wiki plus a model. "I never could separate the design of a language from its implementation." ([Turing lecture](https://www.arabou.edu.kw/faculties/computer/Documents/ReadingList/ITC/a1984-wirth.pdf)) Mo has a Zig toolchain, so this is partly satisfied; the design wiki still runs ahead of the implementation.
- Feature cost accounting cuts against Mo's feature count. Mo has laws, capabilities, refinement types, contracts with never clauses, processes with bounded mailboxes, three verification tiers, recipes, declaration IDs and a separate prover. On Wirth's rule each must be charged to the user: "This cost must be commensurate with the advantages gained by the feature." ([Good Ideas](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf)) Judgment: Mo has not yet published that ledger.
- "Prolific programmers contribute to certain disaster." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf)) Mo's premise is a prolific programmer by construction: an agent writing nearly all the code. Mo's answer is that the laws bound the output; Wirth's claim is that volume itself is the pathology. This is the sharpest philosophical conflict in the dossier.

### What Mo could take

| idea | maps to | status |
|---|---|---|
| Self-compilation time as the compiler's headline quality metric, published per release | [[d23-compile-speed-first-class]] | strengthens Mo |
| A feature-cost ledger: every law and mechanism charged against compile time and reader effort | [[q12-law-numbers]] | new idea for Mo |
| Remove features between versions, not only add them; count removals as progress | [[d05-old-ideas-rethought-ai-first]] | new idea for Mo |
| Runtime checks always generated, never optional, because they are cheap | [[tiger-style-and-power-of-ten]] | already in Mo |
| No type-system loophole, but supply the mechanism that makes the loophole unnecessary | [[q16-escape-hatch]] | strengthens Mo |
| "A language is characterized by what it prevents from being expressed" as the wiki's framing sentence | [[d19-negative-space-is-the-contract]] | already in Mo |

---

## 8. Joe Armstrong — Erlang, OTP

### Ethos in his own words

"The central problem addressed by this thesis is the problem of constructing reliable systems from programs which may themselves contain errors." ([Making reliable distributed systems in the presence of software errors, PhD thesis, 2003](https://erlang.org/download/armstrong_thesis_2003.pdf))

"The essential problem that must be solved in making a fault-tolerant software system is therefore that of fault-isolation." ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf))

"Each independent activity should be performed in a completely isolated process. Such processes should share no data, and only communicate by message passing." ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf))

"In Concurrency Oriented Programming the concurrent structure of the program should follow the concurrent structure of the application." ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf))

"The structure of the program should exactly follow the structure of the problem." ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf))

The four slogans, verbatim: "Let some other process do the error recovery." / "If you can't do what you want to do, die." / "Let it crash." / "Do not program defensively." ([Thesis, section 4.3](https://erlang.org/download/armstrong_thesis_2003.pdf))

"exceptions occur when the run-time system does not know what to do." and "errors occur when the programmer doesn't know what to do." ([Thesis, section 4.4](https://erlang.org/download/armstrong_thesis_2003.pdf))

"You cannot build a fault-tolerant system if you only have one computer." ([A History of Erlang, HOPL III, 2007](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf))

"Erlang was designed for writing concurrent programs that "run forever."" ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf))

"Language features that were not used were removed." ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf))

### Defining decisions

Decision 1: six requirements as the specification of the runtime. Verbatim from the thesis: "R1. Concurrency — Our system must support concurrency. The computational effort needed to create or destroy a concurrent process should be very small, and there should be no penalty for creating large numbers of concurrent processes. R2. Error encapsulation — Errors occurring in one process must not be able to damage other processes in the system. R3. Fault detection — It must be possible to detect exceptions both locally (in the processes where the exception occurred,) and remotely (we should be able to detect that an exception has occurred in a non-local process). R4. Fault identification — We should be able to identify why an exception occurred. R5. Code upgrade — there should exist mechanisms to change code as it is executing, and without stopping the system. R6. Stable storage — we need to store data in a manner which survives a system crash." ([Thesis, section 2.5](https://erlang.org/download/armstrong_thesis_2003.pdf); the PDF's text layer renders some "ff" ligatures oddly, wording is otherwise exact) How it played out: R1–R4 are the BEAM's daily behaviour and are the part Mo copies. R5 and R6 are the two Mo has not answered. Judgment: this is the strongest single finding in this dossier for dispute 4 in mo-context — Armstrong lists stable storage as a requirement at the same level as isolation, precisely because supervision does not preserve state.

Decision 2: handle errors remotely, never locally. Reasoning: "The reason for coercing the hardware error to make it look like a software error is that we don't want to have two different methods for dealing with errors, one for software errors and the other for hardware errors. For reasons of conceptual integrity we want one uniform mechanism." ([Thesis, 4.3.1](https://erlang.org/download/armstrong_thesis_2003.pdf)) And: "This, combined with the extreme case of hardware error, and the failure of entire processors, leads to the idea of handling errors, not where they occurred, but at some other place in the system." ([Thesis, 4.3.1](https://erlang.org/download/armstrong_thesis_2003.pdf)) The benefits he lists: "The error-handling code and the code which has the error execute within different threads of control," and "The code which solves the problem is not cluttered up with the code which handles the exception." ([Thesis, 4.3.1](https://erlang.org/download/armstrong_thesis_2003.pdf)) How it played out: this is Mo's [[d18-two-kinds-of-failure]], almost line for line.

Decision 3: workers and supervisors as distinct roles. "One process, the worker process, does the job. Another process, the supervisor process. observes the worker. If an error occurs in the worker, the supervisor takes actions to correct the error," with "There is a clean separation of issues. The processes that are supposed to do things (the workers) do not have to worry about error handling," and "It often turns out that the error correcting code is generic, that is, generally applicable to many applications, whereas the worker code is more often application specific." ([Thesis, 4.3.2](https://erlang.org/download/armstrong_thesis_2003.pdf)) In HOPL III the productised form: "At the highest level of abstraction are a number of so-called "supervision trees"—the job of a node in the supervision tree is to monitor its children and restart them in the event of failure," and "These design patterns (called behaviors) are the result of many years' experience in building fault-tolerant systems." ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf))

Decision 4: no sharing, copy everything, accept the cost. "At an early stage we rejected any ideas of sharing resources between processes because of the difficulties of error handling. Programming with mutexes and shared resources was just too difficult to get right in a distributed system when errors occurred. We rapidly adopted a philosophy of message passing by copying and no sharing of data resources." ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf)) And the price, stated plainly: "In order to make systems reliable, we have to accept the extra cost of copying data between processes and always making sure that the processes have enough data to continue by themselves if other processes crash." ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf)) Note the second half of that sentence: enough data to continue by themselves. Judgment: that is the supervision-plus-state problem again, and Armstrong's answer is data placement, not restart policy.

Decision 5: dynamic typing, and repeated failure to retrofit types. "Erlang started life as a Prolog interpreter and has always had a dynamic type system, and for a long time various heroic attempts have been made to add a type system to Erlang." ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf)) The record: "The first attempt at a type system was due to an initiative taken by Phil Wadler," "Phil Wadler and Simon Marlow worked on a type system for over a year and the results were published," "The results of the project were somewhat disappointing," and "Several other projects to type check Erlang also failed to produce results that could be put into production." ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf)) The partial success: "It was not until the advent of the Dialyzer that realistic type analysis of Erlang programs became possible," and "The Dialyzer does not attempt to infer all types in a program, but any types it does infer are guaranteed to be correct, and in particular any type errors it finds are guaranteed to be errors." ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf)) Judgment: Mo takes the OTP shape and adds the static types Erlang never managed to retrofit. That combination is Mo's clearest claim to being more than a re-skin — and the Dialyzer's rule (only report what is certainly wrong) is a good model for Mo's diagnostics.

Decision 6: question modules themselves, late in life. "The basic idea is - do away with modules - all functions have unique distinct names - all functions have (lots of) meta data - all functions go into a global (searchable) Key-value database - we need letrec - contribution to open source can be as simple as contributing a single function - there are no "open source projects" - only "the open source Key-Value database of all functions" - Content is peer reviewed" ([Why do we need modules at all?, erlang-questions, 24 May 2011](http://erlang.org/pipermail/erlang-questions/2011-May/058768.html)) His complaint about the status quo: "It's very difficult to decide which module to put an individual function in," and "Erlang programs are composed of lots of small functions, the only place where modules seem useful is to hide a letrec." ([erlang-questions](http://erlang.org/pipermail/erlang-questions/2011-May/058768.html)) And the reframing: "The more I think about it the more I think program development should viewed as changing the state of a Key-Value database." ([erlang-questions](http://erlang.org/pipermail/erlang-questions/2011-May/058768.html)) Judgment: this is Mo's [[d29-edit-by-declaration-id]] proposed in 2011 — content-addressed, metadata-carrying, individually-reviewable declarations rather than files. Unison later built it; Mo has the sidecar version.

On "The Mess We're In" (Strange Loop 2014): no verbatim transcript from a primary source was reachable in this session, so no quotation is given: n.a. The talk is catalogued in public talk indexes ([awesome-talks listing](https://github.com/JanVanRyswyck/awesome-talks)) and secondary write-ups summarise its argument that software complexity has outrun our ability to understand it, but nothing here is quoted from it.

On later regrets: the widely circulated 2013 talk "26 Years with Erlang" is transcribed on Wikiquote, including "Shared memory is evil." and "Erlang was specifically designed for fault tolerance, it was not designed for anything else." ([Wikiquote transcription](https://en.wikiquote.org/wiki/Joe_Armstrong_(programmer))). Wikiquote is a secondary transcription and is flagged as such; treat these as indicative, not citable.

### Opinions that contradict Mo's current design

- Modules. Armstrong's late position is that modules are the wrong unit ([erlang-questions, 2011](http://erlang.org/pipermail/erlang-questions/2011-May/058768.html)). Mo keeps files with a 500-line law, which re-imposes exactly the placement problem he complains about: "It's very difficult to decide which module to put an individual function in."
- Types. Armstrong shipped and defended a dynamically typed language and watched multiple static-typing retrofits fail ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf)). Mo bets the other way, with contracts on top. The Erlang record says the combination is hard even with strong motivation and good people.
- Asynchronous, unreliable message passing is a stated COPL property: "Message passing is assumed to be unreliable with no guarantee of delivery." ([Thesis, 2.4.2](https://erlang.org/download/armstrong_thesis_2003.pdf)) Mo's bounded mailboxes with deadlines make delivery and backpressure part of the contract. That is a defensible improvement, but it is not Erlang, and blocking-on-full versus dropping is a semantics decision Mo must state.
- Stable storage as a first-class requirement (R6) is unanswered in Mo ([Thesis, 2.5](https://erlang.org/download/armstrong_thesis_2003.pdf)).

### What Mo could take

| idea | maps to | status |
|---|---|---|
| R6 stable storage as a named requirement, with a storage protocol distinct from supervision | [[state-model]] | contradicts Mo |
| R5 live code upgrade: say explicitly that Mo declines it, and why | [[d19-negative-space-is-the-contract]] | new idea for Mo |
| "Enough data to continue by themselves if other processes crash" as the restart-state rule | [[d14-processes-are-the-only-identity]] | strengthens Mo |
| Dialyzer's rule: only report what is certainly an error | [[q09-compiler-diagnostics]] | strengthens Mo |
| Functions as the unit of identity and review, not files | [[d29-edit-by-declaration-id]] | already in Mo |
| Error slogans as written law: let it crash, do not program defensively, let some other process fix it | [[d18-two-kinds-of-failure]] | already in Mo |
---

## Cross-cutting themes

### What all eight agree on

1. Simplicity is a reliability property, not taste. Hoare: "The price of reliability is the pursuit of the utmost simplicity." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561)) Wirth: "Reducing complexity and size must be the goal in every step." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf)) Pike: "Features add complexity. We want simplicity." ([Simplicity is Complicated](https://go.dev/talks/2015/simplicity-is-complicated.slide)) Ritchie: "UNIX is a simple coherent system that pushes a few good ideas and models to the limit." ([Turing lecture 1983](http://rkka21.ru/docs/turing-award/dr1983e.pdf)) Dijkstra: "The art of programming is the art of organizing complexity." ([EWD249](https://www.cs.utexas.edu/~EWD/ewd02xx/EWD249.PDF)) Thompson: C was built by a group where "all three of us had to be talked into every feature." ([InformationWeek Q&A](https://www.informationweek.com/software-services/q-a-ken-thompson-creator-of-unix)) Kernighan's four criteria begin with simplicity ([The Practice of Programming](https://theswissbay.ch/pdf/Gentoomen%20Library/Software%20Engineering/B.W.Kernighan,%20R.Pike%20-%20The%20Practice%20of%20Programming.pdf)). Armstrong: "Language features that were not used were removed." ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf))

2. Readability beats writeability. Hoare states it as an absolute: "The readability of programs is immeasurably more important than their writeability." ([Hints](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf)) Pike's proverb form: "Clear is better than clever." ([Go Proverbs](https://go-proverbs.github.io/)) Kernighan: "Code should be clear and simple … and it should avoid clever tricks." ([The Practice of Programming](https://theswissbay.ch/pdf/Gentoomen%20Library/Software%20Engineering/B.W.Kernighan,%20R.Pike%20-%20The%20Practice%20of%20Programming.pdf)) Dijkstra: the competent programmer "avoids clever tricks like the plague." ([EWD340](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html)) Judgment: Mo's spec-altitude bet is a readability bet with a new reader model — humans read contracts, agents read bodies. None of the eight had that split available, and none of their arguments transfers automatically to it.

3. The designer, not the user, owns the mistakes. Hoare at QCon: "A programming language designer should be responsible for the mistakes made by programmers using the language." ([InfoQ](https://www.infoq.com/presentations/Null-References-The-Billion-Dollar-Mistake-Tony-Hoare/)) Wirth: "At the very least, their cost to the user must be known before a language is released." ([Good Ideas](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf)) Dijkstra: "The tools we use have a profound (and devious!) influence on our thinking habits." ([EWD498](https://www.cs.utexas.edu/~EWD/transcriptions/EWD04xx/EWD498.html))

4. What a language forbids defines it. Wirth: "a language is not so much characterized by what it allows to program, but more so by what it prevents from being expressed." ([Good Ideas](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf)) Hoare's compile-time framing: "design programming notations so as to maximize the number of errors which cannot be made." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561)) Pike's removals list in Go, Kernighan's removals list in Limbo ([A Descent into Limbo](https://www.vitanuova.com/inferno/papers/descent.html)), Armstrong's rejection of sharing ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf)). This is Mo's negative-space doctrine with four independent endorsements.

5. Feature creep is the failure mode of success. Hoare on Algol 68, PL/I and Ada ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561)); Wirth on vendors adopting "almost any feature that users want" ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf)); Thompson on C++: "The three of us got together and decided that we hated C++." ([InformationWeek](https://www.informationweek.com/software-services/q-a-ken-thompson-creator-of-unix)); Kernighan: "C++ I think is basically too big a language" ([Interview, 2000](https://ioi.di.unimi.it/kernighan.php)); Pike: "Adding features to Go would not make it better, just bigger." ([Simplicity is Complicated](https://go.dev/talks/2015/simplicity-is-complicated.slide))

6. Isolation and failure detection beat local defence. Hoare's CSP primitives ([CSP](https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf)); Armstrong's four slogans ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf)); Pike's "Don't communicate by sharing memory, share memory by communicating." ([Go Proverbs](https://go-proverbs.github.io/))

### Where they disagree

| dispute | positions |
|---|---|
| Escape hatches | Kernighan: a strict language with no escape fails on unanticipated programs — "There is no escape." ([bwk on Pascal](https://www.lysator.liu.se/c/bwk-on-pascal.html)). Wirth: any loophole voids the guarantee — "A chain is only as strong as its weakest member." ([Good Ideas](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf)) |
| Clean versus dirty | Kernighan: "The languages that succeed are very pragmatic, and are very often fairly dirty" ([Interview, 2000](https://ioi.di.unimi.it/kernighan.php)). Dijkstra: "I see a great future for very systematic and very modest programming languages." ([EWD340](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html)) |
| Proof versus practice | Dijkstra: "let correctness proof and program grow hand in hand" ([EWD340](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html)). Pike: "Go's purpose is therefore not to do research into programming language design; it is to improve the working environment for its designers and their coworkers." ([Go at Google](https://go.dev/talks/2012/splash.article)) |
| Types | Pike: "I am not a fan of type-driven programming, type hierarchies and classes and inheritance." ([Evrone](https://evrone.com/blog/rob-pike-interview)) Armstrong shipped dynamic typing and watched retrofits fail ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf)). Hoare and Wirth want maximal compile-time rejection ([Emperor](https://dl.acm.org/doi/pdf/10.1145/358549.358561), [Good Ideas](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf)) |
| Where safety costs land | Hoare: "If anyone is to be allowed to introduce inefficiency it should be the user programmer, not the language designer." ([Hints](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf)) Wirth and Hoare-in-1980 both kept checks mandatory ([Project Oberon](https://people.inf.ethz.ch/~wirth/ProjectOberon/PO.System.pdf), [Emperor](https://dl.acm.org/doi/pdf/10.1145/358549.358561)) |
| Channel semantics | Hoare: synchronous, "There is no automatic buffeting" and a static process count ([CSP](https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf)). Armstrong: asynchronous and explicitly unreliable — "Message passing is assumed to be unreliable with no guarantee of delivery." ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf)) |
| Modules | Wirth built the typed module interface as the central abstraction ([Project Oberon](https://people.inf.ethz.ch/~wirth/ProjectOberon/PO.System.pdf)). Armstrong, 2011: "do away with modules - all functions have unique distinct names" ([erlang-questions](http://erlang.org/pipermail/erlang-questions/2011-May/058768.html)) |

### Warnings Mo is currently ignoring

1. Trust cannot be established from source. Thompson: "No amount of source-level verification or scrutiny will protect you from using untrusted code," and "The moral is obvious. You can't trust code that you did not totally create yourself." ([Reflections on Trusting Trust](https://dl.acm.org/doi/pdf/10.1145/358198.358210)) Mo's supply-chain story is source-first — recipes, readable dependencies, capability declarations — and compiles to C through Zig. The xz backdoor was delivered through build machinery rather than reviewed source ([Andres Freund, oss-security, 29 March 2024](https://www.openwall.com/lists/oss-security/2024/03/29/4)), and the community answers are reproducible builds ([reproducible-builds.org](https://reproducible-builds.org/)) and diverse double-compiling ([David A. Wheeler](https://dwheeler.com/trusting-trust/)). Mo needs a build-provenance and bootstrap story, not only a source-readability story.

2. A mechanical ban produces a mechanical dodge. Dijkstra: "The exercise to translate an arbitrary flow diagram more or less mechanically into a jumpless one, however, is not to be recommended." ([EWD215](https://www.cs.utexas.edu/~EWD/transcriptions/EWD02xx/EWD215.html)) Mo's while/loop ban invites for _ in 0..1_000_000, which satisfies the law and lies about the bound.

3. Tests never show absence. Dijkstra, twice, five years apart ([EWD249](https://www.cs.utexas.edu/~EWD/ewd02xx/EWD249.PDF), [EWD340](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html)). Mo's tier-2 verified line is derived from tests and contracts. Hoare's verifying-compiler paper is the right precedent for separating the two ([The Verifying Compiler](https://www.csl.sri.com/users/shankar/GC04/hoare-compiler.pdf)).

4. Features must be charged before release. Wirth: "their cost to the user must be known before a language is released" ([Good Ideas](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf)); Hoare: "A feature which is included before it is fully understood can never be removed later." ([Emperor](https://dl.acm.org/doi/pdf/10.1145/358549.358561)) Mo's mechanism count keeps rising with no published ledger.

5. Simplicity resists legislation. Dijkstra: "we do not know how to reach simplicity in a systematic manner." ([EWD1284](https://www.cs.utexas.edu/~EWD/transcriptions/EWD12xx/EWD1284.html)) Mo's 70/500/6/3/12 numbers are legislation. Wirth's alternative lever — a hard, published, measurable budget such as self-compilation time ([Project Oberon](https://people.inf.ethz.ch/~wirth/ProjectOberon/PO.System.pdf)) — constrains the same way without pretending the number defines simplicity.

6. Restart is not storage. Armstrong lists stable storage as requirement R6, alongside isolation and fault detection ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf)), and states the copying rule as "always making sure that the processes have enough data to continue by themselves if other processes crash." ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf)) Mo's supervisor-as-storage dispute is answered in the negative by the person who invented the supervisor.

7. Omitting what users need is expensive even when the designers are right about taste. Go's generics reversal is the documented case: "In three years of Go surveys, lack of generics has always been listed as one of the top three problems to fix in the language" ([Why Generics?](https://go.dev/blog/why-generics)), against Pike's earlier "I found that an odd remark" ([Less is exponentially more](https://commandcenter.blogspot.com/2012/06/less-is-exponentially-more.html)). And the 2025 error-syntax close-out shows the cost of a closed question: "Lack of better error handling support remains the top complaint in our user surveys." ([go.dev blog](https://go.dev/blog/error-syntax))

8. Volume itself is a pathology. Wirth: "Prolific programmers contribute to certain disaster," and a programmer's competence "should be judged by the ability to find simple solutions, certainly not by productivity measured in 'number of lines ejected per day.'" ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf)) Mo's round-3 control run reports Mo at 851 lines against Go's 1,387 and Python's 1,064, which is the right direction on Wirth's metric; the loop count (Mo 9 iterations against Go 2 and Python 1) is the wrong direction on Wirth's other metric, time to a simple solution.

### Source quality notes

Primary sources were strong for Hoare, Dijkstra, Wirth, Pike, Kernighan, Ritchie and Armstrong. Two gaps: Ken Thompson has written very little (the Turing lecture, two interviews, Go's design rationale written mostly by others), and no primary 2023–2026 statement by Thompson on xz or modern supply-chain attacks was located — recorded as n.a. Armstrong's "The Mess We're In" (Strange Loop 2014) has no primary verbatim transcript reachable here — recorded as n.a., with nothing quoted from it. Wirth's compile-speed budget rule appears in his student Michael Franz's account ([Oberon — The Overlooked Jewel](https://dcreager.net/pdf/Franz2000.pdf)) rather than in Wirth's own prose, and is flagged as secondary in section 7. Dijkstra's "elegance is not a dispensable luxury" sentence was not found verbatim in the fetched EWD1284 transcription and is not quoted. Two Wirth PDFs and two Bell Labs history pages were unreachable or robots-blocked; substitutes are cited where used.

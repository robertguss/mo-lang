---
source_url: https://arxiv.org/html/2407.06356
ingested: 2026-09-12
sha256: 3b2935868699cc6e393c1b9fa2553016b2911d4ed995f318dad6ebec85ee29ac
---
# Toward Programming Languages for Reasoning (arXiv 2407.06356) — sections 5.6 to 8 (excerpt)

From a reasoning perspective having builtin validation operators ensures that every application will have the same look and semantics around assertions. It also gives the compiler and runtime direct knowledge of these special operations for example an optimizer can move them off the hot path aggressively, do short circuit evaluation of any message or line number computations, and, if they are disabled, can easily remove all of the dead code. In Bosque we use this awareness along with a new level, safety, that we ensure is always checked – e.g. the compiler is never allowed (optbug, ) to optimize it out!

#### Assert/Pre/Post:

The first form of validation is a classic conditional assert statement that can be used to place ad-hoc checks in a block of code. Bosque also supports pre/post conditions on functions and methods. These features allow developers to insert, explicit, information on expectations/assumptions for any bit of code or invocation.

#### Invariants and Validates:

The ability to explicitly state data invariants is one of the most powerful validation features in the Bosque language. These invariants allow a developer to state a property in a single location – this property ensures that at every creation site it must be preserved and provides a guarantee for every use of the type in a program. An example invariant is seen in the binary-tree example.

Ingesting data from external sources, such as command line args, network data, file reads, etc., is a critical task. Writing code to validate data, even structured data in JSON or XML form, is a tedious and error prone task (restler, ). Errors in this code are amplified as they open opportunities for external, and potentially malicious, sources to directly interact with the application.

By default Bosque checks all active invariants whenever an value is constructed. These are generally not as extensive as would be needed to fully validate untrusted inputs. Thus, Bosque provides a validate keyword that allows the specification of checks that must be run on eternal inputs. When compiling Bosque to executable code these validate checks are combined with the invariants in a special function that the host can use to create values from untrusted external data sources.

Figure 4 shows code from a sample trading application provided by Morgan Stanley that was ported to Bosque (see Section 7). In this code there are several invariants and external validations on the SaleInfo type. The check available >= 0I is performed everytime an SaleInfo value is created. The invariant startAvailable >= 0I is marked as test so it is only enabled when running the code in a test build.

The two validate checks are too expensive to run on every internal operation but if we received a JSON value encoding this info from, say, a HTTP request from a 3rd party we definitely want to check that the data is well formed and consistent with our requirements (we can also use these for static verification).

#### Levels:

The validate feature is a special, and very important, case of the general problem of balancing checking useful properties against the cost of running these checks. To support the ability to utilize these specification features without concern about how they will impact the performance end-users experience Bosque allows any use of a validation annotation to be pre-fixed with a level, spec, debug, test, release, or safety.

The debug, test, release levels are useful for controlling which checks are run dynamically under which conditions. The spec level is useful for checks which would always be infeasible to check at runtime but which are useful for documentation, static analysis tools, and sampling based checking if a program is run in debug build mode. The safety level is for checks that a developer wants to run, even if they can be proven to always hold! This counter-intuitive feature is to ensure that a compiler will never eliminate tests that are critical to data integrity and may still be possible due to hardware or other failure modes.

⬇

 entity SaleOrder { 

 field id: StringOf< ValidID>; 

 field quantity: BigInt; 

 } 

 

 entity SaleInfo { 

 field available: BigInt; 

 field startAvailable: BigInt; 

 field orders: List< SaleOrder>; 

 

 //check sanity on every operation 

 invariant available >= 0 I; 

 invariant test startAvailable >= 0 I; 

 

 //too expensive on every change 

 //but *must* check on untrusted inputs 

 validate orders. unique(pred(a, b) => a. id !== b. id); 

 validate startAvailable - orders. sumOf< USD>(fn(a) => a. quantity) == available; 

 } 

Figure 4. Declarations from Sample Trading App

### 5.7. By-Ref Methods

As very common task is sequentially processing data with an environment of some sort. This can be clumsy to do manually, requiring manual packing and unpacking of env/value results, and the common functional solution of introducing monadic features clashes with our desire to keep behavior syntactically explicit. So, Bosque introduces the concept of ref methods. These are explicitly tagged at both def and call sites and manage the update of the receiver variable with the new state automatically.

In the following example the Counter is initialized to $0⁢n0𝑛0n0 italic_n$ and at each ref method invoke the receiver variable is updated with the result of the this value in the called method as well as assigning the result value. The statement this.{ctr = $ctr + 1n}; updates the value of this with the new ctr value. Any calls to the generateNextID are required to be top-level (not nested in other expressions) and annotated with a ref attribute. If either of these conditions are not satisfied the type-checker will reject the code.

 entity Counter { 

 field ctr: Nat; 

 function create(): Counter { 

 return Counter{0 n}; 

 } 

 method ref generateNextID(): Nat { 

 let id = this. ctr; 

 this.{ ctr = $ctr + 1 n}; 

 return id; 

 } 

 } 

 var ctr = Counter:: create(); //create a Counter 

 //id1 is 0 -- ctr is updated 

 let id1 = ref ctr. generateNextID(); 

 //id2 is 1 -- ctr is updated again 

 let id2 = ref ctr. generateNextID(); 

### 5.8. Recursion

Complex recursive control flows obfuscate the intent and hinder automated analysis and tooling. Thus, Bosque is designed to encourage limited uses of recursion, increase the clarity of the recursive structure, and enable compilers/runtimes to avoid stack related issues (codecomplete, ). To accomplish these goals Bosque borrows from the design of the async/ await syntax and semantics (asyncawait, ) which is used to add structured asynchronous execution to a language. In this design the async/ await keywords are used to explicitly identify functions that are asynchronous and when these functions are invoked.

The Bosque language takes a similar approach by introducing the recursive keyword which is used at both declaration sites to indicate a function/method is recursive and again at the call site so to affirm that the caller is aware of the recursive nature of the call. This feature is used in the binary-tree example when implementing the has method. This method is declared as recursive and later in the body at the callsite tchild.has[recursive](x) the call is explicitly annotated as being potentially recursive.

In Bosque the type-checker will process the call-graph for cycles and flag all caller-callee relations inside the same cycle as requiring both annotations at the declaration and call-site. Thus, mutually recursive calls will require annotations on declarations and, recursive, call-sites as well. These annotations primarily serve to make the, otherwise, implicitly recursive nature of these calls explicit in the code syntax. This provides clarity to the developer on which calls may involve recursion so they are not caught off-guard by the re-entrant nature of the code. This information also provides the compiler with the opportunity to convert an stack based call into a CPS form to avoid possible stack-overflows or enable static stack size computation for small-stacks. The combination of explicit demarcation of recursive execution along with the ability to place strong pre/post conditions on these calls serve as limits on the complexity that recursion can introduce when reasoning about a block of code while still allowing recursion as an option for when functors cannot (or cannot reasonably) be used to express a computation.

## 6. Simplicity and Clarity

Given the design of the core IR (Section 4) and the surface language (Section 5) this section looks at how they resolve the challenges outlined in Section 2 for each of the agents.

#### Immutable State and Local Reasoning:

The use of immutable value semantics and restrictions on exposing memory/object identity via equality operations ensures that the Bosque language is referentially transparent. As a result reasoning about the effects of a statement in general, and function/method calls in particular, can be done independently of the external context and using purely monotone reasoning. Specifically, no property that holds before some operation can be invalidated by the effect of the operation and the only parts of the program state that influence the operation are the argument values.

#### Explicit Behavior:

The lifting of implicit information to a textually explicit form with typedecls, explicit flow typing, and restricted lambda syntax ensure that the intent of blocks of code can be largely understood from their syntax. The addition of explicit support for pre/ post, assert, and invariant declaration syntax lets us lift, otherwise diffuse and implicit information, into an explicit form that can be easily discovered. These features ensure that code can be reasoned about, primarily, by looking at the text and explicit declarations without the need to do extensive simulation of behavior, like a type-checking algorithm, a mutability check, or searching a codebase for diffuse information e.g. every location a given type is constructed in the application.

#### Declarative Collection Processing and Recursion:

The elimination of loops in favor of collection functors eliminates a major source of difficulty for symbolic analysis tooling. They also enhance the readability of the code by providing explicit and declarative ways of expressing operations on collections. The addition of explicit recursive annotations provides a simple way to identify recursive calls to avoid unexpected reentrancy issues and as a way to explicitly identify these calls for specialized processing when needed.

#### Fully Deterministic Behavior:

Exhaustively specifying the semantics of each operation, including canonical orderings for associative containers, sort stability, and evaluation orders gives Bosque code a powerful property. Specifically, for any input there is a single, unique, and deterministic value that is the result. Thus, although Bosque programs are defined in terms of evaluation order and flow their semantics is isomorphic to the direct encoding in first-order logic (Section 7.2).

#### Atomic Data Operations:

The use of atomic constructors and bulk-data operations in Bosque, along with automatically checked invariants, makes it possible to ensure no value is ever in a partially defined or invalid state. This prevents accidental corruption and the construction of cyclic reference loops. Combined with the validate support, these features ensure that when reasoning about code semantics, we can make strong guarantees about the properties that must hold at all program points.

#### Value Equality and Explicit Identity:

The restriction of equality comparisons to, primitive based, KeyType values prevents the exposure of reference equality information (which would violate referential transparency). It also ensures that the definition of equality is uniform across an application and avoids the need to check for possible differences between, say, equality used in an associative container and equality as implemented in a == operator. The elimination of semantically visible aliasing has additional benefits for runtime and compiler implementations.

### 6.2. Reasoning Agents and Benefits

#### Human Developers:

The Bosque language provides a unique combination of features that eliminate various bug classes and simplify reasoning scenarios that humans find challenging. The primary area of improvement comes from regularizing application behavior in a way that reduces (or eliminates) special cases a human developer needs to keep in mind. For example there is no need to remember that sort order may change sometimes, that negation may overflow in one specific case (INT_MIN), wonder if a call modifies global state, figure out what definition of equality will be used for a comparison. The second major benefit that Bosque provides for a human when reasoning about code is a strong bias for explicit intent expression. This includes the ability to explicitly specify logical invariants, the use of flow-type information, and the use of collection functors instead of depending on idiomatic loop structure to convey intent. These features enable developers to understand code explicitly instead of relying on (failable) intuition and patterns.

#### Symbolic Analysis Tooling:

The BosqueIR representation is well-suited to supporting symbolic analysis tools. By construction, it eliminates major sources of complexity, including aliasing, mutability, and nondeterminism, and greatly simplifies other sources like inductive invariants. As a result it is, almost trivially, mappable to an efficiently solvable decidable/semi-decidable fragment of first order logic (Section 7.2). Other symbolic analysis techniques, including abstract-interpretation based, also benefit from the reduced needs to perform strong-updates or frequently apply generic widening. Thus, these models are able to avoid getting ”lost in the details” of possible effects of an operation or losing information by making conservative assumptions in general cases. In practice this leads to increased scalability and precision of the analysis and, as a result, much more practical value from the tools/optimizations that they power.

#### AI Agents:

As with human developers, the features in Bosque that explicitly encode intent in the syntax provides a major boost to LLM based agents. The features in Bosque also provide a richer set of information modalities for the models to use and extract information from. As seen in the Section 7.3 case study an agent working with Bosque code can use the textual language, evaluation of concrete values, and queries to symbolic tools that understand the declarative nature of invariants and assertions. These features improve the ability of the agent to extract useful information from the (limited) context it is given, provide symbolic guardrails to limit the possibility of producing catastrophically wrong results, and allows the system to catch these mistakes quickly and minimize the impact when the agent does generate erroneous outputs.

## 7. Case Studies

In this section we examine how the features of Bosque impact mechanized development. This section uses two case studies, small model validation and AI assisted programming as representative studies to illustrate the potential for Bosque to power the future of software development.

### 7.1. Implementation

The Bosque language, including a compiler/type-checker, runtime, checker, synthesizer framework, and Cloud API specification framework, have all been implemented as open-source software and are publicly available 3 3 3 Bosque source code is available at https://github.com/BosqueLanguage/BosqueCore. The initial implementation uses $30303030$ kloc of TypeScript and $5555$ kloc of Bosque code. We expect this count to grow rapidly as the language moves from a collection of proof-of-concept components to a full-featured platform. There is active collaboration with colleagues at Microsoft to apply Bosque to technical challenges in API/Data Specification and software quality assurance.

#### Motivation

Developers care deeply about the quality and reliability of the software they ship. However, there is a constant tension between time spent on quality and time spent building new features or addressing other client needs. For the majority of applications this calculation makes full-program verification an impractical option and, even with the needed resources, maintaining full-behavioral specifications is a Sisyphean task for most teams as they experience continuously changing business requirements and evolving feature sets.

As a result (most) development teams are not interested in a system that performs full-proofs of correctness. Instead the sweet-spot is simple logical checks (asserts, pre/post, and data invariants) that can be written in the same language, and inline, as the application. Full proofs that these checks are always satisfied, are of course nice but developers often do not have time and technical ability to debug/resolve proof failures, so more practically useful is generating inputs that trigger them if they can fail. In general the preference is for small inputs, or small reproductions that, are easy to debug and, are considered to exist for most possible failures (the small-model hypothesis (smallscope, )). Under these constraints we want to create a checker that:

1. (1)

Can be applied to any runtime or user defined assert/invariant failure
2. (2)

Does not require any specialized annotations or developer knowledge of proof systems
3. (3)

Provides actionable results in the form of a witness input when a failing condition is found

This problem has been studied as a semi-decision procedure for $20+limit-from2020+20 +$ years in the form of Model Checking (CKY03, ), Dynamic-Symbolic Analysis (dart, ), concrete Fuzzing (afl, ), and recently by formulating new (underapproximating) logics for modeling program semantics (incorrectness, ). Despite the importance of the problem and the substantial amount of work on the topic it remains an unresolved challenge in practice. 

#### Direct Solution with Bosque 

In contrast to other widely used languages 4 4 4 A notable exception is Elm (elm, ; highassurance, ). where the semantics are not efficiently encodable in first-order logic (FOL), due to features like loops, mutability, non-deterministic behaviors, etc. as identified in Section 2, Bosque can be converted in a direct manner into efficiently decidable FOL theories. The design restrictions on the BosqueIR core language enable us to map it, almost entirely, to efficiently decidable theories supported by a SAT-Module-Theory (SMT) solver (z3, ). Operations on numbers, data-types, and functions all map to core decidable theories – Integers, Constructors, Uninterpreted Functions, and Interpreted Functions. Strings and Sequences are used to model strings and collections. In Z3 the theories of Strings and Sequences are semi-decision procedures in the unbounded case. However, as we are interested in small-model inputs these are always bounded and become fully (and efficiently) decidable. As a result we can guarantee that an actionable (small) reproduction of a failure can be found if it exists and, from a practical perspective, this can be done automatically and efficiently in practice.

#### Example and Case Study

To illustrate how this system works we show a (simplified) piece of code from a sample application, consisting of $2222$ Kloc of code, published by Morgan Stanley (morphirrepo, ). The relevant type definitions definitions, SaleOrder and SaleInfo are in Figure 4. The function in Figure 5 takes a sale order, checks if there is available inventory to satisfy it, and then either accepts the order (adding it to the history) or returns none to indicate it was rejected. In this function there is one user defined property that needs to be checked, specifically that whenever an order is accepted the inventory must be reduced. This is clearly not a full, or even very complete specification, but in practice these types of sanity check conditions are very popular as they are effective in finding bugs and easy for developers to understand.

⬇

 function process( 

 sales: SaleInfo, order: SaleOrder 

 ): SaleInfo? 

 ensures $return != none ==> 

 $return@< SaleInfo>. available <= sales. available; 

 { 

 if(sales. available < order. quantity) { 

 return none; 

 } 

 else { 

 return sales.{ 

 available=$available - order. quantity, 

 orders=$orders. pushBack(order) 

 }; 

 } 

 } 

 

Figure 5. Order Processing from Trading App

Using the tooling that Bosque provides we can run the static checker over the application. This checker will enumerate every possible error in the application and then translate the relevant code to a (small-model) decidable fragment of logic. Each of these logical formula are passed to the Z3 SMT solver for either a satisfying assignment, which would be the failing input, or unsat which indicates that there does not exist any small-model input that can trigger the error! When running the checker tool on the sample Fintech application we are able to produce a result for every error in under $0.2⁢s0.2𝑠0.2s0.2 italic_s$ per error (including process startup and loading SMTLIB files). For the ensures clause the tool reports that an error is possible and that is corresponds to the case where the order entity is:

⬇ { id: " order_1", quantity: -1 } 

If this concrete input is given to the application the ensures assertion will trigger as the negative quantity results in an increase in the availability. This is an error in the business logic, as SaleOrder is expected to always have a positive quantity. A developer can fix this bug by adding an invariant to the SaleOrder or changing the type of the quantity field to be a BigNat (instead of a BigInt). After either of the changes re-running the checker will report that there is no small input that can trigger this ensures clause.

This case study shows how the design of the BosqueIR representation enables the direct solution of a foundational software-engineering problem. The design of the intermediate language enables us to directly map code to efficiently decidable logics and avoid the complexities that have prevented the widespread use of these types of checkers in the past. Conversion of the full language semantics and checking of arbitrary user properties is among the most challenging reasoning problems in the SE tooling space. Thus, this is a clear demonstration that Bosque creates opportunities for advancement in the practical development of other tools, with simpler reasoning needs such as those based on abstract interpretation or dataflow analysis, as well.

### 7.3. AI Assisted Programming

AI assisted programming is in its early stages but several key challenges are already clear. The first is a need to provide guardrails for the code that these probabilistic agents generate. This is tied with the desire to provide multi-modal inputs for them to work with – the program synthesis community (nlyze, ; flashfill, ; uist, ) has long looked at combinations of natural-language, formal specs, examples, and context as specifications for generating code. Finally, the current large-language-model (LLM) agents are most effective when dealing with text and, the more relevant information that can be hoisted into this representation, the more effective the agents are.

As an example consider the code below where we use a LLM agent to generate code for a function body that a developer has sketched out in TypeScript.

 /*Find the largest pair of values from the lists.*/ 

 function maxPair(x: number [], y: number []): 

 [number, number] 

 { 

 //generate the implementation code here 

 } 

In a language such as TypeScript (or Java) the LLM must resolve the users intent solely from the the natural language in comments and (partial) code context. In our example passing this to GPT-4 (or Github Copilot) and asking for code completions produces multiple possible solutions the highest ranked in both cases is the following:

 let maxPair: [number, number] = [0, 0]; 

 for (let i = 0; i < x. length; i++) { 

 if (x [i] > maxPair [0]) { 

 maxPair [0] = x [i]; 

 maxPair [1] = y [i]; 

 } 

 } 

Interestingly this solution only looks for the maximum value in x and is unlikely to be the desired functionality. If we sample more solutions we also find versions that take the max from each list independently which is more likely to be the desired response but just from the source text it is difficult to make this choice with confidence.

In contrast Bosque has multiple features which are designed to make intent and specifications explicit in the source code. The expressive type system, including unions, nullable-types, and typedecls, along with the explicit syntactic support for pre/post conditions and invariants trivially exposes rich contextual information directly to the LLM. The code below shows the same signature but augmented with partial logical postconditions and examples of inputs and the corresponding outputs.

 /*Find the largest pair of values from the lists.*/ 

 function maxPair(x: List< Int>, y: List< Int>): [Int, Int] 

 ensures x. contains($return.0); 

 ensures y. contains($return.1); 

 examples [ 

 [List{3, 2}, List{3, 5}] => [2, 5] 

 ]; 

 { 

 defer; 

With this extra contextual information the code completions generated are much higher quality. The top ranked solutions we extract include the following two candidates:

⬇ (1) return [x. max(), y. max()]; (2) return List:: zip< Int, Int>(x, y) . maxArg< Int>(fn(v) => v.0 + v.1); 

Just having the ensures and examples as textual hints resulted in a substantial improvement in the generated code. The highest ranked output (#1) is quite plausible. However, we can use the ensures and examples to further check the generated code. By running the examples as test cases we see that output (1) is not the desired result. Instead a slightly lower ranked output #2 5 5 5 The exact rank of this version varies per run. satisfies the example and the ensures clauses. Thus, after re-ranking we suggest output #2, which in this case, is the actual desired output. A preliminary evaluation with manually blanking out bodies shows that the additional information available in Bosque (plus the absence of loops which are known problems for synthesis (tddsynth, )) consistently improves results over simple text/code.

This case study shows how Bosque enables the combination of natural language via comments and declarations, declarative constraints via the ensures clauses, and examples, in a form that a LLM can consume and use to drive the code generation task. These features provide a way to screen for invalid generations, by simply running the provided samples, and provide guardrails by validating the generated code against pre/post conditions and invariants (using methods like the previously described small-model validator). In addition to supporting the direct code synthesis task, this multi-modal interaction capability also opens up a variety of options for exploring user experiences and multi-round interactions as part of the code generation process (uist, ).

## 8. Related Work

Throughout this paper we have discussed the conceptual frameworks (structuredprogramming, ; silverbullet, ; adts, ; tecton, ) and language constructs (STL, ; loopmining, ; comega, ; typescript, ; durablefuncs, ; sml, ) that have motivated the development and the design of the Bosque language. Thus, this section focuses on topics related to the complexity issues identified and connections to other lines of research.

#### Invariant generation:

The problem of generating loop invariants goes back to the introduction of loops as a concept (hinvariants, ; finvariants, ). Despite substantial work on the topic (invnonlinear, ; nipsinv, ; invdemand, ; invgen, ) the problem of generating precise loop invariants remains an open problem. This has severely limited the usability and adoption of formal methods in industrial development workflows. Notable successes include seL4 (sel4, ), CompCert (compcert, ), and Everest (everest, ). However, all of these systems required expertise in formal methods that is beyond what is available to most development teams. The Bosque language seeks to sidestep this challenge entirely by avoiding the presence of unconstrained iteration.

#### Equality and Reference Identity:

Equality is a complicated concept in programming (lefthandequals, ). Despite this complexity it has been under-explored in the research literature and is often defined based on historical precedent and convenience. This can result in multiple flavors of equality living in a language that may (or may not) vary in behavior and results in a range of subtle bugs (findbugs, ) that surface in surprising ways.

Reference identity, and the equality relation it induces, is a particularly interesting example. Identity is often the desired version of equality for classic object-oriented programming (lefthandequals, ) and having it as a default is quite convenient. However, in many cases a programmer desires equality based on values, or a primary key, or an equivalence relation and a default equality based on identity is, instead, a source of bugs. Further, the fact that it is based on memory addresses is a complication to pass-by-value optimizations of attempts to compile to non Von Neumann architectures like FPGAs (fpga, ).

#### Alias Analysis:

The introduction of identity as an observable feature in a language semantics immediately pulls in the concept of aliasing. This is another problem that has been studied extensively over the years (palinear, ; pasolved, ; ptssa, ; paobjsens, ; padsa, ; paparallel, ) and remains an open and challenging problem. A major motivation for this work is, in a sense, to undo the introduction of reference identity and identify code where reference equality does not need to be preserved. This is critical to many compiler optimizations including classic transformations like scalar field replacement, conversion to pass-by-value, and copy-propagation (kennedyallen, ; muchnick, ). This information is also critical to compiling to accelerator architectures like SIMD hardware (mesimd, ).

#### Frames and Ownership:

The problem of aliasing is further compounded with the introduction of mutation. Once this is in the language the problem of computing frames (seplogic, ) and purity (purity, ) becomes critical. Often developers work around the problem of explicit frame reasoning by using an ownership (owner1, ; owner2, ) discipline in their code. This may be a completely convention driven discipline or, more recently, may be augmented by runtime support such as smart pointers (STL, ) and type system support (rust, ; lineartypes, ; affinetypes, ; immutabletypes, ).

#### Concurrency, and Environmental Interaction:

Reasoning in concurrent (parallel) applications with mutablility is a challenging problem. As all Bosque values are immutable the problem of Read-Write or Write-Write dependencies do not exist, so parallelism for performance can be done aggressively without concern for changing application behavior. Concurrency and non-determinism that result from environmental interaction such as user interactions, network, or external interaction with other processes are currently beyond the scope of Bosque. Instead it operates as a pure computation language that can be embedded by a host (or other language like Node.js modules (napi, )) that manage async behavior and IO. A promising direction is integrating a core computation language (like Bosque) with an interaction focused language such as P/P# (plang, ) that has sophisticated methods for analyzing and testing concurrency and environmental interactions (plangtest, ).

#### Incorrectness and Under Approximate Analysis:

Incorrectness Logic (incorrectness, ) and other under approximate approaches (racerd, ) represent an interesting and recent development in the design space of program analysis. These systems look to fuse the power of symbolic representations to capture many concrete states while under (rather than over) approximating reachability. Interestingly, one of the motivations for introducing Incorrectness Logic is that (p. 4) “…the exact reasoning of the middle line of the diagram [strongest post semantics] is definable mathematically but not computable (unless highly incomputable formulae are used to describe the post).” However, as shown in this paper, this middle line of exact and decidable semantics is practical to compute when the language semantics are designed appropriately.

#### Synthesis:

Program synthesis is an active topic of research but the need to reason about loops has limited the application of synthesis to mostly straight-line code. Work on code with loops has been more limited due to the challenge of reasoning about loops in code (mesimd, ; loopslater, ) and the difficultly synthesizers have constructing reasonable code that includes raw loop and conditional control-flow (tddsynth, ). Thus, a language like Bosque, that provides high-level functors as primitives and can be effectively reasoned about opens new possibilities for program synthesis.

## 9. Onward!

This paper argues for a foundational re-conceptualization of the role of programming languages in the process of building software systems. Instead of being a set of increasingly powerful features and logical abstractions that a developer uses to formalize what is typed into a file, we advocate for them to be built as a substrate that is optimized for mechanization and reasoning tasks. This mindset led to revisiting many common assumptions about the features in a language and a drastic push for simplification of their semantics. Section 2 enumerated these features, and the challenges they create for human/symbolic/statistical agents, while Section 4 and Section 5 show how a practical language can be designed to address these challenges.

To validate the effectiveness of the design in actually addressing the challenges identified we looked at two case studies that exercise different aspects of reasoning about an application. Both applications in Section 7 provide capabilities that are beyond the current state of the art in any mainstream programming ecosystem and, both, were built using variations on standard approaches. The key to enabling them was the ability to effectively perform reasoning on the application semantics!

With this initial success it is time to move Onward! Based on our experience with the language, case studies and proof-of-concept systems, we believe the core of the language is stable enough to build on. The compiler for Bosque is now being written in Bosque, collaborators are working with us on applying Bosque to solve critical technical challenges, and the potential for innovative tooling and platform research is massive 6 6 6 This project is fully open-source at: https://github.com/BosqueLanguage/BosqueCore. We believe this is a unique opportunity for the academic and industrial communities to advance into a new era of programming languages that fully embraces the forces of mechanization, integration, AI driven coding, that are shaping the software development landscape.

## Acknowledgements

This work is the result of many years of conversations, experiences, and thinking. I would like to give a special thanks to Ed Maurer, Gaurav Seth, Brian Terlson, Hitesh Kanwathirtha, Mike Kaufman, Todd Mytkowicz, and Earl Barr for all their thoughts and conversations. I would also like to thank Stephen Goldbaum and Richard Perris for their insights on how technology is impacting the FinTech sector. Finally, I want to acknowledge the the Node.js community for their innovation and willingness to experiment!

## References

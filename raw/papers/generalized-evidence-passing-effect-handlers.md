---
source_url: https://www.microsoft.com/en-us/research/wp-content/uploads/2021/08/genev-icfp21.pdf
ingested: 2026-09-12
sha256: 3692fffa317a17d86f80f4974bbd9bbec15fcd987591bb1d0ca2bb985b5c6917
---
# Generalized Evidence Passing for Effect Handlers

Generalized Evidence Passing for Effect Handlers Efficient Compilation of Effect Handlers to C

NINGNING XIE, University of Hong Kong, China 
DAAN LEIJEN, Microsoft Research, USA 
This paper studies compilation techniques for algebraic effect handlers. In particular, we present a sequence 
of refinements of algebraic effects, going via multi-prompt delimited control, generalized evidence passing, 
yield bubbling, and finally a monadic translation into plain lambda calculus which can be compiled efficiently 
to many target platforms. Along the way we explore various interesting points in the design space. We 
provide two implementations of our techniques, one as a library in Haskell, and one as a C backend for 
the Koka programming language. We show that our techniques are effective, by comparing against three 
other best-in-class implementations of effect handlers: multi-core OCaml, the Ev.Eff Haskell library, and 
the libhandler C library. We hope this work can serve as a basis for future designs and implementations of 
algebraic effects. 
CCS Concepts: • Software and its engineering → Control structures; Polymorphism; • Theory of 
computation → Type theory. 
Additional Key Words and Phrases: Algebraic Effects, Handlers, Evidence Passing 
ACM Reference Format: 
Ningning Xie and Daan Leijen. 2021. Generalized Evidence Passing for Effect Handlers: Efficient Compilation 
of Effect Handlers to C. Proc. ACM Program. Lang. 5, ICFP, Article 71 (August 2021), 30 pages. https://doi.org/ 
10.1145/3473576 
1 INTRODUCTION 
Algebraic effects and handlers [Plotkin and Power 2003; Plotkin and Pretnar 2013] provide a 
powerful and flexible way to add structured control-flow abstraction to programming languages. 
Unfortunately, it is not straightforward to compile effect handlers into efficient code: effect opera 
tions are generally able to capture- and resume a delimited continuation, which usually requires 
special runtime support to do efficiently. For example, the effect handler implementation in multi 
core OCaml [Dolan et al. 2017; Sivaramakrishnan et al. 2021] relies on a runtime system that 
uses segmented stacks which can be captured efficiently [Farvardin and Reppy 2020]. Then, a 
natural question that arises is whether it is possible to compile effect handlers efficiently where the 
target platform does not directly support delimited continuations, for example, when compiling to 
C/LLVM, WASM [Haas et al. 2017], JavaScript, Java VM, .NET, etc. 
In this paper we give a formalized translation and evaluation semantics from a typed effect 
handler calculus into a plain typed lambda calculus as a sequence of refinements: 
(1) First we show how effect handler semantics can be expressed using standard multi-prompt 
delimited control semantics [Forster et al. 2019; Gunter et al. 1995] (Section 2.4). 

Authors’ addresses: Ningning Xie, University of Hong Kong, China, xnning@hku.hk; Daan Leijen, Microsoft Research, USA, daan@microsoft.com.

© 2021 Copyright held by the owner/author(s). 2475-1421/2021/8-ART71 https://doi.org/10.1145/3473576

This work is licensed under a Creative Commons Attribution 4.0 International License.

(2) We refine this semantics further to evidence passing semantics (EPS) where the evidence for a handler prompt in the evaluation context is pushed down to each effect operation as an evidence vector (Section 2.5 and 3.1). This makes performing an operation a local transition that no longer needs to search through the evaluation context (Section 2.6 and 3.2). (3) Next we also localize yielding to a handler prompt by bubbling each yield through the evaluation context instead of capturing in one step (Section 2.7 and 4.1). This closely follows the effect handler semantics as given by Pretnar [2015]. (4) With all evaluation transitions localized, we can now define a direct monadic translation of effect handlers into a plain typed lambda calculus using a multi-prompt monad (Section 2.9, 2.11, and 4). Such program can be directly compiled to any target platform (including C/LLVM, WASM, JavaScript, Java VM, .NET, etc) without requiring special runtime mechanisms. Aside from the novel evidence passing semantics, many parts of the refinements are known compilation techniques for effect handlers ś but we believe we are the first to formalize each within a single polymorphically typed framework (combined with evidence passing semantics). Specifically, we make the following contributions:

• We formalize each refinement and translation, and show they are sound and semantics 
preserving (Section 3 and 4). Along the way, we explore various interesting points in the 
design space: 
ś The use of segmented stacks for implementing effect handlers in a direct way (as used by 
multi-core OCaml [Sivaramakrishnan et al. 2021]) versus translation into a multi-prompt 
monad (Section 2.4): segmented stacks need a dedicated runtime system but can capture 
and resume an operation in constant time (for one-shot resumptions), while a multi-prompt 
monad is linear in the continuation points. 
ś Using insertion- versus canonical ordered evidence vectors (Section 2.5): the former is 
efficient to construct but needs a linear lookup for each operation, while a canonical vector 
is more expensive to construct upfront but can use constant time lookup for operations. 
ś Using short-cut resumptions to minimize the stack usage of a resumption while increasing 
sharing of continuation points (Section 2.8); a similar technique is used in [Kiselyov and 
Ishii 2015] to compose monadic binds in an effect monad. 
ś Using bind-inlining and join-point sharing for improved efficiency when translating into 
the multi-prompt monad (Section 2.10). 
• Our evidence passing semantics (EPS) is a generalization of the work on evidence passing 
translation (EPT) [Xie et al. 2020]. In particular, EPT can only express a subset of full effect 
handlers that are restricted to scoped resumptions only, whereas EPS lifts the restriction and 
can fully express effect handlers (Section 2.12 and 3.1). 
• We give the first formal account of optimized tail-resumptive operation semantics and show 
how this can evaluate an operation in-place and avoid performing an expensive yield-and 
resume cycle in the majority of effect operations (Section 2.6 and 3.2). The tail-resumptive 
optimization is surprisingly subtle to get correct ś in particular in combination with unscoped 
resumptions which we illustrate in Section 2.12.2. We prove the correctness of the tail 
resumptive optimization by showing that an optimized program is contextually equivalent 
to the original one. 
• We have implemented our techniques as a monadic library for effect handlers in Haskell, called 
Mp.Eff (for łmulti-prompt effectž) [Xie and Leijen 2021b], generalizing the Ev.Eff library 
based on EPT [Xie and Leijen 2020]. Our implementation is based on insertion-ordered 
evidence vectors. 

• We have also implemented our techniques in the Koka programming language [Leijen 2020] compiling to standard C code (Section 2.11). The implementation uses canonical evidence vectors, short-cut resumptions, bind-inlining, and join-point sharing. • We benchmarked the Koka implementation against four other implementations of effect handlers that compile to native code: the current state-of-the-art direct implementation of effect handlers in multi-core OCaml which uses a dedicated runtime system based on segmented stacks; our Mp.Eff Haskell library; the Ev.Eff Haskell library which has been shown by Xie and Leijen [2020] to perform very well compared to other Haskell effect handler libraries [Schrijvers et al. 2019; Wu and Schrijvers 2015; Wu et al. 2014]; and finally the libhandler C library which implements effect handlers directly in C by copying fragments of the stack [Leijen 2017a]. Comparing across systems and languages is always tricky but the results clearly indicate that our approach can have competitive performance (Section 5). The metatheory proofs are available in the technical report [Xie and Leijen 2021a], and the Mp.Eff Haskell library and benchmarks are available online [Leijen 2021; Xie and Leijen 2021b].

2 OVERVIEW We start with a short discussion and examples of basic effect handlers and follow with an overview of each of our semantic refinements and translation techniques. We refer to other work [Hillerström and Lindley 2016; Leijen 2017b; Pretnar 2015] for further examples of effect handlers.

2.1 Algebraic Effects 
With algebraic effect handlers, an effect l defines a set of operations op. For example, we can have a 
reader effect with an ask operation 
read { ask : () → int } 
and we can perform the ask operation writing perform ask (). A handler (handler h v) takes a list 
of operation clauses in h, and a computation v to be handled. Each operation clause in h takes 
the form op ↦→ f , providing the implementation f for the operation op from the handled effect 
where the implementation f is of form x. k. e: x binds the operation argument, and k binds the 
captured resumption that can be used to resume to the original call-site with the operation result. 
For example, we can handle the reader effect by always resuming with the constant 1: 
h read = { ask ↦→ x. k. k 1 } 
where the expression handler h read ( _. perform ask () + perform ask ()) evaluates to 2. The fol 
lowing evaluation rules give the essence of the untyped semantics for algebraic effect handlers [Xie 
and Leijen 2020]: 
(app) ( x. e) v −→ e[x:=v] 
(handler) handler h f −→ handle h (f ()) 
(return) handle h v −→ v 
(perform) handle h E[perform op v] −→ f v ( x. handle h E[x]) 
iff op ̸∈ bop(E) ∧ (op ↦→ f ) ∈ h 
Rule (app) is standard -reduction and applies a function to a value v by substituting x for the 
argument v in the function body. The (handler) takes a computation f , and applies the computation 
to a unit value under a new frame handle h. The computation to be handled (f ) is always a unit 
taking function as in [Xie et al. 2020], which essentially corresponds to a suspended computation as 
in the call-by-push-value approach [Levy 2006] used in several algebraic effect systems [Kammar 
and Pretnar 2017; Plotkin and Pretnar 2013]. 

| lowing | | evaluation | rules give | the essence of | the | untyped semantics for algebraic effect handlers [Xie |
| --- | --- | --- | --- | --- | --- | --- |
| and | | Leijen | 2020]: | | | |
| | (app) | | ( e) x. v | −→ | | e[x:=v] |
| | (handler) | | handler h f | −→ | | ()) handle h (f |
| | (return) | | handle h v | −→ | | v |
| | (perform) | | handle E[perform h | v] −→ op | | ( E[x]) x. handle f v h |

The handle frame is only generated by handler, and treated as a strictly internal frame. When handling a computation under a handle h frame, there are two possible situations. In the first case, the computation evaluates to a value and the (return) transition discards the handle h frame and propagates the value. The second case captures the essence of algebraic effects handlers where an operation is handled. In rule (perform), perform op v calls an effect operation op by providing the operation argument v. The handle h frame handles the operation by applying the operation implementation f to the operation argument v, and the resumption ( x. handle h E[x]). The resumption captures the original handle, as well as the whole evaluation context E between handle and the operation call. An evaluation context E is essentially an expression with a hole (□) in it, and the notation E[e] represents the expression obtained by plugging e into the hole of E (e.g., (f (g □)) [x] = f (g x)). In this rule, the condition op ̸∈ bop(E) indicates that op is not in the bound operations of E, i.e. not handled by any handle frames in E, ensuring that h is always the innermost handle frame for the effect that handles the operation.

2.2 Examples 
Here we consider some standard examples of algebraic effects, and we refer the reader to other work 
for more examples as well as practical uses of effect handlers [Bauer and Pretnar 2015; Hillerström 
and Lindley 2016; Kammar et al. 2013; Leijen 2017b; Pretnar 2015; Xie et al. 2020]. In the examples, 
we use x ← e1; e2 as a shorthand for ( x. e2) e1, and use e1; e2 for ( _. e2) e1, where _ denotes a 
lambda whose binding is not used in the body. 
Exceptions. The following definition defines an effect exn with one operation throw. 
exn { throw : ∀ . () → } 
Given a datatype Maybe with two constructors Just and Nothing, we can define a handler for 
exceptions that reifies any exceptional computation with a Maybe result to return Nothing on an 
exception: 
h exn = { throw ↦→ x. k. Nothing } 
For example, suppose we define safe division as: 
safediv = x y. if (y == 0) then perform throw () else x/y 
then we have 
handler h exn ( _. Just (safediv 42 2)) handler h exn ( _. Just (safediv 42 0)) 
↦−→ ∗ handle h exn (Just (42/2)) ↦−→ ∗ handle h exn (Just (perform throw ())) 
↦−→ handle h exn (Just 21) ↦−→ ( x. k. Nothing) () ( x. handle h exn (Just x)) 
↦−→ Just 21 ↦−→ ∗ Nothing 
We use the notation ↦−→ to allow expressions to take steps (−→) inside evaluation contexts, where 
↦−→ ∗ is the transitive reflexive closure of ↦−→, and ↦−→ + is the transitive closure of ↦−→. 
Reader. In the previous example we did not make use of the operation argument (x) or the 
resumption (k). Let’s consider this time the evaluation of our first example with the reader effect: 
handler h read ( _. perform ask () + perform ask ()) 
↦−→ ∗ handle h read (perform ask () + perform ask ()) 
↦−→ ( x. k. k 1) () ( x. handle h read (x + perform ask ())) 
↦−→ ∗ ( x. handle h read (x + perform ask ())) 1 
↦−→ handle h read (1 + perform ask ()) ↦−→ ∗ ( x. handle h read (1 + x)) 1 ↦−→ ∗ 2 
where both ask operations resume back to the original calling context with a result. 

State. We can define a state handler using the monadic encoding [Kammar and Pretnar 2017], 
where performing an operation returns a function that takes in the current state. 
st { get : () → , h st = {get ↦→ x. k. ( y. k y y), 
set : → () } set ↦→ x. k. ( y. k () x) } 
The following program starts with an initial state 0. 
(handler h st ( _. perform set 21; w ← perform get (); ( z. w + w) )) 0 
↦−→ (handle h st (perform set 21; w ← perform get (); ( z. w + w) )) 0 
In the following derivation, we make use of the dot notation [Xie and Leijen 2020]. Specifically, the 
notation E1 • E2 composes two evaluation contexts by plugging E2 into the hole of E1, resulting 
in a new evaluation context. The (•) notation is right-associative and has the lowest precedence, 
so we often write E1 • E2 instead of (E1) • E2. The notation E • e has the same meaning as 
E[e], which plugs e into the hole of E, resulting in a new expression. Using the dot notation, the 
evaluation order of expressions becomes more apparent, and it is now easier to discuss one specific 
frame in the chain of evaluation contexts. We start by rewriting the last expression using the dot 
notation as: 
= □ 0 • handle h st □ • (□; w ← perform get (); ( z. w + w)) • perform set 21 
For conciseness, we also often omit a trailing □ in an application context e □ • E and write instead 
e • E; this is usually the case for handle expressions: 
= □ 0 • handle h st • (□; w ← perform get (); ( z. w + w)) • perform set 21 
Writing contexts this way, it shows more clearly the stack of evaluation frames with the expression 
under evaluation at the end. We can now continue evaluating as: 
↦−→ ∗ □ 0 • ( y. k () 21) with k = x.handle h st • (□; w←perform get (); ( z.w + w)) • x 
= ( y. k () 21) 0 ↦−→ k () 21 
↦−→ □ 21 • handle h st • (□; w ← perform get (); ( z. w + w)) • () 
= □ 21 • handle h st • ( () ; w ← perform get () ; ( z. w + w)) 
↦−→ □ 21 • handle h st • (w ← □; ( z. w + w)) • perform get () ↦−→ ∗ 42 
While this is a nice example of the expressiveness of effect handlers, it is clearly not the most 
efficient way to express mutable state. In practice, state can be implemented more efficiently using 
parameterized handlers [Plotkin and Pretnar 2009] or a primitive state handler [Xie and Leijen 2020]. 
Moreover, using the more efficient implementations allow state handlers to be tail-resumptive 
(Section 2.6). 
Non-determinism. By having the resumption k available when handling, we can actually resume 
more than once. In the handler of amb, we implement non-determinism by collecting all possible 
results in a list by resuming the resumption twice, each time with one boolean result. 
amb { flip : () → bool } handler h amb ( _. x ← perform flip (); 
h amb = { flip ↦→ _ k. xs ← k True; y ← perform flip (); 
ys ← k False; [x && y]) 
xs ++ ys } ↦−→ ∗ [True, False, False, False] 
2.3 Compiling Effect Handlers 
As the examples show, algebraic effect handlers can be very expressive. Unfortunately, their 
expressive power also makes it not easy to compile them efficiently. The main culprit is the 
(perform) rule: 
handle h E[perform op v] −→ f v ( x. handle h E[x]) iff op ̸∈ bop(E) ∧ (op ↦→ f ) ∈ h 

This single rule combines two potentially expensive runtime operations:

(1) Searching: The innermost handler for op must be found which usually requires a linear search 
through the current handlers in the evaluation context (i.e. search up through the stack 
frames). 
(2) Capturing: After finding the handler clause f , we need to capture the evaluation con 
text (i.e. stack and registers) up to the found handler, and create a resumption function 
( x. handle h E[x]) which restores the captured context when invoked with a result. An 
added complication is that in the general case such resumption may never be called (as in 
h exn), or invoked more than once (as in h amb), which can present difficulties in the runtime 
(for scanning GC roots for example). 

Capturing and restoring resumptions can be done relatively efficiently if the target runtime system implements segmented stacks [Farvardin and Reppy 2020] ś this is used in multi-core OCaml [Dolan et al. 2015] for example, where segmented stacks split the stack at each handler so that a one-shot resumption can be implemented efficiently by switching back to a previous stack segment [Sivaramakrishnan et al. 2021]). However, many target platforms do not support directly capturing parts of the stack at all, like compilation to C (as in Koka), WASM, .NET, the Java VM, JavaScript, etc, and in these cases it is not even possible to implement (perform) in any direct way. In this paper we address these compilation and runtime challenges by presenting various refine ments of the operational semantics in combination with source translations. Each of these steps enables further optimizations and implementations, and we explore various interesting points in the design space along the way.

2.4 Multi-Prompt Semantics As a first step, we are going to split the (perform) operation into two parts where we separate the searching for a handler from capturing and restoring a resumption. To capture and restore a resumption we are going to use standard (typed) multi-prompt delimited control [Gunter et al. 1995]: instead of a handle h frame, we install a prompt m h frame that is uniquely identified with a marker m, and performing an operation will use a yield m f frame to yield to such prompt. As an example, consider again the reader effect handler h read = {ask ↦→ f } with f = x. k. k 1, where we have the following evaluation (rewritten using the dot notation):

handler h read ( _. perform ask () + perform ask ()) ↦−→ ∗ handle h read • (□ + perform ask ()) • perform ask () ↦−→ f () ( x. handle h read • (□ + perform ask ()) • x) . . .

When using multi-prompt semantics, the first transition now installs a prompt m h read frame instead of a handle frame, where m is a unique marker identifying the prompt:

handler h read ( _. perform ask () + perform ask ()) ↦−→ ∗ prompt m h read (perform ask + perform ask ()) = prompt m h read • (□ + perform ask ()) • perform ask ()

The next transition shows how we separate searching from capturing ś perform ask () now only finds the handler clause f but defers yielding to the prompt by using an explicit yield frame:

↦−→ prompt m h read • (□ + perform ask ()) • yield m ( k. f () k)

The yield m g has two arguments: the marker m that uniquely identifies the prompt to yield to, 
and a function g that is applied to the resumption when reaching the prompt. Through the marker 
m, we can yield directly to the corresponding prompt which captures and applies the resumption: 
↦−→ ( k. f () k) ( x. prompt m h read • (□ + perform ask ()) • x) 
↦−→ f () ( x. prompt m h read • (□ + perform ask ()) • x) 
. . . 
This separation of concerns does not immediately buy us much but, as we will see, it opens up the 
way for optimizing each part individually by (1) using evidence passing semantics to avoid searching, 
and (2) using a monadic translation to enable capturing without requiring a special runtime system. 
Moreover, multi-prompt delimited control is one of the lowest level control operations that can be 
typed in the simply typed lambda calculus. 
If one controls the target platform, it is possible to efficiently implement multi-prompt delimited 
control directly. This is done for example in multi-core OCaml using segmented stacks: here the 
call stack is split in segments where each prompt frame starts a fresh segment. The marker m 
can be implemented directly as the runtime pointer to that frame. Yielding up to a parent stack 
segment is now a constant time operation as only the stack segment pointer needs to be adjusted. 
Resuming once can also be done in constant time this way, but supporting multi-shot resumptions 
still requires a linear copy of the resumption stack segments (and one of the reasons why multi-shot 
resumptions are not directly supported in multi-core OCaml). 

2.5 Evidence Passing Semantics The (perform) operation is still a non-local transition as it searches through the evaluation context to find the innermost handler. We can make it local using evidence passing semantics, where we pass the current handlers in the evaluation context explicitly as an extra evidence vector w down to the perform operations. Instead of searching through the context, we can now look up the handler locally. Essentially, if the current evidence vector is w, then the (perform) rule becomes: perform op v −→ yield m ( k. f v k) where (m, h) = w.l ∧ (op ↦→ f ) ∈ h The expression w.l directly looks up the marker and handler (called evidence) for effect l from the evidence vector w. We apply the idea to our example, where we use the

z}|{

notation to indicate the current evidence vector and we sometimes omit the notation when it is irrelevant or obvious from the context. Evaluation always starts with an empty evidence vector ⟨⟨⟩⟩: ⟨⟨⟩⟩ z }| { handler h read ( _. perform ask () + perform ask ()) which evaluates into:

↦−→ ∗

⟨⟨⟩⟩ z }| { prompt m h read •

w = ⟨⟨read : (m,h read ) ⟩⟩ 
z }| { 
(□ + perform ask ()) • perform ask () 
where the prompt frame modifies the evidence for rest of the evaluation context. At this point 
perform evaluates under an evidence vector ⟨⟨read : (m, h read )⟩⟩, and we get: 
↦−→ prompt m h read • (□ + perform ask ()) • yield m ( k.f () k) where (m, h read ) = w.read 
↦−→ ( k. f () k) ( x. prompt m h read • (□ + perform ask ()) • x) 
↦−→ f () ( x. prompt m h read • (□ + perform ask ()) • x) 
. . . 
Using evidence passing semantics makes the (perform) transition localized which can potentially be 
more efficient than searching through the evaluation context. When we treat the evidence vector as 
an abstract datatype there are two interesting variants depending on how the vectors are ordered: 

(1) Insertion order: Insert handler evidence in the order of the actual handlers in the evaluation 
context. This is straightforward and also the approach we take in the associated Haskell 
library. However, it means that the lookup operation w.l still needs to search linearly through 
the vector for the łinnermostž handler. One way to implement such vector is as a linked 
list where each handler pushes itself on the list. Since evidence vectors are not first-class 
values, we can actually allocate this list on the evaluation stack directly and as such it 
becomes a linked list of handlers at runtime ś this is exactly how various languages (e.g. 
C++ compilers used to do this) and systems (e.g. Windows structured exception handling) 
implement exception handlers where the w parameter is a pointer to the head of the exception 
handler list. 
(2) Canonical order: Use a lexicographic order of the handler evidence based on their effect label. 
This requires a strongly typed calculus but it means that if the effect type is fully known 
at compile time, we can statically determine the index for a particular effect in the runtime 
evidence vector. For example, in systems that keep track of the effect type of expressions 
using row types [Hillerström and Lindley 2016; Leijen 2017b], the effect type of our example 
perform ask () is the singleton effect row ⟨read⟩, and we know statically that the dynamic 
runtime evidence vector will have the form ⟨⟨read : _⟩⟩. We can thus replace the linear runtime 
lookup w.read with a constant-time array access w[0] instead. This is the approach used in 
the Koka compiler. 

2.6 Tail-Resumptive Operations With evidence semantics in place, the only expensive operation left is yielding and capturing a resumption. Fortunately, we can often avoid doing a full yield: almost all common operations in practice happen to be tail resumptive where the operation clause has the form:

op ↦→ x. k. k e where k ̸∈ fv(e)

For example, the ask operation in our h read handler is of this form 2. It turns out we can perform 
such operations in place: instead of yielding up and eventually resuming with the final result, we 
can directly evaluate e on the current stack without doing an expensive yield followed by a resume. 
To this end, we extend each evidence in the evidence vector to store a triple (m, h, w) (instead of a 
tuple (m, h)), where the third component w is the evidence context: this is the evidence vector under 
which the handler h is defined and is used for the evaluated-in-place expression. We illustrate the 
use of this in our running example: 
⟨⟨⟩⟩ 
z }| { 
handler h 
read ( _. perform ask () + perform ask ()) 

↦−→ ∗

⟨⟨⟩⟩ z }| { prompt m h read •

⟨⟨read : (m,h read,⟨⟨⟩⟩) ⟩⟩ z }| { (□ + perform ask ()) • perform ask ()

2While h state is not tail-resumptive here, implementations of state in practice are usually based on parameterized han dlers [Plotkin and Pretnar 2009] or primitive state [Xie and Leijen 2020], both of which are tail-resumptive. The h exn and h amb handlers are not tail-resumptive because of their special nature (aborting the computation and non-determinism, respectively). Furthermore, in practice we can also allow any clause that can be rewritten into the tail-resumptive form ś for example x k. if x == 0 then k 1 else k 2 which can be transformed to x k. k (if x == 0 then 1 else 2).

Here, the evidence vector for perform is ⟨⟨read : (m, h read, ⟨⟨⟩⟩)⟩⟩ and we can locally find the operation 
clause ask → x k. k 1 ∈ h read and determine that it is tail-resumptive. Instead of generating yield 
as before, we instead evaluate e (as in x. k. k e, with e being 1 in this case) in-place: 
↦−→ prompt m h read • (□ + perform ask ()) • under read • 1 
↦−→ prompt m h read • (□ + perform ask ()) • 1 
↦−→ prompt m h read (1 + perform ask ()) 
. . . 
The operation clause is now evaluated in-place ś but note it needs to be evaluated under an under l 
frame. Such frame ensures that if the operation clause e itself performs operations, these are 
resolved correctly with respect to the actual handler up in the evaluation context. Consider for 
example the following reader handler: 
h2 = { ask ↦→ x. k. k (perform ask () + 1) } 
Here the operation clause is tail-resumptive, and itself performs an ask operation. Now consider: 
handler h read ( _. handler h2 ( _. perform ask())) 

↦−→ ∗

⟨⟨⟩⟩ z }| { prompt m1 h read • w1 = ⟨⟨read : (m1,h read,⟨⟨⟩⟩) ⟩⟩ z }| { prompt m2 h2 •

w2 = ⟨⟨read : (m2,h2,w1), read : (m1,h read,⟨⟨⟩⟩) ⟩⟩ z }| { perform ask () At this point, the evidence vector at the second prompt is w1 = ⟨⟨read : (m1, h read, ⟨⟨⟩⟩)⟩⟩, but the ev idence vector at the perform contains two entries: w2 = ⟨⟨read : (m2, h2, w1), read : (m1, h read, ⟨⟨⟩⟩)⟩⟩. Here we see how the third member of the evidence always points to the łpreviousž evidence vector (e.g., w1) under which a particular hander (e.g., h2) is defined. If using insertion-ordered evidence vectors as a linked list, this is always just the tail of the list, but for canonical evidence vectors the previous vector must be kept explicitly. Since the operation clause is tail-resumptive, we get:

↦−→

⟨⟨⟩⟩ z }| { prompt m1 h read •

w1 z }| { prompt m2 h2 •

w2 z }| { under read •

w1 z }| { perform ask () + 1 = prompt m1 h read • prompt m2 h2 • under read • (□ + 1) • perform ask () The evidence vector for the perform ask () + 1 is now w1 and not the unchanged w2. Indeed, it would be incorrect to use w2 or otherwise we would invoke the operation clause of h2 again! The under read frame prevents this from happening and adjusts the evidence vector to the one under which the read handler is itself defined: this is exactly the third component of the evidence, w2.read.thd, which is w1 in our example. We now continue as:

↦−→

⟨⟨⟩⟩ z }| { prompt m1 h read •

w1 z }| { prompt m2 h2 •

w2 z }| { under read •

w1 z }| { (□ + 1) • under read •

⟨⟨⟩⟩ z}|{ 1

↦−→ prompt m1 h read • prompt m2 h2 • under read • (□ + 1) • 1 
↦−→ prompt m1 h read • prompt m2 h2 • under read • 2 ↦−→ ∗ 2 
Note that the second under read frame adjusts the evidence further to ⟨⟨⟩⟩ (which is w1.read.thd). 
The correct formalization of under is subtle, and we will come back to this in Section 2.12. 

2.7 Bubblin

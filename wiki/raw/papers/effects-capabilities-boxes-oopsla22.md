---
source_url: https://se.informatik.uni-tuebingen.de/publications/brachthaeuser22effects.pdf
ingested: 2026-09-12
sha256: 1efb0235fe6e6287936e0e321dcc79f4656cd0ba90b271e09ec7050cba315430
---
# Effects, Capabilities, and Boxes: From Scope-based Reasoning to Type-based Reasoning and Back

Effects, Capabilities, and Boxes 
From Scope-based Reasoning to Type-based Reasoning and Back 
Jonathan Immanuel Brachthäuser 
University of Tübingen, Germany 

Philipp Schuster University of Tübingen, Germany

Edward Lee University of Waterloo, Canada

Aleksander Boruch-Gruszecki 
EPFL, Switzerland 
Abstract 
Reasoning about the use of external resources is an important aspect of many practical applications. 
Effect systems enable tracking such information in types, but at the cost of complicating signatures 
of common functions. Capabilities coupled with escape analysis offer safety and natural signatures, 
but are often overly coarse grained and restrictive. We present System C, which builds on and 
generalizes ideas from type-based escape analysis and demonstrates that capabilities and effects can 
be reconciled harmoniously. By assuming that all functions are second class, we can admit natural 
signatures for many common programs. By introducing a notion of boxed values, we can lift the 
restrictions of second-class values at the cost of needing to track degree-of-impurity information in 
types. The system we present is expressive enough to support effect handlers in full capacity. We 
practically evaluate System C in an implementation and prove its soundness. 

Main Reference Jonathan Immanuel Brachthäuser, Philipp Schuster, Edward Lee, and Aleksander Boruch-Gruszecki. 2022. “Effects, Capabilities, and Boxes: From Scope-based Reasoning to Type-based Reasoning and Back.” Proceedings of the ACM on Programming Languages 6. OOPSLA (2022): 1–30. https://doi. org/10.1145/3527320 Comments This is an extended version of the main reference. Compared to the published paper, this report contains the full appendix (see Appendix A): full operational semantics, details on the soundness proofs, and a comparison with call-by-push-value (CBPV).

### 1 Introduction

Programming languages have to provide the ability to communicate with the outside world. Moreover, programs often need to non-locally interact with other parts of the program, for instance via mutable state or exceptions. If a program depends on or modifies its context, it is effectful, otherwise, it is pure. We say that effectful programs use an effect. Unrestricted or undisciplined use of effects can lead to confusion and bugs [13]. To address this, language designers have sought to enable programmers to statically and locally reason about the use of effects.

### 1.1 Effect Systems and Type-Based Reasoning

Effect systems extend the static guarantees of type systems to additionally track the use of effects [51, 34, 43, 38]. Typically, this additional information of the effect system (on the left) is also reflected in the type of functions, which mention the set of effects a function might use (on the right).

Γ ⊢ s : τ / { Exc, State } τ → τ / { Exc, State } Based on the types, programmers can use this additional information to reason about programs. For example, functions with an empty effect set are pure and can be executed

Jonathan Immanuel Brachthäuser, Philipp Schuster, Edward Lee, and Aleksander Boruch-Gruszecki. “Effects, Capabilities, and Boxes”. Technical Report. 2022. University of Tübingen, Germany.

in parallel without causing data races. From a programmer’s perspective, however, effect systems usually have a number of drawbacks, which inhibit a more widespread adoption. In particular, by enhancing function types with effects such systems often track too much information. Types quickly become verbose, difficult to understand, and difficult to reason about – especially in the presence of effect-polymorphic higher-order functions [55, 48, 9]. Consequently, programmers avoid effect systems and some languages, such as Scala, avoid adding an effect system.

### 1.2 Effects as Capabilities and Scope-Based Reasoning

Capabilities offer an alternative way to control the use of effects. In this model, one can use 
certain effects only through capabilities [16, 36]. Restricting access to capabilities restricts 
effects. A program, such as s below, can only perform effects of capabilities it has access to. 
Similarly, the function type in the middle requires the two capabilities as arguments. 
Γ, ex : Exc, st : State ⊢ s : τ (τ, Exc, State) → τ τ → τ 
From a language designer’s perspective, capabilities offer an interesting alternative to tradi 
tional effect systems: programmers can reason about effects the same way they reason about 
bindings. Additionally, it has been shown that capabilities offer a lightweight alternative to 
traditional effect polymorphism: contextual effect polymorphism [9, 41]. Functions can use 
effects by closing over capabilities. These are not visible in the type of the function (right 
column), simplifying signatures of effect polymorphic higher-order functions [9]. However, 
since since closure over capabilities is not visible in a function’s type, it often hinders reasoning 
about its purity. 
Some capabilities have a limited lifetime, like when modeling checked exceptions, and 
should not leave a particular scope. The problem is non-trivial, since leaving a scope can 
also occur indirectly via functions that close over capabilities. In an attempt to rule this out 
and guarantee effect safety, type-based escape analysis [23, 41] distinguishes between first 
and second-class functions. Capabilities and functions closing over them are second-class. 
They can be passed as arguments, but cannot be returned nor stored in data structures or 
mutable references. This restriction rules out a large class of programs, which are safe but 
not typable. For instance, since second-class functions cannot be returned, currying cannot 
be applied. 

### 1.3 Explicit Boxing – From Scope-Based to Type-Based Reasoning and Back

In this paper, we set out to restore the expressivity of first-class functions and type-based 
reasoning about purity, without sacrificing the simplicity of contextual effect polymorphism. 
As a starting point, we choose a core language with support for contextual effect polymor 
phism via second class capabilities – System Ξ – [9] and extend it with support for first-class 
functions. We require a possible solution to meet the following criteria: 
Backwards compatibility. Types assigned by System Ξ should not change in the extension. 
This entails that ergonomic advantages of lightweight effect polymorphism remain. 
Pay-as-you-go. Only when treating functions in a first-class way, programmers should be 
confronted with additional complexity in the involved types. 
We present System C, which aims at striking the balance between ergonomics (we offer 
the same form of lexical reasoning and contextual effect polymorphism as System Ξ) and 

Brachthäuser, Schuster, Lee, and Boruch-Gruszecki 3 expressivity (we additionally allow returning functions which close over capabilities and support type-based reasoning). Our solution is based on the following design decisions:

Second-class values Following Osvald et al. [41], and like System Ξ, we distinguish between functions that can be treated as first-class values, and functions that are second-class (to highlight this difference, we follow Brachthäuser et al. and explicitly refer to second-class functions as blocks). Thus, we avoid confronting programmers with the ceremony associated with tracking capabilities in types as much as possible. In particular, blocks can freely close over capabilities and effectful computations can simply use all capabilities in their lexical scope, with no visible type-level machinery to keep track of either fact.

Capability sets Based on the work by Osvald et al., we annotate each binding in the typing context with additional information. However, we do not only track whether a bound variable is first- or second-class, but track precisely over which capabilities it closes. That is, we augment bindings (e.g., f :C σ) in the typing context with capability sets (e.g. C). This information is only annotated at the binder and is not part of the type. This is important for ergonomics: the additional information, which is used to guarantee effect safety, is not visible to users unless explicitly requested.

Boxes While blocks can freely close over capabilities and other blocks, they cannot be 
returned from a function or stored in a field. To recover these abilities, System C features 
explicit boxing and unboxing language constructs. They are inspired by equally named modal 
connectives and by the work of Choudhury and Krishnaswami [12] on comonadic type systems. 
Boxing converts a second-class value to a first-class value, reifying the contextual information 
annotated on the binder into the boxed value’s type (e.g., f :C σ ⊢ box f : σ at C). 
That is, instead of completely preventing first-class values from closing over capabilities, the 
capabilities they close over are now faithfully represented in their types. To use a boxed block, 
we have to unbox it. We make sure to only perform this operation when the capabilities are 
still in scope, which guarantees effect safety (e.g., x : σ at C ⊢ unbox x : σ C). The 
reader might find the following analogy helpful: 
Conceptually, we treat mentioning capabilities as an effect. In the terminology of 
call-by-push-value [30], boxing corresponds to “thunking” and unboxing corresponds 
to “forcing” the effect of mentioning capabilities1. 
The box and unbox constructs allow programmers to freely move between tracking capabilities 
implicitly, via lexical scoping, or explicitly, in the types. 

### 1.4 Contributions and Overview

This paper makes the following contributions: An example driven introduction to programming in System C, a calculus that recon ciles scope-based and type-based reasoning in a language with advanced control effects (Section 3).

1 A more detailed comparision with call-by-push-value can be found in Section 6.8.

A formal presentation of System C with static and dynamic semantics (Section 4). The typing context in System C is enhanced with information about block binders, which only becomes visible in types when explicitly boxing blocks. A proof of progress and preservation (Theorems 3 and 5), and effect safety (Corollary 9). A full mechanization of the calculus, as well as proofs of the progress and preservation in the Coq theorem prover (Section 4.5.4). An evaluation in terms of an implementation (Section 5) and several small case studies. This paper is accompanied by an artifact consisting of an interactive demonstration and Coq proofs, archived under https://doi.org/10.5281/zenodo.5833713. Furthermore, Section 2 provides an in-depth presentation of the state-of-the-art and motivates our work. Section 6 offers a comparison with additional lines of related work.

### 2 Motivation

The motivation behind our work is to design a language that specifically features: 
Lexical reasoning. Programmers can determine lexically where an exception / effect is handled. 
Effect safety. The type system establishes that all exceptions (all effects) are eventually 
handled. 
Ergonomics. The verbosity of effect tracking in types is limited to where it is necessary. 
First-class functions. It should be possible to return effectful functions. 
No prior work that we are aware of meets all of the above criteria. In the remainder of this 
section, we will motivate each criterion and point out limitations of existing work. Readers 
who want to first learn more about our proposed solution can skip to Section 3 and can come 
back if necessary. 

### 2.1 Lexical Reasoning

Operationally, traditional implementations of (control) effects (such as exceptions or the more general algebraic effects) are dynamically scoped [11]. Consider, for instance, how exceptions behave in JavaScript:

function process(path) {(|1|) function abort() { throw("processing aborted") } try {(|2|) eachLine(open(path), line ⇒ {(|3|) /*. . .*/ abort() }) } catch { msg ⇒ /*. . . handle IO exception, raised by open . . .*/ }

} 
We define a function process that processes the contents of a file. To do so, it defines a local 
function abort that raises an exception, signalling that processing failed. Since opening a 
file might throw an exception, we additionally install an exception handler to deal with this 
error condition. We then call a higher-order function eachLine with a function argument 
which uses abort. 
The exception thrown by abort might be conceivably handled at three different source 
locations: Either ⃝1 by the call-site of process, ⃝2 by the handler inside process, or ⃝3 by 
a handler inside of eachLine. Depending on the specific example and use case, all three 
are valid choices the programmer could make. Now, what actually happens is that the 
exception will be handled by ⃝2 unless it happens to be handled by ⃝3 . This is impossible to 
know without inspecting the source code of eachLine. Moreover, to propagate the exception 

Brachthäuser, Schuster, Lee, and Boruch-Gruszecki 5 to ⃝1 , we would have to explicitly forward it from ⃝2 , without accidentally forwarding any other exceptions. This behavior is common to most languages such as JavaScript, ML, Java, Ruby, and many more. The underlying problem is that, traditionally, exceptions are dynamically scoped: the exception thrown by abort unwinds the call stack and the first catch clause relative to the dynamic call-site of abort handles it. As explained by Zhang et al. [55], higher-order functions such as eachLine, make it difficult for programmers to statically reason about where an exception will be handled. This behavior is not limited to exceptions but also applies to more general control operators, such as algebraic effect handlers [44].

Capabilities To facilitate reasoning about exception handlers in the presence of higher-order functions, Zhang et al. [55] argue for a different semantics based on lexical scoping. Recently lexically scoped exceptions have been generalized to lexically scoped effect handlers [54, 5, 9]. One particular way to obtain lexically scoped effects is to model effects as capabilities [21] and perform capability passing [9]. Consider the previous example in a hypothetical language with lexically scoped exceptions in explicit capability-passing style:

function process(path, exc1) { function abort() { exc1.throw("processing aborted") } try { exc2 ⇒ eachLine(open(path, exc2), (line, exc3) ⇒ { /*. . .*/ abort() }) } catch { msg ⇒ /*. . . handle IO exception . . .*/ }

}

Every exception handler introduces a term-level capability. Each of the three capabilities (e.g., exc1, exc2, exc3) corresponds to one of the previously marked positions where the exception thrown by abort might be handled. When we want to throw an exception, we have to use one such capability and the exception will be handled by the handler that introduced it. In the function argument of eachLine, we call abort, which in turn calls exc1.throw(. . .). By applying local reasoning it is immediately clear that the exception will be handled at the call-site of process. Moreover, it is directly possible to throw an exception to one of the other handlers, simply by using exc2 or exc3. For this to be safe it is necessary (but, as we will see, not sufficient) that the capabilities are in scope.

### 2.2 Effect Safety

The purpose of an effect system is to statically guarantee effect safety [38]. In the special case of exceptions this means that all exceptions are eventually caught. Enriching function types with effects enables programmers to reason about the presence and absence of particular effects of interest. However, types inferred by traditional type-and-effect systems can be verbose and difficult to understand. This is in particular the case for higher-order functions, where the types not only accurately reflect which effects the function uses, but also which effects it handles. Consider the following example in Koka [27], a language with a Hindley Milner style type system, featuring a row-based effect system, and dynamically scoped effects and handlers.

fun rethrow(func, prog) { handle ({ prog() }) except throw(msg) { throw(func(msg)) }

}

The example defines a useful helper function which catches all exceptions in prog and rethrows them after applying func to the message msg. Koka correctly infers the most

general type:

forall<a,e> (func: (string) → <exc|e> string, prog: () → <exc,exc|e> a) → <exc|e> a It abstracts over the result type a as well as effects e. The result type tells us that function rethrow itself uses effect exc and potentially other effects e to return a result of type a. Inspecting the inferred types of the argument functions sheds some light on how type-and effect checking in Koka (and other languages based on row polymorphism) works. There are two aspects, which we believe are difficult for programmers who are learning the language: 1. Maybe surprisingly, argument func is assigned effect <exc|e>, but why? Since the effect system is based on row-polymorphism, the effect of func has to unify with the effects of its calling context. So the effects of func(msg), of the handler body, and of the overall function have to unify. Operationally this is correct, since func may use exceptions. 2. Even more surprisingly, the type of argument function prog mentions two copies of exc. Again, operationally this is correct since prog might itself either throw an exception that is handled by rethrow, or one that is handled at the call-site of rethrow. Allowing duplicate entries is also necessary for soundness [26, 53]. The function rethrow in Koka is effect polymorphic. This is important because we want to pass effectful functions to it. Consider the following helper function in Koka, which prepends the current info string to all thrown exceptions.

fun prependInfo(prog) { rethrow(fun(str) { getInfo() ++ str }, prog) } It calls rethrow with a function which uses the info effect to express that the current info depends on the context. Koka infers the following type:

forall<a,e> (prog : () → <exc,exc,info|e> a) → <exc,info|e> a The argument to rethrow uses the info effect, which leaks into the inferred type of parameter prog – the problem of avoiding this issue is known as effect encapsulation [32]. Many other problems of existing type- and effect systems, accidental capture [55], or effect para metricity [54], can be tracked down to the operational semantics of the underlying language. The above type is correct and most general, but certainly not easy to understand. We believe, the frequent use of functions with many function parameters can render explicit polymorphism impractical. This scenario is common in OOP, where almost every method is higher-order [14].

### 2.3 Ergonomics

As an alternative to parametric effect polymorphism, second-class values admit a lightweight form of effect polymorphism. Consider the same function in Effekt, a language with lexical effect handlers [9]:

def rethrow[A] { func: String ⇒ String / {} } { prog: () ⇒ A / {Exc} }: A / {Exc} = try { prog() } with Exc { def throw(msg) ⇒ throw(func(msg)) } The signature of rethrow is polymorphic in the result type A, but does not abstract over any effects. No effect variables show up in types nor error messages. Yet, it features effect polymorphism and guarantees effect safety. This is because effect signatures in Effekt are relative to the calling context. The parameter func, enclosed in curly braces, denotes a so-called block – a second-class function. Blocks can use all effects from the context they were defined in; accordingly, func does not need to explicitly mention any effects in its type – it

Brachthäuser, Schuster, Lee, and Boruch-Gruszecki 7 simply can use them. This form of polymorphism is called contextual effect polymorphism [9]. To illustrate, let us consider the call-site in function prependInfo:

def prependInfo[A] { prog: () ⇒ A / {Exc} }: A / {Exc, Info} = rethrow { str ⇒ info() ++ str } { () ⇒ prog() }

The signature of prependInfo expresses that it can handle the exception effect used by prog 
and itself may use the exception and info effects. Notice how the first argument passed to 
rethrow is effectful (it uses info), even though the required type is String ⇒ String / {}. 
Guided by the types, Effekt translates to System Ξ, a core calculus in explicit capability 
passing style. 
def prependInfo[A](prog : Exc ⇒ A, exc1 : Exc, info : Info) : A = 
rethrow[A]({ str ⇒ info() ++ str} , { exc2 ⇒ prog(exc2) } , exc1) 
The function argument closes over capability info, hiding it in its closure. While this leads 
to concise signatures, it means we cannot require function parameters to not use certain 
effects! 

### 2.4 First-Class Functions

Effect safety for lexically scoped effect handlers means that a capability is only used while the corresponding handler is on the stack. In other words, capabilities shall not escape their handler. For example, the following program should be ruled out, since the capability exc leaks via closure:

try { exc ⇒ return (() ⇒ exc.throw("Unsound!")) } catch { . . . }

Type-based escape analysis [23] can provide this static guarantee. One particular solution is based on second-class values, which can be passed as arguments, but never be returned [41]. To establish effect safety, capabilities (like exc) need to be second class. But, as we have seen, functions can close over capabilities, hiding their use. In consequence, existing work either (a) distinguishes between first-class functions that cannot close over capabilities and second-class functions that can [41] or (b) treats all functions as second-class [9]. While many useful programs can still be written with such a restriction, both solutions come with a severe loss of expressivity.

### 2.5 The Best of Both Worlds

To summarize, capability-passing establishes lexical scoping between the binding-site of a capability and its use. Modeling effects as capabilities has multiple advantages. Firstly, programmers can re-apply their knowledge about variable binding to reason about effects. Secondly, combining it with a type-system based on second-class values results in a lightweight form of effect polymorphism, leads to simplified signatures, and avoids problems such as effect encapsulation. However, prior work imposes severe restrictions on the use of second class functions resulting in a significant loss of expressivity. Furthermore, second-class functions silently close over capabilities, which enables contextual effect polymorphism but also prevents type-based reasoning about purity. In the following section, we introduce System C, a language that lifts many of the above mentioned restrictions while preserving all the advantages of capability passing and second-class values.

### 3 Programming with System C

In this section, we will introduce System C and the underlying concepts by example.

### 3.1 Capabilities

One important aspect of System C is that it uses capabilities for authority control [16, 36, 35]. Operationally, a capability is an ordinary object with effectful methods. Holders of the capability are entitled to perform the corresponding effects. What makes capabilities special is that we want to keep track of their use in a program, to indirectly track the use of effects. To control access to capabilities, our system uses second-class values in the style proposed by Osvald et al. [41]—both capabilities and functions that close over them are second class. As we will see, our system allows transitioning back-and-forth between first- and second-class values. When converting to a first-class value, the (otherwise implicitly) captured capabilities become visible in its type (and only then). When transitioning back to second class, we use this information to decide whether the transition should be allowed.

Global capabilities Consider the following program written in System C.

def sayTime(): Unit { console.println("Current time is: " + time.now()) } It defines a block sayTime that prints the current time to the terminal. To do so, sayTime uses two capabilities: console and time. As expected of second-class values, this is not mentioned in the type, which is sayTime: () ⇒ Unit. Here, we rely on scope-based reasoning—we can reference both console and time, therefore we can use them. This intuition carries over to capability-polymorphic terms. Consider repeat, which takes a block parameter f and repeats it n times2.

def repeat(n: Int) { f: () ⇒ Unit }: Unit { if (n == 0) { () } else { f(); repeat(n - 1) { f }} }

Unlike traditional effect systems, in which repeat would need to be explicitly effect polymorphic, we rely on scope-based reasoning—repeat receives f as second-class argument, therefore it can use it. Similarly, wherever we can use a capability, we can also use it with repeat.

repeat(3) { () ⇒ console.println("Hello!") } repeat(3) { () ⇒ sayTime() }

### 3.2 Boxes

There are situations in which scope-based thinking fails us—we sometimes want to prevent a given term from being able to use some (or all) capabilities. For instance, consider a function parallel that takes two blocks and runs them in parallel:

def parallel { f: () ⇒ Unit } { g: () ⇒ Unit }: Unit parallel { () ⇒ console.println("Hello, ") } { () ⇒ console.println("world!") }

2 We enclose value parameters (and arguments) with parenthesis and use curly braces for block parameters (and arguments).

In this example, argument blocks can capture arbitrary capabilities. Evaluating them in parallel could perform non-deterministic side-effects or introduce data races. But how can we express a version of parallel that requires the function arguments to be pure? The answer in System C is: we transition to type-based reasoning:

def parallel(f: () ⇒ Unit at {}, g: () ⇒ Unit at {}): Unit

In this version, parallel now expects first-class functions as arguments. First-class functions are blocks whose types keep track of what set of capabilities they might reference. The functions passed to parallel need to be pure—they cannot reference any capabilities. Our problematic call to parallel now look as follows:

parallel( box {console} { () ⇒ console.println("Hello, ") }, // ill-typed! box {console} { () ⇒ console.println("world!") }) // ill-typed!

The type of either argument is () ⇒ Unit at {console}, making the above ill-typed3. Note how box marks the transition from scope-based to type-based reasoning. It takes a block and turns it into a first-class value. The boxed block can only access capabilities admitted by the boxed type. In the following, we manually annotate the box with {} and thus console cannot be accessed:

box {} { () ⇒ console.println("Hello, ") } // ill-typed!

To complete the picture, consider what capability sets would be inferred in the following term:

box {?} { () ⇒ sayTime() }

Intuitively, we should allow sets no smaller than {console,time}, since sayTime itself uses those capabilities. But how can System C infer this information and refuse programs like the ill-typed example above? The answer is that this information is kept at the binders itself. Which is to say, our system annotates the following blocks with capability sets:

def {console,time} sayTime() : Unit def {} repeat(n: Int) { f: () ⇒ Unit }: Unit def {console,time} sayTimeThrice(): Unit { repeat(3) { () ⇒ sayTime() } }

### 3.2.1 Local Capabilities

So far we have only discussed global capabilities, which prevented us from highlighting one important aspect of our approach to capabilities. In System C, neither capabilities nor blocks can be returned. Why do we want such a restriction? Consider the following term:

withFile("a.txt") { file ⇒ file.readByte(0) } Function withFile creates a capability to access a file, and passes it to a block. After the block terminates, withFile closes the handle and returns the result of the block. If we let the handle outlive the block, using it afterwards results in an error—this is precisely what we want to prevent. We could follow Osvald et al. [41] and Brachthäuser et al. [9] and forbid to

3 We use the notation { . . . } to display capability sets, which are inferred by the type checker and displayed by the IDE.

return any capabilities or functions that close over them. However, this is overly restrictive since sometimes we might want to return a capability from some scope, other than its own. ▶ Example 1. Consider that we may want to do the following: open file A.txt, open file B.txt, read B’s contents to define a block that then continues to read from A, return the block from the scope of file B so that we can use it. Naturally, our block will need to use the handle to A, so how can we return it? We box the block into first-class value, at which point we can see (based on its type) that returning it is safe. The above scenario can be modeled in System C as follows:

withFile("A.txt") { fileA ⇒val offsetReader : Int ⇒ Byte at {fileA} = withFile("B.txt") { fileB ⇒val offset = fileB.readByte(0); return box {fileA} { pos ⇒ fileA.readByte(pos + offset) }

}; (unbox offsetReader)(10)

} Note how in order to use offsetReader, we first need to unbox it. In System C, first-class functions cannot be used at all—they first need to be unboxed, which turns them back into second-class blocks4. We only allow unboxing when all the capabilities mentioned in the box’s type are in scope. The reason for why this is sound becomes apparent if we consider the previous sentence—since unboxing turns boxes back into second-class values, we can only unbox blocks in environments that anyway have access to no less than what the block has access to!

### 3.2.2 From Scope-Based Reasoning to Type-Based Reasoning and Back

Our notion of scope-based reasoning comes from the idea of second-class values [41]. The 
familiar concept of lexical scoping enables convenient and flexible reasoning about the use of 
effects [54, 9]. As already pointed out, not being able to return second-class values at all is 
an overly harsh restriction. Other than the example we have already seen, it immediately 
rules out the common technique of currying functions with second-class arguments. 
Our notion of type-based reasoning is inspired by an approach to reasoning about effects 
with capabilities introduced by Choudhury and Krishnaswami [12]. They demonstrate how 
to recover a notion of pure functions in a language that does not otherwise keep track of 
effects. The idea is to have a special type of values that are guaranteed to not have access 
to any capabilities. We take this idea and generalize it to keep track of which capabilities 
a value has access to. A function of type S ⇒ T at {} is known to be pure, but we are 
not limited to using the empty set in function types. An example is the value box sayTime, 
which has an inferred capability set of {console,time} . That is, we not only know that it is 
impure, but also which capabilities it closes over. 
System C harmoniously combines these two ways of reasoning about effects via capabilities 
and allows programmers to move between them. We mediate between blocks and functions 
by explicitly converting them with box and unbox, respectively. As long as blocks are used 
in a strictly second-class manner, by design, closing over capabilities is not visible to the 

4 In our implementation of System C, we infer almost all necessary boxing and unboxing operations. However, in the paper, for exposition we refrain from doing so.

Brachthäuser, Schuster, Lee, and Boruch-Gruszecki 11 programmer. However, as soon as a function is used as a first-class value, the capabilities come to light.

### 3.2.3 Capability Polymorphism

Effect systems based on capabilities give rise to a new notion of contextual effect polymor phism [9], as observed in the repeat example. Blocks passed to repeat can simply use all capabilities in their lexical scope. Since System C supports boxing blocks, this (so far invisible) polymorphism now can manifest itself in types:

def repeater { f: () ⇒ Unit }: Int ⇒ Unit at { f } { return box { n ⇒ repeat(n) { f } } } The return type of repeater uses a limited form of term dependent types to express capability polymorphism: intuitively, the returned function closes over any capabilities that f closes over. This becomes visible when calling repeater with sayTime, which closes over console and time:

val repeatTime : Int ⇒ Unit at { console, time } = repeater { sayTime }

By design, block arguments, such as f are always capability polymorphic. In contrast, block definitions, such as sayTime are always capability monomorphic. Only capabilities and polymorphic block variables are allowed to occur in capability sets.

3.3 Effect Handlers in System C 
System C combines the notion of second-class values with a particularly general and challenging 
language feature (already present in System Ξ): effect handlers [44, 45]. One potentially 
uncommon aspect of our effect handlers is that we use lexical effect handling in capability 
passing style [5, 9]. We briefly introduce effect handlers and refer the interested reader 
to other introductions [46]—the work by Zhang et al. [56] and Brachthäuser et al. [9] is 
particularly similar in syntax and semantics to our approach. Potentially the simplest and 
most familiar application of effect handlers are exceptions. 

try { console.println("hello"); exc.throw("world"); console.println("done") } with exc: Exc { def throw(msg: String) { console.println(msg + "!") } }

After printing the string "hello", by invoking exc.throw, control flow is transferred to the handler, which simply prints the string "world!". The final call to println is unreachable. Handlers introduce capabilities, such as exc, which here has type Exc. The attentive reader will notice a potential problem—if capabilities are terms, what happens if we perform exc.throw outside of the enclosing try? The answer is: exc is a block and cannot leave the enclosing scope. As such, exc.throw can only be performed when it is handled. Trying to return it will yield a type error:

try { return (box {exc} exc) } with exc: Exc { . . . } // type error The type of the boxed capability is Exc at {exc}, which is not well-formed outside of the corresponding handler that binds it. Unlike exceptions, effects handlers in our system are not limited to aborting the computation—they can continue it at the original call to the capability.

| 12 Effects, | | | Capabilities, and Boxes | |
| --- | --- | --- | --- | --- |
| | | val | before = time.now(); | |
| | | try | { console.println(watch.elapsed()) } | with watch: Stopwatch { |

def elapsed() { resume(time.now() - before) }

}

Again, the handler introduces a capability of type Stopwatch. However, this time the handler implementation resumes the computation by passing a value of type Int, the return type of the effect operation. Interestingly, the continuation resume closes over both the capabilities used by the handled program, as well as the capabilities used by the handler itself. In this case, we have box {console,time} resume since the handled program uses console and the handler uses time.

### 3.4 Conclusion

System C combines two approaches to effects via capabilities: scoped-based reasoning (which admits lightweight polymorphism) and type-based reasoning (which enables reasoning about absence). We can move between the two styles with box and unbox.

### 4 Formal Presentation

In this section, we formally present the syntax, static and dynamic semantics of System C, and highlight meta-theoretic properties. The presentation follows the one of Brachthäuser et al. [9]. For clarity, and to focus on the novel aspects of System C, we omit type polymorphism from our presentation of System C, which is largely orthogonal to the rest of our calculus (Section 5.1). We highlight some important aspects of the calculus, which we will discuss later in full detail5.

Computation and values Since the calculus supports control effects via effect handlers, it is presented in fine-grain call-by-value [31]. We syntactically distinguish statements, which may perform effectful computation (that is, they are serious in the terminology of Reynolds [47]), from expressions and blocks, which are pure (that is, trivial) and cannot perform effects.

Values and blocks Following Brachthäuser et al. [9], we separate the universe of values into expression values that are considered first-class [41] and block values, which we consider second-class. To emphasize the first-class nature of expression values, we often speak of values and blocks. Importantly, blocks may implicitly close over capabilities, whereas values are explicit and reveal captured capabilities in their type. Syntactically, we distinguish between variables that stand for expression values (x, y, . . . ) and variables that stand for block values (f, g, . . . ). The stratification can also be observed on the level of types, where we introduce value types τ and block types σ, correspondingly.

Boxing and unboxing Blocks can be lifted into values by boxing—reifying contextual infor mation in the type; (function) values can be lowered into blocks by explicit unboxing—making capture information contextually available.

5 An extended technical report [10] includes our calculus and its operational semantics in more detail.

### 4.1 Syntax

Figure 1 defines the syntax of System C. We have syntactic categories for expressions, blocks, 
and statements. Only statements can perform effectful computation. As usual, we follow 
Barendregt [3] and require that all variable names are globally unique. 
Syntax: 
Expressions e ::= x expression variables 
| () | 0 | 1 | ... | true | false | ... primitives 
| box b box introduction 
Blocks b ::= f block variables 
| { (ÐÐÐÐ⇀ xi : τ i,ÐÐÐÐ⇀ fj : σj) ⇒ s } block implementation 
| unbox e box elimination 
Statements s ::= def f = b; s block definition 

| b(Ð⇀ ei ,Ð⇀ bj) block application | val x = s; s sequencing | return e returning | try { f ⇒ s } with { (Ð⇀ xi , k) ⇒ s } handlers

Types: Value Types τ ::= Int | Boolean | ... base types | σ at C boxed block types

Block Types σ ::= (Ð⇀ τ i,ÐÐÐÐ⇀ fj : σj) → τ Capabilities C ::= ∅ | {f } | C ∪ C Environments: Environments Γ ::= ∅ empty environment | Γ, x : τ value bindings 
| Γ, f :∗ σ tracked bindings 
| Γ, f :C σ transparent bindings 
Figure 1 Syntax of the language System C – differences to System Ξ highlighted in grey . 

### 4.1.1 Expressions

Expressions are either variables, primitives, or boxed blocks. The evaluation of expressions never has side effects. We could add, for example, integer addition to the syntactic category of expressions. Boxing a block (i.e., box b) performs no side effects either, and only reifies the information about its captured capabilities from the typing context into the type of the resulting boxed block. The ability to box blocks presents a significant extension to other calculi with first- and second-class values [41, 9], because it allows a second-class block b to be lifted to become a first-class value v.

### 4.1.2 Blocks

Blocks in System C play the role of functions in other languages. In contrast to traditional functions in other lambda calculi, our blocks are multi-arity to avoid the complexity of currying in effectful languages. Blocks come in two forms: block literals and unboxed values.

Block literals are of the form { (ÐÐÐÐ⇀ xi: τ i,ÐÐÐÐ⇀ fj: σj) ⇒ s }. They simultaneously abstract over multiple value parameters xi : τ i as well as multiple block parameters fj: σj. The body of a block literal is a (potentially effectful) statement. Unboxing an expression with (unbox e) re-embeds the first-class (function) value e into the universe of blocks. Boxing and unboxing are inverse operations of each other and we have that box (unbox e) ≡ e as well as unbox (box b) ≡ b.

### 4.1.3 Statements

Finally, statements represent potentially effectful comput

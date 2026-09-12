---
source_url: https://www.irif.fr/~gc/papers/elixir-type-system.pdf
ingested: 2026-09-12
sha256: 8da8147bb266c551f67960798d9053c6c8bd62051db1532bcb503b8a4cf09b37
---
# Guard Analysis and Safe Erasure Gradual Typing:  a Type System for Elixir

GUARD ANALYSIS AND SAFE ERASURE GRADUAL TYPING: A TYPE SYSTEM FOR ELIXIR

GIUSEPPE CASTAGNA

a

AND GUILLAUME DUBOC

a,b

a

Institut de Recherche en Informatique Fondamentale, Universit´e Paris Cit´e, CNRS, France

b

Remote Technology, France

Abstract. We formalize a new type system for Elixir, a dynamically typed functional programming language of growing popularity that runs on the Erlang virtual machine. Our system combines gradual typing with semantic subtyping to enable precise, sound, and practical static type analysis, without requiring any changes to Elixir’s compilation pipeline or runtime. Type soundness is ensured by leveraging runtime checks—both implicit, from the Erlang VM, and explicit, via developer-written guards. Central to our approach are two key innovations: the notion of strong functions, which can be assigned precise types even when applied to inputs that may fall outside their intended domain; and a fine-grained analysis of guards that enables accurate type refine ment for case expressions and guarded function definitions. While type information is erased before execution and not used by the compiler, our safe erasure gradual typing strategy maintains soundness and expressiveness without compromising compatibility or performance. This work lays the theoretical foundation for Elixir’s new type system, out lines its integration into recent versions of the language, and demonstrates its effectiveness on large-scale industrial codebases.

1. Introduction

Elixir is an open-source dynamic functional programming language that runs on the Beam, 
the Erlang Virtual Machine [Ste24]. It was designed by Jos´e Valim for building scalable 
and maintainable applications with a high degree of concurrency and seamless distribution. 
Its characteristics have earned it a surging adoption by hundreds of industrial actors like 
Discord and PepsiCo, and tens of thousands of developers. 
Elixir is, in essence, a minimalist language, with most of its constructs being syntactic 
sugar for the language’s core expressions: functions and pattern matching. Despite being a 
dynamically-typed language, there exist tools to perform static analysis on Elixir programs, 
such as Dialyzer [LS06] or Gradualizer [Sve], and attempts have been made at forming a 
theoretic basis to type it, but with clear limitations [CTPV20]. 
To answer the developers’ demand for a stricter, more expressive, and informative type 

system for Elixir, four years ago we started a collaboration with Jos´e Valim and the Elixir development team to study how set-theoretic types augmented with the dynamic type of gradual typing could be used to introduce static typing into Elixir. The results of this

Preprint submitted to Logical Methods in Computer Science

© GUARD ANALYSIS AND SAFE ERASURE GRADUAL TYPING: A TYPE SYSTEM FOR ELIXIR ⃝ CC Creative Commons

collaboration are presented in two distinct companion articles that address fundamentally 
different aspects of the type system design. 
The first article [CDV24] describes the design principles of the type system for Elixir 
and the roadmap to progressively integrate it along the various Elixir releases. The approach 
assumes that the type system will begin by analyzing currently untyped code to catch simple 
errors, and will then progressively evolve as Elixir programmers start annotating their code 
with types, gradually adding more and more of them until they reach a fully statically 
typed program. The second companion article is the present one, which provides the formal 
theoretical foundation by formalizing a type system that solves the technical difficulties of 
fitting the system outlined in [CDV24] into a language like Elixir. 
These companion articles are designed to work in tandem while serving different pur 
poses and targeting distinct audiences. The first companion article targets Elixir program 
mers and serves as a sort of preliminary tutorial on the concepts related to types. This 
second companion article, in contrast, addresses type theorists and language implementers, 
providing the rigorous formalization of the type system, various algorithms used for type 
checking, some hints to the techniques used to implement types and the typing rules, as 
well as the characterization and proofs of the type safety results that underpin the practi 
cal approach described in its companion. It constitutes an essential resource for language 
implementers who seek to develop a type system for a dynamic language—particularly, 
an existing language with substantial codebases—following the design principles outlined 
in [CDV24]. 
This companion article maintains a more focused scope than the first. As stated in the 
title, we concentrate specifically on the distinguishing characteristics of the system: how 
to perform precise analysis of guards used in pattern matching and how to maximize the 
precision of the gradual type system without modifying Elixir compilation (the “erasure” 
in the title) while preserving type soundness (the “safe” in the title). Other aspects of 
the type system which are discussed in the first companion article—such as parametric 
polymorphism, records and maps, modules and protocols—are deliberately not covered 
here, as they are orthogonal to the gradual typing features that constitute the central 
contribution of this second work. 

1.1. Distinctive Features of the Type System. The main novel idea of our type system may be strong functions, which is formalized in Section 2. In the theory and application of gradual typing, there is a clear rift between two kinds of gradually typed languages. Firstly, those that treat the dynamic() type of gradual typing (also known as any, mixed, or unknown, according to the language) as a liability that needs to be checked; to preserve their soundness, these languages (e.g., Reticulated Python [Vit]) use different strategies to insert type-checks into their runtime to protect statically typed parts of their code from dynamically typed ones. But for some languages, such as TypeScript [BAT14], this is not an option as the runtime does not check types by default. Hence, a second way for gradual systems is to resort to full erasure: the type annotations of a TypeScript program leave no trace in the JavaScript emitted by the compiler.

1

In that case the static analysis cannot leverage the runtime to enforce type properties and, therefore, it produces a coarser type approximation. This often pushes full erasure type systems towards unsoundness, since it forces the implementer to make a crucial design choice: either the type system is sound but

1The “erasure” refers to the removal of static type information: types may still be present in the runtime.

provides little information, due to a pervasive use of the dynamic type; or the type system 
is more informative thanks to a more liberal use of the dynamic type, but this flexibility is 
unsound and may thus lead to runtime crashes. 
However, our situation is more nuanced. Although Elixir is dynamically typed, it is 
compiled and then executed on the Erlang VM which, itself, is type-safe through explicit 
runtime type-checks. Furthermore, programmers can introduce such checks explicitly by 
writing them into guards. Hence, we had the opportunity to quantify how much checking 
the VM actually does, and integrate that into our plans for a gradual type system. The 
concept of strong functions directly comes from that: these are functions whose input and 
output types are entirely or partially checked by the VM either because of checks inserted 
by the programmer or by standard checks performed by the VM; hence, it is possible even 
when applied in uncertain conditions (when dynamically typed code is involved) to give 
their result a static type. This approach, that we call safe-erasure gradual typing, refers to 
the fact that, although no checks are inserted into the language related to the types asserted 
by the typechecker, this “type erasure” is safe, because the type-checker knows which parts 
of the code are checked by the VM or the programmer, and which are not. Practically, this 
means that the typechecker can be more precise in its analysis, and infer a type without 
any dynamic() components, even in places where a dynamic() type was statically used, 
because it knows that the VM will check the type of the value at runtime. A requirement for 
this approach to work is to be able to extract as much (necessarily, static) type information 
from Elixir guards as possible, which is the subject of the technical analysis developed in 
Section 3. We will provide a finer placement of our work with respect to current literature 
on gradual typing in Section 9 on related work. 
A key to the success of our approach is the use of semantic subtyping, which allows 
us to use set-theoretic type operators (union, intersection, difference), but also provides us 
with a decidable subtyping relation [FCB08, CX11], which appears crucial especially in the 
analysis of guards. Indeed, this analysis constantly mixes very precise conditions on types 
(including singleton types), and uses intersections, differences, and unions to refine these 
results. It would not otherwise be possible to guarantee such a level of precision, and the 
pattern matching would end up being grossly approximated. 

1.2. A Walkthrough of the Work. The type system of Elixir described by [CDV24] is a gradual polymorphic type system based on the polymorphic type system of CDuce [CNX +14, CNXA15]. In this work, we describe the five main novelties that are missing in the CDuce type system in order to type Elixir programs, presenting them one by one. These are the techniques of (i) strong function typing and (ii) propagation of the dynamic() type neces sary for safe-erasure gradual typing, both described in Section 2; the (iii) guard analysis described in Section 3; the typing (and subtyping) of (iv) multi-arity functions presented in Section 4; the (v) type inference for anonymous functions described in Section 5. In this section, we are going to present them one after the other by giving some small exam ples that should help the reader understand the technical developments described in the following sections.

1.2.1. Soundness. The type system we define here satisfies the following soundness property

If an expression is of type t, then it either diverges, or produces a value of type t, or fails on a dynamic check either of the virtual machine or inserted by the programmer The formal statement of this property is more articulated and given in Theorem 2.3. The system is gradual since the type syntax includes a dynamic() type used to type expressions whose type is unknown at compile time. 2 The soundness guarantee above is typical of the so-called sound gradual typing approaches. These approaches ensure soundness by using typing derivations to insert some suitable dynamic checks at compile time. Our system, instead, does not modify Elixir standard compilation: types are not used for compilation and are erased after type-checking. Our system is, thus, a type-sound (i.e., safe) erasure gradual typing system, the first we are aware of. In particular, the compiler does not insert any dynamic check in the code apart from those explicitly written by the programmer. Therefore, our system must ensure soundness by considering only the checks written by the programmer or performed by the Beam machine. Writing a sound gradual type system for Elixir is easy: since every Elixir computation that does not diverge or fail on a dynamic check returns a value (no stuck terms, thanks to the Beam), then a system that types every expression by dynamic() is trivially sound . . . but hardly useful. Therefore, we need a system that must fulfill two opposite requirements (1) it must use dynamic() as little as possible so as to be useful, and (2) it must use dynamic() enough so as not to hinder the versatility of gradual typing The first requirement is fulfilled by the typing of strong functions, the second requirement by the propagation of dynamic() . We will demonstrate both of these aspects next.

1.2.2. Strong functions (Section 2). Consider the definition in Elixir of a function second that selects the second projection of its argument ( elem(e, n) selects the (n+1)-th projec tion of the tuple e):

| 1 | def second(x), do: elem(x,1) |
| --- | --- |
| | If the argument of the function is not a tuple with at least two elements, then the Beam raises a runtime exception. The function definition above is untyped. We can declare its type by preceding it by a $-prefixed type declaration, as in |
| 2 3 | dynamic() -> dynamic() $ def second(x), do: elem(x,1) |
| | second This is one of the simplest types we can declare for , since it essentially states that second is a function, and nothing more: it expects an argument of an unknown type and— second unless it diverges or fails—returns a result of an unknown type. We can give a type slightly more precise than (i.e., a subtype of) the type above, that is: |
| 4 | {dynamic(), dynamic(), ..} -> dynamic() $ |

2In Elixir, type identifiers end with () , e.g., integer() , boolean() , none() , dynamic() , etc.

GUARD ANALYSIS AND SAFE ERASURE GRADUAL TYPING: A TYPE SYSTEM FOR ELIXIR 5 which states that the argument of a function of this type must be a tuple with at least two elements of unknown type (the trailing “ .. ” indicates that the tuple may have further elements). With this declaration, the application of second to an argument not of this type will be statically rejected, thus statically avoiding the runtime raise by the Beam. We can give to the function also a type that is non-gradual, that is, a type in which dynamic() does not occur—we call such types static types—, such as:

5 $ {term(), integer()} -> integer()

or more generally:

6 $ {term(), integer(), ..} -> integer()

where term() is Elixir’s top type that types all values. Both these type declarations state that second is a function that takes (in the first type) a pair or (in the second type) more generally a tuple whose second element is an integer, and returns an integer. If this is the type declared for second , then the type deduced for the application second({true,42}) is, as expected, integer() . If dyn is an expression of type dynamic() , then the type deduced for second(dyn) will be dynamic() : if dyn evaluates into a tuple with at least two elements, then the application will return a value that can be of any type, thus we cannot deduce for it a type more precise than dynamic() . This differs from current sound gradual typing approaches, which would deduce integer() for this application, but also insert a runtime check that verifies that the result is indeed an integer. However, this is not the way an Elixir programmer would have written this function. If the programmer intention is that second had type {term(), integer(), ..} -> integer() , then the programmer would rather write it as follows: 3

7 $ {term(), integer(), ..} -> integer() 
8 def second_strong(x) when is_integer(elem(x,1)), do: elem(x,1) 

This is defensive programming. The programmer inserts a guard (introduced by the key word when ) that checks that the argument is a tuple whose second element is an integer (the analysis of this kind of complex guards is the subject of Section 3). Thanks to this check (which makes up for the one inserted at compile time by other sound gradual typing ap proaches) we can safely deduce that second_strong(dyn) has type integer() . A function like second_strong is called a strong function, because the programmer inserted a dynamic check that ensures that even if the function is applied to an argument not in its declared domain, it will always return a result in its declared codomain—i.e., integer() —or fail. This allows the system to deduce for second_strong(dyn) the type integer() instead of dynamic() , thus fulfilling our first requirement. A function can be strong not only because it was defensively programmed, but also thanks to the checks performed at runtime by the Beam, as for:

3Elixir’s type system inherits parametric polymorphism from CDuce (see [CDV24]). So a more precise type for second would use a type variable a which in Elixir is quantified postfixedly by a when clause: {term(), a, ..} -> a when a: term() . We do not consider polymorphism here since it is orthogonal to the features under study in this work.

| 9 10 | {term(), integer(), ..} -> integer() $ def inc_second(x), do: elem(x,1) + 1 |
| --- | --- |
| | which is also strong because the Beam virtual machine dynamically checks that both ar integer() elem(x,1) . In other terms since is an guments of an addition are of type is_integer(elem(x,1)) operand of an addition, the Beam performs the check that in second_strong was explicitly added by the programmer. Therefore, also in this case, we know that if the function returns a value, then this value is an integer. Therefore, we can integer() inc_second(dyn) safely deduce the type for and, thus, for instance, that the inc_second(dyn) + second_strong(dyn) addition is well typed. To determine whether a function is strong, we define in Section 2 an auxiliary type system that checks whether the function, when applied to arguments not in its domain, returns results in its codomain or fails. dynamic() (Section 2). In fact, for both the above applications, 1.2.3. Propagation of inc_second(dyn) second_strong(dyn) and , our system deduces a type better than (i.e., a integer() integer() and dynamic() : it deduces . This is an intersection type, subtype of) integer() dynamic() meaning that its expressions have both type and type . The system dynamic() dyn propagates the type of the argument of the applications into the result. This is meant to preserve the versatility of the gradual typing that originated the applica tion, thus fulfilling our second requirement: expressions of this type can be used wherever integer() an integer is expected, but also wherever any strict subtype of (e.g., natural numbers) is. To see the advantages of this propagation, consider the following example that we also use to introduce more set-theoretic type connectives: |
| 11 12 | def negate(x) when is_integer(x), do: -x def negate(x) when is_boolean(x), do: not x |
| | negate The definition of is given by multiple clauses tested in the order in which they negate appear. When is applied, the runtime first checks whether the argument is an x integer, and if so, it executes the body of the first clause, returning the opposite of ; otherwise, it checks whether it is a Boolean, and if so returns its negation; in any other case the application fails. Multi-clause definitions, thus, are equivalent to (type-)case expressions (and indeed, in Elixir they are compiled as such). The usual static checks of redundancy and exhaustiveness that are standard for case expressions apply here, too. For instance, if we negate integer() -> integer() declare to be of type , then the type system warns that negate term() -> term() the second clause of is redundant 4; if we declare for it the type instead, then the function is not well-typed since the clauses are not exhaustive. To type or the function above without any warning, we can use a union type, denoted by : |
| 13 | integer() or boolean() -> integer() or boolean() $ |

4It is just a warning and not an error, since while the declaration states that the function is to be applied only integer expressions, arguments with a dynamic type are possible

GUARD ANALYSIS AND SAFE ERASURE GRADUAL TYPING: A TYPE SYSTEM FOR ELIXIR 7 which states that negate can be applied to either an integer or a Boolean argument and returns either an integer or a Boolean result. Next, let us consider the following definition 5

| 14 15 | $ def | dynamic(), dynamic() -> integer() subtract(a, b), do: a + negate(b) |
| --- | --- | --- |
| | and that, fails). negate(b) of system by issue, we is in the would integer() | subtract see whether it type-checks. The type declaration states that is a function when applied to two arguments of unknown type, returns an integer (or it diverges, or b dynamic() Since the parameter is declared of type , then the system deduces that (integer() or boolean) and dynamic() dynamic() is of type (the in the type b is propagated into the type of the result). To fulfill local requirements, the static type dynamic() can assume to become any type at run-time: following the terminology dynamic() [CLPS19], we say that can materialize into any other type. In the case at addition expects integer arguments. Therefore, the function body is well typed only if integer() negate(b) can deduce for . This is possible since the type of this expression (integer() or boolean) and dynamic() dynamic() and the system can materialize the integer() integer() thus deriving (a type equivalent to) . there to dynamic() Notice the key role played in this deduction by the propagation of : had negate(b) integer() or boolean() system deduced for just the type , then the body have been rejected by the type system since additions expect arguments of type integer() or boolean() , and not of type . subtract A similar problem would happen had we declared to be of type |
| 16 | $ | integer(), integer() -> integer() |
| | In enough for solution | integer() or boolean() -> integer() or boolean() that case, the type is not good negate b integer() for : since we assume to be of type , then the type deduced negate(b) (integer() or boolean()) is again which is not accepted for additions. The negate is to give a better type by using the intersection type |
| 17 | $ | (integer() -> integer()) and (boolean() -> boolean()) |

which is a subtype of the previous type in line 13, and states that negate is a function that returns an integer when applied to an integer and a Boolean when applied to a Boolean. This type allows the type system to deduce the type integer() for negate(b) whenever b is an integer. This example shows why it is important to specify (or infer) precise intersection types for functions. The inference system we present in Section 5 will infer for an untyped definition of negate the intersection of arrows in line 17 rather than the less precise arrow with unions of line 13. Finally, we want to signal that the latest typing of negate given in line 17 does not modify the propagation of dynamic() : the type deduced for negate(dyn) with the second type declaration is again (integer() or boolean) and dynamic() .

5Notice the difference between the type dynamic(), dynamic() -> integer() below and the type {dynamic(), dynamic()} -> integer() : the former is a type of a function that takes two arguments, while the latter is a type of a function that takes one argument of type {{dynamic(),dynamic()}} (i.e., a pair).

1.2.4. Guard Analysis (Section 3). Until now, the guards employed in our examples pri marily involve straightforward type checks on function parameters (e.g., is_integer(a) , is_boolean(x) ). The system we investigate for safe-erasure gradual typing in Section 2 exclusively focuses on these kinds of tests. There is a single exception in our examples with a more intricate guard, specifically is_integer(elem(x,1)) used in line 8. In Elixir, guards can encompass complex conditions, utilizing equality and order relations, selection opera tions, and Boolean operators. To illustrate the range of possibilities, consider the following (albeit artificial) definition:

18 def test(x) when is_integer(elem(x,1)) or elem(x,0) == :int, do: elem(x,1) 19 def test(x) when is_boolean(elem(x,0)) or elem(x,0) == elem(x,1), do: elem(x,0)

The first clause of the definition of test executes when the argument is a tuple where either 
the second element is an integer or the first element is the atom :int (in Elixir, atoms are 
user-defined constants prefixed by a colon). The second clause requires its argument to be 
a tuple in which the first element is either equal to the second element or is a Boolean. 
To type this kind of definitions, the type system needs to conduct an analysis char 
acterizing the set of values for which a guard succeeds. Section 3 presents an analysis 
that characterizes this set in terms of types. In some cases, it is possible to precisely 
represent this set with just one type. For example, the set of values that satisfy the 
guard is_integer(elem(x,1)) of the function second_strong in line 8, corresponds ex 
actly to the values of type {term(), integer(), ..} . Likewise, the arguments that sat 
isfy the guard of the first clause of test in line 18 are precisely those of the union type 
{term(), integer(), ..} or {:int, term(), ..} , where :int denotes the singleton type 
for the value :int . 6 However, such a precision is not always achievable, as demonstrated 
by the guard in the second clause of test (line 19). Since it is impossible to charac 
terize by a type all and only the tuples where the first two elements are equal, we have 
to approximate this set. To represent the set of values that satisfy such guards, we use 
two types—an underapproximation and an overapproximation—referred to as the surely 
accepted type (since it contains only values for which the guard succeeds) and the possibly 
accepted type (since it contains all the values that have a chance to satisfy the guard). 7 
For the guard in line 19, the surely accepted type is {boolean(), ..} since all tuples 
whose first element is a Boolean satisfy the guard; the possibly accepted type, instead, is 
{term(), term(), ..} or {boolean()} since the only values that may satisfy the guard 
are those with at least two elements, or those with just one element of type boolean() . 
When the possibly accepted type and the surely accepted type coincide, they provide a pre 
cise characterization of the guard, as demonstrated in the two previous examples of guards 
(lines 8 and 18). 
The type system uses the possibly/surely accepted types to type case-expressions and 
multi-clause function definitions. In particular, to type a clause, the system computes all the 
values that are possibly accepted by its guard, minus all those that are surely accepted by 
a previous clause, and uses this set of values to type the clause’s body. For example, when 

6We use {:int, term(), ..} rather than {:int, ..} , since the absence of a second element would make the guard fail. 7Formally, the surely accepted type is the largest type contained in all types containing only values that satisfy the guard, and the possibly accepted type is the smallest type containing all types that contain only values that satisfy the guard.

GUARD ANALYSIS AND SAFE ERASURE GRADUAL TYPING: A TYPE SYSTEM FOR ELIXIR 9 declaring test to be of type {term(), term(), ..} -> term() , the system deduces that the argument of the first clause has type {term(), integer(), ..} or {:int, term(), ..} .

For the second clause, the system subtracts the type above from the possibly accepted type 
of the second clause’s guard (intersected with the input type, i.e., {term(), term(), ..} ), 
yielding for x the type {not(:int), not(integer()), ..} , that is, all the tuples with at 
least two elements where the first is not :int ( not t denotes a negation type, which types 
all the values that are not of type t) and the second is not an integer. 
If the difference computed for some clause is empty, then the clause is redundant and a 
warning is issued. This happens, for instance, for the second clause of test , if we declare for 
the function test the type {:int, term(), ..} -> term() : all arguments will be captured 
by the first clause. 
If the domain of the function (or, for case expressions, the type of the matched ex 
pression) is contained in the union of the surely accepted types of all the clauses, then 
the definition is exhaustive. For instance, this is the case if we declare for test the type 
{term(), boolean()} -> term() . If, instead, it is contained only in the union of the pos 
sibly accepted types, then the definition may not be exhaustive, and a warning is emitted 

as for declaring {term(), term(), ..} or {boolean()} -> term() . In all the other cases, the definition is considered ill-typed, as for a declared type tuple() -> term() (where tuple() is the type of all tuples), since a tuple with a single element that is not a Boolean is an argument in the domain that cannot be handled by any clause. As a matter of fact, the guard analysis we present in Section 3 produces for each guard a result that is far more refined than just the possibly and surely accepted types for the guards. For each guard, the analysis partitions both the possibly accepted and the surely accepted types into smaller types that are then used by the inference of Section 5 to produce a typing for non-annotated functions. For instance, for the non type-annotated version of test given in lines 18–19 the guard analysis will produce four different input types that the inference of Section 5 will use to deduce the following intersection type for test :

20 $ ({term(), integer(), ..} -> integer()) and 
21 ({:int, term(), ..} -> term()) and 
22 ({boolean()} or {boolean(), not(integer()), ..} -> boolean()) and 
23 ({not(boolean() or :int), not(integer()), ..} -> not(boolean() or :int)) 

Splitting the domain of test as in the code above is not so difficult since its guards use the connective or and, as we will see, to compute the split, the system in Section 3 nor malizes guards into Boolean disjunctions. Notice, however, that the analysis must take into account the order in which the guards are written. If in line 19 we use the guard elem(x,0) == elem(x,1) or is_boolean(elem(x,0)) , that is, if we swap the order of the operands of the guard, then the arrow type in line 22 is no longer correct, since the applica tion test({true}) would fail and, therefore, the type {boolean()} must not be included in the domain of the arrow in line 22.

1.2.5. Multi-arity Functions (Section 4). At lines 14-15 we defined the function subtract which has two parameters. This arity is reflected in its type, where its domain consists of two comma-separated types (see also Footnote 5). All the other functions that were hitherto given as examples are unary. While the distinction between unary and binary functions may seem trivial to a programmer, it holds significant implications for the type

10 GUARD ANALYSIS AND SAFE ERASURE GRADUAL TYPING: A TYPE SYSTEM FOR ELIXIR system. The CDuce type system can only handle unary functions, and simulates n-ary functions as unary functions on n-tuples. But this is not sufficient in Elixir. First, applying a function to two arguments or to a pair involves different syntaxes, e.g., subtract(42,42) and test({42,42}) . Second, a programmer can explicitly test whether a function f has arity n using is_function(f,n) . In order to precisely characterize the set of values accepted by such a guard, we need a type system in which it is possible to express the type of all functions of a given arity. For instance, we may want to give a type to:

| 24 25 | def curry(f) when is_function(f,2), do: fn a -> fn b -> f.(a,b) end end def curry(f) when is_function(f,3), do: fn a -> fn b -> fn c -> f.(a,b,c) end end end |
| --- | --- |
| | but in current systems with semantic subtyping, we can only express the type of all functions, 8 none() -> term() that is, . Simulating, say, binary functions with functions on pairs {none(), none()} -> term() does not work since would not be the type of all binary functions: since the product with the empty set gives the empty set, this type is equivalent none() -> term() to , the type of all functions. This is the reason why we introduced ,tn) -> t the syntax that outlines the arity of the functions. Now the type of all (t1,· · · (none(), none()) -> term() binary functions can be written as , and we can declare for curry the function the following type (though, type variables or even a gradual type would be more useful than this type). |
| 26 27 | (((none(), none()) -> term()) -> none() -> none() -> term()) and $ (((none(), none(), none()) -> term()) -> none() -> none() -> none() -> term()) |

All this requires modifications, both in the interpretation of types and in the algorithm that decides subtyping, that we describe in Section 4.

1.2.6. Inference (Section 5). In a couple of examples we highlighted our system’s ability 
to deduce the type of a function even in the absence of explicit type declarations. For 
instance, we said that our type system can infer for negate (lines 11–12) the intersection 
type in line 17, and for test (lines 18–19) the type in lines 20–23. This kind of inference 
is different from the inference performed for parametric polymorphism by languages of the 
ML family. Instead of generating and solving unification constraints to deduce the type 
of function parameters, it leverages the guard analysis of Section 3 to derive the type of 
guarded functions: it simply considers the guards of the different clauses of a function 
definition as implicit type declarations for the function parameters, and use them for type 
inference. 
This kind of inference is used when explicit type declarations are omitted. This is partic 
ularly valuable for anonymous functions of which we saw a couple examples in the definition 
of curry (lines 24–25) where the body of the two clauses consists of anonymous functions. 
The goal of this kind of inference is to avoid imposing an obligation on programmers to 
explicitly annotate anonymous functions as in: 

8A value is of type s -> t iff it is a function that when applied to an argument of type s, it returns only results of type t; thus, every function vacuously satisfies the constraint none() -> term() , which only requires its values to be functions, as there is no value of type none() .

| 28 29 | list(integer()) -> list(integer()) $ def bump(lst), do: List.map(fn x when is_integer(x) -> x + 1 end, lst) |
| --- | --- |
| | is_integer(x) Here, the guard already provides the necessary information, making ex plicit annotations superfluous. Additionally, we view the use of an untyped or anonymous function as an implicit application of gradual typing. We have seen in §1.2.3, that when ever gradual typing was explicitly introduced by an annotation, the system propagated dynamic() in all intermediate results so as to preserve the versatility of the initial gradual dynamic() typing. We do the same here and propagate the (implicit use of) in the re sults of the anonymous/untyped functions by intersecting their inferred type with an extra -> dynamic() t arrow of the form , where t is the domain inferred for the function. For negate example, the type inferred for will be the type in line 17 intersected with the type integer() or boolean() -> dynamic() , while the intersection type in lines 20–23 inferred test {term(), term(), ..} or {boolean()} -> dynamic() for will have an extra arrow . (integer() -> integer()) and (integer() -> dynamic()) Likewise, the type will be given bump (line 29); this type is equivalent to the to the anonymous function in the body of integer() -> (integer() and dynamic()) simpler type . All these concepts are formalized in Section 5. 1.2.7. Featherweight Elixir (Section 6). The theoretical developments presented in this work are not directly formalized for Elixir, but rather for a λ-calculus enriched with tuples and case-expressions on patterns and guards. To make explicit the connection between this λ-calculus—called Core Elixir—and Elixir itself, we identify in Section 6 a subset of Elixir, called Featherweight Elixir, that covers all the examples presented in this section. While the correspondence between the expressions of Core Elixir and FW-Elixir is straightforward, the correspondence between patterns and guards is more subtle. To simplify the type analysis, the type tests of Core Elixir are more expressive than those in FW-Elixir, while guards are less expressive. In particular, Core Elixir guards cannot be negated, which is an essential requirement for the guard analysis of Section 3 to work. For instance, while in FW-Elixir it is possible to define a function such as |
| 30 | def first(x) when not(tuple_size(x)==0), do: elem(x,0) |

in Core Elixir it is not possible to write a negated guard such as not(tuple_size(x)==0) . Therefore, in Section 6 we demonstrate that it is possible to compile FW-Elixir guards into equivalent Core Elixir guards and, consequently, that the type analysis defined on Core Elixir easily transposes to FW-Elixir and Elixir itself.

1.2.8. Implementation in Elixir (Section 7). All the features and algorithms presented here have been progressively included in Elixir, starting with the v1.17 release (June 2024) of the language [Eli24b]: the front-end of the Elixir compiler types (multi-arity) functions using safe erasure gradual typing, with strong functions, dynamic() propagation, and guard analysis. The latter is used to perform inference as described in §1.2.6. The Elixir v1.19 implementation (released on October 16, 2025 [Eli25]) covers all language constructs and includes basic, atom, tuple, list, map, and function types, as well as the typing of protocols

12 GUARD ANALYSIS AND SAFE ERASURE GRADUAL TYPING: A TYPE SYSTEM FOR ELIXIR (akin to Haskell type classes). The v1.20 release candidates complete the implementation of guard analysis and use it to infer intersections for multi-clause functions [Eli26]. In the last technical section of this work, Section 7, we present some aspects of this implementation, such as the data structures used to represent types and a more detailed description of the implementation of the typing rules for function application. We also outline the current roadmap for integrating the type system into Elixir. In addition, we present some performance results of the current type-checker on large well-tested codebases, such as the Elixir package manager and the Phoenix web framework. Finally, we discuss the user feedback we have received so far. The implementation is available in the Elixir’s official repository [Eli].

1.2.9. Quantitative and Qualitative Comparison (Sections 8, 9). We conclude our presen tation with an empirical evaluation and a survey of related work. Section 8 reports exper iments conducted on a corpus of real-world codebases to assess the precision of our type system from multiple angles: internally, by examining specific aspects such as dead-code detection, guard exactness, and return-type inference; and externally, by comparing our system against existing gradually-typed languages on controlled benchmarks. Section 9 then situates our contributions within the broader research landscape, discussing how the various components of our system relate to and differ from prior work in gradual typing, subtyping and polymorphism, as well as from industrial gradually-typed systems.

1.3. Contributions and Limitations. Our primary contribution is the establishment of 
the theoretical foundations of the Elixir type system, whose general principles we outlined 
in [CDV24]. Notably, we define what we believe to be the first safe-erasure gradual type 
system. More generally, we believe that the formalization and algorithms presented here 
constitute an essential resource for language implementers wishing to integrate set-theoretic 
types into dynamically typed languages—especially existing languages with substantial run 
ning codebases—following the design principles of [CDV24]. As we outline in Section 9 on 
related work, several other dynamic languages, such as Erlang, Luau, or Python have been 
starting to adopt—to different extents—some concepts of gradual set-theoretic types, and 
the eventual implementation of these concepts will surely benefit from the results presented 
here. 
The technical contributions can be summarized as follows:

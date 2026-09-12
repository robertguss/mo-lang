---
source_url: https://simon.peytonjones.org/assets/pdfs/verse-icfp23.pdf
ingested: 2026-09-12
sha256: d0653ae27d7af54588f404cb902534eb825023391ebeb8899d8a4152e8181842
---
# The Verse Calculus: A Core Calculus for Deterministic Functional Logic Programming (Extended Version)

##### The Verse Calculus: A Core Calculus for Deterministic Functional Logic Programming (Extended Version)

LENNART AUGUSTSSON, Epic Games, Sweden 
JOACHIM BREITNER, Unaffiliated, Germany 
KOEN CLAESSEN, Epic Games, Sweden 
RANJIT JHALA, Epic Games, USA 
SIMON PEYTON JONES, Epic Games, United Kingdom 
OLIN SHIVERS, Epic Games, USA 
GUY L. STEELE JR., Oracle Labs, USA 
TIM SWEENEY, Epic Games, USA 
Functional logic languages have a rich literature, but it is tricky to give them a satisfying semantics. In this 
paper we describe the Verse calculus, VC, a new core calculus for deterministic functional logic programming. 
Our main contribution is to equip VC with a small-step rewrite semantics, so that we can reason about a 
VC program in the same way as one does with lambda calculus; that is, by applying successive rewrites to it. 
We also show that the rewrite system is confluent for well-behaved terms. 
This is an extended version (with appendices) of the paper in the Proceedings of the International Conference on 
Functional Programming (2023). 
CCS Concepts: • Theory of computation → Equational logic and rewriting; Proof theory; Rewrite 
systems; Grammars and context-free languages; • Software and its engineering → Syntax; Semantics; 
Functional languages; Constraint and logic languages; Multiparadigm languages. 
Additional Key Words and Phrases: choice operator, confluence, declarative programming, evaluation strategy, 
even/odd problem, functional programming, lambda calculus, lenient evaluation, logic programming, logical 
variables, normal forms, rewrite rules, skew confluence, substitution, unification, Verse calculus, Verse language 
ACM Reference Format: 
Lennart Augustsson, Joachim Breitner, Koen Claessen, Ranjit Jhala, Simon Peyton Jones, Olin Shivers, Guy L. 
Steele Jr., and Tim Sweeney. 2023. The Verse Calculus: A Core Calculus for Deterministic Functional Logic 
Programming (Extended Version). Proc. ACM Program. Lang. 7, ICFP, Article 203 (August 2023), 80 pages. 
https://doi.org/10.1145/3607845 
1 INTRODUCTION 
Functional logic programming languages add expressiveness to functional programming by intro 
ducing logical variables, equality constraints among those variables, and choice to allow multiple 
Authors’ addresses: Lennart Augustsson, Epic Games, Sweden, lennart.augustsson@epicgames.com; Joachim Breitner, 
Unaffiliated, Germany, mail@joachim-breitner.de; Koen Claessen, Epic Games, Sweden, koen.claessen@epicgames.com; 
Ranjit Jhala, Epic Games, USA, ranjit.jhala@epicgames.com; Simon Peyton Jones, Epic Games, United Kingdom, simonpj@ 
epicgames.com; Olin Shivers, Epic Games, USA, olin.shivers@epicgames.com; Guy L. Steele Jr., Oracle Labs, USA, guy. 
steele@oracle.com; Tim Sweeney, Epic Games, USA, tim.sweeney@epicgames.com. 
Permission to make digital or hard copies of part or all of this work for personal or classroom use is granted without fee 
provided that copies are not made or distributed for profit or commercial advantage and that copies bear this notice and 
the full citation on the first page. Copyrights for third-party components of this work must be honored. For all other uses, 
contact the owner/author(s). 
© 2023 Copyright held by the owner/author(s). 
2475-1421/2023/8-ART203 
https://doi.org/10.1145/3607845 

203:2 Augustsson, Breitner, Claessen, Jhala, Peyton Jones, Shivers, Steele, Sweeney alternatives to be explored. Here is a tiny example:

∃ x y z. x = ⟨ y, 3⟩; x = ⟨2, z⟩; y

This expression introduces three logical (or existential) variables x, y, z, constrains them with two 
equalities (x = ⟨ y, 3⟩ and x = ⟨2, z⟩), and finally returns y. The only solution to the two equalities is 
y =2, z =3, and x = ⟨2, 3⟩; so the result of the whole expression is 2. 
Functional logic programming has a long history and a rich literature [Antoy and Hanus 2010]. 
But it is somewhat tricky for programmers to reason about functional logic programs: they must 
think about logical variables, needed narrowing, unification, and the like. This contrasts with 
functional programming, where one can say “just apply rewrite rules, such as β-reduction, let 
inlining, and case-of-known-constructor.” We therefore seek a precise expression of functional 
logic programming as a term-rewriting system, to give us both a formal semantics (via small-step 
reductions), and a powerful set of equivalences that programmers can use to reason about their 
programs, and that compilers can use to optimize them. 
We make two main contributions. Our first contribution is a new core calculus for functional 
logic programming, the Verse calculus or VC for short (Section 2). Like any functional logic 
language, VC supports logical variables, equalities, and choice, but it is distinctive in several ways: 
• Natively higher order. VC directly supports higher-order functions, just like the lambda calculus. Indeed, every lambda calculus program is a VC program. In contrast, most of the functional logic literature is rooted in a first-order world, and addresses higher-order features via an encoding called defunctionalization [Reynolds 1972; Hanus 2013, 3.3]. 
• Deterministic, with native encapsulation. VC is deterministic, in the sense that when an expression yields more than one value (as is often the case in functional logic programs), those values are returned in a well-specified order. This makes it easy to solve thenotoriously tricky issue [Braßel et al. 2004a,b] of how to encapsulate the result of a search as a data structure, using the all operator (see Section 2.6). It opens up a new approach to dealing with so-called “flexible” vs. “rigid” variables (see Section 2.5). It supports an elegant economy of concepts: for example, there is just one equality (other languages may have a suspending equality and a narrowing equality), and conditional expressions are driven by failure rather than booleans (see Section 2.5). On the other hand, it pretty much rules out laziness (see Section 3.6) and parallel first-come first-returned search strategies. Most other functional logic languages (Curry [Hanus et al. 2016] is the brand leader in this design space) are non-deterministic by design; VC explores a different (and less well-examined) part of the design space. Our second contribution is to equip VC with a small-step term-rewriting semantics (see Section 3). We said that the lambda calculus is a subset of VC, so it is natural to give its semantics using rewrite rules, just as for the lambda calculus. That seems challenging, however, because logical variables and unification involve sharing and non-local communication. How can that be expressed in a rewrite system? Happily, we can build on prior work: exactly the same difficulty arises with call-by-need in the lambda calculus. For a long time, the only semantics of call-by-need that was faithful to its sharing semantics (in which thunks are evaluated at most once) was an operational semantics that sequentially threads a global heap through execution [Launchbury 1993]. But then Ariola et al., in a seminal paper, showed how to reify the heap into the term itself, and thereby build a rewrite system that is completely faithful to lazy evaluation [Ariola et al. 1995]. Inspired by their idea, we present a new rewrite system for functional logic programs that reifies logical variables, unification, and choice into the term itself, and replaces non-deterministic search with 

The Verse Calculus: A Core Calculus for Deterministic Functional Logic Programming (Extended Version) 203:3 a (deterministic) tree of successful results. In VC the choices are “laid out in space” (in the syntax of the term) rather than, as is more typical, “laid out in time” (via non-deterministic rewrites and backtracking).

Integers 
Variables , , , , 
Programs ::= one{ e} where fvs( ) = 
∅Expressions ::= v | ; e | ∃ x. e | fail | e1 e2 | v1v2 | one{ e} | all{ e} ::= e | v =e Note: “ ” is pronounced “expression or equation” 
Values v ::= | hnf 
Head values hnf ::= | | ⟨ v1, ··· , vn⟩ | x. e 
Primops ::= gt | add 
Concrete syntax: “” and “;” are right-associative. 
“=” binds more tightly than “;”. 
“ ” and “∃” each scope as far to the right as possible. 
For example, ( y. ∃ x. x =1; x + y) means ( y. (∃ x. ( ( x =1); ( x + y)))). 
Parentheses may be used freely to aid readability and override default precedence. 
fvs( e) means the free variables of e; in VC, and ∃ are the only binders. 
Desugaring of extended expressions 
e1 + e2 means add⟨ e1, 
e2⟩e1 > e2 means gt⟨ e1, e2⟩ 
∃ x1x2··· xn. e means ∃ x1. ∃ x2. ···∃ xn. e 
x :=e1; e2 means ∃ x. x =e1; e2 
e1 e2 means† f :=e1; x :=e2; f x f , x fresh 
⟨ e1, ··· , en⟩ means† x1:=e1; ···; xn:=en; ⟨ x1, ··· , xn⟩ xifresh 
e1 =e2 means‡ x :=e1; x =e2; x x fresh 
⟨ x1, ··· , xn⟩ . e means p. ∃ x1··· xn. p = ⟨ x1, ··· , xn⟩; e p fresh, n ⩾ 0 
if (∃ x1··· xn. e1) then e2else e3 means (one{(∃ x1··· xn. e1; ⟨⟩ . e2) ( ⟨⟩ . e3)})⟨⟩ 
†Apply this rule only if at least one of the eiis not a value v. 
‡Apply this rule only if either (i) e1is not a value v, or (ii) e1 =e2is not to the left of a “;”. 
Fig. 1. VC : Syntax 

As an example of rewriting in action, the expression above can be rewritten as follows1: ∃ x y z. x = ⟨ y, 3⟩; x = ⟨2, z⟩; y −→{ subst} ∃ x y z. ⟨2, z⟩ = ⟨ y, 3⟩; x = ⟨2, z⟩; y −→{ eqn-elim} ∃ y z. ⟨2, z⟩ = ⟨ y, 3⟩; y −→{ u-tup} ∃ y z. 2=y; z =3; y −→{ eqn-elim} ∃ y. 2=y; y −→{ hnf-swap} ∃ y. y =2; y −→{ subst} ∃ y. y =2; 2 −→{ eqn-elim} 2 Rules may be applied anywhere they match, including under binders, again just like the lambda calculus. This freedom only makes sense, however, if each term ultimately reduces to a unique value, regardless of its reduction path, so we show that VC is confluent, in Section 4. As always with a calculus, the idea is that VC distills the essence of (deterministic) functional logic programming. Each construct does just one thing, and VC cannot be made smaller without losing key features. We are working on Verse, a new general-purpose programming language, built directly on VC; indeed, our motivation for developing VC is practical rather than theoretical. No single aspect of VC is unique, but we believe that their combination is particularly harmonious and orthogonal. We discuss design alternatives in Section 5 and related work in Section 6.

1The rule names after each arrow come from Fig. 3, to be discussed in Section 3; they are given here just for reference. 
Proc. ACM Program. Lang., Vol. 7, No. ICFP, Article 203. Publication date: August 2023. 

2 THE VERSE CALCULUS, INFORMALLY We begin by presenting the Verse calculus, VC, informally. We describe its rewrite rules precisely in Section 3. The (abstract) syntax of VC is given in Fig. 1. It has a very conventional sub-language that is just the lambda calculus with some built-in operations and tuples as data constructors:

• Values. A value v is either a variable x or a head-normal form hnf. In VC, a variable counts as a value because in a functional logic language an expression may evaluate to an as-yet unknown logical variable. A head-normal form is a conventional value: a built-in constant k, an operator op, a tuple, or a lambda. Our tiny calculus offers only integer constants k and two illustrative integer operators op, namely gt and add. 
• Expressions e include values v, and applications v1v2; we will introduce the other constructs as we go. For clarity, we often write v1( v2) rather than v1v2 when v2is not a tuple. 
• A term is either an ordinary expression e, or an equation v =e; this syntax ensures that equations can only occur to the left of a “;” (Section 2.1). 
• A program, p, contains a closed expression from which we extract one result using one (see Section 2.5)—unless the expression fails, in which case the program fails (Section 2.2). The formal syntax for e allows only applications of values to values, ( v1 v2), but the desugaring rules in Fig. 1 show how to desugar more applications ( e1 e2). This restriction is not fundamental; it simply reduces the number of rewrite rules we need2. Modulo this desugaring, every lambda calculus term is a VC term and has the same semantics. Just like the lambda calculus, VC is untyped; adding a type system is an excellent goal but is the subject of another paper. Expressions also include two other key collections of constructs: logical variables with the use of equations to perform unification (Section 2.1), and choice (Section 2.2). The details of choice and unification, and especially their interaction, are subtle, so this section does a lot of arm-waving. But fear not: Section 3 spells out the precise details. We only have space to describe one incarnation of VC; Section 5 explores some possible alternative design choices. 2.1 Logical Variables and Equations The Verse calculus includes first-class logical variables and equations that constrain their values. You can bring a fresh logical variable into scope with ∃, constrain a value to be equal to an expression with an equation v =e, and compose expressions in sequence with ; e (see Fig. 1). As an example, what might be written let x = e1 in e2 in a conventional functional language can be written ∃ x. x =e1; e2in VC. The syntax carefully constrains both the form of equations and where they can appear: an equation ( v =e) always equates a value v to an expression e; and an equation can appear only to the left of a “;” (see in Fig. 1). The desugaring rules in Fig. 1 rewrite a general equation e1 =e2(where e1is not a value) into equations of this simpler form. A program executes by solving its equations, using the process of unification. For example, 
∃ x y z. x = ⟨ y, 3⟩; x = ⟨2, z⟩; y 
is solved by unifying x with ⟨ y, 3⟩ and with ⟨2, z⟩; that in turn unifies ⟨ y, 3⟩ with ⟨2, z⟩, which unifies 
y with 2 and z with 3. Finally, 2 is returned as the result. Note carefully that, as in any declarative 
language, logical variables are not mutable; a logical variable stands for a single, immutable value. 
We use “∃” to bring a fresh logical variable into scope, because we really mean “there exists an x 
such that . . . ”. 
High-level functional languages usually provide some kind of pattern matching; in such a 
language, we might define first by first⟨ a, b⟩ =a. Such pattern matching is typically desugared to 
2This is a common pattern, often called “administrative normal form”, or ANF [Sabry and Felleisen 1992] 
Proc. ACM Program. Lang., Vol. 7, No. ICFP, Article 203. Publication date: August 2023. 

203:6 Augustsson, Breitner, Claessen, Jhala, Peyton Jones, Shivers, Steele, Sweeney more primitive case expressions, but in VC we do not need case expressions: unification does the job. For example we can define first like this:

first := p. ∃ ab. p = ⟨ a, b⟩; a For convenience, we allow ourselves to write a term like first⟨2, 5⟩, where we define the library function first separately with “:=”. Formally, you can imagine each example e being wrapped with a binding for first, thus ∃ first. first = ...; e, and similarly for other library functions. This way of desugaring pattern matching means that the input to first is not required to be fully determined when the function is called. For example:

∃ x y. x = ⟨ y, 5⟩; 2=first( x); y

Here first( x) evaluates to y, which we then unify with 2. Another way to say this is that, as usual 
in logic programming, we may constrain the output of a function (here 2=first( x)), and thereby 
affect its input (here ⟨ y, 5⟩). 
Although “;” is called “sequencing,” the order of that sequence is immaterial for equations that do 
not contain choices (see Section 2.2 for the latter caveat). For example, consider (∃ x y. x =3 + y; y = 
7; x). The sub-expression 3 + y is stuck until y gets a value. In VC, we can unify x only with a 
value—we will see why in Section 2.2—and hence the equation x =3 + y is also stuck. No matter! We 
simply leave it and try some other equation. In this case, we can make progress with y =7, and that 
in turn unlocks x =3 + y because now we know that y is 7, so we can evaluate 3 + 7 to 10 and unify 
x with that. The idea of leaving stuck expressions aside and executing other parts of the program is 
called residuation [Hanus 2013]3, and is at the heart of our mantra “just solve the equations.” 
2.2 Choice 
In conventional functional programming, an expression evaluates to a single value. In contrast, 
a VC expression evaluates to zero, one, or many values; or it can get stuck, which is different 
from producing zero values. The expression fail yields no values; a value v yields one value; and 
the choice e1 e2 yields all the values yielded by e1followed by all the values yielded by e2. Order 
is maintained and duplicates are not eliminated; we shall see why in Section 2.8. In short, an 
expression yields a sequence of values, not a bag, and certainly not a set. 
The equations we saw in Section 2.1 can fail, if the arguments are not equal, yielding no results. 
Thus 3=3 succeeds, while 3=4 fails, returning no results. In general, we use “fail” and “returns no 
results” synonymously. 
What if the choice was not at the top level of an expression? For example, what does ⟨3, (7 
5)⟩mean? In VC, it does not mean a pair with some kind of multi-value in its second component. 
Indeed, as you can see from Fig. 1, this expression is syntactically ill-formed. We must use the 
desugaring rules of Fig. 1, which give a name to that choice, thus: ∃ x. x = (7 5); ⟨3, x⟩. Now the 
expression is syntactically legal, but what does it mean? In VC, a variable is never bound to a 
multi-value. Instead, x is successively bound to 7, and then to 5, like this: 

∃ x. x = (7 5); ⟨3, x⟩ −→ (∃ x. x =7; ⟨3, x⟩) (∃ x. x =5; ⟨3, x⟩) We duplicate the context surrounding the choice, and “float the choice outwards”. The same thing happens when there are multiple choices. For example: ∃ x y. x = (7 22); y = (31 5); ⟨ x, y⟩ yields the sequence ⟨7, 31⟩ , ⟨7, 5⟩ , ⟨22, 31⟩ , ⟨22, 5⟩ Notice that the order of the two equations now is significant: ∃ x y. y = (31 5); x = (7 22); ⟨ x, y⟩ yields the sequence ⟨7, 31⟩ , ⟨22, 31⟩ , ⟨7, 5⟩ , ⟨22, 5⟩ 3Hanus did not invent the terms “residuation” and“narrowing,” but his survey is an excellent introduction and bibliography. Proc. ACM Program. Lang., Vol. 7, No. ICFP, Article 203. Publication date: August 2023.

Readers familiar with list comprehensions in Haskell and other languages will recognize this 
nested-loop pattern, but here it emerges naturally from choice as a deeply built-in primitive, rather 
than being a special construct for lists. 
Just as we never bind a variable to a multi-value, we never bind it to fail either; rather we iterate 
over zero values, and that iteration of course returns zero values. So: 
∃ x. x =fail; 33 −→ fail 
2.3 Mixing Choice and Equations 
In the last section, we discussed what happens if there is a choice in the right-hand side (RHS) of 
an equation. What if we have equations under choice? For example: 
∃ x. ( x =3; x + 1) ( x =4; x + 4) 
Intuitively, “either unify x with 3 and yield x + 1, or unify x with 4 and yield x + 4”. But there is 
a problem: so far we have said only “a program executes by solving its equations” (Section 2.1). 
Here, we can see two equations, ( x =3) and ( x =4), which are mutually contradictory, so clearly 
we need to refine our notion of “solving.” The answer is pretty clear: in a branch of a choice, solve 
the equations in that branch to get the values for some logical variables, and propagate those values 
to occurrences in that branch (only). Occurrences of that variable outside the choice are unaffected. 
We call this local propagation. This local-propagation rule would allow us to reason thus: 
∃ x. ( x =3; x + 1) ( x =4; x + 4) −→ ∃ x. ( x =3; 4) ( x =4; 8) 
Are we stuck now? No, we can float the choice out as before4, 
∃ x. ( x =3; 4) ( x =4; 8) −→ (∃ x. x =3; 4) (∃ x. x =4; 8) 
and now it is apparent that the sole occurrence of x in each ∃ is the equation ( x = 3), or ( x = 
4)respectively; so we can drop the ∃ and the equation, yielding (4 8). 
2.4 Pattern Matching and Narrowing 
We remarked in Section 2.1 that we can desugar the pattern matching of a high-level language into 
equations. But what about multi-equation pattern matching, such as this definition in Haskell: 
append [ ] = 
append ( x : ) =x : append 
If pattern matching on the first equation fails, we want to fall through to the second. Fortunately, 
choice allows us to express this idea directly, where we use the empty tuple ⟨⟩ to represent the 
empty list and pairs to represent cons cells (see Fig. 1 to desugar the pattern-matching lambda): 
append := ⟨ , ⟩ . ( ( = ⟨⟩; ) (∃ x xr. = ⟨ x, xr⟩; ⟨ x, append⟨ xr, ⟩⟩)) 
If is ⟨⟩, the left-hand choice succeeds, returning ; and the right-hand choice fails (by attempting 
to unify ⟨⟩ with ⟨ x, xr⟩). If is of the form ⟨ x, xr⟩, the right-hand choice succeeds, and we make a 
recursive call to append. Finally, if is built with head-normal forms other than the empty tuple 
and pairs, both choices fail, and append returns no results at all. 
This approach to pattern matching is akin to narrowing [Hanus 2013]. Suppose single = ⟨1, ⟨⟩⟩, 
a singleton list whose only element is 1. Consider the call ∃ . append⟨ , single⟩ =single; . The 
call to append expands into a choice: 
( = ⟨⟩; single) (∃ x xr. = ⟨ x, xr⟩; ⟨ x, append⟨ xr, single⟩⟩) 
4Indeed, we could have done so first, had we wished. 
Proc. ACM Program. Lang., Vol. 7, No. ICFP, Article 203. Publication date: August 2023. 
203:8 Augustsson, Breitner, Claessen, Jhala, Peyton Jones, Shivers, Steele, Sweeney 
which amounts to exploring the possibility that is headed by ⟨⟩ or a pair—the essence of narrowing. 
It should not take long to reassure yourself that the program evaluates to ⟨⟩, effectively running 
append backwards in the classic logic-programming manner. 
This example also illustrates that VC allows an equation (for append) that is recursive. As in any 
functional language with recursive bindings, you can go into an infinite loop if you keep fruitlessly 
inlining the function in its own right-hand side. It is the business of an evaluation strategy to do 
only rewrites that make progress toward a solution (Section 3.7). 
2.5 Conditionals and one 
Every source language will provide a conditional, such as if ( x =0) then e2else e3. But what is 
the equality operator in ( x =0)? One possibility, adopted by Curry [Antoy and Hanus 2021, §3.4], 
is this: there is one “=” for equations (as in Section 2.1), and another, say “==”, for testing equality 
(returning a boolean with constructors True and False). VC takes a different, more minimalist 
position, following the lead of Icon (see Section 6.7). In VC, there is just one equality operator, 
written “=” just as in Section 2.1. The expression if ( x =0) then e2else e3tries to unify x with 0. 
If that succeeds (yields one or more values), the if returns e2; otherwise it returns e3. There are no 
data constructors True and False; instead failure (returning zero values) plays the role of falsity. 
But something is terribly wrong here. Consider ∃ x y. y = (if ( x = 0) then 3 else 4); x = 7; y. 
Presumably this is meant to set x to 7, test whether it is equal to 0 (it is not), and unify y with 4. 
But what is to stop us instead unifying x with 0 (via ( x =0)), unifying y with 3, and then failing 
when we try to unify x with 7? Not only is that not what we intended, but it also looks very 
non-deterministic: the result is affected by the order in which we did unifications. 
To address this, we give if a special property: in the expression if e1then e2else e3, equations 
inside e1(the condition of the if) can only unify variables bound inside e1; variables bound outside 
e1are called “rigid.” So in our example, the x in ( x =0) is rigid and cannot be unified. Instead, the if 
is stuck, and we move on to unify x =7. That unblocks the if and all is well. 
In fact, VC desugars the three-part if into something simpler, the unary construct one{ e}. Its 
specification is this: if e fails, one{ e} fails; otherwise one{ e} returns the first of the values yielded 
by e. Now, if e1then e2else e3can (nearly) be re-expressed like this: 

one{( e1; e2) e3} This isn’t right yet, but the idea is this: if e1fails, the first branch of the choice fails, so we get e3; if e1succeeds, we get e2, and the outer one will select it from the choice. But what if e2 or e3 themselves fail or return multiple results? Here is a better translation, the one given in Fig. 15, which wraps the then and else branches within thunks6: (one{( e1; ( ⟨⟩ . e2)) ( ⟨⟩ . e3)})⟨⟩ The argument of one reduces to either ( ⟨⟩ . e2) ( ⟨⟩ . e3) or ( ⟨⟩ . e3) depending on whether e1 succeeds or fails, respectively; one then picks the first value, that is, ⟨⟩ . e2if e1succeeded or ⟨⟩ . e3 if e1failed, and applies it to ⟨⟩. As a bonus, provided we do no evaluation under a lambda, then e2 and e3 will remain unevaluated until the choice is made, just as we expect from a conditional. We use the same local-propagation rule for one that we do for choice (Section 2.3). This, together with the desugaring for if into one, gives the “special property” of if described above.

5The translation in the figure also allows variables bound in the condition to scope over the then branch. 
6Using thunks for the branches of a conditional is another very old idea; for example, see [Steele Jr. 1978, p. 54]. 
Proc. ACM Program. Lang., Vol. 7, No. ICFP, Article 203. Publication date: August 2023. 

2.6 Tuples and all 
The main data structure in VC is the tuple. A tuple is a finite sequence of values, ⟨ v1, ··· , vn⟩, where 
⩾ 0. A tuple can be used like a function: indexing is simply function application with the argument 
being integers from 0 and up. Indexing out of range is fail, as is indexing with a non-integer value. 
For example, t := ⟨10, 27, 32⟩; t(1) reduces to 27 and t := ⟨10, 27, 32⟩; t(3) reduces to fail. 
What if we apply a tuple to a choice, e.g., ⟨10, 27, 32⟩ (1 0 1)? First we must desugar the appli 
cation to the form ( v1v2), which is all VC permits (see Fig. 1), giving x := (1 0 1); ⟨10, 27, 32⟩ ( x), 
which readily reduces to (27 10 27). 
Tuples can be constructed by collecting all the results from a multi-valued expression, using the 
all construct: if e reduces to ( v1 ··· vn), where ⩾ 2, then all{ e} reduces to the tuple ⟨ v1, ··· , vn⟩; 
all{ v} produces the singleton tuple ⟨ v⟩; and all{fail} produces the empty tuple ⟨⟩. Note that is 
associative, which means that we can think of a sequence or tree of binary choices as really being a 
single -way choice. 
You might think that tuple indexing would be stuck until we know the index, but in VC, the 
application of a tuple to a value rewrites to a choice of all the possible values of the index. For 
example, t := ⟨10, 27, 32⟩; ∃ i. t( i) looks stuck because we have no value for i, but this expression 
actually rewrites (via rule app-tup in Section 3.1) to: 
∃ i. ( i =0; 10) ( i =1; 27) ( i =2; 32) which (as we will see in Section 3) simplifies to just (10 27 32). So all allows a choice to be reified 
into a tuple, and (∃ i. t( i)) allows a tuple to be turned back into a choice. The idea of rewriting a 
call of a function with a finite domain into a finite choice is called “narrowing” in the literature. 
Do we even need one as a primitive construct, given that we have all? Can we not use (all{ e}) (0)instead of one{ e}? Indeed, they behave the same if e fully reduces to finitely many choices of 
values. But all really requires every arm of the choice tree to resolve to a value before proceeding, 
while one only needs the first choice to be a value. So, supposing that loop is a non-terminating 
function, one{1 loop⟨⟩} can reduce to 1, while (all{1 loop⟨⟩}) (0) loops. 
2.7 Programming in Verse 
VC is a fairly small language, but it is quite expressive. For example, we can define the typical list 
functions one would expect from functional programming by using the duality between tuples and 
choices, as seen in Fig. 2. A tuple can be turned into choices by indexing with a logical variable i. 
Conversely, choices can be turned into a tuple using all. The choice operator “” serves as both 
cons and append for choices; the corresponding operations for tuples are defined in Fig. 2. Partial 
functions, e.g., head, will fail when the argument is outside of the domain. 
Mapping a multi-valued function over a tuple is somewhat subtle. With flatMap the choices are 
flattened in the resulting tuple, e.g., flatMap⟨( x. x x + 10) , ⟨2, 3⟩⟩ reduces to ⟨2, 12, 3, 13⟩, whereas 
map keeps the choices. For example: 
map⟨( x. x x + 10) , ⟨2, 3⟩⟩ −→ ⟨( x. x x + 10) (2) , ( x. x x + 10) (3)⟩ −→ ⟨2 12, 3 13⟩ −→ ⟨2, 3⟩ ⟨2, 13⟩ ⟨12, 3⟩ ⟨12, 
13⟩Pattern matching for function definitions is simply done by unification of ordinary expressions; 
see the desugaring of pattern-matching lambda in Fig. 1. This in turn means that we can use 
ordinary abstraction mechanisms for patterns. For example, here is a function, fcn, that could be 
called as follows: fcn⟨88, 1, 99, 2⟩. 

fcn( t) :=∃ x y. t = ⟨ x, 1, y, 2⟩; x + y If we want to give a name to the pattern, it is simple to do so: pat⟨ v, w⟩:= ⟨ v, 1, w, 2⟩; fcn( t) :=∃ x y. t =pat⟨ x, y⟩; x + y Proc. ACM Program. Lang., Vol. 7, No. ICFP, Article 203. Publication date: August 2023.

head( ) := (0) tail( ) := all{∃ i. i > 0; ( i)} cons⟨ x, ⟩ := all{ x ∃ i. ( i)} append⟨ , ⟩ := all{(∃ i. ( i)) (∃ i. ( i))} flatMap⟨ f , ⟩ := all{∃ i. f ( ( i))} map⟨ f , ⟩ := if x :=head( ) then cons⟨ f ( x) , map⟨ f , tail( )⟩⟩ else ⟨⟩ filter⟨ p, ⟩ := all{∃ i. x := ( i); one{ p( x)}; x} find⟨ p, ⟩ := one{∃ i. x := ( i); one{ p( x)}; x} some⟨ p, ⟩ := one{∃ i. p( ( i))} zip⟨ , ⟩ := all{∃ i. ⟨ ( i) , ( i)⟩} Desugaring of function definitions f ( x) :=e means f := x. e f ⟨ x, y⟩:=e means f := ⟨ x, y⟩ . e Fig. 2. Functions on tuples, analogous to list or array functions in some other languages Patt

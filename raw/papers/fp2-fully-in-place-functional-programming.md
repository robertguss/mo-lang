---
source_url: https://webspace.science.uu.nl/~swier004/publications/2023-icfp.pdf
ingested: 2026-09-12
sha256: f1bdb1b6714600f9461af4bd390fe72f9741f38195f19e685469b252e863fd95
---
# FP²: Fully in-Place Functional Programming

## FP 2: Fully in-Place Functional Programming

ANTON LORENZEN, University of Edinburgh, UK 
DAAN LEIJEN, Microsoft Research, USA 
WOUTER SWIERSTRA, Universiteit Utrecht, Netherlands 
As functional programmers we always face a dilemma: should we write purely functional code, or sacrifice 
purity for efficiency and resort to in-place updates? This paper identifies precisely when we can have the 
best of both worlds: a wide class of purely functional programs can be executed safely using in-place updates 
without requiring allocation, provided their arguments are not shared elsewhere. 
We describe a linear fully in-place (FIP) calculus where we prove that we can always execute such functions 
in a way that requires no (de)allocation and uses constant stack space. Of course, such a calculus is only 
relevant if we can express interesting algorithms; we provide numerous examples of in-place functions on 
datastructures such as splay trees or finger trees, together with in-place versions of merge sort and quick sort. 
We also show how we can generically derive a map function over any polynomial data type that is fully 
in-place. Finally, we have implemented the rules of the FIP calculus in the Koka language. Using the Perceus 
reference counting garbage collection, this implementation dynamically executes FIP functions in-place 
whenever possible. 
CCS Concepts: • Software and its engineering → Control structures; Recursion; • Theory of computation 
→ Operational semantics. 
Additional Key Words and Phrases: FBIP, Tail Recursion Modulo Cons 
ACM Reference Format: 
Anton Lorenzen, Daan Leijen, and Wouter Swierstra. 2023. FP 2: Fully in-Place Functional Programming. Proc. 
ACM Program. Lang. 7, ICFP, Article 198 (August 2023), 30 pages. https://doi.org/10.1145/3607840 
1 INTRODUCTION AND OVERVIEW 
The functional program for reversing a list in linear time using an accumulating parameter has 
been known for decades, dating back at least as far as Hughes’s work on difference lists [1986]: 
fun reverse-acc( xs : list, acc : list ) : list 
match xs 
Cons(x,xx) -> reverse-acc( xx, Cons(x,acc) ) 
Nil -> acc 
fun reverse( xs : list ) : list 
reverse-acc(xs,Nil) 
As this definition is pure, we can calculate with it using equational reasoning in the style of Bird 
and Meertens [Backhouse 1988; Gibbons 1994]. Using simple induction, we can, for instance, prove 
that this linear time list reversal produces the same results as its naive quadratic counterpart. 
Not all in the garden is rosy: what about the function’s memory usage? The purely functional 
definition of reverse allocates fresh Cons nodes in each iteration; an automatic garbage collector needs 
to discard unused memory. This generally induces a performance penalty relative to an imperative 
Authors’ addresses: Anton Lorenzen, University of Edinburgh, School of Informatics, Edinburgh, UK, anton.lorenzen@ed.ac. 
uk; Daan Leijen, Microsoft Research, Redmond, WA, USA, daan@microsoft.com; Wouter Swierstra, Universiteit Utrecht, 
Utrecht, Netherlands, w.s.swierstra@uu.nl. 
Permission to make digital or hard copies of part or all of this work for personal or classroom use is granted without fee 
provided that copies are not made or distributed for profit or commercial advantage and that copies bear this notice and 
the full citation on the first page. Copyrights for third-party components of this work must be honored. For all other uses, 
contact the owner/author(s). 
© 2023 Copyright held by the owner/author(s). 
2475-1421/2023/8-ART198 
https://doi.org/10.1145/3607840 

This work is licensed under a Creative Commons Attribution 4.0 International License.

in-place implementation that destructively updates the pointers of a linked list. Reasoning about 
such imperative in-place algorithms, however, is much more difficult. 
As programmers we seem to face a dilemma: should we write purely functional code, or sacrifice 
purity for efficiency and resort to in-place updates? This paper identifies precisely when we can 
have the best of both worlds: a wide class of purely functional programs can be executed safely 
using in-place updates without requiring allocation, including the reverse function above. 
In particular, what if the compiler can make the assumption that the function parameters are 
owned and unique at runtime, i.e. that there are no other references to the input list xs of reverse at 
runtime. In that case, the compiler can safely reuse any matched Cons node and update it in-place 
with the result – effectively updating the list in-place. In this paper we describe a novel fully in-place 
(FIP) calculus that guarantees that such a function can be compiled in a way to never (de)allocate 
memory or use unbounded stack space—it can be executed fully in-place. 
To illustrate the purely functional fully in-place paradigm, we consider splay trees as described 
by Sleator and Tarjan [1985]. These are self-balancing trees where every access to an element in 
the tree, including lookup, restructures the tree such that the element is “splayed” to the top of 
the tree. As a result, the lookup function not only returns a boolean representing whether or not 
the element was found in the tree, but also a newly splayed tree. Splay trees are generally not 
considered well-suited for functional languages, because every such restructuring of the tree copies 
the spine of the tree leading to decreased performance relative to an imperative implementation 
that can rebalance the tree in-place. Surprisingly, it turns out to be possible to write the splay 
algorithms in a purely functional style using fully in-place functions. 

1.1 Zippers and Unboxed Tuples Let us first define the type of splay trees containing integers 1:

type stree Node(left : stree, value : int, right : stree) Leaf For the lookup function, once we find a given element in the tree, we need to somehow navigate back through the tree to splay the node to the top. The usual imperative approach uses parent pointers for this, but in a purely functional style we can use Huet’s zipper [1997] instead. The central idea is a simple one: to navigate through a tree step by step, we store the current subtree in focus together with its context. Naively, one might try to represent the context as a path from the root of the tree to the current subtree. The zipper, however, reverses this path so each step up or down the tree requires only constant time. For splay trees, we can define the corresponding zipper as:

type szipper Root NodeL( up : szipper, value : int, right : stree ) NodeR( left : stree, value : int, up : szipper )

Huet already observed that the zipper operations could be implemented in-place. The original 
paper presenting the zipper concludes with the following paragraph [Huet 1997]: 
Efficient destructive algorithms on binary trees may be programmed with these com 
pletely applicative primitives, which all use constant time, since they all reduce to local 
pointer manipulation. 
Our FIP calculus provides the language to make such a statement precise: using the rules presented 
in the next section we can check statically that the various operations on zippers are indeed fully 

1All examples in this paper are written in the Koka langugage which has a full implementation of the FIP check (v2.4.2).

FP 2: Fully in-Place Functional Programming 198:3 in-place. For example, we can move focus to the left subtree as follows:

fip fun left(t : stree, ctx : szipper) : (stree,szipper) match! t Node(l,x,r) -> (l, NodeL(ctx,x,r)) Leaf -> (Leaf, ctx) The fip keyword indicates that a static check guarantees the function is fully in-place. This check, specified in Section 2, verifies that the function lives in a linear fragment of the language where the function parameters and variables are owned and can only be used once. As a consequence, we can safely reuse the memory of a linear value in-place once it is no longer used. The match! keyword 2 indicates a destructive match, after which the matched variable t can no longer be used. Intuitively, we can then see straightaway that the matched Node cell has become redundant and can be reused for the NodeL cell of the zipper. To make this intuition more precise, we view a destructively matched constructor, such as Node(l,x,r), as a collection of its children l, x, and r, and a reuse credit ⋄3. This “diamond” resource type ⋄k represents a specific heap cell of size k and is inspired by the work of Aspinall and Hofmann on space credits [Aspinall and Hofmann 2002; Aspinall et al. 2008; Hofmann 2000b 2000a]. Similar to their space credits, we also apply the linearity restriction to reuse credits, but, unlike space credits, a reuse credit can not be split or merged with other credits. In our example, the match! introduces a reuse credit ⋄3 for the Node, which is consumed by the allocation of NodeL which allows our left function to be fully in-place. It may seem that we still need to allocate a tuple to store the result. Such allocation, however, is usually unnecessary since tuples are often created only to hold multiple return values and immediately destructed afterwards. In our calculus and implementation, we model tuples as unboxed values hence no allocation is needed for these 3. We can now also see that the list reversal of the introduction is also fully in-place: fip fun reverse-acc( xs : list, acc : list ) : list match! xs Cons(x,xx) -> reverse-acc( xx, Cons(x,acc) ) Nil -> acc where the destructive match on xs allows the matched Cons cell to be reused (⋄2) for the Cons(x,acc) allocation in the branch.

1.2 Splay Tree Lookup and Atoms 
Using the zipper definition for splay trees, we can now define the lookup function as follows: 
fip fun lookup( t : stree, x : int ) : (bool, stree) 
zlookup(t,x,Root) 
fip fun zlookup( t : stree, x : int, ctx : szipper ) : (bool, stree) 
match! t 
Leaf -> (False, splay-leaf(ctx)) // not found, but splay anyway 
Node(l,y,r) -> 
if x < y then zlookup(l,x,NodeL(ctx,y,r)) // go down the left (NodeL reuses Node) 
elif x > y then zlookup(r,x,NodeR(l,y,ctx)) // go down the right (NodeR reuses Node) 
else (True, splay(Top(l,y,r),ctx)) // found it, now splay it to the top 
The lookup function calls zlookup with an initial empty context Root. It seems we need to allocate 
the Root constructor, but constructors without any fields do not require allocation. These are 

2In our implementation it turns out we can always infer when a match needs to be destructive and we can always write just match for both destructive and borrowing matches. However, for clarity and correspondence to our formal FIP calculus, we denote destructive matches explicitly in this paper. 3In Koka, tuples are implemented as value types which are unboxed and passed in registers. The fip keyword additionally checks that no automatic (heap allocated) boxing is applied for such value types inside a FIP function.

Fig. 1. Looking up the number 3 in a splay tree (A), creating the zipper context to the node containing 3 (B), and splaying the node up to the top (C).

typically implemented using pointer-tagging where only the tag is used to represent them. We call 
such constructors atoms. Examples include the Nil of lists, but also booleans (True and False), and, 
depending on the implementation, primitive types like integers (int) or floats. 
The zlookup function traverses down the tree while extending the current zipper context in-place 
with the path that is followed. Figure 1 shows a concrete example of how zlookup constructs the 
zipper in the transition from (A) to (B). Once the element is found, the corresponding node is 
splayed back up to the top of the tree as splay(Top(l,x,r),ctx). Here we use the Top constructor: 
type top 
Top( left : stree, value : int, right : stree ) 
But why is this Top constructor needed? Can we not just call splay directly with explicit arguments 
as splay(l,x,r,ctx)? This is not possible though in a fully in-place way. In particular, it would mean 
that the Node(l,y,r) on which we matched would need to be deallocated as it cannot be reused 
immediately (and deallocation is not allowed in fip functions). Moreover, we would now need to 
allocate the final top node later on. If we define splay without using Top, we would get something 
like: 

fun splay( l : stree, x : int, r : stree, ctx : szipper ) : stree // not fip! match! ctx Root -> Node(l,x,r) ... That is, once the zipper ctx is at the Root we need to return a fresh Node with x on top. As there is no constructor that can be reused (since Root is just an atom), this would require allocation. By using the intermediate Top constructor we avoid this: at the call site we can now reuse the Node that we just matched for Top, and later on when we reach the Root, we can reuse Top again to create the final Node that becomes the top of the returned splay tree. This results in the final fully in-place definition of the splay function:

fip fun splay( top : top , ctx : szipper ) : stree 
match! top 
Top(l,x,r) -> match! ctx 
Root -> Node(l,x,r) 
NodeL(Root,y,ry) -> Node(l,x,Node(r,y,ry)) // zig 
NodeL(NodeR(lz,z,up),y,ry) -> splay( Top(Node(lz,z,l),x,Node(r,y,ry)), up) // zig-zag 
NodeL(NodeL(up,z,rz),y,ry) -> splay( Top(l,x,Node(r,y,Node(ry,z,rz))), up) // zig-zig 
NodeR(ly,y,Root) -> Node(Node(ly,y,l),x,r) 
NodeR(ly,y,NodeL(up,z,rz)) -> splay( Top(Node(ly,y,l),x,Node(r,z,rz)), up) // (B)->(C) 
NodeR(ly,y,NodeR(lz,z,up)) -> splay( Top(Node(Node(lz,z,ly),y,l),x,r), up) 
The compiler statically checks that this function is fully in-place. As a result, we know that its 
execution uses no stack space and performs all its rebalancing operations without any (de)allocation 
– each Top and Node can reuse a destructively matched Top, NodeL, or NodeR in every branch. Each of 
the matched cases correspond to a “zig”, “zig-zig”, and “zig-zag” rebalance operation as described 
by Sleator and Tarjan [1985]. Figure 1 shows a concrete example of the “zig-zag” in the transition 

FP 2: Fully in-Place Functional Programming 198:5 from (B) to (C). For completeness, the auxiliary splay-leaf function that is called in case the item is not a member of the tree is included below:

fip fun splay-leaf( ctx : szipper ) : stree match! ctx Root -> Leaf NodeL(up,x,r) -> splay(Top(Leaf,x,r),up) NodeR(l,x,up) -> splay(Top(l,x,Leaf),up)

The definition of splay may look somewhat involved but compared to the imperative definition it is fairly concise. Moreover, the usual imperative algorithm uses extra space for parent pointers in each node. We do not need this: if we study the generated code for the fip functions, we see that the reuse of the zipper nodes corresponds to the usual “pointer-reversal” techniques [Schorr and Waite 1967] (which is illustrated nicely in Figure 1 (B)). Such pointer-reversal is not often used explicitly in practice though since it is difficult to get right by hand. In the code above, however, the fully in-place fip functions using zippers provide a statically typed, memory safe, purely functional definition with the same runtime behaviour, without requiring explicit pointer manipulation.

1.3 Borrowing and Second-Order Functions 
While our examples have so far been entirely first-order, we also allow functions to be passed as 
arguments. For example, we can map over a splay tree as follows: 

fbip fun smap( t : stree, ^f : int -> int) : stree match! t Node(l,v,r) -> Node(smap(f,l), f(v), smap(f,r)) Leaf -> Leaf In this function we seemingly violate our linearity constraint since f is used three times in the first branch. However, the function parameter is marked as borrowed using the hat notation (^f) [Ullrich and de Moura 2019]. This allows the parameter to be freely shared but at the same time it cannot be used in a destructive match, passed as an owned parameter, or returned as a result. Such borrowing is often useful for functions that inspect a data structure. Consider the following example is-node function:

fip is-node( ^t : stree ) : bool 
match t 
Node(_,_,_) -> True 
_ -> False 
This function would not be fully in-place if we matched destructively. A subtle point about higher 
order functions is that we consider an application f(e) as a borrowed use of f, and, as a consequence, 
f cannot modify any captured free variables in-place. We enforce this in our calculus by only 
allowing top-level functions (rather than arbitrary closures) as arguments in our fully in-place 
calculus, effectively making it second-order. 
Finally, note that the smap function is marked not as fip but as fbip. Unlike the earlier splay 
function, smap has recursive calls in non-tail positions. That makes it hard to claim that this function 
is “fully in-place”— after all, its execution uses stack space linear in the depth of the splay tree. We 
use the fbip keyword to signify FIP functions that still reuse in-place but are allowed to use arbitrary 
stack space and deallocate memory. Nevertheless, for smap this is not really required: in Section 3 
we show that any map function of polynomial datatypes (including smap) can be tranformed into a 
tail-recursive, zipper-based traversal that is fully in-place. 
The fbip keyword is derived from the “functional but in-place” technique [Reinking, Xie et 
al. 2021] which is a more liberal notion of our strict fully in-place functions. Our implementation 
also supports fip(n) and fbip(n) for a constant n, which allows the function to allocate at most a 
constant n constructors. This is sometimes useful for functions like splay tree insertion where a 

198:6 Anton Lorenzen, Daan Leijen, and Wouter Swierstra single Node may need to be allocated for the newly inserted element, making it fip(1).

1.4 Fully in-Place in a Functional World One might argue that fully in-place programming is just imperative programming in functional clothing. Where are the closures, the non-linear values, the persistence? And who allocates the list to be reversed in the first place? We need to be able to embed our fully in-place functions in a larger host language to be useful. The challenge is to do this safely while still guaranteeing in-place updates when possible. To illustrate this point, consider the following function:

fun palindrome( xs : list) : list append(xs, reverse(xs)) Even though reverse is a fip function, it would not be safe for it to destructively update its input list since the argument xs is used twice (as an owned argument) in the body of palindrome. The FIP calculus presented here statically checks a function’s definition—yet deciding which calls to fip functions can be safely executed using destructive updates requires further information about how arguments are shared at call sites.

1.4.1 Uniqueness Typing. One way to check this information statically is using a uniqueness type system. For example, Clean [Brus et al. 1987] is a functional language where the type system tracks when arguments are unique or shared [Barendsen and Smetsers 1995; De Vries et al. 2008]. A fip function may safely use in-place mutation, provided all owned parameters have a unique type. In that way, the type system guarantees that any argument passed at runtime will be a unique reference to that object, ruling out any possible sharing. As a result, it is always safe to reuse the argument in-place. One possible drawback of linear type systems and uniqueness typing is that it leads to code duplication, where a single function can have multiple different implementations: one version taking a unique argument; and one taking a shared argument. For example, we may need to define two reverse functions that have an equivalent implementation but only differ in the fip annotation and the uniqueness type of the input list – one uses copying and can be used persistently with a shared list, while the FIP variant updates the list in-place but requires the input list to be unique.

1.4.2 Precise Reference Counting. Checking call sites of fip functions need not happen statically. Instead, we could also use a dynamic approach where we check at runtime if a FIP function can be executed in-place [Lorenzen and Leijen 2022; Schulte and Grieskamp 1992; Ullrich and de Moura 2019]. This is the approach taken in our implementation in the Koka language, which uses Perceus precise reference counting [Reinking, Xie et al. 2021; Ullrich and de Moura 2019]. When an object has a reference count of one, it is safe to update it in-place. To illustrate how the compiled code looks in practice, consider the compilation of the fully in-place reverse-acc function. The destructive match on the input list now dynamically checks whether or not the list can be mutated in place and the generated code will look something like:

fip fun reverse-acc( xs : list, acc : list ) : list 
match! xs 
Cons(x,xx) -> 
val ru = if is-unique(xs) then &xs else { dup(x); dup(xx); decref(xs); alloc(2) } 
reverse-acc( xx, Cons@ru(x,acc) ) 
Nil -> acc 
The reuse credit ⋄2 is compiled into an explicitly named reuse token ru, and holds to the memory 
location of the resulting Cons cell. If the input list is unique, we reuse the address of the input, &xs, and 
otherwise, we adjust the reference counts of the children accordingly and return freshly allocated 
memory of the right size. In the recursive call, we initialize the Cons cell in-place at the ru memory 

FP 2: Fully in-Place Functional Programming 198:7 location as Cons@ru(x,acc). Compared to the static analysis, we have lost the static guarantee that the owned parameters are unique at runtime, but also we gained expressiveness: in particular, we can define now a single purely functional but fully in-place reverse function that serves all usage scenarios: it efficiently updates the elements in place if the argument list is unique at runtime, but it also adapts dynamically when the list, or any sublist happens to be shared – falling back gracefully to allocating fresh Cons nodes for the resulting list.

1.5 Contributions To support the motivating examples outlined so far, this paper makes the following contributions:

• Following the pioneering work on the LFPL calculus [Hofmann 2000b 2000a], we present a novel fully in-place (FIP) calculus (Section 2), precisely capturing those functions that can be executed fully in-place. We provide a standard functional operational semantics for our language, but also define an equivalent semantics for FIP functions in terms of a fixed store, where no (de)allocation can take place. As a result, we know that FIP functions never allocate memory and use bounded stack space. As shown for splay trees, atoms and unboxed tuples are needed to avoid allocations for many common scenarios and the FIP calculus includes these features. Furthermore, the rules of the FIP calculus provide a static guarantee of linearity in a syntactic way where parameters can be owned uniquely or borrowed. 
• The FIP calculus is only useful if it can actually be used to describe interesting algorithms. To show the wide applicability of our approach we present a variety of familiar functional programs and operations on datastructures that are all fully in-place. We have already seen how Huet’s zipper [1997] datastructure, colloquially described as the functional equivalent of backpointers, can be used fully in-place, and how we can use this to implement fully in-place splay trees [Sleator and Tarjan 1985]. In Section 3, we further show that we can use a defunctionalized CPS transfor mation [Danvy 2008] to derive a generic map function for any polynomial inductive datatype. The derived map uses fully in-place Schorr-Waite traversal [Schorr and Waite 1967] without using any extra stack- or heap space. In Section 4, we show further examples of functional algorithms and datastructures that are fully in-place, including imperative red-black tree insertion [Cormen et al. 2022], cons and append operations on finger trees [Claessen 2020; Hinze and Paterson 2006], and even sorting algorithms like merge sort and quick sort. We have an implementation of the FIP calculus in a fork of the Koka compiler that can check and compile all examples in this paper. 
• Finally, we study the dynamic embedding of our FIP calculus based on precise reference count ing in detail in Section 5. Integrating the static FIP calculus with the dynamic Perceus linear resource calculus, 𝜆 1 [Lorenzen and Leijen 2022; Reinking, Xie et al. 2021], gives us precisely the information we need to decide when a function call can be executed in-place or not. However, the original linear resource calculus does not model reuse, atoms, unboxing, or borrowing, all of which are essential for FIP programs. We simplify and extend the linear resource calculus into a new calculus (𝜆 fip) which includes all these features, and give a novel proof of soundness. Surprisingly, it turns out that the extended linear resource calculus 𝜆 fip can be seen a pure extension of the FIP calculus; and the rules of the FIP calculus are a strict subset of 𝜆 fip. In particular, FIP is exactly that subset of 𝜆 fip which requires no dynamic reference counting or memory management at runtime. As a result, in the Perceus setting FIP functions can interact safely with any other function, executing in-place when possible and copying when necessary. 
• In Section 6 we show a short performance evaluation of our particular implementation. It shows that fip algorithms are competitive to standard functional algorithms in Koka. This is somewhat expected since the standard algorithms can already avoid many allocations through the existing dynamic reuse as part of Perceus reference counting. If such dynamic reuse is disabled for the standard algorithms, fip functions tend to outperform with a larger margin. 

Expressions: 
e ::= (v, . . ., v) (unboxed tuple) v ::= x, y (variables) 
| e e (application) | C k 
v1 . . . vk (constructor of arity k) 
| f (e; e) (call) 
| let x = e in e (let binding) 
| match e { p ↦→ e } (matching) p ::= C k 
x1 . . . xk (pattern) 

| match! e { p ↦→ e } (destructive match)

Σ ::= ∅ | Σ, f (y; x) = e (recursive top-level functions with borrowed parameters y) 
Syntax: 
v (v1, . . ., vk) (k ⩾ 1) let x = e1 in e2 let (x) = e1 in e2 
x (x1, . . ., xk) (k ⩾ 1) 𝜆x1, . . ., xk . e 𝜆(x1, . . ., xk). e 
v (v) (unboxed singleton) 
Fig. 2. Syntax of the FIP calculus. 

We have a full implementation in the Koka compiler [Leijen 2021,v2.4.2; Lorenzen et al. 2023b], and detailed proofs can be found in the technical report [Lorenzen et al. 2023a].

2 A LANGUAGE FOR FULLY IN-PLACE UPDATE 
Figure 2 presents the syntax of the fully in-place FIP calculus. The syntax has been carefully chosen 
to be expressive enough to cover many interesting functions as shown in this paper, but at the same 
time restricted enough to be straightforward to analyze. Particular properties of our syntax are the 
inclusion of unboxed tuples, borrowed parameters, and the lack of general lambda expressions. 
The syntax distinguishes between expressions e, and values v that cannot be evaluated further. 
Values are either variables or fully applied constructors C k, taking k values as arguments. We often 
leave out the superscript k when not needed. 
Unboxed tuples (v1, . . ., vk) are considered expressions, rather than values. In this way, we 
syntactically rule out that unboxed tuples may be passed as an argument to a constructor, causing 
them to become “boxed” (and allocated). Instead of enforcing this with a type system [Peyton Jones 
and Launchbury 1991], we use this syntactic restriction to enforce this property. By doing so, the 
check is simpler and allows us to specify the FIP calculus independent of its static semantics. 
We often write just v or e for a singleton unboxed tuple (v), and write an overline to denote 
an unboxed tuple (v1, . . ., vk) as v, or an unboxed tuple of variables (x1, . . ., xk) as x. Since expres 
sions always eventually evaluate to an unboxed tuple, the let x = e1 in e2 expression binds all 
components of the result unboxed tuple e1 in x. 
There are no general lambda expressions. In general, closures need to be heap allocated if they 
contain free variables. To keep the FIP rules as simple as possible, we do not allow arbitrary lambda 
expressions. Instead, the global Σ environment holds all top-level functionsf , which can be mutually 
recursive and passed as arguments. This makes our calculus essentially second-order. A top-level 
function is declared as f (y; x) = e, where y are the borrowed parameters, and x are the owned 
(unique) parameters. Just as in a let binding, the y and x bind the components of the unboxed tuples 
that are passed. A function is called by writing f (e1; e2) with e1 for the borrowed arguments, and 
e2 for the owned arguments. 
If there are no borrowed arguments, we sometimes write just f (e2). The syntax e1 e2 is used for 
general application when the function to be called is not statically known. This happens when a 
function f is passed as an second-order argument itself, and in such case, e2 is always passed as 
the owned parameter(s). We have two match expressions, the regular match, and the destructive 

Evaluation order:

E : : = □ | E e | v E | f (E; e) | f (v; E) | let x = E in e | match E { p ↦→ e } | match! E { p ↦→ e }

e1 −→ e2 E[e1] ↦−→ E[e2]

step

Evaluation steps: 
(let) let x = v in e −→ e[x: =v] 
(call) f (v1; v2) −→ e[y: =v1, x: =v2] with f (y; x) = e ∈ Σ 
(app) (f ) v −→ e[x: =v] with f (; x) = e ∈ Σ 
(match) match (C v) { p ↦→ e } −→ ei[y: =v] with pi = C y 
(match!) match! (C v) { p ↦→ e } −→ ei[x: =v] with pi = C x 
Fig. 3. Functional operational semantics. 

match!. There is no difference in the functional semantics between the two, but in a heap semantics the destructive match can be used for reuse, and as we see in the FIP rules in Figure 4, it can only be used on owned parameters.

2.1 Functional Operational Semantics 
Figure 3 gives the functional operational

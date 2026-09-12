---
source_url: https://www.microsoft.com/en-us/research/wp-content/uploads/2020/11/perceus-tr-v4.pdf
ingested: 2026-09-12
sha256: 3caca772ad58bdba5e42b8f037f19e7816223bb7219849f5ac303fa5a5a91768
---
# Perceus: Garbage Free Reference Counting with Reuse

## Perceus: Garbage Free Reference Counting with Reuse

Microsoft Technical Report, MSR-TR-2020-42, 2020-11-22. (update v4, 2021-06-07). Alex Reinking∗ Microsoft Research Redmond, WA, USA alex_reinking@berkeley.edu

#### Ningning Xie∗

University of Hong Kong Hong Kong, China nnxie@cs.hku.hk

Leonardo de Moura Microsoft Research Redmond, WA, USA leonardo@microsoft.com

Daan Leijen Microsoft Research Redmond, WA, USA daan@microsoft.com

Abstract We introduce Perceus, an algorithm for precise reference counting with reuse and specialization. Starting from a func tional core language with explicit control-flow, Perceus emits precise reference counting instructions such that (cycle-free) programs are garbage free, where only live references are re tained. This enables further optimizations, like reuse analysis that allows for guaranteed in-place updates at runtime. This in turn enables a novel programming paradigm that we call functional but in-place (FBIP). Much like tail-call optimiza tion enables writing loops with regular function calls, reuse analysis enables writing in-place mutating algorithms in a purely functional way. We give a novel formalization of ref erence counting in a linear resource calculus, and prove that Perceus is sound and garbage free. We show evidence that Perceus, as implemented in Koka, has good performance and is competitive with other state-of-the-art memory collectors. Keywords: Reference Counting, Algebraic Effects, Handlers

1 Introduction Reference counting [7], with its low memory overhead and ease of implementation, used to be a popular technique for automatic memory management. However, the field has broadly moved in favor of generational tracing collectors [31], partly due to various limitations of reference counting, in cluding cycle collection, multi-threaded operations, and ex pensive in-place updates. In this work we take a fresh look at reference counting. We consider a programming language design that gives strong compile-time guarantees in order to enable efficient refer ence counting at run-time. In particular, we build on the pioneering reference counting work in the Lean theorem prover [46], but we view it through the lens of language design, rather than purely as an implementation technique. We demonstrate our approach in the Koka language [23, 25]: a functional language with mostly immutable data types together with a strong type and effect system. In contrast ∗The first two authors contributed equally to this work.

to the dependently typed Lean language, Koka is general purpose, with support for exceptions, side effects, and muta ble references via general algebraic effects and handlers [39, 40]. Using recent work on evidence translation [50–52], all these control effects are compiled into an internal core lan guage with explicit control flow. Starting from this functional core, we can statically transform the code to enable efficient reference counting at runtime. In particular:

• Due to explicit control flow, the compiler can emit precise reference counting instructions where a (non-cyclic) ref erence is dropped as soon as possible. We call this garbage free reference counting as only live data is retained (§ 2.2). 
• We show that precise reference counting enables many optimizations, in particular drop specialization which re moves many reference count operations in the fast path (Section 2.3), reuse analysis which updates (immutable) data in-place when possible (Section 2.4), and reuse spe cialization which removes many in-place field updates (Section 2.5). The reuse analysis shows the benefit of a holistic approach: even though the surface language has immutable data types with strong guarantees, we can use dynamic run-time information, e.g. whether a reference is unique, to update in-place when possible. 
• The in-place update optimization is guaranteed, which leads to a new programming paradigm that we call FBIP: functional but in-place (Section 2.6). Just like tail-call op timization lets us write loops with regular function calls, reuse analysis lets us write in-place mutating algorithms in a purely functional way. We showcase this approach by implementing a functional version of in-order Morris tree traversal [35], which is stack-less, using in-place tree node mutation via FBIP. 
• We present a formalization of general reference counting using a novel linear resource calculus, 1, which is closely based on linear logic (Section 3), and we prove that ref erence counting is sound for any program in the linear resource calculus. We then present the Perceus1algorithm 

1Perceus, pronounced per-see-us, is a loose acronym of “PrEcise Reference Counting with rEUse and Specialization”.

as a deterministic syntax-directed version of 1, and prove that it is both sound (i.e. never drops a live reference), and garbage free (i.e. only retains reachable references).

• We demonstrate Perceus by providing a full implementa tion for the strongly typed functional language Koka [1]. The implementation supports typed algebraic effect han dlers using evidence translation [51] and compiles into standard C11 code. The use of reference counting means no runtime system is needed and Koka programs can read ily link with other C/C++ libraries. 
• We show evidence that Perceus, as implemented for Koka, competes with other state-of-the-art memory collectors (Section 4). We compare our implementation in alloca tion intensive benchmarks against OCaml, Haskell, Swift, and Java, and for some benchmarks to C++ as well. Even though the current Koka compiler does not have many optimizations (besides the ones for reference counting), it has outstanding performance compared to these mature systems. As a highlight, on the tree insertion benchmark, the purely functional Koka implementation is within 10% of the performance of the in-place mutating algorithm in C++ (using std::map [13]). 

Even though we focus on Koka in this paper, we believe that Perceus, and the FBIP programming paradigm we identify, are both broadly applicable to other programming languages with similar static guarantees for explicit control flow. There is an accompanying technical report [41] containing all the proofs and further benchmark results.

2 Overview Compared to a generational tracing collector, reference count ing has low memory overhead and is straightforward to implement. However, while the cost of tracing collectors is linear in the live data, the cost of reference counting is linear in the number of reference counting operations. Op timizing the total cost of reference counting operations is therefore our main priority. There are at least three known problems that make reference counting operations expensive in practice and generally inferior to tracing collectors:

• Concurrency: when multiple threads share a data structure, reference count operations need to be atomic, which is expensive. 
• Precision: common reference counted systems are not pre cise and hold on to objects too long. This increases memory usage and prevents aggressive optimization of many ref erence count operations. 
• Cycles: if object references form a cycle, the runtime needs to handle them separately, which re-introduces many of the drawbacks of a tracing collector. 

We handle each of these issues in the context of an eager, functional language using immutable data types together with a strong type and effect system. For concurrency, we precisely track when objects can become thread-shared (Sec tion 2.7.2). For precision, we introduce Perceus, our algorithm for inserting precise reference counting operations that can be aggressively optimized. In particular, we eliminate and fuse many reference count operations with drop specializa tion (Section 2.3), turn functional matching into in-place updates with reuse analysis (Section 2.4), and minimize field updates with reuse specialization (Section 2.5). Finally, although we currently do not supply a cycle col lector, our design has two mitigations that reduces the oc currences of cycles in the first place. First, (co)inductive data types and eager evaluation prevent cycles outside of explicit mutable references, and it is statically known where cycles can possibly be introduced in the code (Section 2.7.4). Second, being a mostly functional language, mutable references are not often used – moreover, reuse analysis greatly reduces the need for them since in-place mutation is typically inferred. The reference count optimizations are our main contribu tion and we start with a detailed overview in the following sections, ending with details about how we mitigate the impact of concurrency and cycles. 2.1 Types and Effects We start with a brief introduction to Koka [23, 25] – a strongly typed, functional language that tracks all (side) effects. For example, we can define a squaring function as: fun square( x : int ) : total int { x * x }

Here we see two types in the result: the effect type total and the result type int. The total type signifies that the func tion can be modeled semantically as a mathematically total function, which always terminates without raising an excep tion (or having any other observable side effect). Effectful functions get more interesting effect types, like: fun println( s : string ) : console () fun divide( x : int, y : int ) : exn int

where println has a console effect and divide may raise an exception (exn) when dividing by zero. It is beyond the scope of this paper to go into full detail, but a novel feature of Koka is that it supports typed algebraic effect handlers which can define new effects like async/await, iterators, or co-routines without needing to extend the language itself [24–26]. Koka uses algebraic data types extensively. For example, we can define a polymorphic list of elements of type a as: type list⟨ a⟩ { Cons( head : a, tail : list⟨ a⟩ ) Nil

}

We can match on a list to define a polymorphic map function 
that applies a function f to each element of a list xs: 
fun map( xs : list⟨ a⟩ , f : a -> e b ) : e list⟨ b⟩ { 
match(xs) { 
Cons(x,xx) -> Cons(f(x), map(xx,f)) 
Nil -> Nil 

} }

Here we transform the list of generic elements of type a to a list of generic elements of type b. Since map itself has no

intrinsic effect, the overall effect of map is polymorphic, and equals the effect e of the function f as it is applied to every element. The map function demonstrates many interesting aspects of reference counting and we use it as a running example in the following sections.

2.2 Precise Reference Counting An important attribute that sets Perceus apart is that it is pre cise: an object is freed as soon as no more references remain. By contrast, common reference counting implementations tie the liveness of a reference to its lexical scope, which might retain memory longer than needed. Consider: fun foo() { val xs = list(1,1000000) // create large list val ys = map(xs, inc) // increment elements print(ys)

}

Many compilers emit code similar to: fun foo() { val xs = list(1,1000000) val ys = map(xs, inc) print(ys) drop(xs) drop(ys)

}

where we use a gray background for generated operations. The drop(xs) operation decrements the reference count of an object and, if it drops to zero, recursively drops all chil dren of the object and frees its memory. These “scoped life time” reference counts are used by the C++ shared_ptr⟨ T⟩(calling the destructor at the end of the scope), Rust’s Rc⟨ T⟩(using the Drop trait), and Nim (using a finally block to call destroy) [53]. It is not required by the semantics, but Swift typically emits code like this as well [14]. Implementing reference counting this way is straightfor ward and integrates well with exception handling where the drop operations are performed as part of stack unwinding. But from a performance perspective, the technique is not always optimal: in the previous example, the large list xs is retained in memory while a new list ys is built. Both exist for the duration of print, after which a long, cascading chain of drop operations happens for each element in each list. Perceus takes a more aggressive approach where owner ship of references is passed down into each function: now map is in charge of freeing xs, and ys is freed by print: no drop operations are emitted inside foo as all local variables are consumed by other functions, while the map and print functions drop the list elements as they go. In this example, Perceus generates the code for map as given in Figure 1b. In the Cons branch, first the head and tail of the list are dupped, where a dup(x) operation increments the reference count of an object and returns itself. The drop(xs) then frees the initial list node. We need to dup f as well as it is used twice, while x and xx are consumed by f and map respectively.

At first blush, this seems more expensive than the scoped approach but, as we will see, this change enables many fur ther optimizations. More importantly, transferring owner ship, rather than retaining it, means we can free an object immediately when no more references remain. This both increases cache locality and decreases memory usage. For map, the memory usage is halved: the list xs is deallocated while the new list ys is being allocated. 2.3 Drop Specialization Once we change to precise, ownership-based reference count ing, there are many further optimization opportunities. After the initial insertion of dup and drop operations, we perform a drop specialization pass. The basic drop operation is defined in pseudocode as: fun drop( x ) { if (is-unique(x)) then drop children of x; free(x) else decref(x)

}

and drop specialization essentially inlines the drop opera tion specialized at a specific constructor. Figure 1c shows the drop specialization of our map example. Note that we only apply drop specialization if the children are used, so no specialization takes place in the Nil branch. Again, it appears we made things worse with extra opera tions in each branch, but we can perform another transfor mation where we push down dup operations into branches followed by standard dup/drop fusion where corresponding dup/drop pairs are removed. Figure 1d shows the code that is generated for our map example. After this transformation, almost all reference count op erations in the fast path are gone. In our example, every node in the list xs that we map over is unique (with a refer ence count of 1) and so the if (is-unique(xs)) test always succeeds, thus immediately freeing the node without any further reference counting. 2.4 Reuse Analysis There is more we can do. Instead of freeing xs and imme diately allocating a fresh Cons node, we can try to reuse xs directly as first described by Ullrich and de Moura [46]. Reuse analysis is performed before emitting the initial reference counting operations. It analyses each match branch, and tries to pair each matched pattern to allocated constructors of the same size in the branch. In our map example, xs is paired with the Cons constructor. When such pairs are found, and the matched object is not live, we generate a drop-reuse operation that returns a reuse token that we attach to any constructor paired with it: fun map( xs, f ) { match(xs) { Cons(x,xx) { val ru = drop-reuse(xs) Cons@ru( f(x), map(xx, f))

} Nil -> Nil

}

(a)

fun map( xs : list⟨ a⟩ , f : a -> e b ) : e list⟨ b⟩ { match(xs) { Cons(x,xx) -> Cons(f(x), map(xx,f)) Nil -> Nil

(b) (c) (d)

} }

(e) (f) (g)

(a) A polymorphic map function fun map( xs, f ) { match(xs) { Cons(x,xx) { dup(x); dup(xx); drop(xs) Cons( dup(f)(x), map(xx, f))

fun map( xs, f ) { match(xs) { Cons(x,xx) { if (is-unique(xs)) then free(xs) else dup(x); dup(xx); decref(xs) Cons( dup(f)(x), map(xx, f))

fun map( xs, f ) { match(xs) { Cons(x,xx) { dup(x); dup(xx) if (is-unique(xs)) then drop(x); drop(xx); free(xs) else decref(xs) Cons( dup(f)(x), map(xx, f))

} Nil { drop(xs); drop(f); Nil }

}

} Nil { drop(xs); drop(f); Nil }

}

} Nil { drop(xs); drop(f); Nil }

} } } }

(c) drop specialization (2.3)

(d) push down dup and fusion (2.3)

(b) dup/drop insertion (2.2)

fun map( xs, f ) { match(xs) { Cons(x,xx) { dup(x); dup(xx); val ru = drop-reuse(xs) Cons@ru( dup(f)(x), map(xx, f))

fun map( xs, f ) { match(xs) { Cons(x,xx) { val ru = if (is-unique(xs)) then &xs else dup(x); dup(xx); decref(xs); NULL Cons@ru( dup(f)(x), map(xx, f))

| dup(x); dup(xx); | | | | | |
| --- | --- | --- | --- | --- | --- |
| val ru = if | (is-unique(xs)) | | | | |
| then | | drop(x); | | drop(xx); | &xs |
| else | | decref(xs); | | | NULL |
| Cons@ru( dup(f)(x), | | | map(xx, | | f)) |

fun map( xs, f ) { match(xs) { Cons(x,xx) { } Nil { drop(xs); drop(f); Nil }

}

} Nil { drop(xs); drop(f); Nil } } Nil { drop(xs); drop(f); Nil }

(f) drop-reuse specialization (2.4)

(g) push down dup and fusion (2.4)

(e) reuse token insertion (2.4)

Fig. 1. Drop specialization and reuse analysis for map.

}

A constructor expression like Cons@ru(x,xx) is implemented in pseudocode as:

fun Cons@ru( x, xx) { if (ru!=NULL) then { ru->head := x; ru->tail := xx; ru } // in-place else Cons(x,xx) // malloc’d

}

The Cons@ru annotation means that (at runtime) if ru==NULL then the Cons node is allocated fresh, and otherwise the mem ory at ru is of the right size and can be used directly. Figure 1e shows the generated code after reference count insertion. Compared to the program in Figure 1b, the generated code now consumes xs using drop-reuse(xs) instead of drop(xs). Just like with drop specialization we can also specialize drop-reuse. The drop-reuse operation is specified in pseu docode as:

However, for our map example there would be no benefit to specializing as all fields are assigned. Thus, we only specialize constructors if at least one of the fields stays the same. As an example, we consider insertion into a red-black tree [17]. We define red-black trees as:

fun drop-reuse( x ) { if (is-unique(x)) then drop children of x; &x else decref(x); NULL

}

type color { Red; Black } 
type tree { 
Leaf 
Node(color: color, left: tree, key: int, 
value: bool, right: tree) 

}

where &x returns the address of x. Figure 1f shows the code for map after specializing the drop-reuse. Again, we can push down and fuse the dup operations, which finally results in the code shown in Figure 1g. In the fast path, where xs is uniquely owned, there are no more reference counting operations at all! Furthermore, the memory of xs is directly reused to provide the memory for the Cons node for the returned list – effectively updating the list in-place.

The red-black tree has the invariant that the number of black nodes from the root to any of the leaves is the same, and that a red node is never a parent of red node. Together this ensures that the trees are always balanced. When inserting nodes, the invariants need to be maintained by rebalancing the nodes when needed. Okasaki’s algorithm [37] implements this elegantly and functionally (the full algorithm can be found in accompanying technical report [41]):

2.5 Reuse Specialization The final transformation we apply is reuse specialization, by which we can further reuse unchanged fields of a constructor.

void inorder( tree* root, void (*f)(tree* t) ) { tree* cursor = root; while (cursor != NULL /* Tip */) { if (cursor->left == NULL) { // no left tree, go down the right f(cursor->value); cursor = cursor->right; } else { // has a left tree tree* pre = cursor->left; // find the predecessor while(pre->right != NULL && pre->right != cursor) { pre = pre->right;

} 
if (pre->right == NULL) { 
// first visit, remember to visit right tree 
pre->right = cursor; 
cursor = cursor->left; 
} else { 
// already set, restore 
f(cursor->value); 
pre->right = NULL; 
cursor = cursor->right; 

} } } }

Fig. 2. Morris in-order tree traversal algorithm in C.

fun bal-left( l : tree, k : int, v : bool, r : tree ): tree { match(l) { Node(_, Node(Red, lx, kx, vx, rx), ky, vy, ry) -> Node(Red, Node(Black, lx, kx, vx, rx), ky, vy, Node(Black, ry, k, v, r))

...

} 
fun ins( t : tree, k : int, v : bool ): tree { 
match(t) { 
Leaf -> Node(Red, Leaf, k, v, Leaf) 
Node(Red, l, kx, vx, r) // second branch 
-> if (k < kx) then Node(Red, ins(l, k, v), kx, vx, r) 
... 
Node(Black, l, kx, vx, r) 
-> if (k < kx && is-red(l)) 
then bal-left(ins(l,k,v), kx, vx, r) 
... 

}

For this kind of program, reuse specialization is effective. For example, if we look at the second branch in ins we see that the newly allocated Node has almost all of the same fields as t except for the left tree l which becomes ins(l,k,v). After reuse specialization, this branch becomes:

Node(Red, l, kx, vx, r) { // second branch val ru = if (is-unique(t)) then &t else { dup(l); dup(kx); dup(vx); dup(r); NULL } if (dup(k) < dup(kx)) { val y = ins(l,k,v) if (ru!=NULL) then { ru->left := y; ru } // fast path else Node(Red, y, kx, vx, r)

}

In the fast path, where t is uniquely owned, t is reused directly, and only its left child is re-assigned as all other fields stay unchanged. This applies to many branches in this example and saves many assignments. Moreover, the compiler inlines the bal-left function. At that point, every matched Node constructor has a correspond ing Node allocation – if we consider all branches we can see that we either match one Node and allocate one, or we match three nodes deep and allocate three. With reuse analysis this type visitor { Done BinR( right:tree, value : int, visit : visitor ) BinL( left:tree, value : int, visit : visitor )

} type direction { Up; Down }

fun tmap( f : int -> int, t : tree, visit : visitor, d : direction ) : tree { match(d) { Down -> match(t) { // going down a left spine Bin(l,x,r) -> tmap(f,l,BinR(r,x,visit),Down) // A Tip -> tmap(f,Tip,visit,Up) // B } Up -> match(visit) { // go up through the visitor Done -> t // C BinR(r,x,v) -> tmap(f,r,BinL(t,f(x),v),Down) // D BinL(l,x,v) -> tmap(f,Bin(l,x,t),v,Up) // E

} } }

Fig. 3. FBIP in-order tree traversal algorithm in Koka.

means that every Node is reused in the fast path without doing any allocations! Essentially this means that for a unique tree, the purely functional algorithm above adapts at runtime to an in-place mutating re-balancing algorithm (without any further allo cation). Moreover, if we use the tree persistently [36], and the tree is shared or has shared parts, the algorithm adapts to copying exactly the shared spine of the tree (and no more), while still rebalancing in place for any unshared parts.

2.6 A New Paradigm: Functional but In-Place (FBIP) The previous red-black tree rebalancing showed that with Perceus we can write algorithms that dynamically adapt to use in-place mutation when possible (and use copying when used persistently). Importantly, a programmer can rely on this optimization happening, e.g. they can see the match patterns and match them to constructors in each branch. This style of programming leads to a new paradigm that we call FBIP: “functional but in place”. Just like tail-call op timization lets us describe loops in terms of regular func tion calls, reuse analysis lets us describe in-place mutating imperative algorithms in a purely functional way (and get persistence as well). Consider mapping a function f over all elements in a binary tree in-order:

type tree { Tip Bin( left: tree, value : int, right: tree )

} 
fun tmap( t : tree, f : int -> int ) : tree { 
match(t) { 
Bin(l,x,r) -> Bin( tmap(l,f), f(x), tmap(r,f) ) 
Tip -> Tip 

} }

This is already quite efficient as all the Bin and Tip nodes are reused in-place when t is unique. However, the tmap function is not tail-recursive and thus uses as much stack space as the depth of the tree. In 1968, Knuth posed the problem of visiting a tree in order while using no extra stack- or heap space [22] (For

readers not familiar with the problem it might be fun to try this in your favorite imperative language first and see that it is not easy to do). Since then, numerous solutions have appeared in the literature. A particularly elegant solution was proposed by Morris [35]. This is an in-place mutating algorithm that swaps pointers in the tree to “remember” which parts are unvisited. It is beyond this paper to give a full explanation, but a C implementation is shown in Figure 2. The traversal essentially uses a right-threaded tree to keep track of which nodes to visit. The algorithm is subtle, though. Since it transforms the tree into an intermediate graph, we need to state invariants over the so-called Morris loops [29] to prove its correctness. We can derive a functional and more intuitive solution using the FBIP technique. We start by defining an explicit visitor data structure that keeps track of which parts of the tree we still need to visit. In Koka we define this data type as visitor given in Figure 3. (Interestingly, our visitor data type can be generically derived as a list of the derivative of the tree data type2 [20, 30]). We also keep track of which direction we are going, either Up or Down the tree. We start our traversal by going downward into the tree with an empty visitor, expressed as tmap(f, t, Done, Down). The key idea is that we are either Done (C), or, on going downward in a left spine we remember all the right trees we still need to visit in a BinR (A) or, going upward again (B), we remember the left tree that we just constructed as a BinL while visiting right trees (D). When we come back (E), we restore the original tree with the result values. Note that we apply the function f to the saved value in branch D (as we visit in-order), but the functional implementation makes it easy to specify a pre-order traversal by applying f in branch A, or a post-order traversal by applying f in branch E. Looking at each branch we can see that each Bin matches up with a BinR, each BinR with a BinL, and finally each BinL with a Bin. Since they all have the same size, if the tree is unique, each branch updates the tree nodes in-place at runtime without any allocation, where the visitor structure is effectively overlaid over the tree nodes while traversing the tree. Since all tmap calls are tail calls, this also compiles to a loop and thus needs no extra stack- or heap space. Finally, just like with re-balancing tree insertion, the algo rithm as specified is still purely functional: it uses in-place up dating when a unique tree is passed, but it also adapts grace fully to the persistent case where the input tree is shared, or where parts of the input tree are shared, making a single copy of those parts of the tree.

2Conor McBride [30] describes how we can generically derive a zipper [20] visitor for any recursive type x. F as a list of the derivative of that type, namely list ( x F | x = x.F) . In our case, calculating the derivative of the inductive tree, we get x. 1 + ( tree × int × x) + ( tree × int × x), which corresponds to the visitor datatype.

2.7 Static Guarantees and Language Features So far we have shown that precise reference counting en ables powerful analyses and optimizations of the reference counting operations. In this section, we use Koka as an exam ple to discuss how strong static guarantees at compile-time can further allow the precise reference counting approach to be integrated with non-trivial language features. 2.7.1 Non-Linear Control Flow. An essential require ment of our approach is that programs have explicit control flow so that it is possible to statically determine where to insert dup and drop operations. However, it is in tension with functions that have non-linear control flow, e.g. may throw an exception, use a longjmp, or create an asynchronous con tinuation that is never resumed. For example, if we look at the code for map before applying optimizations, we have: fun map( xs, f ) { match(xs) { Cons(x,xx) { dup(x); dup(xx); drop(xs); dup(f) Cons( f(x), map(xx, f) )

} ...

If f raised an exception and directly exited the scope of map, then xx and f would leak and never be dropped. This is one reason why a C++ shared_ptr is tied to lexical scope; it integrates nicely with the stack unwinding mechanism for exceptions that guarantees each shared_ptr is dropped eventually. In Koka, we guarantee that all control-flow is compiled to explicit control-flow, so our reference count analysis does not have to take non-linear control-flow into account. This is achieved through effect typing (Section 2.1) where every function has an effect type that signifies if it can throw ex ceptions or not. Functions that can throw are compiled into functions that return with an explicit error type that is either Ok, or Error if an exception is thrown. This is checked and propagated at every invocation3. For example, for map the compiled code (before optimiza tion) becomes like: fun map( xs, f ) { match(xs) { Cons(x,xx) { dup(x); dup(xx); drop(xs); dup(f) match(f(x)) { Error(err) -> { drop(xx); drop(f); Error(err); } Ok(y) -> { match(map(xx, f)) { Error(err) -> drop(y); Error(err) Ok(ys) -> Cons(y,ys)

}

...

At this point all errors are explicitly propagated and all control-flow is explicit again. Note the we have no refer ence count operations on the error values as these are im plemented as value types which are not heap allocated.

3Koka actually generalizes this using a multi-prompt delimited control monad that works for any control effect, with essentially the same principle.

This is similar to error handling in Swift [21] (although it requires the programmer to insert a try at every invoca tion), and also similar to various C++ proposals [44] where exceptions become explicit error values. The example here is specialized for exceptions but the actual Koka implementation uses a generalized version of this technique to implement a multi-prompt delimited con trol monad [18] instead, which is used in combination with evidence translation [51] to express general algebraic effect handlers (which in turn subsume all other control effects, like exceptions, async/await, probabilistic programming, etc). 2.7.2 Concurrent Execution. If multiple threads share a reference to a value, the reference count needs to be incre mented and decremented using atomic operations which can be expensive. Ungar et al. [47] report slowdowns up to 50% when atomic reference counting operations are used. Never theless, in languages with unrestricted multi-threading, like Swift, almost all reference count operations need to assume that references are potentially thread-shared. In Koka, the strong type system gives us additional guar antees about which variables may need atomic reference count operations. Following the solution of Ullrich and de Moura [46], we mark each object with whether it can be thread-shared or not, and supply an internal polymorphic op eration tshare : forall a. a -> io () which marks any ob ject and its children recursively as being thread-shared. Even though marking is linear, it happens at most once for any object since shared objects cannot be unshared. All objects start out as unshared, and are only marked through explicit operations. In particular, when starting a new thread, the argument passed to the thread is marked as thread-shared. The only other operation that can cause thread sharing is setting a thread-shared mutable reference but this is quite uncommon in typical Koka code. The drop and dup oper ations can be implemented efficiently by avoiding atomic operations in the fast path by checking the thread-shared flag. For example, drop may be implemented in C as: static inline void drop( block_t* b ) { if (b->header.thread_shared) { if (atomic_dec(&b->header.rc) == 1) drop_free(b); } else if (b->header.rc-- == 1) drop_free(b);

}

However, this may still present quite some overhead as many drop operations are emitted. In Koka we encode the reference count for thread-shared objects as a negative value. This enables us to use a single inlined test to see if we need to take the slow path for either a thread-shared object or an object that needs to be freed; and we can use a fast inlined path for the common case4: static inline void drop( block_t* b ) {

4Since the thread-shared sign-bit is stable, we can do the test b->header.cr <= 1 without needing expensive atomic operations and can use a memory_order_relaxed atomic read.

if (b->header.rc <= 1) drop_check(b); // slow path else b->header.rc--;

}

The drop_check function checks if the reference count is 1 to release it, or otherwise it adjusts the reference count atomically. We also use the negative values to implement a sticky range where very large reference counts (230 in our implementation) stay without being further adjusted (preventing overflow, and keeping them alive for the rest of the program).

2.7.3 Mutation. Mutation in Koka is done through ex plicit mutable references. Here we look at first-class mutable reference cells, but Koka also has second-class mutable local variables that can be more convenient. A mutable reference cell is created with ref, dereferenced with (!) and updated using (:=):

fun ref( init : a ) : st⟨ h⟩ ref⟨ h,a⟩fun (!)( r : ref⟨ h,a⟩ ) : st⟨ h⟩ a fun (:=)( r : ref⟨ h,a⟩ , x : a ) : st⟨ h⟩ ()

where each operation has a stateful effect st⟨ h⟩ in some heap h. A reference cell of type ref⟨ h,a⟩ is a first-class value that contains a reference to a value of type a. As such, there are always two reference counts involved: that of the reference itself, and that of value that is referenced. When a mutable reference cell is thread-shared, this pre sents a problem as an update operation may race with a read operation to update the reference counts. The pseudocode implementation of both operations is: fun (!)( r ) { fun (:=)( r, x ) { val x = r->value val y = r->value dup(x) r->value := x x drop y } }

The read operation (!) first reads the current reference in x, and then increments its reference count. Suppose though that before the dup, the thread is suspended and another thread writes to the same reference: it will read the same object into y, update the reference, and then drop y – and if y has a reference count of 1 it will be freed! When the other thread resumes, it will now try to dup the just-freed object. To make this work correctly, we need to perform both op erations atomically, either through a double-CAS [9], using hazard pointers [15, 33], or using some other locking mecha nism. Either way, this can be quite expensive. Fortunately, in our setting, we can avoid the slow path in most cases. First of all, since FBIP allows for the efficiency of in-place updates with a purely functional specification (Section 2.6), we expect mutable references to be a last resort rather than the default. Secondly, as discussed in Section 2.7.2, we can also check if a mutable reference is actually thread-shared and thus avoid the atomic code path almost all of the time.

2.7.4 Cycles. A known limitation of reference counting is that it cannot release cyclic data structures. Just like with

mutability, we try to mitigate its performance impact by re ducing the potential for this to occur in the first place. In Koka, almost all data types are immutable and either induc tive or coinductive. It can be shown that such data types are never cyclic (and functions that recurse over such data types always terminate). In practice, mutable references are the main way to con struct cyclic data. Since mutable references are uncommon in our setting, we leave the responsibility to the programmer to break cycles by explicitly clearing a reference cell that may be part of a cycle. Since this strategy is also used by Swift, a widely used language where most object fields are mutable, we believe this is a reasonable approach to take for now. However, we have plans for future improvements: since we know statically that only mutable references are able to form a cycle, we could generate code that tracks those data types at run time and may perform a more efficient form of incremental cycle collection. 2.7.5 Summary. In summary, we have shown how static guarantees at compile-time can be used to mitigate the per formance impact of concurrency and the risk of cycles. This paper does not yet present a general solution to all prob lems with reference counting and future work is required to explore how cycles can be handled more efficiently, and how well Perceus can be used with implicit control flow. Yet, we expect that our approach gives new insights in the general design space of reference counting, and showcase that precise reference counting can be a viable alternative to other approaches. In practice, we found that Perceus has good performance, which is discussed in Section 4.

3 A Linear Resource Calculus In this section we present a novel linear resource calculus, 1, which is closely based on linear logic. The operational semantics of 1is formalized in an explicit heap with refer ence counting, and we prove that the operational semantics is sound. We then formalize Perceus as a sound and precise syntax-directed algorithm of 1and thus provide a theoretic foundation for Perceus. 3.1 Syntax Figure 4 defines the syntax of our linear resource calculus 1. It is essentially an untyped lambda calculus extended with explicit binding as val x = e1; e2, and pattern matching as match. We assume all patterns in match are mutually exclu sive, and all pattern binders are distinct. Syntactic constructs in gray are only generated in derivations of the calculus and are not exposed to users. Among those constructs, dup and drop form the basic instructions of reference counting. Contexts Δ, Γ are multisets containing variable names. We use the compact comma notation for summing (or splitting) multisets. For example, ( Γ, x) adds x to Γ, and ( Γ1, Γ2) ap pends two multisets Γ1 and Γ2. The set of free variables of

Expressions 
e ::= v | e e (value, application) 
| val x = e; e (bind) 
| match x { pi → ei } (match) 
| dup x; e (duplicate) 
| drop x; e (drop) 
| match e { pi → ei } (match expr) 
v ::= x | x. e (variables, functions) 
| C v1 . . . vn (constructor of arity n) 
p ::= C b1 . . .bn (pattern) 
b ::= x | _ (binder or wildcard) 
Contexts Δ, Γ : := ∅ | Δ ∪ x 
Syntactic shorthands 

e1; e2 ≜ val x = e1; e2 sequence, x ̸∈ fv( e2)_. e ≜ x. e x ̸∈ fv( e) x. e ≜ ysx. e ys = fv( e) Fig. 4. Syntax of the linear resource calculus 1.

Δ ↑| Γ
↑ ⊢ e
↑

⇝ e′ ↓ (↑ is input, while ↓ is output)

### Δ | x ⊢ x ⇝ x [ var]

Δ | Γ, x ⊢ e ⇝ e′ x ∈ Δ, Γ Δ | Γ ⊢ e ⇝ dup x; e′ [ dup]

Δ | Γ ⊢ e ⇝ e′ Δ | Γ, x ⊢ e ⇝ drop x; e′ [ drop]

Δ, Γ2 | Γ1 ⊢ e1 ⇝ e′1 Δ | Γ2 ⊢ e2 ⇝ e′2 Δ | Γ1, Γ2 ⊢ e1 e2 ⇝ e′1e′2 [ app]

∅ | Γ, x ⊢ e ⇝ e′ Γ = fv( x. e) Δ | Γ ⊢ x. e ⇝ Γx. e′ [ lam] x ̸∈ Δ, Γ1, Γ2 Δ, Γ2 | Γ1 ⊢ e1 ⇝ e′1 Δ | Γ2, x ⊢ e2 ⇝ e′2 Δ | Γ1, Γ2 ⊢ val x = e1; e2 ⇝ val x = e′1; e′2 [ bind] [match] Δ | Γ, bv( pi) ⊢ ei ⇝ e′i

Δ | Γ, x ⊢ match x { pi ↦→ ei } ⇝ match x { pi ↦→ e′i} Δ, Γi+1, . . ., Γn | Γi ⊢ vi ⇝ v′i 1 ⩽ i ⩽ n Δ | Γ1, . . ., Γn ⊢ C v1 . . . vn ⇝ C v′1 . . . v′n [ con]

Fig. 5. Declarative linear resource rules of 1. an expression e is denoted by fv( e), and the set of bound variables of a pattern p by bv( p).

E ::= □ | E e | v E | val x = E; e

e −→ e′ E[ e] ↦−→ E[ e′] [ eval]

( app) ( x. e) v −→ e[ x:=v] ( bind) val x = v ; e −→ e[ x:=v] ( match) match ( C v1 . . . vn) { pi → ei} −→ ei[ x1:=v1, . . ., xn:=vn]with pi = C x1 . . . xn Fig. 6. Standard strict semantics for 1. 3.2 The Linear Resource Calculus The derivation Δ | Γ ⊢ e ⇝ e′in Figure 5 reads as follows: given a borrowed environment Δ, a linear environment Γ, an expression e is translated into an expression e′ with explicit reference counting instructions. We call variables in the lin ear environment owned. The key idea of 1is that each resource (i.e., owned vari able) is consumed exactly once. That is, a resource needs to be explicitly duplicated (in rule dup) if it is needed more than once; or be explicitly dropped (in rule drop) if it is not needed. The rules are closely related to line

---
source_url: https://kyouko-taiga.github.io/assets/papers/jot2022-mvs.pdf
ingested: 2026-09-12
sha256: 283a92a42989969d0e6911f68f17844dee30fda63ee769f4c4902f0d1ac8a04b
---
# Implementation Strategies for Mutable Value Semantics

Journal of Object Technology | RESEARCH ARTICLE

## Implementation Strategies for Mutable Value Semantics

Dimitri Racordon∗ , §, Denys Shabalin††, Daniel Zheng†, Dave Abrahams‡, and Brennan Saeta† ∗University of Geneva, Faculty of Science, Switzerland §Northeastern University, USA ††Google, Switzerland †Google, USA ‡Adobe, USA

ABSTRACT Mutable value semantics is a programming discipline that upholds the independence of values to support local reasoning. In the discipline’s strictest form, references become second-class citizens: they are only created implicitly, at function boundaries, and cannot be stored in variables or object fields. Hence, variables can never share mutable state. Unlike pure functional programming, however, mutable value semantics allows part-wise in-place mutation, thereby eliminating the memory traffic usually associated with functional updates of immutable data. This paper presents implementation strategies for compiling programs with mutable value semantics into efficient native code. We study Swift, a programming language based on that discipline, through the lens of a core language that strips some of Swift’s features to focus on the semantics of its value types. The strategies that we introduce leverage the inherent properties of mutable value semantics to unlock aggressive optimizations. Fixed-size values are allocated on the stack, thereby enabling numerous off-the-shelf compiler optimizations, while dynamically sized containers use copy-on-write to mitigate copying costs.

KEYWORDS Mutable value semantics, local reasoning, memory safety, borrowing, copy-on-write, compilation, optimizations.

#### 1. Introduction

Software development continuously grows in complexity, as applications get larger and hardware more sophisticated. The essential principle required to build correct systems in the face of growing complexity is local reasoning, described by O’Hearn et al. (2001) as follows: To understand how a program works, it should be possible for reasoning and specification to be con fined to the cells that the program actually accesses. The value of any other cell will automatically remain unchanged. The ability to reason locally about program semantics is also critical for efficiency as it eliminates the need for conservative

JOT reference format: 
Dimitri Racordon, Denys Shabalin, Daniel Zheng, Dave Abrahams, and 
Brennan Saeta. Implementation Strategies for Mutable Value Semantics. 
Journal of Object Technology. Vol. 21, No. 2, 2022. Licensed under 
Attribution 4.0 International (CC BY 4.0) 
http://dx.doi.org/10.5381/jot.2022.21.2.a2 

assumptions about access to the memory. Unfortunately, local reasoning is often lost in a shared memory model, as side effectful operations in one part of the program impact seemingly unrelated locations. Pure functional programming addresses this problem by sim ply outlawing mutation. Unfortunately, this paradigm may fail to capture the programmer’s mental model, or prove ill-suited to express and optimize some algorithms (O’Neill 2009), due to the inability to express in-place mutation. For instance, if x is a binary tree, an assignment that in Java could be written x.left.left.right = v must be translated into a cumbersome composition of updates x’ = updateLeft(x, updateLeft(x.left , updateRight(x.left.right, v))), which can only match the algorithmic efficiency of the original formulation through opti mizer heroics that eliminate unnecessary copies of temporary data (Johann 2003). Another way to uphold local reasoning is to use first-class references, but tame their aliasing. Newer programming lan guages have blended ideas from ownership types (Clarke et al. 2013), type capabilities (Haller & Odersky 2010), and region based memory management (Tofte et al. 2004), offering more

An AITO publication

freedom to write efficient and type-safe programs. These ideas, however, invariably complicate type systems with mechanisms like named lifetimes, which significantly raise the barrier to entry for inexperienced developers (?).

1 fn longer_of ( x: String , y: String ) −> String { 
2 if x. len () > y. len () { x } else { y } 
3 } 
4 
5 fn report_longest (x: String , y: String ) { 
6 let z = longer_of (x , y) ; 
7 println !(" longest of {:?} and {:?} is {:?} ", 
8 x , y , z ); // <− error 
9 } 

Consider the Rust (Matsakis & Klock 2014) example above. A simple function longer_of returns the longer of two character strings. Its caller, report_longest, also simple, is ill-typed. The compiler complains that x and y have been moved (into the call to longer_of), and can no longer be used. Ending variable life times early is part of Rust’s strategy for ensuring memory safety without creating expensive copies at function call boundaries. These goals are difficult to reconcile, so it’s perhaps not surpris ing that simple-looking code exposes language complexity. Mutable value semantics (MVS) sits at third point in the design space where both goals are satisfied and mutation is supported, without the complexity inherent to flow-sensitive type systems. The key to this balance is simple: MVS does not surface references as a first-class concept in the programming model. As such, they can neither be assigned to a variable nor stored in object fields, and all values form disjoint topological trees rooted in the program’s variables. The reader may justifiably wonder whether a discipline with these restrictions is expressive enough to write efficient, non trivial programs. We note that a large body of software projects across multiple languages already answer this question empiri cally, such as the Boost Graph Library (Siek et al. 2002), a col lection of generic components (Stepanov & Rose 2014) for com putations on graphs in C++, and Swift for TensorFlow (Saeta et al. 2021), a high-performance platform for machine learn ing. Further, we observe that well-established programming languages have adopted MVS at the core of their semantics, such as R (R Core Team 2020) and Swift (Apple Inc. 2021), for safety and/or efficiency. In more detail, Swift is a modern general-purpose program ming language, used in a broad spectrum of applications. Its standard library offers a rich collection of reusable components based on MVS, while striving to show competitive performance against comparable libraries in programming languages such as C, C++ and Rust. The language is translated to native code using an LLVM (Lattner & Adve 2004) backend. After a brief introduction of the core tenets of MVS (Sec tion 2), we explore some of these implementation strategies and make the following contributions: – We propose a core language called Swiftlet, a subset of Swift focused exclusively on MVS. We introduce Swiftlet through a series of examples (Section 3) and formalize its semantics (Section 4). – We discuss a compiler for Swiftlet that supports the cre ation of zero-cost abstractions (Section 5).

– We present a handful of compiler optimizations relying on local reasoning and leveraging runtime knowledge to elide unnecessary copies (Section 6). – We report performance measurements on handwritten and randomly generated programs with varying numbers of mu tating operations, comparing results between Swift, Swift let, Scala, and C++ to demonstrate the benefits of MVS over functional updates (Section 7).

#### 2. Mutable value semantics

Before we delve deeper into the details of a language implemen tation, we ought to define precisely what MVS is and how it differs from the more widespread reference semantics.

2.1. Primitive and compound types Popular object-oriented programming languages have converged on a common mutation model that distinguishes between so called “primitive” or “built-in” types (typically numeric types) and “compound” types (typically arrays and classes). Variables of primitive types are independent: the value assigned to a variable of a primitive type cannot change due to an operation on another variable in the program. In contrast, variables of compound type may share state with other variables. Hence, the value assigned to a variable of a compound type can change due to an operation on another variable.

1 class Vec2 { int x , y; } // Primitive fields 
2 class Rect { Vec2 pos , dim ; } // Compound fields 
3 
4 int i1 = 2; // Same pattern with 
5 Vec2 v1 = new Vec2 (i1 , i1 ); // − int : primitive 
6 Rect r1 = new Rect (v1 , v1 ); // − Vec2 : compound 
7 Rect r2 = r1 ; 
8 
9 r2 . dim .x += 4 // Mutates r2 
10 System . out . println ( r1 . pos . x) // Now 6: r1 changed 
11 System . out . println ( r1 . pos . y) // 2: no change 

Listing 1 Compound types in Java have reference semantics

Consider the Java program above, which illustrates the dis tinction in full detail. In lines 1 and 2, it declares compound types Vec2 and Rect, representing 2d vectors and rectangles, respectively. In line 5, both primitive-type fields of v1 are initial ized to the value of the same variable. In line 6, both compound type fields of r1 are initialized with v1, causing r1.pos to share state with r1.dim. In line 7, assignment causes r1 to share state with r2. After line 7, the contents of the program’s memory can be depicted as in Figure 1a. Line 9 performs a mutation, growing the x dimension of r2 by 4. Line 10 shows that the mutation has had a non-local effect, changing r1.pos, a distinct variable of compound type. Line 11 shows that, by contrast, the mutation has not changed the value of the field r1.pos.y, a distinct variable of primitive type, initialized in the same way. This difference in behavior demonstrates that Java has two different kinds of mutation semantics: one for “primitive” types and another for “compound” types.

v1 
r1 
r2 

:Rect pos dim

:Vec2 
x 2 
y 2 

(a) With reference semantics

2

x:Int

2

y:Int pos:Vec2

2

x:Int

2

y:Int dim:Vec2 r1:Rect

2

x:Int

2

y:Int pos:Vec2

2

x:Int

2

y:Int dim:Vec2 r2:Rect

(b) With value semantics Figure 1 Contents of the memory of a program involving compound types. Arrows represent references and boxes represent whole/part relationships.

2.2. Value and reference semantics We can decouple these two mutation semantics from the ques tion of whether a type is “primitive” or “compound”. In fact, one could argue that it makes more sense for a notional vector value like Vec2 to behave just like a scalar int. A more gen eral distinction separates types with reference semantics, which behave like Java’s compound types, from those with value se mantics, which behave like Java’s primitive types. Conceptually, two variables of a reference type can share mutable state, but two variables of a value type cannot. Because the difference in behavior always involves mutation, an immutable type can be said to have value semantics trivially. Mutation by assigning a whole new value to a variable can be rewritten as binding a new variable, with no mutation, so is triv ially equivalent. Therefore, to distinguish the nontrivial cases of interest, we say that a value type has mutable value semantics when its parts can be mutated in-place, without reassigning a variable of the type.

1 struct Vec2 { var x: Int , y: Int } 
2 struct Rect { var pos : Vec2 , dim : Vec2 } 
3 
4 var i1 = 2 
5 var v1 = Vec2 (x : i1 , y: i1 ) 
6 var r1 = Rect ( pos : v1 , dim : v1 ) 
7 var r2 = r1 
8 
9 r2 . dim .x += 4 // Mutates r2 
10 print ( r1 . pos .x) // Prints 2: r1 unchanged 
11 print ( r1 . pos .y) // Prints 2 

Listing 2 Swift has compound types with value semantics Consider the Swift program above, a direct transliteration of the Java code from Listing 1, but using only types with mutable value semantics. In Swift, structs are value types, so after line 6, r1.pos and r1.dim do not share state. Figure 1b depicts the contents of the program’s memory after line 7. Note that we use nesting rather than arrows to represents relationships between values and their parts, because values never share parts. Unlike in Java, the dimensions of r2 are independent from those of r1. Hence, the mutation of r2 at line 9 does not propagate to r1, as shown by the print statement at line 10.

2.3. Spooky action at a distance Our Java example demonstrates how programming with refer ence types implicitly introduces aliasing—a condition where two or more live variables refer to the same memory location— every time a variable is passed to a function or assigned to another variable. Unfortunately, leaving alias creation implicit in the language creates a collection of problems (Noble et al. 1998) that we informally dub spooky action at a distance.1 In short, neither humans nor machines (e.g., optimizing compilers) can reason locally about mutation semantics in the presence of aliases. Consider the so-called “signing flaw”, a security vulnerabil ity discovered in a previous version of the Java platform that allowed untrusted applets to escalate access into the virtual ma chine (Vitek & Bokowski 2001). The vulnerability was caused by a reference leak, giving the attacker the means to mutate the system’s internal list of signatures. The following snippet is a simplified excerpt of the flawed implementation:

1 public class Class { 
2 public Identity [] getSigners () { 
3 return this . signers ; 
4 } 
5 private final Identity [] signers ; 
6 } 

The field signers is exposed via the method getSigners. An attacker could thus obtain an alias on the list of trusted signers and alter it as they see fit. Although the field is private final and is thus neither accessible to clients nor reassignable, nothing prevents a method from accidentally leaking a reference to the object it holds, and through that reference, the list can be mutated (Potanin et al. 2013). The standard prescription for accidental aliasing in Java is the manual insertion of defensive copies, but that is hardly an adequate cure: a missed defensive copy is a possible security vulnerability, an extra copy a source of inefficiency. Alias pre vention mechanisms like ownership types (Clarke et al. 2013) and confined types (Vitek & Bokowski 2001)) are safer, but re quire complex annotations in code. Even when applied correctly, defensive copies must be made conservatively, without dynamic knowledge of how the objects will ultimately be used—for ex ample, whether they are eventually mutated, or even inspected— and thus impose a heavy performance tax. Below the level of the programming model, the mere possibility of mutation through a shared reference creates additional costs (Shaikhha et al. 2017). Optimizing compilers such as GCC and LLVM go to sig nificant lengths to “model the heap” to prove references and pointers do not alias. In cases where uniqueness cannot be

1 With apologies to Einstein.

Implementation Strategies for Mutable Value Semantics 3 proven, code generation becomes pessimistic. Examples of inhibited optimizations include: writing and reloading regis ters from memory, disabling loop-invariant code motion, and preventing vectorization. By contrast, programming with value types rules out alias ing by construction, making it easy to reason about mutation and eliminating this class of bugs. Furthermore, a variable of value type can live exclusively in registers—even when it is compound, and across opaque function boundaries—allowing a compiler to reliably vectorize without modeling the heap. In other words, programming with values yields predictable per formance without risking regression by changing code in a way that would cause optimizers to fall short, due to conservative assumptions. 2.4. The murky depths of ambiguous relationships Implicit aliasing is not the only problem introduced by pervasive reference semantics: it has also led to a widespread fallacious mental model among programmers. Consider the routine ques tion faced by object-oriented developers of whether copying, mutability, or comparison should be “deep” or “shallow” in the context of the following Java example:

1 interface ClickListener { 
2 void clickOccurred () ; 
3 } 
4 
5 public class Button { 
6 private Point position ; 
7 private ClickListener clickHandler ; 
8 } 

It would be inappropriate to “shallow copy” a Button–a dis tinct copy of a Button instance needs a distinct copy of its position. If Button is “deep-copied”, though, its clickHandler will be copied too, which is almost certainly inappropriate. Even if a “deep” copy were appropriate for the clickHandler, we’d have to ask, “how deep?” Since the details of the clickHandler are unknown, there is no answer. In fact, the exact same prob lem applies to both mutability and comparison: neither “deep” nor “shallow” will “cut it.” Each reference in this example represents a relationship be tween the Button and some other object. If we look closely at the nature of those relationships, we can see that there’s something special about the Button’s relationship to its position that makes “deep” treatment appropriate: it connects a whole to its part. While our initial example clearly demonstrates that the idea of “deep” or “shallow” copying is inadequate, recognizing the significance of whole-part relationships suggests that the idea itself is fallacious. Since a correct copy creates an independent but equivalent value of an instance and all of its parts, it would be fair to say there are no correct “deep” or “shallow” copies, only “copies”. This widespread misunderstanding would not exist but for the ambiguous meaning of stored references. It is striking, then, that despite the importance in UML of distinguishing “composi tion” and “aggregation” from mere “association”, and despite UML’s profound influence on object-oriented programming, the whole-part relationship is not surfaced by most object-oriented languages.

Aside from representing arbitrary relationships, stored refer ences hav a second role: they provide access to the related data. In fact it is this access, combined with mutation, that leads to the “spooky action” discussed earlier, because when a reference is copied, access goes along with the relationship. It is interesting to ask, then, what would happen if we decoupled those roles? As it turns out, MVS does just that. In MVS, composition always represents a whole-part rela tionship. This direct representation of composition benefits more than code clarity. The compiler is able to synthesize fun damental, tedious, and error-prone operations such as copying, equality and hashing. More importantly, it can automatically propagate immutability. This last capability has a powerful and non-obvious consequence: given a mutable type, application of a simple ‘let’ to a declared instance, produces a correct im mutable instance. In reference-based languages such as Scala, Objective-C, and JavaScript, where the whole-part relationships are obscured, immutability is both more important—it is the only route to local reasoning—and much harder to achieve. In all of these languages it is common to see a separate immutable type created for every mutable one. (Odersky & Moors 2009; Bierema 2022).

2.5. Representing other relationships Because whole/part relationships do not admit aliasing, they always form a tree, with the parts of a compound type being its children. It is reasonable to ask, then, how we can use mutable value types to represent self-referential data structures, such as doubly linked lists and directed graphs. In fact, any arbitrary graph can be represented as an adja cency list. For example, a vertex set might be represented as an array, each element of which contains an array of outgoing edge destination indices. This approach can be seen as decou pling the two roles of first-class references: inner array elements represent relationships without conferring direct access to the related data, which is only available through the object of which it is a part.2

Naturally, losing the ability to directly access data through references changes the way programs are written. For exam ple, traversing an arbitrary graph requires access to the whole graph at each step, rather than just a single vertex and its out going edges. In exchange, we get improved expressiveness, correctness, and even performance (Siek et al. 2002).

2.6. Semantic regularity and generic programming Uniform mutation semantics makes it possible to create user defined mathematical abstractions that behave like built-in nu meric types. To illustrate, we can add a += operator to the Vec2 type introduced earlier.3 Here, applying the mutating operator += to v1 affects only the value of v1, and not that of v2, just as if they were integers.

1 struct Vec2 { 
2 var x: Int , y: Int 
2 We note that the idea of dissociating the knowledge of a location from the 
right to access is central to capability-based approaches (Smith et al. 2000). 
3 The inout keyword seen here expresses argument mutation, and is explored 
in detail in Section 3. 

3 static func += (a : inout Self , b : Self ) { 
4 a.x += b.x 
5 a.y += b.y 
6 } 
7 } 
8 var v1 = Vec2 (x: 2, y: 2) 
9 var v2 = v1 
10 v2 += Vec2 (x : 1, y: 0) 
11 print ( v1 ) // Vec2 (x: 2, y: 2) 
12 print ( v2 ) // Vec2 (x: 3, y: 2) 

Semantic uniformity is a prerequisite for generic program ming, the discipline of realizing algorithms and data structures so they work in the most general setting possible, without loss of efficiency (Stepanov & Rose 2014).4 Indeed, it becomes difficult to even describe the semantics of an algorithm if any part of it can have non-local effects.

#### 3. Swiftlet

Swiftlet is a subset of Swift, focusing on value types and dis carding all features that are not essential to their description. Our language only features structs (i.e., compounds of het erogeneous types), arrays (i.e., dynamically sized collections of homogeneous data), functions, and numeric (integer and floating-point) values. The result is a language whose complete operational semantics fits a single page (Section 4). A program is described by a sequence of struct declarations, followed by a single expression denoting an entry point (i.e., the contents of the main file in a regular Swift program). A variable is declared with the keyword var followed by a name, an optional type annotation, an initial value, and the expression in which it is bound. A constant is declared similarly, with the keyword let. Naturally, a variable can be mutated or reassigned whereas a constant cannot.

1 var foo : Int = 4; 
2 let bar = foo ; 
3 print ( bar ) // Prints 4 

A struct is a compound type composed of zero or more fields. Each field is typed explicitly with an annotation and associated with a mutability qualifier (let or var) specifying whether it is constant or mutable. Fields can be of any type, but—for simplicity only—type definitions cannot be mutually recursive. Hence, all values have a finite representation.

1 struct Vec2 { ... }; 
2 var v = Vec2 (x: 4, y: 2) ; 
3 print (v. y) // Prints 2 

As all types have value semantics, values form disjoint topo logical trees rooted at variables or constants. Conceptually, an assignment is always a copy of the right operand5and does not create an alias. In the program below, u is assigned a copy of v’s value, so the update of u’s second component in line 4 does not modify v.

1 struct Vec2 { ... }; 
2 var v = Vec2 (x: 4, y: 2) ; 
4 Generic programming as described by its originators depends on the concept 
of regularity (Stepanov & McJones 2009), a refinement of value semantics. 
5 We discuss how the language implementation eliminates unnecessary eager 
copies in Section 6. 

3 var u = v; 4 u. y = 8 // v = Vec2 (x: 4 , y: 2) 5 // u = Vec2 (x: 4 , y: 8)

Immutability applies transitively. All fields of a struct bound to a constant are also treated as immutable by the type system, regardless of their declaration. For example, the program below is ill-typed because v.y denotes a constant, notwithstanding that field having been declared with var.

1 struct Vec2 { ... }; 
2 let v = Vec2 (x: 4, y: 2) ; 
3 v. y = 8 // <− type error 

Likewise, all elements of an array are constant if the array itself is bound to a constant.

1 struct Vec2 { ... }; 
2 let a = [ Vec2 (x: 4, y: 2) , Vec2 (x: 5, y: 3) ]; 
3 a [0]. y = 8 // <− type error 

Functions are declared with the keyword func followed by a name, a list of typed parameters, a codomain, and a body. Arguments are evaluated eagerly and passed by value. Functions are allowed to be mutually recursive.

1 func fact (n: Int ) −> Int { 
2 n > 1 ? n ∗ fact (n : n − 1) : 1 
3 }; 
4 fact (6) // Prints 720 

To implement in-place part-wise mutation across function boundaries, a parameter’s type is marked inout, which makes the parameter mutable in the callee. Conceptually, an inout argument is copied when a function is called and copied back when that function returns.6

1 struct Vec2 { ... }; 
2 func translateX (v : inout Vec2 , d : Int ) −> Void { 
3 v.x = v.x + d 
4 }; 
5 var v = Vec2 (x: 4, y: 2) ; 
6 _ = translateX (v: &v , d: 6) ; 
7 print (v. x) // Prints 10 

In the program above, the function translateX accepts an inout parameter of type Vec2, which it is allowed to mutate. The return type, Void, is Swiftlet’s unit type. The function is called at line 6, effectively mutating the value of the vector v across function boundaries. Note that the ampersand featured in the call expression is not the “address-of” operator from C/C++. Instead, it signals in code that the argument is to be mutated—conceptually “copied out” of the callee upon return. Of course, inout extends to multiple arguments, with one important restriction: to prevent any writeback from being dis carded, overlapping mutations are prohibited. In other words, inout arguments must have independent values. This Law of Exclusivity (McCall 2017) creates a crucial optimization oppor tunity: it is safe to sidestep the conceptual copies by allowing the callee to write the argument’s memory in the caller’s context. In other words, inout argument passing can be implemented as pass-by-reference without surfacing reference semantics in the programming model. Remark that inout parameters are reminiscent of (if not iden tical to) borrowing (Naden et al. 2012), as found in languages

6 The Fortran enthusiast may think of the so-called “call-by-value/return” policy.

Implementation Strategies for Mutable Value Semantics 5 like Rust. The difference lies in the way uniqueness is guaran teed. Unlike generalized borrows, inout parameters are second class citizens: they have lexically-bounded lifetimes and must “appear in person” (Strachey 2000). These restrictions ensure that aliases can be prevented simply by verifying that the “path” to a value (i.e., a list of member accesses and/or array subscripts) never appears twice in inout arguments to a single function call.7 If references were granted first-class status, the type sys tem would have to reason about the possible set of values that a variable may have at a particular point in the program, as a path alone would not be sufficient to identify the referred location. One additional restriction applies to paths identifying ele ments of an array. The type system allows the same array to be indexed more than once by inout arguments only if it can conclude that the indices cannot overlap. For example, given an array x, the expression swap(&x[0], &x[1]) is well-typed, but swap(&x[f(0)], &x[1]) is not. In the second case, the type sys tem conservatively assumes that f(0) could be evaluated as any value, including 1.

2

x:Int

5

y:Int pos:Vec2

8

z:Int

(a) swapX(a: &v, b: &z)

2

x:Int

5

y:Int pos:Vec2

8

z:Int

(b) swapX(a: &v, b: &v.y)

Figure 2 Visual representation of path uniqueness

We illustrate path uniqueness metaphorically. Imagine that values are represented by nested boxes, where nesting denotes a whole/part relationship. A path identifies a single box from outside in. Whenever one appears as an inout argument, the type checker paints the referred box with a color specific to that argument’s position. At the end of the process, the program is ill-typed if one box had to be painted with two different colors. We give an example in Figure 2. Let swapX be a function that accepts a vector and an integer as inout parameters—a and b—and swaps in-place the value of the vector’s first component with that of the second parameter.

1 func swapX (a: inout Vec2 , b: inout Int ) 
2 −> Void { ... }; 
3 var v = Vec2 (x: 2, y: 5) ; 
4 var z = 8; 
5 swapX (a: &v , b: &z) ; // <− well − typed 
6 swapX (a: &v , b: &v. y) // <− ill − typed 

Line 5 creates the situation shown in Figure 2a. No box had to be painted with two different colors: the call is well-typed. Line 6, however, produces Figure 2b. The box representing v.y was painted twice: the call is ill-typed. A Swiftlet function must declare any variables that are to be captured in its closure.8 If capture list is not provided, it

7 Note that, where x denotes an array of integers, a path of the form x[x[0]] is a valid inout argument, even if x occurs twice. Each subscript operation can be thought of as a function call, and in this case, the nested expression x[0] is reduced to an index i before the callee gets exclusive access to a path x[i]. 8 Closures with explicit capture lists have a different syntax in Swift. We overlook that detail for simplicity.

is equivalent to a declaration of a zero-argument list with no captures. The value of each capture is then copied from the context surrounding its declaration, thus enforcing capture-by copy semantics, and each capture is immutable.

1 var x = 2; 
2 func f (y: inout Int ) −> Void { 
3 [x ] in // x is captured immutably 
4 y += x ; 
5 }; 
6 f(y : & x); 
7 print (x) // Prints 4 

By contrast, Swift does not require captures to be explicitly declared, and its implicit captures are by-reference, so closures introduce reference semantics. Consider the following example, which is well-typed in Swift but not in Swiftlet:

1 var x = 0; 
2 func g (y: inout Int ) −> Void { y += x }; 
3 g(y : & x) // <− error 

The above program creates overlapping mutable accesses to the same variable: the first obtained by capture, the second as an inout argument, which violates the Law of Exclusivity. This violation, however, is detected only at runtime. Since Swiftlet captures only by copy, it guarantees statically that closures uphold the Law of Exclusivity. Drawing inspiration from linear type systems (Wadler 1990), languages like Rust capture free variables from the environment destructively. We refer to this policy as capture-by-move. Still others use capture-by-reference, but encode side effects on the environment into function types, essentially equipping the lan guage with a type-and-effect system (Rytz et al. 2013). Both of these approaches to capture semantics introduce significant language complexity. Swift methods are defined to be equivalent to free functions accepting an instance of the receiver struct as a first parameter. Therefore, without loss of expressivity, methods are omitted from Swiftlet for simplicity. Although Swiftlet does not provide Swift’s support for generic types—only arrays are generic—rudimentary polymor phism can be achieved via type-erased containers. An instance of type Any can store a value of any type, allowing the creation of type-erased data structures with value semantics.

1 struct Pair { 
2 var _1 : Any 
3 var _2 : Any 
4 }; 
5 
6 let p = Pair ( _1 : 4 as Any , _2 : [7] as Any ); 
7 p. _2 = p as Any ; // Not a reference loop ! 
8 
9 print (p) // Pair (_1: 4, _2: Pair (_1: 4 , _2: [7]) ) 

Line 1 declares Pair, a type that stores two values, each of arbitrary type. Line 6 creates p, a Pair storing an integer 4 as its first element and an array [7] as its second.9 In line 7, p._2 is assigned the value of p. Finally, line 9 prints the contents of p. Note that, because Any has value semantics, line 7 does not

9 Unlike Swift, Swiftlet requires an explicit “as” cast to store an arbitrary value as Any. Further, the language does not provide a safe "downcast" from Any. An invalid cast results an error at runtime.

cause the pair to refer to itself, avoiding an infinite recursion in line 9. Instead, the value of p has been copied into p._2.

| | | name | | | x,s | | | | | |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 4. Formal definition | | context | | | µ, | φs | : | | X → | M V × |
| This section introduces Swiftlet | formally. We start with its | prog. | | | g | | ::= | | d e | |
| syntax and present a first description in the form of big-step inference rules | of its operational semantics (a.k.a. natural semantics). | struct | | | d | | ::= | | struct | ; s b { } |

| in the form of big-step inference rules This semantics is intended to describe | (a.k.a. natural semantics). the high-level user model | qual. | | | m | | ::= | | let | var | |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| and provide a formal framework | for discussing optimization | | | | | | | | | |
| | | bind. | | | b | | ::= | | m x | τ : |
| strategies. | | | | | | | | | | |
| Then, we present the Swiftlet’s | static semantics, and show | | arg. | | a | | ::= | | &r | | e |
| how its type system guarantees uniqueness at function boundaries. | of arguments inout | | expr. | | e | | ::= | | e;e | = = [e] b e e r e r v in | | | | | |

integer c name x,s context µ, φs : X → M × V prog. g ::= d e struct d ::= struct s { b } ; | s(e) | e(a) | e ? e : e | e as τ | func x (x : p) → τ { [x] in e} in e param. p ::= inout τ | τ type τ ::= (p) → τ | [τ] | s | Z | Any | () path r ::= e.x | e[e] | w

φs | [v] | box(v) | c value v ::= λ(x : p,e) |

lvalue w ::= w.x | w[c] | x Figure 3 Formal syntax of Swiftlet

This section introduces Swiftlet formally. We start with its syntax and present a first description of its operational semantics in the form of big-step inference rules (a.k.a. natural semantics). This semantics is intended to describe the high-level user model and provide a formal framework for discussing optimization strategies. Then, we present the Swiftlet’s static semantics, and show how its type system guarantees uniqueness of inout arguments at function boundaries. Although natural semantics is convenient for describing ob servable behaviors (Leroy & Grall 2009), its inability to distin guish failure from non-termination makes it less well-suited to the study of soundness properties. Hence, to demonstrate the guarantees provided by our static semantics, we finally present a second operational semantics in the form of small-step inference rules. 4.1. Notations We use horizontal bar notation to denote sequences of terms. For instance, x expands to x1, . . . , xkfor some k. We write ε for the empty sequence and, for the sake of syntactic regularity, we assume that x1, . . . , xkis an empty sequence if k = 0. We write | x| for the length of the sequence x. We write x : y meaning x1 : y1, . . . , xk : yk. Let f : A → B be a function, dom(f) denotes its domain. If f is a partial function, then dom(f) is the subset A0 ⊆ A for which f is defined. We write f = [⊥ ]A→ B to represent a partial function f : A → B with dom(f) = ∅. We write f = [a 7→b]A→ B to represent a partial function f such that f(a) = b with dom(f) = { a} . We write f = [a 7→ g(a) | p(a)]A→ B for the function that returns g(a) for all a ∈ A that satisfy a predicate p. For example, [i 7→ − i | i ∈ Z ∧ i < 0]Z→ Z denotes a function that maps each negative integer to its absolute value. We omit the subscript when the function’s domain and codomain are obvious from the context. We write f [a 7→ b] for the function that returns b for a and f(x) for any other argument. For instance, if f(0) = 1 and f(1) = 2, then (f [0 7→ 3])(0) = 3 and (f [0 7→ 3])(1) = 2. We write f [a 7→ ⊥ ] for the function that is not defined for a and returns f(x) for any other argument. Given f : A → B and g : A → B, we write f [a 7→ ? g(a)] for the function f [a 7→ g(a)] if a ∈ dom(g), or f otherwise. Let e be a term and σ a set of substitutions represented as a partial function from variables to terms, we write e[/σ] for the term obtained by applying the substitutions σ to e, renaming free variables as necessary. For instance, if e = λa.ab and σ = [b 7→ c], then e[/σ] = λa.ac. 4.2. Syntax Figure 3 presents the formal syntax of Swiftlet. A program g is a sequence of structure declarations followed by a single functional term acting as its entry point.10 A structure is de scribed by a unique global name and a sequence of property declarations. A property is declared by a binding m x : τ where m denotes its mutability, x identifies its name, and τ specifies its type. Other types include integer (written Z)11, homogeneous arrays (written [τ] where τ is the element type), function types (written (p) → τ, where τ is the return type and each p is a parameter type potentially qualified by inout), the existential container type (written Any), and the unit type (written ()). Functions can be recursive (although not hoisted), but we pro scribe mutually recursive type declarations. For the sake of sim plicity, Swiftlet requires all named declarations (i.e., structures, properties, parameters, and local bindings) to have a unique name. This simplification does not restrict the expressiveness of our language, as name conflicts can always be eliminated via α-conversion. Further, function declarations always feature a capture list, even when it is empty. Expressions are composed out of array literals, structure instantiations, function calls, conditionals, function declarations, binding declarations, assignments, sequences, casts, values, and paths. The latter are at the heart of mutable value semantics. In broad strokes, a path denotes access to a value or part thereof. It can be the name of a binding or any expression suffixed by either a dotted accessor (e.g., e.n) or a bracketed index identifying a specific element in an array (e.g., e1[e2]). Borrowing from C parlance, path expressions starting with a name are called lvalues, as they may appear on the left hand side of an assignment. Only mutable lvalues can serve as ar

10 Named functions are declared in the body of the entry point

11 We exclude floating-point values from the formal definition.

Implementation Strategies for Mutable Value Semantics 7 guments to inout parameters. As mentioned in the previous section, immutability applies transitively, meaning that an lvalue is immutable if any component of its path is. Note: a bracketed lvalue can be mutable even when the expression of its index is immutable. Because 0 without enclosing brackets is not a path component, its immutability does affect that of x[0], which is only immutable if x is an immutable binding. The sequence operator “;” is left associative, that is a; b; c is equivalent to (a; b); c. For clarity, the scope of a declaration is introduced explicitly in the formal syntax: binding and function declarations are always trailed by another expression, which represents their scope. For instance, x in the assignment x = 2 is bound in var x : Z = 1 in (f(x); x = 2), but it is free in both x = 2; var y : Z = 1 in f(x) and var y : Z = 1 in f(y); x = 2. Scopes are used to determine the lifetime of a particular value and reclaim memory. We bring the reader’s attention to a handful of additional dif ferences between Swiftlet’s concrete and formal syntax. First, for the sake of concision, the formal syntax does not use argu ment labels in function calls or structure literals. For instance, a call f(y: &x) in the concrete syntax is written f(&x) formally. Second, the formal syntax lets bindings appear at any position in an expression. For instance, let x = let y = 1 in y in f(x) is formally valid, yet it is ill-formed in the concrete syntax. More generally, any expression can appear in a binding’s initializer, including assignments. This difference, however, does not raise the expressiveness of the 

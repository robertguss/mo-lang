---
source_url: https://doi.org/10.1145/3527313
ingested: 2026-09-12
sha256: 11d94b5e36eb6237bb5c35de6fd0d6e2f32aee83ca4fdc6b92fd4a4ebd7052e6
---
# Linear types for large-scale systems verification

# Linear types for large-scale systems verification

Proceedings of the ACM on Programming Languages. Published: 2022-04-29. 9 citations.

## Authors

- Jialin Li (University of Washington): h-index 4; 31 citations
- Andrea Lattuada (ETH Zurich): h-index 7; 229 citations
- Yi Zhou (Carnegie Mellon University): h-index 3; 115 citations
- Jonathan Cameron (Carnegie Mellon University): h-index 17; 1,120 citations
- Jon Howell (VMware Research, USA): h-index 29; 5,145 citations
- Bryan Parno (Carnegie Mellon University): h-index 39; 9,183 citations
- Chris Hawblitzel (Microsoft (United States)): h-index 28; 3,017 citations

## Topics

- Logic, programming, and type systems
- Security and Verification in Computing
- Formal Methods in Verification

## Funding

- National Science Foundation
  - Graduate Research Fellowship Program (GRFP)

---

# Linear Types for Large-Scale Systems Verification

## Abstract

Reasoning about memory aliasing and mutation in software verification is a hard problem. This is especially true for systems using SMT-based automated theorem provers. Memory reasoning in SMT verification typically requires a nontrivial amount of manual effort to specify heap invariants, as well as extensive alias reasoning from the SMT solver. In this paper, we present a hybrid approach that combines linear types with SMT-based verification for memory reasoning. We integrate linear types into Dafny, a verification language with an SMT backend, and show that the two approaches complement each other. By separating memory reasoning from verification conditions, linear types reduce the SMT solving time. At the same time, the expressiveness of SMT queries extends the flexibility of the linear type system. In particular, it allows our linear type system to easily and correctly mix linear and nonlinear data in novel ways, encapsulating linear data inside nonlinear data and vice-versa. We formalize the core of our extensions, prove soundness, and provide algorithms for linear type checking. We evaluate our approach by converting the implementation of a verified storage system (~24K lines of code and proof) written in Dafny, to use our extended Dafny. The resulting system uses linear types for 91% of the code and SMT-based heap reasoning for the remaining 9%. We show that the converted system has 28% fewer lines of proofs and 30% shorter verification time overall. We discuss the development overhead in the original system due to SMT-based heap reasoning and highlight the improved developer experience when using linear types.

## INTRODUCTION

Formal verification allows developers to prove strong functional correctness guarantees about complex systems software. This can significantly increase software reliability, minimizing the risk of runtime errors that can lead to data loss and potentially disastrous consequences. Although verifying large systems is a notoriously time-consuming task [Klein et al. 2014 ], recent SMT-based verified systems have achieved reasonable run-time performance with a degree of effort feasible for high-value systems [Hance et al. 2020a; Hawblitzel et al. 2015a] .

Unfortunately, existing SMT-based verifiers interact poorly with reasoning about mutable memory in large-scale systems. Interactive proof assistants often use separation logic [Reynolds 2002 ] to reason about memory and aliasing, but SMT solvers do not provide good support for separation logic. As a result, typical SMT-based program verifiers like Dafny [Leino 2010 ] dispatch memory reasoning to the SMT solver, forcing the SMT solver to reason about the disjointness of sets of memory locations and updates to a global heap. This approach requires the developers to establish and maintain memory invariants over all mutable objects, a burdensome task. Furthermore, overloading the SMT solver with memory reasoning leads to poor SMT performance (and hence poor interactivity) and confusing error messages when a proof fails.

Linear type systems [Wadler 1990 ] are gaining traction in practice in Rust [Klabnik et al. 2018; Matsakis and Klock 2014] as a mechanism for controlling and reasoning about aliasing. A growing body of large, performant systems built in Rust [Bhardwaj et al. 2021; Boos et al. 2020; Narayanan et al. 2020] provide evidence that linear types are practical and effective for ensuring program safety. We argue that linear types are effective for SMT-style correctness verification as well.

In our work, we show how to integrate linear types with SMT-based verification. Our approach demonstrates that linear types and SMT solving are complementary: linear types improve SMT performance in the common case where objects are not aliased, and SMT solving enables more expressive verification when aliasing is necessary. When objects are not aliased, the SMT solver can view mutable linear datatypes as immutable mathematical datatypes, speeding solver times. When aliasing is necessary, the SMT solver can precisely reason about the aliasing.

Our approach allows developers to freely mix linear and aliased styles, storing linear data inside nonlinear data and vice-versa. Programs can encapsulate nonlinear, aliased data structures inside linear data structures, using a region-based approach to modularly hide the aliased objects behind a purely linear interface. In the other direction, programs can place linear data inside nonlinear data, using the SMT solver to verify the correct usage of the linear values, avoiding the run-time safety checks needed by other linearly typed languages like Rust. Our approach also supports Rust-style lightweight borrowing of immutable references from linear data, even when the linear data is stored inside aliased, nonlinear objects. We formalize the core of our approach, prove soundness, and prove that the checking of types, linearity, and borrowing is decidable with a straightforward algorithm (Section 2).

The motivation to integrate linear memory reasoning into SMT-based verification is to reduce the cost of practical, large-scale verified development. To evaluate this goal, we introduce the linear type system into Dafny [Leino 2010], a verification language with an SMT backend, which has been used to verify a variety of high performance systems [Hance et al. 2020a; Hawblitzel et al. 2015a Hawblitzel et al. , 2014]] . Then we took one such system, VeriBetrKV 1 [Hance et al. 2020a ], a practical verified storage system (~24K lines of code and proof in the implementation layer), and converted it from vanilla Dafny into our new Linear Dafny. Because Linear Dafny supports hybrid memory reasoning, we could convert VeriBetrKV incrementally over several months, with the system remaining verified at each step throughout the process. The final result is still a hybrid, with 9% using Dafny's vanilla memory reasoning for tricky object relations, and the other 91% exploiting linear memory reasoning.

We find that the linearized VeriBetrKV has 28% fewer lines of proofs, 30% shorter verification time overall, and among slow methods, the median method's interactive verification time is cut nearly in half. We observe that debugging memory errors in linearized code is much simpler, with the linear type system identifying errors at precise lines of code with actionable error messages.

Linear Types for Large-Scale Systems Verification 69:3

The comparison indicates that reasoning about aliasing and mutation via linear types improves the developer experience and reduces development cost over an SMT-only approach. We show that by using better memory reasoning approaches, we can lower verification effort and move a step towards making full verification a realistic engineering choice for a larger set of system software.

Our main contributions are (1) The presentation of a practical design for combining SMT-based heap verification with linear types, as well as enhancements to an existing implementation thereof.

(2) The first formalization combining verification condition generation, linear types, and borrowing.

(3) A novel region-based mechanism to encapsulate nonlinear data inside linear data and vice-versa. (4) A direct comparison of how SMT-based memory reasoning and the linear-SMT hybrid approach impact the developer experience in the context of a large verified system 2 .

The rest of this paper is organized as follows: Section 2 introduces Linear Dafny and presents a detailed formalization; Section 3 compares and contrasts the development experiences of VeriBetrKV and the linearized VeriBetrKV; Section 4 discusses related work on linear type systems.

## DESIGN AND FORMALIZATION OF LINEAR DAFNY

In this section, we present our design and formalization of the Linear Dafny language 3 . We originally built Linear Dafny in support of the implementation of VeriBetrKV [Hance et al. 2020a] , and its basic features and usage are briefly mentioned in Section 5.1 of [Hance et al. 2020a ]. Here we present the complete design, including the underlying type-checking algorithm, support for algebraic datatypes, and enhancements to the implementation. We strengthen the previous Linear Dafny implementation with support for inout parameters and a library for region-based interoperation between linear and nonlinear data.

We first introduce the basic ideas of adding linearity in Dafny, following earlier work by Wadler [Wadler 1990 ], on the Cogent language [Amani et al. 2016] , and on Rust [Klabnik et al. 2018; Matsakis and Klock 2014] . We then focus on a new region-based formalism that improves the interaction of linear data and nonlinear data in Linear Dafny. Finally, we prove the soundness of the formalized system and prove the soundness and completeness of an algorithm for checking types, linearity, and borrowing in the formalized system.

Section 3 then presents a large-scale evaluation, demonstrating the application of Linear Dafny to 91% of the VeriBetrKV implementation, compared to earlier preliminary experiments converting two łleafž modules constituting 16% of the implementation [Hance et al. 2020a ].

### Basic Features of Linear Dafny

Dafny is a programming language and a verifier with both imperative programming and verification support [Leino 2010]. Dafny supports generic classes and dynamic allocation for writing imperative programs, and provides built-in specification constructs including preconditions and postconditions, mathematical functions, and ghost variables for writing formal specifications. In Dafny, developers write down specifications, proofs and methods, and then ask the verifier to check if methods meet their specifications. Behind the scenes, Dafny translates the program into an intermediate verification language Boogie [Barnett et al. 2006 ], which then generates verification conditions for the Z3 SMT (Satisfiability Modulo Theories) solver to resolve [de Moura and Bjùrner 2008] .

Linear Dafny extends the standard Dafny language with a linear type system. Linear type systems disallow the duplication and discarding of linear variables, which helps to control aliasing: by disallowing duplication, the type system can guarantee that a variable pointing to a memory cell is the only variable pointing to that memory cell. In standard Dafny, variables can be ordinary (unannotated) or ghost. We refer to łordinaryž and ghost as two distinct usages for variables. Linear Dafny extends Dafny's type system with two additional usages: linear for linear variables and shared for immutably borrowed variables. Ordinary and ghost variables can be freely duplicated, discarded, stored in datatypes, and passed in and out of functions and methods. Ordinary, linear, and shared variables are compiled to executable code, while ghost variables are erased before compilation. Linear variables can be neither duplicated nor discarded, but can be stored in linear datatypes and passed in and out of functions and methods freely. Shared variables can be duplicated and discarded, but have restricted scope. Shared variables cannot be stored in data structures, but data structures containing linear data can be borrowed so that their fields appear shared.

The left half of Figure 1 shows three standard Dafny methods, M1, M2, and M3, that manipulate arrays, where the seq is Dafny's sequence (immutable array) type and array is Dafny's mutable array type. Mutable arrays can be modified in place (M3), but require reasoning about aliasing (a1 != a2) so that the SMT solver can verify assertions like a1[5] == 100. This reasoning is done through Dafny's dynamic frames [Kassios 2006 ], in which each method that modifies the heap must provide a modifies clause that states the set of heap locations the method changes. Although the specification of non-aliasing in this example is simple (a1 != a2), more complex programs require increasingly elaborate specifications of disjointness for the programmer to write and the SMT solver to reason about.

In contrast to Dafny arrays, which are heap objects, Dafny sequences are values. Sequences are easier to reason about than arrays, but do not support in-place updates, which means that updates to sequences require copying the whole sequence at run-time (M2).

As shown in the right half of Figure 1 , Linear Dafny supports linear datatypes such as linear sequences. Linear datatypes provide both value semantics and in-place updates, achieving the best of both worlds: in M5, linearity ensures that sequences l1 and l2 do not alias and linearity allows in-place updates to the linear sequences without copying the sequence.

In addition, Linear Dafny allows temporary borrowing of linear variables in the style of Wadler's łlet!ž [Wadler 1990 ] and Rust's immutable borrowing. When calling M4, the method M5 temporarily demotes l1 from linear usage to shared usage. While l1 is shared, it can be duplicated, allowing M5 to pass l1 as an argument twice to M4. Like Rust, and unlike Wadler's łlet!ž [Wadler 1990 ] and Cogent [Amani et al. 2016] , Linear Dafny automatically infers where borrowing occurs, so no explicit programmer annotation is needed to share l1 in the call to M4. Section 2.6 describes how Linear Dafny performs this inference.

For soundness's sake, Linear Dafny must ensure that borrowing is only temporary, so that no copies of a shared reference survive after a variable becomes linear again. Otherwise, a value could be viewed as both linear and shared simultaneously, allowing a program to deallocate the value through the linear usage while still reading the value through the shared usage. Like Cogent, Linear Dafny ensures this by disallowing any shared references from being returned out of the scope of a borrow (see Section 2.2 for the precise rules). As long as they don't escape past a borrow, though, shared references can be freely passed in and out of expressions and functions. For instance, like Cogent, Linear Dafny allows functions to return shared references: The method M5 consumes its original linear parameters l1 and l2 and produces new linear values l3 and l4 (which are actually the original sequences l1 and l2, updated in place). Rather than forcing programmers to manually pass all linear values in and out of methods, Linear Dafny also supports inout method parameters, so that M5 can be more concisely written as: method M5(linear inout l1:seq<int>, linear inout l2:seq<int>) returns(x:int) requires |l1| >= 10 && |l2| >= 10 {

x := M4(l1, l1); l1 := seq_set(l1, 5, 100); l2 := seq_set(l2, 5, 200); assert l1[5] == 100; } Arguments to inout parameters can be fields of linear datatypes stored in linear variables or referenced by the inout parameters of the enclosing function. This allows mutably borrowing datatype fields so that programs can efficiently update those fields in place.

Finally, Linear Dafny supports linear algebraic datatypes, which may contain ordinary fields and linear fields. In the List datatype below, the data field is ordinary and the tail field is linear.

When a linear datatype is borrowed as shared, all of its linear fields appear as shared. This allows the while loop shown above to traverse the list without consuming it. In addition to value-based types (sequences and algebraic datatypes), Dafny supports referencebased heap objects (class objects and mutable arrays). Currently, Linear Dafny always treats reference-based heap objects as ordinary rather than shared or linear. It would be straightforward to also allow linear reference-based heap objects, but we didn't have a compelling reason to do so, since linearity already enables mutation of sequences and algebraic datatypes, making linear reference-based heap objects somewhat redundant. Instead, Linear Dafny uses reference-based heap objects for nonlinear data structures, and focuses on enabling interoperation between nonlinear reference-based heap objects and linear value-based types.

### Formalization

This section introduces the syntax and typing rules for a simple model of Linear Dafny. The goal is not to capture all the features of Linear Dafny, but instead to illustrate and clarify the key ideas in Linear Dafny and prove their soundness. We then use the formal model to extend and improve Linear Dafny by breaking Linear Dafny's monolithic heap into regions. This region-based approach yields three novel improvements, all illustrated in our formal model:

(1) Regions allow proper encapsulation of nonlinear data structures stored inside linear data structures, so that any modifications to nonlinear data stay private and are not leaked via Dafny's modifies clauses. (2) Regions enable an elegant form of borrowing for linear data stored inside nonlinear data, replacing the clumsy attribute-based mechanism described in [Hance et al. 2020a (3) Our regions take advantage of SMT solving to avoid the need for region variables, universal region quantification, and existential region quantification. Figure 2 shows the syntax of the formal model. Usages include linear, shared, and ordinary (we omit Linear Dafny's ghost usage for simplicity). Types include integers, references, regions, and linear tuples. We start by describing the basic features for integers and linear tuples, leaving regions and references for 2.4.

= 𝑖 | ℓ | null | r 𝑑 | ⟨𝑣 1 , . . . , 𝑣 𝑛 ⟩ expression 𝑒 ::= 𝑣 | 𝑥 | 𝑒 1 + 𝑒 2 | 𝑒 1 ; 𝑒 2 | let 𝑢 𝑥 = 𝑒 1 in 𝑒 2 | ⟨𝑒 1 , . . . , 𝑒 𝑛 ⟩ | 𝑒.𝑖 | let ⟨𝑥 1 , . . . , 𝑥 𝑛 ⟩ = 𝑒 1 in 𝑒 2 | new_region() | free_region(𝑒) | alloc S(𝑒 1 , . . . , 𝑒 𝑛 ) @ 𝑒 0 | read(𝑒 1 .𝑖) @ 𝑒 0 | write(𝑒 1 .𝑖 := 𝑒 2 ) @ 𝑒 0 | swap(𝑒 1 .𝑖 := 𝑒 2 ) @ 𝑒 0 location typing L ::= {ℓ 1 ↦ → S 1 , . . . , ℓ 𝑛 ↦ → S 𝑛 } region typing R ::= {r 1 ↦ → 𝑢 ls 1 , . . . , r 𝑛 ↦ → 𝑢 ls 𝑛 } variable typing X ::= {𝑥 1 ↦ → 𝑢 1 𝜏 1 , . . . , 𝑥 𝑛 ↦ → 𝑢 𝑛 𝜏 𝑛 } combined typing C ::= L; R; X

⟩ = 𝑦 in let ⟨⟩ = 𝑥 ′ in 𝑎 + 𝑎 ′ + 𝑏

The type checking rules use an environment X = { 1 ↦ → 1 1 , . . . , ↦ → } that maps variables to their types and usages. The notation X = X 1 # X 2 means that X is split into two parts, X 1 and X 2 , which share the same nonlinear mappings but contain disjoint linear mappings. With this notation, we can write simple type checking rules for integer addition and linear tuple construction (considering, for moment, only 2-tuples for simplicity):

X 1 ⊢ 𝑒 1 : ordinary int X 2 ⊢ 𝑒 2 : ordinary int X 1 # X 2 ⊢ 𝑒 1 + 𝑒 2 : ordinary int X 1 ⊢ 𝑒 1 : 𝑢 1 𝜏 1 X 2 ⊢ 𝑒 2 : 𝑢 2 𝜏 2 X 1 # X 2 ⊢ ⟨𝑒 1 , 𝑒 2 ⟩ : linear ⟨𝑢 1 𝜏 1 , 𝑢 2 𝜏 2 ⟩

When type checking ⟨, ⟩ in the example above, both X 1 and X 2 will contain the nonlinear mapping ↦ → ordinary int, but only X 1 will contain the linear mapping ↦ → linear ⟨⟩. As is standard in formal presentations of linear type systems [Wadler 1990 ], the typing rule does not directly determine how to split X into X 1 and X 2 . Section 2.6 presents a simple algorithm for deciding this split.

Formal presentations of borrowing are less common and generally either rely on Wadler's explicit let! notation [Amani et al. 2016; Wadler 1990] or are based on Rust's more complex rules, as in RustBelt [Jung et al. 2017] and Oxide [Weiss et al. 2019 ]. Here, we introduce rules for borrowing that are simpler than Rust's rules and do not rely on let!. We illustrate this approach with the rule for sequencing expressions 1 ; 2 :

𝑢 1 ≠ linear X 1 , shared(X 𝑏 ) ⊢ 𝑒 1 : 𝑢 1 𝜏 1 X 2 , linear(X 𝑏 ) ⊢ 𝑒 2 : 𝑢 2 𝜏 2 (X 1 # X 2 ), linear(X 𝑏 ) ⊢ 𝑒 1 ; 𝑒 2 : 𝑢 2 𝜏 2

The notation X = X 1 , X 2 means that X is split into two parts, X 1 and X 2 , which contain disjoint mappings, both for linear and nonlinear mappings. The notation linear(X) denotes an environment in which all usages are linear, while the notation shared(X) denotes the same environment as linear(X), except that all usages are shared. In the rule above, this has the effect of splitting out zero or more linear mappings linear(X ) from the overall environment, and then viewing them as shared mappings when checking expression 1 ś in other words, borrowing zero or more linear mappings as shared within 1 . As with the split between X 1 and X 2 , the typing rule does not directly determine which X to split out. Section 2.6's algorithm also decides this split.

To help understand the rule above, consider a slight variation of the earlier example, where we use ł;ž to discard the result of .2 + .2; rather than putting the result in a variable : . . .

let linear 𝑦 = ⟨𝑥, 𝑎⟩ in 𝑦.2 + 𝑦.2; let ⟨𝑥 ′ , 𝑎 ′ ⟩ = 𝑦 in . . .

## When we apply the typing rule for 𝑒

1 ; 𝑒 2 , we use 𝑒 1 = 𝑦.2 + 𝑦.2 and 𝑒 2 = let ⟨𝑥 ′ , 𝑎 ′ ⟩ = 𝑦 in . . . and linear(X 𝑏 ) = {𝑦 ↦ → linear 𝜏 𝑦 } and shared(X 𝑏 ) = {𝑦 ↦ → shared 𝜏 𝑦 },

where we define = ⟨linear ⟨⟩, ordinary int⟩. Because is shared in shared(X ) rather than linear, it may be duplicated in the expression .2 + .2. After the borrowing finishes, reverts to its original linear usage in the remaining expression 2 . This is safe because 1 completely evaluates to a value, which is then discarded, before 2 begins evaluation, so the program's execution never observes as both shared and linear simultaneously.

The same reasoning allows for borrowing in let expressions: Here, the result of evaluating 1 is not discarded, but the rule prohibits returning a shared result from 1 if any borrowing occurs. This restriction, which is also made by Cogent's let! expression [Amani et al. 2016] , prevents borrowed values from leaking back out through the bound variable , so that values borrowed by 1 can flow into 1 but not out. More generally, the places where borrowing occurs are barriers that block all borrowed variables from flowing out.

𝑢 1 = shared ⇒ X 𝑏 = ∅ X 1 , shared(X 𝑏 ) ⊢ 𝑒 1 : 𝑢 1 𝜏 1 X 2 , linear(X 𝑏 ), 𝑥 ↦ → 𝑢 1 𝜏 1 ⊢ 𝑒 2 : 𝑢 2 𝜏 2 (X 1 # X 2 ), linear(X 𝑏 ) ⊢ let 𝑢 1 𝑥 = 𝑒 1 in 𝑒 2 : 𝑢 2 𝜏 2 Proc. ACM Program. Lang.,

As with Wadler's original let! expression, the rule above requires that 2 consume any borrowed linear variables. At first, this may appear to disallow expressions like łlet ordinary = .2 + .2 in + 1ž that use a borrowed without consuming . However, in such cases, the borrowing simply happens in a larger scope. For instance, the borrowing of occurs in the let for rather than the let for in the following example:

. . . let ordinary 𝑏 = (let ordinary 𝑧 = 𝑦.2 + 𝑦.2 in 𝑧 + 1) in let ⟨𝑥 ′ , 𝑎 ′ ⟩ = 𝑦 in . . .

Once an expression has borrowed a linear tuple as a shared tuple, it can select fields from the tuple:

X ⊢ 𝑒 : shared ⟨𝑢 1 𝜏 1 , . . . , linear 𝜏 𝑖 , . . . , 𝑢 𝑛 𝜏 𝑛 ⟩ X ⊢ 𝑒.𝑖 : shared 𝜏 𝑖 X ⊢ 𝑒 : shared ⟨𝑢 1 𝜏 1 , . . . , ordinary 𝜏 𝑖 , . . . , 𝑢 𝑛 𝜏 𝑛 ⟩ X ⊢ 𝑒.𝑖 : ordinary 𝜏 𝑖

Note that the result of selecting a linear field from a shared tuple is itself shared.

Figure 3 shows the complete type checking rules, including rules for regions that will be described in Section 2.4. The rules include the environment X that maps variables to their types and usages, as well as environments L for references to locations and R for regions. The notation C = L; R; X represents the combined typing environment, !C selects the nonlinear mappings from C, and ¡C selects the linear mappings from C. Borrowing is allowed in three different rules: sequencing 1 ; 2 , let expressions, and tuple deconstruction. This highlights the fact that in Linear Dafny, as in Rust, borrowing is ubiquitous, rather than being restricted to a special expression like let!.

## DESIGN AND FORMALIZATION OF LINEAR DAFNY
### SMT Solving and Weakest Preconditions

Linear Dafny programs are checked with both a type checker and an SMT solver. To help demonstrate the balance and interplay between type checking and SMT solving, we include a simple SMT checking process in our formal model. In particular, we show:

(1) Since the type system handles linearity checking, the SMT solver can view linear datatypes as simple mathematical datatypes, without worrying about the linearity.

(2) The SMT solver can statically check the correct usage of linear values stored inside nonlinear objects, which Rust needs run-time checks for (Section 2.5).

(3) The SMT solver can track the relation between regions and references into regions, without needing region variables and quantification over region variables (Section 2.4). Linear Dafny uses Dafny's built-in verification condition generator to verify Linear Dafny code. To model Dafny's verification condition generator, Figure 5 defines a verification condition generator wp(, . ) that computes a weakest precondition for any expression and postcondition . The postcondition may use the variable to refer to the final value computed by . To prove that evaluates to 4, for instance, we can ask an SMT solver to prove the validity of the formula wp(, . = 4). The definition of wp(, . ) shows that wp(let ordinary = 2 in + 2, . = 4) is equal to 2 + 2 = 4, which is an easy formula for an SMT solver to prove. For convenience, some of the definitions in Figure 5 use ∀ quantifiers to introduce temporary variables; an SMT solver can easily eliminate these using Skolemization since they appear only in positive positions.

Note that wp(, . ) ignores linearity completely. Operations on linear tuples, for example, are translated directly into operations on SMT tuples, with no concerns about linearity or borrowing.

## Well-typed expression

C ⊢ 𝑒 : 𝑢 𝜏 !C, 𝑥 ↦ → 𝑢 𝜏 ⊢ 𝑥 : 𝑢 𝜏 !C ⊢ 𝑖 : ordinary int !C, ℓ ↦ → S ⊢ ℓ : ordinary ref(S) !C ⊢ null : ordinary ref(S) 𝑢 ≠ ordinary domain(𝑑) = {ℓ ∈ domain(L) | RegionOfLoc(ℓ) = r} L; R ⊢ 𝑑 : 𝑢 L; R # {r ↦ → 𝑢}; !X ⊢ r 𝑑 : 𝑢 region 𝑢 1 ≠ linear C 1 , shared(C 𝑏 ) ⊢ 𝑒 1 : 𝑢 1 𝜏 1 C 2 , linear(C 𝑏 ) ⊢ 𝑒 2 : 𝑢 2 𝜏 2 (C 1 # C 2 ), linear(C 𝑏 ) ⊢ 𝑒 1 ; 𝑒 2 : 𝑢 2 𝜏 2 𝑢 1 = shared ⇒ C 𝑏 = ∅; ∅; ∅ C 1 , shared(C 𝑏 ) ⊢ 𝑒 1 : 𝑢 1 𝜏 1 C 2 , linear(C 𝑏 ), 𝑥 ↦ → 𝑢 1 𝜏 1 ⊢ 𝑒 2 : 𝑢 2 𝜏 2 (C 1 # C 2 ), linear(C 𝑏 ) ⊢ let 𝑢 1 𝑥 = 𝑒 1 in 𝑒 2 : 𝑢 2 𝜏 2 𝑢 ≠ ordinary C 1 ⊢ 𝑒 1 : share_as(𝑢, 𝑢 1 ) 𝜏 1 . . . C 𝑛 ⊢ 𝑒 𝑛 : share_as(𝑢, 𝑢 𝑛 ) 𝜏 𝑛 C 1 # . . . # C 𝑛 ⊢ ⟨𝑒 1 , . . . , 𝑒 𝑛 ⟩ : 𝑢 ⟨𝑢 1 𝜏 1 , . . . , 𝑢 𝑛 𝜏 𝑛 ⟩ C 1 ⊢ 𝑒 1 : ordinary int C 2 ⊢ 𝑒 2 : ordinary int C 1 # C 2 ⊢ 𝑒 1 + 𝑒 2 : ordinary int C ⊢ 𝑒 : shared ⟨𝑢 1 𝜏 1 , . . . , 𝑢 𝑖 𝜏 𝑖 , . . . , 𝑢 𝑛 𝜏 𝑛 ⟩ C ⊢ 𝑒.𝑖 : share_as(shared, 𝑢 𝑖 ) 𝜏 𝑖 C 0 , shared(C 𝑏 ) ⊢ 𝑒 0 : linear ⟨𝑢 1 𝜏 1 , . . . , 𝑢 𝑛 𝜏 𝑛 ⟩ C 𝑥 , linear(C 𝑏 ), 𝑥 1 ↦ → 𝑢 1 𝜏 1 , . . . , 𝑥 𝑛 ↦ → 𝑢 𝑛 𝜏 𝑛 ⊢ 𝑒 𝑥 : 𝑢 𝑥 𝜏 𝑥 (C 0 # C 𝑥 ), linear(C 𝑏 ) ⊢ let ⟨𝑥 1 , . . . , 𝑥 𝑛 ⟩ = 𝑒 0 in 𝑒 𝑥 : 𝑢 𝑥 𝜏 𝑥 !C ⊢ new_region() : linear region C ⊢ 𝑒 : linear region C ⊢ free_region(𝑒) : ordinary int StructType(S) = (𝑢 1 𝜏 1 , . . . , 𝑢 𝑛 𝜏 𝑛 ) C 0 ⊢ 𝑒 0 : linear region C 1 ⊢ 𝑒 1 : 𝑢 1 𝜏 1 . . . C 𝑛 ⊢ 𝑒 𝑛 : 𝑢 𝑛 𝜏 𝑛 C 0 # C 1 # . . . # C 𝑛 ⊢ alloc S(𝑒 1 , ..., 𝑒 𝑛 ) @ 𝑒 0 : linear ⟨ordinary ref(S), linear region⟩ StructType(S) = (𝑢 1 𝜏 1 , . . . , 𝑢 𝑖 𝜏 𝑖 , . . . , 𝑢 𝑛 𝜏 𝑛 ) C 0 ⊢ 𝑒 0 : shared region C 1 ⊢ 𝑒 1 : ordinary ref(S) C 0 # C 1 ⊢ read(𝑒 1 .𝑖) @ 𝑒 0 : share_as(shared, 𝑢 𝑖 ) 𝜏 𝑖 StructType(S) = (𝑢 1 𝜏 1 , . . . , ordinary 𝜏 𝑖 , . . . , 𝑢 𝑛 𝜏 𝑛 ) C 0 ⊢ 𝑒 0 : linear region C 1 ⊢ 𝑒 1 : ordinary ref(S) C 2 ⊢ 𝑒 2 : ordinary 𝜏 𝑖 C 0 # C 1 # C 2 ⊢ write(𝑒 1 .𝑖 := 𝑒 2 ) @ 𝑒 0 : linear region StructType(S) = (𝑢 1 𝜏 1 , . . . , linear 𝜏 𝑖 , . . . , 𝑢 𝑛 𝜏 𝑛 ) C 0 ⊢ 𝑒 0 : linear region C 1 ⊢ 𝑒 1 : ordinary ref(S) C 2 ⊢ 𝑒 2 : linear 𝜏 𝑖 C 0 # C 1 # C 2 ⊢ swap(𝑒 1 .𝑖 := 𝑒 2 ) @ 𝑒 0 : linear ⟨linear 𝜏 𝑖 , linear region⟩

Well-typed struct instance C ⊢ : S containing ls and region data: (L 1 ; R 1 ; X 1 ), (L 2 ; R 2 ; X 2 ) = L 1 , L 2 ; R 1 , R 2 ; X 1 , X 2 where ł, ž splits into pieces with disjoint domains.

L; R ⊢ 𝑑 : 𝑢 ls StructType(S) = (𝑢 1 𝜏 1 , . . . , 𝑢 𝑛 𝜏 𝑛 ) C 1 ⊢ 𝑣 1 : share_as(𝑢 ls , 𝑢 1 ) 𝜏 1 . . . C 𝑛 ⊢ 𝑣 𝑛 : share_as(𝑢 ls , 𝑢 𝑛 ) 𝜏 𝑛 C 1 # . . . # C 𝑛 ⊢ S(𝑣 1 , ..., 𝑣 𝑛 ) : S containing 𝑢 ls L; R 1 ; ∅ ⊢ 𝑠 1 : L(ℓ 1 ) 𝑢 ls . . . L; R 𝑛 ; ∅ ⊢ 𝑠 𝑛 : L(ℓ 𝑛 ) 𝑢 ls L; R 1 # . . . # R 𝑛 ⊢ {ℓ 1 ↦ → 𝑠 1 , . . . , ℓ 𝑛 ↦ → 𝑠 𝑛 } : 𝑢 ls

(L; R 1 ; X 1 ) # (L; R 2 ; X 2 ) = L; R 1 # R 2 ; X 1 # X 2 where: R = R 1 # R 2 iff !R =!R 1 =!R 2 and ¡R = ¡R 1 , ¡R 2 X = X 1 # X 2 iff !X =!X 1 =!X 2 and ¡X = ¡X 1 , ¡X 2 C = L; R; X where C 1 # C 2 # . . . # C 𝑛 denotes C 1 # (C 2 # (. . . # C 𝑛 ) . . .) for 𝑛 ≥ 1 and !C for 𝑛 = 0 !(L; R; X) = L; !R; !X and ¡(L; R; X) = ∅; ¡R; ¡X where: !R = {r ↦ → 𝑢 ∈ R | 𝑢 ≠ linear} ¡R = {r ↦ → 𝑢 ∈ R | 𝑢 = linear} !X = {𝑥 ↦ → 𝑢 𝜏 ∈ X | 𝑢 ≠ linear} ¡X = {𝑥 ↦ → 𝑢 𝜏 ∈ X | 𝑢 = linear}

linear(L; R; X) = (∅; linear(R); linear(X)) and shared(L; R; X) = (∅; shared(R); shared(X)) where linear(. . .) and shared(. . .) replace usages with linear and shared respectively: This helps to keep the verification condition formulas small and simple, which in turn helps to keep the SMT validity checking fast and predictable.

linear(R) = {r ↦ → linear | r ↦ → 𝑢 ∈ R} shared(R) = {r ↦ → shared | r ↦ → 𝑢 ∈ R} linear(X) = {𝑥 ↦ → linear 𝜏 | 𝑥 ↦ → 𝑢 𝜏 ∈ X} shared(X) = {𝑥 ↦ → shared 𝜏 | 𝑥 ↦ → 𝑢 𝜏 ∈ X} share_as(shared, linear) = shared and share_as(𝑢 1 , 𝑢 2 ) = 𝑢 2 otherwise.

## DESIGN AND FORMALIZATION OF LINEAR DAFNY
### Regions, Part 1: Nonlinear Data Inside Linear Data

Linear typing ma

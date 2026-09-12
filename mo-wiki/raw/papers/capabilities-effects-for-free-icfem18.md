---
source_url: https://potanin.github.io/files/CraigPotaninGrovesAldrichICFEM2018.pdf
ingested: 2026-09-12
sha256: e30a9adf408b65c05f8da5418613f8033c8c5f71ca6a272c64fcad0f5048c8a8
---
# Capabilities: Effects for Free

## Capabilities: Effects for Free

Aaron Craig 1, Alex Potanin 1[0000− 0002− 4242− 2725], Lindsay Groves 1, and Jonathan Aldrich 2[0000− 0003− 0631− 5591]

1 School of Engineering and Computer Science, Victoria University of Wellington, NZ { aaron.craig,alex,lindsay} @ecs.vuw.ac.nz 2 School of Computer Science, Carnegie Mellon University jonathan.aldrich@cs.cmu.edu

Abstract. Object capabilities are increasingly used to reason informally about the properties of secure systems. But can capabilities also aid in formal reason ing? To answer this question, we examine a calculus that uses effects to capture resource use and extend it to support capability-based reasoning. We demonstrate that capabilities provide a way to reason about effects: we can bound the effects of an expression based on the capabilities to which it has access. This reason ing is “free” in that it relies only on type-checking (not effect-checking), does not require the programmer to add effect annotations within the expression, and does not require the expression to be analysed for its effects. Our result sheds light on the essence of what capabilities provide and suggests ways of integrating lightweight capability-based reasoning into languages.

### 1 Introduction

Capabilities have been recently gaining attention as a promising mechanism for con trolling access to resources, particularly in object-oriented languages and systems [17, 6, 5, 4]. A capability is an unforgeable token that can be used by its bearer to perform some operation on a resource [3]. In a capability-safe language, all resources must be accessed through object capabilities, and a resource-access capability must be obtained from an object that already has it: “only connectivity begets connectivity” [17]. For ex ample, a logger component that provides a logging service would need to be initialised with an object capability providing the ability to append to the log file. Capability-safe languages prohibit the ambient authority [18] that is present in non capability-safe languages. An implementation of a logger in Java, for example, does not need to be initialised with a log file capability, as it can simply import the appro priate file-access library and open the log file for appending by itself. But critically, a malicious implementation could also delete the log, read from another file, or exfiltrate logging information over the network. Other mechanisms such as sandboxing can be used to limit the damage of such malicious components, but recent work has found that Java’s sandbox (for instance) is difficult to use and therefore often misused [2, 12]. In practice, reasoning about resource use in capability-based systems is mostly done informally. But if capabilities are useful for informal reasoning, shouldn’t they also aid in formal reasoning? Recent work by Drossopoulou et. al. [6] sheds some light on this question by presenting a logic that formalizes capability-based reasoning about trust

2 A. Craig et al.

between objects. Two other trains of work, rather than formalise capability-based rea soning itself, reason about how capabilities may be used: Dimoulas et al. [5] developed a formalism for reasoning about which components may use a capability and which may influence (perhaps indirectly) the use of a capability, while Devriese et al. [4] for mulate an effect parametricity theorem that limits the effects of an object based on the capabilities it possesses, and then use logical relations to reason about capability use in higher-order settings. Overall, this prior work presents new formal systems for reason ing about capability use, or reasoning about new properties using capabilities. We are interested in a different question: can capabilities be used to enhance formal reasoning that is currently done without relying on capabilities? In other words, what value do capabilities add to existing formal reasoning approaches? To answer this question, we decided to pick a simple and practical formal reasoning system, and see if capability-based reasoning could help. A natural choice for our inves tigation is effect systems [19]. Effect systems are a relatively simple formal reasoning approach, which augment type systems with the ability to reason about dynamic effects — and keeping things simple will help to highlight the difference made by capabilities. Effects also have an intuitive link to capabilities: in a system that uses capabilities to protect resources, an expression can only have an effect on a resource if it is given a capability to do so. One challenge to the wider adoption of effect systems is their annotation over head [20]. For example, Java’s checked exception system, which is a kind of effect system, is often criticised for being cumbersome [8]. While effect inference can be used to reduce the annotations required [10], understanding error messages that arise through effect inference requires a detailed understanding of the internal structure of the code, not just its interface. Capabilities are a promising alternative for reducing the overhead of effect annotations, as suggested by the following example:

1 import log : String -> Unit with effect File.write 
2 e 

Fig. 1. Declaring an effect Our examples are written in a capability-safe language supporting first-class, object like modules, similar to Wyvern [15], in which expressions declare what capabilities they need to execute. In this case, an expression e must be passed a function of type String → Unit, 3 which incurs no more than the effect File.write when invoked. This function is bound to the name log inside e. What can we say about the effects that evaluating e will have on resources, such as the file system or network? Because we are in a capability-safe language, e has no ambient authority, so the only way it could have any effects is via the log function given to it. Since the log function is annotated as having no more than the File.write effect, this is an upper-bound on the effects of e. Note we only required that e obeys the rules of capability safety. We did not require it to have effect annotations, and we didn’t analyse its structure, as an effect inference would. Also note that e might be arbitrarily large, perhaps consisting of an entire program we have downloaded from a source we trust enough to write to a log, but not enough to access any other resources. Thus in this 3 Unit is a singleton type, like void in C and Java.

Capabilities: Effects for Free 3

scenario, capabilities can be used to reason “for free” about the effects of a large body of code (e), based on a few annotations on the components it imports (log). This example illustrates the central intuition of this paper: in a capability-safe set ting, the effects of an unannotated expression can be bounded by the effects latent in the variables that are in scope. In the remainder of this paper, we formalise these ideas in a capability calculus (CC; section 2). Along the way we must generalise this intuition: what if log takes a higher-order argument? If e evaluates, not to unit, but to a function, what can we say about its effects? We then show how CC can model practical situations by encoding a range of Wyvern-like programs section 3). A more thorough discussion, including a proof of soundness is given in an accompanying technical report [1].

### 2 Capability Calculus (CC)

While the current resurgence of interest in capabilities is primarily focused on object oriented languages, for simplicity our formal definitions build on a typed lambda calcu lus with a simple notion of capabilities and their operations. CC permits the nesting of unannotated code inside annotated code in a controlled, capability-safe manner using the import form from Figure 1. This allows us to reason about unannotated code by inspecting what capabilities are passed into it from its unannotated surroundings. Allowing effect-annotated and unannotated code to be mixed helps reduce the cog nitive overhead on developers, allowing them to prototype in the unannotated sublan guage and incrementally add annotations as they are needed. Reasoning about unanno tated code is difficult in general. Figure 2 demonstrates why: apply takes a function f as input and executes it, but the effects of f depend on its implementation. Without more information, there is no way to know what effects might be incurred by apply.

1 def apply(f: Unit → Unit): 
2 f() 

Fig. 2. What effects can apply incur?

Consider another scenario, where a developer must decide whether or not to use the logger functor defined in Figure 3. This functor takes two capabilities as input, File and Socket. 4 It instantiates an object-like module that has a single, unannotated log method with access to these capabilities. The type of this object-like module is Logger, which is assumed to be defined elsewhere.

1 module def logger(f:{File},s:{Socket}):Logger 
2 def log(x: Unit): Unit 
3 ... 
Fig. 3. In a capability-safe setting, logger can only exercise authority over the File and Socket 
capabilities given to it. 

4 Note that the resource literal is File, while the type of the resource literal is { File} .

4 A. Craig et al.

How can we determine what effects will be incurred if Logger.log is invoked? One approach is to manually 5 examine its source code, but this is tedious and error-prone. In many real-world situations, the source code may be obfuscated or unavailable. A capability-based argument can do better, since a Logger can only exercise the authority it is explicitly given. In this case, the logger functor must be given File and Socket, so an upper bound on the effects of the Logger it instantiates will be the set of all op erations on those resources, { File.∗ , Socket.∗} . Knowing the Logger could perform arbitrary reads and writes to File, or communicate with Socket, the developer decides this implementation cannot be trusted and does not use it. To model this situation in CC, we add a new import expression that selects what authority εs the unannotated code may exercise. In the above example, the expected least authority of Logger is { File.append} , so that is what the corresponding import would select. The type system can then check whether the capabilities being passed into the unannotated code exceed εs. If it accepts, then εs is a safe upper bound on the effects of the unannotated code. This is the key result: when unannotated code is nested inside annotated code, capability-safety enables us to make a safe inference about its effects by examining what capabilities are being passed in by the annotated code.

2.1 Grammar (CC) The grammar of CC has rules for annotated code and analogous rules for unannotated code. To distinguish the two, we put a hat above annotated types, expressions, and contexts. eˆ, τˆ, and Γˆ are annotated, while e, τ , and Γ are unannotated. The rules for unannotated programs and their types are given in Figure 4. Unannotated types τ are built using → and sets of resources { r¯} . An unannotated context Γ maps variables to unannotated types. The syntax for invoking an operation on a resource is e.π. Resource literals and operations are drawn from fixed sets R (containing, e.g. File, Socket) and Π (containing, e.g. write, read).

e ::= exprs : | x variable | v value | e e application | e.π operation v ::= values : | r resource literal | λx : τ.e abstraction

τ ::= types : 
| { r¯} resource set 
| τ → τ function 
Γ ::= type ctx : 
| ∅ empty ctx 
| Γ, x : τ binding 
ε ::= effects : 
| { r.π} effect set 

Fig. 4. Unannotated programs and types in CC. Because our focus is on tracking what effects happen, i.e. whether particular op erations are invoked on particular resources, we make the following simplifying as sumptions: first, any operation may be called on any resource literal; and second, all operations take no inputs and return unit. 5 or automatically—but if the automation produces an unexpected result we must fall back to manual reasoning to understand why.

Capabilities: Effects for Free 5 eˆ ::= labelled exprs : | x variable | v value ˆ | eˆ e application ˆ | e.π operation ˆ | import(εs) x = ˆe in e import vˆ ::= labelled values : | r resource literal | λx : ˆτ.e abstraction ˆ

τˆ ::= annotated types : 
| { r¯} resource set 
| τˆ → ε τ function ˆ 
Γˆ ::= annotated type ctx : 
| ∅ empty ctx. 
| Γ , x ˆ : ˆτ binding 
ε ::= effects : 
| { r.π} effect set 

Fig. 5. Annotated programs and types in CC. Rules for annotated programs and their types are shown in Figure 5. The first main difference is that the → ε type constructor has a subscript ε, which is a set of effects that functions of that type may incur. The other main difference is the new expres sion form, import(εs) x = ˆe in e, where e is some unannotated code and eˆ is a capability being passed to it; we call eˆ an import. For simplicity, we assume there is only ever one import. Note the definition not only allows resource literals to be imported, but also effectful functions. Inside e, eˆ is bound to the variable x. εs is the maximum authority that e is allowed to exercise (its “selected authority”). For example, suppose an unannotated Logger, which requires File, is expected to only append to a file, but has an implementation which writes. This would be the expression import(File.append) x = File in λy : Unit. x.write. The import expression is the only way to mix annotated and unannotated code, because it is the only situation in which we can say something interesting about the effects of unannotated code. For the rest of our discussion of CC, we will only be interested in unannotated code when it is encapsulated by an import expression. Capability safety prohibits ambient authority. CC meets this requirement by forbid ding the use of resource literals directly inside an import expression (though they can still be passed in as a capability via the binding variable x). We could have enforced this syntactically, but we choose to do it using the typing rule for import in section 2.3.

2.2 Semantics (CC) The rules for CC are natural extensions of the simply-typed lambda calculus, so for brevity we only give the rules for import (see Figure 6). Reductions are defined on annotated expressions, using the notation eˆ −→ eˆ0| ε0, which means that eˆ is reduced to eˆ0 in a single step, incurring the set of effects ε0. To execute the unannotated code inside an import expression, we recursively annotate its components with the selected authority εs. While it is meaningful to execute unannotated code, we only care about it inside import expressions, so do not bother to give rules for this. E-IMPORT1 reduces the capability being imported. When it has been reduced to a value vˆ, E-IMPORT2 annotates e with the selected authority ε — this is annot(e, ε) — and substitutes the import vˆ for its name x in e — this is [ˆv/x]annot(e, ε). annot(e, ε) is the expression obtained by recursively annotating the parts of e with the set of effects ε. A definition is given in Figure 7, with versions defined on expres sions and types. Later we will need to annotate contexts, so the definition is given here.

6 A. Craig et al. eˆ −→ eˆ | ε

eˆ −→ eˆ0| ε0 import(εs) x = ˆe in e −→ import(εs) x = ˆe0 in e | ε0 (E-IMPORT1)

import(εs) x = ˆv in e −→ [ˆv/x]annot(e, εs) | ∅ (E-IMPORT2)

Fig. 6. New single-step reductions in CC. Note that annot operates on a purely syntatic level. Nothing prevents us from annotat ing a program with something unsafe, so any use of annot must be justified.

annot :: e × ε → eˆ annot(r, ) = r annot(λx : τ1.e, ε) = λx : annot(τ1, ε).annot(e, ε) annot(e1 e2, ε) = annot(e1, ε) annot(e2, ε) annot(e1.π, ε) = annot(e1, ε).π annot :: τ × ε → τˆ annot({ r¯} , ) = { r¯}annot(τ1 → τ2, ε) = annot(τ1, ε) → ε annot(τ2, ε). annot :: Γ × ε →

Γˆ

annot(∅, ) = ∅ annot(Γ, x : τ, ε) = annot(Γ, ε), x : annot(τ, ε)

Fig. 7. Definition of annot.

2.3 Static Rules (CC) Terms can be annotated or unannotated, so we need to be able to recognise when either is well-typed. We do not reason about the effects of unannotated code directly, so judge ments involving them only ascribe a type to an expression, with the form Γ ` e : τ . Subtyping judgements have the form τ <: τ . Because these rules are essentially those of the simply-typed lambda calculus, we do not list them here. Judgements involving annotated terms have the form Γˆ ` eˆ : ˆτ with ε, meaning that when eˆ is evaluated, it reduces to a value of type τˆ, incurring no more than the effects in ε. Most of the rules are analogous to those of the simply-typed lambda cal culus; these ones are given in Figure 8. Note that the rule for typing an operation call, ε-OPERCALL, types the expression as Unit, following our simplifying assumption that all operations return Unit. There is one rule left, for typing import. Since it is a complicated rule, we will start with a simplified (but incorrect) version, and spend the rest of the section building up to the final version. To begin, typing import(εs) x = ˆe in e in a context Γˆ requires us to know that eˆ is well-typed, so we add the premise Γˆ ` eˆ : ˆτ with ε1. e is only allowed to use what authority has been explicitly given to it (i.e. the capability eˆ, bound to x). To ensure this, we require that e can be typechecked using only one binding, x : ˆτ , which binds x to the type of the capability being imported. Typing e in this restricted environment means it cannot use any other capabilities, thus prohibiting the exercise of ambient authority. There is a problem though: e is unannotated, while τˆ is annotated, and there is no rule for typechecking unannotated code in an annotated context. To get around this, we

Capabilities: Effects for Free 7

Γ ` e : τ with ε Γ, x : τ ` x : τ with ∅ (ε-VAR) Γ, r : { r} ` r : { r} with ∅ (ε-RESOURCE)

Γ, x : τ2 ` e : τ3 with ε3 Γ ` λx : τ2.e : τ2 → ε3 τ3 with ∅ (ε-ABS)

Γ ` e1 : τ2 → ε τ3 with ε1 Γ ` e2 : τ2 with ε2 Γ ` e1 e2 : τ3 with ε1 ∪ ε2 ∪ ε (ε-APP)

Γ ` e : { r¯} Γ ` e.π : Unit with { r.π¯ } (ε-OPERCALL)

Γ ` e : τ with ε 
τ <: τ0 ε ⊆ ε0 
Γ ` e : τ0 with ε0 (ε-SUBSUME) 

Γ ` e : τ with ε

τ01 <: τ1 τ2 <: τ02 ε ⊆ ε0 τ1 → ε τ2 <: τ01 → ε0 τ02 (S-ARROW) r ∈ r1 =⇒ r ∈ r2 { r¯1} <: { r¯2}

(S-RESOURCE) Fig. 8. Type-and-effect and subtyping judgements in CC. define a function erase in Figure 9, which removes the annotations from a type. We can then add x : erase(ˆτ ) ` e : τ as a premise.

erase :: ˆτ → τ erase({ r¯} ) = { r¯}erase(ˆτ1 → ε τˆ2) = erase(ˆτ1) → erase(ˆτ2) Fig. 9. Definition of erase. The first version of ε-IMPORT is given in Figure 10. Since import(εs) x = ˆv in e reduces to [ˆv/x]annot(e, εs) by E-IMPORT2, its ascribed type is annot(τ, ε), which is the type of the unannotated code e, annotated with its selected authority εs. The effects of reducing the import are ε1 ∪ εs — the former happens when the imported capability is reduced to a value, while the latter happens when the body of the import expression is annotated and executed.

Γˆ ` eˆ : ˆτ with ε1 x : erase(ˆτ ) ` e : τ

Γˆ ` import(εs) x = ˆe in e : annot(τ, εs) with εs ∪ ε1

(ε-IMPORT1-BAD) Fig. 10. A first (incorrect) rule for type-and-effect checking import expressions. This first rule is incomplete, since any capability can be passed to the unannotated code e, even if it has effects that weren’t declared in εs. To avoid this, we define a func tion effects, which collects the set of effects that an (annotated) type captures. For ex ample, { File} captures every operation on File, so effects({ File} ) = { File.∗} . A first (but not yet correct) definition of this is given in Figure 11. We then add the premise effects(ˆτ ) ⊆ εs, which restricts imported capabilities to only those with effects selected in εs. The updated rule for typing import is given in Figure 12.

8 A. Craig et al. effects :: ˆτ → ε effects({ r¯} ) = { r.π | r ∈ r, π ¯ ∈ Π}effects(ˆτ1 → ε τˆ2) = effects(ˆτ1) ∪ ε ∪ effects(ˆτ2)

Fig. 11. A first (incorrect) definition of effects.

Γˆ ` eˆ : ˆτ with ε1 x : erase(ˆτ ) ` e : τ effects(ˆτ ) ⊆ εs Γˆ ` import(εs) x = ˆe in e : annot(τ, εs) with ε ∪ ε1

(ε-IMPORT2-BAD) Fig. 12. A second (still incorrect) rule for type-and-effect checking import expressions. There are still issues with this second rule, as the annotations on one import can be broken by another import. To illustrate, consider Figure 13 where two 6 capabilities are imported. This program imports a function go which, when given a Unit →∅ Unit function with no effects, will execute it. The other import is File. The unannotated code creates a Unit → Unit function which writes to File and passes it to go, which subsequently incurs File.write.

1 import({File.*}) 
2 go = λx: Unit → ∅ Unit. x unit 
3 f = File 
4 in 
5 go (λy: Unit. f.write) 
Fig. 13. Permitting multiple imports will break ε-IMPORT2. 
In the world of annotated code, it is not possible to pass a file-writing function to 
go, but because the judgement x : erase(ˆτ ) ` e : τ discards the annotations on go, and 
since the file-writing function has type unit → unit, the unannotated world accepts it. 
Although the unannotated code is allowed to incur this effect, since its selected authority 
is { File.∗} , this nonetheless violates the type signature of go. We want to prevent this. 
If go had the type Unit 
→{ File.write} Unit, Figure 13 would be safely rejected. 
However, a modified program where a file-reading function is passed to go would have 
the same issue. go is only safe when it expects every effect that the unannotated code 
might pass to it. To ensure this is the case, we shall require imported capabilities to 
have the authority to incur every effect in εs. To achieve greater control in how we 
say this, we split the definitions of effects into two separate functions, effects and 
ho-effects. The latter is for higher-order effects, which are those effects not captured 
directly in the function body, but rather are possible because of what is passed into 
the function as an argument. If values of τˆ possess a capability that can be used to 
incur the effect r.π, then r.π ∈ effects(ˆτ ). If values of τˆ can incur r.π, but need 
to be given the capability (as a function argument) by someone else to do so, then 
r.π ∈ ho-effects(ˆτ ). Definitions are given in Figure 14. 
Both effects and ho-effects are mutually recursive, with base cases for resource 
types. Any effect can be directly incurred by a resource on itself, hence effects({ r¯} ) = 
{ r.π | r ∈ r, π ¯ ∈ Π} . A resource cannot be used to indirectly invoke some other effect, 
so ho-effects({ r¯} ) = ∅. The mutual recursion echoes the subtyping rule for func 
tions: recall that functions are contravariant in their input type and covariant in their 
6 Our formalisation only permits a single capability to be imported, but this discussion leads to 
a generalisation needed for the rules to be safe when multiple capabilities can be imported. In 
any case, importing multiple capabilities can be handled with an encoding of pairs. 

Capabilities: Effects for Free 9 effects :: ˆτ → ε effects({ r¯} ) = { r.π | r ∈ r, π ¯ ∈ Π}effects(ˆτ1 → ε τˆ2) = ho-effects(ˆτ1) ∪ ε ∪ effects(ˆτ2) ho-effects :: ˆτ → ε ho-effects({ r¯} ) = ∅ ho-effects(ˆτ1 → ε τˆ2) = effects(ˆτ1) ∪ ho-effects(ˆτ2) Fig. 14. Effect functions (corrected). output; likewise, both functions recurse on the input-type using the other function, and recurse on the output-type using the same function. In light of these new definitions, we still require effects(ˆτ ) ⊆ εs — unanno tated code must select any effect its capabilities can incur — but we add a new premise εs ⊆ ho-effects(ˆτ ), which requires any higher-order effect of the imported capabil ities to be declared in εs. Put another way, the imported capabilities must be expect ing every effect they could be given by the unannotated code (which is at most εs). The counterexample from Figure 13 is now rejected, because ho-effects((Unit →∅ Unit) →∅ Unit) = ∅, but effects(File) = { File.∗} 6⊆ ∅. This is still not sufficient! Consider εs ⊆ ho-effects(ˆτ1 → ε0 τˆ2). Expanding the definition of ho-effects, this is the same as εs ⊆ effects(ˆτ1) ∪ ho-effects(ˆτ2). Let r.π ∈ εs and suppose r.π ∈ effects(ˆτ1), but r.π /∈ ho-effects(ˆτ2). Then εs ⊆ effects(ˆτ1) ∪ ho-effects(ˆτ2) is still true, but τˆ2 is not expecting r.π. If τˆ2 is a function, unannotated code could violate its annotations by passing it a capability for r.π, even though r.π is not a higher-order effect of τˆ2. The cause of this issue is that ⊆ does not distribute over ∪ . We want a relation like εs ⊆ effects(ˆτ1)∪ ho-effects(ˆτ2), which also implies εs ⊆ effects(ˆτ1) and εs ⊆ effects(ˆτ2). Figure 15 defines this: safe is a distributive version of εs ⊆ effects(ˆτ ) and ho-safe is a distributive version of εs ⊆ ho-effects(ˆτ ). An amended version of ε-IMPORT is given in Figure 16, with a new premise ho-safe(ˆτ, εs), capturing the notion that imported capabilities must be expecting the effects they could be passed by the unannotated code (which is at most εs).

safe(ˆτ, ε) safe({ r¯} , ε) (SAFE-RESOURCE) ε ⊆ ε0 ho-safe(ˆτ1, ε) safe(ˆτ2, ε) safe(ˆτ1 → ε0 τˆ2, ε) (SAFE-ARROW)

ho-safe(ˆτ, ε) ho-safe({ r¯} , ε) (HOSAFE-RESOURCE) safe(ˆτ1, ε) ho-safe(ˆτ2, ε) ho-safe(ˆτ1 → ε0 τˆ2, ε) (HOSAFE-ARROW) Fig. 15. Safety judgements in CC. The premises so far restrict what authority can be selected by unannotated code, but consider the example eˆ = import(∅) x = unit in λf : File. f.write. The unannotated code selects no capabilities and returns a function which takes File and incurs File.write. This satisfies the premises in ε-IMPORT3, but its type would be the pure function { File} →∅ Unit.

10 A. Craig et al.

Γˆ ` eˆ : ˆτ with ε1 effects(ˆτ ) ⊆ εs ho-safe(ˆτ, εs) x : erase(ˆτ ) ` e : τ

Γˆ ` import(εs) x = ˆe in e : annot(τ, εs) with ε ∪ ε1

(ε-IMPORT3-BAD) Fig. 16. A third (still incorrect) rule for type-and-effect checking import expressions. Speaking more generally, suppose the unannotated code evaluates to a function of type f, which is annotated to annot(f, εs). Suppose annot(f, εs) is invoked at a later point, back in the annotated world, incurring r.π. What is the source of r.π? If r.π was selected by the import expression surrounding f, it is safe for annot(f, εs) to incur this effect. Otherwise, annot(f, εs) may have been passed, as an argument, a capability to do r.π, in which case r.π is a higher-order effect of annot(f, εs). If the argument is a function, then r.π ∈ εs by the soundness of our calculus. But if the argument is a resource literal r, then annot(f, εs) could exercise r.π without declaring it in εs — this we do not yet account for. To make εs contain every effect captured by resources passed into annot(f, εs) as arguments, we inspect f for resource types. For example, if the unannotated code evaluates to a function of type { File} → Unit, we need { File.∗} ∈ εs. To do this, we add a new premise ho-effects(annot(τ, ∅)) ⊆ εs. Because ho-effects is only defined on annotated types, we first annotate τ with ∅, and since we are only inspecting the resources passed into f as arguments, our choice of annotation doesn’t matter. Now we can handle the example from before. The unannotated code types via the judgement x : Unit ` λf : { File} . f.write : { File} → Unit. Its higher-order effects are ho-effects(annot({ File} → Unit, ∅)) = { File.∗} , but { File.∗} 6⊆∅, so the example is safely rejected. The final version of ε-IMPORT is given in Figure 17. With it, we can now model the example from the beginning of this section, where the Logger selects the File capabil ity and exposes an unannotated function log with type Unit → Unit and implementa tion e. The expected least authority of Logger is { File.append} , so its corresponding import expression would be import(File.append) f = File in λx : Unit. e. The imported capability is f = File, which has type { File} , and effects({ File} ) = { File.∗} 6⊆ { File.append} , so this example safely rejects: Logger.log has authority to do anything with File, and its implementation e might be violating its stipulated least authority { File.append} .

effects(ˆτ ) ∪ ho-effects(annot(τ, ∅)) ⊆ εs

Γˆ ` eˆ : ˆτ with ε1 ho-safe(ˆτ, εs) x : erase(ˆτ ) ` e : τ Γˆ ` import(εs) x = ˆe in e : annot(τ, εs) with εs ∪ ε1

(ε-IMPORT)

Fig. 17. The final rule for typing imports.

### 3 Applications

In this section, we examine a number of scenarios to show how capabilities can help developers reason about the effects and behaviour of code. In each story we will discuss some Wyvern code before translating it to CC and explaining how its rules apply. By

Capabilities: Effects for Free 11

doing this, we hope to convince the reader of the benefits of capability-based reasoning, and that CC captures the intuitive properties of capability-safe languages like Wyvern.

3.1 Unannotated Client A logger module, when given File, exposes a log function which incurs the effect File.append. The client module, possessing the logger module, exposes an unan notated function run. While logger has been annotated, client has not. If client.run is executed, what effects might it have? Code for this example is given below.

1 module def logger(f: {File}):Logger 
2 def log(): Unit with {File.append} = 
3 f.append(‘‘message logged’’) 
1 module def client(logger: Logger) 
2 def run(): Unit = 
3 logger.log() 
1 require File 
2 instantiate logger(File) 
3 instantiate client(logger) 
4 client.run() 

A translation into CC is given below. Lines 1-3 and 5-8 define MakeLogger and MakeClient, which instantiate the logger and client modules respectively (rep resented as functions). Lines 10-14 define MakeMain, which returns a function which, when executed, instantiates all other modules and invokes the code in the body of main. Program execution begins on line 16, where main is given the initial capabilities (just File in this case).

1 let MakeLogger = 
2 (λf: File. 
3 λx: Unit. f.append) in 
4 

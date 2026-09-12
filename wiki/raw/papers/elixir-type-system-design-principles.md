---
source_url: https://www.irif.fr/~gc/papers/elixir-type-design.pdf
ingested: 2026-09-12
sha256: cb5d2ef12bcbb979e407f9a6453c6178967f9df7e7dbaa86a5ffe3b7545d180a
---
# The Design Principles of the Elixir Type System

The Design Principles of the Elixir Type System Giuseppe Castagnaa, Guillaume Duboca,b, and José Valimc

a IRIF, Université Paris Cité and CNRS, France 
b Remote Technology, France 
c Dashbit, Poland 
Abstract Elixir is a dynamically-typed functional language running on the Erlang Virtual Machine, designed 
for building scalable and maintainable applications. Its characteristics have earned it a surging adoption by 
hundreds of industrial actors and tens of thousands of developers. Static typing seems nowadays to be the most 
important request coming from the Elixir community. We present a gradual type system we plan to include in 
the Elixir compiler, outline its characteristics and design principles, and show by some short examples how to 
use it in practice. 
Developing a static type system suitable for Erlang’s family of languages has been an open research problem 
for almost two decades. Our system transposes to this family of languages a polymorphic type system with 
set-theoretic types and semantic subtyping. To do that, we had to improve and extend both semantic subtyping 
and the typing techniques thereof, to account for several characteristics of these languages—and of Elixir in 
particular—such as the arity of functions, the use of guards, a uniform treatment of records and dictionaries, 
the need for a new sound gradual typing discipline that does not rely on the insertion at compile time of 
specific run-time type-tests but, rather, takes into account both the type tests performed by the virtual machine 
and those explicitly added by the programmer. 
The system presented here is “gradually” being implemented and integrated in Elixir, but a prototype 
implementation is already available. 
The aim of this work is to serve as a longstanding reference that will be used to introduce types to Elixir 
programmers, as well as to hint at some future directions and possible evolutions of the Elixir language. 
ACM CCS 2012 
Theory of computation → Type structures; Program analysis; 
Software and its engineering → Functional languages; 
Keywords type systems, dynamic languages, set-theoretic types, Elixir. 

## The Art, Science, and Engineering of Programming

Submitted May 31, 2023 
Published October 15, 2023 
doi 10.22152/programming-journal.org/2024/8/4 
© Giuseppe Castagna, Guillaume Duboc, and José Valim 
This work is licensed under a “CC BY 4.0” license. 
In The Art, Science, and Engineering of Programming, vol. 8, no. 2, 2024, article 4; 39 pages. 
The Design Principles of the Elixir Type System 
1 Introduction 
Elixir [20] is a functional programming language that runs on BEAM, the Erlang 
Virtual Machine [48]. The language has been gaining adoption over the last years in 
areas such as web applications, embedded systems, data processing, and distributed 
systems, and used by companies like Discord and PepsiCo. The success of Elixir can be 
in good part ascribed to the underlying BEAM machine, developed by Ericsson in the 
eighties, and considered to be a great feat of engineering for concurrency, distribution, 
and fault tolerance. A limitation of both Erlang and Elixir is that they are dynamically 
typed, meaning they do not enjoy the safety features of a static type system that 
ensure at compile-time the absence of a given class of run-time errors. 
Developing a static type system suitable for Erlang has been an open research 
problem for almost two decades. The earliest effort was attempted by Marlow and 
Wadler [34], which typed a subset of Erlang using subtyping unification constraints. 
However, their system was not adopted as type inference was slow, and the inferred 
types were large and complex. Ever since then, several attempts—either practical, 
theoretical, or both—have followed [37, 32, 50, 40, 21, 29, 45]. 
We present a gradual type system for Elixir, based on the framework of semantic 
subtyping [10, 23]. This framework, developed for and implemented by the CDuce 
programming language [3, 16], provides a type system centered on the use of set 
theoretic types (unions, intersections, negations) that satisfy the commutativity and 
distributivity properties of the corresponding set-theoretic operations [23]. The system 
is a polymorphic type system with local type inference, that is, functions are explicitly 
annotated with types that may contain type variables, but their applications do not 
require explicit instantiations: the system deduces the right instantiations of every 
type variable. It also features precise typing of patterns and guards combined with 
type narrowing: the types of the capture variables of the pattern and of some variables 
of the matched expression are refined in the branches of case expressions to take into 
account the results of pattern matching. With respect to the system implemented for 
the CDuce language, the system we define for Elixir brings several novelties and new 
features. Its main contributions can be summarized as follows: 
Semantic subtyping. An extension of the semantic subtyping framework to fit 
Elixir/Erlang, in particular, the definition of new function domains to account for 
the tight connection between Elixir/Erlang functions and their arity. 
Guards. A new typing technique for analyzing guards in pattern matching. 
Records and dictionaries. A new typing discipline unifying records and dictionaries. 
Dynamic type. The integration of the dynamic type in the type system, which is 
used to describe untyped parts of the code, and how they interact with statically 
typed parts. This uses and innovates techniques of the gradual typing literature. 
Strong arrows. A new gradual typing technique for typing functions that takes into 
account runtime type tests performed by the virtual machine or inserted by the 
programmer. This makes it possible to guarantee the soundness of the gradual 
typing system with precise static types, without modifying the compilation of the 
source code, that is, in the terminology of [31], a safe type system with erasure 
gradual typing. 

4:2

The system we present is, thus, a combination of both existing (set-theoretic types, polymorphism with local type inference, narrowing, gradual typing) and new (guard analysis, strong arrows, records and dictionaries) techniques. We believe that for the definition of a type system for the Elixir/Erlang ecosystem1 there is no single silver bullet solution, and that, instead, all the techniques above are necessary to give the system a chance to be accepted and adopted by the community of developers (see also Section 5). We partially implemented the system by a simple prototype that was internally tested by the Elixir development team and that received scattered feedback from the Elixir community. At the moment of writing we are working on an implementation to (gradually) integrate the system in the compiler that we hope to test in the course of next year. Only then we will be able to assess the usability of the type system, how it will perform on large codebases, and the degree of adoption by the community. And while we are cautiously confident in the work we present here, we do not rule out the possibility of finding unforeseen deal-breakers that could send us back to square one. Outline In Section 2, we provide an overview of the specific typing issues that arise in Elixir and the reasons why set-theoretic types are a good fit to type it. In Section 3, we demonstrate the various typing techniques we developed specifically for Elixir. We outline the formal approach to typing programs in Elixir in Section 4. Section 5 covers our design principles for integrating the type system into the Elixir compiler and the impact on programmers. Section 6 discusses related work, while Section 7 concludes our presentation and outlines some features planned as future work.

2 Typing Elixir: An Overview 
2.1 Why Types 

Static typing seems nowadays to be the biggest need for the Elixir community. Today, Elixir supports Typespec, a mechanism for annotating functions with types [49]. However, Typespec’s specifications are not verified by the compiler. Instead, a tool called Dialyzer, which ships with the Erlang standard library, can be used to find discrepancies in your source code and type annotations. Dialyzer is based on success typing [32], which guarantees no false positives, but may leave several bugs uncaught. As the Elixir community grows, the general feedback is that, while Dialyzer is helpful and provides developers with some guarantees, its ergonomics and functionality do not fully match the community expectations. Based on our experience with the language and its ecosystem, we speculate developers would accept more false positives from the compiler in exchange for catching more bugs. Hence, the interest of the authors in fully baking static typing into the Elixir compiler.

1 Semantically, Elixir is a superset of Erlang with the addition of protocols and macros. This is a design goal of Elixir, reflected by the fact the Elixir front-end compiler produces Erlang AST. Therefore, by typing all Elixir idioms, we also type all Erlang idioms.

4:3

The benefits we expect are essentially twofold. The first benefit of types is to aid documentation (emphasis on the word “aid” since we don’t believe types can replace textual documentation). Elixir already reaps similar benefits from Typespec, and we expect an integrated type system to be even more valuable in this area. The second benefit of static types revolves around contracts. If function caller(arg) calls a function named callee(arg), we want to guarantee that, as these functions change over time, the caller passes valid arguments into the callee and correctly handles the return types from the callee. This may seem like a simple guarantee, but we can run into tricky scenarios even on small code samples. For example, imagine that we define a negate function, that negates numbers. One may implement it like this:

1 $ integer() -> integer() 
2 def negate(x) when is_integer(x), do: -x 

The negate function receives an integer() and returns an integer().2 Type specifi cations are prefixed by $ and each specification applies to the definition it precedes. With our custom negation in hand, we can implement a custom subtraction:

3 $ (integer(), integer()) -> integer() 
4 def subtract(a, b) when is_integer(a) and is_integer(b) do 
5 a + negate(b) 
6 end 

This would all work and typecheck as expected, as we are only working with integers. Now, imagine in the future someone decides to make negate polymorphic (here, ad hoc polymorphic), by including an additional clause so it also negates booleans:

7 $ (integer() or boolean()) -> (integer() or boolean()) 
8 def negate(x) when is_integer(x), do: -x 
9 def negate(x) when is_boolean(x), do: not x 

The specification at issue uses integer() or boolean() stating that both the argu ment and the result are either an integer or a boolean. This is a union type which has become common place in many programming languages. The type specified for negate is not precise enough for the type system to deduce that when negate is applied to an integer the result is also an integer.

10 Type warning: 
11 | def subtract(a, b) when is_integer(a) and is_integer(b) do 
12 | a + negate(b) 
13 ^ the operator + expects integer(), integer() as arguments, 
14 but the second argument can be integer() or boolean() 
Such a type system would not be enough to capture many of Elixir idioms, and it 
would probably lead to too many false positives. Therefore, in order to evolve contracts 
over time, we need more expressive types. In particular, to solve this issue we need an 
intersection type, which specifies that negate has both type integer()->integer() 
2 We follow Erlang convention that basic types are suffixed by “ () ”, for instance, string() . 

4:4

Giuseppe Castagna, Guillaume Duboc, and José Valim (i.e., it is a function that maps integers to integers) and type boolean()->boolean() (i.e., it is a function that maps booleans to booleans). This type is more precise than the previous one and is written as:

15 $ (integer() -> integer()) and (boolean() -> boolean())

With this type, the type checker can infer that applying negate to an integer will return an integer. Therefore, in the definition of subtract, the application negate(b) has type integer(), and the function subtract is well-typed.

2.2 Set-Theoretic Types and Subtyping Relation

Unions, intersections, and—see later on—negations are called set-theoretic types, insofar as they can be thought of in terms of sets: if we think of a type as the set of all values of that type (e.g., integers() as the set of all integer constants, boolean() as the set containing just true and false, ...), then the union of two types is the set that contains the union of their values (e.g., a value of type integer() or boolean() is either an integer value or a boolean value), the intersection of two types is the set that contains the values that are in both types (e.g, a value in the intersec tion (integer()->integer()) and (boolean()->integer()) is a function that both maps integers to integers and maps booleans to integers), and, finally, the negation of a type is its complement, that is, it contains all the (well-typed) values that are not in the type (e.g., a value in not integer() is any value that is not an integer). Notice that an intersection of arrows does not necessarily correspond to multiple definitions of a function. For instance, the following definition is well-typed:

16 $ (integer() -> integer()) and (boolean() -> boolean()) 
17 def negate_alt(x), do: (if is_integer(x), do: -x, else: not x) 

We have seen that we can specify two different types for negate, that is: (1) (integer() or boolean()) -> (integer() or boolean()) (2) (integer() -> integer()) and (boolean() -> boolean()) and we said that the latter type is “more precise” than the former. Formally, we state that the latter is a subtype of the former, meaning that every value of the latter is also a value of the former. In the case of the two types above, the subtyping relation is also strict: every function that maps integers to integers and booleans to booleans, is also a function that maps an integer or a boolean to an integer or a boolean, but not vice versa. For example, the constant function fn x -> 42 end maps both integers and booleans to integers and thus to integer() or boolean(); as such it is a function of the type in (1). However, it does not map booleans to booleans. Therefore, it is not in the intersection type in (2). When two types are one subtype of each other they are said to be equivalent, since they denote the same set of values (e.g., (integer()->integer()) and (boolean()->integer()) is equivalent to (integer or boolean())->integer()). The type of negate or negate_alt can also be expressed without intersections, by using parametric bounded quantification,3 but this is seldom the case. For instance, 3 Precisely as $ a -> a when a: integer() or boolean() : see Section 2.3.

4:5

Elixir provides a negation operator named !, which is defined for all values. The values nil and false return true, while all other values return false. With set-theoretic types, we can give to this operator the following intersection type:

18 $ (false or nil -> true) and (not (false or nil) -> false)

This type introduces two further ingredients of our type syntax: singleton types 
and negation types. Namely, the atoms true, false, and nil,⁴ are also types, called 
singleton types, because they contain only the constant/atom of the same name. The 
connective not denotes the negation of a type, that is, the type that contains all the 
well-typed values that are not in the negated type, whence the interpretation of the 
functional type above.⁵ 
The advantage of interpreting types as the set of their values is that types satisfy 
the distributivity and commutativity laws of their set-theoretic counterparts. 
For instance, a well-known property of products is that unions of products with a 
same projection factorize, that is,{s1,t} or {s2,t} is equivalent to{s1 or s2, t} 
(Elixir uses curly brackets for products). This is reflected by the behavior of our 
type-checker that accepts the following definitions: 
19 $ type t() = {integer() or string(), boolean()} 
20 $ type s() = {integer(), boolean()} or {string(), boolean()} 
21 $ (( t() -> t()), s() ) -> s() 
22 def apply(f,x) do: f.(x) 
The first two lines define the types t() and s() while lines 21-22 define a function 
whose typing demonstrates that the type-checker considers t() and s() to be equiva 
lent. This is because it allows an expression of type t() to be used where an expression 
of type s() is expected (i.e., f which expects an argument of type t() is given an 
argument x, which is of type s()) and an expression of type s() where an expression 
of type t() is expected (i.e., the type specification declares that apply returns a result 
of type s(), but the body returns f(x) which is of type t()). In contrast, languages 
that use a syntactic definition of subtyping, such as Typed Racket, Flow, or TypeScript, 
accept the application f(x) but reject the typing of apply: they cannot deduce that 
t() is a subtype of s(). 
Finally, we adopt the Typespec conventions wherein term() represents the top type 
(i.e., the type of all values) and none() denotes the empty type, that is, the type that 
has no value and which is equivalent to not term() (likewise, term() is equivalent 
to not none()). 

2.3 Applying Set-Theoretic Types to Elixir

The existing set-theoretic types literature enables our type system to represent several Elixir idioms. We outline some examples in this section. 4In Elixir, atoms are user-defined constants obtained by prefixing an identifier by colon, as in :ok , :error , and so on. The atoms true , false , and nil are supported without colon for convenience. 5 The precedence of and and or is higher than type constructors (arrows, tuples, records, lists), and the negation not has the highest precedence of them all.

4:6

Parametric Polymorphism with Local Type Inference Set-theoretic type-systems feature parametric polymorphism with local type inference: expressions (in particular func tions) can be given types containing type variables, but to use them it is not necessary to specify how to instantiate these variables, since the system deduces it [15, 14]. In our implementation, type variables are identifiers that are quantified by using a postfix when in which variables come with their upper bound.⁶ Type variables are distinguishable from basic types, since they are not suffixed by “()”. We feature only first order polymorphism, so when can only occur outside a type (never inside it). The map and reduce operations over lists are good examples of need for polymorphic types, since most of the functions working with collections (known as “enumerables” in Elixir) cannot be sensibly typed without them. For instance, we have

23 $ ([a], (a -> b)) -> [b] when a: term(), b: term() 
24 def map([h | t], fun), do: [fun.(h) | map(t, fun)] 
25 def map([], _fun), do: [] 

26 $ ([a], b, (a, b -> b)) -> b when a: term(), b: term() 
27 def reduce([h | t], acc, fun), do: reduce(t, fun.(h, acc), fun) 
28 def reduce([], acc, _fun), do: acc 
meaning that for all types a and b (i.e., for all a and b subtypes of term()): 
map is a binary function that takes a list of elements of type a (notation [a]), a 
function from a to b and returns a list of elements of type b; 
reduce is a ternary function that takes a list of a elements, an initial value of type 
b, a binary function that maps a’s and b’s into b’s, and returns a b result. 
Local type inference infers that for map([1, 4], fn x -> negate(x) end) both type 
variables must be instantiated by integer(), deducing the type [integer()] for it. 
Intersection can also be used to define the type specification of reduce for the case 
of empty lists (in which case the third argument can be of any type): 

29 $ (([a] and not [], b, (a, b -> b)) -> b) and 
30 (([], b, term()) -> b) when a: term(), b: term() 

Polymorphic types make inference more precise for other functions. For instance, if we add a default case to the negate example (lines 51-52) we obtain the code

31 def negate(x) when is_integer(x), do: -x 
32 def negate(x) when is_boolean(x), do: not x 
33 def negate(x), do: x 

for which we can deduce—or at least check—the type (notice the use of bounded 
quantification in line 36) 
6 We did not specify lower bounds since they are not frequently used and they can be encoded 
by union types, e.g., ∀ (s ≤ α).α → α de f = ∀ (α).(s ∨ α → s ∨ α); upper bounds can be encoded, 
too, this time by intersections (e.g., ∀ (s ≤ α ≤ t).α → α de f = ∀ (α).((s ∨ α) ∧ t) → (s ∨ α) ∧ t)), 
but their frequency justifies the introduction of specific syntax. 
The use of postfix when for variable quantification is borrowed from Typespec. 

4:7

34 $ (integer() -> integer()) and 
35 (true -> false) and (false -> true) and 
36 (a -> a) when a: not(integer() or boolean()) 

and thus deduce for some function such as

37 def foo(x) when is_atom(x), do: negate(x)

the type atom() -> atom(), since an atom is neither an integer nor a Boolean. It is possible to define polymorphic types with type parameters. For instance, we can define the type tree(a), the type of nested lists whose elements are of type a, as 38 $ type tree(a) = (a and not list()) or [tree(a)]

and then use it to type the polymorphic function flatten that flattens a tree(a) returning a list of a elements:

39 $ tree(a) -> [a] when a: term() 
40 def flatten([]), do: [] 
41 def flatten([x | xs]), do: flatten(x) ++ flatten(xs) 
42 def flatten(x), do: [x] 

The function above is well-typed. The three clauses of its definition are exhaustive (the last one captures all the arguments not captured by the first two). The first clause returns an empty list (thus a value of type [a]). The second clause captures any argument that is a non-empty list of tree(a) elements (since these are the only lists the function can be applied to), therefore our system deduces that x is of type tree(a) and xs is of type [tree(a)]; since [tree(a)] is a subtype of tree(a) (the latter being defined as the union of the former with another type), then both subsequent applications of flatten are well typed; therefore, both return results of type [a] whose concatenation (noted ++ ) yields againt a result of type [a]. Finally, the inputs of type tree(a) that are not captured by the first two clauses, and are thus processed by the last clause, are just the arguments of type a that are not lists (from all inputs of type tree(a), the first clause removes the empty lists, while the second clause removes all the non-empty lists of tree(a) elements); therefore the result of this clause is of type [a and not list()] and, by subtyping, of type [a], too. When flatten is applied, then the local type inference analyzes the argument, in order to determine the instantiation of the type of the function. If the argument is not a list, then a is instantiated to the type of the argument. If it is a list, then a is instantiated to the union of the types of all the non-list elements of this nested list. For instance, the type statically deduced for the application

43 flatten [3, "r", [4, [true, 5]], ["quo", [[false], "stop"]]] is [integer() or boolean() or binary()] (where binary() is the type for strings).

Protocols Elixir supports a kind of polymorphism akin to Haskell’s typeclasses, via protocols. A protocol defines a set of operations that can be implemented for

4:8

any type. For example, the String.Chars protocol requires the implementation of 
the to_string function. This function can convert any data type to a human rep 
resentation as long as an implementation of the String.Chars protocol (viz., of 
to_string) has been defined for that data type. The union of all types that imple 
ment String.Chars is automatically filled in by the Elixir compiler and denoted 
by String.Chars.t(). In the absence of set-theoretic types this union would be 
approximated by term(). 
Protocols can combine with parametric polymorphism to define more expressive 
types, such as collections. In Elixir, lists, sets, and ranges are all said to implement the 
Enumerable protocol which can be represented by the type Enumerable.t(a), that 
is, the enumerables whose elements are of type a (i.e., a-lists, a-sets, and a-ranges). 
So, for instance, the type of a generic map function that processes the elements of an 
enumerable will be type Enumerable.t(a), (a -> b) -> Enumerable.t(b), while 
the function that sums all elements of an enumerable of integer elements will have 
type Enumerable.t(integer()) -> integer(). 
The power behind Elixir protocols is that they allow library authors to express 
requirements in their APIs that are decoupled from the implementation of those 
requirements. For example, one strength of Elixir is in developing web applications. 
Web applications often have to encode Elixir data structures into different formats, 
such as JSON, CSV, XML, etc. To decouple the data types from the encoding logic, the 
author of a web framework defines a protocol, such as JSON.Encoder, and states it 
can encode any data structure, as long as it implements the JSON.Encoder protocol. 
With set-theoretic types, library authors can now combine protocols to build addi 
tional requirements. One business may require that all of their public data must be 
available in several different data formats. They can encapsulate this requirement by 
defining an intersection of existing protocols: 

44 $ type export() = JSON.Encoder.t() and CSV.Encoder.t() and XML.Encoder.t()

A system with looser requirements may use a union instead of intersection: the data type must implement at least one of the formats above, in order to be accepted by the system.

3 Extending Semantic Subtyping for Elixir All features presented so far adapt to Elixir what is already possible in the type system of CDuce, defined via the set-theoretic interpretation of types of semantic subtyping [23]. There are however several key specific characteristics of Elixir that require the semantic subtyping framework to be modified, improved, and/or extended.

3.1 Function Arity A first such characteristic is the arity of functions which plays an important role in Elixir. While it is possible to test the arity of a function using the expression is_function (e.g., is_function(foo, 2) tests whether foo is a binary function), it is not possible

4:9

The Design Principles of the Elixir Type System in semantic subtyping to express the type of exactly all functions with a specific arity.⁷ This is because, in CDuce, all functions are unary, with a function that takes two arguments being considered a unary function that expects a pair. Although it is possible to define a type for all functions as none() -> term(),⁸ it is not possible to give a type specifically for, say, binary functions using{none(),none()} -> term() , for the simple reason that a product of the empty set is equivalent to the empty set, and thus the latter type is equivalent to the former. To address this issue, we introduce a special syntax for function types, written as (t1,··· ,tn) -> t which outlines the arity of the functions and that we already used in the previous examples. This allows the type of all binary functions to be written as (none(),none()) -> term(). However, this requires a non-trivial modification in the set-theoretic interpretation of function spaces: after defining the interpretation of multi-arity functions, subtyping is reframed as a set-containment problem. Solving this problem then produces the decision algorithm for subtyping (see Appendix A.1 for further details).

3.2 Guards and Pattern Matching

A second characteristic of Elixir that is not captured by the current research on 
semantic subtyping is the extensive use of guards both in function definitions and 
pattern matching. 
In the previous examples, we have explicitly declared the type signature of all 
functions we defined, such as: 

45 $ integer() -> integer() 
46 def negate(x) when is_integer(x), do: -x 

However, our type system is capable to infer the types of functions as the above even in the absence of their type declaration, by considering guards as explicit type annotations for the respective parameters. This not only applies to simple type tests of the parameters, but also to more complex tests. For example, for

47 def get_age(person) when is_integer(person.age), do: person.age our system deduces from the guard that person must be a record with at least the field age defined, and containing a value of type integer(), that is, an expression of type %{age: integer(), ...} . This is a record type: records in Elixir are prefixed by % to distinguish them from tuples; the three dots indicate that the record type is open, that is, it types records where other fields may be defined (cf. Section 3.3). Since the dot in person.age denotes field selection, then our system deduces for the function get_age the type %{age: integer(), ...} -> integer() . One novelty of our system is that it can precisely express (most) guards in terms of types, in the sense that the set of values that satisfy a guard is the set of values that belong to a given type: for instance, 7In our system, to be able to express arity tests in terms of types is crucial for the precise typing of guards and, thus, of functions and pattern matching: cf. Section 3.2. 8 The top type of functions of arity one is not term()->term() . In our system, every function of this type can be safely applied to any argument of type term() , that is, every well-typed argument. But of course not every function satisfies this property: only the total ones.

4:10

the set of all values that satisfy the guard is_integer(person.age)) coincides with 
the set of values that have type %{age: integer(), ...} . Previous systems with 
semantic subtyping and set-theoretic types did not account for guards, which is the 
reason why we had to develop a specific analysis technique for them (see Section 4 
for more details). 
Note that, in the absence of such guards, it is the task of the programmer to 
explicitly provide the type of the whole function by preceding its definition by a 
type specification. It is also possible to elide parts of the return type of non-recursive 
functions by using the underscore symbol “_”, as in 

48 $ integer() -> _ 
49 def negate(x) when is_integer(x), do: -x 

or 50 $ (integer() -> _) and (boolean() -> _) 51 def negate(x) when is_integer(x), do: -x 52 def negate(x) when is_boolean(x), do: not x leaving to the type system the task of deducing the best possible types to replace for each occurrence of the underscore. Exhaustivity Checking Type analysis makes it possible to check whether clauses of a function definition, or patterns in a case expression, are exhaustive, that is, if they match every possible input value. For instance, consider the following code: 53 $ type result() = 54 %{output: :ok, socket: socket()} or 55 %{output: :error, message: :timeout or {:delay, integer()}} 56 57 $ result() -> string() 58 def handle(r) when r.output == :ok, do: "Msg received" 59 def handle(r) when r.message == :timeout, do: "Timeout" We define the type result() as the union of two record types: the first maps the atom :output to the (atom) singleton type :ok and the atom :socket to the type socket(); the second maps :output to :error and maps :message to a union type formed by an atom and a tuple. Next consider the definition of handle: values of type %{output: error, message: {:delay, integer()}} are going to escape every pattern used by handle, triggering a type warning: 60 Type warning: 61 | def handle(r) do 62 ^^^^^^^^^ 63 this function definition is not exhaustive. 64 there is no implementation for values of type: 65 %{output: :error, message: {:delay, integer()}}

Note that the type checker is able to compute the exact type whose implementation is missing, which enables fast refactoring since, as the type of result() or the imple mentation of handle are modified, the type checker will issue precise new warnings to point out the places where code changes are required.

4:11

Redundancy Checking Similarly, it is possible to find useless branches—i.e., branches that cannot ever match. For instance, if we add a clause to the previous example:

66 $ result() -> string() 
67 def handle(r) when r.output == :ok, do: "Msg received" 
68 def handle(r) when r.message == :timeout, do: "Timeout" 
69 def handle({:ok, msg}), do: msg 
then since the specified input type is result() (which is a subtype of maps), the third 
branch will never match (its pattern matches only pairs) and can be deleted. 
This will remove useless code, detect unused function definitions, or reveal more 
complex problems as these hints can indicate areas where the programmer’s expecta 
tions and the actual logic of the program do not match. 
Narrowing Narrowing is the typing technique that consists in taking into account 
the result of a (type-related) test to refine (i.e., to narrow) the type of variables 
in the different branches of the test. In Section 2.2 we have already presented a 
simple example in which narrowing is used, namely, in the function negate_alt 
(code in line 17) the type-checker uses the test to narrow the type of x, which is 
(integer() or boolean()), to integer() in the “do” branch and to boolean() in 
the “else” branch. This is a simple application of narrowing, where the narrowing is 
performed on the type of a variable whose type is directly tested. However, our system 
is also able to narrow the type of the variables that occur in the expression tested by a 
“case” or a “if ”, even if this expression is not a single variable (some exceptions apply 
though: see future works). Here is a more complete example where we test the field 
selection on a variable 
70 $ result() -> _ 
71 def handle(r) when r.output == :ok, do: {:accepted, r.socket} 
72 def handle(r) when is_atom(r.message), do: r.message 
73 def handle(r), do: {:retry, elem(r.message, 1)} 
In the example the type of r which initially is result() is narrowed in the first branch 
to %{output: :ok, socket: socket()} , to %{output: :error, message: :timeout} in 
the second branch, and to %{output: :error, message: {:delay, integer())}} in the 
last one. This precision is shown by the fact that handle type-checks the following 
type specification too: 
74 $ (%{output: :ok, socket: socket()} -> {:accept, socket()}) and 
75 (%{output: :error, message: :timeout} -> :timeout) and 
76 (%{output: :error, message: {:delay, integer()}} -> {:retry, integer()}) 
As a matter of fact, deducing the type of the parameters of a function by examining 
its guards is just yet another application of narrowing where the function parameters 
are initially given the type term() and narrowed by the types deduced for the guards. 
Conservative Approximations When performing a type analysis on patterns with 
guards, it may not always be possible to determine the precise type of the captured 

4:12

Giuseppe Castagna, Guillaume Duboc, and José Valim values. In such cases, we use both lower and upper approximations to ensure that narrowing and exhaustivity/redundancy checking still work. As an example, consider the following simplistic function:

77 def foo(x) when map_size(x) == 2, do: Map.to_list(x) We are unable to express by a type the exact domain of this function, which is the set of “all maps of size 2”. However, when the guard succeeds, it is clear that x is a map, and this assumption is enough to deduce by narrowing that the body of the function is well-typed. Using the type of all maps to approximate the set of all maps of size 2 is an over-approximation. We call such a type the potentially accepted type of the pattern/guard since it contains all the values that may match it. Conversely, consider the following example:

78 def bar(x) when (is_map(x) and map_size(x) == 2) or is_list(x), do: 
,→ to_string(x) 
79 def bar(x) when length(x) == 2, do: x 
The first clause matches both the maps of size 2 (but no other map) and any lists. 
Although we cannot characterize by a type all the values matched by the first clause, we 
do know that all lists are captured by it and, therefore, the second clause is redundant 
(length being defined only for lists). The type of all lists is an under-approximation 
(i.e., a subset) of the set of all values that satisfy the guard in the first clause. We refer 
to this under-approximation as the surely accepted type of the pattern/guard since it 
contains only values that do match it. Our system makes a distinction between guards 
that require approximation and those that do not, as further described in Section 4. 
Complex Guards The analysis of guards is more sophisticated than it appears. First 
of all, guards are examined left to right by incrementally generating environments 
during their analysis. An example is the guard in line 78: if we compare it with line 77 
we see that we added an is_map(x) test. Without it the guard in line 78 would be 
equivalent to the one in line 77, since when x is a list, then map_size(x) == 2 fails 
(rather than return false), and so does the whole guard: the is_list(x) would 
never be evaluated. To account for this, our analysis examines is_list(x) only if 
the preceding clause may not fail, which is always the case—though, it can return 
false— and map_size(x) is examined only in the environments in which is_map(x) 
succeeds. 
Another stumbling block is that the analysis may need to generate for a single guard 
different type environments under which the continuation of the program is checked, 
as the following definition shows: 

80 $ (term(),term()) -> {integer(),term()} or {term(),boolean()} or nil 
81 def baz(x, y) when is_boolean(x) or is_integer(y), do: {y,x} 
82 def baz(_, _), do: nil 

The definition above type-checks, but this is possible only because the analysis of the guard is_boolean(y) or is_integer(z) in line 81 generates two distinct environ ments (i.e., one where z has type integer() and y type term(), and a second one

4:13

The Design Principles of the Elixir Type System where their types are inverted) which are both used to deduce two types for{z,y} which are then united in the result. By the same technique, in the absence of a type specification our system deduces for the first clause of baz in line 81 the type

83 ((term(),integer()) -> {integer(),term()}) and 
84 ((boolean(),term()) -> {term(),boolean()}) 
and the analysis of the code defined in line 82 adds to this intersection the following 
arrow: (not(boolean()),not(integer())) -> nil. 
Finally, our type system can analyze arbitrarily nested Boolean combinations of 
guards which are type tests of complex selections primitives, as the following definition 
of a parametric guard is_data(d) shows: 
85 defguard is_data(d) when is_tuple(d) and tuple_size(d) == 2 and 
86 (elem(d, 0) == :is_an_int and is_integer(elem(d, 1)) or 
87 elem(d, 0) == :is_a_bool and is_boolean(elem(d, 1))) 
Our system deduces that the guard is_data(d) succeeds if and only if d is of type 
data() defined as follows: 
88 $ type data() = {:is_an_int, integer()} or {:is_a_bool, boolean()} 
3.3 Records and Dictionaries 

In Elixir, maps are a key-value data structure that serves as the primary means of storing data. There are two distinct use cases for maps: as records, where a fixed set of keys is defined, and as dictionaries, where keys are not known in advance and can be dynamically generated. A map type should unify both, allowing the type-checker to sensibly choose when it needs to ensure that some expected keys are present while enforcing type specifications for queried values. Maps as

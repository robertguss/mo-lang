---
source_url: https://austral-lang.org/spec/spec.html
ingested: 2026-09-12
sha256: 9ee040df449663d0c5a28de7f0c1d6a1b7a118fc671d10b128b8695b710563b0
---
# The Austral Language Specification

The Austral Language Specification 

# The Austral Language Specification

Fernando Borretti

# Introduction

> Time, which attenuates all memories, sharpens that of the Zahir.
> 
> — Jorge Luis Borges, El Zahir

Austral is a new programming language. It is designed to enable writing code that is secure, readable, maintainble, robust, and long-lasting.

# Design Goals

This section lists the design goals for Austral.

1. Simplicity. This is the sine qua non: the language must be simple enough to fit in a single person’s head. We call this “fits-in-head simplicity”. Notably, many languages fail to clear this bar. C++ is the prototypical example, already its author has warned against excess complexity (in vain).

Simplicity is valuable for multiple reasons:

1. It makes the language easier to implement, which makes it feasible to have multiple implementations, reducing vendor lock-in risk.
2. It makes the language easier to learn, which is good for beginners.
3. It makes code easier to reason about, because there are fewer overlapping language features to consider.

Simplicity is defined in terms of Kolmogorov complexity: a system is simple not when it forgives mistakes or is beginner-friendly or is easy to use. A system is simple when it can be described briefly.

Two crucial measures of simplicity are:

1. Language lawyering should be impossible. If people can argue about what some code prints out, that’s a language failure. If code can be ambiguous or obsfuscated, that is not a failure of the programmer but a failure of the language.
2. A programmer should be able to learn the language in its entirety by reading this specification.

Simplicity also means that Austral is a generally low-level language. There is no garbage collector, not primarily because of performance concerns, but because it would require an arbitrarily complex runtime.
2. Correctness. This is an intangible, but generally, the measure of how much a language enables programmers to write correct code is: if the code compiles, it should work. With the caveat that said code should use the relevant safety features, since it is possible to write unsafe C in any language.

There is a steep tradeoff curve between correctness and simplicity: simple type system features provide 80% of correctness. The remaining 20% consists of things like:

1. Statically proving that there are no integer overflows.
2. Proving that all array indexing calls are within array bounds.
3. More generally: proving that function contracts are upheld.

Doing this with full generality requires either interactive theorem proving or SMT solving, which is a massive increase in implementational complexity (Z3 is 300,000 lines of C++). Given that this is an active area of research in computer science, we sacrifice absolute safety for implementational simplicity.
3. Security. It should not be difficult to write secure code. That is: ordinary language features should not be strewn with footguns that make security impossible.
4. Readability. We are not typists, we are programmers. And because code is read far more than it is written, we should optimize for readability, perhaps at the cost of writability.
5. Maintainability. Leslie Lamport wrote:

> An automobile runs, a program does not. (Computers run, but I’m not discussing them.) An automobile requires maintenance, a program does not. A program does not need to have its stack cleaned every 10,000 miles. Its if statements do not wear out through use. (Previously undetected errors may need to be corrected, or it might be necessary to write a new but similar program, but those are different matters.) An automobile is a piece of machinery, a program is some kind of mathematical expression.

Working programmers know this is far from reality. Bitrot, not permanence, is the norm. However, bitrot is avoidable by doing careful design up-front, prioritizing stability in the design, and, crucially: saying no to proposed language features. The goal is that code written in Austral that depends only on the standard library should compile and run without changes decades into the future.
6. Modularity. Software is built out of hierarchically organized modules, accessible through interfaces. Languages have more-or-less explicit support for this:

1. In C, all declarations exist in the same namespace, and textual inclusion and the separation of header and implementation files provides a loose modularity, enforced only through style guides and programmer discipline.
2. In Python, modules exist, their names and paths are tied to the filesystem, and the accessibility of identifiers is determined by their names.
3. In Rust and Java, visibility modifiers are attached to declarations to make them public or private.

Austral’s module system is inspired by those of Ada, Modula-2, and Standard ML, with the restriction that there are no generic modules (as in Ada or Modula-3) or functors (as in Standard ML or OCaml), that is: all modules are first-order.

Modules are given explicit names and are not tied to any particular file system structure. Modules are split in two textual parts (effectively two files), a module interface and a module body, with strict separation between the two. The declarations in the module interface file are accessible from without, and the declarations in the module body file are private.

Crucially, a module `A` that depends on a module `B` can be typechecked when the compiler only has access to the interface file of module `B`. That is: modules can be typechecked against each other before being implemented. This allows system interfaces to be designed up-front, and implemented in parallel.
7. Strictness. Gerald Jay Sussman and Hal Abelson wrote:

> Pascal is for building pyramids — imposing, breathtaking, static structures built by armies pushing heavy blocks into place. Lisp is for building organisms — imposing, breathtaking, dynamic structures built by squads fitting fluctuating myriads of simpler organisms into place.

Austral is decidedly a language for building pyramids. Code written in Austral is strict, rigid, crystalline, and brittle: minor changes are prone to breaking the build. We posit that this is a good thing.
8. Restraint. There is a widespread view in software engineering that errors are the responsibility of programmers, that “only a bad craftsperson complains about their tools”, and that the solution to catastrophic security vulnerabilities caused by the same underlying mechanisms is to simply write fewer bugs.

We take the view that human error is an inescapable, intrinsic aspect of human activity. Human processes such as code review are only as good as the discipline of the people running them, who are often tired, burnt out, distracted, or otherwise unable to accurately simulate virtual machines (a task human brains were not evolved for), or facing business pressure to put expedience over correctness. Mechanical processes — such as type systems, type checking, formal verification, design by contract, static assertion checking, dynamic assertion checking — are independent of the skill of the programmer.

Therefore: programmers need all possible mechanical aid to writing good code, up to the point where the implemention/semantic complexity exceeds the gains in correctness.

Given the vast empirical evidence that humans are unable to predict the failure modes and security vulnerabilities in the code they write, Austral is designed to restrain programmer power and minimize footguns.

# Rationale

This section explains and justifies the design of Austral.

## Syntax

According to Wadler’s Law,

> In any language design, the total time spent discussing a feature in this list is proportional to two raised to the power of its position.
> 
> 0. Semantics
> 1. Syntax
> 2. Lexical syntax
> 3. Lexical syntax of comments

Therefore, I will begin by justifying the design of Austral’s syntax.

Austral’s syntax is characterized by:

1. Being statement-oriented rather than expression oriented.
2. Preference over English-language keywords over non-alphanumeric symbols, e.g. `begin` and `end` rather than `{` and `}`, `bind` over `>>=`, etc.
3. Delimiters include the name of the construct they terminate, e.g. `end if` and `end for`.
4. Verbose names are preferred over inscrutable abbreviations.
5. Statements are terminated by semicolons.

These decisions will be justified individually.

### Statement Orientation

Syntax can be classified into three categories.

1. Statement-Oriented: Like C, Pascal, and Ada. Statements and expressions form two distinct syntactic categories.
2. Pure Expression-Oriented Syntax: Like Lisp, Standard ML, OCaml, and Haskell. There are only expressions, and the syntax reflects this directly.
3. Mixed Syntax: Many newer languages, like Scala and Rust, fall into this category. At the AST level there is only one kind of thing: expressions. But the actual written syntax is made to resemble statement-oriented languages to make programmers more comfortable.

In Epigrams in Programming, Alan Perlis wrote:

> 6. Symmetry is a complexity-reducing concept (co-routines include subroutines); seek it everywhere.

Indeed, expression-oriented syntax is simpler (there is no duplication between e.g. `if` statements and `if` expressions) and symmetrical (there is only one syntactic category of code). But it suffers from excess generality in that it is possible to write things like:

```
let x = (* A gigantic, inscrutable expression
           with multiple levels of `let` blocks. *)
in
    ...
```

In short, nothing forces the programmer to factor things out.

Furthermore, in pure expression-oriented languages of the ML family code has the ugly appearance of “hanging in the air”, there is little in terms of delimiters.

Three kinds of syntax.

Mixed syntaxes are unprincipled because the textual syntax doesn’t match the AST, which makes it possible to abuse the syntax and write “interesting” code. For example, in Rust, the following:

```
let x = { let y; }
```

is a valid expression. `x` has the Unit type because the block expression ends in a semicolon, so it is evaluated to the Unit type.

A statement-oriented syntax is less simple, but it forces code to be structurally simple, especially when combined with the restriction that uninitialized variables are not allowed. Then, the programmer is forced to factor out complicated control flow into chains of functions.

Historically, there is one language that moved from an expression-oriented to a statement-oriented syntax: ALGOL W was expression-oriented; Pascal, its successor, was statement-oriented.

### Keywords over Symbols

Austral syntax prefers English-language words in place of symbols. This is because words are easier to search for, both locally and on a search engine, than a string of symbols.

Additionally, words are read into sounds, which aids in remembering them, while a string like `>>=` can only be understood as a visual symbol.

Using English-language keywords, however, does not mean we use a natural language inspired syntax, like Inform7. The problem with programming languages that use an English-like natural language syntax is that the syntax is a facade: programming languages are formal languages, sentences in a programming language have a rigid and ideally unambiguous interpretation.

Programming languages should not hide their formal nature under a “friendly” facade of natural language syntax.

### Terminating Keywords

In Austral, delimiters include the name of the construct they terminate. This is after Ada (and the Wirth tradition) and is in contrast to the C tradition. The reason for this is that it makes it easier to find one’s place in the code.

Consider the following code:

```
void f() {
    for (int i = 0; i < N; i++) {
        if (test()) {
            for (int j = 0; j < N; j++) {
                if (test()) {
                    g();
                }
            }
        }
    }
}
```

Suppose we want to add some code after the second for loop. In this case, it’s simple enough:

```
void f() {
    for (int i = 0; i < N; i++) {
        if (test()) {
            for (int j = 0; j < N; j++) {
                if (test()) {
                    g();
                }
            }
            // New code goes here.
        }
    }
}
```

But suppose that instead of a call to `g()` we have multiple pages of code:

```
void f() {
    for (int i = 0; i < N; i++) {
        if (test()) {
            for (int j = 0; j < N; j++) {
                if (test()) {
                    // Hundreds and hundreds of lines here.
                }
            }
        }
    }
}
```

Then, when we scroll to the bottom of the function to add the code, we find this train of closing delimiters:

```
                }
            }
        }
    }
}
```

Which one of these corresponds to the second `for` loop? Unless we have an editor with folding support, we have to find the column where the second `for` loop begins, scroll down to the closing curly brace at that column position, and insert the code there. This is manual and error-prone.

Consider the equivalent in an Ada-like syntax:

```
function f() is
    for (int i = 0; i < N; i++) do
        if (test()) then
            for( int j = 0; j < N; j++) do
                if (test()) then
                    g();
                end if;
            end for;
        end if;
    end for;
end f;
```

Then, even if the code spans multiple pages, finding the second `for` loop is easy:

```
                end if;
            end for;
        end if;
    end for;
end f;
```

We have, from top to bottom:

1. The end of the second `if` statement.
2. The end of the second `for` loop.
3. The end of the first `if` statement.
4. The end of the first `for` loop.
5. The end of the function `f`.

Thus, delimiters which include the name of the construct they terminate involve more typing, but make code more readable.

Note that this is often done in C and HTML code, where one finds things like this:

```
} // access check
```

or,

```
</table> // user data table
```

However, declarations end with a simple `end`, not including the name of the declaration construct. This is because declarations are rarely nested, and including the name of the declaration would be unnecessarily verbose.

### Terseness versus Verbosity

The rule is: verbose enough to be readable without context, terse enough that people will not be discouraged from factoring code into many small functions and types.

### Semicolons

It is a common misconception that semicolons are needed for the compiler to know where a statement or expression ends. That is: that without semicolons, languages would be ambiguous. This obviously depends on the language grammar, but in the case of Austral it is not true, and the grammar would remain unambiguous even without semicolons.

The purpose of the semicolon is to provide redundancy, which aids both reading and parser error recovery. For example, in the following code:

```
let x : T := f(a, b, c;
```

The programmer has forgotten the closing parenthesis in a function call. However, the parser can report the error as soon as it encounters the semicolon.

For many people, semicolons represent the distinction between an old and crusty language and a modern one, in which case the semicolon serves a function similar to the use of Comic Sans by the OpenBSD project.

### Syntax of Type Declarations

The syntax of type declarations it designed to make explicit the analogy between functions and generic types: that is, generic types are essentially functions from types to a new type.

Where function declarations look like this:

\[ \text{function} ~ \text{f} ( \text{p}_1: \tau_1, \dots, \text{p}_1: \tau_1 ): \tau_r ; \]

A type declaration looks like:

\[ \text{type} ~ \tau [ \text{p}_1: k, \dots, \text{p}_1: k ]: u ; \]

Here, type parameters are analogous to value parameters, kinds are analogous to types, and the universe is analogous to the return type.

## Linear Types

Resource-aware type systems can remove large categories of errors that have caused endless security vulnerabilities in a simple way. This section describes the options.

This section begins with the motivation for linear types, then explains what linear types are and how they provide safety.

### Resources and Lifecycles

Consider a file handling API:

```
type File

File openFile(String path)

File writeString(File file, String content)

void closeFile(File file)
```

An experienced programmer understands the implicit lifecycle of the `File` object:

1. We create a `File` handle by calling `openFile`.
2. We write to the handle zero or more times.
3. We close the file handle by calling `closeFile`.

We can depict this graphically like this:

A graph with three nodes labeled ‘openFile’, ‘writeString’, and ‘close File’. There are four arrows: from ‘openFile’ to ‘writeString’, from ‘openFile’ to ‘closeFile’, from ‘writeString’ to itself, and from ‘writeString’ to ‘closeFile’.

But, crucially: this lifecycle is not enforced by the compiler. There are a number of erroneous transitions that we don’t consider, but which are technically possible:

The graph from the previous figure, with a new node labeled ‘leak’, and with four new arrows in red: one from ‘closeFile’ to itself labeled ‘double close’, one from ‘closeFile’ to ‘writeString’ labeled ‘use after close’, one from ‘openFile’ to ‘leak’ labeled ‘forgot to close’, and one from ‘writeString’ to ‘leak’ also labeled ‘forgot to close’.

These fall into two categories:

1. Leaks: we can forget to call `closeFile`, e.g.:

```
let file = openFile("hello.txt")
writeString(file, "Hello, world!")
// Forgot to close
```
2. Use-After-Close: and we can call `writeString` on a `File` object that has already been closed:

```
closeFile(file)
writeString(file, "Goodbye, world!");
```

And we can close the file handle after it has been closed:

```
closeFile(file);
closeFile(file);
```

In a short linear program like this, we aren’t likely to make these mistakes. But when handles are stored in data structures and shuffled around, and the lifecycle calls are separated across time and space, these errors become more common.

And they don’t just apply to files. Consider a database access API:

```
type Db

Db connect(String host)

Rows query(Db db, String query)

void close(Db db)
```

Again: after calling `close` we can still call `query` and `close`. And we can also forget to call `close` at all.

And — crucially — consider this memory management API:

```
type Pointer<T>

Pointer<T> allocate(T value)

T load(Pointer<T> ptr)

void store(Pointer<T> ptr, T value)

void free(Pointer<T> ptr)
```

Here, again, we can forget to call `free` after allocating a pointer, we can call `free` twice on the same pointer, and, more disastrously, we can call `load` and `store` on a pointer that has been freed.

Everywhere we have resources — types with an associated lifecycle, where they must be created, used, and destroyed, in that order — we have the same kind of errors: forgetting to destroy a value, or using a value after it has been destroyed.

In the context of memory management, pointer lifecycle errors are so disastrous they have their own names:

1. Double free errors.
2. Use-after-free errors.

Naturally, computer scientists have attempted to attack these problems. The traditional approach is called static analysis: a group of PhD’s will write a program that goes through the source code and performs various checks and finds places where these errors may occur.

Reams and reams of papers, conference proceedings, university slides, etc. have been written on the use of static analysis to catch these errors. But the problem with static analysis is threefold:

1. It is a moving target. While type systems are relatively fixed — i.e., the type checking rules are the same across language versions — static analyzers tend to change with each version, so that in each newer version of the software you get more and more sophisticated heuristics.
2. Like unit tests, it can usually show the presence of bugs, but not their absence. There may be false positives — code that is perfectly fine but that the static analyzer flags as incorrect — but more dangerous is the false negative, where the static analyzer returns an all clear on code that has a vulnerability.
3. Static analysis is an opaque pile of heuristics. Because the analyses are always changing, the programmer is not expected to develop a mental model of the static analyzer, and to write code with that model in mind. Instead, they are expected to write the code they usually write, then throw the static analyzer at it and hope for the best.

What we want is a way to solve these problems that is static and complete. Static in that it is a fixed set of rules that you can learn once and remember, like how a type system works. Complete in that is has no false negatives, and every lifecycle error is caught.

And, above all: we want it to be simple, so it can be wholly understood by the programmer working on it.

So, to summarize our requirements:

1. Correctness Requirement: We want a way to ensure that resources are used in the correct lifecycle.
2. Simplicity Requirement: We want that mechanism to be simple, that is, a programmer should be able to hold it in their head. This rules out complicated solutions involving theorem proving, SMT solvers, symbolic execution, etc.
3. Staticity Requirement: We want it to be a fixed set of rules and not an ever changing pile of heuristics.

All these goals are achievable: the solution is linear types.

### Linear Types

This section describes what linear types are, how they provide the safety properties we want, and how we can relax some of the more onerous restrictions so as to increase programmer ergonomics while retaining safety.

A type is a set of values that share some structure. A linear type is a type whose values can only be used once. This restriction may sound onerous (and unrelated to the problems we want to solve), but it isn’t.

A linear type system can be defined with just two rules:

1. Linear Universe Rule: in a linear type system, the set of types is divided into two universes: the free universe, containing types which can be used any number of times (like booleans, machine sized integers, floats, structs containing free types, etc.); and the linear universe, containing linear types, which usually represent resources (pointers, file handles, database handles, etc.).

Types enter the linear universe in one of two ways:

1. By fiat: a type can simply be declared linear, even though it only contains free types. We’ll see later why this is useful.

```
// `LInt` is in the `Linear` universe,
// even if `Int` is in the `Free` universe.
type LInt: Linear = Int
```
2. By containment: linear types can be thought of as being “viral”. If a type contains a value of a linear type, it automatically becomes linear.

So, if you have a linear type `T`, then a tuple `(a, b, T)` is linear, a struct like:

```
struct Ex {
    a: A;
    b: B;
    c: Pair<T, A>;
}
```

is linear because the slot `c` contains a type which in turn contains `T`. A union or enum where one of the variants contains a linear type is, unsurprisingly, linear. You can’t sneak a linear type into a free type.

The virality of linear types ensures that you can’t escape linearity by accident.
2. Use-Once Rule: a value of a linear type must be used once and only once. Not can: must. It cannot be used zero times. This can be enforced entirely at compile time through a very simple set of checks.

To understand what “using” a linear value means, let’s look at some examples. Suppose you have a function `f` that returns a value of a linear type `L`.

Then, the following code:

```
{
    let x: L := f();
}
```

is incorrect. `x` is a variable of a linear type, and it is used zero times. The compiler will complain that `x` is being silently discarded.

Similarly, if you have:

```
{
    f();
}
```

The compiler will complain that the return value of `f` is being silently discarded, which you can’t do to a linear type.

If you have:

```
{
    let x: L := f();
    g(x);
    h(x);
}
```

The compiler will complain that `x` is being used twice: it is passed into `g`, at which point is it said to be consumed, but then it is passed into `h`, and that’s not allowed.

This code, however, passes: `x` is used once and exactly once:

```
{
    let x: L := f();
    g(x);
}
```

“Used” does not, however, mean “appears once in the code”. Consider how `if` statements work. The compiler will complain about the following code, because even though `x` appears only once in the source code, it is not being “used once”, rather it’s being used — how shall I put it? 0.5 times?:

```
{
    let x: L := f();
    if (cond) {
        g(x);
    } else {
        // Do nothing.
    }
}
```

`x` is consumed in one branch but not the other, and the compiler isn’t happy. If we change the code to this:

```
{
    let x: L := f();
    if (cond) {
        g(x);
    } else {
        h(x);
    }
}
```

Then we’re good. The rule here is that a variable of a linear type, defined outside an `if` statement, must be used either zero times in that statement, or exactly once in each branch.

A similar restriction applies to loops. We can’t do this:

```
{
    let x: L := f();
    while (true) {
        g(x);
    }
}
```

Because even though `x` appears once, it is used more than once: it is used once in each iteration. The rule here is that a variable of a linear type, defined outside a loop, cannot appear in the body of the loop.

That’s it. That’s all there is to it. We have a fixed set of rules, and they’re so brief you can learn them in a few minutes. So we’re satisfying the simplicity and staticity requirements listed in the previous section.

But do linear types satisfy the correctness requirement? In the next section, we’ll see how linear types make it possible to enforce that a value should be used in accordance to a lifecycle.

### Linear Types and Safety

Let’s consider a linear file system API. We’ll use a vaguely C++ like syntax, but linear types are denoted by an exclamation mark after their name.

The API looks like this:

```
type File!

File! openFile(String path)

File! writeString(File! file, String content)

void closeFile(File! file)
```

The `openFile` function is fairly normal: takes a path and returns a linear `File!` object.

`writeString` is where things are different: it takes a linear `File!` object (and consumes it), and a string, and it returns a “new” linear `File!` object. “New” is in quotes because it is a fresh linear value only from the perspective of the type system: it is still a handle to the same file. But don’t think about the implementation too much: we’ll look into how this is implemented later.

`closeFile` is the destructor for the `File!` type, and is the terminus of the lifecycle graph: a `File!` enters and does not leave, and the object is disposed of. Let’s see how linear types help us write safe code.

Can we leak a `File!` object? No:

```
let file: File! := openFile("sonnets.txt");
// Do nothing.
```

The compiler will complain: the variable `file` is used zero times. Alternatively:

```
let file: File! := openFile("sonnets.txt");
writeString(file, "Devouring Time, blunt thou the lion’s paws, ...");
```

The return value of `writeString` is a linear `File!` object, and it is being silently discarded. The compiler will whine at us.

We can strike the “leak” transitions from the lifecycle graph:

A graph with three nodes labeled ‘openFile’, ‘writeString’, and ‘close File’. There are four black arrows: from ‘openFile’ to ‘writeString’, from ‘openFile’ to ‘closeFile’, from ‘writeString’ to itself, and from ‘writeString’ to ‘closeFile’. There are two red arrows: one from ‘closeFile’ to ‘writeString’ labeled ‘use after close’, and one from ‘closeFile’ to itself labeled ‘double close’.

Can we close a file twice? No:

```
let file: File! := openFile("test.txt");
closeFile(file);
closeFile(file);
```

The compiler will complain that you’re trying to use a linear variable twice. So we can strike the “double close” erroneous transition from the lifecycle graph:

A graph with three nodes labeled ‘openFile’, ‘writeString’, and ‘close File’. There are four black arrows: from ‘openFile’ to ‘writeString’, from ‘openFile’ to ‘closeFile’, from ‘writeString’ to itself, and from ‘writeString’ to ‘closeFile’. There is one red arrow: from ‘closeFile’ to ‘writeString’ labeled ‘use after close’.

And you can see where this is going. Can we write to a file after closing it? No:

```
let file: File! := openFile("test.txt");
closeFile(file);
let file2: File! := writeString(file, "Doing some mischief.");
```

The compiler will, again, complain that we’re consuming `file` twice. So we can strike the “use after close” transition from the lifecycle graph:

A graph with three nodes labeled ‘openFile’, ‘writeString’, and ‘close File’. There are four arrows: from ‘openFile’ to ‘writeString’, from ‘openFile’ to ‘closeFile’, from ‘writeString’ to itself, and from ‘writeString’ to ‘closeFile’.

And we have come full circle: the lifecycle that the compiler enforces is exactly, one-to-one, the lifecycle that we intended.

There is, ultimately, one and only one way to use this API such that the compiler doesn’t complain:

```
let f: File! := openFile("rilke.txt");
let f_1: File! := writeString(f, "We cannot know his legendary head\n");
let f_2: File! := writeString(f_1, "with eyes like ripening fruit. And yet his torso\n");
...
let f_15: File! := writeString(f_14, "You must change your life.");
closeFile(f_15);
```

Note how the file value is “threaded” through the code, and each linear variable is used exactly once.

And now we are three for three with the requirements we outlined in the previous section:

1. Correctness Requirement: Is it correct? Yes: linear types allow us to define APIs in such a way that the compiler enforces the lifecycle perfectly.
2. Simplicity Requirement: Is it simple? Yes: the type system rules fit in a napkin. There’s no need to use an SMT solver, or to prove theorems about the code, or do symbolic execution and explore the state space of the program. The linearity checks are simple: we go over the code and count the number of times a variable appears, taking care to handle loops and `if` statements correctly. And also we ensure that linear values can’t be discarded silently.
3. Staticity Requirement: Is it an ever-growing, ever-changing pile of heuristics? No: it is a fixed set of rules. Learn it once and use it forever.

And does this solution generalize? Let’s consider a linear database API:

```
type Db!

Db! connect(String host)

Pair<Db!, Rows> query(Db! db, String query)

void close(Db! db)
```

This one’s a bit more involved: the `query` function has to return a tuple containing both the new `Db!` handle, and the result set.

Again: we can’t leak a database handle:

```
let db: Db! := connect("localhost");
// Do nothing.
```

Because the compiler will point out that `db` is never consumed. We can’t `close` a database handle twice:

```
let db: Db! := connect("localhost");
close(db);
close(db); // error: `db` consumed again.
```

Because `db` is used twice. Analogously, we can’t query a database once it’s closed:

```
let db: Db! := connect("localhost");
close(db);
let (db1, rows): Pair<Db!, Rows> := query(db, "SELECT ...");
close(db); // error: `db` consumed again.
```

For the same reason. The only way to use the database correctly is:

```
let db: Db! := connect("localhost");
let (db1, rows): Pair<Db!, Rows> := query(db, "SELECT ...");
// Iterate over the rows or some such.
close(db1);
```

What about manual memory management? Can we make it safe? Let’s consider a linear pointer API, but first, we have to introduce some new notation. When you have a generic type with generic type parameters, in a regular language you might declare it like:

```
type T<A, B, C>
```

Here, we also have to specify which universe the parameters and the resulting type belong to. Remember: there are two universes: free and linear. So for example we can write:

```
type T<A: Free, B: Free>: Free
type U!<A: Linear>: Linear
```

But sometimes we want a generic type to accept type arguments from any universe. In that case, we use `Type`:

```
type Pair<L: Type, R: Type>: Type;
```

This basically means: the type parameters `L` and `R` can be filled with types from either universe, and the universe that `Pair` belongs to is determined by said arguments:

1. If `A` and `B` are both `Free`, then `Pair` is `Free`.
2. If either one of `A` and `B` are `Linear`, then `Pair` is `Linear`.

Now that we’re being explicit about universes, we can drop the exclamation mark notation.

Here’s the linear pointer API:

```
type Pointer<T: Type>: Linear;

generic <T: Type>
Pointer<T> allocate(T value)

generic <T: Type>
T deallocate(Pointer!<T> ptr)

generic <T: Free>
Pair<Pointer<T>, T> load(Pointer<T> ptr)

generic <T: Free>
Pointer<T> store(Pointer<T> ptr, T value)
```

This is more involved than previous examples, and uses new notation, so let’s break it down declaration by declaration.

1. First, we declare the `Pointer` type as a generic type that takes a parameter from any universe, and belongs to the `Linear` universe by fiat. That is: even if `T` is `Free`, `Pointer ` will be `Linear`.

```
type Pointer<T: Type>: Linear;
```
2. Second, we define a generic function `allocate`, that takes a value from either universe, allocates memory for it, and returns a linear pointer to it.

```
generic <T: Type>
Pointer<T> allocate(T value)
```
3. Third, we define a slightly unusual `deallocate` function: rather than returning `void`, it takes a pointer, dereferences it, deallocates the memory, and returns the dereferenced value:

```
generic <T: Type>
T deallocate(Pointer!<T> ptr)
```
4. Fourth, we define a generic function specifically for pointers that contain free values: it takes a pointer, dereferences it, and returns a tuple with both the pointer and the dereferenced free value.

```
generic <T: Free>
(Pointer<T>, T) load(Pointer<T> ptr)
```

Why does `T` have to belong to the `Free` universe? Because otherwise we could write code like this:

```
// Suppose that `L` is a linear type.
let p: Pointer<L> := allocate(...);
let (p2, val): Pair<Pointer<L>, L> := load(p);
let (p3, val2): Pair<Pointer<L>, L> := load(p2);
```

Here, we’ve allocated a pointer to a linear value, but we’ve loaded it from memory twice, effectively duplicating it. This obviously should not be allowed. So the type parameter `T` is constrained to take only values of the `Free` universe, which can be copied freely any number of times.
5. Fifth, we define a generic function, again for pointers that contain free values. It takes a pointer and a free value, and stores that value in the memory allocated by the pointer, and returns the pointer again for reuse:

```
generic <T: Free>
Pointer<T> store(Pointer<T> ptr, T value)
```

Again: why can’t this function be defined for linear values? Because then we could write:

```
// Suppose `L` is a linear type, and `a` and b`
// are variables of type `L`.
let p1: Pointer<L> := allocate(a);
let p2: Pointer<L> := store(p1, b);
let l: L := deallocate(p2);
```

What happens to `a`? It is overwritten by `b` and lost. For values in the `Free` universe this is no problem: who cares if a byte is overwritten? But we can’t overwrite linear values – like database handles and such – because the they would be leaked.

It is trivial to verify the safety properties. We can’t leak memory, we can’t deallocate twice, and we can’t read or write from and to a pointer after it has been deallocated.

### What Linear Types Provide

Linear types give us the following benefits:

1. Manual memory management without memory leaks, use-after-`free`, double `free` errors, garbage collection, or any runtime overhead in either time or space other than having an allocator available.
2. More generally, we can manage any resource (file handles, socket handles, etc.) that has a lifecycle in a way that prevents:

1. Forgetting to dispose of that resource (e.g.: leaving a file handle open).
2. Disposing of the resource twice (e.g.: trying to free a pointer twice).
3. Using that resource after it has been disposed of (e.g.: reading from a closed socket).

All of these errors are prevented statically, again without runtime overhead.
3. In-place optimization: the APIs we have looked at resemble functional code. We write code “as if” we were creating and returning new objects with each call, while doing extensive mutations under the hood. This gives us the benefits of functional programming (referential transparency and equational reasoning) with the performance of imperative code that mutates data wildly.
4. Safe concurrency. A value of a linear type, by definition, has only one owner: we cannot duplicate it, therefore, we cannot have multiple owners across threads. So imperative mutation is safe, since we know that no other thread can write to our linear value while we work with it.
5. Capability-based security: suppose we want to lock down access to the terminal. We want there to be only one thread that can write to the terminal at a time. Furthermore, code that wants to write to the terminal needs permission to do so.

We can do this with linear types, by having a linear `Terminal` type that represents the capability of using the terminal. Functions that read and write from and to the terminal need to take a `Terminal` instance and return it. We’ll discuss capability based security in greater detail in a future section.

### The Trust Boundary

So far we have only seen the interfaces of linear APIs. What about the implementations?

Here’s the linear file access API, using the universe notation instead of the exclamation mark notation to indicate linear types:

```
type File: Linear

File openFile(String path)

File writeString(File file, String content)

void closeFile(File file)
```

How does `writeString` respect linearity? Clearly, it is consuming a `File` handle, then returning it again. Does it internally close and reopen the file handle?

The answer involves the concept of a trust boundary: inside the `File` type is a plain old fashioned (unrestricted, non-linear) file handle, like so:

```
struct File: Linear {
  handle: int;
}
```

The `openFile` function looks like this:

```
extern int fopen(char* filename, char* mode)

File openFile(String path) {
    let ptr: int = fopen(as_c_string(filename), "r");
    return File(handle => ptr);
}
```

`openFile` calls `fopen`, which returns a file handle as an ordinary, free integer. Then we wrap it in a nice linear type and return it to the client.

Write string is where the magic happens:

```
extern int fputs(char* string, int fp)

File writeString(File file, String content) {
  let { handle: int } := file;
  fputs(as_c_string(content), handle);
  return File(handle => handle);
}
```

The `let` statement uses destructuring syntax: it “explodes” a linear struct into a set of variables.

Why do we need destructuring? Imagine if we had a struct with two linear fields:

```
struct Pair {
  x: L1;
  y: L2;
}
```

And we wanted to write code like:

```
let p: Pair := make_pair();
let x: L1 := p.x;
```

This is a big problem. `p` is being consumed by the `p.x` expression. But what happens to the `y` field in the `p` struct? It is leaked: we can’t afterwards write `p.y` because `p` has been consumed.

Austral has special rules around accessing the fields of a struct to prevent this kind of situation. And the destructuring syntax we’re using allows us to take a struct, dismantle it into its constituent fields (linear or otherwise), then transform the values of those fields and/or put them back together.

This is what we’re doing in `openFile`: we break up the `File` value into its constituent fields (here just `handle`), which consumes it. Then we call `fputs` on the non-linear handle, then, we construct a new instance of `File` that contains the unchanged file handle.

From the compiler’s perspective, the `File` that goes in is distinct from the `File` that goes out and linearity is respected. Internally, the non-linear handle is the same.

Finally, `closeFile` looks like this:

```
extern int fclose(int fp)

void closeFile(File file) {
  let { handle: int } := file;
  fclose(handle);
}
```

The `file` variable is consumed by being destructured. Then we call `fclose` on the underlying file handle.

And there you have it: linear interface, non-linear interior. Inside the trust boundary, there is a light amount of unsafe FFI code (ideally, carefully vetted and tested). Outside, there is a linear interface, which can only be used correctly.

### Affine Types

Affine types are a “weakening” of linear types. Where linear types are “use exactly once”, affine types are “use at most once”. Values can be silently discarded.

This requires a way to associate destructors to affine types. Then, at the end of a block, the compiler will look around for unconsumed affine values, and insert calls to their destructors.

There are two benefits to affine types:

1. First, by using implicit destructors, the code is less verbose.
2. Secondly (and this will be expanded upon in the next section), affine types are compatible with traditional (C++ or Java-style) exception handling, while linear types are not.

But there are downsides:

1. Sometimes, you don’t want values to be silently discarded.
2. There are implicit function calls (destructor calls are inserted by the compiler at the end of blocks).
3. Exception handling involves a great deal of complexity, and is not immune to e.g. the “double throw” problem.

### Borrowing

Returning tuples from every function and threading linear values through the code is very verbose.

It is also often a violation of the principle of least privilege: linear values, in a sense, have “uniform permissions”. If you have a linear value, you can destroy it. Consider the linear pointer API described above: the `load` function could internally deallocate the pointer and allocate it again.

We wouldn’t expect that to happen, but the whole point is to be defensive. We want the language to give us some guarantees: if a function should only be allowed to read from a linear value, but not deallocate it or mutate its interior, we want a way to represent that.

Borrowing is stolen lock, stock, and barrel from Rust. It advanced programming ergonomics by allowing us to treat a linear value as free within a delineated context. And it allows us to degrade permissions: we can pass read-only references to a linear value to functions that should only be able to read from that value, we can pass mutable references to a linear value to functions that should only be able to read from, and mutate, that value, without destroying it. Passing the linear value itself is the highest level of permissions: it allows the receiving function to do anything whatever with that value, by taking complete ownership of it.

### The Cutting Room Floor

Universes are not the only way to implement linear types. There are three ways:

1. Linearity via arrows, as in the linear types extension of the GHC compiler for Haskell. This is the closest to Girard’s linear logic.
2. Linearity via kinds, which involves partitioning the set of types into two universes: a universe of unrestricted values which can be copied freely, such as integers, and a universe of restricted or linear types.
3. Rust’s approach, which is a sophisticated, fine-grained ownership tracking scheme.

In my opinion, linearity via arrows is best suited to an ML family language with single-parameter functions.

Rust’s ownership tracking scheme allows programmers to write code that looks quite ordinary, frequently using values multiple times, while retaining “linear-like” properties. Ordinarily the restrictions show up when compilation fails.

The Rust approach prioritizes programmer ergonomics, but it has a downside: the ownership tracking scheme is not a fixed algorithm that is set in stone in a standards document, which programmers are expected to read in order to write code. Rather, it is closer to static analysis in that it is a collection of rules, which evolve with the language, generally in the direction of improving ergonomics and allowing programmers to focus on the problem at hand rather than bending the code to fit the ownership scheme. Consequently, Rust programmers often describe a learning curve with a period of “fighting the borrow checker”, until they become used to the rules.

Compare this with type checking algorithms: type checking is a simple, inductive process, so much so that programmers effectively run the algorithm while reading code to understand how it behaves. It often does not need documenting because it is obvious whether or not two types are equal or compatible, and the “warts” are generally in the area of implicit integer or float type conversions in arithmetic, and subtyping where present.

There are many good reasons to prefer the Rust approach:

1. Programmers care a great deal about ergonomics. The dangling else is a feature of C syntax that has caused many security vulnerabilities. Try taking this away from programmers: they will kick and scream about the six bytes they’re saving on each `if` statement.
2. Allowing programmers to write code that they’re used to helps with onboarding new users. It is generally not realistic to tell programmers to “read the spec” to learn a new language.
3. By putting the complexity in the language, application code becomes simpler: programmers can focus on solving the problem at hand, and the compiler, ever helpful, will do its best to “prove around it”, that is, the compiler bends to the programmer’s code and tries to interpret it as best it can, rather than the programmer bending to the language’s rules.
4. Since destructors are automatically inserted, the code is less verbose.
5. Finally, Rust’s approach is compatible with exception handling, which the language provides: panics unwind the stack and call destructors automatically. Austral, because of its emphasis on implementation simplicty, has much more verbose code around error handling.

Austral takes the approach that a language should be simple enough that it can be understood entirely by a single person reading the specification. Consequently, a programmer should be able to read a brief set of linearity checker rules, and afterwards be able to write code without fighting the system, or failing to understand how or why some code compiles.

In short: we sacrifice terseness and programmer ergonomics for simplicity. Simple to learn, simple to understand, simple to reason about.

To do this, we choose linearity via kinds, because it provides the simplest way to implement a linear type system. The set of unrestricted types is called the “free universe” and is denoted `Free` (because `Unrestricted` takes too much typing) and the set of restricted or linear types is called the “linear universe” and is denoted `Linear`.

Another feature that was considered and discarded is LinearML’s concept of observer types, a lightweight alternative to read-only references that has the benefit of not requiring regions, but has the drawback that they can’t be stored in data structures.

### Conclusion

In the next section, we explain the rationale for Austral’s approach to error handling, why linear types are incompatible with traditional exception handling, what affine types are, and how our preferred error handling scheme impacts the choice of linear types over affine types.

Afterwards, we describe capability-based security, and how linear types allow us to implement capabilities.

## Error Handling

On July 3, 1940, as part of Operation Catapult, Royal Air Force pilots bombed the ships of the French Navy stationed off Mers-el-Kébir to prevent them falling into the hands of the Third Reich.

This is Austral’s approach to error handling: scuttle the ship without delay.

In software terms: programs should crash at the slightest contract violation, because recovery efforts can become attack vectors. You must assume, when the program enters an invalid state, that there is an adversary in the system. For failures — as opposed to errors — you should use `Option` and `Result` types.

This section describes the rationale for Austral’s approach to error handling. We begin by describing what an error is, then we survey different error handling strategies. Then we explain how those strategies impinge upon a linear type system.

### Categorizing Errors

“Error” is a broad term. Following Sutter and the Midori error model, we divide errors into the following categories:

1. Physical Failure: Pulling the power cord, destroying part of the hardware.
2. Abstract Machine Corruption: A stack overflow.
3. Contract Violations: Due to a mistake the code, the program enters an invalid state. This includes:

1. An arithmetic operation leads to integer overflow or underflow (the contract here is that operands should be such that the operation does not overflow).
2. Integer division by zero (the contract is the divisor should be non zero).
3. Attempting to access an array with an index outside the array’s bounds (the contract is that the index should be within the length of the array).
4. Any violation of a programmer-defined precondition, postcondition, assertion or invariant.

These errors are bugs in the program. They are unpredictable, often happen very rarely, and can open the door to security vulnerabilities.
4. Memory Allocation Failure: `malloc` returns `null`, essentially. This gets its own category because allocation is pervasive, especially in higher-level code, and allocation failure is rarely modeled at the type level.
5. Failure Conditions. “File not found”, “connection failed”, “directory is not empty”, “timeout exceeded”.

We can pare down what we have to care about:

1. Physical Failure: Nothing can be done. Although it is possible to write software that persists data in a way that survives e.g. power failure. Databases are often implemented in this way.
2. Abstract Machine Corruption. The program should terminate. At this point the program is in a highly problematic state and any attempt at recovery is likely counterproductive and possibly enables security vulnerabilities.
3. Memory Allocation Failure: Programs written in a functional style often rely on memory allocation at arbitrary points in the program execution. Allocation failure in a deeply nested function thus presents a problem from an error-handling perspective: if we’re using values to represent failures, then every function that allocates has to return an `Optional` type or equivalent, and this propagates up through every client of that function.

Nevertheless, returning an `Optional` type (or equivalent) on memory allocation is sufficient. It places a minor burden on the programmer, who has to explicitly handle and propagate these failures, but this burden can be eased by refactoring the program so that most allocations happen in the same area in time and space.

This type of refactoring can improve performance, as putting allocations together will make it clear when there is an opportunity to replace \(n\) allocations of an object of size \(k\) bytes with a single allocation of an array of \(n \times k\) bytes.

A common misconception is that checking for allocation failure is pointless, since a program might be terminated by the OS if memory is exhausted, or because platforms that implement memory overcommit (such as Linux) will always return a pointer as though allocation had succeeded, and crash when writing to that pointer. This is a misconception for the following reasons:

1. Memory overcommit on Linux can be turned off.
2. Linux is not the only platform.
3. Memory exhaustion is not the only situation where allocation might fail: if memory is sufficiently fragmented that a chunk of the requested size is not available, allocation will fail.
4. Failure Conditions. These errors are recoverable, in the sense that we want to catch them and do something about them, rather than crash. Often this involves prompting the user for corrected information, or otherwise informing the user of failure, e.g. if trying to open a file on a user-provided path, or trying to connect to a server with a user-provided host and port.

Consequently, these conditions should be represented as values, and error handling should be done using standard control flow.

Values that represent failure should not be confused with “error codes” in languages like C. “Error codes or exceptions” is a false dichotomy. Firstly, strongly-typed result values are better than brittle integer error codes. Secondly, an appropriate type system lets us have e.g. `Optional` or `Result` types to better represent the result of fallible computations. Thirdly, a linear type system can force the programmer to check result codes, so the argument that error codes are bad because programmers might forget to check them is obviated.

That takes care of four of five categories. There’s one left: what do we do about contract violations? How we choose to handle this is a critical question in the design of any programming language.

### Error Handling for Contract Violations

There are essentially three approaches, from most to least brutal:

1. Terminate Program: When a contract violation is detected, terminate the entire program. No cleanup code is executed. Henceforth “TPOE” for “terminate program on error”.
2. Terminate Thread: When a contract violation is detected, terminate the current thread or task. No cleanup code is executed, but the parent thread will observe the failure, and can decide what to do about it. Henceforth “TTOE” for “terminate thread/task on error”.
3. Traditional Exception Handling: Raise an exception/panic/abort (pick your preferred terminology), unwind the stack while calling destructors. This is the approach offered by C++ and Rust, and it integrates with RAII. Henceforth “REOE” for “raise exception on error”.

#### Terminate Program

The benefit of this approach is simplicity and security: from the perspective of security vulnerabilities, terminating a program outright is the best thing to do,

If the program is the target of an attacker, cleanup or error handling code might inadvertently allow an attacker to gain access to the program. Terminating the program without executing any cleanup code at all will prevent this.

The key benefit here besides security is simplicty. There is nothing simpler than calling `_exit(-1)`. The language is simpler and easier to understand. The language also becomes simpler to implement. The runtime is simpler. Code written in the language is simpler to understand and reason about: there are no implicit function calls, no surprise control flow, no complicated unwinding schemes.

There are, however, a number of problems:

1. Resource Leaks: Depending on the program and the operating system, doing this might leak resources.

If the program only allocates memory and acquires file and/or socket handles, then the operating system will likely be able to garbage-collect all of this on program termination. If the program uses more exotic resources, such as locks that survive program termination, then the system as a whole might enter an unusable state where the program cannot be restarted (since the relevant objects are still locked), and human intervention is needed to delete those surviving resources.

For example, consider a build. The program might use a linear type to represent the lifecycle of the directory that stores build output. A `create` function creates the directory if it does not already exist, a corresponding `destroy` function deletes the directory and its contents.

If the program is terminated before the `destroy` function is called, running the program again will fail in the call to `create` because the directory already exists.

Additionally, in embedded systems without an operating system, allocated resources that are not cleaned up by the program will not be reclaimed by anything.
2. Testing: In a testing framework, we often want to test that a function will not fail on certain inputs, or that it will definitely fail on certain others. For example, we may want to test that a function correctly aborts on values that don’t satisfy some precondition.

JUnit, for example, provides `assertThrows` for this purpose.

If contract violations terminate the program, then the only way to write an `assertAborts` function is to fork the process, run the function in the child process, and have the parent process observe whether or not it crashes. This is expensive. And if we don’t implement this, a contract violation will crash the entire unit testing process.

This is a problem because, while we are implicitly “testing” for contract violations whenever a function is called, it is still good to have explicit unit tests that we can point to in order to prove that a function does indeed reject certain kinds of values.
3. Exporting Code: When exporting code through the FFI, terminating the program on contract violations is less than polite.

If we write a library and export its functionality through the FFI so it is accessible from other languages, terminating the process from that library will crash everything else in the address space. All the code that uses our library can potentially crash on certain obscure error conditions, a situation that would be extremely difficult to debug due to its crossing language boundaries.

The option of forking the process, in this context, is prohibitively expensive.

#### Terminate Thread on Error

Terminating the thread where the contract violation happened, rather than the entire process, gives us a bit more recoverability and error reporting ability, at the cost of safety and resource leaks.

The benefit is that calling a potentially-failing function safely “only” requires spawning a new thread. While expensive (and not feasible in a function that might be called thousands of times a second) this is significantly cheaper than forking the process.

A unit testing library could plausibly do this to implement assertions that a program does or does not violate any conditions. Condition failures could then be reported within the unit testing framework as just another failing test, without crashing the entire process or requiring expensive forking of the process.

If we split programs into communicating threads, the failure of one thread could be detected by its parent, and reported to the user before the program is terminated.

This is important: the program should still be terminated. Terminating the thread, rather than the entire program, is inteded to allow more user-friendly and complete reporting of failures, not as a general purpose error recovery mechanism.

For example, in the context of a webserver, we would not want to restart failed server threads. Since cleanup code is not executed on thread termination, a long running process which restarts failing threads will eventually run out of memory or file handles or other resources.

An attacker that knows the server does this could execute a denial of service attack by forcing a previously undetected contract violation.

#### Raise Exception on Error

This is traditional exception handling with exception values, stack unwinding, and destructors. C++ calls this throwing an exception. Rust and Go call it panicking. The only technical difference between C++ exception handling and Go/Rust panics is that C++ exceptions can be arbitrarily sized objects (and consequently throwing requires a memory allocation) while in Go and Rust panics can at most carry an error message. Ada works simil

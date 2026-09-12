---
source_url: https://www.cs.cmu.edu/~aldrich/papers/ecoop14-tsls.pdf
ingested: 2026-09-12
sha256: 149253da7e69ef6ed57f9eccf8729f5fed8af4232ea0d982ca6e987edcb0f15f
---
# Safely Composable Type-Specific Languages

## Safely Composable Type-Specific Languages

Cyrus Omar, Darya Kurilova, Ligia Nistor, Benjamin Chung, and Alex Potanin, 1and Jonathan Aldrich Carnegie Mellon University and Victoria University of Wellington 1 {comar, darya, lnistor, bwchung, aldrich}@cs.cmu.edu and alex@ecs.vuw.ac.nz 1

Abstract. Programming languages often include specialized syntax for com mon datatypes (e.g. lists) and some also build in support for specific special ized datatypes (e.g. regular expressions), but user-defined types must use general purpose syntax. Frustration with this causes developers to use strings, rather than structured data, with alarming frequency, leading to correctness, performance, security, and usability issues. Allowing library providers to modularly extend a language with new syntax could help address these issues. Unfortunately, prior mechanisms either limit expressiveness or are not safely composable: individ ually unambiguous extensions can still cause ambiguities when used together. We introduce type-specific languages (TSLs): logic associated with a type that determines how the bodies of generic literals, able to contain arbitrary syntax, are parsed and elaborated, hygienically. The TSL for a type is invoked only when a literal appears where a term of that type is expected, guaranteeing non interference. We give evidence supporting the applicability of this approach and formally specify it with a bidirectionally typed elaboration semantics for the Wyvern programming language. Keywords: extensible languages; parsing; bidirectional typechecking; hygiene

### 1 Motivation

Many data types can be seen, semantically, as modes of use of general purpose product and sum types. For example, lists can be seen as recursive sums by observing that a list can either be empty, or be broken down into a product of the head element and the tail, another list. In an ML-like functional language, sums are exposed as datatypes and products as tuples and records, so list types can be defined as follows:

datatype ’a list = Nil | Cons of ’a * ’a list

In class-based object-oriented language, objects can be seen as products of their in stance data and classes as the cases of a sum type [9]. In low-level languages, like C, structs and unions expose products and sums, respectively. By defining user-defined types in terms of these general purpose constructs, we im mediately benefit from powerful reasoning principles (e.g. induction), language support (e.g. pattern matching) and compiler optimizations. But these semantic benefits often come at a syntactic cost. For example, few would claim that writing a list of numbers as a sequence of Cons cells is convenient:

Cons(1, Cons(2, Cons(3, Cons(4, Nil))))

2 Omar, Kurilova, Nistor, Chung, Potanin, Aldrich

Lists are a common data structure, so many languages include literal syntax for in troducing them, e.g. [1, 2, 3, 4]. This syntax is semantically equivalent to the general purpose syntax shown above, but brings cognitive benefits both when writing and read ing code by focusing on the content of the list, rather than the nature of the encoding. Using terminology from Green’s cognitive dimensions of notations [8], it is more terse, visible and maps more closely to the intuitive notion of a list. Stoy, in discussing the value of good notation, writes [31]: A good notation thus conceals much of the inner workings behind suitable abbreviations, while allowing us to consider it in more detail if we require: matrix and tensor notations provide further good examples of this. It may be summed up in the saying: “A notation is important for what it leaves out.” Although list, number and string literals are nearly ubiquitous features of modern languages, some languages provide specialized literal syntax for other common col lections (like maps, sets, vectors and matrices), external data formats (like XML and JSON), query languages (like regular expressions and SQL), markup languages (like HTML and Markdown) and many other types of data. For example, a language with built-in notation for HTML and SQL, supporting type safe splicing via curly braces, might define:

1 let webpage : HTML = Results for {keyword} 
2 {to_list_items(query(db, 
3 SELECT title, snippet FROM products WHERE {keyword} in title))} 
4 

as shorthand for:

1 let webpage : HTML = HTMLElement(Dict.empty(), [BodyElement(Dict.empty(), 
2 [H1Element(Dict.empty(), [TextNode("Results for " + keyword)]), 
3 ULElement((Dict.add Dict.empty() ("id","results")), to_list_items(query(db, 
4 SelectStmt(["title", "snippet"], "products", 
5 [WhereClause(InPredicate(StringLit(keyword), "title"))]))))])]) 

When general-purpose notation like this is too cognitively demanding for comfort, but a specialized notation as above is not available, developers turn to run-time mecha nisms to make constructing data structures more convenient. Among the most common strategies in these situations, no matter the language paradigm, is to simply use a string representation, parsing it at run-time:

1 let webpage : HTML = parse_html(" Results for "+keyword+" 
2 " + to_string(to_list_items(query(db, parse_sql( 
3 "SELECT title, snippet FROM products WHERE ’"+keyword+"’ in title")))) + 
4 " ") 

Though recovering some of the notational convenience of the literal version, it is still more awkward to write, requiring explicit conversions to and from structured rep resentations (parse_html and to_string, respectively) and escaping when the syntax of the data language interferes with the syntax of string literals (line 2). Such code also causes a number of problems that go beyond cognitive load. Because parsing occurs at run-time, syntax errors will not be discovered statically, causing potential run-time errors in production scenarios. Run-time parsing also incurs performance overhead, particularly relevant when code like this is executed often (as on a heavily-trafficked website). But the most serious issue with this code is that it is highly insecure: it is

Safely Composable Type-Specific Languages 3 vulnerable to cross-site scripting attacks (line 1) and SQL injection attacks (line 3). For example, if a user entered the keyword ’; DROP TABLE products --, the entire product database could be erased. These attack vectors are considered to be two of the most serious security threats on the web today [26]. Although developers are cautioned to sanitize their input, it can be difficult to verify that this was done correctly throughout a codebase. The best way to avoid these problems today is to avoid strings and other sim ilar conveniences and insist on structured representations. Unfortunately, situations like this, where maintaining strong correctness, performance and security guarantees entails significant syntactic overhead, causing developers to turn to less structured solutions that are more convenient, are quite common (as we will discuss in Sec. 5). Adding new literal syntax into a language is generally considered to be the respon sibility of the language’s designers. This is largely for technical reasons: not all syn tactic forms can unambiguously coexist in the same grammar, so a designer is needed to decide which syntactic forms are available, and what their semantics should be. For example, conventional notations for sets and maps are both delimited by curly braces. When Python introduced set literals, it chose to distinguish them based on whether the literal contained only values (e.g. {3}), or key-value pairs ({"x": 3}). But this causes an ambiguity with the syntactic form { } – should it mean an empty set or an empty map (called a dictionary in Python)? The designers of Python avoided the ambiguity by choosing the latter interpretation (in this case, for backwards compatibility reasons). Were this power given to library providers in a decentralized, unconstrained man ner, the burden of resolving ambiguities would instead fall on developers who happened to import conflicting extensions. Indeed, this is precisely the situation with SugarJ [6] and other extensible languages generated by Sugar* [7], which allow library providers to extend the base syntax of the host language with new forms in a relatively uncon strained manner. These new forms are imported transitively throughout a program. To resolve syntactic ambiguities that arise, clients must manually augment the composed grammar with new rules that allow them to choose the correct interpretation explic itly. This is both difficult to do, requiring a reasonably thorough understanding of the underlying parser technology (in Sugar*, generalized LR parsing) and increases the cognitive load of using the conflicting notations (e.g. both sets and maps) together be cause disambiguation tokens must be used. These kinds of conflicts occur in a variety of circumstances: HTML and XML, different variants of SQL, JSON literals and maps, or differing implementations (“desugarings”) of the same syntax (e.g. two regular ex pression engines). Code that uses these common abstractions together is very common in practice [13]. In this work, we will describe an alternative parsing strategy that sidesteps these problems by building into the language only a delimitation strategy, which ensures that ambiguities do not occur. The parsing and elaboration of literal bodies occurs during typechecking, rather than in the initial parsing phase. In particular, the typechecker defers responsibility to library providers, by treating the body of the literal as a term of the type-specific language (TSL) associated with the type it is being checked against. The TSL definition is responsible for elaborating this term using only general-purpose syntax. This strategy permits significant semantic flexibility – the meaning of a form like { } can differ depending on its type, so it is safe to use it for empty sets, maps and

4 Omar, Kurilova, Nistor, Chung, Potanin, Aldrich

JSON literals. This frees these common forms from being tied to the variant of a data structure built into a language’s standard library, which may not provide the precise semantics that a programmer needs (for example, Python dictionaries do not preserve key insertion order). We present our work as a variant of an emerging programming language called Wyvern [22]. To allow us to focus on the essence of our proposal and provide the com munity with a minimal foundation for future work, the variant of Wyvern we develop here is simpler than the variant we previously described: it is purely functional (there are no effects other than non-termination) and it does not enforce a uniform access princi ple for objects (fields can be accessed directly), so objects are essentially just recursive labeled products with simple methods. It also adds recursive sum types, which we call case types, similar to those found in ML. One can refer to our version of the language as TSL Wyvern when the variant being discussed is not clear. Our work substantially extends and makes concrete a mechanism we sketched in a short workshop paper [23]. The paper is organized as a language design for TSL Wyvern: – In Sec. 2, we introduce TSL Wyvern with a practical example. We introduce both inline and forward referenced literal forms, splicing, case and object types and an example of a TSL definition. – In Sec. 3, we specify the layout-sensitive concrete syntax of TSL Wyvern with an Adams grammar and introduce the abstract syntax of TSL Wyvern. – In Sec. 4, we specify the static semantics of TSL Wyvern as a bidirectionally typed elaboration semantics, which combines two key technical mechanisms: 1. Bidirectional Typechecking: By distinguishing locations where an expression must synthesize a type from locations where an expression is being analyzed against a known type, we precisely specify where generic literals can appear and how dispatch to a TSL definition (an object with a parse method serving as metadata of a type) occurs. 2. Hygienic Elaboration: Elaboration of literals must not cause the inadvertent capture or shadowing of variables in the context where the literal appears. It must, however, remain possible for the client to do so in those portions of the literal body treated as spliced expressions. The language cannot know a priori where these spliced portions will be. We give a clean type-theoretic formulation that achieves of this notion of hygiene. – In Sec. 5, we gather initial data on how broadly applicable our technique may be by conducting a corpus analysis, finding that existing code often uses strings where specialized syntax might be more appropriate. – In Sec. 6, we briefly report on the current implementation status of our work. – We discuss related work in Sec. 7 and conclude in Sec. 8 with a discussion of present limitations and future research directions.

### 2 Type-Specific Languages in Wyvern

We begin with an example in Fig. 1 showing several different TSLs being used in a fragment of a web application showing search results from a database. We will review this example below to develop intuitions about TSLs in Wyvern; a formal and more detailed description will follow. For clarity of presentation, we color each character by the TSL it is governed by. Black is the base language and comments are in italics.

Safely Composable Type-Specific Languages 5 
1 let imageBase : URL = <images.example.com> 
2 let bgImage : URL = <%imageBase%/background.png> 
3 new : SearchServer 
4 def resultsFor(searchQuery, page) 
5 serve(~) (* serve : HTML -> Unit *) 
6 >html 
7 >head 
8 >title Search Results 
9 >style ~ 
10 body { background-image: url(%bgImage%) } 
11 #search { background-color: %darken(‘#aabbcc‘, 10pct)% } 
12 >body 
13 >h1 Results for <{HTML.Text(searchQuery)}: 
14 >div[id="search"] 
15 Search again: < SearchBox("Go!") 
16 < (* fmt_results : DB * SQLQuery * Nat * Nat -> HTML *) 
17 fmt_results(db, ~, 10, page) 
18 SELECT * FROM products WHERE {searchQuery} in title 

Fig. 1: Wyvern Example with Multiple TSLs must be balanced> {literal body here, {inner braces} must be balanced} [literal body here, [inner brackets] must be balanced] ‘literal body here, ‘‘inner backticks‘‘ must be doubled‘ ’literal body here, ’’inner single quotes’’ must be doubled’ "literal body here, ""inner double quotes"" must be doubled" 12xyz (* no delimiters necessary for number literals; suffix optional *)

Fig. 2: Inline Generic Literal Forms

#### 2.1 Inline Literals

Our first TSL appears on the right-hand side of the variable binding on line 1. The variable imageBase is annotated with its type, URL. This is a named object type declaring several fields representing the components of a URL: its protocol, domain name, port, path and so on (below). We could have created a value of type URL using the general purpose introductory form new, which forward references an indented block of field and method definitions beginning on the line after it appears:

1 objtype URL 
2 val protocol : String 
3 val subdomain : String 
4 (* ... *) 
1 let imageBase : URL = new 
2 val protocol = "http" 
3 val subdomain = "images" 
4 (* ... *) 

This is tedious. By associating a TSL with the URL type (we will show how later), we can instead introduce precisely this value using conventional notation for URLs by plac ing it in the body of a generic literal, <images.example.com>. Any other delimited form in Fig. 2 can equivalently be used when the constraints indicated can be obeyed. The type annotation on imageBase (or equivalently, ascribed directly to the literal) implies that this literal’s expected type is URL, so the body of the literal (the characters between the angle brackets, in blue) will be governed by the URL TSL during the typechecking phase. This TSL will parse the body (at compile-time) and produce an elaboration: a Wyvern abstract syntax tree (AST) that explicitly instantiates a new object of type URL using general-purpose forms only, as if the above had been written directly.

6 Omar, Kurilova, Nistor, Chung, Potanin, Aldrich

2.2 Splicing In addition to supporting conventional notation for URLs, this TSL supports splicing another Wyvern expression of type URL to form a larger URL. The spliced term is here delimited by percent signs, as seen on line 2 of Fig. 1. The TSL chooses to parse code between percent signs as a Wyvern expression, using its abstract syntax tree (AST) to construct the overall elaboration. A string-based representation of the URL is never constructed at run-time. Note that the delimiters used to go from Wyvern to a TSL are controlled by Wyvern while the TSL controls how to return to Wyvern. 2.3 Layout-Delimited Literals On line 5 of Fig. 1, we see a call to a function serve (not shown) which has type HTML -> Unit. Here, HTML is a user-defined case type, having cases for each HTML tag as well as some other structures, such as text nodes and sequencing. Declarations of some of these cases can be seen on lines 2-6 of Fig. 4 (note that TSL Wyvern also includes simple product types for convenience, written T1 * T2). We could again use Wyvern’s general-purpose introductory form for case types, e.g. BodyElement((attrs, child)). But, as discussed in the introduction, this can be cognitively demanding. Thus, we have associated a TSL with HTML that provides a simplified notation for writing HTML, shown being used on lines 6-18 of Fig. 1. This literal body is layout-delimited, rather than de limited by explicit tokens as in Fig. 2, and introduced by a form of forward reference, written ~ (“tilde”), on the previous line. Because the forward reference occurs in a posi tion where the expected type is HTML, the literal body is governed by that type’s TSL. The forward reference will be replaced by the general-purpose term, of type HTML, generated by the TSL during typechecking. Because layout was used as a delimiter, there are no syntactic constraints on the body, unlike with inline forms (Fig. 2). For HTML, this is quite useful, as all of the inline forms impose constraints that would cause conflict with some valid HTML, requiring awkward and error-prone escaping. It also avoids issues with leading indentation in multi-line literals, as the parser strips these automatically for layout-delimited literal bodies. 2.4 Implementing a TSL Portions of the implementation of the TSL for HTML are shown on lines 8-15 of Fig. 4. A TSL is associated with a named type using a general mechanism for associating a statically-known value with a named type, called its metadata. Type metadata, in this context, is comparable to class annotations in Java or class/type attributes in C#/F# and internalizes the practice of writing metadata using comments, so that it can be checked by the language and accessed programmatically more easily. This can be used for a variety of purposes – to associate documentation with a type, to mark types as being deprecated, and so on. Note that we allow programs to extract the metadata value of a named type T programmatically using the form metadata[T]. For the purposes of this work, metadata values will always be of type HasTSL, an object type that declares a single field, parser, of type Parser. The Parser type is an object type declaring a single method, parse, that transforms a ParseStream extracted from a literal body to a Wyvern AST. An AST is a value of type Exp, a case type that encodes the abstract syntax of Wyvern expressions. Fig. 5 shows portions of the decla-

Safely Composable Type-Specific Languages 7 
1 casetype HTML 
2 Empty 
3 Seq of HTML * HTML 
4 Text of String 
5 BodyElement of Attributes * HTML 
6 StyleElement of Attributes * CSS 
7 (* ... *) 
8 metadata = new : HasTSL 
9 val parser = ~ 
10 start <- ’>body’= attributes start> 
11 fn (attrs, child) => Inj(‘BodyElement‘, Pair(attrs, child)) 
12 start <- ’>style’= attributes EXP> 
13 fn (attrs, e) => ‘StyleElement((%attrs%, %e%))‘ 
14 start <- ’<’= EXP> 
15 fn (e) => ‘%e% : HTML‘ 

Fig. 4: A Wyvern case type with an associated TSL.

1 objtype HasTSL 
2 val parser : Parser 
3 objtype Parser 
4 def parse(ps : ParseStream) : Result 
5 metadata : HasTSL = new 
6 val parser = (*parser generator*) 
7 casetype Result 
8 OK of Exp * ParseStream 
9 Error of String * Location 
10 casetype Exp 
11 Var of ID 
12 Lam of ID * Type * Exp 
13 Ap of Exp * Exp 
14 Inj of Id * Exp 
15 ... 
16 Spliced of ParseStream 
17 metadata : HasTSL = new 
18 val parser = (*quasiquotes*) 

Fig. 5: Some of the types included in the Wyvern prelude.

rations of these types, which live in the Wyvern prelude (a collection of types that are automatically loaded before any other). Notice, however, that the TSL for HTML is not provided as an explicit parse method but instead as a declarative grammar. A grammar is specialized notation for defining a parser, so we can implement a grammar-based parser generator as a TSL atop the lower-level interface exposed by Parser. We do so using a layout-sensitive grammar formalism developed by Adams [1]. Wyvern is itself layout-sensitive and has a grammar that can be written down using this formalism, as we will discuss, so it is sensible to expose it to TSL providers as well. Most aspects of this formalism are conventional. Each non-terminal (e.g. the designated start non-terminal) is defined by a number of disjunctive rules, each introduced using <-. Each rule defines a sequence of terminals (e.g. ’>body’) and non-terminals (e.g. start, or one of the built-in non-terminals ID, EXP or TYPE, representing Wyvern identifiers, expressions and types, respectively). Unique to Adams grammars is that each terminal and non-terminal in a rule can also have an optional layout constraint associated with it. The layout constraints available are = (meaning that the leftmost column of the annotated term must be aligned with that of the parent term), > (the leftmost column must be indented further) and >= (the leftmost column may be indented further). Note that the leftmost column is not simply the first character, in the case of terms that span multiple lines. For example, the production rule of the form A → B = C≥ D > approximately reads as: “Term B must be at the same indentation level as term A, term C may be at the same or a greater indentation level as term A, and term D must be at an indentation level greater than term A’s.” In particular, if D contains a NEWLINE character, the next line must be indented past the position of the

8 Omar, Kurilova, Nistor, Chung, Potanin, Aldrich left-most character of A (typically, though not always, constructed so that it must appear at the beginning of a line). There are no constraints relating D to B or C other than the standard sequencing constraint: the first character of D must be further along in the file than the others. Using Adams grammars, the syntax of real-world languages like Python and Haskell can be written declaratively. Each rule is followed, in an indented block, by a spliced function that generates an elaboration given the elaborations recursively generated by each of the n non-terminals in the rule, ordered left-to-right. Elaborations are of type Exp, which is a case type containing each form in the abstract syntax of Wyvern (as well as an additional case, Spliced, that is used internally), which we will describe later. Here, we show how to generate an elaboration using the general-purpose introductory form for case types (line 11, Inj corresponds to the introductory form for case types) as well as using quasiquotes (line 13). Quasiquotes are expressions written in concrete syntax that are not evaluated for their value, but rather evaluate to their corresponding syntax trees. We observe that quasiquotes too fall into the pattern of “specialized notation associated with a type”: quasiquotes for expressions, types and identifiers are simply TSLs associated with Exp, Type and ID (Fig. 5). They support the Wyvern concrete syntax as well as an additional delimited form, written with %s, that supports “unquoting”: splicing another AST into the one being generated. Again, splicing is safe and structural, not string-based. We can see how HTML splicing works on lines 12-15: we simply include the Wyvern expression non-terminal EXP in our rule and insert it into our quoted result where appropriate. The type that the spliced Wyvern expression will be expected to have is determined by where it is placed. On line 13 it is known to be CSS by the decla ration of HTML, and on line 15, it is known to be HTML by the use of an explicit ascription.

### 3 Syntax

3.1 Concrete Syntax We will begin our formal treatment by specifying the concrete syntax of Wyvern declar atively, using the same layout-sensitive formalism that we have introduced for TSL grammars, developed recently by Adams [1]. Adams grammars are useful because they allow us to implement layout-sensitive syntax, like that we’ve been describing, without relying on context-sensitive lexers or parsers. Most existing layout-sensitive languages (e.g. Python and Haske

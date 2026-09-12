---
source_url: https://bracha.org/newspeak-modules.pdf
ingested: 2026-09-12
sha256: 51b56e04c47ebf0c4e074b8485bfdc30423f08de34c70fc5b5e8330b5e37d2dc
---
# Modules as Objects in Newspeak

Modules as Objects in Newspeak

Gilad Bracha 1, Peter von der Ah´e 2, Vassili Bykov 3, Yaron Kashai 4, William Maddox 5, and Eliot Miranda 6

1 Ministry of Truth gilad@bracha.org 2 peter@ahe.dk

3 smalltalkbigot@gmail.com

4 Cadence Design Systems yaron@cadence.com 5 Adobe Systems wmaddox@adobe.com 6 Teleplace eliot@teleplace.com

Abstract. We describe support for modularity in Newspeak, a program ming language descended from Smalltalk [33] and Self [69]. Like Self, all computation — even an object’s own access to its internal structure — is performed by invoking methods on objects. However, like Smalltalk, Newspeak is class-based. Classes can be nested arbitrarily, as in Beta [44]. Since all names denote method invocations, all classes are virtual; in particular, superclasses are virtual, so all classes act as mixins. Un like its predecessors, there is no static state in Newspeak, nor is there a global namespace. Modularity in Newspeak is based exclusively on class nesting. There are no separate modularity constructs such as packages. Top level classes act as module definitions, which are independent, im mutable, self-contained parametric namespaces. They can be instantiated into modules which may be stateful and mutually recursive.

1 Introduction

To achieve the structuring power of modules, Smalltalk ... would need 
nested classes. 
Clemens Szyperski, [64] 

Modularity is a major issue in software design. Many programming languages provide features intended to support modularity. The state of the art leaves much to be desired however. Few languages support the use of modules as components. Typically, modules are not first class values in the language. They cannot be abstracted over. One cannot have multiple instances of a module definition in a single program, for example, nor are mutually recursive modules supported. These deficits are not theoretical. In recent years they have spawned the evolution of a variety of extralinguistic tools (e.g., [4, 1, 3, 2]). Even relatively powerful module constructs such as those of ML [41] have engendered a large body of research aimed at relaxing their limitations ([58, 23, 37, 56, 50, 24]). The Newspeak programming language [16] supports component-style modu larity via a novel object-oriented language design, based on two key ideas:

1. All names are late bound. 2. There is no global namespace. Point (1) holds because the only run time operation in Newspeak is virtual method invocation, known as message send in Smalltalk and Self parlance. We refer to this style of programming as message-based programming, and consider Newspeak to be a message-based language. We use the terms method invocation and message send interchangeably throughout this paper. 1 The exclusive use of messages in Newspeak strictly enforces the adage ”pro gram to an interface not an implementation”. The concept of interface is central to modularity [11]. As in Self, there is no way to directly reference a slot (we follow Self in referring to storage locations as slots) since the only operation allowed is method invocation. Slot declarations implicitly introduce accessor methods. Unlike Self, Newspeak is a class based language. As with slots, there is no way to refer directly to class declarations. Class declarations implicitly introduce accessor methods for the classes. This implies that classes are first class values, and that class names are dynamically bound, and subject to override just like methods. In other words, classes are always virtual [43]. In particular, superclass names are also dynamically bound, implying that a class declaration is never statically tied to a specific superclass. Every class declaration is in fact a mixin declaration [17]. Newspeak supports nested class declarations. Top level classes serve as mod ule definitions, and their instances are modules. The idea that classes should be used to define modules is natural and obvious. However, its successful applica tion has proven to be elusive. A major contribution of this paper is to show how modularity can be achieved based exclusively on class nesting, without recourse to additional constructs such as packages, components, fragments etc. Because there is no global namespace, a top level class declaration cannot refer to an enclosing scope; all names used within it must be defined by it or inherited. This enables a discipline whereby all external dependencies of a module declaration are explicitly listed at the top of the class. Furthermore, module definitions can be compiled and loaded in any order. Module definitions are stateless; even though Newspeak is an imperative language, it has no concept of static state. It follows that any connection to the world outside the module must come via parameters supplied at instance creation. Modules therefore act as sandboxes, providing a natural fit with object capability based security [47]. Of course, since modules are instances, they are first class. Side-by-side de ployment of multiple instances of a module definition is trivial. Modules being objects, they conform to a procedural interface, and distinct implementations of the same module interface are possible as well.

1 The term message is widely associated with asynchrony. However, messages may be synchronous as well. We consider virtual method invocations to be synchronous message sends. We plan to add support for asynchrony to Newspeak in the future.

The combination of virtual classes and class nesting allows entire class hier archies to be defined, mixed in and overridden within modules, supporting class hierarchy inheritance [55, 28].

1.1 Contributions 
The main contribution of this paper is the design and implementation of a pro 
gramming language that combines support for: 
– First class, mutually recursive modules. 
– Side-by-side deployment of multiple module instances. 
– Multiple simultaneous implementations of a module interface. 
– Class hierarchy inheritance and mixins, including module mixins. 
– Object capability based security and module sandboxing. 
– Full reflectivity. 
To the best of our knowledge, no other programming language supports all of 
these features. 
Specific technical contributions are a modularity mechanism that relies ex 
clusively on class nesting, without recourse to additional constructs; a semantics 
that reduces the risk of inadvertent name capture via inheritance; and an in 
stance initialization scheme that implicitly supports the factory pattern while 
decoupling the instance interface from the factory interface. 

1.2 Roadmap The next section introduces Newspeak and its key ideas by means of informal examples. Section 3 describes the core semantics with more precision. Next, section 4 includes design rationale and usage guidelines. Section 5 describes our experience using Newspeak and the project’s current status, followed by a discussion of related work (section 6), future work (7) and conclusions.

2 Newspeak by Example Syntactically, Newspeak is closely related to Smalltalk and Self. For readers ignorant of Smalltalk syntax, we will explain its essentials below. We begin with a simple example which introduces the class Point, shown in figure 1. The class defines two slots x and y. Slots are declared between vertical bars. Slots are similar to instance variables, except that they are never accessed di rectly. Slots are accessed only through automatically generated getters and set ters. If p is a Point, p x and p y denote the values stored in p’s x and y slots respectively. Note that there is no dot between p and x; since method invoca tion is the only operation in Newspeak, it can be recognized implicitly by the compiler. Comments appear between double quotes, and strings between single quotes.

class Point x: i y: j = ( ” This section is the instance initializer ” | ”declare slots” public x ::= i. ” ::= denotes slot initialization” public y ::= j. | )

(

public printString = ( ˆ ’x = ’, x printString, ’ y = ’, y printString

)

)

Fig. 1. Cartesian Points

The first pair of parentheses in the class declaration delimits the instance initializer where slots are declared and initialized. Slots that are not explicitly initialized are set to nil. Setter methods are denoted by the slot name followed by a colon, so p x: 91 sets the x coordinate of p to 91. This is an example of Smalltalk’s keyword syntax. In general, the header of an N-ary method, N > 0, is declared id1: p1 id2: p2 ... idN: pN, where id1:id2:...idN: is the name of the method and pi, 1 ≤ i ≤ N are the formal parameters; each idi : is a keyword. An invocation of such a method is written id1: e1 id2: e2 ... idN: eN, where the ei are expressions denoting the actual arguments. The order of the keywords is significant and cannot be changed. In addition to keyword methods, one may define methods whose name is composed of special symbols such as +, &, | etc. These methods always take one argument and are written using infix notation, e.g., a * b. These are known as binary methods. Our example shows the use of such a binary method: the ”,” method of String which implements string concatenation. Within the body of Point, the names x, y, x: and y: are in scope and can be used directly, as shown in the method printString (note that the caret (ˆ) is used to indicate that an expression should be returned from the method, just like the return keyword in conventional languages). However, x and y denote calls to the getter methods, not references to variables. Newspeak programs enjoy the property of representation independence — one can change the layout of objects without any need to make further source changes anywhere in the program. For example, if we chose to modify Point so that it uses polar coordinates, no modification to the printString method would be needed, as long as we preserved the interface of Point by providing methods x and y that compute the cartesian coordinates. The class declaration evaluates to a class object. Instances may only be cre ated by invoking a factory method on Point. Every class has a single primary factory, in this case x:y:. If no factory name is given, it defaults to new. The pri mary factory method’s header is declared immediately after the class name. The formal parameters of the primary factory are in scope in the instance initializer. In figure 1, the slot declarations include an initialization clause of the form ::= e where e is an arbitrary expression. For example x is initialized to the value of the formal parameter i using the syntax x ::= i. The declaration of the primary factory automatically generates a correspond ing method on the class object. When invoked, this method will allocate a fresh instance o, ensure that the instance initializer of the class is executed with self = o, and return the initialized instance o. To create a fully initialized instance of Point write, e.g.: Point x: 42 y: 91. The factory method is somewhat similar to a traditional constructor. How ever, it has a significant advantage: its usage is indistinguishable from an ordinary method invocation. This allows us to substitute factory objects for classes (or one class for another) without modifying instance creation code. Instance cre ation is always performed via a late bound procedural interface. This eliminates the primary motivation for dependency injection frameworks [2]. Having introduced basic syntax and terminology, let us examine a more sub stantial example.

2.1 Nested Classes Newspeak class declarations can be nested within one another to arbitrary depth. Thus, a Newspeak class can have three kinds of members: slots, methods and classes. All references to names are always treated as method invocations, so any member declaration within a class can be overridden in a subclass. It is possible not only to override methods with methods, but to override slots, classes and methods with each other. For example, one can decide that in a particular subclass, a slot value should in fact be computed by a function, and simply override the slot with a method. An example of class nesting is ShapeLibrary, a class library for manipulating geometric shapes, shown in figure 2. ShapeLibrary has a number of nested classes within it. Several of these are outlined in the figure. We elide the details of some class declarations, replacing them with ellipses.

class ShapeLibrary usingPlatform: platform = ( | ”We use = to define immutable slots”. private List = platform collections List. private Error = platform exceptions Error. private Point = platform graphics Point.

| ) (

public class Shape = (...)(...) public class Circle = Shape (...)(...) public class Rectangle = Shape (...)(...)

)

Fig. 2. Outline of a shape library

Shapes are organized in a class hierarchy rooted in class Shape. The details of this code are unimportant to us here, except for one point: the classes refer to each other. For example both Circle and Rectangle inherit from Shape (the name of the superclass follows the equal sign in the class declaration). Recall, however, that a name such as Shape cannot refer to a class directly. Rather, it is a method invocation that will return the desired class. This method is defined implicitly in class ShapeLibrary by the declaration of the nested class Shape. The method is available to all code nested within ShapeLibrary. This is how an enclosing class provides a namespace for its nested classes.

Imports Code within a module must often make use of code defined by other modules. For example, ShapeLibrary requires utility classes such as List, defined by the standard collections library. In the absence of a global namespace, there is no way to refer to a class such as List directly. Instead, we have defined a slot named List inside ShapeLibrary. The slot declarations used in figure 2 differ slightly from our earlier examples. Here, slot initialization uses = rather than ::=. The use of = signifies that these are immutable slots, that will not be changed after they are initialized. No setter methods are generated for immutable slots, thus enforcing immutability. When ShapeLibrary is instantiated, it expects an object representing the un derlying platform as an argument to its factory method usingPlatform:. This ob ject will be the value of the factory method’s formal parameter platform. During the initialization of the module, the slot List will be initialized via the expression platform collections List. This sends the message collections to platform, presum ably returning an object representing an instance of the platform’s collection library. This object then responds to the message List, returning the desired class. The class is stored in the slot, and is available to code within the module definition via the slot’s getter method. The slot definition of List fills the role of an import statement, as do those of Error and Point. Note that the parameters to the factory method are only in scope within the instance initializer. The programmer must take explicit action to make (parts of) them available to the rest of the module. The preferred idiom is to extract individual classes and store them in slots, as shown here. It is then possible to determine the module’s external dependencies at a glance, by looking at the instance initializer. Encouraging this idiom is the prime motivation for restricting the scope of the factory arguments to the initializer.

Modularity Since the entire library is embedded within a single class, it is possible to create multiple instances of the library and use them simultane ously (side-by-side deployment). For example, we could instantiate the library with different platform objects, which could provide different implementations of List with different characteristics (e.g., varying speed and memory require ments, logging capabilities etc.). Different module instances do not interfere with each other, because there is no static state. Module definitions are therefore re entrant.

It is also possible to provide different implementations of the library. Since the library is accessed strictly via a procedural interface, functionally equivalent implementations may be used transparently to clients. In all of the above scenarios, one can switch between libraries dynamically, store libraries in data structures, pass them as parameters etc., because libraries are represented as first class objects.

2.2 Class Hierarchy Inheritance 
We now extend our example to show how inheritance can be applied to an entire 
class hierarchy. 
class ExtendShapes withShapes: shapes = ( 
| ShapeLibrary = shapes. | )( 
public class ColorShapeLibrary usingPlatform: platform = 
ShapeLibrary usingPlatform: platform ( 

)( public class Shape = super Shape ( | color | )(...)

)

)

Fig. 3. Subclassing a Hierarchy

Figure 3 shows the class ExtendShapes. The factory method for this class, withShapes:, takes a single argument, shapes which should be a shape library class such as ShapeLibrary. The instance initializer imports this library under the name ShapeLibrary. Nested within ExtendShapes is class ColorShapeLibrary, which inherits from ShapeLibrary. This shows that it is possible to subclass an imported class. The name of the superclass, ShapeLibrary, is followed by the message usingPlatform: platform. We do this in order to determine what parameters will be made avail able to the superclass’ initializer. Before a subclass’ instance initializer is exe cuted, control passes to the instance initializer of its superclass in much the same way as constructors are chained in mainstream languages. Here we indicate that platform will be passed on to the superclass’ instance initializer. ColorShapeLibrary overrides Shape. It defines its own class Shape that sub classes the superclass’ class of the same name. The overriding class Shape has added a slot, color. Since Shape is the superclass of all other classes in ShapeLi brary, they all inherit the new slot. Let us see how this occurs. When the class declaration for Shape is overridden in ColorShapeLibrary, the automatically generated accessor method is overridden as well. Hence every at tempt to access Shape on an instance of ColorShapeLibrary will produce the overridden class rather than the original.

Classes are generated lazily. The first time a class is referenced, its accessor manufactures the class and caches the result. Subsequent accesses always return the same class object. As an example, consider the class Circle. This class is declared in ShapeLibrary and inherited unchanged in ColorShapeLibrary. It declares its superclass to be Shape. The first attempt to use Circle on an instance of ColorShapeLibrary will cause the class to be generated; this will require accessing the superclass. The superclass clause denotes a method invocation, not a direct reference to a class, just like every other name in a Newspeak program. Therefore, the new class will be a subclass of the overridden version of Shape, as intended. The same holds for all other subclasses of Shape in the library, as one would expect.

2.3 Application Assembly and Deployment In the absence of a global namespace, it may not be obvious how one combines separately developed top level classes into a single application. Here we discuss some options; other variations are possible. An application is typically constructed by instantiating a top level class T representing the application as a whole. T will likely depend on a number of separately compiled module definitions; its factory method should take these, and only these, as arguments. The Newspeak IDE provides us with a names pace containing all classes used in development. It in this namespace that we will instantiate T. Use of the IDE namespace is analogous to how tools like make reference the components of an application utilizing the file system as a namespace. Class T should have a method main:args: as its entry point. The method takes an object representing the underlying platform, and an array of command line arguments. The code in main:args: will instantiate the various module defi nitions imported by T, linking them together as required and then start up the application. One deployment option is to use serialized objects as our binary format. We can serialize an instance of T, and later run it via a tool that deserializes it and invokes its main:args: method. This is similar to the classic C convention of invoking an application via a distinguished function main(). T is analogous to the C program, its main:args: method is analogous to the main() function, and the serialized instance is analogous to a binary file. Deserialization is the equivalent of linking and loading. We have now established an intuition as to how modularity works in Newspeak and what it can achieve. It is time to discuss the semantics of Newspeak in detail.

3 Semantics The semantics of the Newspeak language are defined in [16]. Here we focus on the core of the semantics: method lookup and its interaction with class nesting. As illustrated in [42] such interaction can be subtle, especially in the presence of virtual classes. This section is targeted at readers with a keen interest in these subtleties; the rest of the paper can be understood independently.

3.1 Classes, Declarations and Mixins In Newspeak, it is important to distinguish between a class and a class decla ration. In a traditional object oriented language there is a 1:1 correspondence between a class declaration (a syntactic entity) and a class (a run time entity). In Newspeak, however, superclasses are dynamically bound, so a class declara tion does not uniquely determine a class. Instead, a class declaration induces a mixin, a description of a class that is abstract with respect to any superclass. There can be many classes that correspond to a given declaration. Each such class is an application of the mixin induced by its declaration to some super class. It is possible to explicitly extract and apply the mixin associated with a class declaration, but we will not explore this feature further here. We use intuitive terms such as top level class, nested class and enclosing class to refer to classes that correspond, respectively, to top level, nested or enclosing class declarations. When there is no risk of confusion, we may continue to use the term class rather than the more verbose class declaration, e.g., when we speak of a method being declared in a class.

3.2 Nested Classes and Enclosing Objects Nested Classes are Per Instance Each instance of an enclosing class has its own distinct set of nested classes. As an example of why this is necessary, consider the case of class ColorShapeLibrary in figure 3. The superclass of ColorShapeLibrary is imported by the surrounding module definition. Each instance of the enclosing class may be have distinct imports, leading to a completely different nested class. More generally, the notion that a class is an attribute of an object, just like a method or slot, is motivated by modeling considerations, as in Beta.

Enclosing Objects and Lexical Scope The relationship between an instance o of an enclosing class and its nested classes is bidirectional: each such nested class has o as its enclosing object. The relationship between enclosing objects and nested classes is illustrated in Figure 4, which depicts a top level class O whose declaration includes a nested class declaration I. O is shown with two instances, anO1 and anO2. Each such instance has its own class I. Each I class can have its own instances - in this case anI1 and anI2 respectively. A class’ enclosing object is the dynamic representation of the lexical scope immediately enclosing the class’ declaration. Since lexical scope plays an im portant role in Newspeak method lookup, there is a close connection between enclosing objects and message sends.

anI1

O

anI2

I I anO1 anO2

### Legend

instance-of enclosing-object nested class anObject aClass

Fig. 4. Enclosing classes, nested classes and their instances

3.3 Method Lookup In most object-oriented programming languages, if the receiver of a message is self it can be omitted. In the presence of class nesting, if the receiver is implicit (i.e., omitted), it may be either self or some enclosing object. In statically typed languages, the lexical level of the receiver is determined at compile time [42, 61]. In dynamically typed languages, it is usually done at run time as part of the method lookup process. Typically, one starts the lookup with the class of self (or self itself in a prototype based language) and proceeds up its inheritance chain; if no method is found, one jumps to the enclosing lexical level and recurses. This notion is described in detail in the Java Language Specification [35] and formalized in [61]. It is called “comb semantics” in NewtonScript [62]. 2 Newspeak differs in that lookup proceeds up the lexical scope chain (start ing with the lexically deepest activation record) and only if no lexically visible matching method is found do we proceed up the inheritance chain of self. In no case do we search the inheritance chains of enclosing objects. See figure 5 for an illustration. The motivation for our design is the desire to avoid inadvertent capture of method names by superclasses. In both Beta and Java, situations such as the following (illustrated in Java) can arise:

class Sup { }class Outer {int m(){ return 91;}class Inner extends Sup {int foo(){ return m();}

} }The expectation is that new Outer.Inner().foo() will yield the result 91, because it returns the result of the call to m, which is defined in the enclosing scope. Consider what happens if one now modifies the definition of Sup:

class Sup { int m(){ return 42;} }

The result of calling foo is now 42. The behavior of the subclass has changed in a way that its designer could not anticipate, which is clearly undesirable. Of course, inheritance in general suffers from modularity problems, but there is no reason to aggravate them further. In Newspeak, code is immune to capture of lexically scoped names due to changes in inherited libraries. We believe this approach is more robust in the face of program evolution, especially on larger scales. We now examine the semantics of method lookup in more detail. Ordinary message sends involve a receiver and a message consisting of a method name and a (possibly empty) set of arguments. The meaning of such sends is standard, as in Smalltalk: methods matching the send are looked up a standard single inheritance class chain, starting with the class of the receiver. 2 NewtonScript has no lexical nesting, but its lookup semantics are nevertheless es sentially the same.

C S

O O C

O C

Object

#### self send/ Inheritance implicit receiver send

#### lexical chain

## Legend

superclass enclosing class

Fig. 5. Method lookup

More interesting are implicit receiver sends — sends written without an ex plicit receiver.

Implicit Receiver Sends An implicit receiver send is equivalent to an ordinary send to the implicit receiver. The question is how to determine the receiver when it is implicit. Figure 6 gives pseudo-code for computing the implicit receiver.

0 function implicitReceiver(s, r, d, m) { 1 if declares(d, m) return r; 
2 if (enclosingDeclaration(d) = nil) return s; 
3 var cls := class(r); 
4 while (declaration(cls) 6 = d) cls := superClass(cls); 
5 return implicitReceiver(s, enclosingObject(cls), enclosingDeclaration(d), m); 
6 } 

Fig. 6. Determining implicit receivers

The code above makes use of six auxiliary functions: declares(d, m) is a predicate that evaluates to true if the declaration d includes a declaration of a member named m; enclosingDeclaration(d) returns the declaration lexically enclosing the declaration d, or nil if d is a top level class declaration; class(o) is the class of the object o; declaration(c) is the class declaration corresponding to class c; superClass(c) is the superclass of c; and finally, enclosingObject(c) is the enclosing object of class c. The function implicitReceiver takes four arguments: the receiver of the cur rent method, s (i.e., self); a candidate receiver object r; a candidate class dec laration d; and a message name m. The search for an implicit receiver begins by invoking implicitReceiver with self as both the current and the candidate re ceiver, the class declaration immediately enclosing the call site as the candidate declaration and the name of the message being sent as the final argument. The function requires the invariant that the class of r, or some superclass, corresponds to d. The invariant ensures that if d declares a member named m, r can respond to the message; r’s class chain includes a class C corresponding to d and d includes a matching member. This invariant holds for the initial arguments, and is preserved when the function recurses. Line 1 of figure 6 tests if the candidate declaration declares a member named m. If so, the candidate receiver is the desired result and we are done; if not, we need a new candidate declaration, representing the next lexical level. The new candidate declaration is the enclosing declaration of d. If the enclosing declaration is nil, d must represent a top level declaration, meaning that no matching member has been found in the lexical scope. The desired member can only be inherited, and the implicit receiver must be self (line 2). Otherwise we must determine a new candidate receiver. On lines 3 and 4, we scan up the superclass chain of r, looking for a class cls corresponding to the declaration d. The next candidate receiver will be the enclosing object of cls.

The scan is necessary because the class of r need not correspond to the declaration d; the send may be in inherited code, in which case the enclosing declaration is that of a superclass of r. On line 5, we pass the new candidates to a recursive call of implicitReceiver, with s and m unchanged.

4 Discussion 
4.1

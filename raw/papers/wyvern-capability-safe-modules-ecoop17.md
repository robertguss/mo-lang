---
source_url: https://potanin.github.io/files/MelicherShiPotaninAldrichECOOP2017.pdf
ingested: 2026-09-12
sha256: 880b114c605297bf3acc4a92d825ce8a7e3c906082caac78e2608cc63db1432c
---
# A Capability-Based Module System for Authority

## A Capability-Based Module System for Authority Control∗

### Darya Melicher1, Yangqingwei Shi2, Alex Potanin3, and Jonathan Aldrich4

1 Carnegie Mellon University, Pittsburgh, PA, USA 
2 Carnegie Mellon University, Pittsburgh, PA, USA 
3 Victoria University of Wellington, Wellington, New Zealand 
4 Carnegie Mellon University, Pittsburgh, PA, USA 

Abstract The principle of least authority states that each component of the system should be given author ity to access only the information and resources that it needs for its operation. This principle is fundamental to the secure design of software systems, as it helps to limit an application’s attack surface and to isolate vulnerabilities and faults. Unfortunately, current programming languages do not provide adequate help in controlling the authority of application modules, an issue that is particularly acute in the case of untrusted third-party extensions. In this paper, we present a language design that facilitates controlling the authority granted to each application module. The key technical novelty of our approach is that modules are first class, statically typed capabilities. First-class modules are essentially objects, and so we formalize our module system by translation into an object calculus and prove that the core calculus is type safe and authority-safe. Unlike prior formalizations, our work defines authority non-transitively, allowing engineers to reason about software designs that use wrappers to provide an attenuated version of a more powerful capability. Our approach allows developers to determine a module’s authority by examining the capab ilities passed as module arguments when the module is created, or delegated to the module later during execution. The type system facilitates this by identifying which objects provide capabil ities to sensitive resources, and by enabling security architects to examine the capabilities passed into and out of a module based only on the module’s interface, without needing to examine the module’s implementation code. An implementation of the module system and illustrative ex amples in the Wyvern programming language suggest that our approach can be a practical way to control module authority. 1998 ACM Subject Classification D.3.3 Language Constructs and Features Keywords and phrases Language-based security, capabilities, authority, modules Digital Object Identifier 10.4230/LIPIcs.ECOOP.2017.15

### 1 Introduction

The principle of least authority [34] is a fundamental technique for designing secure soft ware systems. It states that each component of a system must be able to access only the information and resources that it needs for operation and nothing more. For example, if an application module needs to append an entry to an application log, the module should not also be able to access the whole file system. This is important for any software system that ∗ A technical report containing a complete version of the formalism is also available [21].

© Darya Melicher, Yangqingwei Shi, Alex Potanin, and Jonathan Aldrich; 
licensed under Creative Commons License CC-BY 
31st European Conference on Object-Oriented Programming (ECOOP 2017). 
Editor: Peter Müller; Article No. 15; pp. 15:1–15:27 
Leibniz International Proceedings in Informatics 
Schloss Dagstuhl – Leibniz-Zentrum für Informatik, Dagstuhl Publishing, Germany 

divides its code into a trusted code base [33] and untrusted peripheral code, as in it, trusted 
code could run directly alongside untrusted code. Common examples of such software sys 
tems are extensible applications, which allow enriching their functionality with third-party 
extensions (also called plug-ins, add-ins, and add-ons), and large software systems, in which 
some developers may lack the expertise to write secure- or privacy-compliant code and thus 
should have a limited ability to access system resources in their code. Enforcing the principle 
of least authority helps to limit the attack surface of a software system and to isolate vul 
nerabilities and faults. However, current programming languages do not provide adequate 
control over the authority of untrusted modules [3, 38], and non-linguistic approaches also 
fall short in controlling authority [4, 18, 35, 42]. 
Application security becomes even more challenging if an application uses code-loading 
facilities or advanced module systems, which allow modules to be dynamically loaded and 
manipulated at runtime. In such cases, an application has extra implementation flexibility 
and may decide what modules to use at runtime, e.g., responding to user configuration or 
the environment in which the application is run. On the other hand, untrusted modules 
may get access to crucial application modules that they do not explicitly import via global 
variables or method calls. For example, although a third-party extension may import only 
the logging module and not the file I/O module, the extension could receive an instance of 
the file I/O module via a method call as an argument or as a return value. Dynamic module 
loading can be modeled as first-class modules, i.e., modules that are treated like objects and 
can be instantiated, stored, passed as an argument, returned from a function, etc. However, 
in a conventional programming language featuring first-class modules (e.g., Newspeak [2], 
Scala [31], and Grace [15]), it is difficult to track and control modules accesses. 
In this paper,1 we present a module system that helps software developers to control 
the authority of code by treating modules as first-class, statically typed capabilities [5]— 
i.e., communicable but unforgeable references allowing to access a resource—and making 
access to security- and privacy-related modules capability-protected, in the style of the E 
programming language [25]. Specifically, if module A wants to access module B, A may do 
so only if A possesses an appropriate capability. Leveraging capabilities allows us to support 
first-class modules (e.g., representing dynamic module loading, linking, and instantiation) 
while still providing a strong model for reasoning about application security and module 
isolation. 
The design of the module system and the accompanying type system of the language 
simplify reasoning about module authority. To determine the authority of a module via 
capability-based reasoning, a security expert or a system architect must understand what 
capabilities the module can access. Since our module system is statically typed (in contrast 
to Newspeak [2], which provides a capability-safe but dynamically typed module system), 
the architect needs to examine only the module’s interface and the interfaces of its imports 
and does not need to examine the code of any module. For example, suppose an application 
has a trusted logger module that legitimately imports a module for file I/O, and the logger 
module is the only module imported by an extension. To ensure that the extension does not 
have access to the file I/O module, except as mediated (i.e., attenuated [25]) by the logger 
module, it is sufficient to verify that the extension does not import the file I/O module 
directly and that the extension cannot get direct access to a file I/O capability by calling the 
logger’s methods. The first condition is a syntactic check, and the second condition requires 
inspecting only the logger’s interface, e.g., to ensure that none of the methods in the interface 

1 A one-paragraph poster abstract for this work appeared elsewhere [16].

return a file object (or indeed the file I/O module itself, since modules are first-class). Our 
module system enjoys an authority safety property that statically guarantees that the above 
two possibilities are all a developer has to consider. This is in contrast to conventional 
languages and module systems, in which global variables, unrestricted reflection, arbitrary 
downcasts, and other “back doors” make capability-based reasoning infeasible. 
Our work has four central contributions. The first contribution is the design of a module 
system that supports first-class modules (cf. Newspeak, Scala, and Grace) and is capability 
safe [22, 25]. Our approach forbids global state, instead requiring each module to take 
the resources it needs as parameters, which ensures that modules do not carry ambient 
authority [40] (similar to Newspeak, but in contrast to Scala and Grace). For practical 
purposes, our module system supports module-local state and does not restrict the imports 
of non-state-bearing modules (in contrast to Newspeak). 
The second contribution is a type system that distinguishes modules and objects that 
act as capabilities to access sensitive resources, from modules and objects that are purely 
functional computation or store immutable data. This design makes it easy for an architect 
to focus on the parts of an interface that are relevant to the authority of a module. Overall, 
the type system allows developers to determine the authority of a module at compile time 
by examining only the interfaces of the module and the modules it imports, without having 
to look at the implementation of the involved modules. 
The third contribution of our work is the formalization of authority control in the de 
signed module system, in which we introduce a novel, non-transitive definition of authority 
that explicitly accounts for attenuated authority (e.g., as in the logger example above). 
We also introduce a definition of authority safety and formally prove the designed system 
authority-safe. Our result contrasts prior, transitive definitions of authority safety that 
cannot account for authority attenuation [7, 20]. 
The final contribution is the implementation of the designed module system in Wyvern, a 
statically typed, capability-safe, object-oriented programming language [29], demonstrating 
the feasibility and practicality of the proposed approach. 
We start the paper by describing the Wyvern module system from the perspective of 
a software developer in Section 2 and present the formalization of the designed module 
system in Section 3. We continue by introducing the definition of authority safety, state 
authority-related properties of Wyvern’s module system, and prove Wyvern authority-safe 
in Section 4. Then, we report on the implementation of the Wyvern module system and on 
the limitations of our approach in Sections 5 and 6 respectively. Finally, we compare our 
approach to other language-based approaches in Section 7 and conclude in Section 8. 

### 2 Wyvern Module System

In Wyvern, modules have several features distinguishing its module system from others: Modules are first-class, i.e., they are treated as objects and can be instantiated, stored, passed as arguments into methods, and returned from methods. Modules are treated as capabilities in the style of [1], i.e., we unify the notion of having a reference to a module with the notion of having a capability to access that module. If a module can access another module, we say that the former module has a capability to use the latter module. (The same is true for objects.) Modules are divided into two categories: resource modules, i.e., security- or privacy related modules (system resources, modules containing application data, or state-bearing modules), and pure modules, i.e., non-state-bearing utility modules.

Wyvern Libraries Word Processor

Collections

System Resources

Extensions listFactory logger wordCloud

network prettyChart

...

...

queueFactory

fileIO

Platforms python ...

java

...

wordProcessor

Figure 1 A module import diagram of a word processor application used in code examples. The boxes represent modules, and the arrows represent module imports. If an arrow goes from module A to module B, A imports B. The arrows with black arrowheads correspond to importing resource modules; the arrow with an unfilled arrowhead corresponds to importing a pure module. The dark background delineates the trusted code base.

To illustrate our approach, let us consider a sample application that allows third-party extensions. Figure 1 shows a module import diagram of a word processor application, similar to OpenOffice or MS Word, that extends its feature set by allowing third-party extensions. The vertical dotted line represents a virtual border between standard language-provided libraries and the word processor code. The boxes represent modules, which are clustered according to their conceptual type. The arrows represent module imports. If an arrow goes from module A to module B, module A imports module B. The arrows with black arrowheads correspond to importing resource modules, while the arrow with an unfilled arrowhead corresponds to importing a pure module. Being able to import a resource module, which corresponds to arrows with black arrowheads on the diagram, is equivalent to having unconditional control and thus authority over the imported module. Wyvern provides a number of standard libraries: Collections refer to a set of pure mod ules that provide implementations of basic functionality, e.g., list and queue factories. Sys tem Resources refers to a set of language-provided modules that implement system-level functionality, e.g., file and network access. Platforms refer to the modules that implement the Wyvern back end. Platforms and system resources may be used to subvert the word processor, and thus access to them requires the possession of special capabilities. The word processor system consists of core modules, which are considered trusted, and extension modules (marked so on the diagram), which are provided by third parties and considered untrusted. The diagram presents only a subset of modules of the word processor’s core that are used in our examples: the wordProcessor module is the main module of the word processor, and the logger module provides a logging service and can be used by multiple word processor’s modules. We use the word processor example to introduce Wyvern’s two types of modules— resource modules and pure modules—and to show how one can determine a module’s au thority. For brevity, all module definitions and their types in code examples are put together; however, in reality, each module definition and type resides in a separate file.

### 2.1 Threat Model

Our approach focuses on ensuring the principle of least authority and assumes a software system that is divided into a trusted code base [33] and untrusted peripheral code. All the code in the trusted code base is vetted by security or privacy experts. The untrusted code may be modules within the same code base or third-party extensions. Our module

D. Melicher, Y. Shi, A. Potanin, and J. Aldrich 15:5 
1 module def wordProcessor(io : FileIO) : WordProcessor 
2 import logger 
3 var log : Logger = logger(io) 
4 ... 
5 resource type FileIO 
6 def read(file : File) : String 
7 ... 
8 resource type Logger 
9 def appendToLog(entry : String) : Unit 
10 module def logger(io : FileIO) : Logger 
11 def appendToLog(entry : String) : Boolean 
12 io.open("~/log.txt").append(entry) 
Figure 2 A Wyvern code example demonstrating resource modules, their imports, and instanti 
ations. 

system aims at giving the untrusted modules the least possible authority over security- and 
privacy-related modules of the trusted code base, thus minimizing the possible damage if 
the untrusted code is malicious or vulnerable. The authority given to untrusted modules is 
scrutinized, but their code is not examined, except for their interfaces. 
The following two common scenarios fit our threat model: 
Malicious third-party code. In an extensible software system, an attacker writes a malicious 
extension and tricks the user into loading it into the system. We wish to limit the damage 
that such an extension can do. 
Fallible in-house code. In a large software system, a trusted core is written by security 
experts, who have the knowledge to securely access sensitive resources, e.g., the network 
and file system, while the rest of the system is written by non-security experts, who may 
introduce vulnerabilities that could be exploited by an attacker. We wish to limit the 
damage that may result from exploits to the non-core parts of the system. 
In both scenarios, modules written by less trusted parties can access security- and 
privacy-related modules, e.g., system resources, only via safe interfaces written by experts. 
We leverage module system capabilities to ensure that attackers cannot do anything to 
security- or privacy-critical resources beyond what is permitted by the safe interfaces. Vul 
nerabilities inside the trusted code base are explicitly outside of our security model. We 
discuss the limitations of this model more in Section 6. 
The word processor example is presented as the first scenario, but it can be adapted 
to the second scenario as well. In Figure 1, the trusted code base is marked by the dark 
background. 

### 2.2 Resource Modules

Resource modules are defined as modules that: 
1. encapsulate system resources (e.g., java and fileIO), 
2. use other resource modules (e.g., wordProcessor and logger), or 
3. contain mutable state (e.g., wordProcessor). 
A module is a resource if it has one or more of these characteristics. For example, the 
wordProcessor module is a resource module because it imports the system resource fileIO 
and has state (details upcoming). It is important for state-bearing modules to be resources, 
as they may contain private application data and also may facilitate communication between 
modules that import them, potentially allowing illegal sharing of capabilities. 
Figure 2 presents a code example with several resource modules and types. By con 
vention, module names start with lowercase letters, while type names are capitalized. The 

code snippet starts with the definition of the main module of the word processor applic 
ation, wordProcessor, which is a resource module. The module imports a module instance 
of a resource type FileIO (defined on lines 5–7) via the argument passing mechanism. In 
Wyvern, each resource module is an ML-style functor [19], i.e., it is a function that accepts 
one or more arguments, each of which is a module instance of a required type, and produces 
a module instance as a result. In the case of wordProcessor, the module functor accepts a 
module instance of type FileIO and returns an instance of the wordProcessor module. 
FileIO is a resource type that gives access to the file system, and since wordProcessor 
imports an instance of this type, wordProcessor is a resource module too. To access a resource 
module of the FileIO type, wordProcessor needs to have an appropriate capability. The 
capability must be passed into the wordProcessor module on its instantiation by either another 
module or top-level code. 
The wordProcessor module instantiates the logger module (defined on lines 8–12) by, first, 
importing the definition of the logger module using the import keyword and then calling 
the imported logger functor definition with appropriate arguments to get an instance of 
the logger module. (Technically, logger(io) is syntactic sugar for logger.apply(io), where 
apply() is a default method called on a resource module to instantiate it.) The argument that 
logger requires is a module instance of the FileIO type, and by passing in io, wordProcessor 
gives logger the capability to use the module instance of the FileIO type it received on 
instantiation. The created instance of logger is immediately assigned to a local variable 
log, which may be used later in the wordProcessor’s code. Note that wordProcessor imports a 
module instance of the FileIO type, but it instantiates, i.e., creates a local instance of, the 
logger module. Generally, any resource module can instantiate other resource modules from 
its initialization block and even provide them with access to resource modules to which it 
itself has access. Since logger is a resource module, instantiating it creates a capability for 
it, which, in this case, belongs to the wordProcessor module. 
Alternatively, if wordProcessor did not want to provide logger access to the file system, 
wordProcessor could create and pass in a dummy module of type FileIO as follows: 

module def wordProcessor(io : FileIO) : WordProcessor import logger var dio : FileIO = dummyIO var log : Logger = logger(dio) ...

This would disallow the logger module from having any access to the file system. To run the program, the top-level code is as follows:

| | platform | java | |
| --- | --- | --- | --- |
| | import | fileIO | |
| | import | wordProcessor | |
| | let | io = fileIO(java) in | |

platform java 
import fileIO 
import wordProcessor 
let io = fileIO(java) in 
let wp = wordProcessor(io) in ... 
First, the back end to be used is specified using the platform keyword. This keyword can 
appear only on the top level and is used to create a resource module instance representing 
the back-end implementation. Then, the definitions of the fileIO and wordProcessor module 
functors are imported, and the two modules are instantiated receiving the arguments they 
require. The two newly created module instances are assigned to two variables in two nested 
let constructs and can be used in the rest of the code contained in the inner let’s body. 
The top-level code exercises high-level control over accesses to resource modules, per 
forming two important functions. First, it instantiates resource modules, implicitly creating 

D. Melicher, Y. Shi, A. Potanin, and J. Aldrich 15:7 
1 module listFactory : ListFactory 
2 def create() : List 
3 ... 
4 module def wordCloud(log : Logger) : WordCloud 
5 import wyvern : listFactory as list 
6 var words : List = list.create() 
7 ... 
Figure 3 A Wyvern code example demonstrating a pure module and its import. 

capabilities that allow using the instantiated modules. Second, it grants module access per 
missions (conceptually, in the Newspeak style [2]; syntactically, in the ML-functor style [19]): 
the instantiated modules (and implicit capabilities to use them) are passed as arguments to 
authorized modules. 
For brevity, the top level code can be shortened as follows: 

require fileIO : FileIO import wordProcessor let wp = wordProcessor(fileIO) in ...

Here we use syntactic sugar (the keyword require) for specifying the platform (the default platform is chosen), and importing the functor definition of and instantiating the fileIO module. This syntactic sugar can be used for resource modules that import only the resource module representing the back-end implementation, and is usually used for short programs, e.g., “Hello, World!” Notably, two modules may share a module instance and potentially use it for commu nication. For example, if both extensions prettyChart and wordCloud would like to append to the word processor’s log, they may share one instance of the logger module:

| | require | | fileIO |
| --- | --- | --- | --- |
| | import | | wordCloud |
| | import | | prettyChart |
| | let | | log = logger(fileIO) in |

let wCloud = wordCloud(log) in let pChart = prettyChart(log) in ...

This makes the language more flexible and simplifies certain implementation tasks.

### 2.3 Pure Modules

The definition of a pure module is the opposite from the definition of a resource module. 
Pure modules are those modules that: 
1. do not encompass system resources, 
2. do not import any resource module instances, 
3. do not contain or transitively reference any mutable state, 
4. have no side effects. 
For a module to be pure, all of these conditions must be satisfied. The third condition has a 
caveat: The prohibition is on whether a module and its functions capture state, not whether 
they affect it. Functions defined in a pure module may have side effects on state, but only 
if the state in question is passed in as an argument or created within the function itself. 
Thus pure modules are harmless from the security perspective, and for more convenience, 
in Wyvern, any module can import any pure module. 
Figure 3 shows an example of a pure module and how it can be imported. The listFactory 
module is the implementation of a list factory and belongs to the standard Wyvern library. 

1 module def wordCloud(log : Logger, list : ListFactory) : WordCloud 
2 var words : List = list.create() 
3 ... 
4 // top level 
5 require fileIO 
6 import wordCloud 
7 import listFactory as list 
8 let log = logger(fileIO) in 
9 let wCloud = wordCloud(log, list) in ... 
Figure 4 A Wyvern code example demonstrating how a pure module can be passed to a module 
as an argument. 

java fileIO logger wordCloud

x x

x Figure 5 Authority distribution between fileIO, logger, and wordCloud. If an arrow goes from module A to module B, A has authority over B. Crosses on arrows mean that such authority is not granted. In Wyvern, authority is non-transitive.

It does not contain mutable state, but 

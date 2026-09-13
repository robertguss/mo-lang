# Java — Write Once, Run Anywhere, Forever

## Origin story

### Designer, institution, year

**James Gosling**, with **Mike Sheridan** and **Patrick Naughton**, initiated the Java language project at **Sun Microsystems** in **June 1991** ([Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))). Gosling had joined Sun in **1984** and worked there for 26 years, until his resignation on **April 2, 2010**, after Oracle's acquisition of Sun ([Wikipedia: James Gosling](https://en.wikipedia.org/wiki/James_Gosling)).

The language was **initially called Oak**, "after an oak tree outside Gosling's office. The project later used the name Green and was finally renamed Java, from Java coffee, a type of coffee from Indonesia" ([Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))).

Key dates:

| Event | Date |
|---|---|
| Project initiated | June 1991 |
| Public release (Sun's Java platform) | May 23, 1995 |
| Java 1.0 | 1996 |
| Generics (J2SE 5.0) | 2004 |
| Oracle acquires Sun | January 27, 2010 |
| OpenJDK becomes official reference (SE 7) | 2011 |
| Virtual Threads (JEP 444, Java 21) | 2023 |

### The motivating problem

Java began as an initiative for **consumer electronics** (set-top boxes, interactive television) at Sun's "Green Project." When that market did not materialize, the team pivoted to the emerging Web. Gosling "got the idea for the Java virtual machine while writing a program to port software from a PERQ by translating Perq Q-Code to VAX assembler and emulating the hardware… he pursued architecture-neutral execution for widely distributed programs by implementing a similar principle: programs would always target the same virtual machine" ([Wikipedia: James Gosling](https://en.wikipedia.org/wiki/James_Gosling)).

The design pitch: **"Write once, run anywhere" (WORA)**. "Compiled Java code can run on all platforms that support Java without needing to be recompiled. Java 1.0 promised WORA functionality and provided no-cost runtimes on popular platforms" ([Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))).

### Initial reception

Massive. Java arrived with the web, positioned as the browser's native computation model via **applets**. Netscape licensed Java in 1995; Microsoft embraced-extended-extinguished it (leading to the *Sun v. Microsoft* Java trademark lawsuit). By 1998, Java had displaced C++ as the language of enterprise back-end development.

## Design philosophy

### Core principles

- **Simplicity over completeness.** No multiple inheritance of implementation; no operator overloading; no `#include`/preprocessor; no explicit pointers.
- **Object-oriented from the ground up.** Everything except primitives is an object; every class descends from `java.lang.Object`.
- **Automatic memory management** via garbage collection.
- **Platform independence via bytecode.** Source → JVM bytecode → JIT to native.
- **Safety first.** Bounds-checked arrays, type-safe casts, no pointer arithmetic ("The lack of pointer arithmetic allows the garbage collector to relocate referenced objects and helps ensure type safety and security" — [Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))).
- **Familiar syntax.** "Gosling designed Java with a C/C++-style syntax intended to be familiar to system and application programmers" ([Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))).

### What Java rejected

- **Multiple inheritance** of implementation (retained multiple interface inheritance).
- **Operator overloading.**
- **Explicit pointer arithmetic.**
- **Manual memory management** — no `delete`.
- **Preprocessor and macros.**
- **Structs / value types** — added only much later via records (Java 14) and Project Valhalla (in progress).

### Cultural values

Enterprise reliability, backward compatibility to a fault, tooling and IDE integration, comprehensive documentation via Javadoc, and openness — Sun released the code under GPLv2 in 2007.

## Language features

### Syntax

C/C++-derived; static typing; classes with single inheritance and interface multiple inheritance; packages; checked and unchecked exceptions; annotations (5.0); lambdas (8); records (14); pattern matching (14+); sealed classes (17); virtual threads (21).

### Type system

Nominal, static, with generics (2004, J2SE 5.0). "Generics allow compile-time type checking without requiring many container classes containing nearly identical code" ([Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))). Generics are erased at runtime — an intentional design decision for backward compatibility with pre-generics code.

"In 2016, Java's type system was proven unsound because generics can be used to construct classes and methods that allow an instance of one class to be assigned to a variable of another unrelated class. Such code is accepted by the compiler but fails at runtime with a class cast exception" ([Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))). This was Amin & Tate's paper on Java/Scala unsoundness.

### Memory model

Automatic garbage collection is fundamental. "The programmer determines when objects are created. The Java runtime is responsible for recovering memory once objects are no longer in use" ([Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))).

Java's memory-model history:

- **Parallel GC** — default in Java 8.
- **G1GC** — Garbage-First Garbage Collector — default since Java 9.
- **ZGC** — Z Garbage Collector — introduced Java 11 (sub-millisecond pauses on multi-TB heaps).
- **Shenandoah** — introduced Java 12 (in third-party OpenJDK builds like Eclipse Temurin; unavailable in Oracle's builds).

Java's **memory model** (JMM, JSR-133, 2004) was a landmark: the first mainstream language with a rigorous specification of happens-before, volatile, final, and race semantics.

### Concurrency

Java 1.0 shipped with `Thread`, `synchronized`, `wait`/`notify` — heavy OS threads. **`java.util.concurrent`** (JSR-166, Java 5, 2004) by Doug Lea added executors, futures, atomics, concurrent collections.

The revolution: **Project Loom's Virtual Threads**, final in **Java 21** (2023) ([Inside Java: Virtual Threads](https://inside.java/2023/10/30/sip086/)):

- "Virtual Threads extend `java.lang.Thread`. Run on top of Platform Threads. Are not linked to underlying OS threads. Are not tied to a specific Platform Thread. Can move between Platform Threads as needed. Retain their context, thread-local values, stack trace, and related information when moving between Platform Threads."
- "The JDK can schedule and unschedule Virtual Threads by monitoring blocking operations, including `BlockingQueue.take()`, waiting for bytes to be received on a socket."
- "Virtual Threads are scheduled by default using a `java.util.concurrent.ForkJoinPool`. The scheduler operates on a FIFO model."

The point: "Virtual Threads allow Java developers to obtain many benefits of reactive programming while retaining the ease of writing and debugging associated with imperative programming" ([Inside Java](https://inside.java/2023/10/30/sip086/)).

### Error handling

**Checked exceptions** are a distinctive Java feature: methods must declare (`throws`) or catch checked exceptions at compile time. They are widely criticized (Bruce Eckel, Anders Hejlsberg on record) as producing exception pollution or empty catch blocks; no subsequent language has adopted them.

### Metaprogramming

Runtime reflection via `java.lang.reflect`; annotation processing at compile time; bytecode manipulation via ASM, Byte Buddy, Javassist. No macros. **Records** (Java 14, JEP 359/395) reduced boilerplate for data classes.

### Module system

**JPMS (Project Jigsaw, Java 9, 2017)** added a language-level module system: `module-info.java`, `requires`, `exports`. Adoption has been uneven; many libraries still ship as classpath JARs rather than named modules.

### Notable innovations

- Cross-platform bytecode.
- JIT compilation as default execution model.
- The Java Memory Model (JSR-133).
- Annotations.
- Virtual threads at scale.

## Implementation

### Reference compiler

**`javac`** (in OpenJDK). Java is compiled to **JVM bytecode**, "an intermediate representation… analogous to machine code but intended to be executed by a virtual machine written specifically for the host hardware" ([Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))).

### Lexer, parser, IR

Hand-written recursive-descent parser in javac. The bytecode itself is the portable IR.

### The JVM

**HotSpot** is the standard production JVM. "Java's HotSpot compiler is described as two compilers in one" — the tiered C1 (client) and C2 (server) compilers. **GraalVM** provided an alternative JIT (Graal) and native-image (AOT) compilation; "GraalVM allowed tiered compilation and was included in, for example, Java 11, but was removed as of Java 16" ([Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))). GraalVM continues as a separate download.

### Runtime and GC

Discussed above — G1GC default; ZGC and Shenandoah for low-pause workloads.

### Bootstrapping

The JDK is written in a mixture of Java and C++ (HotSpot itself is C++).

### Alternative implementations

- **GraalVM** — polyglot VM with native-image AOT.
- **Eclipse OpenJ9** (IBM) — production JVM tuned for cloud.
- **Azul Zing / Prime** — commercial JVM with C4 pauseless GC.
- **Amazon Corretto**, **Eclipse Temurin (Adoptium)**, **Microsoft Build of OpenJDK** — free OpenJDK distributions.
- **RoboVM**, **Codename One** — Java on iOS (historical).
- **TeaVM**, **CheerpJ** — Java to WebAssembly / JavaScript.

## Ecosystem

### Package manager

**Maven** (Apache) and **Gradle** are the two dominant build/dependency systems. Maven Central hosts millions of artifacts.

### Standard library

Enormous: `java.util`, `java.io`, `java.nio`, `java.util.concurrent`, `java.time` (Java 8, JSR-310), `java.net.http` (Java 11 HttpClient), `java.util.stream` (Java 8), `java.lang.foreign` (Java 22 FFI).

### Tooling

**IntelliJ IDEA** (JetBrains), **Eclipse**, **NetBeans**, **VS Code + Java extensions**. Debuggers: JDB, jdb; profilers: JFR (Java Flight Recorder), YourKit, JProfiler. Build: Maven, Gradle, Ant.

### Governance

**Java Community Process (JCP)** — "In 1997, Sun Microsystems approached ISO/IEC JTC 1 and later Ecma International to formalize Java. Sun soon withdrew from the formalization process. Java remains a de facto standard controlled through the Java Community Process" ([Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))).

The **OpenJDK** project is the reference implementation, "used by most developers, and the default JVM for almost all Linux distributions… licensed under the GNU GPL" ([Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))). Oracle drives the release train (six-month cadence since Java 9, with LTS releases at 11, 17, 21, 25).

## Adoption

### Where it dominates

- **Enterprise backend services** — every major bank, insurer, telecom, and retailer has significant Java systems.
- **Android** — until Kotlin overtook it as Google's preferred language (2019), Android was ~all Java.
- **Big-data** — Hadoop, Spark (Scala on JVM), Kafka, Cassandra, Flink, Elasticsearch — the JVM is the dominant big-data runtime.
- **Servers and middleware** — Tomcat, Jetty, Netty, JBoss / WildFly, Spring, Micronaut, Quarkus.
- **IDEs** — Eclipse and IntelliJ are Java.
- **Scientific and financial computing** — extensive.

### Where it never won

- Systems programming (C++/Rust).
- Desktop GUI (mostly).
- Games (C++/C# with Unity).
- Data science (Python).
- Web frontend (JavaScript).

### Current momentum (2026)

Very strong. Java 21 (LTS, 2023) delivered virtual threads and pattern matching; Java 25 (LTS, 2025) shipped further Loom, Valhalla, and Panama work. The six-month release cadence provides steady features; ZGC and Shenandoah keep Java competitive with Go for tail-latency-sensitive services; Loom repositions Java for high-concurrency IO where Node.js and Go had been dominant. Kotlin, Scala, Clojure remain vibrant JVM neighbors.

## Criticism and open problems

- **Verbosity** — historically compared unfavorably to Python and Kotlin. Records, `var` inference (Java 10), text blocks (Java 15), and pattern matching narrow the gap.
- **Checked exceptions** — no other mainstream language adopted them.
- **Generics via type erasure** — parametric type information erased at runtime; "In 2016, Java's type system was proven unsound" ([Wikipedia: Java](https://en.wikipedia.org/wiki/Java_(programming_language))).
- **Startup time and memory footprint** — a real barrier for CLI and serverless. GraalVM native-image, CRaC (Coordinated Restore at Checkpoint), and Leyden aim to fix this.
- **Value types / Project Valhalla** — long-awaited (over 10 years in development).
- **Module system uptake** slow — most ecosystem libraries still use the classpath.
- **Oracle / Google API-copyright fight** (2010–2021) — chilled Java's positioning; ultimately resolved in Google's favor by SCOTUS in 2021.
- **Nullability** — no built-in non-null types (unlike Kotlin's `String?`); JSpecify (2024+) is trying to standardize null annotations.

## Influence on other languages

- **C#** — Microsoft's answer to Java (Anders Hejlsberg lead designer); improved on many Java rough edges (properties, LINQ, async/await first).
- **Scala** — Odersky's JVM-based functional/OO hybrid.
- **Kotlin** — JetBrains' more concise JVM language; became Google's preferred Android language (2019).
- **Clojure** — Rich Hickey's Lisp on JVM.
- **Groovy**, **JRuby**, **Jython** — dynamic languages on JVM.
- **Ceylon**, **Fantom**, **Xtend** — historical Java successors.
- **Go's error handling** was explicitly a reaction against Java exceptions.

## Key sources

- James Gosling, Bill Joy, Guy L. Steele Jr., Gilad Bracha, *The Java Language Specification*, multiple editions (Addison-Wesley, 1996–).
- James Gosling, Henry McGilton, *The Java Language Environment: A White Paper*, Sun Microsystems, 1996.
- Doug Lea et al., *JSR-133: Java Memory Model and Thread Specification Revision*, 2004.
- Ron Pressler (Oracle), Project Loom and Virtual Threads talks and JEPs (JEP 444).
- [Inside Java: Virtual Threads and Project Loom](https://inside.java/2023/10/30/sip086/).
- [Wikipedia: Java (programming language)](https://en.wikipedia.org/wiki/Java_(programming_language)).
- [Wikipedia: James Gosling](https://en.wikipedia.org/wiki/James_Gosling).
- OpenJDK: [openjdk.org](https://openjdk.org).

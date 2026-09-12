---
source_url: https://www.adacore.com/languages/spark
ingested: 2026-09-12
sha256: 899b593db60fe6cf4a6cf385e460f40dea20a06ef89f82767368f724f89f46d4
---
# Languages | SPARK | AdaCore

Languages | SPARK | AdaCore

Languages > SPARK_

# The SPARK Programming Language

SPARK, which is based on Ada, offers unparalleled safety and security through its design and support for deductive formal verification. You simply can’t write better code.

Features_

## Key Advantages of SPARK

##### Foundations of the Ada Language

SPARK is based on the Ada programming language. All of the benefits of the Ada language translates directly into benefits for SPARK. Wherever you can use Ada, from large server to small devices, you can use SPARK.

##### Absence of Runtime Errors

Run-Time errors include issues traditionally found by automatic checks at run-time and defensive code, such as out-of-bound array access, division by zero, overflow and more. SPARK proves that no run-time errors are possible in your code.

##### Memory Safety

Through a combination of mitigation of dynamic memory usage, borrow-checking analysis and advanced formal proof, SPARK formally demonstrates absence of memory issues such as use after free, access to uninitialized memory or memory leaks and corruption.

##### Functional Safety

SPARK contracts - preconditions, postconditions, type invariants, assertions, etc. - are part of the language, not structured comments. The contracts are checked by the compiler, proved by SPARK, and have execution semantics.

##### No Dynamic Checks or Defensive Code

SPARK proves that defensive code and other run-time checks that may be inserted in the code will never fail. This allows the compiler to remove them from the compiled code, ensuring optimal efficiency while retaining guarantees of integrity.

##### No Undefined Behavior

SPARK is a dialect of Ada that removes Ada features leading to undefined behavior and extends Ada's support for formal specification. When you develop in SPARK, you're using the safest, most secure Ada possible.

##### Strong Typing

SPARK is a strongly typed language. Building upon Ada, types in SPARK are fundamental elements of the software design. They are named, associated with properties, and checked for consistency statically, via proof. When leveraged, SPARK’s type safety prevents errors that arise when mixing up variables or accidentally converting between type representations.

##### Modularity

SPARK is fundamentally modular. SPARK performs deductive formal verification one subprogram at a time. Called subprograms are assumed to satisfy their postconditions when their preconditions are met. This ensures that SPARK scales and works well in teams. It also lets you use FFI without sacrificing the ability to prove the correctness of your SPARK code.

Mathematical Assurance_

## Build with Formal Methods

Formal methods represent software semantics using mathematics precisely, allowing analysis of software behaviors prior to runtime. SPARK provides deductive formal verification: subprograms are represented as Hoare triples, and SPARK proves that when the subprogram preconditions are met, subprogram execution ensures the postcondition. SPARK proofs are sound - no false negatives, and precise - no false positives, provided timeout is not reached. Since SPARK operates one subprogram at a time, its analysis is scalable. Moreover, you can focus SPARK on only those parts of your software that are of greatest concern.

Related Products_

## Our SPARK Technology

### GNAT Pro

GNAT Pro offers software development environments and toolchains for all versions of Ada across a rich set of platforms, featuring IDEs, native and cross compilers, a multi-language build system, multi-language debuggers, and configurable runtime libraries. Explore

### GNAT Static Analysis Suite

A comprehensive set of tools for enforcing coding standards, analyzing code metrics, and detecting defects and vulnerabilities in Ada code. Explore

### GNAT Dynamic Analysis Suite

Provides unit testing and fuzz testing capabilities, along with a structural coverage analysis tool. Explore

### SPARK Pro

Leverages formal methods to automatically prevent or detect a wide range of bugs in Ada, ensuring higher reliability and security. Explore

Expert Support & Training_

## Our SPARK Services

AdaCore’s services help teams adopt SPARK with confidence, offering training, mentorship, and certification support tailored to high-integrity projects.

### Certification support

Since SPARK is based on Ada, library & runtime certification and tool qualification are available for DO-178, EN-50128, ISO 26262, ECSS-E-ST-40C / ECSS-Q-ST-80C and IEC 61508. Learn More

### Mentorship

SPARK represents a new programming paradigm. Our mentorship programs ensure your teams are ready to get full value from adopting SPARK Pro. Learn more

### SPARK Language Training

AdaCore offers tailored training designed to help your team get up and running with SPARK. Learn More

Where SPARK is Used Today_

## When Failure is not an Option

SPARK is playing an increasingly critical role in the development of safety- and security-critical systems — from advanced defense applications and air-traffic management to firmware in medical and industrial automation domains — because its design enforces the elimination of runtime errors, ensures information-flow integrity, and enables formal proof of functional correctness. It is the only technology available today that enables the deployment of formal methods directly on source code at industrial scale. As the demand for mathematically assured software grows, SPARK continues to expand its relevance across industries that tolerate nothing less than provable correctness.

Get in Touch_

## Expert Guidance

Ready to bring the benefits of formal verification to your project? Our team can help you get started with the right tools, training, and support.

Speak to an Expert

Case Study_

## NVIDIA: Adoption of SPARK Ushers in a New Era in Security-Critical Software Development

Learn why NVIDIA made the “heretical” decision to abandon C/C++ and adopt SPARK as its coding language of choice for security-critical software and firmware components.

NVIDIA Dhawal Kumar, Principle Software Engineer

FAQs_

## Find answers to common questions about SPARK

What kind of pointer support does SPARK offer?

SPARK supports pointers (Ada access types) using an ownership model that was derived from that of Rust. So you can use pointers in your SPARK code, provided you follow SPARK’s ownership rules.

How do I use exceptions in SPARK?

You can raise and handle exceptions in your SPARK code. If you propagate an exception, you have to mention it in an Exceptional_Cases contract, in which you specify what the calling subprogram can count on when handling the exception.

What targets does SPARK support?

Because SPARK code is Ada, SPARK is supported on all the targets that GNAT supports.

Explore More_

## Latest News and Resources

## NVIDIA Security Team: “What if we just stopped using C?”

[Blog Post]Fabien Chouteau

## Ada and SPARK: Beyond Static Analysis for Medical Devices

[Case Study]

## Should I choose Ada, SPARK, or Rust over C/C++?

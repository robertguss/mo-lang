---
source_url: https://arxiv.org/abs/2509.13429
ingested: 2026-09-12
sha256: 5231291f568e21415e9da67c0d37eaea5fb48e0608a820d38a1e18fa8b5e7622
---
# Catalpa: GC for a Low-Variance Software Stack

Catalpa: GC for a Low-Variance Software Stack

# Catalpa: GC for a Low-Variance Software Stack

Anthony Arnold anthony.arnold@uky.edu University of KentuckyLexingtonKentuckyUSA and Mark Marron mark.marron@uky.edu University of KentuckyLexingtonKentuckyUSA

(2025)

###### Abstract.

The performance of an application/runtime is usually conceptualized as a continuous function where, the lower the amount of memory/time used on a given workload, then the better the compiler/runtime is. However, in practice, good performance of an application is viewed as more of a binary function – either the application responds in under, say 100 ms, and provides a good user experience (usability), or it takes a noticeable amount of time, leaving the user waiting and potentially abandoning the task. Thus, performance really means how often the application is fast enough to meet user expectations, leading industrial developers to focus on the 95 ${}^{\text{th}}$ and 99 ${}^{\text{th}}$ percentile tail-latencies as heavily, or moreso, than average response time.

Our vision is to create a software stack that actively supports these needs via programming language and runtime system design. In this paper we present a novel garbage-collector design, the Catalpa collector, for the Bosque programming language and runtime. This allocator is designed to minimize latency and tail-latency variability while maintaining high-throughput and incurring small memory overheads. To achieve these goals we leverage various features of the Bosque language, including immutability and reference-cycle freedom, to construct a collector that has provably bounded collection pauses, incurs a fixed-constant memory overhead, and ensures starvation freedom for the application!

††copyright: acmlicensed††journalyear: 2025††doi: XXXXXXX.XXXXXXX

## 1. Introduction

A key-performance-indicator (KPI) for many applications is the $99^{\text{th}}$ (or $95^{\text{th}}$ ) response percentile latency – that is, the time it takes for the application to respond to a user request $99\%$ of the time. This is a critical metric as these tail-latency events are often pain points for users and, once encountered, lead to disengagement (usability). Unfortunately, these tail-latency events are often intermittent, involve multiple events, and even different subsystems (tailatscale; toddmeasure). These features combine to make them very difficult to diagnose and resolve.

Some sources of tail-latency are irreducible parts of a distributed (or networked) application, such as connection latency, shared resource contention, or hardware failures. However, the latency from these sources is often amplified by runtime and application behavior. For example, a network stall that leads to requests backing up, which leads to many objects being promoted into old GC generations, leading to a long GC pause during whole heap collection, causing more requests to back up, and so on. As seen in this example, the triggering event for the latency spike is an intermittent network stall but the amplification, along with triage work and resolution, is in the runtime behavior.

This work focuses on addresssing this challenge via the construction of a programming language and software stack that behave in a fundamentally path independent (or memoryless) manner, where regardless of previous operations or even simultaneous executions, the behavior of the systems appears as if each task was executed in isolation. A key aspect of creating this type of system is focusing on optimizing for tail-latency variability and avoiding amplifications of pathological behaviors while maintaining high-throughput and incurring small memory overheads. This is a radical departure from the current state of the art where modern runtimes are focused on average behaviors and fast path optimization but struggle with worst-case behaviors and heuristics. Of particular importance in this area is the design of the memory management and garbage collection system, which are often a major source of latency variance, and other performance variability issues in the memory subsystem (distillingcost; understandcost).

Leveraging novel aspects of the Bosque programming language (bosque), this paper introduces a new garbage collector Catalpa which is the first language/runtime/gc combination capable of satisfying the no-tradeoff memory subsystem happiness property (Theorem 5). Recent work (pathalogical) has theoretically validated the conjectures (understandcost; lxr; urc), that it is impossible for (mainstream) languages with imperative features to simultaneously ensure bounded pause times and starvation-freedom without incurring large performance penalties (thrashing) in other areas. However, Bosque which represents a new viewpoint for programming languages, provides a unique opportunity to rethink the design of the memory management system.

Specifically, this work takes a well known GC design, a copying collector for young objects and a reference counting collector for old objects (urc; intrc), and simplifies the implementation using the novel aspects of the Bosque programming language to construct a specialized garbage collector with the following novel properties:

•

Bounded Collector Pauses: The collector only requires the application to pause for a (small) bounded period that is proportional to the size of the nursery.

•

Starvation Freedom: The collector can never be outrun by the application allocation rate and will always satisfy allocation requests (until true exhaustion).

•

Fixed Work Per Allocation: The work done by the allocator and GC for each allocation is constant – regardless of object lifetimes or application behavior.

•

Application Code Independence: The application code does not pay any cost, e.g. read/write barriers, remembered sets, etc., for the GC implementation.

•

Constant Memory Overhead: The reserve memory required by the allocator/collector is bounded by a (small) constant overhead.

We show that such a system is possible in Section 5 and present a practical design and implementation of the Catalpa collector in Sections 3 and 4. Empirically, we validate (Section 6) that this design is effective with at $50^{\text{th}}$ percentile GC pause time is less than \qty133\micro with an astonishing $99^{\text{th}}$ percentile pause time of under \qty300\micro and, the reserve memory overhead is proportional to the size of the nursery of \qty8\mega. In addition, the immutability of values and elimination of read/write barriers leads to an amortized constant cost per allocation and guarantee that each collection can recover either all recoverable or at least enough to cover a full cycle of allocation requests (Section 3). Finally, as shown in Sections 3 and 4, the application code does not pay any cost for the GC implementation and the algorithm works with conservative collection (conservativegc), enabling the compiler to skip root-maps, and easily support pointers into the stack and interior value pointers.

In summary the key contributions of this paper are:

(1)

The formalization of the no-tradeoff memory subsystem happiness property, along with associated theorems and proofs, as a key objective for modern language/runtime/gc systems (Section 5).

(2)

A demonstration, via a novel GC construction (Sections 3 and 4), that existing impossibility results (pathalogical; understandcost) do not apply to languages with the features of Bosque.

(3)

An experimental evaluation of the collector showing that, in addition to its theoretical guarantees, the combined language/runtime system achieves (very) low and predictable pause times along with low memory overheads in practice (Section 6).

## 2. Bosque Background

The goal of the Bosque project is to create a programming system that is optimized for reasoning – by humans, symbolic analysis tooling, and AI agents (Large Language Models in particular) (bosque). The approach taken by Bosque is to identify and remove features or concepts that complicate various forms of reasoning and that are frequent causes of software faults, increase the effort required for a developer (or AI agent) to reason about and implement functionality in an application, or complicate automatically reasoning about a program. Although the initial motivation of this work was focused on software assurance and quality, these same simplifications also provide strong guarantees about how memory can be allocated, organized, and used at runtime as well!

At the core of Bosque is a let-based functional language with a nominal type system for declaring datatypes. A sample Bosque program for computing the largest low-high temperature range in a list is shown in Figure 1.

Figure 1. Max Temperature Range in the Bosque Programming Language.

type Fahrenheit = Int;

entity TempRange {

field low: Fahrenheit;

field high: Fahrenheit;

invariant $low <= $high;

}

function maxTempRange(temps: List): TempRange {

return temps.maxElement(pred(t1, t2) => {

return t1.high - t1.low < t2.high - t2.low

});

}

maxTempRange(List {

TempRange{32, 50},

TempRange{40, 60},

TempRange{20, 30}

});

%% Result is TempRange{40, 60}

The first declaration in the code in Figure 1 is a type declaration for a new type Fahrenheit that is an alias for the Int type. This allows the creation of a new type that is distinct from Int but has the same (efficient) underlying representation. Next is a entity declaration of a composite datatype TempRange that has two fields: low and high, both of type Fahrenheit. The invariant declaration ensures that the low field is always less than or equal to the high field whenever a TempRange value is created.

The function maxTempRange takes a list of TempRange values and returns the one with the largest difference between the high and low temperature fields. The code uses a higher-order function maxElement that takes a predicate function to compare two TempRange values. The last expression in the code i

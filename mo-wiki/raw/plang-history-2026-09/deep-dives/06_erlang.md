# Erlang / BEAM — Let It Crash, Then Restart

## Origin story

### Designers, institution, year

Erlang was created at **Ericsson** in **1986** by **Joe Armstrong**, **Robert Virding**, and **Mike Williams** ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))). The name is attributed to Bjarne Däcker and "has been presumed to refer to Danish mathematician and engineer Agner Krarup Erlang and to be a syllabic abbreviation of 'Ericsson Language.'"

The **BEAM virtual machine** work began in **1992**; Erlang was released as open source in **1998**, and the language achieved "fully open-sourced" status by 1996–1998 ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language)); [Brown, "Erlang design history"](http://www.macs.hw.ac.uk/splv/wp-content/uploads/2019/08/brown2019_erlang.pdf)). Note: Ericsson "banned the in-house use of Erlang for new products in February 1998" and then "re-hired Joe Armstrong in 2004" after Erlang's external success rendered the ban untenable ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))).

### The motivating problem

Ericsson needed a language for telephone-switching software with brutal requirements: **distribution, fault tolerance, soft real-time operation, highly available non-stop applications, and hot swapping** ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))). Existing languages made these properties awkward or impossible.

The initial Erlang was implemented in **Prolog** and "was influenced by PLEX, the programming language used in earlier Ericsson exchanges." By 1988 Erlang had "proven suitable for prototyping telephone exchanges," but "the Prolog interpreter was too slow for production use; one Ericsson group estimated that it needed to be 40 times faster." The **BEAM VM** was born to bridge the gap ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))).

### Initial reception

The decisive event was **AXE-N**, Ericsson's next-generation switch project, which collapsed in **1995**. Armstrong recorded that this collapse "moved Erlang from a laboratory product to real applications." Erlang was chosen for the **AXD** (Asynchronous Transfer Mode) exchange; in **March 1998** Ericsson announced the **AXD301** switch containing "over one million lines of Erlang" and reported to achieve "high availability of nine '9's" (i.e., 99.9999999%) ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))). This became the standard talking point for Erlang's reliability claims.

## Design philosophy

### Core principles

- **Isolated processes communicating only by message passing.** Erlang applications "are built from lightweight Erlang processes… strongly isolated… created and destroyed through lightweight operations… communicating only through message passing… independent of shared resources… capable of non-local error handling" ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))). Wikipedia notably "does not explicitly describe Erlang as implementing the 'actor model'," though the design is universally described that way outside Ericsson's own materials — Brown (2019) explicitly lists Erlang's concurrency model as "Actor Model" ([Brown 2019](http://www.macs.hw.ac.uk/splv/wp-content/uploads/2019/08/brown2019_erlang.pdf)).
- **"Let it crash."** Rather than defensive in-process error handling, "the philosophy favors completely restarting a process rather than attempting to recover from a serious failure. It reduces the amount of defensive programming required" ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))).
- **Supervisor trees.** "A typical Erlang application is structured as a supervisor tree. The architecture is a hierarchy of processes. The top-level process is called a supervisor. A supervisor spawns multiple child processes that act as workers or as lower-level supervisors. Supervisor hierarchies can have arbitrary depth" ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))).
- **Hot code swap.** Two versions of a module can coexist; processes migrate at external calls.

### What Erlang rejected

- **Shared state** — "processes share no state with one another."
- **In-process exception handling as the primary error strategy** — crashes are handled by supervising processes.
- **Object-oriented inheritance and classes** — Erlang is a functional language.
- **Synchronous distribution semantics** — everything asynchronous.

### Cultural values

Reliability over performance; correctness through isolation over correctness through checking; the assumption that failure is normal and must be planned for rather than prevented.

## Language features

### Syntax

Prolog-inspired: variables begin with uppercase; atoms with lowercase; pattern-matched function heads; guards; commas within clauses, semicolons between clauses, and periods at statement ends. Idiomatic Erlang uses recursion and pattern matching heavily.

### Type system

Dynamically typed. Optional static analysis via **Dialyzer** and **success typing** (Kostis Sagonas et al.). More recently, an ongoing Ericsson-sponsored effort to add gradual typing to Erlang follows Elixir's set-theoretic work.

### Memory model

Each process has its own heap (private, per-process), so garbage collection is per-process and pauses only one process at a time. Messages between processes are copied into the receiver's heap. Binaries larger than 64 bytes are reference-counted in a shared binary heap.

### Concurrency

The centerpiece. "Erlang processes are not operating-system processes or threads; they are lightweight processes scheduled by BEAM. The estimated minimal overhead for each process is 300 words. A 2005 benchmark successfully ran 20 million processes with 64-bit Erlang on a machine with 16 GB RAM, corresponding to 800 bytes per process. Erlang has supported symmetric multiprocessing since release R11B, released in May 2006" ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))). Message passing is shared-nothing and asynchronous, and processes can transparently be on remote nodes.

### Error handling

Two orthogonal mechanisms: (1) intra-process `try`/`catch`/`throw`; (2) the process link/monitor mechanism, where a process crash sends an exit message to linked or monitoring processes. The supervisor tree pattern uses monitors: "If the monitored process crashes, the supervisor receives a message containing a tuple whose first member is the atom `'DOWN'`" ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))).

### Metaprogramming

Erlang has no macro system comparable to Lisp's; parse transforms and `-define` textual macros exist. Elixir, built on the same VM, added a proper macro system (see the Elixir deep-dive).

### Module system

Simple: modules are files, functions are exported via `-export` attributes, hot-swap is per-module. OTP's **application** and **release** concepts provide larger-scale packaging.

### Hot code loading

"Code is loaded and managed as module units; a module is a compilation unit. The system can keep two versions of a module in memory simultaneously. Processes can concurrently run code from both versions. The versions are referred to as the 'new' and 'old' versions. A process does not move to the new version until it makes an external call to its module" ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))).

## Implementation

### The BEAM VM

BEAM (Bogdan/Björn's Erlang Abstract Machine) is the standard implementation. "BEAM executes bytecode that is converted to threaded code at load time." A native code compiler exists on most platforms, developed by the **High Performance Erlang Project (HiPE) at Uppsala University**, "fully integrated into Ericsson's open-source Erlang/OTP system in October 2001." Erlang also supports interpretation from source through an AST via script as of R11B-5 ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))). More recently, **JIT compilation** based on AsmJit was introduced in **OTP 24** (2021), producing dramatic speedups.

### Lexer, parser, IR, backend

`compile:file/1` runs a hand-written lexer + yeccc-generated parser to Core Erlang → SSA-like intermediate forms → BEAM bytecode. HiPE and the newer JIT both consume BEAM bytecode.

### Runtime and GC

Per-process generational GC (pauses only affect one process's few hundred words to few tens of kilobytes). Preemptive scheduler with reduction counts (each function call decrements a "reduction" budget; when it hits zero, the scheduler preempts). Kernel-level SMP scheduler since R11B (2006).

### Bootstrapping

The Erlang compiler is written in Erlang.

### Alternative implementations

- **AtomVM** — Erlang bytecode for microcontrollers.
- **LFE** (Lisp Flavoured Erlang) — a Lisp on BEAM by Robert Virding.
- **GRiSP** — bare-metal embedded Erlang.
- **Erlang/RTL** and various historical research VMs.

## Ecosystem

### Package manager

**Rebar3** (community) and **Hex.pm** (packages, shared with Elixir).

### Standard library

**OTP** (Open Telecom Platform) is the standard library: `gen_server`, `gen_statem`, `supervisor`, `application`, `mnesia`, `inets`, `ssl`, `ssh`. Wikipedia notes "Erlang/OTP is supported and maintained by the Open Telecom Platform (OTP) product unit at Ericsson."

### Tooling

**Erlang LS** provides LSP; **rebar3** builds; **eunit** and **common_test** for testing; **observer** for live introspection; **wombat_oam** commercial.

### Community and governance

Ericsson OTP team is the primary steward; a broad community coordinates through EEP (Erlang Enhancement Proposals) and the OTP team's release cadence.

## Adoption

### Where it's used

- **Ericsson** — AXD301 switch, GPRS/3G/LTE support nodes. "In 2014, Ericsson reported that Erlang was being used in its support nodes, GPRS mobile networks worldwide, 3G mobile networks worldwide, LTE mobile networks worldwide" ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))). Also **Nortel** and **Deutsche Telekom**.
- **WhatsApp** — the canonical example. The Erlang Factory 2012 talk from WhatsApp engineer Rick Reed detailed the scaling journey:

| WhatsApp milestone | Value |
|---|---|
| Initial server loading | ~200k connections |
| Initial bottlenecks | Around 425k connections |
| After first round of fixes | 1M connections |
| About a month later | 2M connections |
| Unintentional February record | 2.8M connections before intervention |
| Peak packet rate at 2.8M | 571k packets/sec |
| Peak distribution message rate | >200k msgs/sec |
| Later target | 3M connections |
| Performance goal | 1M connections per server |

The hardware was "Dual Westmere hex-core… 24 logical CPUs… 100GB RAM… SSD… Dual NIC… FreeBSD 8.3… OTP R14B03… CPU utilization >85% across 24 logical CPUs" ([WhatsApp Scaling, Erlang Factory 2012](https://www.erlang-factory.com/upload/presentations/558/efsf2012-whatsapp-scaling.pdf)).

Reed's takeaway: "Erlang had 'awesome SMP scalability.' More than 85% CPU utilization was achieved across 24 logical CPUs… From 200k to 2M connections, the fixes were all contention fixes. Some issues were internal to BEAM. Some issues were addressable with application changes. Most required BEAM patches" ([WhatsApp Erlang Factory](https://www.erlang-factory.com/upload/presentations/558/efsf2012-whatsapp-scaling.pdf)).

- **Klarna** — Swedish fintech, one of the largest Erlang deployments.
- **RabbitMQ** — Pivotal's message broker.
- **CouchDB** — Apache document database.
- **Riak** — Basho distributed KV store.
- **Discord**, **Pinterest**, **Bet365**, **Goldman Sachs** — production Erlang or Elixir at scale (see Elixir deep-dive).

### Where it dominates

Massively-concurrent I/O-bound systems: telecoms, messaging, real-time bidding, chat, message brokers.

### Where it failed to penetrate

Numeric and scientific computing; native GUI; anything requiring low-latency numerical performance. Erlang's per-process copying and dynamic typing preclude high-throughput CPU-bound workloads.

### Current momentum (2026)

Steady. Ericsson continues to invest; the JIT (OTP 24, 2021) provided substantial performance gains. Elixir's popularity has enlarged the BEAM ecosystem substantially; Erlang itself sees regular OTP releases twice a year.

## Criticism and open problems

- **Syntax is polarizing** — Prolog-derived, unfamiliar to most.
- **Dynamic typing** — Dialyzer's success typing catches many bugs but not all; the ongoing gradual typing effort acknowledges the gap.
- **Cold-start performance and single-threaded computational workloads** are weak points.
- **String handling** was historically a mess (character lists vs. binaries); modern practice standardizes on binaries.
- **Hot code loading is exacting** — "successful hot code loading is exacting and requires code to be written carefully to use Erlang's facilities" ([Wikipedia: Erlang](https://en.wikipedia.org/wiki/Erlang_(programming_language))).

## Influence on other languages

- **Elixir** (José Valim, 2011) — runs on BEAM, uses OTP; the largest single beneficiary.
- **Gleam** — statically-typed BEAM language.
- **LFE** — Lisp on BEAM.
- **Scala's Akka** — actor model on JVM, explicitly inspired by Erlang.
- **Pony**, **Orleans** (.NET), **Rust's Actix** — all acknowledge the Erlang/actor lineage.
- **Kubernetes and cloud orchestration patterns** — supervisor trees, restart strategies, and health-check-driven restarts recapitulate OTP patterns at the infrastructure layer. Erlang users often observe (as one blog post put it) that "the cloud arrived at the same conclusions that Joe Armstrong and the Ericsson team reached in 1986."

## Key sources

- Joe Armstrong, "A History of Erlang," HOPL III, 2007.
- Joe Armstrong, *Programming Erlang*, Pragmatic Bookshelf, 2007 (2nd ed. 2013).
- Joe Armstrong, "Making Reliable Distributed Systems in the Presence of Software Errors," PhD dissertation, KTH, 2003.
- Rick Reed, ["Scaling to Millions of Simultaneous Connections"](https://www.erlang-factory.com/upload/presentations/558/efsf2012-whatsapp-scaling.pdf), Erlang Factory SF Bay, 2012.
- Christopher M. Brown, ["Erlang" lecture notes](http://www.macs.hw.ac.uk/splv/wp-content/uploads/2019/08/brown2019_erlang.pdf), SPLV 2019.
- [Wikipedia: Erlang (programming language)](https://en.wikipedia.org/wiki/Erlang_(programming_language)).
- Erlang/OTP source: [github.com/erlang/otp](https://github.com/erlang/otp).

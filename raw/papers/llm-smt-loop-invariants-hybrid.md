---
source_url: https://arxiv.org/abs/2508.00419
ingested: 2026-09-12
sha256: 3bb602f5d387eed9e2725535fa4fdbeadb4ea2db4ccffd50e05c4bc0598d2b9d
---
# Loop Invariant Generation: A Hybrid Framework of Reasoning optimised LLMs and SMT Solvers

Loop Invariant Generation: A Hybrid Framework of Reasoning optimised LLMs and SMT Solvers

# Loop Invariant Generation: A Hybrid Framework of Reasoning optimised LLMs and SMT Solvers

Varun Bharti IIIT DelhiDelhiIndia varun22562@iiitd.ac.in, Shashwat Jha IIIT DelhiDelhiIndia shashwat22472@iiitd.ac.in, Dhruv Kumar BITS PilaniPilaniIndia dhruv.kumar@pilani.bits-pilani.ac.in and Pankaj Jalote IIIT DelhiDelhiIndia jalote@iiitd.ac.in

(2018)

###### Abstract.

Loop invariants are essential for proving the correctness of programs with loops. Developing loop invariants is challenging, and fully automatic synthesis cannot be guaranteed for arbitrary programs. Some approaches have been proposed to synthesize loop invariants using symbolic techniques and more recently using neural approaches. These approaches are able to correctly synthesize loop invariants only for subsets of standard benchmarks. In this work, we investigate whether modern, reasoning-optimized large language models can do better. We integrate OpenAI’s O1, O1-mini, and O3-mini into a tightly coupled generate-and-check pipeline with the Z3 SMT solver, using solver counterexamples to iteratively guide invariant refinement. We use Code2Inv benchmark, which provides C programs along with their formal preconditions and postconditions. On this benchmark of 133 tasks, our framework achieves 100% coverage (133/133), outperforming the previous best of 107/133, while requiring only 1–2 model proposals per instance and 14–55 seconds of wall-clock time. These results demonstrate that LLMs possess latent logical reasoning capabilities which can help automate loop invariant synthesis. While our experiments target C-specific programs, this approach should be generalizable to other imperative languages.

Loop invariants, Formal Verification, Large Language Models, SMT, Program Analysis

††copyright: acmlicensed††journalyear: 2018††doi: XXXXXXX.XXXXXXX††conference: Make sure to enter the correct conference title from your rights confirmation email; June 03–05, 2018; Woodstock, NY††isbn: 978-1-4503-XXXX-X/2018/06††ccs: Software and its engineering Software verification and validation††ccs: Software and its engineering Software verification††ccs: Theory of computation Invariants††ccs: Theory of computation Program specifications††ccs: Theory of computation Program analysis††ccs: Theory of computation Program verification††ccs: Computing methodologies Natural language processing

## 1. Introduction

Loop invariants are logical assertions that characterize exactly those program states that hold both immediately before and immediately after each iteration of a loop. Concretely, consider the annotated fragment

| $$\{P\}\;\mathbf{while}\;(B)\;\{S\};\;\{Q\}$$ |
| --- |

where $P$ is the precondition, $B$ the loop guard, $S$ the loop body, and $Q$ the postcondition. An invariant $I$ must satisfy three finite checks:

| $$P\;\implies\;I,\quad I\land B\;\implies\;I^{\prime},\quad I\land\neg B\;\implies\;Q,$$ |
| --- |

where $I^{\prime}$ denotes $I$ interpreted over the state resulting from executing $S$ . By discharging these implications, deductive verifiers avoid reasoning about an unbounded number of loop iterations, making loop invariants indispensable for proving correctness properties automatically.

Despite this, generating correct inductive invariants is a major bottleneck. Invariant synthesis is undecidable in general, and manual annotation is tedious and error-prone. While automated techniques exist, key challenges remain. Static methods like abstract interpretation overapproximate reachable states via numeric domains (intervals, octagons, polyhedra) (Cousot and Cousot, 1977; Blanchet et al., 2003), but require expert domain choices and struggle with non-linear or modular patterns. Counterexample guided abstraction refinement ( CEGAR )refines abstractions (Clarke et al., 2003). Template-based solvers assume invariant shapes and solve for parameters (Gulwani et al., 2008), failing outside predefined templates. Interpolation techniques extract invariants from failed proofs (McMillan, 2003), but depend on finding such proofs. Dynamic tools like Daikon mine likely invariants from traces (Ernst et al., 2007), but require formal validation and can miss edge cases.

Figure 1. Flow diagram of the generate–and–check loop used for invariant synthesis.

Machine learning approaches aim to learn patterns from data. Code2Inv treats invariant synthesis as a reinforcement learning task, training a policy network to interact with an SMT solver, solving 92/133 benchmarks (Si et al., 2018). CLN2Inv and its nonlinear variants learn differentiable representations, capturing polynomial and complex relations (Ryan et al., 2020; Yao et al., 2020), but are data-dependent and generalize poorly to unseen structures.

Recent work has explored using large language models for loop invariant generation (Pei et al., 2023), (Wu et al., 2024), with LEMUR (Wu et al., 2024) emerging as a particularly influential framework. LEMUR prompts GPT-3.5(Ye et al., 2023) and GPT-4(Achiam et al., 2023) with loop code and associated verification conditions to synthesize candidate invariants. A key innovation is its feedback mechanism: when a generated invariant fails verification, counterexamples are extracted and incorporated into the next prompt to guide refinement. This generate–check–repair loop enables LEMUR to achieve strong performance, solving 107 out of 133 benchmarks in the Code2Inv dataset (Wu et al., 2024).

Our framework adopts the principle of prompt refinement guided by counterexamples, but extends it beyond LEMUR’s C-specific toolchain. While LEMUR integrates with C‑specific SMT‑based model checkers such as CBMC, ESBMC, and UAutomizer, our approach leverages Z3, an SMT-LIB–compliant solver agnostic to the source language. This design enables broader applicability: any imperative language can be supported by emitting suitable SMT encodings.

To motivate the generate–and–check framework, we first show how any candidate invariant $I$ can be validated by reducing it to a sequence of SMT-LIB satisfiability queries. Given precondition $P$ , loop guard $B$ , and postcondition $Q$ , we assert the negation of each verification condition in SMT-LIB. Concretely, we generate three assertions:

| (assert (not (=> P I))) |
| --- |
| (assert (not (=> (and I B) I’))) |
| (assert (not (=> (and I (not B)) Q))) |
| $\displaystyle\texttt{followed by {(check-sat)}}.$ |

This reduction to a finite sequence of SMT queries naturally enables the integration of LLM-generated invariant candidates with automatic, solver-driven validation and iterative refinement.

In this work, we present our approach to loop invariant generation that tightly integrates powerful reasoning based language models with language neutral automated verifiers. Our framework iteratively alternates between two core phases: (1) An inference phase, where the model synthesizes a candidate invariant from the program text and specification, and (2) a formal verification phase, where an SMT solver checks the candidate against the initialization, inductive, and postcondition obligations. Whenever the solver detects a failure, it produces a concrete counterexample that is fed back into the next inference prompt, guiding the model to refine or strengthen its proposal. This generate-and-check paradigm ensures that every accepted invariant is formally proven correct, while exploiting the model’s capacity for semantic insight and pattern recognition. We evaluate the framework on Code2Inv benchmark (Si et al., 2018),achieving 100% coverage on all cases. The performance gains arise primarily from selecting reasoning optimized LMs rather than from the verifier itself. The models utilized are :

•

O1-mini (2024)(OpenAI, 2025b): a compact, fast model optimized for multi-step deduction under tight latency constraints.

•

O3-mini (2025)(OpenAI, 2025c): a next generation variant with expanded context and enhan

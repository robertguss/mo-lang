---
source_url: https://arxiv.org/abs/2509.22908
ingested: 2026-09-12
sha256: 176ce8c1d15196dbeb8366021a487f3f0091eb9d6952f44374ad89ae6429bee2
---
# A benchmark for vericoding: formally verified program synthesis

A benchmark for vericoding: formally verified program synthesis

arXiv is now an independent nonprofit! Learn more×

# A benchmark for vericoding: formally verified program synthesis

Sergiu Bursuc Theodore Ehrenborg Shaowei Lin Lacramioara Astefanoaei Ionel Emilian Chiosa Jure Kukovec Alok Singh Oliver Butterley Adem Bizid Quinn Dougherty Miranda Zhao Max Tan Max Tegmark

###### Abstract

We present and test the largest benchmark for vericoding, LLM-generation of formally verified code from formal specifications — in contrast to vibe coding, which generates potentially buggy code from a natural language description. Our benchmark contains 12,504 formal specifications, with 3,029 in Dafny, 2,334 in Verus/Rust and 7,141 in Lean. Of these, 6,174 are new unseen problems. We find vericoding success rates of 27% in Lean, 44% in Verus/Rust and 82% in Dafny using off-the-shelf LLMs. Adding natural-language descriptions does not significantly improve performance. We also find that LLM progress has improved progress on pure Dafny verification from 68% to 96% over the past year. The benchmark and vericoding results are shared in this GitHub repo. 11 1 Beneficial AI Foundation1 22 2 Massachusetts Institute of Technology2

## 1 Introduction

Rapid AI progress has popularized vibe coding, which generates computer programs from natural language descriptions. For example, Google has reported that over 30% of its software is created this way (Google Earnings Call). Unfortunately, the resulting code can be buggy, and traditional bug hunting with test cases can typically only demonstrate the presence and not the absence of bugs, since there are too many test cases to try them all. For example, major code-testing efforts failed to prevent bugs causing an Ariane-V rocket explosion (Ariane 5 Failure) and an embarrassing security vulnerability in the Bash shell (Shellshock Bug) that was built into the Unix operating system for 25 years before being discovered. The 2024 CrowdStrike outage disrupted 8.5 million devices globally, harming airlines, hospitals, banking, broadcasting, emergency services (CrowdStrike Outage).

Fortunately, rigorous correctness guarantees can be created via formal verification, by generating a machine-checkable proof that code meets its human-written specifications. Unfortunately, despite a venerable history dating back to Turing 1950, formal verification remains niche, applied to only a tiny fraction of all software because it requires much more human labor than programming does.

This makes it timely to test whether AI can help, either by verifying existing code or by writing new formally verifiable code from scratch based on its specification, which we term vericoding. The premise of this paper is that AI will soon be able to greatly facilitate both, dramatically reducing the cost of creating bug-free software. It is easy to imagine formal verification being simply a built-in final step of future compilers, which discover code problems and attempt to fix them automatically. One can also imagine a future where humans do not need to write programs, only specs.

This optimistic premise is based on the close analogy with automated theorem proving, where AI produces formal proofs not about code but about mathematical theorems. Fueled by the advent of benchmarks totaling over 100,000 theorems, AI tools have during the last few years improved their success rate from 21% to over 82% on the MetaMath benchmark (Polu & Sutskever 2020; Lample et al. 2022). In August 2025, Seed-Prover achieved over 50% on PutnamBench (Chen et al. 2025), proved 78.1% of formalized past mathematics olympiad problems, and scored 99.6% on the MiniF2F benchmark (up from a 50% SOTA mid 2024). Together with the Seed-Geometry engine, the models solved 5 of 6 problems at IMO 2025.

Unfortunately, formal verification sorely lacks correspondingly large benchmarks: the largest of their kind contain fewer than $10^{3}$ examples. There is room for expanding not only their size and diversity, but also their level of difficulty: Many examples are limited to single-function programs, and sometimes the formal specification for a program directly repeats an implementation of the algorithm. To support automation of formal verification and vericoding, the goal of the present paper is to provide such a benchmark expansion, by assembling and testing a suite of formal specifications for Lean (Moura & Ullrich 2021), Rust/Verus (Lattuada et al. 2024) and Dafny (Leino 2010).

The rest of this paper is organized as follows. We summarize related work in Section 2, and describe our benchmark construction in Section 3, outlining how vericoding sources were assembled or translated from natural language documentation, vibe coding datasets and verification benchmarks. In Section 4, we quantify the ability of current LLMs to solve vericoding tasks. Special attention is given to Lean tasks, because of recent successes in AI-assisted theorem proving. For example, we explore specifications expressed as Hoare triples using a new mvcgen feature. We summarize our conclusions in Section 5 and provide further technical details of our translation and vericoding approaches in the Appendix in the supplementary material.

## 2 Related Work

Over the past two years, there has been increased interest in constructing new benchmarks for verification (proofs from formal specifications and implementations) and vericoding (implementations and proofs from formal specifications), as seen in Table 1, much work remains. There is significant variation in the types of verification and vibe coding tasks. VerifyThisBench (Deng et al. 2025), for example, generates specs, implementations and proofs jointly from natural language descriptions. Meanwhile, VeriBench (Miranda et al. 2025) takes Python code and documentation, and generates implementations, specs and unit tests in Lean to be proved by the LLM. A novel form of vibe coding comes from the FVAPPS (Dougherty & Mehta 2025) benchmark which contains formal specs generated from natural language descriptions. For code synthesis, the LLM is given the descriptions and the formal specs, and specs and unit tests are employed to provide some formal correctness guarantees. Meanwhile, the field of AI control (Greenblatt et al. 2024) checks AI-produced code for correctness and safety using techniques such as oversight by weaker LLMs, but this does not produce formal guarantees.

In vericoding, no natural language descriptions are provided to the LLM for code generation. In benchmarks such as CLEVER (Thakur et al. 2025) and VERINA (Ye et al. 2025), the tasks include formal spec generation from documentation, in addition to formal and proof generation. Both benchmarks also require the Lean implementation to be synthesized before constructing a proof of its correctness. We acknowledge that spec generation is an important problem, but focus on the task of generating implementations and formal proofs in this work. We also let the LLM generate the implementation and the proof jointly — over several iterations, the model is allowed to change the implementation to make the proof easier or correct mistakes.

The challenge of constructing large coding benchmarks lies in gathering a large base of problems, formatting them and checking them for quality. DafnyBench (Loughridge et al. 2025) builds this base from existing benchmarks such as Clover and DafnySynthesis, and from GitHub scrapes. Large language models (LLMs) and other LLMs have facilitated this. FVAPPS (Dougherty & Mehta 2025) uses LLMs to translate Python tasks from the APPS benchmark to Lean, and to format the translations. AlphaVerus (Aggarwal et al. 2024) goes further with a self-improving framework that iteratively translates programs from Dafny to Verus and leverages feedback from the verifier. In our work, we instead use LLMs out of the box, using them not just for translation, but also for critiquing the translations and for fixing errors in them.

Table 1: Recent benchmarks for theorem proving, verification, vibe coding and vericoding. Verification and vericoding benchmarks are two orders of magnitude smaller than those for theorem proving and vibe coding. We list only benchmarks for Dafny, Verus and Lean. Notable benchmarks in other languages are SV-COMP (Beyer & Strejček 2025) and SyGuS (Alur et al. 2018) in C and Java, and FVELER (Lin et al. 2024) and AFP (Archive of Formal Proofs) in Isabelle. In comparison, we have 12504 tasks of which 6174 are new or translated from other benchmarks.

| Task | Benchmark | Language | Size |
| --- | --- | --- | --- |
| Thm proving | PutnamBench (Tsoukalas et al. 2024) | Lean, Isabelle, Coq | 1709 |
| Thm proving | FormalMATH (Yu et al. 2025) | Lean | 5560 |
| Thm proving | LeanDojo (Yang et al. 2023) | Lean | 98734 |
| Thm proving | LISA (Jiang et al. 2021) | Isabelle | 183000 |
| Verification | VeriBench (Miranda et al. 2025) | Lean | 113 |
| Verification | Verus-Bench (Yang et al. 2025) | Verus | 150 |
| Verification | Verified Cogen (JetBrains-Research 2025) | Verus (among others) | 223 |
| Verification | VerifyThisBench (Deng et al. 2025) | Dafny, Why3, etc. | 481 |
| Verification | DafnyBench (Loughridge et al. 2025) | Dafny | 782 |
| Vibe coding | HumanEval (Chen et al. 2021) | Python | 163 |
| Vibe coding | FVAPPS (Dougherty & Mehta 2025) | Lean | 4715 |
| Vibe coding | APPS (Hendrycks et al. 2021) | Python | 10000 |
| Vibe coding | CodeContests (Li et al. 2022) | Mixed | 13610 |
| Vibe coding | HumanEval-XL (Peng et al. 2024) | Mixed | 22080 |
| Vericoding | CLEVER (Thakur et al. 2025) | Lean | 161 |
| Vericoding | VERINA (Ye et al. 2025) | Lean | 189 |

## 3 Benchmark Construction

We are primarily interested in constructing a benchmark for two kinds of provers: automated theorem provers (ATPs) such as Dafny and Verus, which use SMT solvers to automatically discharge verification conditions, and interactive theorem provers (ITPs) such as Lean, which use tactics to build proofs. We begin by curating some original sources, such as HumanEval, Clever, Verina, APPS, and Numpy documentation. The original sources are then translated into other languages. Lastly, the translations are compiled, parsed into different sections, and quality-checked. We include tasks with specs that are incomplete, inconsistent, or non-compilable, because spec repair is an essential part of the formal verification workflow. Further details and scripts used in our construction can be found in the Appendix and in the supplementary material.

Table 2: Number of tasks for each language and source. Originals are in bold, and translations are not. The $*$ indicates new tasks. $X\!:\!Y$ indicates that $X$ tasks were generated during translation, and $Y$ tasks remained after compiling, formatting and quality checks. We use only the latter tasks for our experiments. We release also the problematic tasks in case there is interest to use them for other purposes, such as spec repair. The task IDs are of the form XYdddd where X indicates the language (Dafny, Lean, Verus), Y refers to the source (see the Ref column in the table) and dddd is a four-digit zero-padded number starting from 0000.

| Source | Ref | Dafny | Verus | Lean | Total |
| --- | --- | --- | --- | --- | --- |
| APPS (Test) | A | 883 : 677 * | 677 : 536 * | 677 : 676 * | 2237 : 1889 |
| $\mathsf{DafnyBench}$ | D | 929 : 443 | 442 : 440 * | 440 : 440 * | 1811 : 1323 |
| NumpyTriple | T | 603 : 603 * | 603 : 581 * | 666 : 603 * | 1872 : 1787 |
| VerifiedCogen | J | 172 : 172 * | 172 : 172 | 172 : 172 * | 516 : 516 |
| Verina | V | 157 : 157 * | 157 : 156 * | 189 : 189 | 503 : 502 |
| Bignum | B | 62 : 62 * | 62 : 62 * | 62 : 62 * | 186 : 186 |
| NumpySimple | S | 59 : 58 * | 59 : 58 * | 59 : 59 * | 177 : 175 |
| HumanEval | H | 164 : 162 | 162 : 161 * | 161 : 1611 | 487 : 484 |
| FVAPPS | F | | | 4715 : 4006 | 4715 : 4006 |
| Total | | 3029 : 2334 | 2334 : 2166 | 7141 : 6368 | 12504 : 10868

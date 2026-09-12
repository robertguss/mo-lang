---
source_url: https://arxiv.org/abs/2512.15816
ingested: 2026-09-12
sha256: b5d1a7e820964b80550e3d86232ed818b5cdbee8fbb33813e14d4244f521d469
---
# A Neurosymbolic Approach to Loop Invariant Generation via Weakest Precondition Reasoning

A Neurosymbolic Approach to Loop Invariant Generation via Weakest Precondition Reasoning

\hideLIPIcs

Department of Computer Science and Statistics, Trinity College Dublin, Dublin, Ireland kingd6@tcd.ieLero, Research Ireland Centre for Software and Department of Computer Science and Statistics, Trinity College Dublin, Dublin, Ireland vasileios.koutavas@tcd.ie Faculty of Informatics, TU Wien, Vienna, Austrialaura.kovacs@tuwien.ac.at \CopyrightDaragh King, Vasileios Koutavas, and Laura Kovács\ccsdesc[500]Software and its engineering Formal software verification \ccsdesc[500]Theory of computation Program verification \ccsdesc[300]Computing methodologies Artificial intelligence

# A Neurosymbolic Approach to Loop Invariant Generation via Weakest Precondition Reasoning

Daragh King111Corresponding Author Vasileios Koutavas Laura Kovács

###### Abstract

Loop invariant generation remains a critical bottleneck in automated program verification. Recent work has begun to explore the use of Large Language Models (LLMs) in this area, yet these approaches tend to lack a reliable and structured methodology, with little reference to existing program verification theory. This paper presents NeuroInv, a neurosymbolic approach to loop invariant generation. NeuroInv comprises two key modules: (1) a neural reasoning module that leverages LLMs and Hoare logic to derive and refine candidate invariants via backward-chaining weakest precondition reasoning, and (2) a verification-guided symbolic module that iteratively repairs invariants using counterexamples from OpenJML. We evaluate NeuroInv on a comprehensive benchmark of 150 Java programs, encompassing single and multiple (sequential) loops, multiple arrays, random branching, and noisy code segments. NeuroInv achieves a $99.5\%$ success rate, substantially outperforming the other evaluated approaches. Additionally, we introduce a hard benchmark of $10$ larger multi-loop programs (with an average of $7$ loops each); NeuroInv’s performance in this setting demonstrates that it can scale to more complex verification scenarios.

###### keywords:

Loop invariants, Program verification, Hoare logic, Neurosymbolic AI, Large language models

## 1 Introduction

Loop invariant generation is a central challenge in automated program verification. Within Hoare logic [hoare-logic], loop invariants are the inductive assertions for establishing the correctness of looping computations; loop invariants must: (a) hold before the loop, (b) be preserved by each loop iteration, and (c) imply the loop postcondition upon exit (see Section 1.1 for additional details on Hoare logic and loop invariants). Despite their conceptual simplicity, discovering suitable loop invariants is an undecidable problem and notoriously difficult to achieve with heuristics. Traditional static techniques—including abstract interpretation [cousot1977abstract], logical abduction [calcagno2009bi], symbolic execution [nguyen2017symlnfer], and recurrence solving [humenberger2017invariant]—perform well in narrow domains but often struggle to generalise across programs with more complex structures, such as programs with multiple loops. Dynamic approaches such as [ernst2007daikon] can infer loop invariants from program executions, but their soundness is fundamentally constrained by the trace quantity and quality.

The advent of Large Language Models (LLMs) has led to recent work exploring whether they can generate program properties such as weakest preconditions [11024288, king2025fuzzfeedautomaticapproachweakest], postconditions [endres2024can], and even loop invariants [pei2023can, janssen2024can]. While these early investigations demonstrate promise, existing LLM-based approaches to loop invariant generation typically rely on ad-hoc prompting, and provide no systematic alignment with program verification theory. Moreover, because these methods lack a principled mechanism for the guided refinement of loop invariants, the invariants that are produced are often brittle (both syntactically and semantically) — these invariants may be sufficient for simple integer loops but unreliable for programs involving arrays, multiple loops, or noisy and semantically irrelevant code.

To address these limitations in LLM-based loop invariant inference, we introduce NeuroInv, a neurosymbolic [garcez2023neurosymbolic] framework for loop invariant generation that integrates LLMs with weakest precondition (WP) reasoning [wp-calculus] and counterexample-guided symbolic verification. NeuroInv comprises two complementary modules. The neural module segments the input program into loop-free and looping components, it then leverages an LLM to perform three primary tasks: (1) calculate WPs of loop-free code segments, (2) generate candidate loop invariants, and (3) check and refine candidate loop invariants according to the preservation and exit obligations defined by Hoare logic (Section 1.1) – when the aforementioned obligations fail, the module attempts targeted refinement of the candidate loop invariant. The process employed by the neural module yields a structured and theory-guided reasoning procedure that stands in contrast to ad-hoc prompting approaches [janssen2024can].

The symbolic module strengthens the above approach by validating the neurally-derived invariants using OpenJML, extracting counterexamples when verification fails, and attempting invariant repair through a feedback-directed process. This dual-level refinement and repair approach enables NeuroInv to reliably generate correct loop invariants.

We evaluate NeuroInv on a comprehensive benchmark of 150 Java programs, encompassing single and multiple (sequential) loops, multiple arrays, random branching, and noisy code segments. NeuroInv achieves a $99.5\%$ success rate, substantially outperforming ad-hoc prompting, neural-only ablations, and a state-of-the-art LLM-based specification generator for Java [ma2024specgen]. A hard benchmark of $10$ larger multi-loop programs further demonstrates that NeuroInv scales effectively to more complex programs, with the neural module playing a key role in handling longer and more complex reasoning chains. Taken together, these results illustrate that systematic WP reasoning, when integrated with verification feedback, significantly enhances the robustness and reliability of LLM-assisted invariant generation.

The remainder of the paper is structured as follows. Section 1.1 outlines the requisite background on Hoare logic [Floyd67, hoare-logic], weakest preconditions [wp-calculus], and loop invariants necessary for understanding NeuroInv. Section 2 presents the method behind NeuroInv, while Section 3 outlines our experimental evaluation and the obtained results. Section 4 discusses threats to validity and future work. Section 5 highlights related work, and Section 6 concludes.

### 1.1 Hoare Logic, Weakest Preconditions and Loop Invariants

Hoare logic provides a formal system for reasoning about the correctness of imperative programs. The core unit of this logic is the Hoare triple (Definition 1.1). Hoare triples fundamentally rely on the notions of pre- and postconditions: postconditions specify the desired property of the program state upon termination, whilst preconditions specify the required property of the initial program state for it to behave as intended (i.e. to satisfy the program’s postcondition). The logic has a total and partial correctness version, depending on whether it proves termination or not. Here, we focus on partial correctness.

###### Definition 1.1 (Hoare Triple (Partial Correctness)).

A Hoare triple $\{P\}\ C\ \{Q\}$ asserts that if the precondition $P$ holds before executing command $C$ , and $C$ terminates, then the postcondition $Q$ holds after execution.

Reasoning over Hoare triples enables compositional program verification, but to do so effectively one must carefully consider the notion of a precondition. Consider the Hoare triple $\{P\}\ C\ \{Q\}$ , if $P$ 

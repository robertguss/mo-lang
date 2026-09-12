---
source_url: https://www.alphaxiv.org/abs/2602.09447
ingested: 2026-09-12
sha256: 3db99961200cc1e6e4a1ac81581c5f613585ee42e391baf4e5b14ae4d9279695
---
# SWE-AGI: Benchmarking Specification-Driven Software Construction with MoonBit in the Era of Autonomous Agents | alphaXiv

SWE-AGI: Benchmarking Specification-Driven Software Construction with MoonBit in the Era of Autonomous Agents | alphaXiv

Submitted 11 Feb 2026

# SWE-AGI: Benchmarking Specification-Driven Software Construction with MoonBit in the Era of Autonomous Agents

Zhirui Zhang

HZ

Hongbo Zhang

HF

Haoxiang Fei

ZB

Zhiyuan Bao

YC

Yubin Chen

ZL

Zhengyu Lei

Ziyue Liu

Yixuan Sun

+6 more Show less

MX

Mingkun Xiao

ZY

Zihang Ye

YZ

Yu Zhang

HZ

Hongcheng Zhu

YW

Yuxiang Wen

Heung-Yeung Shum

## Abstract

Although large language models (LLMs) have demonstrated impressive coding capabilities, their ability to autonomously build production-scale software from explicit specifications remains an open question. We introduce SWE-AGI, an open-source benchmark for evaluating end-to-end, specification-driven construction of software systems written in MoonBit. SWE-AGI tasks require LLM-based agents to implement parsers, interpreters, binary decoders, and SAT solvers strictly from authoritative standards and RFCs under a fixed API scaffold. Each task involves implementing 1,000-10,000 lines of core logic, corresponding to weeks or months of engineering effort for an experienced human developer. By leveraging the nascent MoonBit ecosystem, SWE-AGI minimizes data leakage, forcing agents to rely on long-horizon architectural reasoning rather than code retrieval. Across frontier models, gpt-5.3-codex achieves the best overall performance (solving 19/22 tasks, 86.4%), outperforming claude-opus-4.6 (15/22, 68.2%), and kimi-2.5 exhibits the strongest performance among open-source models. Performance degrades sharply with increasing task difficulty, particularly on hard, specification-intensive systems. Behavioral analysis further reveals that as codebases scale, code reading, rather than writing, becomes the dominant bottleneck in AI-assisted development. Overall, while specification-driven autonomous software engineering is increasingly viable, substantial challenges remain before it can reliably support production-scale development.

## Overview

SWE-AGI represents a new approach to evaluating AI systems' ability to autonomously construct complete software systems from explicit specifications. Unlike existing benchmarks that focus on code completion or bug fixes within existing repositories, this benchmark challenges agents to build production-scale software from scratch using only high-level requirements and authoritative standards.

The research addresses a critical gap in current evaluation methodologies: while large language models demonstrate impressive coding abilities on isolated tasks, their capacity to orchestrate end-to-end software development remains inadequately assessed. SWE-AGI introduces 22 complex tasks requiring agents to implement complete systems like parsers, compilers, and networking protocols, with implementations typically spanning thousands of lines of code.

## Methodology and Benchmark Design

The benchmark employs MoonBit, a relatively new programming language, as its implementation target. This choice is strategic - MoonBit's limited presence in large-scale training corpora minimizes the risk of agents relying on memorized solutions rather than genuine reasoning. The language's features, including type soundness, exhaustive pattern matching, and declaration-first workflow support, provide agents with high-quality feedback during development cycles.

Each task in SWE-AGI follows a standardized structure:

- Task Statement: Detailed acceptance criteria and constraints in `TASK.md`
- Normative References: Authoritative specifications and standards in the `specs/` directory
- API Scaffold: Pre-defined public interfaces using MoonBit's `*_spec.mbt` files
- Public Tests: Visible test subset for local validation in `*_pub_test.mbt`

The evaluation process requires agents to interpret specifications, implement logic against fixed APIs, validate using public tests, and submit solutions via `swe-agi-submit`. Final assessment occurs against hidden private test suites to prevent overfitting.

The 22 tasks span seven categories: template/DSL parsers, data serialization formats, markup processors, programming language front-ends, binary decoders, networking protocols, and automated reasoning systems. Tasks are stratified into three difficulty levels: 6 easy, 8 medium, and 8 hard, based on estimated implementation complexity and semantic requirements.

## Agent Evaluation and Performance Analysis

The evaluation examined multiple frontier language models including GPT-5.3-codex, GPT-5.2-codex, Claude Opus variants, and several other contemporary models. Agents interacted with repositories through specialized command-line interfaces tailored to each model's capabilities.

Performance revealed a sharp difficulty gradient across task tiers. All evaluated frontier agents achieved perfect success on easy tasks (6/6), demonstrating reliable execution of the complete development loop for simpler parsing and decoding challenges. However, performance diverged significantly on more complex tasks:

GPT-5.3-codex emerged as the strongest performer, solving 19/22 tasks overall (86.4%), including all medium-tier tasks and 5/8 hard tasks. The model demonstrated superior time efficiency, requiring 3-5 times less wall-clock time than its predecessor while achieving higher completion rates.

GPT-5.2-codex completed 17/22 tasks (77.3%), with notable struggles on hard-tier challenges requiring sustained architectural reasoning. One striking case involved a 42-hour execution on the `ecma262` JavaScript parser task, ultimately producing over 30,000 lines of code without passing the final test suite.

Claude Opus models showed significant version-to-version improvement, with Opus-4.6 solving 15/22 tasks versus Opus-4.5's 10/22 completion rate. However, this improvement often came with increased development time, suggesting more extensive exploration and debugging processes.

Rapid assessment of other contemporary models on easy tasks revealed substantially lower success rates, with most achieving only 0-2 completions out of 6 attempts, highlighting SWE-AGI's effectiveness in differentiating agent capabilities.

## Behavioral Insights and Bottleneck Analysis

Analysis of agent interaction logs revealed critical patterns in how different models approach complex software construction. As task difficulty increased, a fundamental shift occurred in effort allocation:

$Read Actions=Code Understanding TimeTotal Development Time\text{Read Actions} = \frac{\text{Code Understanding Time}}{\text{Total Development Time}}$ Read Actions= Total Development Time Code Understanding Time​

On hard tasks, code reading became the dominant activity:

- GPT-5.3-codex: 41.4% of actions
- GPT-5.2-codex: 64.6% of actions
- Claude Opus-4.6: 50.2% of actions
- Claude Opus-4.5: 43.5% of actions

This finding challenges conventional assumptions about AI-assisted development bottlenecks. Rather than raw code generation being the primary hurdle, maintaining architectural consistency and understanding complex, evolving codebases emerged as the critical constraint for scaling to production systems.

Strategic differences also emerged between models. GPT-5.3-codex exhibited a more iteration-oriented profile, allocating greater effort to debugging (19.8% vs. 9.2% for GPT-5.2-codex on hard tasks) while requiring fewer total interactions. Claude Opus-4.6 demonstrated improved specification engagement and planning compared to its predecessor, dedicating more effort to comprehension activities rather than reactive patching.

## Near-Miss Analysis and Specification Adherence

Many "failed" submissions achieved high test-suite pass rates, often succeeding on 95%+ of evaluation cases. For example, GPT-5.2-codex achieved 99.8% pass rate on the `cdcl` SAT solver task, while Claude Opus-4.5 reached 96.4% on the Lua interpreter implementation. These near-misses indicate that remaining defects typically involved subtle normative requirements, state-machine corner cases, or performance constraints rather than fundamental architectural failures.

This pattern suggests that the transition from research-grade to production-grade autonomous development hinges on agents' ability to handle specification edge cases and maintain strict adherence to formal standards - capabilities that require deeper reasoning about implicit requirements and exhaustive validation strategies.

## Implications for Autonomous Software Engineering

SWE-AGI's findings carry significant implications for the field's trajectory. The benchmark demonstrates that specification-driven autonomous software construction is becoming increasingly feasible for well-defined, moderate-complexity systems. However, the sharp performance degradation on complex tasks reveals substantial challenges that must be addressed before agents can reliably support production development.

The dominance of code comprehension bottlenecks, particularly for large systems, suggests that future agent architectures should prioritize capabilities beyond code generation. Advanced reasoning about system architecture, maintaining long-term codebase coherence, and effective debugging of complex interactions will likely determine success in autonomous software engineering applications.

For the broader research community, SWE-AGI provides a rigorous evaluation framework that isolates genuine engineering capabilities from memorization effects. The benchmark's emphasis on specification adherence, architectural reasoning, and sustained implementation offers a complementary assessment paradigm to existing function-level and repository-based evaluations, helping advance the development of more capable autonomous software engineering systems.

SWE-bench: Can language models resolve real-world GitHub issues?

This paper introduces the SWE-bench framework, which the SWE-AGI paper frequently uses as a primary point of contrast. SWE-AGI positions itself as a fundamentally different, specification-driven paradigm compared to SWE-bench's approach of resolving issues within existing repositories, making this citation crucial for understanding its novelty.

C. E. Jimenez, J. Yang, A. Wettig, et al. SWE-bench: Can language models resolve real-world GitHub issues? arXiv preprint arXiv:2310.06770, 2023. URL https://arxiv.org/abs/2310.06770.

Evaluating large language models trained on code

This work introduced the foundational HumanEval benchmark, which evaluates function-level code synthesis. The SWE-AGI paper references it to contextualize the evolution of code generation benchmarks, highlighting its own focus on much larger, system-scale construction as a significant step forward in complexity and realism.

M. Chen, J. Tworek, H. Jun, Q. Yuan, H. P. de Oliveira Pinto, J. Kaplan, H. Edwards, Y. Burda, N. Joseph, G. Brockman, A. Ray, R. Puri, G. Krueger, M. Petrov, H. Khlaaf, G. Sastry, P. Mishkin, B. Chan, S. Gray, N. Ryder, M. Pavlov, A. Power, L. Kaiser, M. Bavarian, C. Winter, J. Hilton, R. Nakano, C. Hesse, J. Chen, E. Sigler, D. Ziegler, N. Stiennon, J. Wu, A. Radford, D. Amodei, and I. Sutskever. Evaluating large language models trained on code. arXiv preprint arXiv:2107.03374, 2021. URL https://arxiv.org/abs/2107.03374.

SWE-Bench pro: Can AI agents solve long-horizon software engineering tasks?

As a recent and more difficult version of SWE-bench, this citation represents the state-of-the-art in the repository-issue resolution paradigm. By contrasting with SWE-Bench Pro, the paper argues that its specification-driven approach provides a cleaner evaluation signal for long-horizon reasoning, minimizing confounding factors like repository-specific conventions.

X. Deng, J. Da, E. Pan, et al. SWE-Bench pro: Can AI agents solve long-horizon software engineering tasks?, 2025. URL https://arxiv.org/abs/2509.16941.

This paper introduced the MBPP dataset, another early and influential benchmark for evaluating small, problem-level program synthesis. It is referenced in the paper's comparison table to demonstrate how SWE-AGI moves beyond short-horizon coding problems to assess the autonomous, end-to-end construction of complex software systems.

J. Austin, A. Odena, M. Nye, M. Bosma, H. Michalewski, D. Dohan, E. Jiang, C. Cai, M. Terry, Q. Le, et al. Program synthesis with large language models. arXiv preprint arXiv:2108.07732, 2021. URL https://arxiv.org/abs/2108.07732.

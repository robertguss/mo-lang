---
source_url: https://arxiv.org/abs/2403.01632
ingested: 2026-09-12
sha256: c5a5e078f494bedddac986896ecc2c588e8e23d5727e6a19c161ea6a3e863bf3
---
# SynCode: LLM Generation with Grammar Augmentation

SynCode: LLM Generation with Grammar Augmentation

arXiv is now an independent nonprofit! Learn more×

# SynCode: LLM Generation with Grammar Augmentation

Shubham Ugare Affiliation: University of Illinois Urbana-Champaign, USA Tarun Suresh Affiliation: University of Illinois Urbana-Champaign, USA Hangoo Kang Affiliation: University of Illinois Urbana-Champaign, USA Sasa Misailovic Affiliation: University of Illinois Urbana-Champaign, USA Gagandeep Singh Affiliation: University of Illinois Urbana-Champaign and VMware Research, USA

###### Abstract

LLMs are widely used in complex AI applications. These applications underscore the need for LLM outputs to adhere to a specific format, for their integration with other components in the systems. Typically the format rules – e.g., data serialization formats such as JSON, YAML, or Code in Programming Language – are expressed as context-free grammar (CFG). Due to the hallucinations and unreliability of LLMs, instructing LLMs to adhere to specified syntax becomes an increasingly important challenge.

We present SynCode, a novel framework for efficient and general syntactical decoding with LLMs, to address this challenge. SynCode ensures soundness and completeness with respect to the CFG of a formal language, effectively retaining valid tokens while filtering out invalid ones. SynCode uses an offline-constructed, efficient lookup table, the DFA mask store, created from the DFA (Deterministic Finite Automaton) of the language’s grammar for efficient generation. SynCode seamlessly integrates with any language defined by CFG, as evidenced by experiments focusing on generating JSON, SQL, Python, and Go outputs. Our experiments evaluating the effectiveness of SynCode for JSON generation demonstrate that SynCode eliminates all syntax errors and significantly outperforms state-of-the-art baselines. Furthermore, our results underscore how SynCode significantly reduces 96.07% of syntax errors in generated Python and Go code, showcasing its substantial impact on enhancing syntactical precision in LLM generation.

Our code is available at https://github.com/uiuc-focal-lab/syncode

## 1 Introduction

Recent research has shown that transformer-based large language models (LLMs) can play a pivotal role within compound AI systems, where they integrate with other software tools Zaharia et al. (2024); Mialon et al. (2023). For example, OpenAI’s code interpreter OpenAI (2024) generates and executes Python programs automatically while responding to user prompts. Similarly, Wolfram Alpha wolfram (2024) translates user queries about mathematical questions into a domain-specific language (DSL) for utilizing various tools. LLMs are utilized in various other applications to translate natural language text into formal languages, such as inputs to logic solvers Pan et al. (2023); Olausson et al. (2023) and theorem provers Wu et al. (2022); Yang et al. (2023), among others. In all these applications, the LLM output is expected to follow a certain syntactic structure. However, challenges such as hallucination and non-robustness make LLMs unreliable for such automated systems Liang et al. (2023). Moreover, recent theoretical Hahn (2020); Yang et al. (2024) and empirical Ebrahimi et al. (2020); Bhattamishra et al. (2020); Delétang et al. (2023) research suggests that language models based on transformers show difficulty in learning basic formal grammars.

The interaction between software tools and LLMs commonly occurs through data serialization formats like JSON or YAML, or code in domain-specific or general-purpose programming languages, such as Python or Go. Despite advancements in techniques such as fine-tuning and prompt engineering, which enhance the model’s ability, these approaches fall short of fully addressing the challenge of syntactical accuracy in generated output. This problem is especially prominent in two common scenarios: (1) using open-source models, which are typically relatively small, and (2) generating text for formal languages with relatively modest representation in the LLM’s training data.

Modern LLMs generate text sequentially, from left to right, one token at a time. For each prefix, the model computes a probability distribution over a predefined vocabulary to predict the next token. The LLM’s decoding algorithm dictates how these probabilities are used to generate the token sequence. Very recently, researchers have proposed new techniques for grammar-guided generation to enhance the syntactical accuracy of LLMs by modifying the decoding algorithm. Although they ensure that the model consistently selects tokens that adhere to a specified formal language Scholak et al. (2021); Poesia et al. (2022); Gerganov and et. al. (2024); Willard and Louf (2023), the existing approaches for grammar-guided generation either suffer from high error rates, resulting in syntactically incorrect output or impose significant run time overhead in the inference:

•

Issues with syntactical accuracy: The language grammar consists of the terminals, fundamental building blocks of the language (e.g., keywords, operators). Typically, a lexer creates lexical tokens from the input, each token associated with a terminal from the grammar. The LLM tokens form part of the model’s fixed vocabulary, defined before training, and do not directly correspond to lexical tokens associated with any specific grammar. This discrepancy, known as token misalignment, presents a significant challenge in ensuring precise grammar-guided generation Poesia et al. (2022). Thus, formally showing the soundness of the algorithm poses a challenge for ensuring the precision of the approach.

•

Issues with high computational overhead: Typically, the computational complexity of additional operations performed for syntactical generation is lower than the standard LLM generation operations needed for propagating the input through LLM layers. However, these syntactical generation operations are typically executed sequentially on a CPU, in contrast to the GPU-accelerated LLM generation, adding to the run time. Achieving low inference overhead faces two primary challenges for syntactical LLM generation. First, the algorithm should facilitate offline computations that minimize the overhead during inference. Second, it should effectively utilize available hardware resources and offload additional computations to modern hardware, such as GPUs, to enable parallel computation.

•

Issues with generality: Prior works are restricted to specific LLM decoding schemes Scholak et al. (2021); Lundberg et al. (2023). A major challenge for generality is designing a composable algorithm that can integrate with any decoding strategy such as greedy, beam search, and different types of temperature sampling.

Our goal is to make grammar-guided generation precise and efficient by imposing formal grammar constraints on LLM generations, ensuring the output adheres strictly to the predefined syntax.

SynCode. SynCode is an efficient and general approach for generating syntactically correct output. SynCode takes a context-free grammar (CFG) represented with extended Backus–Naur form (EBNF) rules and ensures that the LLM output follows the provided grammar. SynCode algorithm is general and can be composed with any existing LLM decoding algorithm, including greedy, beam search, and sampling.

During the LLM decoding stage, where LLM selects the next token, SynCode employs a strategic two-step approach. In the initial step, it leverages partial output to generate sequences of terminals that can follow the partial output called accept sequences. This reduction to the level of terminals—a closer abstraction to language grammar than LLM tokens—simplifies the problem. Simultaneously, SynCode computes a remainder from the partial output, representing the suffix that may change its terminal type in subsequent generations. In the second step, SynCode algorithm walks over the DFA using the remainder and uses 

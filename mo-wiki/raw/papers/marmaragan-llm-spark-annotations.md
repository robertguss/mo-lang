---
source_url: https://arxiv.org/abs/2502.07728
ingested: 2026-09-12
sha256: 2607c93338d586cf42cc0d25f8c6e1920ff0d2c81f2b77b37c9d1f1e53ab57db
---
# Verifying LLM-Generated Code in the Context of Software Verification with Ada/SPARK

Verifying LLM-Generated Code in the Context of Software Verification with Ada/SPARK

# Verifying LLM-Generated Code in the Context of Software Verification with Ada/SPARK

Marcos Cramer1 and Lucian McIntyre2 1secunet Security Networks AG, Dresden, Germany 2International Center for Computational Logic, Technical University Dresden, Germany marcos.cramer@secunet.com, lucianmcintyre@mailbox.org https://orcid.org/0000-0002-9461-1245 https://orcid.org/0009-0008-0408-4340

###### Abstract

Large language models (LLMs) have demonstrated remarkable code generation capabilities, but the correctness of the generated code cannot be inherently trusted. This paper explores the feasibility of using formal software verification, specifically the SPARK framework for Ada, to ensure the reliability of LLM-generated code. We present Marmaragan, a tool that leverages an LLM in order to generate SPARK annotations for existing programs, enabling formal verification of the code. The tool is benchmarked on a curated set of SPARK programs, with annotations selectively removed to test specific capabilities. The performance of Marmaragan with GPT-4o on the benchmark is promising, with correct annotations having been generated for 50.7% of the benchmark cases. The results establish a foundation for future work on combining the power of LLMs with the reliability of formal software verification.

## 1 INTRODUCTION

Large language models (LLMs) have attracted significant attention within both the AI research community and the general public due to their generative capabilities. Tools such as ChatGPT have demonstrated the potential of LLMs to automate and accelerate processes in diverse fields, with software development benefiting particularly from their ability to generate code. However, while LLMs showcase impressive creativity and adaptability, they also present risks. As these models operate as black boxes, the code they generate cannot inherently be trusted to be correct or error-free, posing challenges for real-world applications where reliability and safety are essential.

To address the uncertainties associated with LLM-generated code, formal verification techniques offer a promising solution. Formal software verification employs rigorous mathematical methods to prove the correctness of code against a specified set of properties, which can help ensure that software meets its intended specifications reliably. Integrating formal verification with LLM-generated code has the potential to mitigate risks, making it possible to harness the creative benefits of LLMs while maintaining a high standard of code quality and safety.

The current paper is motivated by the need to bridge the gap between the creative potential of LLMs and the necessity for reliable, error-free code. By leveraging formal verification techniques, specifically through the SPARK programming language, we aim to explore the feasibility of combining LLMs with formal verification to produce code that is both innovative and provably correct. This study investigates whether LLMs can generate annotations for SPARK programs, facilitating formal verification of the resulting code.

For this purpose, we have implemented Marmaragan, a tool that leverages an LLM in order to generate SPARK annotations for existing programs, enabling formal verification of the code using the GNATprove tool. Marmaragan can be viewed as a prototype for the backend of an AI-powered annotation generator that could run in the background of a SPARK editor. It incorporates features such as generating multiple solution attempts, retrying with additional context from GNATprove, and providing pre-compiled error messages to improve performance. Marmaragan can currently be combined with any LLM in the OpenAI API and has been most throughly tested with GPT-4o. It has parameters for the number of solutions generated in parallel, for the number of retries that Marmaragan attempts before giving up as well as for toggling a special chain-of-thought mode.

In order to evaluate how well Marmaragan performs depending on the value of its parameters, we created a benchmark based on a curated set of SPARK programs, from which annotations were selectively removed following various removal schemata. Experiments on the benchmark demonstrate Marmaragan’s competence in generating annotations: Overall, it generates correct annotations for 50.7% of the benchmark programs. Furthermore, the experiments shed light on what is the optimal balance between parallel solution attempts and retries in the light of limited computational resources.

By successfully generating correct annotations, we establish a foundation for future work: In the near to medium-term future, this research could contribute to making applications of formal verification of code reliability and safety more efficient. In the long term it could contribute a building block towards a hybrid tool that combines the power of LLMs with the reliability of software verification for generating fully verified programs.

In Section 2, we discuss the preliminaries of this paper in the areas of logic, formal software verification (with a focus on SPARK 2014) and large language models. The implementation of Marmaragan is presented in Section 3. In Section 4, we describe the methodology that we applied to create a benchmark for evaluating Marmaragan. The results of running Maramaragan with varying parameters on the benchmark are presented in Section 5, and in Section 6 we discuss these results. Section 7 presents related work. In section 8, we discuss future work before concluding in Section 9.

## 2 PRELIMINARIES

This section discusses the foundations the work is set upon and the work it relates to and is inspired by.

### 2.1 Formal Software Verification

Formal software verification is the process of proving the correctness of a software program with respect to a specified formal specification or property, using formal mathematical methods. It ensures that the software behaves as intended in all possible scenarios. In contrast with common non-formal testing techniques, which always cover only a limited number of scenarios and are thus vulnerable to having missed out on a scenario in which a bug takes effect, formal software verification covers all potential runs of the program. From now on, we will often use the equivalent term “formal verification” as a shorthand for “formal software verification”.

There are different methodological approaches to formal verification. For this paper, we don’t need to consider model checking and instead focus on deductive verification, which is “the process of turning the correctness of a program into a mathematical statement and then proving it” [Filliâtre, 2011]. In deductive verification, the desired behaviour of the program needs to be specified in a formal language. The task is then to prove that the program actually satisfies the specification for all possible inputs.

At the level of single functions in the program, this is realized through pre- and postconditions, which are assertions on values of variables that enter and exit given functions within our program, specifying properties and relationships [Hoare, 1969]. A precondition defines the conditions that must be met, so that a given function can be executed. Analogously, a postcondition defines the conditions that must be met directly subsequent to function execution. For example, a function computing $F(x,y)=x-y$ could have the precondition $x>y$ for ensuring that one stays in the realm of positive numbers. In this case, a sensible postcondition would be $F(x,y)>0$ , as this postcondition logically follows from the precondition and the definition of the function $F(x,y)$ . This kind of logical entailment needs to hold for every postcondition of a function, and this needs to be established through a formal proof. We say that there is proof obligation for deriving the postcondition.

### 2.2 SPARK 2014

SPARK 2014 [Moi, 2013] is a formally defined subset of the Ada programming language [AdaCore, 1980], designed to support the development of reliable and provably correct software [Barnes, 2012]. Its unambiguous semantics ensures that programs behave consistently and predictably. SPARK allows only specific constructs from Ada, ensuring compatibility with formal verification methods. Programs written in SPARK can be annotated with assertions, including preconditions and postconditions, to support modular deductive verification [Hoare, 1969].

SPARK has found application in multiple areas, including train control systems and space transportation [Dross et al., 2014], commercial aviation [Moy et al., 2013], air traffic management [Chapman and Schanda, 2014] and GPU design [Chapman et al., 2024].

Some annotations in SPARK take the form of pragma statements, such as:

pragma Assertion (condition);

These include constructs like Assert, Loop_Invariant (see section 2.2.1 below), and Loop_Variant, which facilitate detailed specification and verification. Additionally, SPARK ensures the absence of runtime errors, such as array bounds violations or division by zero, by verifying adherence to defined rules.

In SPARK, code is organized into two types of files: .ads and .adb. The .ads files, known as specification files, define the interface of modules, including function and procedure declarations along with their associated preconditions and postconditions. In contrast, the .adb files, or implementation files, contain the executable code and additional annotations such as Assert, Loop_Invariant, and Loop_Variant pragmas. This separation supports a clear distinction between the specification and implementation, facilitating modular reasoning and verification of SPARK programs.

The GNATprove toolchain is the primary mechanism for verifying SPARK programs. It operates in three stages:

•

Check: Ensures SPARK compatibility.

•

Flow: Analyzes data and information flow.

•

Proof: Verifies code against assertions and conditions using third-party theorem provers via Why3 [Filliâtre and Paskevich, 2013].

GNATprove translates SPARK code into proof obligations, resolving them using automated provers. This ensures compliance with user-defined and language-level constraints, making SPARK programs highly reliable.

GNATprove provides feedback in the form of errors and mediums. Errors typically indicate issues such as syntax or type errors that prevent the program from being executed. Mediums, on the other hand, result from proof obligations that could not be discharged, either because the statement being proved is false or due to missing annotations. When a statement is false, these mediums may include counterexamples generated by the tool to help identify the source of the issue.

#### 2.2.1 Loop Invariants

A loop invariant is a property that holds during each loop iteration. It can be viewed as the induction hypothesis in an inductive proof over the number of loop iterations. Consider the example in Listing 1.

Listing 1: Example of loop invariants for a SPARK function that doubles a number.

procedure Double_Number (X : in Natural; Result : out Natural) is

Count : Natural := 0;

begin

Result := 0;

while Count < X loop

pragma Loop_Invariant (Result = Count * 2);

pragma Loop_Invariant (Count < X);

Result := Result + 2;

Count := Count + 1;

end loop;

end Double_Number;

Here, the invariants state that the Result is twice the Count and that the loop counter does not exceed X.

### 2.3 Large Language Models and Transformers

The development of large language models (LLMs) has been a significant leap forward for AI development, spurred by the introduction of the transformer architecture by Vaswani et al. in “Attention Is All You Need” [Vaswani et al., 2017].

LLMs, which are specialized neural models with billions of parameters, excel at capturing patterns in text data to perform a variety of language tasks. These models evolved from earlier statistical lang

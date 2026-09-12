---
source_url: https://arxiv.org/abs/2406.08467
ingested: 2026-09-12
sha256: f288bccb9113cbb038e4ddf0ae0c99b95f042a06c73ffd118c6928799e2ede62
---
# DafnyBench: A Benchmark for Formal Software Verification

DafnyBench: A Benchmark for Formal Software Verification

arXiv is now an independent nonprofit! Learn more×

# DafnyBench: A Benchmark for Formal Software Verification

Chloe Loughridge* Affiliation: Harvard College Email: cloughridge@college.harvard.edu Qinyi Sun*† Affiliation: Massachusetts Institute of Technology Email: wendysun@mit.edu Seth Ahrenbach Email: seth.ahrenbach@omnifederal.com Federico Cassano Affiliation: Northeastern University Email: cassano.f@northeastern.edu Chuyue Sun Affiliation: Stanford University Email: chuyues@stanford.edu Ying Sheng Affiliation: Stanford University Email: ying1123@stanford.edu Anish Mudide Affiliation: Massachusetts Institute of Technology Email: amudide@mit.edu Md Rakib Hossain Misu Affiliation: University of California Irvine Email: mdrh@uci.edu Nada Amin Affiliation: Harvard University Email: namin@seas.harvard.edu Max Tegmark Affiliation: Massachusetts Institute of Technology Email: tegmark@mit.edu

###### Abstract

We introduce DafnyBench, the largest benchmark of its kind for training and evaluating machine learning systems for formal software verification. We test the ability of LLMs such as GPT-4 and Claude 3 to auto-generate enough hints for the Dafny formal verification engine to successfully verify over 750 programs with about 53,000 lines of code. The best model and prompting scheme achieved 68% success rate, and we quantify how this rate improves when retrying with error message feedback and how it deteriorates with the amount of required code and hints. We hope that DafnyBench will enable rapid improvements from this baseline as LLMs and verification techniques grow in quality.

**footnotetext: Equal contribution. Order determined alphabetically.††footnotetext: Corresponding author.

## 1 Introduction

Rapidly improving Large Language Models (LLMs) [1, 2, 3] are helping accelerate software development through co-pilots and other program synthesis tools. But how can we ensure that LLM-generated code meets our specifications and reliably does precisely what it is supposed to do? Indeed, this remains a persistent problem even with human-written code: major code-testing efforts failed to prevent e.g. bugs causing an Ariane-V rocket explosion [4] and embarrassing security vulnerabilities in ssh [5] and the Bash shell [6]. The latter was built into the Unix operating system for 25 years before being discovered.

Although formal verification can guarantee perfect reliability, providing rigorous mathematical proof that software meets specification, it has yet to gain widespread adoption because it is costly. Formally verifying code can easily take more than ten times as much human work as writing it in the first place. Moreover, existing formal-verification tools tend to involve a major learning curve above and beyond just learning to code, greatly reducing the pool of people able to do this work.

The premise of this paper is that AI will soon be able to greatly facilitate formal verification, and hopefully even fully automate it one day. This would drive its cost to near-zero, dramatically increase its adoption and dramatically reduce the prevalence of buggy software. It is easy to imagine formal verification becoming simply a built-in final step of future compilers, which discover code problems and perhaps even fix them automatically. This optimistic premise is based on the close analogy with automated theorem proving, where AI produces formal proofs not about code but about mathematical theorems. Fueled by the advent of benchmarks totaling over 100,000 theorems, AI tools have during the past few years improved their proof success fraction to over 82% [7, 8].

Unfortunately, formal verification sorely lacks correspondingly large benchmarks: the largest of their kind are Clover [9] and dafny-synthesis [10], containing 66 and 153 programs, respectively. There is room for expanding not only their size, but also their level of difficulty: For example, Clover is limited to single-function programs, and sometimes the formal specification for the program directly repeats the implementation of the algorithm (see Appendix F). To support automation of formal verification, the goal of the present paper is to provide such a benchmark expansion. We do so by assembling a suite of formally verified programs written in Dafny, a formal verification language that was developed for easy adoption by programmers due to its similarity with popular imperative programming languages such as Python and C++ [11]. In order for formal verification to succeed, most of these programs require supplementary text constituting “hints” to the automated theorem prover.

The rest of this paper is organized as follows. We summarize related work in Section 2, describe our benchmark construction in Section 3, and quantify the ability of current LLMs to solve benchmark verification tasks in Section 4. We summarize our results and discuss promising opportunities for further work in Section 5 . We provide further details on the benchmark construction and evaluation in appendices.

## 2 Related Work

As summarized in Table 1 below, there is a striking lack of training data for formal verification: while there are hundreds of thousands of training examples for proving mathematical theorems and over ten thousand training examples for synthesizing programs, there are only $66+153=219$ for proving program correctness. This motivates our work in the current paper to expand the benchmarks from Clover and dafny-synthesis.

Table 1: Summary of popular machine-learning benchmark datasets for proving mathematical theorems, synthesizing programs, and formally verifying programs. Size is measured by the number of samples in each dataset. In the formal reasoning datasets, each sample is usually a math problem or a theorem. In the program synthesis and verified software programming benchmarks, each sample corresponds to a program.

| Category | Dataset | Size |
| --- | --- | --- |
| Mathematical theorem proving | CoqGym [12] | 71,000 proofs |
| | LeanDojo [13] | 98,734 proofs |
| | PISA [14] | 138,000 proofs |
| | Natural Proofs [15] | 15,000 proofs |
| | Archive of Formal Proofs [16] | 1 million lines of code |
| Unverified program synthesis | APPS [17] | 10,000 programs |
| | HumanEvalX [18, 19] | 165 programs |
| | MBPP [20] | 974 programs |
| | SWEBench [21] | 2,294 programs |
| | LiveCodeBench [22] | grows weekly |
| Formal software verification | Clover [9] | 66 programs |
| | Dafny-synthesis [10] | 153 programs |

The 66 programs in the Clover benchmark are human-written. In contrast, dafny-synthesis translates 153 MBPP problems from Python to Dafny using GPT-4. While this method is more efficient than manual translation, it could potentially skew the distribution of represented problems away from real-world Dafny problems that may be too hard for GPT-4 to verify on its own [10]. Our dataset counterbalances this potentially skewed distribution by introducing problems verified by human programmers on GitHub.

Clover proposes the most sophisticated benchmark evaluation strategy to date for formally verifiable software: the authors suggest a six-way consistency check between code, docstrings, and hints. Their checker achieves an 87% acceptance rate of correct implementations on the Clover benchmark while rejecting all incorrect implementations [9]. The authors note that equivalence checking with natural language is currently weak, but can hopefully be improved upon [9]. We do not yet implement the full Clover evaluation scheme in DafnyBench, and instead deem a benchmark program "solved" if a model can make it pass the Dafny verifier without modifying the requires and ensures statements in the program and without using {:verify false} or assume false (see Appendix E for further details).

## 3 DafnyBench Dataset Construction

### 3.1 Sourcing Ground Truth Programs

In total, our DafnyBench benchmark contains 782`ground_truth` stand-alone Dafny programs that compile. These problems come from the following sources:

•

GitHub Scrape: We scraped all publicly available Dafny files on GitHub published on the before the end of 2023. The relevant files were returned from the GitHub API using the language:Dafny search command. We then de-duplicated these files using a minhash de-duplication script written by Chenghao Mou (described in Appendix A). The de-duplication process reduced the number of .dfy files from $\sim$ 15,000 to $\sim$ 5,000. We then attempted to verify each of these remaining files using the dafny verify command with a local installation of Dafny 4.3.0, and removed any files that did not verify. At this stage, we removed all of the files from the Clover repository [9], which had already been formatted as benchmark files. This left 1,112 files. We found that 374 of these files lacked ensures statements, and 459 of lacked`assert` and`invariant` clauses. We removed the union of these sets, which left us with 556`ground_truth` files. Out of these files, 113 verify without any compiler hints. To mitigate data contamination, models run on our benchmark should ideally not be trained on data from the repositories listed in Appendix D.

•

Clover: We added 62 ground truth textbook Dafny programs provided by the Clover dataset [9]. We formatted these to fit our benchmark style and removed their compiler hints. Out of these files, 23 verify without any compiler hints.

•

Dafny-synthesis: Finally, we included 164 Dafny programs provided by the dafny-synthesis benchmark. These problems have been translated from the MBPP benchmark [10]. Out of these files, 72 verify without any compiler hints.

- H Reproducibility Statement

The`ground_truth` programs in our dataset have on average 2.12 methods, 1.03 functions, and 1.40 lemmas. This places the mean complexity of our examples at a level higher than Clover alone, which has only one stand-alone method per example.

Table 2: Mean and maximum values that describe attributes of a DafnyBench test program.

| | Mean | Max |
| --- | --- | --- |
| # Methods | $2.12$ | $42$ |
| # Functions | $1.03$ | $42$ |
| # Lemmas | $1.40$ | $35$ |
| # Characters | $1916.47$ | $28736$ |
| # Hint characters | $261.23$ | $6019$ |

### 3.2 Task Design: Fill Hints

We have fully implemented the`fill_hints` task. For this task, we took a`ground_truth` program, removed all of its hints (i.e., all of the`assert` and`invariant` statements in the body of the code), and asked LLM to fill hints back in so that the resulting program could be verified with Dafny.

Figure 1: Overview of evaluating LLM on a DafnyBench test program.

We do not demarcate from where these hints have been removed, i.e., we do not insert /* TODO */ after we remove each annotation, which would make the task easier and not reflective of models utility in real-world use cases.

#### Evaluation Metric

An LLM’s attempt to fill hints back in for a test program is counted as a success if all following conditions are satisfied: 1) The reconstructed program is verified with Dafny; 2) LLM preserves all preconditions (`requires` statements) and postconditions (`ensures` statements); and 3) LLM does not use`{:verify false}` or`{assume false}` to "cheat."

Figure 2: An example ground_truth program that is fully verified with Dafny. To create the fill_hints task, we would remove the invariant lines from the program above.

method LinearSearch (a: array, P: T -> bool) returns (n: int)

ensures 0 <= n <= a.Length

ensures n == a.Length || P(a[n])

ensures forall i :: 0 <= i < n ==> !P(a[i])

{

n := 0;

while n != a.Length

invariant 0 <= n <= a.Length

invariant forall i :: 0 <= i < n ==> !P(a[i])

{

if P(a[n]) {

return;

}

n := n + 1;

}

}

## 4 Experiments

In this section, we report success rates for different models on the`fill_hints` task, as well as provide some insight into current LLMs’ capabilities at writing hints for formal verification.

### 4.1 Prompts & Hyperparameters

We tried to

---
source_url: https://www.microsoft.com/en-us/research/wp-content/uploads/2024/08/paper.pdf
ingested: 2026-09-12
sha256: 30352a344e9507078653edb93c1dd1af40b1156f09d98a06fa2d852013e70440
---
# RUSTASSISTANT: Using LLMs to Fix Compilation

## RUSTASSISTANT: Using LLMs to Fix Compilation

## Errors in Rust Code

Pantazis Deligiannis Microsoft Research, USA Email: pdeligia@microsoft.com

Akash Lal, Nikita Mehrotra, Rishi Poddar, Aseem Rastogi Microsoft Research, India Email: { akashl, nmehrotra, t-ripoddar, aseemr} @microsoft.com

Abstract—The Rust programming language, with its safety guarantees, has established itself as a viable choice for low level systems programming language over the traditional, unsafe alternatives like C/C++. These guarantees come from a strong ownership-based type system, as well as primitive support for features like closures, pattern matching, etc., that make the code more concise and amenable to reasoning. These unique Rust features also pose a steep learning curve for programmers. This paper presents a tool called RUSTASSISTANT that lever ages the emergent capabilities of Large Language Models (LLMs) to automatically suggest fixes for Rust compilation errors. RUS TASSISTANT uses a careful combination of prompting techniques as well as iteration between an LLM and the Rust compiler to deliver high accuracy of fixes. RUSTASSISTANT is able to achieve an impressive peak accuracy of roughly 74% on real-world compilation errors in popular open-source Rust repositories. We also contribute a dataset of Rust compilation errors to enable further research.

I. INTRODUCTION

Code comprehension capabilities of Large Language Mod els (LLMs) are disrupting the way we build and maintain software systems. LLMs are rapidly becoming an integral part of the workflow, starting from software development [1], to testing [2], repair and debugging [3], [4], [5], [6], [7], [8], [9], [10]. One can interact with pre-trained LLMs [11], [12], [13], [14], [15], without any need of fine-tuning, through prompts that details a particular task simply with instructions in natural language. Using prompt engineering to study and harness LLMs has become an active area of research [16], [17]. In this paper, we consider the task of fixing Rust [18] compilation errors using LLMs. Rust, with its safety guar antees, has established itself as a viable choice for low-level systems programming language over the traditional, unsafe alternatives like C/C++. Rust enjoys strong support from both the open-source community [19], [20], and technology companies alike [21], [22]. The Rust typechecker, with a novel borrow checker at its core, ensures that Rust programs are free of memory-safety errors and data races that have plagued low-level systems for decades. 1 In addition, Rust has primitive support for features like closures, pattern matching, etc., that make the code more concise and amenable to reasoning.

1A Microsoft study found that ∼ 70% of the vulnerabilities Microsoft assigns a CVE each year continue to be memory safety issues [23].

15 struct Foo { map: RwLock<HashMap<String, Bar>> 
}16 
17 impl Foo 
{18 pub fn get(&self, key: String) → &Bar 
{19 self.map.write().unwrap().entry(key).or insert(Bar::new()) 
20 
}21 } 

Fig. 1: Snippet from a Stack Overflow question

However, this also means that there is a steep learning curve for programmers coming to Rust for the first time. Although Rust tooling (compiler error messages, IDE support [24]) is well-designed to help programmers understand and fix the compilation errors, they can still be intimidating for Rust beginners. A recent survey by the Rust team [25] reports that 83% of the responders who adopted Rust at work found it to be challenging. Though adopting a new language and its ecosystem is always challenging, 27% of the responders also say that using Rust is at times a struggle. Consider, for example, Figure 1 showing snippet from a Stack Overflow question [26] about the following error that the Rust compiler emits on this code:

error[E0515]: cannot return value referencing temporary value 
−−> src/example.rs:21:4 
|19 | self.map.write().unwrap().entry(key).or insert(Bar::new()) 
| −−−−−−−−−−−−−−−−−−−−−ˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆ 
| | 
| returns a value referencing data owned by the current func 
| temporary value created here 

For non-experts, making sense of the Rust borrow checking rules, especially with mutex and concurrency can be daunting. And even if the solution is conceptually clear, one still needs to know about Rust libraries that can be used for the fix. Contributions: We present RUSTASSISTANT, an LLM based tool for automatically fixing Rust compilation errors. RUSTASSISTANT specializes prompt construction for the pur pose of fixing compilation errors, and uses a novel changelog format in order to harness the LLM capabilities (Section III). RUSTASSISTANT is capable of generating non-trivial fixes that are required for real-world scenarios. Section II shows how RUSTASSISTANT is able to fix the error described above. To evaluate RUSTASSISTANT, we built a dataset of Rust compilation errors collected from three different sources: (a) 270 micro-benchmarks that we have written ourselves,

covering 270/506 official Rust error codes [27], (b) 50 Rust 
programs collected from Stack Overflow questions, and (c) 
182 GitHub commits with compilation errors from the top 
100 Rust crates from crates.io (Section IV). 
Using RUSTASSISTANT, we systematically study and eval 
uate capabilities of two LLMs, GPT-3.5 [11] and GPT 
4 [12], for fixing Rust compilation errors. With GPT-4, we 
find that RUSTASSISTANT is able to fix 92.59% of the 
micro-benchmarks, 72% of the Stack Overflow programs, and 
73.63% of the GitHub commits. We also find that GPT 
4 performs better than GPT-3.5 in the task. We report on 
several ablation studies, to investigate the impact of prompting 
variations (Section V). 
We also demonstrate the generalizability of RUSTASSIS 
TANT beyond compilation errors. With only minor prompt 
modifications, it can handle linter errors generated by Rust 
Clippy, one of the most popular static analysis tool for Rust 
[28]. RUSTASSISTANT achieves an accuracy of 75% on the 
top-10 Rust crates for fixing Clippy-reported errors, which is 
almost 2.4 times better fix rate than Clippy’s own auto-fix 
feature (RQ4, Section V). 
We plan to open-source both our dataset as well as the 
implementation of RUSTASSISTANT2. 

II. OVERVIEW

This section provides an overview of RUSTASSISTANT and walks through the example from Section I. Scope: Our goal is to build a toolchain and systematically evaluate the capabilities of LLMs for generating fixes for Rust compilation errors. These fixes must pass the compiler and must also retain the intended semantics of the code. The former is an objective criterion while the latter is subjective. Since the code that we start with is not even well-typed, let alone have a well-defined semantics, one requires external judgement to assess the quality of a fix. In the evaluation of RUSTASSISTANT (Section V), we either rely on test cases (fix must build and pass the test) or a comparison with the actual fix made by a developer to establish quality. We focus on fixing code-related issues and, thus, consider editing only the Rust source files. Errors that require changing a configuration (e.g., adding a package to a .toml file) are currently out of scope. We also do not consider errors related to the use of the unsafe keyword, which provides an escape hatch from the typechecker. 3 Example: The code snippet in Figure 1 contains struct Foo, which maintains a HashMap mapping String keys to Bar values. The hashmap is concurrency-protected with a RwLock, a locking mechanism in Rust that allows multiple readers but at-most one writer at a time. The programmer’s intent in the function get is to return a reference to the value mapped to key in the hashmap.

2See https://aka.ms/rust-build-fix 3We note that the unsafe keyword actually does not turn off all type checking in Rust. In some cases, especially when interacting with C APIs, an idiomatic translation might necessarily require the use of unsafe. Inves tigating the performance of LLMs in generating idomatic unsafe code, while interesting, is outside the scope of this paper.

ChangeLog:1@src/example.rs 
FixDescription: Change the return type of the ’get’ method to 
return an Arc and wrap the Bar in an Arc when inserting 
it into the HashMap. 
OriginalCode@19−23: 
[19] impl Foo 
{[20] pub fn get(&self, key: String) → &Bar 
{[21] self.map.write().unwrap().entry(key).or insert(Bar::new()) 
[22] 
}[23] 
}FixedCode@19−24: 
[19] impl Foo 
{[20] pub fn get(&self, key: String) → std::sync::Arc 
{[21] self.map.write().unwrap().entry(key).or insert with( 
[22] || std::sync::Arc::new(Bar::new())).clone() 
[23] 
}[24] } 

Fig. 2: Output of RUSTASSISTANT.

error[E0308]: mismatched types 
−−> src/example.rs:22:6 
22 | || std::sync::Arc::new(Bar::new())).clone() 
| ˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆ 
| expected struct ‘Bar’, found struct ‘Arc’ 

Fig. 3: Error after the first fix suggested by RUSTASSISTANT

The implementation of get first calls RwLock::write to get exclusive write access to the hashmap object. The write access is released as the guard goes out-of-scope, e.g., when the function call returns. The function then proceeds to read the value of key, and return a reference to the read value. When this code is compiled, the compiler complains with the error shown in Section I. Rust maintains a list of all the error codes that can be emitted by the compiler [27]. Here the error code is E0515 on line 21, meaning that the function is trying to return reference to a local variable. The error comes from the Rust borrow checker. The returned reference, which is derived from the mutex owned hashmap, escapes the function scope, and therefore, outlives the mutex guard lifetime—a violation of the borrow checking rules. Let’s see how RUSTASSISTANT fixes the code. RUSTAS SISTANT first invokes the Rust compiler on the input code and collects the error message. It then feeds the code and the error message, along with instructions in a prompt, to the LLM. RUSTASSISTANT is parametric in the choice of LLM; we show the interactions with GPT-4 in this section. Figure 2 shows the output of GPT-4. The output contains the suggested fix in text and a code patch in the form of a changelog; this format is explained in the next section. The suggested fix is to change the return type of get to Arc, and also insert Arc in the hashmap. Arc in Rust is an atomically reference-counted, thread-safe pointer. With this change, the get function can return a copy of the value, an Arc pointer that points to the same heap location as the value in the map (clone creates the copy). RUSTASSISTANT parses this LLM output, applies the sug gested patch, and compiles the program again. This time, the

Rust compiler complains with the error shown in Figure 3. The error is about the mismatch between the declared type of hashmap, mapping String keys to Bar values, and the usage of it as a map from String keys to Arc values—indeed, the previous patch did not fix the declaration of the hashmap. RUSTASSISTANT sends the code and the error to the LLM again. In this instance, GPT-4 responds with the following fix, correctly suggesting to change the type of map.

ChangeLog:1@src/example.rs 
FixDescription: Change the type of values stored in the HashMap 
to Arc. 
OriginalCode@16−16: 
[16] map: RwLock<HashMap<String, Bar>> 
FixedCode@16−16: 
[16] map: RwLock<HashMap<String, std::sync::Arc > 

After applying this patch, the compilation succeeds and RUSTASSISTANT returns. Using Arc is also the accepted Stack Overflow answer for this question [26].

III. RUSTASSISTANT IMPLEMENTATION

Algorithm 1 The RUSTASSISTANT algorithm.

Require: m: LLM, N: Number of completions 
Require: project: Rust project 
1: errs ← check(project) 
2: while errs ̸ = ∅ do 
3: e ← choose any(errs) 
4: g ← { e}5: snap ← project 
6: while g ̸ = ∅ do 
7: e′ ← choose any(g) 
8: p ← instantiate prompt(e′) 
9: n ← invoke llm(m, p, N) 
10: c ← best completion(project, n) 
11: project ← apply patch(project, c) 
12: g ← check(project) − errs 
13: if giveup() then 
14: project ← snap 
15: break 
16: end if 
17: end while 
18: errs ← check(project) 
19: end while 

RUSTASSISTANT is a command-line tool that takes as input the filesystem path to a Rust project, potentially with errors. RUSTASSISTANT parses the project to build an in memory index of the Rust source files. The index allows RUSTASSISTANT to retrieve the contents of the files, edit them, or even revert them to a previous state. RUSTASSISTANT must handle the complexities of fixing errors in real-world scenarios. Source files can be large relative to the LLM prompt sizes that were available to us (maximum of 32K tokens, for GPT-4), and most of the code in a file might not be relevant to a reported error any way. RUSTASSISTANT, therefore, performs localization for each error to identify relevant parts of the source code and presents only those parts to the LLM. This implies that we need a way of parsing the LLM response to know which change needs to be applied where. We tried a naive approach where we asked the LLM to simply give us the entire revised code snippets but this did not work well (Section V). We instead define a simple, but effective, changelog format that only captures the changes that need to be made to the given code snippets. We describe this format in the prompt and instruct the model to follow it. RUSTASSISTANT uses a lightweight parser to understand the changelog in the LLM’s response and can then easily apply the changes to the original source code. This approach significantly increases RUSTASSISTANT’s accuracy, possibly because the LLM output stays focussed on the code changes. The format is also easy to parse and check for validity. Algorithm 1 shows the RUSTASSISTANT core algorithm. The algorithm starts by invoking the compiler on the project to gather the initial list of errors, and starts fixing them one at a time (line 2). a) Inner loop for fixing an input error: The inner loop (lines 6 − 17) iterates with the LLM with the goal of fixing a single input error (e). During this iteration, the source files may change and those changes may themselves induce additional errors. To accommodate this, we introduce an abstraction called an error group as the working unit of the RUSTASSISTANT inner loop. An error group is a set of errors that RUSTASSISTANT is currently trying to fix. An error group is initialized with the input error (line 4) and may grow or shrink within the loop. The loop terminates when either the error group becomes empty, implying that the original error e was fixed, or RUSTASSISTANT gives up on the error group (line 13), in which case the project is restored to its initial state at the beginning of the outer loop. We now explain the body of the inner loop. b) Prompt construction (instantiate prompt): For each error (e′) in the current error group, RUSTASSISTANT constructs a prompt p, shown in Figure 4 (the headings are for illustration purposes only), asking for a fix to the error. The prompt is parameterized over error-specific content, using the ‘{} ’ syntax. The preamble section instantiates the compiler command that was used (cmd). The next section of the prompt contains the text of the error message. This is followed by code snippet(s) that RUSTASSISTANT deems necessary to present to the LLM for fixing the error. These are obtained by first identifying source locations in the error. The Rust compiler, for instance, not just points to the error location, but to related locations as well. In the example error message below, the location after note is a related location:

error[E0369]: binary operation ‘>=’ cannot be applied to ‘ 
Verbosity’ 
−−> src/logger.rs:53:21 
53 | if self.verbosity >= Verbosity::Exhaustive { 
| −−−−−−−−−−− ˆˆˆ −−−−−−−−−−−−− 
note: an implementation of ‘PartialOrd< >’ might be missing 
−−> src/logger.rs:16:1 
16 | pub enum Verbosity { 
| ˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆ must implement ‘PartialOrd< >’ 
help: consider annotating with ‘#[derive(PartialEq, PartialOrd)]’ 

RUSTASSISTANT prompt template preamble

RUSTASSISTANT then extracts a window of ± 50 lines around each location, and adds these snippets to the prompt. (The size of this window is configurable; we settled on ± 50 to balance prompt size against accuracy on a small subset of benchmarks.) RUSTASSISTANT also adds the line number for each line of code as a prefix, which helps the LLM to better identify the code lines in the prompt. In an initial attempt, we tried only extracting code segments in a proper lexical scope (e.g., the entire body of a function where a relevant line appears). This not only increased the complexity of our tooling (because one needs to parse the Rust code and obtain an AST) but we also found that LLMs are robust even to non-lexical scopes. We decided in favor of keeping our tooling simple. The next section of the prompt (instructions) are simple instructions that ask for a fix. For instance, it instructs the model to avoid adding unsafe code, in an effort to keep the tool focused on generating good Rust code. The final section of the prompt contains instructions to the LLM for formatting the output, as a list of one or more change logs. It contains meta-instances of change log to explain the format to LLM. Each changelog begins with an ID numbered starting with 1 and the source file to which it is applied (ChangeLog line in Figure 4). The next part (FixDescription line) asks the LLM to add a free-form description of the fix that it is proposing. This description is not even parsed by RUSTASSISTANT. Its purpose is to enable chain-of-thought reasoning [29] that has been found to help increase the accuracy of the model’s response. Next part is a repetition of the input code that was given to the model (OriginalCode). This part is defensive because it is a repetition of the input; RUSTASSISTANT rejects the changelog if the OriginalCode segment fails to match the actual original code. Finally, the output must have the fixed code (FixedCode) that should replace all the lines of the original code. If this segment is empty, for example, then it implies that the corresponding original code segment should be deleted. There are other defensive checks in the changelog format:

| You related | are given Rust | the below error from running ’{cmd}’ and code snippets. |
| --- | --- | --- |
| | Prompt | context with error information and code snippets |
| {error} --- {code_snippets} | {error_explanation} | |
| | | Instructions for fixing the error |
| Instructions: Not the snippets fix. could or use ]’). each snippets. instructions. | every snippet error, but as Assume be missing code that unsafe or For your containing Each | Fix the error on the above code snippets. might require a fix or be relevant to take into account the code in all above it could help you derive the best possible that the snippets might not be complete and lines above or below. Do not add comments is not necessary to fix the error. Do not unstable features (through ’#![feature(...) answer, return one or more ChangeLog groups, one or more fixes to the above code group must be formatted with the below |
| | Instructions | and examples for formatting the changelog output |
| Format a description list snippets. consecutive (including followed fixed of the snippets Each FixedCode the prefixed the --- ChangeLog:1@ FixDescription: OriginalCode@4-6: [4] [5] [6] FixedCode@4-6: [4] [5] [6] OriginalCode@9-10: [9] [10] FixedCode@9-9: [9] ... ChangeLog:K@ FixDescription: OriginalCode@15-16: [15] [16] FixedCode@15-17: [15] [16] [17] --- Answer: | instructions: one or Each a by lines code (including changes). must listed snippets, line index with original. space>. space> space> space> space> space> |

each of OriginalCode and FixedCode segments must mention the line number range; and this number range repeats again in the code segment. All such checks act as a guard; change logs are rejected when this information fails to match. c) LLM invocation (invoke llm): Once the prompt is instantiated, RUSTASSISTANT invokes the LLM with the prompt (line 9) asking for N completions, essentially, N responses to the same prompt. On receiving these completions, RUSTASSISTANT ranks them and picks the best completion (line 10). To rank the completions, RUSTASSISTANT applies all the changelogs in a completion and counts the number of resulting errors reported by the compiler. The completion that results in the least number of errors is ranked the highest. The best completion is applied to the project (line 11), the current error group is updated (line 12) and RUSTASSISTANT then continues with the inner loop. When the inner loop completes, RUSTASSISTANT updates the set of pending errors

Fig. 4: The RUSTASSISTANT prompt template.

(line 18) because it is possible that fixing one error group caused the errors to change. (As a detail, errors that were previously given up, on line 13, are not tried again; but this is omitted from the algorithm). RUSTASSISTANT uses a few heuristics to ensure termination of the inner and the outer loops. First, it provides a config urable option (default 100) to limit the maximum number of unique errors that an error group can have over its lifetime in the inner loop. If this limit is reached, the inner loop gives up. Second, if the set of errors in an error group does not change across iterations of the inner loop, RUSTASSISTANT considers it as not making progress and gives up on the error group. The outer loop is bounded to run for as many iterations as the initial number of errors obtained on line 1. (For the purpose of checking if two errors are same, which is needed when performing set operations, RUSTASSISTANT represents an error as the concatenation of its error code, error message, and the file name, without any line numbers.)

IV. RUST ERROR DATASET

We build a dataset of Rust compilation errors collected from three different sources. We also compile a collection of linting errors reported by Clippy on these sources.

A. Micro-benchmarks Rust offers a comprehensive catalog of errors, indexed by error codes, that the Rust compiler may emit. The catalog is accompanied by small programs that trigger the specific error codes [27]. To build our micro-benchmarks dataset, we wrote small Rust programs, one per error code, designed specially to trigger that error code. We wrote these programs ourselves, using the snippets in the Rust catalog as a reference. We consider 270 error codes out of a total of 506. We exclude error codes that are no longer relevant in the latest version of the Rust compiler (1.67.1). Additionally, we exclude all errors related to package use, build configuration files, and foreign function interop, as well as error codes on the use of unsafe; as mentioned in Section II, these errors are out-of scope for us. We also create a unit test for each error code. This test is not shown to RUSTASSISTANT; it is written in a separate file. It is only used to check if the fix meets the intended semantics of the program. As an example, following is a snippet from our micro-benchmark for error code E0382 (borrow of moved value), with the corresponding testcase (comments are not present in the benchmark):

pub fn get value() −> u32 
{let calc1 = Calculator { val: 6 } ; 
let mut calc2 = calc1; calc2.val = 5; 
// inc increments val by 1 
::inc(&calc1) 
// above line borrows calc1 after it has been moved (illegal) 
}#[test] 
fn test e0382() 
{let result = get value(); assert eq!(result, 6); 

} We further classified each of the errors codes into one of the six categories: Syntax, Type, Generics, Traits, Ownership, and Lifetime. The primary objective of this benchmark is to determine if RUSTASSISTANT is more proficient at fixing certain types of errors compared to others.

B. Stack Overflow (SO) code snippets Stack Overflow (SO) is a popular online community where programmers and developers seek help for coding issues. We manually scrape SO to collect questions about Rust compila tion errors. To limit our effort, we concentrate on memory safety (including ownership and lifetime) and thread-safety issues, two areas in which the Rust type system is stricter than C/C++. To ensure that the questions are relevant and substantial, we apply some filtering criteria. For example, we require each question to have at least one answer, we exclude cases that we deem trivial (e.g., the question is misclassified or contains syntax errors unrelated to the intended category), as well as exclude questions that were tagged as duplicates of a previously posted question. After applying these filtering criteria, we select the first 50 most relevant questions with total 65 compilation errors. 94% of the errors are related to the Rust-specific concepts of lifetime, ownership, and traits. Code snippets in these questions are not always self contained. We manually add code and stubs to scope the compilation issue to only what was asked in the corresponding SO question. This process of completing the program snippet was generally quite straightforward. We manually add test cases also, as we did for the micro-benchmarks. For example, for the code snippet shown in Section I, we wrote the following test:

pub fn get value() −> usize 
{let foo = Foo { map: RwLock::new(HashMap::new()) } ; 
let bar = foo.get("key".to string()); 
bar.val.load(Ordering::SeqCst) 
}#[test] 
fn test so042() 
{// 0 is the default value that is added for a new key 
let result = get value(); assert eq!(result, 0); 

} C. Top-100 crates For a more comprehensive real-world evaluation, we look at the GitHub repositories of the top-100 Rust crates (the most widely-used Rust library packages) from crates.io [30]. We examine the history of these repositories and identify commits that have compilation errors (we clone the commits and build them locally, we also filter out commits where the errors are out-of-scope). We found 182 such commits. The benchmark then is to fix the commits so that they pass the Rust compiler. In our evaluation, we manually audit the fixes to check whether they preserve the intended semantics (see RQ3 in Section V). These contain 204 errors, out of which 61 errors are related to ownership, lifetime, and traits. D. Linting errors To build a dataset of linting errors, we pick top-10 crates, and run rust-clippy on the latest commit in the main branch of their corresponding GitHub repositories. Clippy [28] is one of the most popular open-source static analysis tool for Rust with roughly 10K stars on GitHub. It is designed to help developers write idiomatic, efficient, and bug-free Rust code by providing a set of predefined linting rules. Clippy also provides helpful messages and suggestions to guide developers in making improvements to their code. Fixing Clippy errors tests the ability of RUSTASSISTANT to generalize beyond compilation errors. Our dataset has a total of 346 Clippy errors. Clippy has multiple categories of checks [28]. For our dataset, we only consider Pedantic, Complexity, and Style. The rest of the categories did not raise errors in the top-10 crates. Additionally, there is a category called Nursery, but it consists of lints that are not yet stable, so we exclude it from our consideration. Pedantic refers to stylistic or convention violations, Complexity refers to unnecessarily complex or convoluted code that hamper maintainability, and Style covers various linting rules related to code style and best practices, focusing on conventions such as naming, spacing, formatting, and other stylistic aspects of the code.

V. EVALUATION

We evaluate RUSTASSISTANT to answer the following research questions: 1) RQ1: To what extent is RUSTASSISTANT successful in fixing Rust compilation errors? 2) RQ2: How effective are different prompting strategies and algorithmic variations? 3) RQ3: How accurate are the fixes generated by RUSTAS SISTANT for real-world repositories? 4) RQ4: Can RUSTASSISTANT generalize to fix errors re ported by a Rust static analyzer? LLM Configuration: We adopted a deterministic ap proach by using top_p=1, meaning that the most likely token is selected at each generation step. To maintain the focus and consistency of the outputs, we opt for a low temperature of 0.2. While the maximum length of the generated output is set to the default value of 800 tokens, in practice, our changelog snippets are concise and significantly smaller in length. We evaluate both GPT-3.5-turbo [11] (which we call as GPT-3.5) and GPT-4 [12]; a comparison between them helps understand the effect of model scaling on RUSTASSISTANT’s accuracy. For both LLMs, we also vary the number of LLM completions (#N) from 1 to 5 to provide insights into the optimal balance between computation time and quality of the fixes. A. RQ1: To what extent is RUSTASSISTANT successful in fixing Rust compilation errors? For micro-benchmarks and SO, we say that a benchmark is fixed by RUSTASSISTANT if the result code compiles and passes its unit test. A generated fix can fail for three reasons: (1) Format Errors, where the generated changelog is not correctly formatted, or the format is correct but the original code or lines do not match, leading to the rejection of the changelog; (2) Build Errors, the fix when applied still results in compilation errors; (3) Failed Tests, there are no formatting or compilation errors, but the corresponding unit test fails. For the top-100 crates benchmark, we report the

# Failures Model N #Fixed Fmt Build Test

Micro-benchmarks 
(cargo fix: 25 / 270) 
GPT-3.5 
1 143 59 56 12 
5 199 44 10 17 

GPT-4 1 249 ✗ 8 13 5 252 ✗ 4 14

Stack Overflow (cargo fix: 1/50)

GPT-3.5 1 12 18 18 2 5 25 21 2 2

GPT-4 1 37 1 7 5 5 36 3 4 7

TABLE I: Evaluation on micro-benchmark and SO datasets (N is the number of completions, Fixed rate is out of 270 for micro-benchmark and 50 for Stack Overflow).

number of commits that successfully compile after running our tool as well as the number of compilation errors fixed across all the commits. As an estimate for the cost of running RUSTASSISTANT, we also report per commit average of (a) number of LLM queries, (b) number of input and output tokens per prompt, and (c) running time. As a point of comparison, for each dataset, we report the number of benchmarks that can be fixed by cargo fix -broken-code, a Rust command that tries to fix compilation errors by applying any suggestions from the Rust compiler [31]. This tool is an open source effort maintained by the Rust community and serves as a pattern-based baseline in our evaluation, i.e., fixes that can be implemented as a pattern derived from a compilation error. 1) Micro-benchmarks: The top half of Table I shows the performance of RUSTASSISTANT on micro-benchmarks. RUS TASSISTANT achieves a peak accuracy of 93%. In comparison, cargo fix is only able to fix less than 10% of the errors. GPT-4’s performance is significantly better than GPT-3.5, so model scaling helps. Increasing the number of completions helps, but only minimally for GPT-4, potentially because its fix rate is already very high with N = 1. We also notice that GPT-3.5 often fails to follow our formatting requirement in its output (59 failures with N = 1) or fails to satisfy the compiler (56 failures with N = 1).

pub fn get value() → f64 {let mut val: f64 = 7.0; val <<= 2.0; val

}

Interestingly, sometimes RUSTASSIS TANT produces a fix that fails the cor responding unit test (e.g., with GPT-4, there are 13 test failures with N = 1). Consider the code alongside. It fails to build because it uses the bitwise operator <<= on a floating point value (error code E0368). GPT-4 proposes a fix to change the operator to multiplication, but it keeps the unit as 2.0, instead of changing it to 4.0. Expectedly, this fix fails the unit test that we wrote for this benchmark. 2) Stack Overflow (SO) benchmarks: The bottom half of Table I shows the results on the SO benchmarks. Overall trends, with respect to the two models and the number of completions, are similar to microbenchmarks. However, the fix

Avg Prompts / Model #N #Commits #Errors Commit

GPT-3.5 1 55 / 182 414 / 925 11 5 65 / 182 509 / 925 12

GPT-4 1 99 / 182 796 / 925 10 5 134 / 182 846 /925 10

TABLE II: Evaluation on the top-100 Rust crates (cargo fix fixes 1/182).

percentages are consistently lower. RUSTASSISTANT is able to achieve a peak fix percentage of 74%. cargo fix shows a more drastic drop in performance, it is able to fix only 1/50. As the example from Section II shows, fixes can require the introduction of new concepts and types (such as reference counting via Arc) that are hard to automate in a pattern-based manner from the compilation error message. Across the micro-benchmarks and SO benchmarks, we manually investigate the reasons for failure. In some cases, the model suggests a correct partial fix but then does not follow up with the additional fixes required. In other cases, it gets stuck in a loop where it proposes a fix and undoes it in the next iteration, causing RUSTASSISTANT to give up. In a few cases, the model tries to import a package that it needs, but RUSTASSISTANT is not prepared to edit the .toml project file for actually doing the import. It is possible that further refinement of the LLM prompt can fix such issues; we leave it for future work. For the successful benchmarks, with GPT-4, RUSTASSIS TANT required up to 6 iterations of the inner-loop (Algo rithm 1) to come up with a fix. In the case of SO benchmarks, this number goes up to 15. 3) Top-100 crates benchmark: Table II presents results on the top-100 crates benchmark. RUSTASSISTANT is able to achieve an impressive peak accuracy of 91.46% in terms of fixing errors, matching what is also observed in the micro benchmarks. When we consider the ability to fix all errors in a commit, the fix rate is lower, but still impressive at 73.63%, i.e., roughly three-fourths of the commits could have been automatically fixed by RUSTASSISTANT. As Table II shows, RUSTASSISTANT requires on-average 10 round-trip interactions with GPT-4 to fix an entire commit. For the configuration with 5 completions, we further computed the token costs. RUSTASSISTANT used, on average, 2751 input tokens per prompt and 679 output tokens per prompt. With current OpenAI pricing, this amounts to only USD 1.2 to fix all errors in a commit. 4 The price per commit with GPT-3.5 is much lower (USD 0.07) at the expense of lower fix quality. In terms of running times, RUSTASSISTANT spends ma jority of the time either building the code or querying the LLM. The latter is the dominant cost, especially because our OpenAI endpoints were throttled, causing a majority of our requests to timeout. For fair accounting, and because RUSTASSISTANT runs sequentially, we remove requests that timed out from consideration. Then RUSTASSISTANT spends

4See https://openai.com/pricing; prices can vary with time.

22 seconds on average per commit on building the code, and 
249.9 seconds waiting on GPT-4. It should be possible to 
improve this running time by parallelizing RUSTASSISTANT 
(across different errors) but we leave this for future work. 
B. Qualitative analysis of fixes generated by RUSTASSISTANT 
We further analyzed the fixes generated by RUSTASSIS 
TANT to investigate its ability to fix non-trivial errors. We 
concentrate on compilation errors related to ownership, life 
time, and traits, arguably the concepts that Rust programmers 
struggle with most. We identify 23 Rust error codes that are 
related, and refer to this set as S . 5 
Among micro-benchmarks, RUSTASSISTANT is able to fix 
90/99 errors from S . In the SO dataset, there are 43/50 
programs that have at least one compilation error from S ; 
RUSTASSISTANT is able to fix 31 of them. Finally, in the 
top-100 crates benchmark, 60/182 commits have at least one 
compilation error from S , out of which RUSTASSISTANT 
fixes 58 in a runtime behavior preserving way (Section V-D 
describes this criteria more precisely). 
We now demonstrate, using examples, that the fixes do 
not follow from the compiler error message and that they 
require understanding the code that needs fixing. Consider the 
following error from parking lot, one of the crates in our top 
100 dataset: 
error[E0713]: borrow may still be in use when destructor runs 
−−> src/mutex.rs:318:23 
|286 | impl<’a, T: ?Sized + ’a> MutexGuard<’a, T> { 
| −− lifetime ‘’a‘ defined here 
... 
317 | / MutexGuard 
{318 | | borrow: f(orig.borrow), 
| | ˆˆˆˆˆˆˆˆˆˆˆ 
319 | | raw: orig.raw, 
320 | | marker: orig.marker, 
321 | | } 
| | − returning this value requires that ‘*orig.borrow‘ 
is borrowed for ‘’a‘ 
322 | } 

Following is some context relevant to the error; the error above is inside the map function.

pub struct MutexGuard<’a, T: ?Sized + ’a> { ... borrow: &’a mut 
T, } 
pub fn map (orig: Self, f: F) −> MutexGuard<’a, U 
> where F: FnOnce(&mut T) −> &mut U { ... } 

The error occurs because the mutable borrow of orig.borrow at line 318 (indicated in the error message) conflicts with the destructor of orig invoked at the end of map. Since map takes the ownership of the orig argument, the Rust compiler adds this destructor call. RUSTASSISTANT suggests a fix that wraps orig in std::mem::ManuallyDrop inside map to inhibit compiler from calling its destructor, and adjusts the uses of orig to account for it (the actual fix in the repository uses std::mem::forget which achieves the same effect).

5E0106, E0311, E0515, E0621, E0700, E0726, E0382, E0594, E0499, E0502, E0505, E0507, E0521, E0596, E0597, E0716, E0119, E0223, E0271, E0277, E0405, E0445, E0782

| GPT-3.5 | 1 18 182 298 925 / / ✓ P0 5 16 182 382 925 / / |
| --- | --- |
| GPT-3.5 | 1 18 182 46 925 / / ✗ P4 5 59 182 129 925 / / |

Model Prompt G #N #Commits #Errors

This fix is non-trivial. The official documentation of this error code (E0713) suggests taking the function argument by reference. However, RUSTASSISTANT suggests an alternate fix that is closer to the developer intent. We also observe that RUSTASSISTANT is able to suggest fixes that are code-dependent, i.e., different fixes for the same compilation error code. For example, one of the SO benchmarks has the following error (the for loop is the relevant code):

TABLE III: Ablations on the top-100 Rust packages.

for (i, m) in self.margins.iter mut().enumerate() 
{m.y += 1.; 
if m.y > 640. { self.margins.remove(i); } 
}error[E0499]: cannot borrow ‘self.margins‘ as mutable more than 
once at a time 
−−> src/example.rs:29:17 
|26 | for (i, m) in self.margins.iter mut().enumerate() { 
| −−−−−−−−−−−−−−−−−−−−−−−−−−−−−−−− 
| | 
| first mutable borrow occurs here 
| first borrow later used here 
... 
29 | self.margins.remove(i); 
| ˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆˆ second mutable borrow occurs here 

The error complains about two mutable borrows of self. margins, a std::Vec. RUSTASSISTANT fixes the error by con verting the for loop into a while loop that uses an index variable for iteration. With this fix, there is only one mutable borrow of self.margins.

let mut i = 0; 
while i < self.margins.len() 
{self.margins[i].y += 1.; 
if self.margins[i].y > 640. { self.margins.remove(i); 
}else { i += 1; } 

RUSTASSISTANT fixes it by changing the return type of some f to Vec and updating the new string function to return a String instead of a reference. This example illus trates the diversity of potential fixes for the same error codes. C. RQ2: How effective are different prompting strategies and algorithmic variations? We perform an ablation study by permuting between differ ent prompting and algorithmic variations, in order to identify the most effective features of RUSTASSISTANT. We consider five prompt variants, which differ in the way RUSTASSISTANT asks LLMs to output the fixes, i.e. the output formatting instructions. 1) P0 (Basic): This variant serves as the baseline. It does not have the changelog section; it instead asks for the complete revised snippe

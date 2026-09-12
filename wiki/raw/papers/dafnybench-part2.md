---
source_url: https://arxiv.org/abs/2406.08467
ingested: 2026-09-12
sha256: d6ff364900c4eacf188d874d8554575b9f4a2810aaeb78445c846f20a155cdd2
---
# DafnyBench — task design and results (excerpt)

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

We tried to keep prompts and hyperparameters mostly the same across models in order to reduce the difference between model performances that is caused by hyperparameters. However, the prompts are not fully identical. For example, when we ask LLM to simply return the hints-filled program without any explanation, Claude 3 tends to add explanations that interfere with Dafny compilation. Thus, we had to adjust some prompts slightly to fit each model’s peculiarities.

For hyperparameters, we set`max_tokens`$=4096$ , which corresponds to the lowest max output token limit among all the evaluated models, and we set`temperature`$=0.3$ . We gave each model up to $n=10$ attempts at a given file. If it succeeded on an attempt before the $n^{\rm th}$ , it would be early stopped. If the model failed on any of the intermediate attempts, it received the Dafny error message and was asked to filled in the hints again with the error message taken into consideration. If it failed on all $n$ attempts, it was considered to fail on that specific test program.

### 4.2 Basic Results

We tested GPT-4o, GPT-4 Turbo [23], GPT-3.5 Turbo [24], Claude 3 Opus [2], and CodeLlama-7b-Instruct-hf [25] on the $782$ -program benchmark. Table 3 shows that Claude 3 Opus performed best, achieving a success rate $\sim 68\%$ .

### 4.3 Difficulty Utilizing Dafny Error Messages

Figure 3 shows how the cumulative success rate improved with more attempts $n$ . We see that the best models succeeded on the first try about 54%, with rapidly diminishing returns after that, approaching a plateau about 65% for $n\sim 5$ . This suggests that the LLMs are not great at taking Dafny error messages into consideration, or struggle to cope with the underlying task.

| Model | % Success |
| --- | --- |
| No LLM | $26.9$ |
| GPT-3.5 Turbo | $44.0\pm 1.8$ |
| GPT-4 Turbo | $59.8\pm 1.8$ |
| GPT-4o | $59.3\pm 1.8$ |
| Claude 3 Opus | 67.8 $\pm 1.7$ |
| CodeLlama-7b-Instruct-hf | $28.0\pm 1.6$ |

Table 3: Models’ success rates at writing formally verifiable hints for DafnyBench, with $n=10$ attempts given. Dafny succeeds in auto-verifying some programs even without hints, corresponding to the “No LLM" $26.9\%$ success rate baseline.

Figure 3: Success rate vs. number of attempts given.

### 4.4 Difficulty Grows with Program Size

Figure 4a show that the success rate drops with program size. An obvious explanation could be that there is more to verify and more hints needed. Also, as a program gets longer, there may be more dependencies among variables, functions, methods, and classes, increasing the overall verification difficulty level.

### 4.5 Difficulty Grows with Hint Quantity

Figure 4b shows that the success rate drops with the hint quantity, defined as the number of characters in the lines of compiler hints. In other words, the success rate drops with the amount of work that the LLM needs to do (the amount of text that it needs to insert in the right places).

Figure 4: Mean success rate of each bin vs. program length (a), and mean success rate of each bin vs. hint quantity (b). The vertical lines indicate the bin boundaries used, where the bins have an almost uniform distribution of the programs. Note that the bins are different for the two metrics. For better visual clarity, the scales are adjusted for both plots and their $x$ -axes do not start at $0$ character.

(a)

(b)

## 5 Discussion and Conclusions

We have assembled the largest machine-learning benchmark to date for formal software verification and made it publicly available on GitHub at https://github.com/sun-wendy/DafnyBench. We also tested five large language models on this benchmark, including one open source model.

We found that Claude 3 Opus achieved $\sim 68\%$ accuracy on our benchmark, with even better success on programs that were shorter or involved less hint text than the benchmark average. GPT-4 Turbo came second with $\sim 60\%$ accuracy. Meanwhile, CodeLlama-7b-Instruct-hf only achieved a marginal improvement in accuracy compared to our "No LLM" baseline. While in certain cases it succeeds in copying and lightly modifying programs that already verify without compiler hints, it fails to add compiler hints to programs that don’t verify without them.

### 5.1 Opportunities for Larger Benchmarks

It will be valuable to further expand formal verification benchmarks, which still remain more than two orders of magnitude smaller than corresponding benchmarks for mathematical theorem proving. One convenient way to expand the number of available problems may involve incorporating Dafny programs from GitHub that have dependencies spread across multiple files (while DafnyBench encompasses increasingly complex multi-step programs, its programs each fit in a single file, avoiding the intricacies associated with distributed files or the integration of external libraries).

Perhaps models that perform especially well on this initial benchmark can later be used to expand it by translating existing Python benchmark problems into Dafny, Rust [26] or other popular formal verification languages.

A subset of the programs we scraped from GitHub do not have appropriate docstrings. By building a benchmark with better code documentation, models may be able to leverage helpful contextual information to better constructing verification hints.

### 5.2 Benchmark Evaluation Limitations

Data contamination emerges as a potentially significant limitation for evaluating LLMs on this benchmark. Scraping data from platforms such as GitHub introduces risks of leveraging previous models’ training data into the benchmark evaluation, potentially artificially inflating the abilities of certain models.

Another limitation emerges in that this benchmark does not assess a model’s competence in translating natural language into concise formal specifications. Arguably, this conversion is a demanding and crucial skill we seek from language models: the capacity to validate, beyond merely verifying code. The pivotal question is whether a model can assist in identifying the essential properties an algorithm must fulfill. Currently, evaluating this ability presents significant challenges. The Clover paper stands as a prominent example in this area, highlighting the complexity of translating natural language descriptions into formal specifications that can be effectively used for validation. This provides an exciting frontier for future work, which we begin to brainstorm in Appendix C.

### 5.3 Opportunities for Improved LLM Results

It will be interesting to test this benchmark on additional LLMs, both existing ones such as Gemini [3] and Grok [27] and upcoming ones. Furthermore, we evaluated the models with a fixed temperature setting and a max output token limit of 4096, and we used prompts that were manually but not very systematically tuned for effectiveness (see Appendix B) — all of these choices probably leave room for improvement.

We do not yet provide an official training dataset or models custom-trained to do well on the DafnyBench evaluation set. However, we do provide the full json file produced by the GitHub scrape, and we separately provide the names of the files we use for the evaluation benchmark. Hence it is possible for researchers to use files from the Github scrape that are not used in the benchmark as training data, though we cannot at this time provide strong guarantees on similarity between such training problems and the benchmark problems. Pre-training on this type of data may boost large language model performance on DafnyBench.

We also see great opportunity for LLM-related innovation on the algorithmic side: out-of-the-box LLMs provide a floor but not a ceiling for possible performance on this benchmark. For example, fine-tuning or search-based inference-time algorithms might boost models’ performances on this benchmark [28].

### 5.4 The Promise of Better LLM-Powered Verifiers

LLMs also have potential to improve formal verification in more profound ways than mentioned above, when used in combination with other AI tools. For example, they can help automate the identification of sub-goals and hints, exponentially reducing the search space for automated theorem provers and SAT solvers. A good software developer is likely able to specify the high level assurance properties of a piece of code. However, in trying to prove that the given code satisfies these high level properties, numerous, sub-goals must be identified, proven, and leveraged correctly in the broader context. Software developers often lack familiarity with the complexities of proof sub-goals and hints. LLMs offer a way to bridge this gap between software developers and formal verification.

Achieving this requires benchmarks suitable for improving the performance and generality of LLMs with respect to software verification. Bigger, more general benchmarks can be used to train LLMs to specify sub-goals and hints in formats most useful to the presently available provers and solvers. Benchmarks covering broad ground, from cryptography, lambda calculus, embedded systems, and avionics, in a variety of widely used programming languages suitable for verification, will help create LLMs that can take real-world software, automatically process and serve it to verification tools, and inform the developer in near real time about the correctness of the code. The problem is analogous to that solved by existing automated theorem provers and model checkers in the domain of mathematics. They address the problem, when given a set of constraint formulas or background theorems, whether a candidate formula is satisfiable or derivable. Many clever algorithms have increased the degree of automation available to mathematical theorem proving over time. LLMs should be able to help similarly improve automation for software verification. For a survey on the application of deep learning to automated theorem proving, see [29].

In order to formally specify a correctness property for a programming language, some formalization of the lower level language’s semantics must be represented in a higher level specification language. A lower level language with well-defined semantics to begin with makes this easier. For languages lacking well-defined semantics, such as C, JavaScript, and Python, a well-defined subset may suffice [30]. Programming languages fall on a spectrum of well-defined semantics, with higher level languages like Haskell on one end, and C on the other. Rust falls in a particularly nice intermediate place, with a strongly typed, functional semantics and macros for achieving side effects. An ecosystem of formal verification tools has begun to emerge for Rust, due to its nice semantics and popularity as a practical programming language [31]. A benchmark leveraging this ecosystem for LLMs would likely compound on this progress dramatically. Multiple formal verification tools compile to Rust or extract correct Rust code. For example, Dafny can compile to Rust, and other tools for extracting Rust from Coq exist [32, 33]. In this case, Rust would be considered the low level language, and Dafny and Coq would serve as candidate specification languages. A workflow might be possible such that a developer working in Rust could have a LLM assistant that identifies correctness properties for the code, either automatically or provided at a high level by the developer, and produces appropriate artifacts for verifying correctness via multiple tools for improved assurance.

### 5.5 The Promise of Auto-Verifying Program Synthesis

Above we discussed the challenge of verifying existing pre-programs. Anther promising approach is use program-synthesis techniques that produce not only programs but also proofs of their correctness, all at the same time. This makes intuitive sense, since when a human programmers writes code, they typically have an informal proof in their head for why this code is correct.

In other words, in addition to bridging the gap from low level implementation to high level specification in the upward direction, LLMs can offer assistance in generating provably correct low level code from high level specifications via program synthesis. Current approaches to program synthesis enable engineers to encode a desired specification in a high level language, and then through a (hopefully) verified correct compiler generate correct low level code in a language like VHDL [34] or Verilog [35] for hardware synthesis. Indeed, the compilation of Dafny code to Rust or Python is an example of program synthesis. Program synthesis is limited by the need for a special purpose language or compiler to be constructed and verified correct in its own right. For example, ReWire is a domain specific language defined as a subset of Haskell [36]. Using ReWire, engineers can specify hardware properties and then through the Haskell compiler, synthesize VHDL that is guaranteed to satisfy the specifications. ReWire itself was manually verified correct using the Coq Interactive Theorem Prover. In order to add a new high to low path, a new language or compiler must be defined and verified. If an engineer needs to synthesize correct Verilog rather than VHDL, they must first learn Caisson [37].

LLMs offer a way to generalize this approach. Starting with a high level language, an engineer might be able to specify a system and then leverage a LLM to generate low level code with the corresponding loop invariants, weakest pre-conditions, strongest post-conditions, etc, included. In the limit, an engineer might be using a natural language to describe the system and its desired assurance properties, with the LLM performing translation, annotation, and even suggesting additional correctness properties. Early results indicate that an LLM that is able to converse with a human when producing a program can reduce the error rate against a simple programming benchmark by half [20]. If instead of receiving feedback from a human, the LLM were to interact with a suite of formal verification tools, we expect further improvements. We could avoid hallucination problems by relying on the LLM to generate the code and formal specification, but relying on an established verification tool to perform the model checking or proof verification itself. The LLM’s translation process need not itself be verified, because it can try multiple times to produce a verifiable output. The LLM must be capable of generating code that is appropriately annotated for theorem proving, which is exactly the skill assessed by test benches like that described here. The more theorem proving tools and programming languages that LLMs are trained and assessed on, the more auto-verifying program synthesis options become available. To return to the previous example, a LLM proficient at ReWire, Caisson, and myriad other software verification techniques, might be given a ReWire specification as input and told to produce correct Verilog as output. The ReWire specification contains the high level correctness properties that must be satisfied. The task is to synthesize Verilog code that satisfies those same correctness properties specified in Caisson. A strong ability to reason about code properties and to express them in multiple languages is exactly what is called for here, and what diverse LLM test benches help to enable.

In summary, there are good reasons for optimism that automated formal verification will soon be greatly improved.

Acknowledgements: The authors wish to thank Clark Barrett, Rustan Leino, Daniel Windham, David Brandfonbrener, William Byrd, Josh Engels, and Anastasiya Kravchuk for helpful discussions.

## References

- [1] Sébastien Bubeck, Varun Chandrasekaran, Ronen Eldan, Johannes Gehrke, Eric Horvitz, Ece Kamar, Peter Lee, Yin Tat Lee, Yuanzhi Li, Scott Lundberg, et al. Sparks of artificial general intelligence: Early experiments with gpt-4. arXiv preprint arXiv:2303.12712, 2023.
- [2] Anthropic. The claude 3 model family: Opus, sonnet, haiku. Technical report, Anthropic, 2024.
- [3] Gemini Team, Rohan Anil, Sebastian Borgeaud, Yonghui Wu, Jean-Baptiste Alayrac, Jiahui Yu, Radu Soricut, Johan Schalkwyk, Andrew M Dai, Anja Hauth, et al. Gemini: a family of highly capable multimodal models. arXiv preprint arXiv:2312.11805, 2023.

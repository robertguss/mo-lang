---
source_url: https://arxiv.org/abs/2509.22908
ingested: 2026-09-12
sha256: 6274838b947972edf96def930a0f122b10eddf810f0f9b42fa60a561ea1072f6
---
# A benchmark for vericoding — sections 4.1–4.2 (excerpt)

We quantify the vericoding success rate for LLMs such as GPT and Claude straight out of the box, without special techniques such as reinforcement learning or fine-tuning. Our experimental pipeline is simple: we present to the LLM a prompt that is annotated to indicate the context, the problem spec, as well as different holes (e.g. sorry’s) that require input from the LLM model. The model responds with blocks generated for each of the holes. The generated blocks are validated by checking for cheating patterns, and inserted into the task file template. The file is then verified with the proof checker. If both validation and verification pass, the LLM is deemed to have successfully completed the task. Otherwise, the error messages are passed to the LLM for correction. We allow only a fixed number of such iterations before deciding that the LLM has failed. This process is described more precisely in Figure 3. The validation tests are specific for each proof language. They depend on corresponding compile options, syntax and programming patterns. We designed the tests by taking into account known proof bypass patterns (e.g. using sorry for Lean), as well as various LLM cheating strategies that we have identified during our experiments.

Prompts and hyperparameters: We have two prompt templates for each language, listed in Appendix 1.3: one for code and proof generation and one for fixing verification errors in previously generated files. We informally explored prompting variations, but did not optimize the prompts fully. The Verus prompt might benefit from examples of common lemmas in vstd. For Dafny/Verus, we gave sample syntax in the prompt. Each LLM had 5 attempts per task, except 10 attempts on the challenging BigNum dataset. In comparison, Harmonic used half a million CPUs to run Lean for its IMO work (Harmonic 2025).

LLM cheating detection: Our block validation script systematically detects potential LLM cheating patterns that could bypass the proof checker, possibly by changing the goals. These include : (1) Using assume(false) or sorry to disable the proof checker. We can instruct the proof checker to reject such proofs. (2) Changing postconditions in the spec to ensures true to make it trivial to prove. We can block the LLM from altering the specs. (3) Implementation leakage from the spec. We use ghost functions in Dafny/Verus to partly mitigate this. There will typically be some level of implementation leakage from the specs–if not the full implementation, then at least the spirit of it. Indeed, we expect LLMs to do so, so the onus is on spec writers to create good specs (see, e.g., the CLEVER benchmark). (4) We anticipated a cunning form of cheating where the LLM begins a comment section in one block and closes the comment section in another, effectively erasing any intermediate task spec through this trick. Thankfully, this did not happen.

Manual inspection: To quantify the validity of the vericoding process, we perform manual inspection of 5 randomly chosen successful vericoding outputs for each language and data source, noting any LLM behavior that could be considered cheating. The reports, detailed in the supplementary material, show language-specific patterns: Dafny exhibited no issues (except for redundant lemmas), with LLMs correctly giving trivial solutions when the specs were weak. Verus showed many weak specs due to spec translation issues, e.g. deviations from the original BigNum specs in Dafny. Lean displayed occasional redundant lemma additions during vericoding, and had some weak specs from the original sources. Across Dafny, Verus and Lean, conditioned on vericoding success, roughly 9% of the specs were too weak and another 15% had poor translations. Note that these problematic specs still make perfectly valid vericoding tasks, just different tasks than originally intended. No further cheating was discovered, other than those which were caught by our validation checks.

### 4.1 Vericoding results

Table 3 shows that LLM vericoding worked best on Dafny (82.2%), followed by Verus (44.2%) and Lean (26.8%). Claude-Opus- 4.1 excelled at Dafny, while GPT-5 led on Verus and Lean. The “model union” numbers denote the fraction solved by at least one of the LLMs.

Verus success rates are probably lower due to several factors: unlike Dafny’s uniform mathematical types, Verus distinguishes between ghost types (for specifications) and Rust native types (for execution), requiring verification of machine-level complexities such as overflow handling. Additionally, LLM translations often fail to systematically map between these type systems, and Verus is a newer, lower-resource language than Dafny.

Lean’s lower success probably stems mostly from LLMs being trained primarily on mathematical theorem proving rather than code verification. The Lean prompt might benefit from examples of how to use new tactics such as grind and canonical. ITPs and ATPs will also require different strategies for exploiting LLMs: A human writing Lean gets constant feedback about the proof state, while our scaffolding only told the LLM what the proof state was 5 times per example.

We have separated FVAPPS into Row A of Table 3 because the specs are weaker and allow for more trivial solutions. We did not apply the unit tests associated to the tasks in these experiments. Here, GPT-5 is again seen to perform best.

Verification alone: We use the original dataset from Loughridge et al. 2025 with 782 tasks and its original prompts to gauge how much the LLMs have improved on verification. Table 3 shows the success rates (sample sizes in parentheses) for different LLMs, revealing rapid progress: The June 2024 state-of-the-art of 68% with Opus-3 has now risen to 89% with Opus-4.1 and 96% for the model union. See Appendix 1.6 for more details.

Hoare triples in Lean: The model union achieved 7.6% success on our novel Numpy-Triple benchmark, which is below the language average of 26.8%. This is likely due to the mvcgen feature being new. We expect the success rate to improve significantly over the next two years when newer LLMs are trained on datasets that use this feature and as SMT-solver-based tactics in Lean become more proficient at tackling the proof obligations.

Spec and vibe coding: In addition to formal specifications, several of our source benchmarks contain informal descriptions of vericoding tasks. One of these is Verina, for which we perform a separate set of experiments including the informal descriptions in the LLM prompt. The aim is to test their effect on vericoding performance. We find that including the ”vibe” information provides no statistically significant performance improvement (indeed, the results seen to be slightly worse on average), so we decided not to extended this experiment to our full benchmark, and plan to study this more extensively in future work.

Improvements from ensemble methods: Results from taking the union of successful attempts from different models can be found in Table 3. This potentially suggests that in the future, vericoding tasks should be decomposed into smaller parallel tasks that can be tackled by different models. To make this like a mixture of experts (MoE) strategy in advanced language models (Jiang et al. 2024), we would need to implement a router model (perhaps just a pre-deep-learning bag-of-words model) that decides which LLM will attempt a problem.

### 4.2 Parameters influencing vericoding difficulty

We investigate three different parameters that one may expect to impact vericoding complexity: spec length (the number of characters in the spec source code), solution length (the number of characters in the LLM’s solution), and spec ratio (code length divided by spec length). Note that an LLM’s solution may or may not be code that satisfies the spec or even parses in its target language, since not all solutions are correct.

Spec length depends on the number of preconditions, postconditions, and helper definitions. More preconditions ease verification by providing assumptions, while more postconditions increase difficulty by requiring additional proofs. Helper definitions create interdependent proof obligations that are harder to solve.

We find that LLMs easily generate implementations (consistent with vibe coding success), but struggle more with proofs — adding invariants/assertions for ATPs or choosing tactics for ITPs. Our results, shown in Figure 4, exclude all cases where the LLM fails to propose an implementation.

Figure 4: Vericoding success as a function of task spec length (top row), generated code length (middle row) and spec ratio (bottom row) which is the code length divided by the spec length. sorted by size

Figure 4 shows the relation between vericoding success and the various parameters. Spec length is the weakest predictor of vericoding complexity, presumably because simple problems can have lengthy solutions (e.g., Fermat’s Last Theorem). Additionally, longer specs often contain helper functions that do not require vericoding, unlike additional postconditions which increase difficulty. Solution length shows a clearer trend: longer implementations are more likely incorrect, similar to human coding where more code increases error probability. With finite iterations per task, shorter implementations allow better use of each iteration. Spec ratio trends fall between these patterns, following solution length trends more closely.

Table 3: Vericoding results

| | NumPyS | NumPy3 | DafnyBench | HumanEval | Verina | BigNum | VerifCogen | APPStest | Totals $\downarrow$ |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Dafny | 58 tasks | 430 tasks | 443 tasks | 162 tasks | 157 tasks | 62 tasks | 172 tasks | 677 tasks | 2161 tasks |
| claude-opus-4.1 | 60.3% | 64.9% | 67.0% | 71.6% | 73.2% | 14.5% | 90.7% | 66.6% | 67.5% |
| gpt-5-mini | 67.2% | 56.3% | 64.1% | 71.6% | 73.9% | 25.8% | 85.5% | 71.6% | 66.9% |
| gpt-5 | 65.5% | 56.3% | 63.9% | 72.2% | 76.4% | 19.4% | 86.6% | 69.1% | 66.1% |
| claude-sonnet-4 | 65.5% | 69.3% | 61.2% | 72.8% | 72.0% | 8.1% | 84.3% | 60.3% | 64.6% |
| gemini-2.5-pro | 63.8% | 60.2% | 58.2% | 69.1% | 66.9% | 6.5% | 79.7% | 40.8% | 55.0% |
| grok-code | 48.3% | 47.0% | 52.8% | 57.4% | 63.1% | 3.2% | 75.6% | 52.9% | 53.0% |
| glm-4.5 | 50.0% | 41.4% | 20.3% | 50.0% | 51.0% | 4.8% | 67.4% | 48.7% | 42.0% |
| gemini-2.5-flash | 48.3% | 34.4% | 36.3% | 42.6% | 45.9% | 0.0% | 57.0% | 36.9% | 38.2% |
| deepseek-chat-v3.1 | 39.7% | 43.0% | 30.2% | 45.1% | 46.5% | 3.2% | 50.0% | 30.6% | 36.2% |
| model union | 75.9% | 77.9% | 71.9% | 93.2% | 87.3% | 48.4% | 95.9% | 83.0% | 82.2% |
| Verus | 58 tasks | 581 tasks | 443 tasks | 161 tasks | 156 tasks | 62 tasks | 172 tasks | 536 tasks | 2166 tasks |
| gpt-5 | 18.9% | 47.5% | 18.3% | 15.5% | 30.7% | 3.2% | 49.4% | 26.5% | 30.9% |
| claude-opus-4.1 | 18.9% | 29.7% | 19.2% | 9.9% | 26.2% | 1.6% | 63.4% | 18.1% | 24.6% |
| gemini-2.5-pro | 34.5% | 31.5% | 19.7% | 9.3% | 25.6% | 1.6% | 52.9% | 16.0% | 24.1% |
| claude-sonnet-4 | 20.7% | 22.0% | 19.0% | 5.6% | 27.5% | 1.6% | 48.2% | 13.4% | 19.9% |
| glm-4.5 | 8.6% | 23.0% | 11.3% | 5.6% | 16.0% | 0.0% | 27.3% | 16.8% | 16.6% |
| gpt-5-mini | 3.4% | 21.3% | 9.5% | 6.2% | 24.3% | 0.0% | 22.6% | 19.0% | 16.5% |
| grok-code | 10.3% | 22.9% | 10.6% | 3.1% | 17.9% | 1.6% | 25.0% | 13.8% | 15.5% |
| gemini-2.5-flash | 10.3% | 16.3% | 7.7% | 1.2% | 12.8% | 0.0% | 16.2% | 5.2% | 9.8% |
| deepseek-chat-v3.1 | 3.4% | 6.9% | 5.0% | 1.8% | 10.2% | 0.0% | 8.7% | 6.5% | 6.1% |
| model union | 37.9% | 55.8% | 34.8% | 26.1% | 46.8% | 4.8% | 77.9% | 38.8% | 44.3% |
| Lean | 59 tasks | 603 tasks | 440 tasks | 161 tasks1 | 189 tasks | 62 tasks | 172 tasks | 675 tasks | 2361 tasks |
| gpt-5 | 45.8% | 5.1% | 32.0% | 3.7% | 14.3% | 12.9% | 34.9% | 18.4% | 17.9% |
| claude-sonnet-4 | 30.5% | 0.7% | 11.4% | 1.2% | 13.8% | 1.6% | 10.5% | 24.0% | 11.9% |
| gemini-2.5-pro | 23.7% | 0.3% | 14.1% | 3.1% | 12.2% | 1.6% | 9.3% | 19.9% | 10.9% |
| claude-opus-4.1 | 20.3% | 1.0% | 11.8% | 3.1% | 15.3% | 1.6% | 10.5% | 19.3% | 10.7% |
| gpt-5-mini | 15.3% | 0.3% | 15.0% | 0.0% | 1.6% | 1.6% | 4.1% | 6.8% | 5.7% |
| grok-code | 10.2% | 0.0% | 9.1% | 0.0% | 1.1% | 0.0% | 4.7% | 6.2% | 4.2% |
| glm-4.5 | 6.8% | 0.2% | 2.5% | 0.0% | 0.5% | 0.0% | 1.7% | 2.7% | 1.6% |
| gemini-2.5-flash | 0.0% | 0.2% | 0.5% | 0.0% | 0.0% | 0.0% | 0.6% | 1.9% | 0.7% |
| deepseek-chat-v3.1 | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.0% | 0.1% | 0.0% |
| model union | 52.5% | 7.6% | 34.1% | 8.1% | 25.4% | 12.9% | 44.2% | 38.5% | 26.8% |


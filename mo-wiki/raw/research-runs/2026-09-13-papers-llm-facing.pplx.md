---
tool: Perplexity Computer
prompt: prompts-research-agenda-2026-09 / R1 (papers, LLM-facing)
run: 2026-09-13
run_by: Perplexity Computer, at Robert's request
sha256: 676aa1a542d48452fb10b5046bb3698153d37780b33acfaadf783e447b01a2df
---
# R1: Recent LLM-facing research, 2024–2026 (agents + verification; language design for LLMs)

Run date: 2026-09-13. Researcher: R1 subagent. Every number below was read this session from the linked page (arXiv abstract page, venue page, DOI landing page, or the author's own post). Where a page did not state a number, this dossier says "n.a." rather than guessing. Nothing here comes from memory.

## Framing: what the 2025–2026 literature actually settles

Three things changed in this literature since the papers already in the Mo wiki (Marmaragan, NeuroInv, RustAssistant, SynCode, CodeAct, the MoonBit paper).

First, verified code generation now has ranked, cross-language numbers instead of anecdotes. The same specification, discharged by the same off-the-shelf models, gets 82% in Dafny, 44% in Verus/Rust, and 27% in Lean ([vericoding benchmark, arXiv:2509.22908](https://arxiv.org/abs/2509.22908)), and an independently built, contract-aligned benchmark reproduces the ordering at 40.3% Dafny / 24.7% Verus / 7.8% Lean ([AlgoVeri, arXiv:2602.09464](https://arxiv.org/abs/2602.09464)). The verifier's automation level, not the model, dominates the outcome. That is the single most Mo-relevant empirical fact of the last year: Mo's tier-2 contracts sit near the Dafny end of that spectrum, and Mo's separate `mo prove` tool sits near the Lean end.

Second, the bottleneck moved from proofs to specifications. Benchmarks that separate code, spec, and proof show models writing correct code far more often than sound specs, and sound specs far more often than proofs: 72.6% code correctness vs 52.3% spec soundness/completeness vs 4.9% proof success for the best model ([VERINA, arXiv:2505.23135](https://arxiv.org/abs/2505.23135)). Specification failures are not random: generated specs omit input assumptions, accept wrong outputs, or reject valid ones, and an LLM judge misses 26% of those failures ([Verus-SpecGym, arXiv:2605.26457](https://arxiv.org/abs/2605.26457)). Under plain prompting, models satisfy 0% of implicit input contracts while passing 75–82% of functional tests ([ContractEval, arXiv:2510.12047](https://arxiv.org/abs/2510.12047)). Mo's `requires` + mandatory `test rejects` pairing is a direct answer to exactly this failure mode, and it is now supported by measurement rather than taste.

Third, diagnostics are now measurable as an interface for models, not only for humans. Replacing a raw verifier log with a reconstructed, Rust-styled explanation of where the proof was lost raises LLM repair success by 11–21 percentage points on the same tasks ([bpfix, arXiv:2607.02748](https://arxiv.org/abs/2607.02748)), and a PL-community ablation finds "concrete evidence that more detailed error messages improve an agent's ability to fix type errors" ([Type-Error Ablation and AI Coding Agents, arXiv:2606.01522](https://arxiv.org/abs/2606.01522)). The counterweight is that for humans, LLM-rewritten error messages repeatedly fail to improve objective debugging ([Not the Silver Bullet, arXiv:2409.18661](https://arxiv.org/abs/2409.18661); [Beyond the Traceback, arXiv:2608.20896](https://arxiv.org/abs/2608.20896)). Mo's MO-coded `what`/`why` diagnostics have two audiences with different measured responses.

A caution that runs through Cluster B: almost nothing in the literature isolates language design. The strongest available comparisons are token-efficiency evals and multi-language quality studies, and their authors are explicit that confounds (corpus size, library maturity, benchmark structure) dominate. The one production-scale Rust-vs-Python port measured near-parity on SWE-bench Verified with a 15.9x code-size reduction in favor of Python ([arXiv:2604.11518](https://arxiv.org/abs/2604.11518)) — which is evidence against, not for, the "stricter language wins for agents" hypothesis, and should be read next to Mo's own Round 3 control run.

---

## A1. LLMs writing contracts, loop invariants, and proofs

### A benchmark for vericoding: formally verified program synthesis
Sergiu Bursuc, Theodore Ehrenborg, Shaowei Lin, et al. — Dafny 2026 workshop, POPL 2026 series; preprint submitted 26 Sep 2025. [arXiv:2509.22908](https://arxiv.org/abs/2509.22908); venue listing: [Dafny 2026 / POPL 2026](https://popl26.sigplan.org/details/dafny-2026-papers/13/A-benchmark-for-vericoding-formally-verified-program-synthesis).
The benchmark contains 12,504 formal specifications — 3,029 Dafny, 2,334 Verus/Rust, 7,141 Lean — of which 6,174 are new unseen problems, and it defines vericoding as generating verified code from a formal spec rather than from prose ([arXiv:2509.22908](https://arxiv.org/abs/2509.22908)). Headline result, quoted verbatim: "We find vericoding success rates of 27% in Lean, 44% in Verus/Rust and 82% in Dafny using off-the-shelf LLMs" ([arXiv:2509.22908](https://arxiv.org/abs/2509.22908)). The page also records pure-Dafny verification moving from 68% to 96% over the preceding year, and reports that adding natural-language descriptions to the formal specs does not significantly improve performance ([arXiv:2509.22908](https://arxiv.org/abs/2509.22908)).
Mo relevance: the 82/44/27 spread is the empirical case for Mo keeping SMT-automated, Dafny-shaped contracts in tier 2 and pushing Lean-shaped interactive proving out to a separate tool ([[d32-proving-is-a-separate-tool]]). The "prose adds nothing on top of a formal spec" finding argues that Mo's `never` sentences earn their place as human-facing artifacts, not as model hints.

### AlgoVeri: An Aligned Benchmark for Verified Code Generation on Classical Algorithms
Haoyu Zhao, Ziran Yang, Jiawei Li, et al. — preprint, arXiv:2602.09464, submitted 10 Feb 2026. [arXiv:2602.09464](https://arxiv.org/abs/2602.09464).
AlgoVeri holds the specification fixed — identical functional contracts for 77 classical algorithms across Dafny, Verus, and Lean — so the comparison is about the verification system rather than the task ([arXiv:2602.09464](https://arxiv.org/abs/2602.09464)). Verbatim: "While frontier models achieve tractable success in Dafny ($40.3$% for Gemini-3 Flash), where high-level abstractions and SMT automation simplify the workflow, performance collapses under the systems-level memory constraints of Verus ($24.7$%) and the explicit proof construction required by Lean (7.8%)" ([arXiv:2602.09464](https://arxiv.org/abs/2602.09464)). Iterative repair triples pass rates in Dafny for Gemini-3 ([arXiv:2602.09464](https://arxiv.org/abs/2602.09464)).
Mo relevance: the tripling-under-repair number is the cleanest published evidence that Mo's loop economics (compile-fast, re-run, re-check) matter more than one-shot model quality — and it is measured on the automation-rich end of the spectrum, where Mo's tier 2 lives ([[q08-verification-tiers]]).

### VERINA: Benchmarking Verifiable Code Generation
Zhe Ye, Zhengxu Yan, Jingxuan He, et al. — preprint, arXiv:2505.23135, submitted 29 May 2025. [arXiv:2505.23135](https://arxiv.org/abs/2505.23135).
VERINA is 189 manually curated Lean tasks that score code, specification, and proof separately, plus their compositions ([arXiv:2505.23135](https://arxiv.org/abs/2505.23135)). Verbatim: "The best model, OpenAI o3, achieves a 72.6% code correctness rate, 52.3% for specification soundness and completeness, and a mere 4.9% proof success rate (based on one trial per task)" ([arXiv:2505.23135](https://arxiv.org/abs/2505.23135)).
Mo relevance: the ordering code > spec > proof is the quantitative core of the spec-altitude bet ([[d02-spec-altitude]]). It says the artifact Mo asks humans to read is also the artifact models are second-best at producing — so contract review is where human attention buys the most.

### VeriBench: End-to-End Formal Verification Benchmark for AI Code Generation in Lean 4
Brando Miranda, Srivatsava Daruru, Zhanke Zhou, et al. — ICLR 2026 submission (submitted 20 Sept 2025, modified 11 Feb 2026). [OpenReview forum P7NUVF6wo4](https://openreview.net/forum?id=P7NUVF6wo4).
140 tasks at five difficulty levels (56 HumanEval problems, 41 foundational exercises, 10 classical algorithms, 28 security-critical programs adapted from real vulnerabilities, 5 Python standard-library programs), scored on four hierarchical subtasks: Lean 4 compilation, unit-test pass proportion, correctness-theorem synthesis quality, and pass@1 proof success ([OpenReview](https://openreview.net/forum?id=P7NUVF6wo4)). Claude 3.7 Sonnet reaches 35.0% compilation success and 40.6% unit-test passing; LLaMA-70B failed to compile any programs; a trace-based self-debug agent architecture reaches 49.3% compilation success and a Draft-Sketch-Proof agent 28.9% pass@1 ([OpenReview](https://openreview.net/forum?id=P7NUVF6wo4)).
Mo relevance: the jump from 35.0% to 49.3% compilation success purely from a trace-based self-debug loop is a measured argument for Mo's replay traces being a first-class agent input, not just a debugging convenience.

### Local Success Does Not Compose: Benchmarking Large Language Models for Compositional Formal Verification
Xu Xu, Xin Li, Xingwei Qu, et al. — ICLR 2026 (poster, Fri 24 Apr 2026). [ICLR 2026 page](https://iclr.cc/virtual/2026/poster/10006597).
DafnyCOMP targets multi-function programs (2–5 functions) with non-trivial data dependencies: 400 synthesized programs, 300 chain-structured and 100 non-chain DAG instances from 10 topology templates ([ICLR 2026](https://iclr.cc/virtual/2026/poster/10006597)). Frontier LLMs exceed 99% syntactic well-formedness and above 58% end-to-end verification on prior single-function Dafny benchmarks, but achieve near-zero end-to-end verification on DafnyCOMP, attributed to specification fragility, implementation–proof misalignment, and reasoning instability ([ICLR 2026](https://iclr.cc/virtual/2026/poster/10006597)).
Mo relevance: this is the strongest counterweight to per-function optimism. Mo's laws force many small functions with contracts at every boundary; if local success does not compose, Mo needs a composition story (module-level contracts, or verified glue) rather than more per-function checks ([[q08-verification-tiers]], [[d19-negative-space-is-the-contract]]).

### AutoVerus: Automated Proof Generation for Rust Code
Chenyuan Yang, Xuheng Li, Md Rakib Hossain Misu, et al. — OOPSLA 2025; also in Proceedings of the ACM on Programming Languages. [arXiv:2409.13082](https://arxiv.org/abs/2409.13082); [DOI 10.1145/3763174](https://dl.acm.org/doi/10.1145/3763174).
A network of LLM agents mimics three human proof phases — preliminary generation, refinement guided by generic tips, debugging guided by verification errors ([arXiv:2409.13082](https://arxiv.org/abs/2409.13082)). Verbatim: "Our evaluation shows that AutoVerus can automatically generate correct proof for more than 90% of them, with more than half of them tackled in less than 30 seconds or 3 LLM calls" — on a suite of 150 non-trivial proof tasks ([arXiv:2409.13082](https://arxiv.org/abs/2409.13082)). The ACM landing page states the venue (PACMPL) but carries no abstract text or numbers ([DOI 10.1145/3763174](https://dl.acm.org/doi/10.1145/3763174)).
Mo relevance: the "3 LLM calls / 30 seconds" figure sets the latency budget Mo's compile-speed targets are competing with; if a proof round-trip is 30 s, a 50 ms `mo check` is the right order of magnitude for the inner loop ([[d23-compile-speed-first-class]]).

### KVerus: Scalable and Resilient Formal Verification Proof Generation for Rust Code
Yuwei Liu, Xinyi Wan, Yanhao Wang, et al. — preprint, arXiv:2605.03822, submitted 5 May 2026. [arXiv:2605.03822](https://arxiv.org/abs/2605.03822).
Retrieval-augmented, dependency-aware Verus proof generation with semantic lemma indexing and error-driven self-refinement: 80.2% of tasks verified on three single-file benchmarks vs 56.9% for AutoVerus, and 51.0% on three repository-level benchmarks with cross-file dependencies vs 4.5% for a multi-round prompting baseline ([arXiv:2605.03822](https://arxiv.org/abs/2605.03822)). In the Asterinas Rust OS memory-management module it produced upstream-accepted proofs for 23 previously unverified functions, 21.0% of proof code ([arXiv:2605.03822](https://arxiv.org/abs/2605.03822)). It also degrades less than AutoVerus under breaking Verus updates ([arXiv:2605.03822](https://arxiv.org/abs/2605.03822)).
Mo relevance: the 4.5% → 51.0% repository-level gap is about context assembly, not model strength. Mo's `.mo.ids` sidecar and stable declaration IDs are exactly the machinery a dependency-aware retriever needs ([[d29-edit-by-declaration-id]]).

### Reducing the Costs of Proof Synthesis on Rust Systems by Scaling Up a Seed Training Set (VeruSyn)
Nongyu Di, Tianyu Chen, Shan Lu, et al. — preprint, arXiv:2602.04910, submitted 4 Feb 2026, revised 9 May 2026. [arXiv:2602.04910](https://arxiv.org/abs/2602.04910).
Verbatim: "With VeruSyn, we synthesize the largest set of Verus verified programs: 6.9 million Rust programs, each with a formal specification and a proof that it meets that specification" ([arXiv:2602.04910](https://arxiv.org/abs/2602.04910)). A Qwen2.5-Coder-32B-Instruct model fine-tuned on it is claimed to have an appealing cost-proof tradeoff against Claude Sonnet 4.5 and to significantly outperform o4-mini and prior research models; no pass-rate percentages are stated on the abstract page ([arXiv:2602.04910](https://arxiv.org/abs/2602.04910)).
Mo relevance: this is the cold-start recipe applied to a verification language — self-synthesis, tutorial-based synthesis, agent-trajectory synthesis. If Mo generates a corpus, this is the shape of the pipeline and the scale (millions, not thousands) that a 32B model needed ([[d28-nothing-final-until-measured]]).

### Verifying LLM-Generated Code in the Context of Software Verification with Ada/SPARK (Marmaragan)
Marcos Cramer, Lucian McIntyre — preprint, arXiv:2502.07728, submitted 11 Feb 2025. [arXiv:2502.07728](https://arxiv.org/abs/2502.07728).
Marmaragan uses an LLM to generate SPARK annotations for existing programs so they can be formally verified; with GPT-4o it generated correct annotations for 50.7% of benchmark cases on a curated set of SPARK programs (benchmark size not stated on the page) ([arXiv:2502.07728](https://arxiv.org/abs/2502.07728)).
Mo relevance: already in the wiki; retained here as the lineage point for "annotate an existing program" versus the 2026 style of "co-generate program and proof." The 50.7% is the number newer work has to beat.

### WybeCoder: Verified Imperative Code Generation
Fabian Gloeckle, Mantas Baksys, Darius Feher, et al. — preprint, arXiv:2603.29088, submitted 31 Mar 2026, revised 14 Apr 2026. [arXiv:2603.29088](https://arxiv.org/abs/2603.29088).
An agentic "prove-as-you-generate" framework in which code, invariants, and proofs co-evolve, combining automatic verification-condition generation and SMT solving with interactive Lean proofs ([arXiv:2603.29088](https://arxiv.org/abs/2603.29088)). Verbatim: "Our best system solves 74% of Verina tasks and 62% of Clever tasks at moderate compute budgets, substantially surpassing previous evaluations" ([arXiv:2603.29088](https://arxiv.org/abs/2603.29088)). The page describes synthesizing dozens of valid invariants, dispatching dozens of subgoals, and producing hundreds of lines of verified code ([arXiv:2603.29088](https://arxiv.org/abs/2603.29088)).
Mo relevance: 4.9% proof success on VERINA (single-shot, 2025) versus 74% of Verina tasks solved by an agentic co-evolution loop (2026) is the year's biggest delta, and it is a delta in loop design. Mo's advantage is that the loop is native.

### AxDafny: Agentic Verified Code Generation in Dafny
Benjamin Breen, Austin Letson, Borja Requena Pozo, et al. — preprint, arXiv:2606.32007, submitted 30 Jun 2026. [arXiv:2606.32007](https://arxiv.org/abs/2606.32007).
Verifier-guided repair that iteratively generates implementations, invariants, assertions, and termination arguments; 92.7% verification success on DafnyBench, 6.5 percentage points above the strongest previously reported proof-hint baseline, plus a new 250-problem LiveCodeBench-Pro-Dafny translated into Dafny with formal specs and a verifier-based harness ([arXiv:2606.32007](https://arxiv.org/abs/2606.32007)). The paper reports that verification success and runtime test performance measure different aspects of generated code ([arXiv:2606.32007](https://arxiv.org/abs/2606.32007)).
Mo relevance: "verified" and "passes tests" are different axes — which is precisely why Mo computes a separate `verified:` line at tier 2 rather than folding everything into a green test run ([[q08-verification-tiers]]).

### P³: Joint Program-and-Proof Planning for Verified Code Generation
Zenan Li, Ziran Yang, Peiyang Song, et al. — preprint, arXiv:2608.09277, submitted 10 Aug 2026. [arXiv:2608.09277](https://arxiv.org/abs/2608.09277).
The agent derives a unified program-and-proof plan from the specification before elaborating implementation and proof scaffold under that shared plan; across Verina, AlgoVeri, and Lean4Commit0 with four frontier LLM backends it achieves the highest solve rate in every benchmark–model setting, improving solve rates by 4.6–11.2 percentage points over the stronger baseline while cutting per-task API cost by up to roughly 40% and wall-clock time by up to roughly 37% on the difficult subsets; targeted ablation gives 3.3–8.3 points over implementation-only planning ([arXiv:2608.09277](https://arxiv.org/abs/2608.09277)).
Mo relevance: planning the contract and the body together beats planning the body alone by 3.3–8.3 points. That is an argument for Mo's ordering — signature and contract first, body second — as an agent-facing workflow, not only a review convention ([[d20-human-pulled-in-when-shape-changes]]).

### VeriSoftBench: Repository-Scale Formal Verification Benchmarks for Lean
Yutong Xin, Qiaochu Chen, Greg Durrett, et al. — preprint, arXiv:2602.18307, submitted 20 Feb 2026. [arXiv:2602.18307](https://arxiv.org/abs/2602.18307).
Verbatim: "We introduce VeriSoftBench, a benchmark of 500 Lean 4 proof obligations drawn from open-source formal-methods developments and packaged to preserve realistic repository context and cross-file dependencies" ([arXiv:2602.18307](https://arxiv.org/abs/2602.18307)). Three findings: Mathlib-style provers transfer poorly to repository-centric tasks; success decreases as transitive repository dependence grows; curated dependency-closure context beats exposing the whole repository ([arXiv:2602.18307](https://arxiv.org/abs/2602.18307)). No pass rates or model names are stated on the page.
Mo relevance: "curated dependency closure beats the whole repo" is a direct design constraint on what Mo's tooling should hand an agent — the closure of a declaration ID, not the file, and certainly not the project.

### Quokka: Accelerating Program Verification with LLMs via Invariant Synthesis
Anjiang Wei, Tarun Suresh, Tianran Sun, et al. — preprint, arXiv:2509.21629, submitted 25 Sep 2025, revised 30 Jan 2026. [arXiv:2509.21629](https://arxiv.org/abs/2509.21629).
Verbatim: "We construct a benchmark of 866 instances and evaluate 9 state-of-the-art LLMs across multiple model families" ([arXiv:2509.21629](https://arxiv.org/abs/2509.21629)). Quokka achieves at least 1.2x verification speedup on 81 instances versus 39 for the previous best approach, with supervised fine-tuning and Best-of-N sampling improving acceleration further ([arXiv:2509.21629](https://arxiv.org/abs/2509.21629)).
Mo relevance: invariants generated by a model are useful even when they only make the verifier faster rather than making an unprovable thing provable — a modest, credible framing for what `mo prove` could offer on day one.

### Loop Invariant Generation: A Hybrid Framework of Reasoning-optimised LLMs and SMT Solvers
Varun Bharti, Shashwat Jha, Dhruv Kumar, et al. — preprint, arXiv:2508.00419, submitted 1 Aug 2025. [arXiv:2508.00419](https://arxiv.org/abs/2508.00419).
O1, O1-mini and O3-mini paired with Z3 in a generate-and-check loop that refines invariants from solver counterexamples. Verbatim: "On this benchmark of 133 tasks, our framework achieves 100% coverage (133 out of 133), outperforming the previous best of 107 out of 133, while requiring only 1-2 model proposals per instance and 14-55 seconds of wall-clock time" ([arXiv:2508.00419](https://arxiv.org/abs/2508.00419)).
Mo relevance: for the bounded-loop shapes Mo permits, invariant synthesis is close to solved at 1–2 proposals per loop. This weakens the argument that Mo must ban `while` to keep verification tractable, and strengthens the argument that Mo's real reason for the ban is human legibility of bounds ([[q16-escape-hatch]], live dispute 2).

---

## A2. Autoformalization and spec-from-intent

### Intent Formalization: A Grand Challenge for Reliable Coding in the Age of AI Agents
Shuvendu K. Lahiri — preprint, arXiv:2603.17150, submitted 17 Mar 2026, 10 pages. [arXiv:2603.17150](https://arxiv.org/abs/2603.17150).
Position paper naming intent formalization — translating informal intent into checkable formal specs — as the deciding factor in whether AI makes software more reliable or merely more abundant. Verbatim: "The central bottleneck is validating specifications: since there is no oracle for specification correctness other than the user, we need semi-automated metrics that can assess specification quality with or without code, through lightweight user interaction and proxy artifacts such as tests" ([arXiv:2603.17150](https://arxiv.org/abs/2603.17150)). No quantitative results are stated on the page.
Mo relevance: this is, in the literature's own words, the argument for Mo's compiler-checked `test rejects` rule. A `requires` with a test that trips it is exactly a "proxy artifact" validating the spec ([[d19-negative-space-is-the-contract]]).

### Verus-SpecGym: An Agentic Environment for Evaluating Specification Autoformalization
Anmol Agarwal, Natalie Neamtu, Pranjal Aggarwal, et al. — preprint, arXiv:2605.26457, submitted 26 May 2026. [arXiv:2605.26457](https://arxiv.org/abs/2605.26457).
Verus-SpecBench holds 581 specification-writing tasks; Verus-SpecGym gives agents Verus, bash, and a filesystem ([arXiv:2605.26457](https://arxiv.org/abs/2605.26457)). Gemini 3.1 Pro solves 77.8%, other frontier models 51.1–57.8%, open-source models 21.5–25.5%; failures are model-generated specs that omit input assumptions, accept incorrect outputs, or reject valid ones; LLM-as-a-judge evaluation misses 26% of the failures the authors' evaluator catches ([arXiv:2605.26457](https://arxiv.org/abs/2605.26457)).
Mo relevance: the three failure modes map one-to-one onto Mo's contract vocabulary — missing `requires`, too-weak `ensures`, over-strong `requires`. The 26% judge-miss rate is a warning against ever letting a model grade Mo contracts without a mechanical check.

### ContractEval: A Benchmark for Evaluating Contract-Satisfying Assertions in Code Generation
Soohan Lim, Joonghyuk Hahn, Hyunwoo Park, et al. — preprint, arXiv:2510.12047, submitted 14 Oct 2025. [arXiv:2510.12047](https://arxiv.org/abs/2510.12047). Also listed as Findings of ACL 2026: [ACL Anthology](https://aclanthology.org/2026.findings-acl.2112/).
364 tasks, each with descriptions reconstructed to state contracts explicitly, test cases synthesized by an LLM + SMT pipeline, and reference code plus contracts ([arXiv:2510.12047](https://arxiv.org/abs/2510.12047)). Five open-source code LLMs reach 75–82% pass@1 functional correctness with 0% contract satisfaction under standard prompting; stating the contracts explicitly in the prompt raises contract satisfaction only to 23–41% ([arXiv:2510.12047](https://arxiv.org/abs/2510.12047)).
Mo relevance: the strongest single number in this dossier for the negative-space thesis. Functional correctness is not evidence of contract compliance; 0% baseline means the guard has to be a language rule, not a prompt ([[d19-negative-space-is-the-contract]], [[d04-style-rules-become-laws]]).

### Faithful Autoformalization of Natural Language Assertions (Monty)
Hongyi Liu, Madhusudan Parthasarathy, Adithya Murali — preprint, arXiv:2607.13303, submitted 14 Jul 2026. [arXiv:2607.13303](https://arxiv.org/abs/2607.13303).
Monty filters candidate formalizations using a conformance score plus validity scores obtained by testing code against the formalized assertions. On 541 assertion-generation tasks derived from 22 collection-like Java classes it recovers ground truth more reliably than naive LLM translation, improving precision by up to 20 points on average ([arXiv:2607.13303](https://arxiv.org/abs/2607.13303)).
Mo relevance: "test the spec by running code against it" is Mo's tier-2 loop in another language. Up-to-20-points precision from that filter is the expected value of making `test rejects` mandatory rather than optional.

### Faithful Autoformalization via Roundtrip Verification and Repair
Daneshvar Amrollahi, Jerry Lopez, Clark Barrett — preprint, arXiv:2604.25031, submitted 27 Apr 2026, revised 9 May 2026. [arXiv:2604.25031](https://arxiv.org/abs/2604.25031).
Formalize, translate back to natural language, re-formalize, then check logical equivalence with a formal tool — no ground-truth annotations needed; disagreements trigger stage-level diagnosis and scoped repair ([arXiv:2604.25031](https://arxiv.org/abs/2604.25031)). Evaluated on two statutory domains (Texas Transportation Code, Texas Parks and Wildlife Code) with Claude Opus 4.6 and GPT-5.2 against three repair baselines; under the full repair system, rules failing the equivalence check show 1.4x–2.5x more NLI drift than rules that pass ([arXiv:2604.25031](https://arxiv.org/abs/2604.25031)). Verbatim: "When an LLM formalizes natural language, how do we know the output is faithful?" ([arXiv:2604.25031](https://arxiv.org/abs/2604.25031)).
Mo relevance: a mechanical, oracle-free faithfulness check for the pair (`never` sentence, boolean block). Mo could run the roundtrip at commit time: does the quoted sentence re-formalize to the same predicate?

### Neurosymbolic Auditing of Natural-Language Software Requirements (VERIMED)
Bethel Hall, William Eiers — preprint, arXiv:2605.13817, submitted 13 May 2026. [arXiv:2605.13817](https://arxiv.org/abs/2605.13817).
Verbatim: "We show that large language models, equipped with an SMT solver, can audit such requirements: translating them into formal logic, detecting ambiguity through stochastic variation in the generated formalization, and exposing inconsistency, vacuousness, and safety violations through solver queries on the resulting specification" ([arXiv:2605.13817](https://arxiv.org/abs/2605.13817)). Verified accuracy on a hemodialysis question-answering benchmark rises from 55.4% to 98.5% once concrete SMT counterexamples are fed back ([arXiv:2605.13817](https://arxiv.org/abs/2605.13817)).
Mo relevance: two transferable mechanisms — ambiguity detected by sampling the same requirement several times and comparing formalizations, and vacuousness detected by solver query. Both are candidate `mo check` extensions for `never` clauses, and both attack live dispute 3 (vacuous tests).

### Validating Formal Specifications with LLM-generated Test Cases
Alcino Cunha, Nuno Macedo — preprint, arXiv:2510.23350, submitted 27 Oct 2025, revised 18 Feb 2026. [arXiv:2510.23350](https://arxiv.org/abs/2510.23350).
Test cases are generated from natural-language requirements for structural requirements of simple Alloy domain models. Verbatim: "The results show that, in this context, GPT-5 is already quite effective at generating positive (and negative) test cases that are syntactically correct and that satisfy (or not) the given requirement, and that can detect many wrong specifications written by humans" ([arXiv:2510.23350](https://arxiv.org/abs/2510.23350)). No pass rates or counts are stated on the abstract page.
Mo relevance: positive/negative test pairs generated from a requirement are structurally identical to Mo's `test rejects` obligation. The finding that they catch human spec errors supports applying the rule to human-written contracts too, not only model-written ones.

### Certified Program Synthesis with a Multi-Modal Verifier (LeetProof / Velvet)
Yueyang Feng, Dipesh Kafle, Vladimir Gladshtein, et al. — preprint, arXiv:2604.16584, submitted 17 Apr 2026. [arXiv:2604.16584](https://arxiv.org/abs/2604.16584).
Verbatim: "We overcome both challenges by structuring the certified synthesis workflow around a multi-modal verifier -- a single tool combining dynamic validation, automated proofs, and interactive proof scripting in one foundational framework" ([arXiv:2604.16584](https://arxiv.org/abs/2604.16584)). The two named challenges are specification defects and the limits of any single verification paradigm; the pipeline reportedly achieves a significantly higher rate of fully certified solutions than a single-mode baseline at the same budget across two frontier LLM backends, with no percentages stated on the page ([arXiv:2604.16584](https://arxiv.org/abs/2604.16584)).
Mo relevance: independent arrival at Mo's tiering — dynamic validation (tier 2/3) and proving (`mo prove`) as modes of one workflow rather than rival tools ([[d32-proving-is-a-separate-tool]]).

### PAT-Agent: Autoformalization for Model Checking
Authors not stated on the venue page — ASE 2025, Research Papers. [ASE 2025 page](https://conf.researchr.org/details/ase-2025/ase-2025-papers/200/PAT-Agent-Autoformalization-for-Model-Checking).
A Planning LLM extracts modelling elements and produces a plan, a Code Generation LLM synthesizes the formal model, the PAT model checker verifies it against user properties, and a Repair Loop corrects the model from counterexamples; experiments cover 40 systems and the page claims "high verification success with superior efficiency" without stating a rate ([ASE 2025](https://conf.researchr.org/details/ase-2025/ase-2025-papers/200/PAT-Agent-Autoformalization-for-Model-Checking)).
Mo relevance: counterexample-driven repair of the model (not the code) is the missing half of Mo's crash-to-task loop: sometimes the right fix is the contract, and the agent needs a protocol that permits proposing that ([[d21-autonomous-crash-fixing]]).

### Leveraging LLMs for Formal Software Requirements — Challenges and Prospects (VERIFAI)
Arshad Beg, Diarmuid O'Donoghue, Rosemary Monahan, et al. — Overlay 2025 workshop (26 Oct 2025); preprint submitted 18 Jul 2025. [arXiv:2507.14330](https://arxiv.org/abs/2507.14330).
Programme paper for the VERIFAI project: NLP, ontology-based domain modelling, artefact reuse and LLMs to generate verifiable specifications from informal requirements; no quantitative results are stated on the page ([arXiv:2507.14330](https://arxiv.org/abs/2507.14330)).
Mo relevance: evidence that funded programmes now treat spec-from-intent as an open problem; cite for framing, not numbers.

---

## A3. Agent–compiler feedback loops and diagnostic design

### Characterizing and Bridging the Diagnostic Gap in eBPF Verifier Rejections (bpfix)
Yusheng Zheng, Zhengjie Ji, Weichen Tao, et al. — preprint, arXiv:2607.02748, submitted 2 Jul 2026. [arXiv:2607.02748](https://arxiv.org/abs/2607.02748).
Verbatim: "To quantify this gap, we conduct an empirical study of 235 reproduced rejections, showing that 47% of rejections return only EINVAL, one error string maps to as many as nine distinct root causes, and 10 of the 12 root causes are eBPF-specific" ([arXiv:2607.02748](https://arxiv.org/abs/2607.02748)). bpfix reconstructs where the proof was established and lost from the verifier log and prints a Rust-like diagnostic; on a 75-task LLM repair benchmark, current models achieve 0–37% one-shot success with the raw verifier log, and replacing the log with bpfix localization improves repair by 11–21 percentage points ([arXiv:2607.02748](https://arxiv.org/abs/2607.02748)).
Mo relevance: the closest thing in the literature to a controlled measurement of diagnostic design against agent repair success. It quantifies the value of Mo's `what`/`why`/stable-code diagnostics at 11–21 points, and it names the anti-pattern Mo must avoid: one error code covering many root causes ([[q09-compiler-diagnostics]]).

### Type-Error Ablation and AI Coding Agents
Shriram Krishnamurthi, Matthew Flatt — preprint, arXiv:2606.01522, submitted 1 Jun 2026. [arXiv:2606.01522](https://arxiv.org/abs/2606.01522).
Programs carrying a single deliberate type error each, with error messages ablated to different detail levels. Verbatim: "We find concrete evidence that more detailed error messages improve an agent's ability to fix type errors" ([arXiv:2606.01522](https://arxiv.org/abs/2606.01522)). The page also reports that the presence of a type system appears to help more than test-suite failure reports alone, and that when the agent fixes the type error the program passes all semantic tests most of the time; no numerical rates are stated on the abstract page ([arXiv:2606.01522](https://arxiv.org/abs/2606.01522)).
Mo relevance: two Mo bets in one ablation — types beat tests as agent feedback, and message detail is a design variable with measurable payoff. Note the honest limit: the abstract page gives direction, not magnitude.

### Not the Silver Bullet: LLM-enhanced Programming Error Messages are Ineffective in Practice
Eddie Antonio Santos, Brett A. Becker — UKICER '24 proceedings; preprint submitted 27 Sep 2024. [arXiv:2409.18661](https://arxiv.org/abs/2409.18661).
A within-subjects study with n = 106 participants compared stock compiler messages, expert-handwritten messages, and GPT-4 explanations across six buggy C programs. Verbatim: "Despite promising evidence on synthetic benchmarks, we found that GPT-4 generated error messages outperformed conventional compiler error messages in only 1 of the 6 tasks, measured by students' time-to-fix each problem"; handwritten explanations beat both LLM-generated and conventional messages on objective and subjective measures ([arXiv:2409.18661](https://arxiv.org/abs/2409.18661)).
Mo relevance: hand-authored diagnostics won. That is an argument for Mo's insistence that every diagnostic is written, coded and curated rather than generated ([[q09-compiler-diagnostics]]).

### Beyond the Traceback: Using LLMs for Adaptive Explanations of Programming Errors
Alexandru-Radu Moraru, Shreyan Biswas, Ujwal Gadiraju — preprint, arXiv:2608.20896, submitted 21 Aug 2026. [arXiv:2608.20896](https://arxiv.org/abs/2608.20896).
A multi-stage crowdsourced study with N = 103 compared two LLM-generated styles (pragmatic/action-oriented and contingent/scaffolded) on three objective metrics (fix rate, attempts, time-to-fix) and three subjective ones (readability, cognitive load, tone). Verbatim finding: rewritten messages "significantly improved subjective evaluations... these perceived gains did not translate into statistically significant improvements in objective debugging performance," described as "a critical human-AI complementarity gap" ([arXiv:2608.20896](https://arxiv.org/abs/2608.20896)).
Mo relevance: replicates the Silver Bullet result with a different design. Mo should measure diagnostics against agent loop count and human fix time, and should not trust "this message reads better" as evidence.

### Using Large Language Models to Enhance Programming Error Messages
Juho Leinonen, Arto Hellas, Sami Sarsa, et al. — SIGCSE TS 2023; preprint submitted 20 Oct 2022. [arXiv:2210.11630](https://arxiv.org/abs/2210.11630); [DOI 10.1145/3545945.3569770](https://dl.acm.org/doi/10.1145/3545945.3569770).
The originating optimistic result: "Large language models can be used to create useful and novice-friendly enhancements to programming error messages that sometimes surpass the original programming error messages in interpretability and actionability" ([arXiv:2210.11630](https://arxiv.org/abs/2210.11630)). The ACM landing page carries the title, authors and a 03/02/2023 issue date but no abstract text or numbers ([DOI 10.1145/3545945.3569770](https://dl.acm.org/doi/10.1145/3545945.3569770)).
Mo relevance: lineage for the 2024–2026 negative replications. Keep it cited so the disagreement in the literature stays visible.

### Auto-repair without test cases: How LLMs fix compilation errors in large industrial embedded code
Han Fu, Sigrid Eldh, Kristian Wiklund, et al. — 2025 28th Euromicro Conference on Digital System Design (DSD); preprint submitted 15 Oct 2025. [arXiv:2510.13575](https://arxiv.org/abs/2510.13575).
From more than 40,000 commits of an industrial product, an industrial CI system augmented with four state-of-the-art LLMs (unnamed on the page) resolves up to 63% of compilation errors in the baseline dataset; 83% of fixes associated with successful CI builds are judged reasonable; the majority of successful cases complete within 8 minutes against hours for manual debugging ([arXiv:2510.13575](https://arxiv.org/abs/2510.13575)).
Mo relevance: the industrial baseline for "compiler error in, patch out" without tests — and the reason Mo's Round 3 control result (6 syntax diagnostics before green) should be read as normal rather than damning, provided each diagnostic round is cheap.

### Unlocking LLM Code Correction with Iterative Feedback Loops
Le Zhang, Suresh Kothari — 14th Computing Conference 2026; preprint submitted 16 Jun 2026. [arXiv:2606.17514](https://arxiv.org/abs/2606.17514).
Four models, two major programming languages, real-world problems, iterating on compiler messages and test-case feedback. Verbatim: "Results show that reasoning models consistently improve over iterations, substantially outperforming non-reasoning models in leveraging feedback, while syntactic and runtime errors are far more tractable than logical or algorithmic failures" ([arXiv:2606.17514](https://arxiv.org/abs/2606.17514)). No per-iteration percentages, model names or benchmark sizes are stated on the page.
Mo relevance: Mo's loop count is dominated by whatever class of error the language surfaces. If syntactic and runtime errors converge fast and logic errors do not, Mo's 9-loop Round 3 profile (6 syntax + 1 real bug + 2 test mistakes) is a cheap profile, not an expensive one — the syntax rounds are the tractable class.

### Static Analysis as a Feedback Loop: Enhancing LLM-Generated Code Beyond Correctness
Scott Blyth, Sherlock A. Licorish, Christoph Treude, et al. — preprint, arXiv:2508.14419, submitted 20 Aug 2025. [arXiv:2508.14419](https://arxiv.org/abs/2508.14419).
Iterative static-analysis prompting with Bandit and Pylint on PythonSecurityEval with GPT-4o: security issues fall from over 40% to 13%, readability violations from over 80% to 11%, reliability warnings from over 50% to 11%, within ten iterations ([arXiv:2508.14419](https://arxiv.org/abs/2508.14419)). Verbatim: "These results demonstrate that LLMs, when guided by static analysis feedback, can significantly enhance code quality beyond functional correctness" ([arXiv:2508.14419](https://arxiv.org/abs/2508.14419)).
Mo relevance: the null hypothesis in Mo's own control-run framing, quantified. Bolting analyzers onto Python does drive violations to roughly 11–13% within ten loops. Mo's claim has to be that its checks reach zero at loop one, by construction, not that no one else can improve.

### AkiraRust: Re-thinking LLM-aided Rust Repair Using a Feedback-guided Thinking Switch
Renshuang Jiang, Yichong Wang, Pan Dong, et al. — accepted to DAC (year not stated on the page); preprint submitted 25 Feb 2026. [arXiv:2602.21681](https://arxiv.org/abs/2602.21681).
A finite-state machine adapts the detect/repair flow to runtime semantic conditions and coordinates fast and slow thinking across agents. Verbatim: "Experimental results show that AkiraRust achieves about 92% semantic correctness and delivers a 2.2x average speedup compared to SOTA" ([arXiv:2602.21681](https://arxiv.org/abs/2602.21681)).
Mo relevance: 92% semantic correctness on Rust repair is the bar a Mo-native repair loop is measured against, and the 2.2x speedup comes from routing (cheap model for cheap errors) — a natural fit for Mo's stable diagnostic codes, which make routing decidable without a model call.

### Learning to Repair Lean Proofs from Compiler Feedback (APRIL)
Evan Wang, Simon Chess, Daniel Lee, et al. — preprint, arXiv:2602.02990, submitted 3 Feb 2026, 15 pages. [arXiv:2602.02990](https://arxiv.org/abs/2602.02990).
Verbatim: "We introduce APRIL (Automated Proof Repair in Lean), a dataset of 260,000 supervised tuples pairing systematically generated proof failures with compiler diagnostics and aligned repair and explanation targets" ([arXiv:2602.02990](https://arxiv.org/abs/2602.02990)). A finetuned 4B-parameter model outperforms the strongest open-source baseline in single-shot repair; no percentages are given on the page ([arXiv:2602.02990](https://arxiv.org/abs/2602.02990)).
Mo relevance: diagnostics are training data. If Mo emits stable codes with `what`/`why` fields, the (failure, diagnostic, repair) triple is machine-generable at scale — the cheapest path to a small Mo-specialized repair model ([[q09-compiler-diagnostics]]).

### Beyond Fixed Tests: Repository-Level Issue Resolution as Coevolution of Code and Behavioral Constraints (Agent-CoEvo)
Kefan Li, Yuan Yuan, Mengfei Wang, et al. — preprint, arXiv:2604.04580, submitted 6 Apr 2026. [arXiv:2604.04580](https://arxiv.org/abs/2604.04580).
Verbatim: "We argue that repository-level issue resolution is fundamentally not optimization under fixed tests, but search over evolving behavioral constraints" ([arXiv:2604.04580](https://arxiv.org/abs/2604.04580)); no numbers are stated on the page.
Mo relevance: if constraints co-evolve with code, an agent fixing a crash must be allowed to propose a contract change — which in Mo pulls in a human by design ([[d20-human-pulled-in-when-shape-changes]]).

### Agentic Hardware Design as Repository-Level Code Evolution (HORIZON)
Cunxi Yu, Chenhui Deng, Nathaniel Pinckney, et al. — preprint, arXiv:2606.28279, submitted 26 Jun 2026. [arXiv:2606.28279](https://arxiv.org/abs/2606.28279).
The harness is a Markdown file, a project pack, an executable evaluator, an acceptance predicate and a git/runtime policy; it reports 100% benchmark completion across ChipBench, RTLLM, Verilog-Eval and nine CVDP categories in a hands-free loop, while stating agentic hardware design is not solved ([arXiv:2606.28279](https://arxiv.org/abs/2606.28279)).
Mo relevance: the acceptance predicate is load-bearing — an explicit, machine-checkable definition of done, like Mo's `verified:` line. It also shows "100% completion" against a weak predicate means little, which is the vacuity risk in live dispute 3.
---

## A4. Constrained and grammar-guided decoding

### Type-Constrained Code Generation with Language Models
Niels Mündler, Jingxuan He, Hao Wang, et al. — preprint, arXiv:2504.09246, submitted 12 Apr 2025, revised 6 Jun 2025. [arXiv:2504.09246](https://arxiv.org/abs/2504.09246).
A type system for TypeScript prefixes drives prefix-based type inference and searches for viable completions during decoding. Verbatim: "Our method reduces compilation errors by more than half and significantly increases functional correctness in code synthesis, translation, and repair tasks across LLMs of various sizes and model families, including SOTA open-weight models with more than 30B parameters" ([arXiv:2504.09246](https://arxiv.org/abs/2504.09246)). On HumanEval synthesis it delivers 3.5% absolute improvement in functional correctness for open-weight models and 1.1% absolute for closed models, and on repair it more than doubles gains ([arXiv:2504.09246](https://arxiv.org/abs/2504.09246)).
Mo relevance: the compiler's type information, applied at generation time, halves compile errors. Mo's Rust-plus-refinements type system is a richer constraint source than TypeScript's, and Mo's fast checker makes prefix-time checking plausible ([[d22-rust-plus-refinements-types]], [[d23-compile-speed-first-class]]).

### SynCode: LLM Generation with Grammar Augmentation
Shubham Ugare, Tarun Suresh, Hangoo Kang, et al. — preprint, arXiv:2403.01632, submitted 3 Mar 2024, revised 10 Nov 2024. [arXiv:2403.01632](https://arxiv.org/abs/2403.01632).
An offline DFA mask store built from the language grammar's terminals lets SynCode retain only syntactically valid tokens, with soundness and completeness proofs for context-free grammars ([arXiv:2403.01632](https://arxiv.org/abs/2403.01632)). Verbatim: "Our experiments demonstrate SynCode's effectiveness, showing a 96.07% reduction in syntax errors for Python and Go code generation" ([arXiv:2403.01632](https://arxiv.org/abs/2403.01632)); JSON and Python/Go integrations achieve 100% and 96.07% syntax-error elimination respectively, and quantitative results include 100%, 96.07%, 10.2%, 13% and 26.4% figures on the page ([arXiv:2403.01632](https://arxiv.org/abs/2403.01632)).
Mo relevance: already in the wiki; the number to remember is that grammar masking removes essentially all syntax errors. Mo's Round 3 profile was dominated by syntax diagnostics, so a published Mo grammar with a mask store would erase most of that loop count ([[q09-compiler-diagnostics]], live dispute on control-run baselines).

### Correctness-Guaranteed Code Generation via Constrained Decoding
Lior Fox, Michael Deviatkin, Reut Tsarfaty, et al. — COLM 2025; preprint submitted 21 Aug 2025. [arXiv:2508.15866](https://arxiv.org/abs/2508.15866).
Claims a constrained-decoding scheme that guarantees syntactic correctness against a formal grammar while preserving the model's distribution over valid strings; no pass rates on the abstract page ([arXiv:2508.15866](https://arxiv.org/abs/2508.15866)).
Mo relevance: guarantees are grammar-relative, so shipping a machine-readable Mo grammar is a distribution decision ([[d35-mo-is-an-ecosystem]]).

### Flexible and Efficient Grammar-Constrained Decoding
Kanghee Park, Timothy Zhou, Loris D'Antoni — preprint, arXiv:2502.05111, submitted 7 Feb 2025. [arXiv:2502.05111](https://arxiv.org/abs/2502.05111).
A new GCD algorithm precomputes 17.71x faster than the best prior approach while retaining state-of-the-art efficiency at inference time ([arXiv:2502.05111](https://arxiv.org/abs/2502.05111)). Verbatim: "Our algorithm achieves the best of both worlds" ([arXiv:2502.05111](https://arxiv.org/abs/2502.05111)).
Mo relevance: preprocessing cost was the practical obstacle to grammar-constrained decoding for a language whose grammar is still moving. A 17.71x cheaper precompute makes "regenerate the mask store on every grammar change" viable during Mo's design phase.

### Generating Structured Outputs from Language Models: Benchmark and Studies (JSONSchemaBench)
Saibo Geng, Hudson Cooper, Michał Moskal, et al. — preprint, arXiv:2501.10868, submitted 18 Jan 2025, revised 6 Feb 2025. [arXiv:2501.10868](https://arxiv.org/abs/2501.10868).
JSONSchemaBench holds roughly 10,000 real-world JSON schemas across a wide range of constraint complexity, and six state-of-the-art constrained-decoding frameworks are evaluated on efficiency, coverage, and quality ([arXiv:2501.10868](https://arxiv.org/abs/2501.10868)). Verbatim: "we uncover key trade-offs in structured generation: constrained decoding enforces syntactic validity but may degrade semantic fidelity" ([arXiv:2501.10868](https://arxiv.org/abs/2501.10868)).
Mo relevance: the trade-off is the caution Mo needs. Constraining syntax hard enough to force validity can make the model write worse logic; Mo's laws are grammar-level constraints and could carry the same cost. Testable with Mo's own control runs ([[d28-nothing-final-until-measured]]).

### TyFlow: Type-Centric Neurosymbolic Code Generation
Author list not shown on the page — preprint, arXiv:2510.10216, submitted 11 Oct 2025. [arXiv:2510.10216](https://arxiv.org/abs/2510.10216).
Makes type information part of generation rather than a post-hoc filter; the page claims substantial improvements in complex type-directed synthesis without numbers ([arXiv:2510.10216](https://arxiv.org/abs/2510.10216)).
Mo relevance: the more Mo pushes semantics into types, the more this matters — the prerequisite is a checker fast enough for the decode loop.

### AdapTrack: Grammar-Adaptive Tracking for Constrained Decoding
Zhiyu Fan, Shin Hwei Tan, Abhik Roychoudhury, et al. — ICSE 2026; preprint submitted 20 Oct 2025. [arXiv:2510.17376](https://arxiv.org/abs/2510.17376).
Reported improvements of 360.87%, 38.93%, 7.84% and 6.42% on four evaluation settings against prior constrained-decoding baselines, with the largest gain on the hardest setting ([arXiv:2510.17376](https://arxiv.org/abs/2510.17376)).
Mo relevance: the enormous headline improvement is on the setting where the baseline was weakest — the honest reading is that constrained decoding is still immature for unfamiliar grammars, which is exactly Mo's situation.

### Grammar Prompting for Domain-Specific Language Generation with Large Language Models
Bailin Wang, Zi Wang, Xuezhi Wang, et al. — preprint, arXiv:2305.19234, submitted 30 May 2023. [arXiv:2305.19234](https://arxiv.org/abs/2305.19234).
Verbatim: "We propose grammar prompting, a simple approach to enable LLMs to use external knowledge and domain-specific constraints, expressed through a grammar in Backus-Naur Form (BNF), during in-context learning" ([arXiv:2305.19234](https://arxiv.org/abs/2305.19234)). Each demonstration is augmented with a specialized BNF grammar; at inference the model predicts a grammar for the input and then generates against it, evaluated on semantic parsing, PDDL planning, and SMILES molecule generation ([arXiv:2305.19234](https://arxiv.org/abs/2305.19234)). No experimental numbers are stated on the abstract page.
Mo relevance: the cheapest cold-start mechanism available to Mo — ship the BNF in the prompt, no decoder integration required. It costs tokens per call, which interacts with B1 ([[d35-mo-is-an-ecosystem]]).

### From Text to DSL: Evaluating Open LLMs on Grammar-Conformant Generation
Author list not shown on the page — preprint, arXiv:2605.15865, submitted 16 May 2026. [arXiv:2605.15865](https://arxiv.org/abs/2605.15865).
39 open LLMs from 0.5B to 32B parameters are evaluated on generating grammar-conformant DSL output under zero-shot and few-shot prompting ([arXiv:2605.15865](https://arxiv.org/abs/2605.15865)). The page reports that few-shot examples substantially improve grammar conformance and that model scale alone does not determine conformance; specific rates are n.a. on the abstract page.
Mo relevance: relevant to Mo's cold start on small local models. "Few-shot beats scale" implies a curated Mo example pack matters more than waiting for the next frontier model.

### Semantic Probabilistic Control of Language Models (SPEAC / UCLID5)
Kareem Ahmed, Catarina G. Belém, Padhraic Smyth, et al. — preprint, arXiv:2406.03636, submitted 5 Jun 2024, revised 6 Jun 2025. [arXiv:2406.03636](https://arxiv.org/abs/2406.03636).
Semantic control uses a differentiable proxy for a semantic constraint and steers generation via gradient-based sampling; the paper reports effectiveness on detoxification, sentiment control, and — the Mo-relevant case — "enforcing syntactic constraints in the challenging domain of program synthesis in the UCLID5 formal verification language" ([arXiv:2406.03636](https://arxiv.org/abs/2406.03636)). No pass rates are stated on the page.
Mo relevance: an existence proof that a niche verification language can be steered without retraining. Modest, but the best-fit precedent for Mo's exact position: no corpus, formal grammar, small user base.

---

## A5. Test generation, mutation testing, and vacuous tests

### Mutation-Guided LLM-based Test Generation at Meta (ACH)
Christopher Foster, Abhishek Gulati, Mark Harman, et al. — preprint, arXiv:2501.12862, submitted 22 Jan 2025. [arXiv:2501.12862](https://arxiv.org/abs/2501.12862).
ACH generates faults (mutants) from a textual description of a fault class and then generates tests that detect them; deployed at Meta on Instagram and Facebook privacy work it was applied to 10,795 Kotlin classes, produced 9,095 mutants, and yielded 571 tests accepted by engineers — a 73% acceptance rate, of which 36% were deemed privacy-relevant ([arXiv:2501.12862](https://arxiv.org/abs/2501.12862)). Verbatim: "Our initial deployment was primitive: only 25% of the tests it generated were accepted by engineers. After the improvements described in this paper, ACH's test acceptance rate rose to 73%" ([arXiv:2501.12862](https://arxiv.org/abs/2501.12862)); mutant precision rose from 0.79 to 0.95 ([arXiv:2501.12862](https://arxiv.org/abs/2501.12862)).
Mo relevance: the production answer to vacuous tests. Generate the fault first, then require a test that catches it. This is the strongest available support for making Mo's fault-injection tests mandatory and mechanically checked rather than declared ([[d19-negative-space-is-the-contract]], live dispute 3).

### AdverTest: Adversarial Mutation-Guided Test Generation
Yifan Zhang, Wenhan Zhu, Xin Zhou, et al. — preprint, arXiv:2602.08146, submitted 9 Feb 2026. [arXiv:2602.08146](https://arxiv.org/abs/2602.08146).
An adversarial loop where a mutant generator and a test generator co-improve. Reported mutation-score improvements: 8.56% over the best LLM-based state of the art and 63.30% over EvoSuite ([arXiv:2602.08146](https://arxiv.org/abs/2602.08146)).
Mo relevance: gives Mo a metric for test quality that does not depend on human judgment — mutation score against generated faults. Candidate for `mo test --sim` scoring.

### SWE-Mutation: Benchmarking LLMs on Repository-Level Mutation Testing
Zhiyuan Pan, Xing Hu, Xin Xia, et al. — Findings of ACL 2026; preprint submitted 28 May 2026. [arXiv:2605.22175](https://arxiv.org/abs/2605.22175).
2,636 mutants over 800 repository instances in 9 programming languages, evaluating both mutant verification (can the model tell whether a mutant is killed) and detection ([arXiv:2605.22175](https://arxiv.org/abs/2605.22175)). DeepSeek-V3.1 achieves only 10.20% on verification and 36.15% on detection; detection accuracy falls from 71.04% on same-file cases to 39.81% when the mutant and test are in different files ([arXiv:2605.22175](https://arxiv.org/abs/2605.22175)).
Mo relevance: models are bad at judging whether a test actually catches a fault, and much worse across files. So Mo cannot delegate the vacuity check to a model; it must be executed (inject fault, observe failure). Cross-file collapse also argues for Mo's small-file laws ([[q12-law-numbers]]).

### Can Large Language Models Write Good Property-Based Tests?
Vasudev Vikram, Caroline Lemieux, Rohan Padhye — preprint, arXiv:2307.04346, submitted 10 Jul 2023, revised 12 Oct 2023. [arXiv:2307.04346](https://arxiv.org/abs/2307.04346).
Verbatim: "Our best-performing configuration, GPT-4 with 'Chain-of-Thought' prompting, produced 21% valid, non-trivial PBTs" ([arXiv:2307.04346](https://arxiv.org/abs/2307.04346)). The study spans 40 Python library APIs with a validity/soundness/completeness taxonomy and reports models sampled few candidates (a mean around 2.4 distinct properties per API) ([arXiv:2307.04346](https://arxiv.org/abs/2307.04346)).
Mo relevance: the 21% figure sets the baseline for asking a model to invent properties unaided. Mo's `never` sentences hand the property to the model instead of asking it to guess — that is the design response to a 21% success rate.

### On the Effectiveness of LLM-Generated Property-Based Tests in Finding Edge-Case Bugs
Author list not shown on the page — AIware 2025; preprint submitted 29 Oct 2025. [arXiv:2510.25297](https://arxiv.org/abs/2510.25297).
Property-based tests and example-based tests each detect 68.75% of the studied edge-case bugs, while their union reaches 81.25% ([arXiv:2510.25297](https://arxiv.org/abs/2510.25297)).
Mo relevance: PBTs and concrete examples are complementary, not substitutes — equal individually, materially better together. Mo's test story should require both a `rejects` example and a property, and this is the number that justifies the double cost.

### Property-Generated Solver: Property-oriented feedback for code generation (PGS)
Fangwen Mu, Lin Shi, Song Wang, et al. — preprint, arXiv:2506.18315, submitted 23 Jun 2025. [arXiv:2506.18315](https://arxiv.org/abs/2506.18315).
A Generator plus a Tester agent using property-based testing rather than example tests to drive the feedback loop. The page reports an average pass@1 improvement of 13.4% over the compared feedback methods, a fix rate above 64%, and efficiency of roughly 1.4x–1.6x in inference cost ([arXiv:2506.18315](https://arxiv.org/abs/2506.18315)).
Mo relevance: property-shaped feedback beats example-shaped feedback in the repair loop, which is what Mo's `never` clauses become when a test fails — and it is cheaper per fix, which matters for Mo's loop economics.

### HierSVA: A Data Synthesis Pipeline, Dataset, and Benchmark for LLM-Driven Hierarchical Hardware Formal Verification
Maohua Nie, Jiang Zhu, Jingqun Zhang, et al. — preprint, arXiv:2606.13706, submitted 9 Jun 2026. [arXiv:2606.13706](https://arxiv.org/abs/2606.13706).
HierSVA-DS holds 342 modules at hierarchy depths 0–9, with a 28 module-bug-pair deep subset; HierSVA-B scores six axes: syntax correctness, assertion proof success rate, vacuity, specification faithfulness, mutation coverage, and formal core coverage; twelve recent LLMs are evaluated, giving a 67.1% module-level compile rate, with 82.1% of assertions in evaluable runs proving non-vacuously ([arXiv:2606.13706](https://arxiv.org/abs/2606.13706)).
Mo relevance: this is the only benchmark found that scores vacuity as a first-class metric. Its axis list is a ready-made scorecard for Mo's own contract-quality evaluation, and roughly 18% vacuous-or-worse assertions quantifies how real the vacuity risk is (live dispute 3).

### Closing the Quality Loop for RTL Assertion Generation
Author list not shown on the page — preprint, arXiv:2606.21451, submitted 24 Jun 2026. [arXiv:2606.21451](https://arxiv.org/abs/2606.21451).
Argues assertion generation must be evaluated by a quality loop rather than syntactic acceptance; no quantitative results on the abstract page ([arXiv:2606.21451](https://arxiv.org/abs/2606.21451)).
Mo relevance: framing for the claim that "the assertion compiles" is not evidence the assertion is worth anything.

---

## A6. Editing by structure or ID, and edit-failure modes

### CodeStruct: Structure-Aware Code Editing for Language Models
Author list not shown on the page — Findings of ACL 2026; preprint submitted 6 Apr 2026. [arXiv:2604.05407](https://arxiv.org/abs/2604.05407).
Edits are expressed against AST entities (declarations, blocks) rather than as text diffs or line ranges. Reported results: pass@1 improvements of 1.2%–5.0% over diff-based baselines with 12%–38% fewer output tokens, and the empty-patch rate for GPT-5-nano falls from 46.6% to 7.2% ([arXiv:2604.05407](https://arxiv.org/abs/2604.05407)).
Mo relevance: the strongest direct evidence for edit-by-declaration-ID. The empty-patch collapse (46.6% → 7.2%) is a mechanical failure mode of text-based editing that structure-based editing removes, and small models benefit most ([[d29-edit-by-declaration-id]]).

### To Diff or Not to Diff: Adaptive Edit Representations for Code Agents (AdaEdit)
Author list not shown on the page — Findings of ACL 2026; preprint submitted 30 Apr 2026. [arXiv:2604.27296](https://arxiv.org/abs/2604.27296).
The agent chooses per-edit between whole-file rewriting and diff/patch representations based on predicted edit locality and size, cutting latency and cost by more than 30% relative to a fixed representation while maintaining or improving resolve rate ([arXiv:2604.27296](https://arxiv.org/abs/2604.27296)).
Mo relevance: an argument against making declaration-ID edits the only channel. Mo should offer the ID channel and a whole-declaration rewrite, and let the agent pick — that is what the measured 30% saving comes from.

### SWE-Edit: Training Code Agents to Edit
Author list not shown on the page — preprint, arXiv:2604.26102, submitted 29 Apr 2026. [arXiv:2604.26102](https://arxiv.org/abs/2604.26102).
Reinforcement learning (GRPO) on Qwen3-8B specifically for the edit action yields +2.1 percentage points resolve rate, −17.9% cost, and +12.5 percentage points edit success rate ([arXiv:2604.26102](https://arxiv.org/abs/2604.26102)).
Mo relevance: edit success is trainable and is not the same variable as reasoning quality. If Mo's edit protocol is clean and machine-checkable, a small model can be trained to hit it — the +12.5-point edit-success delta is the size of the prize.

### Structure-Aware Fill-in-the-Middle Pretraining for Code (AST-FIM)
Linyuan Gong, Alvin Cheung, Mohammad Rasool Fakoor, et al. — preprint, arXiv:2506.00204, submitted 30 May 2025. [arXiv:2506.00204](https://arxiv.org/abs/2506.00204).
Verbatim: "we propose AST-FIM, a pretraining strategy that leverages Abstract Syntax Trees (ASTs) to mask complete syntactic structures at scale, ensuring coherent training examples better aligned with universal real-world code structures and common code edits" ([arXiv:2506.00204](https://arxiv.org/abs/2506.00204)). The paper also introduces Real-FIM-Eval, derived from 30,000+ real code changes across 12 languages, and reports AST-FIM outperforming standard random-character FIM by up to 5 points on infilling benchmarks ([arXiv:2506.00204](https://arxiv.org/abs/2506.00204)).
Mo relevance: structure-aligned masking during pretraining transfers to real edits. For Mo, the corollary is that a synthetic Mo corpus should be masked at declaration boundaries — the same boundaries `.mo.ids` names ([[d29-edit-by-declaration-id]]).

### SWE-agent: Agent-Computer Interfaces Enable Automated Software Engineering
John Yang, Carlos E. Jimenez, Alexander Wettig, et al. — preprint, arXiv:2405.15793, submitted 6 May 2024. [arXiv:2405.15793](https://arxiv.org/abs/2405.15793).
Verbatim: "we design an ACI which achieves a pass@1 rate of 12.5% on SWE-bench, over four times the state-of-the-art of 3.8% for a comparable non-interactive LM," plus 87.7% on HumanEvalFix ([arXiv:2405.15793](https://arxiv.org/abs/2405.15793)).
Mo relevance: the interface, not the model, produced the gain — the precedent for treating the tool surface (and a language) as a first-order variable.

### Understanding the Behaviour of Code Agents: A Trajectory-Level Analysis
Author list not shown on the page — preprint, arXiv:2511.00197, submitted 31 Oct 2025. [arXiv:2511.00197](https://arxiv.org/abs/2511.00197).
Trajectory analysis finds agents locate the correct files in 72%–81% of tasks even when the final patch fails, isolating the failure to editing and reasoning rather than search ([arXiv:2511.00197](https://arxiv.org/abs/2511.00197)).
Mo relevance: localization is close to solved; the loss is in the edit and the reasoning about the change. Mo's leverage is therefore at the point of edit and at the check that follows it, not in code navigation.

### Understanding Failures in Automated Issue Solving
Author list not shown on the page — preprint, arXiv:2509.13941, submitted 17 Sep 2025. [arXiv:2509.13941](https://arxiv.org/abs/2509.13941).
A manual analysis of 150 failed trajectories produces a taxonomy of 3 phases, 9 categories, and 25 fine-grained failure modes; a targeted intervention derived from the taxonomy solves 22.2% more of the previously intractable instances ([arXiv:2509.13941](https://arxiv.org/abs/2509.13941)).
Mo relevance: failure modes are addressable once named — a 22.2% recovery on "intractable" cases. Mo's equivalent artifact is a taxonomy of its own control-run failures, which the Round 3 loop counts have started ([[d28-nothing-final-until-measured]]).

### Metaprogramming for Unfamiliar Languages
Author list not shown on the page — preprint, arXiv:2606.10933, submitted 11 Jun 2026. [arXiv:2606.10933](https://arxiv.org/abs/2606.10933).
Six coding agents were evaluated on four esoteric languages. Claude Opus 4.6 and GPT-5.4 at extra-high reasoning effort spontaneously wrote Python metaprograms that emit the target-language program rather than writing the target language directly, and performance dropped substantially when that strategy was restricted ([arXiv:2606.10933](https://arxiv.org/abs/2606.10933)).
Mo relevance: a direct warning for Mo's cold start. Agents faced with an unfamiliar language will route around it by generating it from a familiar one — so Mo needs either good enough direct support or an honest generator story, plus evals that detect the workaround ([[d01-agents-write-the-code]]).
---

## B1. Token efficiency versus correctness across languages

### How does programming language affect token efficiency and correctness?
Dan Luu — personal blog post, no publication date stated on the page. [danluu.com/pl-tokens](https://danluu.com/pl-tokens/). Not peer-reviewed; treat as engineering evidence, not academic.
The post reports "a very meaningful gap of 2.6x between C (the least token efficient language I compared) and Clojure (the most efficient)" and, on a cited Rosetta Code experiment, J "dominates at just 70 tokens average, nearly half of Clojure (109 tokens)" ([danluu.com/pl-tokens](https://danluu.com/pl-tokens/)). It also documents how easily such evals break: in a cited `ai-coding-lang-bench` run "the only failures in 600 runs were in Rust and Haskell," which turned out to be a harness bug — a Go run had created a symlink so later tests for every language ran the first Go executable, and "on rescoring Rust against its own executable ... Rust gets a perfect score" ([danluu.com/pl-tokens](https://danluu.com/pl-tokens/)). On a Zstd task, 36 of 40 medium-effort and 5 of 40 ultra-effort Clojure programs had test failures traced to one library detail (`byte` conversion throwing on 128–255), and on a Guards of Atlantis 2 task, "regardless of language, agents scored approximately 0" ([danluu.com/pl-tokens](https://danluu.com/pl-tokens/)). The author pre-registered confidence levels — 95% that the broad dynamic-versus-static claim would not hold, 60% that static languages would be somewhat better at ultra effort, 98% that J-style "weird language supremacy" would not hold ([danluu.com/pl-tokens](https://danluu.com/pl-tokens/)).
Mo relevance: the most useful thing here is methodological. A single library gotcha moved a language's failure rate by 31 of 40 programs, and a symlink invalidated a 600-run result. Mo's own control runs need per-language harness isolation, pre-registration, and enough tasks that one stdlib quirk cannot dominate ([[d28-nothing-final-until-measured]]).

### The Hidden Cost of Readability: How Code Formatting Silently Consumes Your LLM Budget
Dangfeng Pan, Zhensu Sun, Cenyuan Zhang, et al. — ICSE'26 (first cycle); preprint submitted 19 Aug 2025. [arXiv:2508.13666](https://arxiv.org/abs/2508.13666).
Ten LLMs, four languages (Java, Python, C++, C#), fill-in-the-middle completion: removing formatting elements gives an average input token reduction of 24.5% with negligible output token reduction and without degrading performance; prompting and fine-tuning cut output code length by up to 36.1% without compromising correctness; the authors ship a bidirectional transformation tool so humans still read formatted code ([arXiv:2508.13666](https://arxiv.org/abs/2508.13666)).
Mo relevance: whitespace and formatting are 24.5% of input cost and carry no measured signal for models. That is a strong argument for a canonical Mo formatter with a compact wire form for agents — and against paying for legibility twice ([[d26-developer-and-agent-happiness]]).

### EffiBench-X: A Multi-Language Benchmark for Measuring Efficiency of LLM-Generated Code
Yuhao Qing, Boyu Zhu, Mingzhe Du, et al. — preprint, arXiv:2505.13004, submitted 19 May 2025. [arXiv:2505.13004](https://arxiv.org/abs/2505.13004).
Competitive-programming tasks in Python, C++, Java, JavaScript, Ruby and Go, with human-expert solutions as the efficiency baseline. Verbatim: "Even the most efficient LLM-generated solutions (Qwen3-32B) achieve only around 62% of human efficiency on average, with significant language-specific variations" ([arXiv:2505.13004](https://arxiv.org/abs/2505.13004)).
Mo relevance: functional correctness does not imply efficient code, and the gap is language-dependent. If Mo wants performance claims, they need their own measurement track — correctness benchmarks will not surface them ([[d28-nothing-final-until-measured]]).

### EffiPair: Improving the Efficiency of LLM-generated Code with Relative Contrastive Feedback
Samira Hajizadeh, Suman Jana — preprint, arXiv:2604.05137, submitted 6 Apr 2026. [arXiv:2604.05137](https://arxiv.org/abs/2604.05137).
Inference-time feedback that compares two structurally similar programs for the same task and summarizes the differences associated with better efficiency: up to 1.5x speedup with DeepSeek-Chat V3.2 versus generation without performance feedback, and more than 90% reduction in token usage compared to prior work ([arXiv:2604.05137](https://arxiv.org/abs/2604.05137)). Verbatim: "By replacing isolated scalar feedback with pairwise contrastive comparisons, EffiPair provides more direct guidance while reducing profiling and prompting overhead" ([arXiv:2604.05137](https://arxiv.org/abs/2604.05137)).
Mo relevance: pairwise contrast beats scalar scores as agent feedback. Mo's `--sim` runs could report "this version versus the last green version" rather than an absolute number.

### Chinese Language Is Not More Efficient Than English in Vibe Coding
Simiao Ren, Xingyu Shen, Yuchen Zhou, et al. — preprint, arXiv:2604.14210, submitted 6 Apr 2026. [arXiv:2604.14210](https://arxiv.org/abs/2604.14210).
Against a widely claimed "up to 40%" cost reduction from Chinese prompts, the study finds token cost depends on model architecture — GLM-5 consumes fewer tokens with Chinese, while MiniMax-2.7 shows 1.28x higher token costs for Chinese — and Chinese prompting generally produces lower success rates than English on SWE-bench Lite ([arXiv:2604.14210](https://arxiv.org/abs/2604.14210)).
Mo relevance: tokenizer-level intuitions about "more compact input is cheaper and better" do not survive measurement, and the effect flips across models. Any Mo syntax decision justified by token count must be measured across several tokenizers.

### Large Language Models for Code Generation from Multilingual Prompts
Saima Afrin, Alessandro Midolo, Camilo Escobar-Velásquez, et al. — preprint, arXiv:2607.14816, submitted 16 Jul 2026. [arXiv:2607.14816](https://arxiv.org/abs/2607.14816).
460 tasks (230 Python, 230 Java), three models (GPT-4o mini, DeepSeek, Claude), five prompt languages (English, Chinese, Hindi, Spanish, Italian): English prompts do not consistently produce the best results, the effect of prompt language depends on the programming language and the model, and generated code frequently mixes English with the prompt language in comments and string literals ([arXiv:2607.14816](https://arxiv.org/abs/2607.14816)).
Mo relevance: supports the general lesson that surface-level input choices interact with the target language. For Mo, the `never` sentences are natural language inside the program — this paper says that choice has measurable, model-dependent effects on the code around it.

### Token Economics for LLM Agents: A Dual-View Study from Computing and Economics
Yuxi Chen, Junming Chen, Chenyu He, et al. — preprint, arXiv:2605.09104, submitted 9 May 2026. [arXiv:2605.09104](https://arxiv.org/abs/2605.09104).
A survey with a four-level taxonomy (single agent, multi-agent systems, agent ecosystems, security); no empirical numbers on the page. Verbatim: "By unifying computer science and economics, we conceptualize tokens as production factors, exchange mediums, and units of account" ([arXiv:2605.09104](https://arxiv.org/abs/2605.09104)).
Mo relevance: framing only — verbosity is a cost with a unit, not an aesthetic complaint.

---

## B2. Cold start for a language with no corpus

### A Taxonomy of Programming Languages for Code Generation
Nishat Raihan, Christian Newman, Marcos Zampieri, et al. — preprint, arXiv:2604.00239, submitted 31 Mar 2026. [arXiv:2604.00239](https://arxiv.org/abs/2604.00239).
Verbatim: "To fill this gap, we present the first reproducible PL resource classification, grouping 646 languages into four tiers" ([arXiv:2604.00239](https://arxiv.org/abs/2604.00239)). Across seven major corpora, Tier-3 (High) languages are 1.9% of languages but 74.6% of all tokens, while Tier-0 (Scarce) languages are 71.7% of languages and 1.0% of tokens ([arXiv:2604.00239](https://arxiv.org/abs/2604.00239)).
Mo relevance: this quantifies Mo's starting position. Mo is Tier-0 by construction, in a distribution where 1.9% of languages hold three-quarters of the training signal. Any plan that depends on organic corpus growth is betting against that distribution ([[case-against-new-languages]]).

### A Survey on LLM-based Code Generation for Low-Resource and Domain-Specific Programming Languages
Sathvik Joel, Jie JW Wu, Fatemeh H. Fard — ACM TOSEM (accepted; year not stated on the page); preprint submitted 4 Oct 2024. [arXiv:2410.03981](https://arxiv.org/abs/2410.03981).
111 papers filtered from over 27,000 published studies (2020–2024), organizing four evaluation techniques and six groups of improvement methods; the survey notes that even Rust, with 3.5 million users, cannot fully exploit LLM capabilities, and that a standard evaluation approach and benchmark for low-resource languages is lacking ([arXiv:2410.03981](https://arxiv.org/abs/2410.03981)).
Mo relevance: if Rust counts as under-served at 3.5M users, Mo will not reach adequacy through adoption. The absence of a standard low-resource benchmark also means Mo has to build its own eval, which is what the control runs are ([[d28-nothing-final-until-measured]]).

### Knowledge Transfer from High-Resource to Low-Resource Programming Languages for Code LLMs (MultiPL-T)
Federico Cassano, John Gouwar, Francesca Lucchetti, et al. — preprint, arXiv:2308.09895, submitted 19 Aug 2023. [arXiv:2308.09895](https://arxiv.org/abs/2308.09895).
Two stages: synthesize tests for commented high-resource code and filter faulty tests and low-coverage code; then translate Python to the target low-resource language and validate the translation with the tests ([arXiv:2308.09895](https://arxiv.org/abs/2308.09895)). The method produces "tens of thousands of validated training items" for Julia, Lua, OCaml, R and Racket, and fine-tuned StarCoderBase and Code Llama models outperform other open Code LLMs on MultiPL-E, more efficiently than simply training longer ([arXiv:2308.09895](https://arxiv.org/abs/2308.09895)).
Mo relevance: the concrete cold-start recipe for Mo — translate validated Python/Rust into Mo and keep only translations whose tests pass. The validation gate is what makes it safe, and Mo's checker is stricter than the gate this paper used ([[d05-old-ideas-rethought-ai-first]]).

### Studying Code LLMs Across Low-Resource Parallel Languages (HPC-INSTRUCT / HPC-Coder-v2)
Aman Chaturvedi, Daniel Nichols, Siddharth Singh, et al. — venue not stated on the fetched PDF page (hosted as a 2025 ISC paper). [cs.umd.edu PDF](https://www.cs.umd.edu/~bhatele/pubs/pdf/2025/isc2025.pdf).
HPC-INSTRUCT holds more than 122k synthetic parallel-code instruction samples, built from 125k seed snippets collected from The Stack V2 with roughly 25,000 samples each in Python, C, Fortran and C++, 15,000 CUDA samples and smaller sets beyond ([cs.umd.edu PDF](https://www.cs.umd.edu/~bhatele/pubs/pdf/2025/isc2025.pdf)). Fine-tuned HPC-Coder-v2 models are reported as the best-performing open-source code LLMs for parallel code generation, approaching GPT-4 while using less memory and generating faster ([cs.umd.edu PDF](https://www.cs.umd.edu/~bhatele/pubs/pdf/2025/isc2025.pdf)).
Mo relevance: 122k synthetic samples were enough to move a niche domain to near-frontier quality. That is a tractable target for Mo — three orders of magnitude smaller than VeruSyn's 6.9M, and a plausible first corpus.

### Beyond Language Boundaries: Uncovering Programming Language Families for Code Language Models
Shangbo Yun, Xiaodong Gu, Jianghong Huang, et al. — FSE 2026 (accepted); preprint submitted 22 Dec 2025. [arXiv:2512.19509](https://arxiv.org/abs/2512.19509).
21 primary linguistic features (variable definition, control structures, method declarations and others) and semantically parallel snippets across 19 languages are embedded and hierarchically clustered into latent language families; the paper reports that transfer across related languages, proximity-guided curriculum learning, and centroid-based intermediary translation significantly improve multilingual code LLM performance on four code intelligence tasks ([arXiv:2512.19509](https://arxiv.org/abs/2512.19509)).
Mo relevance: syntactic proximity is a lever Mo can pull deliberately. Mo's Ruby-flavored, Elixir-shaped surface places it near well-resourced families, and "centroid-based intermediary translation" is an argument for a canonical Mo-from-Elixir/Ruby translation path ([[d07-elixir-flavored-functional]], [[d27-simple-and-elegant-like-ruby]]).

### Cross-lingual Transfer in Programming Languages: An Extensive Empirical Study
Razan Baltaji, Saurabh Pujar, Louis Mandel, et al. — Transactions on Machine Learning Research, 06/2025; preprint submitted 25 Oct 2023. [arXiv:2310.16937](https://arxiv.org/abs/2310.16937).
Transfer is evaluated across 10 to 41 programming languages on five tasks (code generation, clone detection, code repair, solution domain classification, error detection); cross-lingual transfer significantly outperforms zero-shot learning, effectiveness varies by source-target pair, and a performance-prediction model identifies good transfer sources from linguistic and dataset features ([arXiv:2310.16937](https://arxiv.org/abs/2310.16937)).
Mo relevance: the source language for Mo's synthetic corpus is a choosable parameter with a predictor attached. Judgment: pick sources by predicted transfer, not by what Mo's designers like writing.

### Synthetic Programming Elicitation for Text-to-Code in Very Low-Resource Programming and Formal Languages (SPEAC)
Federico Mora, Justin Wong, Haley Lepe, et al. — preprint, arXiv:2406.03636, submitted 5 Jun 2024, revised through 31 Oct 2024. [arXiv:2406.03636](https://arxiv.org/abs/2406.03636).
SPEAC designs an intermediate language that LLMs naturally know how to use, compiles it automatically to the very low-resource target, and uses compiler techniques to repair generated code that falls outside the intermediate language; in a UCLID5 case study it produces syntactically correct programs more often than retrieval and fine-tuning baselines without sacrificing semantic correctness (no percentages on the page) ([arXiv:2406.03636](https://arxiv.org/abs/2406.03636)).
Mo relevance: the honest alternative to fighting the corpus problem head-on — let agents write something they know and compile down. Note the tension with Mo's premise that the language itself is the interface ([[d01-agents-write-the-code]]).

### Metaprogramming for Unfamiliar Languages
Author list not shown on the page — preprint, arXiv:2606.10933, submitted 11 Jun 2026. [arXiv:2606.10933](https://arxiv.org/abs/2606.10933).
Across six agents and four esoteric languages, Claude Opus 4.6 and GPT-5.4 at extra-high reasoning effort spontaneously wrote Python metaprograms that emit the target language, and performance dropped substantially when that strategy was restricted ([arXiv:2606.10933](https://arxiv.org/abs/2606.10933)).
Mo relevance: agents will do SPEAC by themselves, unprompted, when a language is unfamiliar. Mo's evals must record whether the model wrote Mo or wrote a generator, or the cold-start numbers will be measuring the wrong thing.

### VeruSyn (also in A1), counted as cold-start evidence
Nongyu Di, Tianyu Chen, Shan Lu, et al. — preprint, arXiv:2602.04910. [arXiv:2602.04910](https://arxiv.org/abs/2602.04910).
6.9 million verified Rust programs with specifications and proofs synthesized from a seed set, used to fine-tune a 32B model ([arXiv:2602.04910](https://arxiv.org/abs/2602.04910)).
Mo relevance: an upper bound on the corpus scale a verification-heavy language needed, with every sample machine-verified. Mo can do the same because `mo check` is the filter.

---

## B3. Do strict languages reduce agent bugs?

### Type-Error Ablation and AI Coding Agents (also in A3)
Shriram Krishnamurthi, Matthew Flatt — preprint, arXiv:2606.01522. [arXiv:2606.01522](https://arxiv.org/abs/2606.01522).
The only study found that isolates a language feature against agent performance: detailed error messages improve an agent's ability to fix type errors, a type system appears to help more than test-suite failures alone, and a fixed type error usually implies passing semantic tests ([arXiv:2606.01522](https://arxiv.org/abs/2606.01522)).
Mo relevance: the closest direct support for "stricter language, better agent" — it supports the direction of Mo's bet without sizing it ([[d11-statically-typed]], [[d22-rust-plus-refinements-types]]).

### From Translation to Superset: Benchmark-Driven Evolution of a Production AI Agent from Rust to Python
Jinhua Wang, Biswa Sengupta — preprint, arXiv:2604.11518, submitted 13 Apr 2026. [arXiv:2604.11518](https://arxiv.org/abs/2604.11518).
The production Codex CLI Rust codebase (648K LOC, 65 crates) was translated to Python (41K LOC), a 15.9x reduction, with SWE-bench Verified 73.8% for Python versus 70.0% for Rust and Terminal-Bench 42.5% versus 47.5%, described as near-parity, plus 30 feature-flagged extensions ([arXiv:2604.11518](https://arxiv.org/abs/2604.11518)).
Mo relevance: the single most inconvenient result in this dossier for the strictness thesis. On real agentic tasks, the dynamically typed port matched or beat the Rust original at 1/16th the code size. Judgment: Mo's Round 3 LOC advantage (851 vs Go 1,387 vs Python 1,064) is the kind of measurement this paper says matters, and Mo should expect a Python-shaped competitor to be close on outcomes ([[case-against-new-languages]]).

### Perish or Flourish? A Holistic Evaluation of Large Language Models for Code Generation in Functional Programming
Nguyet-Anh H. Lang, Eric Lang, Thanh Le-Cong, et al. — preprint, arXiv:2601.02060, submitted 5 Jan 2026. [arXiv:2601.02060](https://arxiv.org/abs/2601.02060).
FPBench holds 721 tasks at three difficulty levels across Haskell, OCaml and Scala, evaluated with models from GPT-3.5 to GPT-5: performance improves substantially with model advancement, but error rates remain significantly higher in purely functional Haskell and OCaml than in hybrid Scala or imperative Java, and models frequently produce non-idiomatic functional code following imperative patterns; static-analysis feedback and hand-crafted instructions permit partial self-repair ([arXiv:2601.02060](https://arxiv.org/abs/2601.02060)).
Mo relevance: the most Mo-shaped warning in Cluster B. Mo is a pure-functional-flavored language with no `while`, and this measures a real penalty for exactly that shape — plus the specific failure of models writing imperative patterns in a functional language ([[d07-elixir-flavored-functional]], [[d10-immutable-by-default]], live dispute 2).

### Human-Written vs. AI-Generated Code: A Large-Scale Study of Defects, Vulnerabilities, and Complexity
Domenico Cotroneo, Cristina Improta, Pietro Liguori, et al. — ISSRE 2025 (36th IEEE International Symposium on Software Reliability Engineering); preprint submitted 29 Aug 2025. [arXiv:2508.21634](https://arxiv.org/abs/2508.21634).
Over 500k code samples in Python and Java compared across ChatGPT, DeepSeek-Coder and Qwen-Coder versus human code: AI code is generally simpler and more repetitive but more prone to unused constructs, hardcoded debugging artifacts, and high-risk security vulnerabilities, while human code shows greater structural complexity and more maintainability issues ([arXiv:2508.21634](https://arxiv.org/abs/2508.21634)).
Mo relevance: names the concrete failure classes a Mo linter should reject by law — unused constructs, leftover debugging, high-risk patterns — all of which are decidable statically ([[d04-style-rules-become-laws]]).

### Security and Quality in LLM-Generated Code: A Multi-Language, Multi-Model Analysis
Mohammed Kharma, Soohyeon Choi, Mohammed AlKhanafseh, et al. — IEEE Transactions on Dependable and Secure Computing (accepted; year not stated); preprint submitted 3 Feb 2025, revised 9 Mar 2026. [arXiv:2502.01853](https://arxiv.org/abs/2502.01853).
200 tasks in six categories: security effectiveness varies by language, many models fail to use modern security features such as those in Java 17, and outdated methods remain common, especially in C++ ([arXiv:2502.01853](https://arxiv.org/abs/2502.01853)).
Mo relevance: models default to the idioms that dominate their training data, including deprecated ones. For a new language, that means Mo must make the safe idiom the only idiom, because "the model will pick the modern API" is not supported ([[d15-effects-via-capabilities]], [[d30-supply-chain-security]]).

### Bugs in Large Language Models Generated Code: An Empirical Study
Florian Tambon, Arghavan Moradi Dakhel, Amin Nikanjam, et al. — preprint, arXiv:2403.08937, submitted 13 Mar 2024. [arXiv:2403.08937](https://arxiv.org/abs/2403.08937).
333 bugs from CodeGen, PanGu-Coder and Codex, organized into 10 patterns — misinterpretations, syntax error, silly mistake, prompt-biased code, missing corner case, wrong input type, hallucinated object, wrong attribute, incomplete generation, non-prompted consideration — validated by a survey of 34 practitioners ([arXiv:2403.08937](https://arxiv.org/abs/2403.08937)).
Mo relevance: a checklist to test Mo's laws against. Judgment: Mo's type system and contracts plausibly catch wrong input type, wrong attribute, hallucinated object and missing corner case; misinterpretation and prompt-biased code are untouched by any language feature.

### Do Code LLMs Do Static Analysis?
Chia-Yi Su, Collin McMillan — Empirical Software Engineering (accepted; year not stated); preprint submitted 17 May 2025, revised 26 Mar 2026. [arXiv:2505.12118](https://arxiv.org/abs/2505.12118).
Three static-analysis tasks (callgraph, AST, dataflow generation) alongside three code-intelligence tasks. Verbatim: "We found that LLMs show poor performance on static analysis tasks and that pretraining on the st[atic analysis tasks does not lead to better performance]" ([arXiv:2505.12118](https://arxiv.org/abs/2505.12118)), with the page also reporting that the two skill sets do not transfer in either direction.
Mo relevance: models do not internally do the analysis Mo's compiler does. This is the argument for handing analysis results to the model as diagnostics rather than assuming it reasons about dataflow ([[d03-source-carries-its-evidence]]).

### Rethinking Code Complexity Through the Lens of Large Language Models (LM-CC)
Chen Xie, Yuling Shi, Xiaodong Gu, et al. — preprint, arXiv:2602.07882, submitted 8 Feb 2026. [arXiv:2602.07882](https://arxiv.org/abs/2602.07882).
After controlling for code length, classical complexity metrics show no consistent correlation with LLM performance; LM-CC, built from entropy-based semantic units, a compositional hierarchy, and branching-induced divergence, correlates more strongly and lowering it improves task performance ([arXiv:2602.07882](https://arxiv.org/abs/2602.07882)). No numbers are stated on the page.
Mo relevance: bears directly on live dispute 1. Mo's shape laws are classical metrics (lines, params, nesting depth), and this paper says classical metrics do not predict model performance once length is controlled. If true, Mo's numeric laws are legibility rules for humans, not model-performance levers ([[q12-law-numbers]]).

---

## B4. Human review of agent-written code

### Experienced Open-Source Developer Productivity (METR RCT)
Joel Becker, Nate Rush, Beth Barnes, et al. — preprint; no arXiv ID or date stated on the page. [metr.org paper PDF](https://metr.org/Early_2025_AI_Experienced_OS_Devs_Study-paper.pdf).
16 developers with moderate AI experience completed 246 tasks in repositories they had worked on for an average of 5 years, averaging 23,000 GitHub stars; tasks took 2.0 hours on average. Allowing early-2025 AI tools increased completion time by 19%, against a forecast 24% reduction and a post-hoc self-estimate of a 20% reduction; the authors caution the result is setting-specific ([metr.org](https://metr.org/Early_2025_AI_Experienced_OS_Devs_Study-paper.pdf)).
Mo relevance: the strongest available evidence that developer intuition about agent workflows is unreliable in the wrong direction by roughly 40 percentage points. Any Mo claim about agent productivity needs a control run, not a feeling ([[d28-nothing-final-until-measured]]).

### Habituation at the Gate: Rising Approval and Declining Scrutiny in Human Review of AI Agent Code
Haoran Yu, Lifei Liu, Xiaochong Jiang, et al. — KDD 2026 Workshop on Agentic Software Engineering (SE 3.0); preprint submitted 27 Jun 2026. [arXiv:2606.22721](https://arxiv.org/abs/2606.22721).
400 repeat reviewers, 11,429 reviews, seven-month window: population-level approval rises from 30.1% early to 36.8% late (Wilcoxon signed-rank \(p < 10^{-6}\)), with a cumulative +14.5 percentage-point gap across ten within-reviewer experience deciles; meanwhile review latency rises 3.5x and inline comments fall 22% — a pattern the authors read as reflexive habituation under growing workload rather than rational trust calibration ([arXiv:2606.22721](https://arxiv.org/abs/2606.22721)).
Mo relevance: the empirical case for Mo's review economics. Human scrutiny decays with exposure, so Mo must minimize what humans must read and make the rest mechanically enforced — which is precisely the spec-altitude argument ([[d02-spec-altitude]], [[d20-human-pulled-in-when-shape-changes]]).

### Trust-Calibrated Code Review: A Participatory Design Study of Review Workflows for LLM-Generated Multi-File Changes
Lo Gullstrand Heander, Agnia Sergeyuk, Ilya Zakharov, et al. — submitted to ESEM SEIP 2026; preprint submitted 1 Jun 2026. [arXiv:2606.01969](https://arxiv.org/abs/2606.01969).
N = 17 practitioners in the Discover phase (7 returning for Develop), validated with N = 43: a three-level workflow (overview, file analysis, code snippet) and seven design constructs — chunk, risk-per-line, risk-per-file, judge, walk-through, zooming in/out, security cage — all scoring above the neutral midpoint (level means 3.50–3.91 on a five-point scale); 63% of respondents expected reduced overall review effort and 52% expected reduced per-change effort ([arXiv:2606.01969](https://arxiv.org/abs/2606.01969)). The framing claim is that reviewing LLM-generated multi-file changes is a trust-calibration problem rather than a diffing problem ([arXiv:2606.01969](https://arxiv.org/abs/2606.01969)).
Mo relevance: practitioners asked for risk signals at the granularity where they allocate attention. Mo can emit those signals from the language itself — capability sets touched, contracts changed, declaration IDs affected — which no diff tool can synthesize reliably ([[d03-source-carries-its-evidence]], [[d29-edit-by-declaration-id]]).

### Same Scrutiny, More Time: Eye Tracking Insights into Reviewing LLM-Labelled Code
Ranim Khojah, Francisco Gomes de Oliveira Neto, Mazen Mohamad, et al. — ASE 2026 (41st IEEE/ACM International Conference on Automated Software Engineering); preprint submitted 25 Jun 2026. [arXiv:2606.26505](https://arxiv.org/abs/2606.26505).
Labelling code as LLM-generated did not change review thoroughness but did increase fixation time on the labelled code; reviewers reported adapting strategies (assessing logical correctness, using the prompt to guide review), revealing a gap between stated intentions and measured behaviour ([arXiv:2606.26505](https://arxiv.org/abs/2606.26505)). No participant counts or percentages are stated on the abstract page.
Mo relevance: telling humans "an agent wrote this" costs time without buying rigor. Mo's answer has to be structural — put the risk in the contract diff — not a warning label.

### A Study on Developer Behaviors for Validating and Repairing LLM-Generated Code Using Eye Tracking and IDE Actions
Ningzhi Tang, Meng Chen, Zheng Ning, et al. — preprint, arXiv:2405.16081, submitted 25 May 2024. [arXiv:2405.16081](https://arxiv.org/abs/2405.16081).
28 participants validated and repaired Copilot-generated code in three projects, split into provenance-informed and uninformed groups. Verbatim: "Being aware of the code's provenance led to improved performance, increased search efforts, more frequent Copilot usage, and higher cognitive workload" ([arXiv:2405.16081](https://arxiv.org/abs/2405.16081)).
Mo relevance: read next to the ASE 2026 eye-tracking result, the literature disagrees on whether provenance awareness helps. Judgment: treat "should Mo mark agent-authored declarations?" as an open, testable question rather than a settled one.

### Evaluating the Impact of Explainable AI on Trust in AI-Assisted Code Review
Zhenhan Gao, Marvin Muñoz Barón, Umm-e Habiba, et al. — PACMSE Vol. 3, No. ISSTA, Article ISSTA093 (ISSTA 2026); preprint submitted 27 Jul 2026. [arXiv:2607.24601](https://arxiv.org/abs/2607.24601).
A within-subjects study with 34 participants over three LLM-based review systems and three explanation conditions: detailed explanation plus feedback yields the highest perceived trust (M = 3.99/5), feedback-only yields the highest agreement with the AI recommendation (89.22%), and explanation level does not significantly affect review time ([arXiv:2607.24601](https://arxiv.org/abs/2607.24601)).
Mo relevance: more explanation raised trust but not agreement. Judgment: for Mo diagnostics aimed at humans, the `why` field buys confidence; the `fix` field is what changes behaviour.

### Code Readability in the Age of Large Language Models: An Industrial Case Study from Atlassian
Wannita Takerngsaksiri, Chakkrit Tantithamthavorn, Micheal Fu, et al. — accepted at ICSME (year not stated on the page); preprint submitted 20 Jan 2025, current version 18 Jul 2025. [arXiv:2501.11264](https://arxiv.org/abs/2501.11264).
A practitioner survey plus an evaluation of code generated by Atlassian's HULA agent framework against human-written code in real scenarios: readability remains a critical concern, and HULA's generated code is comparable in readability to human-written code, which the authors read as supporting appropriate trust ([arXiv:2501.11264](https://arxiv.org/abs/2501.11264)). No readability scores are stated on the page.
Mo relevance: agent-written code in production is already at human readability parity in at least one large shop — so Mo's readability laws cannot be justified by "agent code is unreadable." They have to be justified by review cost at scale ([[q12-law-numbers]]).

### The Readability Spectrum: Patterns, Issues, and Prompt Effects in LLM-Generated Code
Hengzhi Ye, Fengyuan Ran, Weiwei Xu, et al. — preprint, arXiv:2605.13280, submitted 13 May 2026. [arXiv:2605.13280](https://arxiv.org/abs/2605.13280).
5,869 scenarios drawn from World of Code and LeetCode. Verbatim: "We find that current LLMs produce code with overall readability comparable to human-written code, but displaying distinct readability issue patterns" ([arXiv:2605.13280](https://arxiv.org/abs/2605.13280)); function signatures, constraints and style descriptions are the most influential prompt dimensions, while the overall impact of prompt design remains limited ([arXiv:2605.13280](https://arxiv.org/abs/2605.13280)).
Mo relevance: the three most influential prompt dimensions are exactly Mo's signature-plus-contract surface. That is favorable evidence for Mo's ordering — but "impact of prompt design remains limited" caps how much to claim ([[d02-spec-altitude]]).

---

## B5. Style constraints and their measured effects

### Beyond the Prompt: An Empirical Study of Cursor Rules
Shaokang Jiang, Daye Nam — MSR 2026 (to appear); preprint submitted 21 Dec 2025. [arXiv:2512.18925](https://arxiv.org/abs/2512.18925).
A qualitative study of 401 open-source repositories containing cursor rules yields a taxonomy of five themes: Conventions, Guidelines, Project Information, LLM Directives, Examples ([arXiv:2512.18925](https://arxiv.org/abs/2512.18925)). Verbatim: "While Large Language Models (LLMs) have demonstrated remarkable capabilities, research shows that their effectiveness depends not only on explicit prompts but also on the broader context provided" ([arXiv:2512.18925](https://arxiv.org/abs/2512.18925)). No effectiveness measurements are reported.
Mo relevance: the market has already voted for machine-readable project constraints, and 401 repos show what people put in them. Mo's laws are the compiler-enforced version of the same content — with the advantage that they cannot be ignored mid-session ([[d04-style-rules-become-laws]]).

### Show and Tell: Prompt Strategies for Style Control in Multi-Turn LLM Code Generation
Jeremiah Bohr — preprint, arXiv:2511.13972, submitted 17 Nov 2025. [arXiv:2511.13972](https://arxiv.org/abs/2511.13972).
A paired two-turn protocol with four conditions over N = 160 paired programs: combined instruction-plus-example prompts give the strongest initial compression and the greatest expansion discipline; instructions alone have large initial effects with moderate discipline; examples alone have modest initial effects and no expansion discipline ([arXiv:2511.13972](https://arxiv.org/abs/2511.13972)). No percentages are stated on the page.
Mo relevance: prompt-level style control decays as code grows — "no expansion discipline" for examples alone. That is the decay Mo's compiler-enforced laws exist to prevent, and this paper is the measurement of the failure mode Mo is replacing.

### Beyond Functional Correctness: Investigating Coding Style Inconsistencies in Large Language Models
Yanlin Wang, Tianyue Jiang, Mingwei Liu, et al. — preprint, arXiv:2407.00456, submitted 29 Jun 2024, revised 21 Jun 2025. [arXiv:2407.00456](https://arxiv.org/abs/2407.00456).
The paper builds a taxonomy of coding-style inconsistencies between Code LLMs and human developers, compares generated and human code on readability, conciseness and robustness, examines causes, and proposes mitigations ([arXiv:2407.00456](https://arxiv.org/abs/2407.00456)). No quantitative results are stated on the abstract page.
Mo relevance: establishes that models have a style of their own that diverges from human convention. For Mo, the design question is whether the laws should encode human convention or model convention — this paper says they differ ([[d26-developer-and-agent-happiness]]).

### Guidelines to Prompt Large Language Models for Code Generation: An Empirical Characterization
Alessandro Midolo, Alessandro Giagnorio, Fiorella Zampetti, et al. — preprint, arXiv:2601.13118, submitted 19 Jan 2026. [arXiv:2601.13118](https://arxiv.org/abs/2601.13118).
Ten prompt-improvement guidelines, assessed with 50 practitioners, covering better specification of inputs and outputs, pre- and post-conditions, examples, detail types, and disambiguation ([arXiv:2601.13118](https://arxiv.org/abs/2601.13118)). No effect sizes on the page.
Mo relevance: independent practitioner-derived agreement that pre/post-conditions and examples belong in the task description. Mo makes them syntax instead of prompt hygiene ([[d19-negative-space-is-the-contract]]).

### When Prompt Under-Specification Improves Code Correctness
Amal Akli, Mike Papadakis, Maxime Cordy, et al. — preprint, arXiv:2604.24712, submitted 27 Apr 2026. [arXiv:2604.24712](https://arxiv.org/abs/2604.24712).
Across 10 models, structurally rich task descriptions (LiveCodeBench) show near-zero net effect from under-specification mutations, while HumanEval-style prompts degrade; sometimes mutations improve correctness by disrupting misleading lexical or structural cues such as over-fitted terminology, misleading constraints, and spurious identifier triggers ([arXiv:2604.24712](https://arxiv.org/abs/2604.24712)). Verbatim: "Overall, our study shows that structurally rich task descriptions can substantially mitigate the negative effects of un[der-specification]" ([arXiv:2604.24712](https://arxiv.org/abs/2604.24712)).
Mo relevance: structure in the task statement buys robustness — and a specific caution that constraints can mislead. Mo's contracts are structure, but a wrong `requires` will steer a model wrong with full confidence.

### Benchmarking the Titans: A Multi-Dimensional Empirical Evaluation of LLM Code Generation Quality in the .NET Ecosystem
Seyed Mohammad Mahdi Ghalandarian, Majid Bazargani, Masoumeh Taromirad — Second Workshop on Large Language Models for Generative Software Engineering (LLM4SE 2026), co-located with STAF 2026, Rennes, 29 Jun – 3 Jul 2026; preprint submitted 23 Aug 2026. [arXiv:2608.22529](https://arxiv.org/abs/2608.22529).
85 algorithmic C# tasks derived from HumanEval, 340 generated solutions, four models (GPT, Gemini, Claude, Grok), three independent dimensions (functional correctness, static code quality, runtime efficiency): correctness and quality correlate at Pearson r = 0.075, so pass@k rankings systematically misrepresent the full performance profile ([arXiv:2608.22529](https://arxiv.org/abs/2608.22529)).
Mo relevance: r = 0.075 is the number to quote whenever someone argues Mo's style laws are redundant with correctness. Passing tests carries almost no information about the quality attributes Mo's laws target ([[d04-style-rules-become-laws]], [[q12-law-numbers]]).

### LM-CC (also in B3) and The Hidden Cost of Readability (also in B1), counted as shape-law evidence
[arXiv:2602.07882](https://arxiv.org/abs/2602.07882); [arXiv:2508.13666](https://arxiv.org/abs/2508.13666).
Classical metrics show no consistent correlation with LLM performance after controlling for length, while the LLM-oriented LM-CC metric does, and lowering LM-CC improves performance ([arXiv:2602.07882](https://arxiv.org/abs/2602.07882)). Prompting and fine-tuning reduced generated code length by up to 36.1% without compromising correctness ([arXiv:2508.13666](https://arxiv.org/abs/2508.13666)).
Mo relevance: length is the one Mo-style law with supporting evidence. If a shape law is meant to help the model, express it in LM-CC terms (compositional depth, branching divergence) rather than line counts ([[q12-law-numbers]], live dispute 1).

---

## What this changes for Mo, ranked by strength of evidence against a live Mo dispute

1. Vacuous contracts and vacuous tests are a measured phenomenon, and the fix is to generate the fault first. Meta's ACH reached a 73% engineer acceptance rate on mutation-guided tests with mutant precision rising 0.79 → 0.95 ([arXiv:2501.12862](https://arxiv.org/abs/2501.12862)), and models cannot be trusted to judge whether a test kills a mutant: 10.20% verification accuracy, dropping from 71.04% to 39.81% when mutant and test live in different files ([arXiv:2605.22175](https://arxiv.org/abs/2605.22175)). Mo should execute fault injection rather than declare it, and score vacuity as HierSVA does ([arXiv:2606.13706](https://arxiv.org/abs/2606.13706)). This resolves live dispute 3 in favor of the stricter option.

2. Contracts are not a redundant restatement of tests. Five open code LLMs achieved 75–82% pass@1 with 0% contract satisfaction, rising only to 23–41% when contracts were stated explicitly in the prompt ([arXiv:2510.12047](https://arxiv.org/abs/2510.12047)); correctness and quality correlate at r = 0.075 on an independent C# evaluation ([arXiv:2608.22529](https://arxiv.org/abs/2608.22529)); verification success and runtime test performance measure different things ([arXiv:2606.32007](https://arxiv.org/abs/2606.32007)). Mo's `requires`/`ensures`/`never` layer earns its cost.

3. Mo's shape numbers, as currently expressed, have evidence against them. Classical complexity metrics show no consistent correlation with LLM performance after controlling for length ([arXiv:2602.07882](https://arxiv.org/abs/2602.07882)), and agent-written code is already at human readability parity in industry ([arXiv:2501.11264](https://arxiv.org/abs/2501.11264); [arXiv:2605.13280](https://arxiv.org/abs/2605.13280)). Length itself survives — up to 36.1% shorter output with no correctness loss ([arXiv:2508.13666](https://arxiv.org/abs/2508.13666)). Judgment: keep the length law, justify nesting and parameter caps as human-review economics, and consider restating them in LM-CC terms. This pushes live dispute 1 toward "laws are for humans."

4. Diagnostics are an interface with a measured exchange rate for agents, and a null result for humans. Localization-quality diagnostics bought 11–21 percentage points of LLM repair success ([arXiv:2607.02748](https://arxiv.org/abs/2607.02748)), and detail level measurably helps agents fix type errors ([arXiv:2606.01522](https://arxiv.org/abs/2606.01522)) — while LLM-rewritten messages beat conventional ones in only 1 of 6 tasks for students ([arXiv:2409.18661](https://arxiv.org/abs/2409.18661)) and produced no objective gains in a second study ([arXiv:2608.20896](https://arxiv.org/abs/2608.20896)). Mo's MO-coded `what`/`why`/`fix` design is right for agents; its human payoff should not be assumed.

5. The verifier's automation level dominates the model. 82% Dafny / 44% Verus / 27% Lean on identical work ([arXiv:2509.22908](https://arxiv.org/abs/2509.22908)), reproduced at 40.3% / 24.7% / 7.8% with the spec held fixed ([arXiv:2602.09464](https://arxiv.org/abs/2602.09464)), and 4.9% proof success at the frontier on VERINA ([arXiv:2505.23135](https://arxiv.org/abs/2505.23135)). Keeping SMT-shaped contracts in `mo check` and interactive proving in a separate tool is the empirically supported split.

6. Human review scrutiny decays, so Mo's review surface must be small and mechanical. Approval rose 30.1% → 36.8% over seven months with a +14.5 pp within-reviewer gradient, review latency up 3.5x and inline comments down 22% ([arXiv:2606.22721](https://arxiv.org/abs/2606.22721)); practitioners want risk signals at attention granularity ([arXiv:2606.01969](https://arxiv.org/abs/2606.01969)); labelling code as AI-written adds time without adding thoroughness ([arXiv:2606.26505](https://arxiv.org/abs/2606.26505)). Spec-altitude review is the right target; a warning label is not.

7. Edit-by-declaration-ID now has direct measured support. AST-entity edits gave +1.2–5.0% pass@1 with 12–38% fewer output tokens and cut GPT-5-nano's empty-patch rate from 46.6% to 7.2% ([arXiv:2604.05407](https://arxiv.org/abs/2604.05407)); edit success is separately trainable, +12.5 pp with GRPO ([arXiv:2604.26102](https://arxiv.org/abs/2604.26102)); agents already locate the right files 72–81% of the time even when they fail ([arXiv:2511.00197](https://arxiv.org/abs/2511.00197)). The one caveat: adaptive choice between diff and whole-file rewriting cut latency and cost by over 30% ([arXiv:2604.27296](https://arxiv.org/abs/2604.27296)), so the ID channel should not be the only channel.

8. Composition, not per-function verification, is the frontier — and Mo's small-function laws point straight at it. Frontier models exceed 99% well-formedness and above 58% end-to-end verification on single-function Dafny benchmarks yet reach near-zero on compositional DafnyCOMP ([ICLR 2026](https://iclr.cc/virtual/2026/poster/10006597)), and repository-level Verus proof success was 4.5% for prompting versus 51.0% with dependency-aware retrieval ([arXiv:2605.03822](https://arxiv.org/abs/2605.03822)). Mo needs a module-level contract composition story, and the dependency closure of a declaration is the right context unit ([arXiv:2602.18307](https://arxiv.org/abs/2602.18307)).

9. The banned `while` loop is not required for verifiability. A reasoning-model plus Z3 loop covered 133 of 133 invariant tasks with 1–2 proposals in 14–55 s ([arXiv:2508.00419](https://arxiv.org/abs/2508.00419)). Judgment: this weakens the verification argument in live dispute 2 and leaves the legibility argument standing on its own.

10. Cold start is solvable but only with machine-verified synthetic data, and agents will route around an unfamiliar language if allowed. Tier-0 languages are 71.7% of languages and 1.0% of tokens ([arXiv:2604.00239](https://arxiv.org/abs/2604.00239)); validated translation produced tens of thousands of usable items for five low-resource languages ([arXiv:2308.09895](https://arxiv.org/abs/2308.09895)); 122k synthetic samples reached near-GPT-4 quality in a niche domain ([cs.umd.edu PDF](https://www.cs.umd.edu/~bhatele/pubs/pdf/2025/isc2025.pdf)); 6.9M were used for Verus proofs ([arXiv:2602.04910](https://arxiv.org/abs/2602.04910)); and agents spontaneously wrote Python metaprograms rather than the unfamiliar language ([arXiv:2606.10933](https://arxiv.org/abs/2606.10933)).

11. Strictness has thin, mixed support as a productivity claim. The one direct language-feature ablation favors types over tests as agent feedback ([arXiv:2606.01522](https://arxiv.org/abs/2606.01522)), but a production Rust→Python port reached near-parity at 1/16th the LOC (73.8% vs 70.0% SWE-bench Verified; 42.5% vs 47.5% Terminal-Bench) ([arXiv:2604.11518](https://arxiv.org/abs/2604.11518)), and purely functional languages showed significantly higher error rates than hybrid or imperative ones on 721 FPBench tasks ([arXiv:2601.02060](https://arxiv.org/abs/2601.02060)). Judgment: Mo should argue strictness from verifiability and review cost, not from raw agent success rates, because the raw-rate evidence does not support it yet.

12. Syntax-error loops are the cheapest thing to eliminate, and there is a known mechanism. Grammar-constrained decoding removed 96.07% of syntax errors in Python and Go ([arXiv:2403.01632](https://arxiv.org/abs/2403.01632)), type-constrained decoding cut compile errors by more than half ([arXiv:2504.09246](https://arxiv.org/abs/2504.09246)), grammar-prompting needs no decoder integration ([arXiv:2305.19234](https://arxiv.org/abs/2305.19234)), and precompute is 17.71x cheaper than it was ([arXiv:2502.05111](https://arxiv.org/abs/2502.05111)). Mo's Round 3 loop count was dominated by syntax diagnostics; shipping a grammar and a mask store is the highest-leverage cold-start action. The caution: constrained decoding can degrade semantic fidelity ([arXiv:2501.10868](https://arxiv.org/abs/2501.10868)).

---

## Gaps: what nobody has measured

1. No study isolates a single language feature against agent end-to-end success on multi-file tasks. The type-error ablation is the closest and it is single-error, single-file ([arXiv:2606.01522](https://arxiv.org/abs/2606.01522)). Mo's control runs are, as far as this search found, closer to a controlled comparison than anything published — provided the harness discipline that [danluu.com/pl-tokens](https://danluu.com/pl-tokens/) shows is easy to lose.

2. Nobody has measured the effect of a function-length, nesting-depth, or parameter-count cap on model correctness or repair-loop length. The nearest evidence is negative-by-implication (classical metrics do not predict LLM performance after controlling length, [arXiv:2602.07882](https://arxiv.org/abs/2602.07882)) and one positive on length alone ([arXiv:2508.13666](https://arxiv.org/abs/2508.13666)). This is a Mo-shaped experiment nobody has run.

3. No published number exists for how many loops-to-green a language costs an agent. Every benchmark reports pass@k or resolve rate; the closest proxies are "1–2 proposals per invariant" ([arXiv:2508.00419](https://arxiv.org/abs/2508.00419)), "half in under 3 LLM calls" ([arXiv:2409.13082](https://arxiv.org/abs/2409.13082)), and ten iterations to drive static-analysis violations to 11–13% ([arXiv:2508.14419](https://arxiv.org/abs/2508.14419)). Mo's Round 3 loop counts are a metric the field does not report.

4. Contract quality has no accepted metric. HierSVA scores vacuity for hardware assertions ([arXiv:2606.13706](https://arxiv.org/abs/2606.13706)) and Verus-SpecGym catalogues three spec failure modes ([arXiv:2605.26457](https://arxiv.org/abs/2605.26457)), but there is no software-side equivalent of mutation score for contracts. Mo could define one: percentage of injected faults excluded by the contract alone.

5. The effect of diagnostic wording on agent loop count is measured exactly once, on eBPF verifier logs ([arXiv:2607.02748](https://arxiv.org/abs/2607.02748)). No study varies error-code stability, `why` text, or suggested-fix presence independently. Mo can run this ablation on its own diagnostics cheaply.

6. Nobody has measured whether machine-checkable project rules (Mo's laws) outperform prompt-level rules (cursor rules) on the same tasks. The cursor-rules study is purely descriptive over 401 repositories ([arXiv:2512.18925](https://arxiv.org/abs/2512.18925)), and the style-control study measures only prompt mechanisms ([arXiv:2511.13972](https://arxiv.org/abs/2511.13972)).

7. No evidence found on whether capability- or effect-annotated code is easier or harder for agents to write than ambient-effect code. Searches in this session surfaced no empirical study on effect systems and LLMs; the nearest adjacent evidence is that models default to familiar, sometimes outdated APIs ([arXiv:2502.01853](https://arxiv.org/abs/2502.01853)). This is an open question directly under [[d15-effects-via-capabilities]] and [[d31-effects-never-hide-in-a-value]].

8. No study measures whether marking declarations as agent-authored changes review outcomes, and the two eye-tracking studies point in opposite directions on provenance awareness ([arXiv:2606.26505](https://arxiv.org/abs/2606.26505) versus [arXiv:2405.16081](https://arxiv.org/abs/2405.16081)).

9. Nothing found measures supply-chain behaviour of agents — whether an agent picks a smaller, auditable dependency when the language makes provenance visible. The token-economics survey lists security as a taxonomy level without empirical results ([arXiv:2605.09104](https://arxiv.org/abs/2605.09104)). Open under [[d30-supply-chain-security]] and [[q17-package-management-and-supply-chain]].

10. Cross-tokenizer stability of a language's syntax has not been studied for any new language. The prompt-language work shows the direction of token-cost effects flips between models ([arXiv:2604.14210](https://arxiv.org/abs/2604.14210)), which implies Mo's syntax should be evaluated on several tokenizers before any compactness claim is made.

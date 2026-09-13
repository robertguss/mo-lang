---
tool: Perplexity
prompt: prompts-mo-parallel-tracks / prompt 1 (empirical validation)
run: 2026-09-13
run_by: Claude (via Perplexity session 4a4e7abb)
session_url: https://www.perplexity.ai/computer/tasks/4a4e7abb-f42a-4934-8384-ed09992e3864
sha256: d5f4e6aac0782a17a19f15e7013d6c732528e7e80bd3f96182900b6215997a6e
---
# Empirical Validation of a New Programming Language for AI Agents

A research report on how to design a rigorous, publication-quality evaluation program for a general-purpose language built primarily to be authored by AI coding agents. The report treats the null hypothesis — that the same guarantees can be bolted onto Go, TypeScript, Python, or Rust and match the new language once training-data gravity is accounted for — as the working default, and looks for the evidence that would overturn it.

## Executive Framing

Two empirical literatures dominate this question. Programming-language evaluation is a field where "practical effect size is exceedingly small" is a common outcome once a study is reanalyzed by an independent group ([Berger et al., ACM TOPLAS 2019](https://dl.acm.org/doi/fullHtml/10.1145/3340571)). AI code-generation benchmarking has, in the last twelve months, produced two large embarrassments: a 138-sample audit of SWE-bench Verified found that **59.4% of problems had material test or description defects** and that "all frontier models reproduced gold patches on many problems," which OpenAI treats as direct contamination evidence ([OpenAI, "Why we no longer evaluate SWE-bench Verified," 2025](https://openai.com/index/why-we-no-longer-evaluate-swe-bench-verified/)); and the "No Resource, No Benchmarks" study reports that today's frontier models score an **average pass@1 of 9%** on MoonBit and Gleam versus **79% on Python**, and **0–1% on hard tasks** for the same no-resource languages ([Giagnorio et al., arXiv:2606.16827](https://arxiv.org/html/2606.16827v1)).

The design implication is bracing. A new agent-first language starts at Gleam-like territory on today's benchmarks. Any evaluation that treats "pass@k on public tasks" as evidence, without contamination audits, adversarial task sets, blinded independent grading, and pre-registered effect thresholds, will be indistinguishable from the naive PL comparisons that the reanalysis literature has systematically demolished. The good news is that the same literature tells you exactly what a credible design looks like: it is the intersection of Berger et al.'s reproduction protocol, Pineau et al.'s ML reproducibility checklist, and the Csmith → CompCert model of adversarial validation.

---

## Part 1 — How New Programming Languages Have Historically Been Evaluated

### The canonical multi-language defect study, and its reproduction

The most-cited empirical PL study of the last decade is **Ray, Posnett, Filkov & Devanbu, "A Large-Scale Study of Programming Languages and Code Quality in GitHub," FSE 2014**. The design used **728 GitHub projects, 17 languages, 63M SLOC, ~1.5M commits, and 29K authors**. Bug-fixing commits were labeled by keyword search on commit messages, and a negative-binomial regression modeled bug-commit counts as a function of language, controlling for age, size, and team size. Eleven of seventeen languages had a statistically significant association with defects; the authors were explicit that the effect was small ([Ray et al., FSE 2014 PDF](https://baishakhir.github.io/uploads/fse2014-lang_study.pdf); [ACM DOI](https://dl.acm.org/doi/10.1145/2635868.2635922)).

The reproduction study is now the more important paper. **Berger, Hollenbeck, Maj, Vitek & Vitek, "On the Impact of Programming Languages on Code Quality: A Reproduction Study," ACM TOPLAS / CACM 2019** re-ran the analysis with methodological corrections. They found **~106K commits (19.95%) missing from the original commits table**; a **36% false-positive rate and 11% false-negative rate on the keyword-based bug labels** when 10 developers hand-validated 400 commits; and **16 of 41 "TypeScript" repositories were not TypeScript**. After cleaning, the number of languages with a significant defect association shrank from **11 to 4**, and even those effects were "exceedingly small" and driven by a handful of projects ([Berger et al., ACM TOPLAS 2019](https://dl.acm.org/doi/fullHtml/10.1145/3340571); [CACM version](https://cacm.acm.org/research/on-the-impact-of-programming-languages-on-code-quality/)).

For a new language, this history sets a very specific bar: **any PL-quality claim must survive Berger et al.'s reproduction protocol — human-validated bug labels, language-classification audits, missing-data audits, pre-registered controls, and published reanalysis scripts.**

### The other multi-language observational work

**Meyerovich & Rabkin, "Empirical Analysis of Programming Language Adoption," OOPSLA 2013** combined 213,471 SourceForge projects, 13,271 respondents to the Hammer Principle survey, 1,679 Slashdot commenters, and 1,142 MOOC students — the largest observational PL-adoption study to date. Two numbers matter for anyone selling a safety-oriented language: **only 8% of respondents named bug-finding as the most valuable aspect of static typing**, while **33% endorsed unit testing over types for that purpose**, and the top-cited factor in choosing a language was **library availability**, not correctness or performance ([Meyerovich & Rabkin, OOPSLA 2013 PDF](https://lmeyerov.github.io/projects/socioplt/papers/oopsla2013.pdf)).

**Nanz & Furia, "A Comparative Study of Programming Languages in Rosetta Code," ICSE 2015** analyzed **7,087 programs solving 745 tasks across 8 languages**. Functional and scripting languages produced more concise code; strongly typed compiled languages were less prone to runtime failure; effect sizes were modest and highly task-dependent ([arXiv:1409.0252](https://arxiv.org/abs/1409.0252)).

**Prechelt's 2000 IEEE Computer study** remains one of the few PL comparisons with practically significant effects. Eighty implementations of the same "phonecode" task by 74 different programmers across 7 languages produced a median working time of **3.1 hours for scripting languages versus 10.0 hours for compiled languages** — a ~3× productivity delta ([Prechelt, IEEE Computer 2000](https://page.mi.fu-berlin.de/prechelt/Biblio/jccpprt_computer2000.pdf)). Dan Luu's survey of the PL empirical literature identifies Prechelt, Endrikat et al. on typed API use, and Cooley on VHDL versus Verilog as the exceptions to the "small effect" pattern; almost everything else — including the Ray/Berger corpus — has effect sizes small enough to be swamped by team, task, and process variance ([Luu, "Empirical evidence on programming languages"](https://danluu.com/empirical-pl/)).

### Static typing: the small effect, quantified

**Gao, Bird & Barr, "To Type or Not to Type: Quantifying Detectable Bugs in JavaScript," ICSE 2017** took **400 randomly sampled JavaScript bug fixes** from public GitHub, had annotators reintroduce the bug, and ran TypeScript and Flow to see how many would have been caught. Result: **~15% of the sampled bugs** would have been detected statically ([ACM DOI 10.1109/ICSE.2017.75](https://dl.acm.org/doi/10.1109/ICSE.2017.75)). This is the "15% figure" widely quoted; the authors emphasize it is an upper bound.

**Bogner & Merkel, "On the Impact of TypeScript in a Large-Scale Empirical Study" (arXiv 2203.11115, 2022)** studied **604 GitHub projects (299 JavaScript, 305 TypeScript), 16M LoC, 575,699 commits, and 214,075 issues**. TypeScript projects had **12 fewer code smells per kLOC** than JavaScript (Cohen's d = 0.671) and lower cognitive complexity, but the **share of bug-fix commits was higher in TS — 0.206 vs 0.126, roughly 60% more** — and there was **no significant difference in bug-resolution time** ([arXiv:2203.11115](https://arxiv.org/abs/2203.11115)). The "types reduce bugs" claim is genuinely contested at the population level, even where it survives at the individual-bug level.

### Rust: the strongest real-world defect data

Because a safety-oriented language must position itself against Rust's rollouts, the Android and Chromium numbers are the calibration reference.

Google's Android security team reports that memory-safety vulnerabilities **fell from 76% of total Android vulnerabilities in 2019 to 24% in 2024**, well below the industry norm of ~70%, and that absolute counts fell from ~223 to under 50 while the codebase grew — an ~84% reduction over five years ([Google Security Blog, Sept 25, 2024](https://security.googleblog.com/2024/09/eliminating-memory-safety-vulnerabilities-Android.html); corroborated by [BleepingComputer](https://www.bleepingcomputer.com/news/security/google-sees-68-percent-drop-in-android-memory-safety-flaws-over-5-years/) and [The Register](https://www.theregister.com/2024/09/25/google_rust_safe_code_android/)). The follow-up "Rust in Android: move fast and fix things" (2025) reports Rust vulnerability density at **~0.2 per MLOC vs C/C++ at ~1000 per MLOC**, a claimed >1000× reduction in memory-safety defect density; **~4× lower rollback rate** for medium/large Rust changes; and **~20% fewer code-review revisions and ~25% less reviewer time** ([blog.google, 2025](https://blog.google/technology/safety-security/rust-in-android-move-fast-fix-things/)).

The Chromium security team reports **912 high or critical severity security bugs since 2015, ~70% memory safety issues, ~50% use-after-free** ([Chromium Memory Safety](https://www.chromium.org/Home/chromium-security/memory-safety/)). This is the empirical baseline the Rust rollouts replace, and it is the model a Mo-scale evaluation should imitate: eliminate a well-defined defect class, measure the density before and after, publish six-year time series rather than snapshots.

### Elixir, Erlang, WhatsApp — the concurrency case

WhatsApp's engineers reported a peak of **2,277,845 concurrent connections per server** on FreeBSD + Erlang/OTP, 465M MAU, hundreds of billions of daily messages, and **~32 engineers** to build it ([Reed, Erlang Factory 2012](https://www.erlang-factory.com/upload/presentations/558/efsf2012-whatsapp-scaling.pdf)). The lesson is that runtime and concurrency model can dominate raw language ergonomics; the result is largely BEAM-attributable (preemption, per-process heaps, message passing), not Erlang syntax. The commonly-quoted Erlang/AXD-301 "nine 9s" availability figure does not appear to trace to a primary peer-reviewed source and should not be used as evidence for a new language.

### Kotlin — an evidence gap

Google publishes adoption metrics (~60% of the top 1,000 Android apps use Kotlin) and internal testimony that Kotlin's non-null types have caught NPE bugs across AndroidX, but **no rigorous public defect-comparison study for Kotlin vs Java at Google-scale exists**. Any evaluation borrowing Kotlin as a comparator is standing on adoption evidence, not measured safety evidence.

### What the taxonomy of PL evaluation actually contains

Across these studies, PL evaluation reduces to a small number of instrument classes:

| Instrument | Example study | What it can settle |
|---|---|---|
| Observational defect count | Ray et al. FSE 2014 | Population associations at best; contested without Berger-style validation |
| Small-N controlled programming task | Prechelt 2000 | Productivity gaps of the size of 2–3× if effect is real |
| Corpus micro-analysis | Nanz & Furia ICSE 2015 | Conciseness, per-task idioms; not defect rate |
| Bug-injection replay | Gao/Bird/Barr ICSE 2017 | Upper bound on what a type system catches |
| Empirical adoption survey | Meyerovich & Rabkin OOPSLA 2013 | What developers value; not what actually works |
| Large-scale production deployment | Chromium, Android Rust | Density deltas for well-defined defect classes |
| Industrial case study | WhatsApp / Erlang | Scale and runtime capacity; not defect deltas |

Prechelt-style productivity effects and Android-Rust-style defect-class elimination are the only two categories to have produced practically significant, hard-to-reanalyze-away results. **A new agent-first language should aim for one of these two shapes, not for a general "reduces bugs" claim.**

---

## Part 2 — How AI Coding Tools and Agent-Authored Code Are Currently Evaluated

### The base benchmarks and their inflation

**HumanEval (Chen et al., 2021)** is 164 hand-written Python problems with function signatures, docstrings, and unit tests, scored with pass@k. Codex-12B scored **28.8% pass@1** and **70.2% pass@100** — the k-scaling result already implied that a single-shot number badly undersells model coverage ([arXiv:2107.03374](https://arxiv.org/abs/2107.03374)). **MBPP (Austin et al., 2021)** is 974 Python problems, mostly entry-level; the largest evaluated LM reached **59.6% few-shot** and **83.8% when fine-tuned on MathQA-Python** ([arXiv:2108.07732](https://arxiv.org/abs/2108.07732)). **APPS (Hendrycks et al., 2021)** is 10,000 Python competitive-programming problems tiered from introductory to competition; GPT-Neo passed ~20% of introductory test cases and near-zero on competition problems ([arXiv:2105.09938](https://arxiv.org/abs/2105.09938)). **AlphaCode (Li et al., Science 2022)** was the first system to reach a **median Codeforces ranking of ~54.3%** among human competitors, which moved the field's expectations for what "credible participation" meant ([Science 378, 2022](https://www.science.org/doi/10.1126/science.abq1158)).

The EvalPlus critique is the most-cited reason these numbers should be discounted. **Liu et al., "Is Your Code Generated by ChatGPT Really Correct?" NeurIPS 2023** extended HumanEval and MBPP tests by ~80× via LLM- and mutation-based generation, then re-ran models. The result was **pass@k reductions of 19.3–28.9%** for the same models; several models that outperformed ChatGPT on HumanEval failed to do so on HumanEval+, showing that overfitting distorts model *ranking*, not just absolute scores ([arXiv:2305.01210](https://arxiv.org/abs/2305.01210); [NeurIPS 2023 page](https://neurips.cc/virtual/2023/poster/72990)).

### SWE-bench and the collapse of the "verified" abstraction

**Jimenez et al., "SWE-bench," ICLR 2024** collected **2,294 real GitHub issues from 12 popular Python repositories**. Given the issue text and repository state, an agent must produce a patch that passes hidden `FAIL_TO_PASS` and `PASS_TO_PASS` tests. The original baseline was **Claude 2 at 1.96%** ([arXiv:2310.06770](https://arxiv.org/abs/2310.06770)).

The Verified subset arrived in August 2024. OpenAI had **93 experienced Python developers annotate 1,699 SWE-bench samples on four dimensions**. **68.3% of samples were filtered out**; **38.3% had underspecified problem statements**; **61.1% had overly narrow tests** — evidence that the majority of the original SWE-bench was structurally broken. The curated 500-sample Verified set produced a jump from ~16% to **33.2% for GPT-4o-2024-05-13**, almost entirely a benchmark-quality artifact ([OpenAI, "Introducing SWE-bench Verified," 2024](https://openai.com/index/introducing-swe-bench-verified/)).

Twelve months later, OpenAI announced they would no longer evaluate on Verified. Their reasons: SOTA on Verified went from **74.9% to 80.9% in 6 months**; a follow-up **138-problem audit found 59.4% had material test or description issues (35.5% overly narrow tests, 18.8% overly wide)**; and **all frontier models reproduced gold patches on many problems**, which OpenAI interprets as direct pretraining or later-stage contamination ([OpenAI, 2025](https://openai.com/index/why-we-no-longer-evaluate-swe-bench-verified/)). Even a curated 500-sample subset labeled by 93 developers was substantially contaminated and structurally biased within a year of release. **Any evaluation strategy for a new language must assume that any public benchmark it uses will follow the same trajectory.**

**Multi-SWE-bench (Zan et al., 2025)** provides the current best evidence on cross-language variance under identical protocol: **1,632 instances, 39 repositories, 7 languages, 68 annotators**. For Claude-3.7-Sonnet + MopenHands: **Python 52.20%, Java 21.88%, Rust 15.90%, C++ 14.73%, C 8.59%, Go 7.48%, JS 5.06%, TypeScript 2.23%** ([arXiv:2504.02605](https://arxiv.org/html/2504.02605)). Python is nearly an order of magnitude ahead. A new language starts *below* Rust/TS-like baselines unless it ships substantial training signal.

### Contamination-resistant benchmarks and the new baseline

**LiveCodeBench (Jain et al., 2024)** collects **400 problems** from LeetCode / AtCoder / CodeForces held **May 2023–May 2024**, with per-problem release dates so any model is scored only on problems released after its cutoff ([arXiv:2403.07974](https://arxiv.org/abs/2403.07974)). **BigCodeBench (Zhuo et al., 2024)** has **1,140 tasks across 139 libraries and 7 domains**, average 5.6 tests per task, 99% branch coverage; the best of 60 LLMs reached ~60% versus a **human baseline of ~97%** ([arXiv:2406.15877](https://arxiv.org/abs/2406.15877)). **Riddell, Ni & Cohan, ACL 2024** computed surface-form and semantic overlap between popular code benchmarks and open pretraining corpora and confirmed that **models score measurably better on subsets that had been seen during training** ([arXiv:2403.04811](https://arxiv.org/abs/2403.04811)); **Sainz et al. EMNLP 2023** formalized the contamination-inflation position ([ACL Anthology](https://aclanthology.org/2023.findings-emnlp.722/)).

**MultiPL-E (Cassano et al., 2022)** translated HumanEval and MBPP into 18 languages via a tool-assisted pipeline. Codex matched Python performance on JS, C++, Scala, and TypeScript; **popularity correlated with model performance** ([arXiv:2208.08227](https://arxiv.org/abs/2208.08227); [project site](https://nuprl.github.io/MultiPL-E/)).

### The no-resource paper — the number that most directly applies to Mo

**Giagnorio et al., "No Resource, No Benchmarks, No Problem? Evaluating and Improving LLMs for Code Generation in No-Resource Languages," 2026** is the study most directly applicable to any new agent-first language. HumanEval (154 tasks), MBPP (355 tasks), and McEval-Hard (227 tasks) translated into 9 languages spanning high-resource (Python/JS/Java), low-resource (OCaml, Haskell, Elixir, Racket), and **no-resource (MoonBit, Gleam)**. Headline results (pass@1, averaged across items and models):

| Regime | Average pass@1 | McEval-Hard | Notes |
|---|---:|---:|---|
| High-resource | **79%** | 59–89% | Python/JS/Java |
| Low-resource | **62%** | 27–84% | OCaml/Haskell/Elixir/Racket |
| No-resource | **9%** | **0–1%** | MoonBit/Gleam |

On Gleam, o3-mini's **syntactic-error rate was ~90%** — the model could not even produce compilable code most of the time. Adding language-specific documentation in prompt improved odds ratios by **~1.21× up to ~10.95×**, showing that "documentation-in-context" is a genuinely large lever for a brand-new language ([arXiv:2606.16827](https://arxiv.org/html/2606.16827v1)).

**SWE-AGI (Ling et al., 2026)** is the specification-driven benchmark built explicitly on MoonBit precisely because MoonBit is largely absent from pretraining. **22 tasks across 7 categories, each requiring 10³–10⁴ LoC of MoonBit, weeks-to-months of expert engineering per task, 10% public tests / 90% private tests.** Baselines: **gpt-5.3-codex 19/22 (86.4%), gpt-5.2-codex 17/22 (77.3%), claude-opus-4.6 15/22 (68.2%)**. On six easy-tier tasks alone, most other frontier models solve at most 2/6 ([arXiv:2602.09447](https://arxiv.org/html/2602.09447v1); [swe-agi.com](https://swe-agi.com/about.html)). The design choices — submission-based sandbox, fixed API scaffold, hidden private tests, human-validated tests from authoritative RFCs, canonical + property-based + LLM-generated + fuzz-mutated test corpora — are the current template for how a new language should build its own harness.

### Quasar, CodeAct, and the "action language" precedent

**Bastani et al., "QUASAR: A Programming Language for the Age of LLM Actions," 2025** is direct precedent for a purpose-built language for LLM code actions. LLMs generate a *restricted Python subset* which is transpiled into QUASAR for execution with batched access-control approvals, automatic parallelization, and conformal-semantics uncertainty. Result: **26% ± 29 fewer user interactions overall on GQA, 44% ± 19 where batching was possible on AgentDojo, 97% ± 1 reduction in approvals on BrowseComp-Plus, 93% ± 4 execution-time speedup** ([arXiv:2506.12202](https://arxiv.org/pdf/2506.12202v2)). Critically, the authors report that **LLMs cannot generate QUASAR directly — "they have never seen it before"** — so the practical strategy was "Python subset → transpile," which sidesteps the no-resource problem while capturing the safety and performance wins. **A Mo evaluation should include (a) direct-write pass rates, (b) transpile-from-Python pass rates, and (c) safety-property counts as first-class metrics.**

**CodeAct (Wang et al., 2024)** compared agents that use executable Python as their action space against JSON/text tool-calling agents and reported **~20% higher success rate for code-action agents** on multi-tool benchmarks ([arXiv:2402.01030](https://arxiv.org/abs/2402.01030)). If a new language's execution model *is* the agent's action language, CodeAct is the empirical baseline for the expected capability lift.

### Dan Luu's cross-language LLM data

Luu's **`pl-tokens`** post ran two studies: the **Zstd suite** (40 programs per language × 12+ languages) and **`ProgramBench`** (4,800 test cases across many languages). Findings: the "dynamically typed is better for LLMs" claim is **not supported** by his data once controlled for task and model; **language popularity has only a weak-to-moderate correlation** with pass rate with pronounced non-monotonicities; **Clojure medium-complexity Zstd programs failed 36/40 attempts**; and a widely-cited prior "ai-coding-lang-bench" **had test-harness bugs that produced false Rust failures** and propagated to popular articles ([Luu, "How much do programming languages affect ChatGPT?"](https://danluu.com/pl-tokens/)). The state of the art in blog-post benchmarks is unreliable enough that the empirical baseline for "LLM code quality by language" is essentially open.

### Gaps and contested claims specific to agent-language evaluation

1. **Elixir/Discord defect data does not exist** in comparable form to the Rust/Android density numbers; Discord's public materials focus on scale and Rust rewrites of specific services.
2. **Kotlin vs Java defect data does not exist** at scale from Google.
3. **TypeScript "reduces bugs" is contested** — Gao/Bird/Barr's ~15% upper bound is often quoted without its bound, and Bogner/Merkel finds *more* bug-fix commits in TypeScript than JavaScript.
4. **SWE-bench Verified is already a lower-bound-quality data point** — OpenAI's own 138-sample audit found 59.4% material issues plus direct contamination evidence.
5. **A new language begins with a Gleam-like handicap** (~9% pass@1 average, 0–1% on hard tasks), and any evaluation must explicitly report where it sits on this spectrum and how it plans to move up.
6. **Contamination is a moving target**; the current defenses (LiveCodeBench, SWE-bench Pro, SWE-AGI) should be assumed compromised within 12–18 months of release. A rotation, not a fixed benchmark, is required.

---

## Part 3 — Formal Verification and Contract-Based Programming: What the Evidence Actually Shows

### The compiler-verification landmark

**Xavier Leroy, "Formal Verification of a Realistic Compiler," CACM 2009** documents CompCert, which compiles a large C subset through **8 intermediate languages and 14 passes**, formalized in **42,000 lines of Coq** (14% compilation algorithms, 10% language semantics, **76% correctness proofs**). Runtime: >2× faster than `gcc -O0`; 7% slower than `-O1`; 12% slower than `-O2`. Development effort: ~3 person-years ([Leroy CACM PDF](https://xavierleroy.org/publi/compcert-CACM.pdf); [CACM](https://cacm.acm.org/research/formal-verification-of-a-realistic-compiler/)).

**Yang, Chen, Eide & Regehr, "Finding and Understanding Bugs in C Compilers," PLDI 2011** is the outside adversarial test. Csmith-based random testing over three years reported **>325 previously unknown bugs** across every C compiler tested; "every compiler we tested was found to crash and also to silently generate wrong code when presented with valid input." The paper's headline finding for the verification community is the asymmetry: **CompCert's verified middle and back end was the only substantial component in which Csmith found zero wrong-code bugs**; the bugs it did find in the CompCert pipeline were in the unverified front end ([Yang et al., PLDI 2011 preprint](https://users.cs.utah.edu/~regehr/papers/pldi11-preprint.pdf)). This single sentence is the most-cited empirical validation of formal verification in PL history: an outside team made it credible.

### SPARK/Ada — the industrial contract-language evidence base

**Chapman, "Industrial Experience with SPARK," SIGAda** reports three flagship deployments:

- **SHOLIS** (UK DEF-STAN 00-55): ~13,000 declarations, ~14,000 statements, ~9,000 verification conditions discharged by code proof; proof was "significantly more cost-effective at finding faults than traditional testing."
- **MULTOS CA** (ITSEC E6): SPARK is the security kernel of the tamper-proof software; 30% SPARK, 30% Ada 95, 30% C++, 5% C, 5% SQL.
- **Lockheed C-130J Mission Computer** (DO-178B Level A): ~80% of the MC core in SPARK; Lockheed reported an **80% saving against the expected MC/DC test budget** and a fault density **less than one tenth of the expected industry norm for safety-critical software** ([Chapman SIGAda PDF](https://www.sigada.org/ada_letters/dec2000/chapman-paper.pdf)).

The AFIT thesis (Baity 2021) reproduces those SPARK numbers and cites Woodcock et al.'s 62-project industrial formal-methods survey: **92% reported improved quality, 0% worsened quality; 12% worsened time, 7% worsened cost; three times as many projects reported reduced time as increased time** ([AFIT thesis](https://apps.dtic.mil/sti/trecms/pdf/AD1132199.pdf)). The Tokeneer replay with SPARK 2014 reduced **unproved checks from 234 to 39** and detected **all four seeded vulnerabilities** ([AdaCore blog](https://www.adacore.com/blog/tokeneer-fully-verified-with-spark-2014)).

The often-quoted "3–5× cost multiplier for SPARK" is not attested in the primary Chapman or AdaCore documents — the published numbers are 80% MC/DC savings and <10% of industry-norm fault density, i.e., net savings. That widely-repeated number should be traced to a primary source before being used.

### The systems-verification cost curve

**IronFleet (SOSP 2015)** is the most detailed public accounting of a verified distributed-system stack ([UMich mirror](https://web.eecs.umich.edu/~manosk/assets/papers/ironfleet-sosp15.pdf)):

| Layer | Spec LOC | Impl LOC | Proof LOC |
|---|---:|---:|---:|
| High-level specs (IronRSL + IronKV + TL) | 327 | – | – |
| Protocol (IronRSL Protocol/Refinement/Liveness) | 202 | – | 12,450 |
| Protocol (IronKV) | 134 | – | 6,817 |
| TLA library | – | – | 1,824 |
| Implementation (Common/RSL/KV + I/O) | 737 | 5,114 | 18,162 |
| **Total** | **1,400** | **5,114** | **39,253** |

Implementation-layer **proof-to-executable ratio 3.6:1**; safety proof-to-code **5:1**; with liveness the overall ratio was **8:1**; **~3.7 person-years** of methodology and verification work; peak IronRSL throughput within **2.4× of unverified Go MultiPaxos**. Ironclad Apps (OSDI 2014) reported a **4:1 proof-to-code ratio**. seL4 sits at **~10 kLOC C to ~500 kLOC proof (50:1)** at a cost of **~$400/LoC vs ~$1,000/LoC for comparable unverified high-assurance kernels**, with "no bugs publicly reported in the verified portions of the kernel in over 15 years" ([Wikipedia seL4](https://en.wikipedia.org/wiki/SeL4)).

The pattern is: contract-level guarantees on production code (SPARK on Lockheed) do not add net cost and may reduce it by 80% downstream. Full functional-correctness proofs of protocol code (Ironclad, IronFleet) run 4–8:1. Machine-checked C-kernel proofs run 50:1. **The proof-to-code ratio is roughly linear in the depth of the guarantee, and superlinear once you reach machine-code-to-binary equivalence.**

### The Everest / F* line — verified crypto at line rate

**EverCrypt (IEEE S&P 2020)** aggregates over **124K verified lines of specs, code, and proofs** to produce **~29K lines of C and 14K lines of assembly**, deployed in Mozilla Firefox, the Linux kernel, mbedTLS, Tezos, WireGuard, and the Windows kernel. Merkle-tree library supports **2.7M inserts/s**; performance "matches or exceeds the best unverified implementations" ([EverCrypt page](http://www.normalesup.org/~ramanana/research/everest/evercrypt/); [Project Everest](https://project-everest.github.io/); [HACL* repo](https://github.com/hacl-star/hacl-star)). Because correctness is by construction, "defects found" is not the right metric — the salient claim is *field deployment at line rate against a machine-checked spec*.

### Lean 4 in industry

**Leo de Moura's CAV 2024 invited talk** reports Lean 4 as **~120 kLoC of Lean**, Mathlib ported to Lean 4 in 2023, Lean FRO launched July 2023 with AWS advisors. **SampCert** — the formally verified DP sampler behind AWS Clean Rooms Differential Privacy — is the only verified implementation of discrete Gaussian and zCDP primitives and is **2× faster** than the unverified predecessor. AWS's Cedar authorization language has its engine and analyzer verified in Lean ([CAV 2024 slides](https://leodemoura.github.io/files/CAV2024.pdf); [Lean use cases](https://lean-lang.org/use-cases/)).

### TLA+ at Amazon — the design-level bug-finding case

**Newcombe, Rath, Zhang, Munteanu, Brooker & Deardeuff, CACM April 2015**: TLA+ used on **10 large complex AWS systems by 7 teams**; engineers become productive in **2–3 weeks**. DynamoDB spec written in "a couple of weeks" ran on 10 EC2 model-checking instances and found **1 data-loss bug plus 2 more serious subtle bugs, and 1 subtle bug in the initial data-center migration design**; shortest counterexample **35 high-level steps**. S3, first-algorithm B.M., PlusCal, and distributed-algorithm cases produced additional subtle bugs. Conventional design review, static analysis, stress testing, and fault injection were "necessary but not sufficient" ([CACM abstract](https://cacm.acm.org/research/how-amazon-web-services-uses-formal-methods/)).

### LLM-assisted verification — the very recent wave

**DafnyBench (Loughridge et al., arXiv:2406.08467, June 2024)**: **750 Dafny programs, ~53,000 LOC**. Best model at release: **Claude 3 Opus at 67.8% ± 1.7%**; retry with error-message feedback moved best models from ~54% first-attempt to ~65% after several tries ([arXiv:2406.08467](https://arxiv.org/abs/2406.08467)).

**Vericoding (Bursuc et al., arXiv:2509.22908, September 2025)** is the follow-up. Benchmark: **12,504 formal specifications — 3,029 Dafny, 2,334 Verus/Rust, 7,141 Lean — of which 6,174 are new unseen problems**. Vericoding success rates with off-the-shelf LLMs: **Dafny 82%, Verus/Rust 44%, Lean 27%**. Adding natural-language descriptions does not significantly improve performance. The paper's headline: **"LLM progress has improved pure Dafny verification from 68% to 96% over the past year"** ([arXiv:2509.22908](https://arxiv.org/abs/2509.22908)).

**AutoVerus (Yang et al., OOPSLA 2025)** reports **>90% correct proofs on 150 non-trivial Verus tasks**, >50% completed in under 30 seconds or ≤3 LLM calls ([arXiv:2409.13082](https://arxiv.org/abs/2409.13082)). **Baldur (First, Rabe, Ringer & Brun, FSE 2023)** generates whole proofs for **6,336 Isabelle/HOL theorems**, adding **+8.7 pp over Thor**; combined **Baldur + Thor fully prove 65.7%** ([arXiv:2303.04910](https://arxiv.org/abs/2303.04910)). **LeanDojo (Yang et al., NeurIPS 2023)** extracts **98,734 theorems and proofs** from Mathlib; ReProver trains in **1 GPU-week** ([arXiv:2306.15626](https://arxiv.org/abs/2306.15626)).

**The most important number in this whole section for an agent-first language design** is the Vericoding cross-language ordering: with the same LLMs, **Dafny 82% ≫ Verus/Rust 44% ≫ Lean 27%**. This is the first controlled, primary-source comparison of agent-plus-verifier throughput as a function of language design. **The language design directly determines how much of the verification an agent can do.**

### Independent vs author-graded classification

- **Independent controlled comparison:** Csmith → CompCert (Yang et al. PLDI 2011); KLEE vs developer test suites (Cadar et al. OSDI 2008 — **KLEE beat 15 years of developer tests on coreutils: 84.5% vs 67.7% line coverage, 76.9% vs 56.5% branch coverage**, [PDF](https://www.usenix.org/legacy/event/osdi08/tech/full_papers/cadar/cadar.pdf)); Vericoding cross-language comparison; Woodcock 62-project survey.
- **Case study, author-graded:** IronFleet, Ironclad, EverCrypt, Chapman SPARK deployments, Tokeneer, seL4, Amazon TLA+, MongoDB TLA+, Elasticsearch TLA+, SampCert, Cedar, Bosque, Idris.
- **Benchmark, author-graded but reproducible:** DafnyBench, AutoVerus, Baldur, LeanDojo, Copra, LLMSTEP.

The strongest single piece of independent evidence remains Csmith → CompCert.

---

## Part 4 — Experimental Design: A Concrete, Executable Evaluation Program

The seven protocols below are pre-registered on OSF using an SE-adapted registered-report template. Code, prompts, harness images, task splits, raw logs, per-attempt token ledgers, and analysis notebooks are released under MIT + CC-BY-4.0 within 30 days of results freeze. Model checkpoints are frozen for confirmatory runs; the same outer ReAct loop, tool set, 40-step iteration cap, and 200,000-token context window is used across all language conditions to isolate language effects from scaffold effects. Alpha 0.05, two-tailed, Benjamini–Hochberg FDR at q = 0.05. Power target 0.80 for small effects (d = 0.3 for continuous outcomes; Δ = 5 pp around a 0.40 base rate for proportions). Blinding, attrition rules, and analysis stack (`lme4`, `brms`, 10,000-resample bootstrap) are pre-registered.

### Experiment 1 — Null-Hypothesis: Mo versus mainstream + bolted-on checks

**H1₁:** Mo produces an end-to-end task-success rate ≥ **5 pp** higher than the best bolted-on baseline (pre-registered directional test). Co-primary contrasts on defect rate and iteration count.

**Language conditions (5 levels):** (1) Mo; (2) Go + `staticcheck` + `errcheck` + capability sandbox + `contracts-go`; (3) TypeScript + `strict: true` + `zod` + `effect-ts` + `eslint --max-warnings 0`; (4) Python + `pydantic v2` + `returns` + `mypy --strict` + `bandit`; (5) vanilla Python floor.

**Task set (833 tasks):** all **500 SWE-bench Verified** instances ([OpenAI 2024](https://openai.com/index/introducing-swe-bench-verified/)); 164 originals + 164 perturbed problems from HumanEval+ ([Liu et al. NeurIPS 2023](https://arxiv.org/abs/2305.01210)); **150 held-out** problems commissioned between design freeze and reveal by three engineers unfamiliar with Mo, each with hidden `FAIL_TO_PASS` and `PASS_TO_PASS` tests following the SWE-bench Verified protocol. The held-out set exists to control for contamination that has entered baseline-language training data more than Mo's.

**Sample size:** 833 tasks × 3 model checkpoints = 2,499 attempts per language, sufficient for the Δ = 5 pp primary contrast at power > 0.99 in the pooled analysis and ≥ 0.80 for Δ ≥ 8 pp within stratum.

**Metrics:** binary task success on hidden tests; defect rate on a shadow suite the agent never sees (mutation-derived); iteration count; time-to-first-passing-attempt; escape-hatch counts (`unsafe`, `any`, `@ts-ignore`, `# type: ignore`, Mo `pragma bypass`).

**Success threshold (committed in advance):** Mo will be counted as positive support only if **all three** of the following hold: task-success ≥ 5 pp higher than the best baseline with 95% CI excluding 0; defect-rate mean ≥ 15% relatively lower with one-sided bootstrap p < 0.05; iteration-count median not more than 15% higher (non-inferiority band). 1-of-3 or 2-of-3 is reported as mixed.

**Analysis:** mixed-effects logistic regression with task and model as random intercepts; Tukey HSD across 5 language levels with BH-FDR; defect rate as negative-binomial GLMM with `offset(log(shadow_tests))`; Wilcoxon signed-rank on paired iteration counts; Bayesian robustness with `brms` and LOO-CV.

**Confounder table:** contamination favoring Python/JS (mitigated by the 150 held-out set); Mo-port quality (blind two-expert audit); toolchain strawman (baseline stack chosen by 5 senior engineers per language, frozen); model differences (same 3 checkpoints; model as random intercept); prompt-engineering asymmetry (system prompts ≤ 800 tokens, structurally identical, frozen and published); scaffold advantage (generic tool interface; all diagnostic parsers pre-registered and equivalent); iteration-cap masking (survival curves + cap-80 sensitivity on 20% subsample); test-set leakage (grep-audit trajectories for test filenames).

### Experiment 2 — Cold-start / training-data gravity

**H1₃:** Successive augmentations (grammar-constrained decoding → in-context skill file → RAG → compiler-feedback loops) each add ≥ **3 pp** to Mo pass@1 monotonically. **H1₄:** The best augmented Mo condition closes ≥ **60%** of the gap between "base model on Mo" and "base model on Python" on translated HumanEval+ tasks.

**Ablation ladder:**

| Condition | Description |
|---|---|
| A0 | Base model on Mo, zero-shot |
| A1 | + grammar-constrained decoding via Mo GBNF grammar ([Geng et al. EMNLP 2023](https://arxiv.org/abs/2305.13971); [Melcer et al. 2024](https://ar5iv.labs.arxiv.org/html/2402.17988)) |
| A2 | + 2 KB in-context Mo skill file (task-agnostic style + effect model) |
| A3 | + RAG over Mo docs and stdlib (BGE-M3 retriever, top-k = 5), following [DocPrompting (Zhou et al. ICLR 2023)](https://arxiv.org/abs/2207.05987) and [ReAcc (Lu et al. 2022)](https://arxiv.org/abs/2203.07722) |
| A4 | + compiler-feedback loops with n ∈ {1, 3, 5} retries |
| A5 | Python reference ceiling (base model on Python, zero-shot) |

**Task set:** 154 HumanEval + 355 MBPP + 227 McEval-Hard = **736 tasks × 6 conditions × 3 models = 13,248 attempts**, mirroring the filtering in Giagnorio et al. ([arXiv:2606.16827](https://arxiv.org/html/2606.16827v1)).

**Power:** paired within-task McNemar on n = 736 with expected discordant rate ≈ 0.25 detects a 3-pp effect at power > 0.90.

**Metrics:** pass@1 primary; pass@10 at temperature 0.7 with the unbiased HumanEval estimator; gap-closure ratio `(A_k − A0) / (A5 − A0)` bounded to [0,1]; retry-saturation curve.

**Threshold:** monotone-increasing ladder with all pairwise differences ≥ +3 pp (95% CI excludes 0); gap-closure ≥ 60% for A4 vs A5; retry saturation reaches ≥ 90% of asymptote by n = 5.

**Confounders:** translator artifacts (60-translation hand audit per benchmark, re-run excluding flagged); retriever quality (recall@5 on hand-labeled relevance set); constrained-decoding fluency hit (soft-constraint A1' as sensitivity if hard constraint hurts >5% of tasks by >20 pp); grammar completeness (99% conformance on 500 hand-written Mo files); skill-file authorship advantage (authored blind, third-party reviewed, no tuning on eval tasks).

### Experiment 3 — Maintainability (6-month within-subjects longitudinal)

**H1₅:** After 6 months, developers modifying agent-authored Mo complete change tasks ≥ **20% faster** than modifying the equivalent bolted-on baseline, with ≤ **60% of the regression rate**. **H1₆:** Cyclomatic-complexity growth per change is ≥ **25% lower** in Mo.

**Design:** within-subjects, counterbalanced Latin-square over two 24-week arms. Two initial 30-KLOC codebases (a task-runner and a document-store) are generated in month 0 by the same agent stack in both Mo and the best Experiment-1 baseline. Each of **32 professional developers** completes a fixed sequence of 12 change tickets at months 3 and 6: **6 bug-fix tickets** from real historical PRs on comparable OSS Go/TS repos, **4 small-feature tickets**, and **2 refactor tickets**. Latin-square counterbalances language order; 8-hour paid Mo onboarding with an 80% competency-quiz floor.

**Sample:** 32 × 2 languages × 2 timepoints × 12 tickets = **1,536 change events**; paired within-subjects at d = 0.3 requires 88 pairs and the design provides 384 per timepoint.

**Metrics:** wall-clock time-to-modify (capped at 90 min); regressions introduced on the hidden pre-existing test suite; cyclomatic-complexity growth via `radon`/`gocyclo`/`ts-complex`/purpose-built `mo-cc`; 10-item comprehension quiz per ticket (Cohen's κ ≥ 0.7 required between two blinded raters); NASA-TLX cognitive load.

**Threshold:** median time-to-modify (Mo) ≤ 0.80 × baseline with 95% bootstrap CI excluding 1.0; mean regressions/ticket ≤ 0.60 × baseline; comprehension quiz ≥ baseline + 1.0 raw points; cyclomatic growth ≤ 0.75 × baseline.

**Analysis:** linear mixed-effects `time ~ language * timepoint + (1|developer) + (1|ticket)`; Poisson GLMM on regressions with `offset(log(tests_run))`; Gaussian LMM on `log(1+ΔM)`; ordinal LMM on comprehension; pre-registered mediation of time-to-modify by comprehension.

**Confounders:** novelty (counterbalanced Latin square with language-order interaction); developer skill (within-subject; pre-test coding assessment covariate); codebase drift (both codebases frozen at month 0); Hawthorne effects (third-party facilitator; developers told study is about "maintenance tooling"); language proficiency asymmetry (competency-quiz floor); attrition (20% budget; multiple-imputation sensitivity at 30%).

### Experiment 4 — Human review at spec altitude

**H1₇:** Reviewers of Mo spec artifacts (function signatures with contracts, capability annotations, and property tests — *no bodies*) detect ≥ **90%** of the defects that reviewers of full bodies detect in the baseline, at ≤ **60%** of the review time. **H1₈:** Comprehension quiz scores for spec-only Mo review are non-inferior to full-body baseline (Δ ≥ −0.5 on a 10-point scale, TOST lower bound excludes −0.5).

**Design:** 2 × 2 between-subjects factorial: {Mo, TS-baseline} × {spec-only, full-body}. **240 professional reviewers × 60 review tasks × 5 PRs each × 12 injected mutants** = **43,200 mutant × reviewer observations**. Mutation categories follow [Panichella et al. "Property-Based Mutation Testing" (2023)](https://arxiv.org/abs/2301.13615): semantic-shift mutants (body mutated, spec satisfiable), spec-violation mutants (spec mutated, body follows), architectural mutants (hidden capability added or effect signature changed). Design extends the [Spadini et al. ICSE 2019 test-driven code-review protocol](https://sback.it/publications/icse2019a.pdf), which itself extended [Bacchelli & Bird ICSE 2013](https://2013.icse-conferences.org/content/expectations-outcomes-and-challenges-modern-code-review.html) and [Sadowski et al. ICSE-SEIP 2018](https://dl.acm.org/doi/pdf/10.1145/3183519.3183525).

**Metrics:** defect-detection rate (mutant flagged within 5 lines of injection); false-positive rate; wall-clock review time (capped 45 min); 10-item comprehension quiz (behavior, invariants, capabilities, effects); architectural decision agreement against a two-senior-engineer rubric.

**Threshold:** Mo-spec detection ≥ 0.90 × Mo-body detection (non-inferiority margin 5 pp); median review time (Mo-spec) ≤ 0.60 × baseline-body; comprehension quiz mean (Mo-spec) ≥ mean(baseline-body) − 0.5; architectural agreement (Mo-spec) ≥ 0.80 × Mo-body.

**Analysis:** mixed-effects logistic regression `detected ~ language * artifact + mutant_category + (1|reviewer) + (1|pr) + (1|mutant)`; TOST for non-inferiority; log-normal LMM on review time; Bayesian complement.

**Confounders:** mutant realism (mutants drawn from Experiment 5's CVE corpus + classical operators, realism rated by 3 experts); reviewer familiarity (8-hour onboarding, competency floor); comment-classification bias (blinded raters, κ ≥ 0.7); order effects (randomized per reviewer); spec-shorter-therefore-easier confound (analyze detection normalized by bytes and tokens); syntax breaks blinding (recruit reviewers with no Mo public exposure; exit-survey probe).

### Experiment 5 — Defect study: real-bug corpus replay

**H1₉:** Of a random sample of **500 real-world CVE/advisory bugs** from Python, JS/TS, and Go repositories, transpiled to Mo, Mo's static analysis (type + effect + capability + exhaustiveness) catches ≥ **40%** at compile time. **H1₁₀:** Mo's runtime contracts catch an additional ≥ **20 pp** under a shadow test run.

**Corpus:** 300 bugs from the [GitHub Advisory Database](https://github.com/advisories) 2020–2025, stratified by CWE (min 40 each of memory-safety-adjacent, injection, logic/state, concurrency, auth/authz); 200 bugs from historical resolved issues on the 12 SWE-bench Verified repositories. Each bug is transpiled to Mo (automated + two-reviewer human audit, κ ≥ 0.7); the pre-fix version is run through (i) Mo compile only, (ii) Mo compile + runtime contracts under test suite, (iii) baseline linter stack, (iv) baseline + tests.

**Metrics:** static catch rate (compiler error within ±5 LOC of the fault); runtime catch rate; false-positive rate on the post-fix version; localization accuracy (median line-distance); CWE-stratified baseline delta.

**Threshold:** combined Mo catch rate ≥ **60%** overall; static-only ≥ 40%; Mo static + runtime ≥ baseline static + runtime by ≥ **15 pp** overall with 95% bootstrap CI excluding 0; false-positive rate on post-fix ≤ 5%; localization median ≤ 3 LOC.

**Analysis:** paired McNemar per bug against each baseline; CWE-stratified logistic regression `caught ~ toolchain + cwe + (1|repo)`; sensitivity excluding transpilations flagged as lossy.

**Confounders:** transpilation quality (two-reviewer audit; lossy cases excluded from primary); advisory sampling bias (stratified sampling script published; independent 100-bug replication sample); baseline lint config strength (vetted by 3 senior engineers per language); coverage dependency for runtime catches (sensitivity restricted to line-coverage ≥ 80%); ground-truth ambiguity (fault-region rather than fault-line as sensitivity). The "nine 9s" Erlang folklore is explicitly **not** used as a threshold anchor; the [Chromium ~70%](https://www.chromium.org/Home/chromium-security/memory-safety/) and [Android trend](https://security.googleblog.com/2024/09/eliminating-memory-safety-vulnerabilities-Android.html) motivate CWE stratification only.

### Experiment 6 — Honest token accounting

**H1₁₁:** After amortizing skill-file and error-catalog loads over ≥ 30 tasks per session, Mo's mean total tokens per accepted task is ≤ **1.25×** the best baseline. **H1₁₂:** Per-task marginal token cost (excluding amortized preamble) is ≤ **0.90×** baseline.

**Design:** re-uses Experiment 1's 833-task set under three batching regimes: {1, 10, 50 tasks per session}. Following the [ilo "Ways to be Token Efficient" case study](https://ilo-lang.ai/docs/ecosystem/token-efficiency/), which separates amortized skill-load cost from per-task marginal cost and warns against apples-to-oranges token comparisons.

**Metrics:** total tokens (input + output + cached, billed with published multipliers); amortized preamble; marginal per-task; USD cost at frozen rate card; cost per successful task. Cache hit rate reported separately; comparisons hold or ignore caching consistently across arms.

**Threshold:** amortized-total ratio (Mo / best baseline) ≤ 1.25 at batch = 50; marginal per-task ratio ≤ 0.90; cost-per-success ratio ≤ 1.10.

**Confounders:** vendor cache-pricing differences (native + priced tokens reported separately; cache-off sensitivity); chattier diagnostics (diagnostic verbosity is Experiment 7's ablation lever; this study reports at default only); baselines lack skill files (matched-byte-count "coding conventions" preamble for baselines; publish both); iteration-cap truncation (report cap-hit % per arm; cap-80 sensitivity); vendor-run measurement bias (all runs on identical harness; no vendor-supplied numbers).

### Experiment 7 — Agent-friendliness feature ablation

**H1₁₃:** At least **3 of 6** features produce a main effect ≥ **+3 pp** on task success in the fractional-factorial (α = 0.05 BH-FDR). **H1₁₄:** Removing "structured diagnostics" causes the largest single-factor drop.

**Six binary factors:**

| Factor | Off | On (Mo native) |
|---|---|---|
| F1 Structured diagnostics | Plain-text `stderr` | JSON diagnostics with span IDs, category, fix-hints |
| F2 Edit-by-ID | Line-based edit tool | Node-ID edit over AST |
| F3 Capability-checked effects | All effects allowed | Capability tokens required at compile |
| F4 Fast compile loop | Full rebuild (~3 s) | Incremental (~150 ms) |
| F5 Deterministic simulation | Real-time async | Sim clock with pre-registered seeds |
| F6 Contract runtime | Contracts off | Contracts enforced with structured violation reports |

**Design:** **Resolution-IV 2⁶⁻¹ = 32 cells** on the full 650-task set (500 SWE-bench Verified + 150 held-out) × 3 models = **19,500 attempts per cell**; full 2⁶ = 64 factorial on a 100-task stratified subsample for 2-way interactions. Follows [SWE-agent NeurIPS 2024 ablation methodology](https://proceedings.neurips.cc/paper_files/paper/2024/file/5a7c947568c1b1328ccc5230172e1e7c-Paper-Conference.pdf), [OpenDevin CodeAct 1.0](https://xwang.dev/blog/2024/opendevin-codeact-1.0-swebench/), and [DEI (Zhang et al. 2024)](https://arxiv.org/pdf/2408.07060) (10 runs each of Agentless, Moatless, Aider over 300 SWE-Bench-Lite instances).

**Metrics:** task success, defect rate, iteration count, time-to-first-pass, escape-hatch usage; plus diagnostic-follow accuracy (fraction of turns where the agent's next edit addresses the top diagnostic), capability-violation counts, contract-violation counts, edit-conflict rate.

**Threshold:** ≥ 3 factors with main effect ≥ +3 pp FDR-corrected; ranking of factors stable across the 3 models (Kendall τ ≥ 0.6); adversarial pre-registration commits to reporting all six factors including any *negative* effects.

**Analysis:** mixed-effects logistic regression with all six main effects, selected 2-way interactions from subsample, task and model random intercepts; Type-III SS ANOVA-of-deviance; BH-FDR; Bayesian model averaging over the 2⁶ feature-inclusion models with `brms + loo`.

**Confounders:** docs leaking information about disabled features (docs regenerated per condition); runtime-only features biting only at execution (static and dynamic fail tallies reported separately); randomization variance (3 seeds per cell); model × feature interaction (model as random slope); Resolution-IV aliasing (aliasing structure published; interactions confirmed on full-factorial subsample); publication temptation to hide null features (adversarial pre-registration).

---

## Part 5 — Threats to Validity and Failure Modes of PL / AI Evaluation

Any "our new agent-first language beats language X on our benchmark" claim inherits the failure modes of the two most epistemically fragile literatures in computer science.

### Cherry-picking and the "we beat X on our benchmark" pattern

**Vitek & Kalibera, "Repeatability, Reproducibility and Rigor in Systems Research," PLDI 2011** reviewed 133 papers from ASPLOS, PACT, PLDI, and CGO. They report that **"none adequately considered measurement bias"** and that **"39 of 42 papers at PLDI 2011 reporting execution time did not bother to mention uncertainty"** ([Vitek & Kalibera, 2011 PDF](https://www.cs.kent.ac.uk/pubs/2011/3174/content.pdf); [ACM DL](https://dl.acm.org/doi/10.1145/2038642.2038650)). Their four-symptom catalog — unrepeatable, unreproduced, measuring the wrong thing, meaninglessly measuring the right thing — is the reference taxonomy for language-shootout pathology.

### The researcher-group effect

**Shepperd, Bowes & Hall, "Researcher Bias in Machine Learning for Software Defect Prediction," IEEE TSE 2014** meta-analyzed 42 primary studies containing 600 empirical prediction results with random-effects ANOVA over four factors. **The choice of classifier explains 1.3% of variance; the researcher group explains 31%.** Their summary: *"It matters more who does the work than what is done"* ([Shepperd, Bowes & Hall 2014 ePrints](https://eprints.lancs.ac.uk/id/eprint/127414/)). This is direct evidence that unblinded evaluation is systematically biased.

### The Ray → Berger saga is the reference precedent

Any PL evaluation that does not explicitly address the Berger et al. critique is inadequate. The original Ray et al. FSE 2014 paper found 11 languages with defect associations across 728 GitHub projects. Berger et al.'s 2019 reproduction, with human-validated bug labels, missing-data audit, and language-classification audit, reduced that to 4 languages with "exceedingly small" practical effect sizes, and concluded that "too many unaccounted sources of bias remain to hope for a meaningful comparison of bug rates across languages" ([Berger et al., ACM TOPLAS 2019](https://dl.acm.org/doi/fullHtml/10.1145/3340571)). **A new language evaluation must survive this protocol.**

### Contamination in code benchmarks

**Riddell, Ni & Cohan (arXiv 2403.04811, March 2024)** found "substantial overlap between popular code generation benchmarks and open training corpus" and that "models perform significantly better on the subset of the benchmarks where similar solutions are seen during training" ([arXiv:2403.04811](https://arxiv.org/abs/2403.04811)). **Sainz et al. EMNLP 2023** formalize the position: "The worst kind of data contamination happens when a Large Language Model is trained on the test split of a benchmark, and then evaluated in the same benchmark" ([ACL Anthology](https://aclanthology.org/2023.findings-emnlp.722/)). The GPT-4 technical report itself acknowledged Codeforces contamination when the model "solves problems dated before its training cutoff at much higher rates than newer problems" ([arXiv:2303.08774](https://arxiv.org/abs/2303.08774)).

### Model capability drift

**Chen, Zaharia & Zou, "How Is ChatGPT's Behavior Changing over Time?" (arXiv 2307.09009)** compared March 2023 and June 2023 versions of GPT-3.5 and GPT-4. **GPT-4 (March 2023) achieved 84% accuracy on prime-vs-composite; GPT-4 (June 2023) dropped to 51% on the same test.** They observed increased formatting errors in code generation and reduced instruction-following, and concluded that "the behavior of the 'same' LLM service can change substantially in a relatively short amount of time" ([arXiv:2307.09009](https://arxiv.org/abs/2307.09009)). Every benchmark result must be pinned to a specific model version, weights hash where available, and inference-server configuration.

### Pre-registration in software engineering

**Ernst & Baldassarre, "Registered Reports in Software Engineering" (arXiv 2302.03649, 2023)** document that registered reports "were first introduced in the International Conference on Mining Software Repositories in 2020" and are "now established in three conferences and two pre-eminent journals, including Empirical Software Engineering" ([arXiv:2302.03649](https://arxiv.org/abs/2302.03649)). **Field et al., "The effect of preregistration on trust in empirical research findings," Royal Society Open Science 2020** show that preregistration meaningfully increases reader trust ([Field et al. 2020 PDF](https://pure.uva.nl/ws/files/55596572/rsos.181351.pdf)). **Cockburn, Gutwin & Dix, "HARK No More" (CHI 2018)** documented that undisclosed hypothesizing-after-results-are-known was widespread in HCI ([CHI 2018](https://dl.acm.org/doi/10.1145/3173574.3173715)).

### Reproducibility crises

**Collberg & Proebsting, "Repeatability in Computer Systems Research" (CACM March 2016)** studied 601 ACM papers whose results were backed by code. **For only 32.3% could they obtain and build the code within 30 minutes; for 54% either it built or the authors said it would with reasonable effort** ([TR PDF](http://reproducibility.cs.arizona.edu/v2/RepeatabilityTR.pdf); [CACM DOI](https://dl.acm.org/doi/10.1145/2812803)). **Pineau et al., JMLR 2021** introduced the ML Reproducibility Checklist now standard at NeurIPS — mathematical setting, assumptions, complexity analysis, dataset statistics, code (training + evaluation + trained models), hyperparameter search protocol, number of runs, central tendency + variation, average runtime/energy, compute infrastructure ([JMLR](https://jmlr.org/papers/v22/20-303.html); [checklist PDF](https://www.cs.mcgill.ca/~jpineau/ReproducibilityChecklist.pdf)).

### The three hard questions specific to an agent-first PL

**Q1: How do you avoid measuring your own model's ability to game your own benchmark?** Use held-out, adversarially generated problems drawn from a distribution the model authors do not control — freshly filed GitHub issues after the model cutoff, LiveCodeBench-style rolling windows, Riddell-style contamination audits. Recruit independent labs to run the eval — the Shepperd 31% researcher-group effect is your prior. Publish the eval harness and the exact model weights hash / API snapshot per Pineau et al.

**Q2: How do you handle monthly model capability changes?** Version-pin every result to a model snapshot; use open-weights models where possible; report per-snapshot results and a snapshot × task interaction, not a single scalar; adopt "living benchmark" methodology with continuous re-runs against a rolling pool.

**Q3: How do you evaluate a language whose value grows over time as agents get better?** Report a *capability curve*, not a point: (model capability tier) × (task-completion rate on the new language) for multiple tiers. Rust's memory-safety case is the template — Google presented a six-year time series of Android vulnerabilities, not a single snapshot. Pre-register the *hypothesized slope*.

### Honest-practice checklist

Synthesized from the literature:

1. **Pre-register** hypotheses, task set, primary metric, statistical test, and stopping rules before touching the model.
2. **Blind graders** to language identity; report inter-rater agreement.
3. **Contamination audit** every benchmark against training data with surface + semantic matching.
4. **Pin model versions**, publish weight hashes / API dates, report both point and drift.
5. **Report uncertainty**: bootstrap CIs on every reported percentage; the PLDI 2011 baseline is 39 of 42 papers *without* uncertainty.
6. **Independent replication** by ≥ 1 external lab before headline claims.
7. **Full ML reproducibility checklist** (Pineau et al.): data, code, hyperparameters, runs, compute.
8. **Distinguish design effects from process effects**; Ray et al. themselves noted process factors overwhelmingly dominate language effects.
9. **Living benchmark** for LLM tasks: rolling problem pool, published cutoff dates, per-model-snapshot leaderboards.
10. **Effect-size honesty**: report practical magnitude, not just p-values.

---

## Part 6 — What Results Would Move the Field

### Historical landmarks that calibrate ambition

Three prior results anchor what "moving the field" actually looks like.

**CompCert + Csmith (Yang et al. PLDI 2011).** "More than 325 previously unknown bugs" reported to compiler developers, and "the under-development version of CompCert was the only compiler we have tested for which Csmith cannot find wrong-code errors." An outside adversarial team made the CompCert claim credible ([PLDI 2011 preprint](https://users.cs.utah.edu/~regehr/papers/pldi11-preprint.pdf)).

**Rust in Android (Google Security Blog, Sept 2024).** Memory-safety vulnerabilities fell **76% → 24% of total Android vulnerabilities over six years**, with the absolute count falling from 223 in 2019 to under 50 in 2024. The result moved industry policy: CISA, NSA, and the ONCD have since cited Rust adoption as a national-security lever ([Google Security Blog](https://security.googleblog.com/2024/09/eliminating-memory-safety-vulnerabilities-Android.html)).

**AlphaCode (Science 2022).** Median Codeforces ranking of ~54.3% among human competitors. It did not win contests, but it did *credibly participate* in them, and that moved the field ([Science 378, 2022](https://www.science.org/doi/10.1126/science.abq1158)).

### Single most-diagnostic positive experiment

**Adversarial capability curve on freshly-filed, contamination-audited, real-world tasks, run by an independent lab, with a pre-registered slope.**

Choose 200 tasks drawn from GitHub issues filed *after* the model cutoff dates of the largest weights-open and closed-weights model tiers. Contamination-audit each task using Riddell-style matching against known pretraining corpora. Have three independent labs run agents in three languages: the new language, Python, and Rust or TypeScript. Grade with blinded per-task unit tests plus human reviewers who don't know which language produced which patch. Pre-register the hypothesis: *"On tasks not seen during training, task-completion rate in the new language exceeds Python by ≥ 15 absolute percentage points at the frontier model tier, with the gap widening for smaller (weaker) models."*

This design hits every threat to validity from Part 5 at once — contamination, blinding, researcher bias, drift, effect size, independent replication. If the effect holds, it is a direct analog of the CompCert result: outside adversarial testing that a rival could have set up to fail your language.

### Single most-diagnostic falsification

**Berger-style independent reanalysis of the headline dataset.** Publish traces, unit tests, model outputs, grader annotations. Fund an unaffiliated group to reanalyze under a pre-committed protocol. Falsification: if the independent reanalysis finds that the number of languages with a productivity/quality-gain association drops from N to <N/3 (as happened to Ray et al.), or if grader-blinding removes the effect, the thesis is falsified.

A second, cheaper falsifier: adversarial task set. Have a hostile red team construct 100 tasks *designed* to make the new language look worse than Python or Rust. If the language cannot survive this, "wins" on the friendly benchmark are Vitek–Kalibera cherry-picking.

### The 12-month evaluation program (3–5 experiments)

**E1 — Contamination-audited coding benchmark (months 0–3).** Build a fresh 500-problem Verified-style benchmark ([OpenAI SWE-bench Verified](https://openai.com/index/introducing-swe-bench-verified/)) with ≥ 3 human annotators per problem and Riddell-style contamination audit ([arXiv:2403.04811](https://arxiv.org/abs/2403.04811)) against The Stack + Common Crawl. Publish a per-snapshot leaderboard using `lm-evaluation-harness` conventions ([EleutherAI](https://github.com/EleutherAI/lm-evaluation-harness)).

**E2 — Pre-registered head-to-head PL comparison (months 2–6).** Registered report submitted to MSR/EMSE ([Ernst & Baldassarre 2023](https://arxiv.org/abs/2302.03649)). 40 tasks × 3 languages × 3 model tiers × 3 seeds. Blinded graders, published grader IRA. Prechelt confound checks and a Berger-style prospective reanalysis clause built in.

**E3 — Adversarial random program testing (months 3–9).** Csmith-style generator for agent programs in the new language. Test that agents can compile 99%+ of well-typed programs, that undefined-behavior surface is provably empty for the fragment, and that semantics-preserving transformations pass differential test.

**E4 — Longitudinal drift study (months 0–12, continuous).** Weekly re-runs of E1 against 4 model families. Chart the capability × time curve. If the language's advantage widens with capability, that is the AlphaCode-style "moves with the frontier" evidence.

**E5 — Independent replication (months 9–12).** Fund one academic lab to reimplement E1 and E2 end-to-end. Publish the delta.

### The 24-month program (publication-quality at PLDI / POPL / OOPSLA / ICSE / FSE / NeurIPS / ICLR / USENIX Security / S&P)

Adding to the year-one set:

- **E6 — Verified / formal-methods track (PLDI/POPL/OOPSLA).** Mechanized semantics for the language core in Coq/Rocq (Chlipala/Bedrock2 template) or Lean 4. Prove agent-safety properties: capability isolation, deterministic replay, effect containment. Collaborators: Adam Chlipala (MIT PL&V, [adam.chlipala.net](https://adam.chlipala.net/), [mit-plv/bedrock2](https://github.com/mit-plv/bedrock2)); Nadia Polikarpova (UCSD, program synthesis and refinement types, [UCSD profile](https://jacobsschool.ucsd.edu/faculty/profile?id=456)); Andrew Appel (Princeton, Verified Software Toolchain); Xavier Leroy (Collège de France).
- **E7 — Security evaluation (USENIX Security / S&P).** Zeller-style delta debugging + fuzzing applied to agent-generated programs; measure prompt-injection resistance and capability-escape rate versus Python/Rust baselines. Collaborators: Andreas Zeller (CISPA, [profile](https://cispa.de/en/people/zeller)); Rahul Purandare.
- **E8 — Naturalness and LLM-code metrics (NeurIPS/ICLR/ICSE).** Entropy and next-token predictability tests against the [Hindle, Barr, Su, Gabel & Devanbu "Naturalness of Software" baseline](https://web.cs.ucdavis.edu/~devanbu/natural.pdf). Collaborators: Prem Devanbu (UC Davis), Earl Barr (UCL), Baishakhi Ray (Columbia / AWS AI Labs), Sarah Nadi (NYU Abu Dhabi / Alberta).
- **E9 — Real-world agent deployment (FSE-Industry, ICSE-SEIP).** 12-month field study with 50+ developers using agents in the new language on production repos ([Ko, LaToza & Burnett protocol](https://link.springer.com/article/10.1007/s10664-013-9279-3)).
- **E10 — Verification × LLM integration (NeurIPS or ITP).** Combine language verification with LLM proof synthesis. Collaborators: Sean Welleck (CMU, LLMSTEP/Baldur, [Baldur](https://arxiv.org/abs/2303.04910)); Emily First (UCSD/UMass); Talia Ringer (UIUC, [tringer.web.illinois.edu](https://tringer.web.illinois.edu/)); Wenda Li (Cambridge); Yuhuai Wu (Google/xAI).
- **E11 — Full agent-eval integration (ICLR/NeurIPS Datasets & Benchmarks).** Integrate the E1 benchmark into [SWE-agent (Yang et al. arXiv:2405.15793)](https://arxiv.org/abs/2405.15793) and [OpenDevin (Wang et al. arXiv:2407.16741)](https://arxiv.org/abs/2407.16741). Collaborators: Ofir Press, John Yang, Kilian Lieret (Princeton NLP); Graham Neubig (CMU, OpenHands); Chi Wang ([AutoGen](https://microsoft.github.io/autogen/)).
- **E12 — HELM-style holistic evaluation (NeurIPS).** Multi-dimensional scoring against [Stanford CRFM's HELM (Liang, Bommasani et al. arXiv:2211.09110)](https://arxiv.org/abs/2211.09110).

### The frontier working on this in 2024–2026

Software engineering research: Christian Bird (Microsoft Research), Earl Barr (UCL), Bertrand Meyer (Constructor Institute), Andreas Zeller (CISPA), Prem Devanbu (UC Davis), Sarah Nadi (NYU Abu Dhabi / Alberta), Rahul Purandare, Baishakhi Ray (Columbia / AWS AI Labs).

PL and verification: Adam Chlipala (MIT), Nadia Polikarpova (UCSD), Andrew Appel (Princeton), James Wilcox and Zachary Tatlock (Certora, ex-UW), Xavier Leroy (Collège de France).

LLM + code: Percy Liang and Rishi Bommasani (Stanford CRFM/HELM), Denny Zhou (Google DeepMind), Yuhuai Wu, Chenglong Wang (Microsoft Research), Jonas Gehring (Meta AI, Code Llama), Yujia Li (Google DeepMind, AlphaCode).

Agent evaluations: Ofir Press, John Yang, Kilian Lieret (Princeton NLP, SWE-bench, SWE-agent); Graham Neubig (CMU, OpenHands); Chi Wang (Google DeepMind, formerly Microsoft AutoGen).

Benchmarks: BigCode Project (Loubna Ben Allal, Leandro von Werra, HF + ServiceNow), [bigcode-project.org](https://www.bigcode-project.org/); EleutherAI (lm-evaluation-harness).

Verification × LLM: Talia Ringer (UIUC), Emily First (UCSD/UMass), Sean Welleck (CMU), Wenda Li (Cambridge/Edinburgh).

### What would actually convince the field

A credible, publishable, hard-to-dismiss result for an agent-first PL requires the intersection of:

1. **Adversarially collected, contamination-audited task set** (defeats Riddell/Sainz).
2. **Blinded, independent grading with published IRA** (defeats Shepperd 31% researcher-group effect).
3. **Pre-registered hypothesis with a stated effect-size floor** (defeats Berger-style "flaws erode 11 → 4 languages").
4. **Capability × model-tier curve, not a point** (defeats Chen–Zaharia–Zou drift; matches Rust/Google Android time-series template).
5. **Independent replication by a rival lab** (matches the Berger community-accepted standard).
6. **Full ML reproducibility-checklist compliance** (Pineau et al. NeurIPS 2019).
7. **A CompCert-style adversarial red-team result** — someone external tries hard to break the language's core safety/agent claim and fails.

If a paper does all seven, PLDI/POPL/OOPSLA/ICSE/FSE will take it seriously. If it does the first three plus a compelling capability curve, NeurIPS/ICLR Datasets & Benchmarks will accept the eval as a contribution. If it also has a security red-team result, USENIX Security and S&P open up.

The single most-cited-in-a-decade outcome, in the Rust/CompCert mold, would be: *"Six years and 50,000 production developers later, defect rates in code generated by frontier agents targeting language X are half those of Python, on tasks known to be outside training data, replicated by three independent labs, with the gap widening at every capability tier."*

---

## Part 7 — Synthesis: If This Project Were Being Run

This section is the report's opinionated recommendation, separated from the evidence.

### The five experiments to run in the first year, in order

1. **Cold-start / training-data gravity (Experiment 2).** Do this *first*, before anything else. The Giagnorio result (9% average pass@1 for no-resource languages, 0–1% on hard tasks) is the current empirical starting point. If the ablation ladder does not close ≥ 60% of the gap between "base model on Mo" and "base model on Python" on translated HumanEval+, the rest of the program is speculative. This experiment is compute-cheap, mostly automated, and takes ~4 weeks to run. It sets the ceiling for everything that follows.
2. **Null-hypothesis experiment (Experiment 1).** This is the study a hostile reviewer will demand. Include the vanilla-Python floor and the four bolted-on baselines. Commit publicly to the all-three-of-three threshold (5 pp task success + 15% relative defect reduction + non-inferior iteration count) before running. Half the credibility of the entire program comes from being willing to fail this experiment.
3. **Defect study — real-bug corpus replay (Experiment 5).** This is the direct analog of the Chromium and Android Rust before/after data. It is the only experiment in the program that can plausibly produce a Rust-style "eliminate a whole defect class" headline. Even if Experiment 1 comes in mixed, a strong defect-study result changes the strategic conversation.
4. **Agent-friendliness feature ablation (Experiment 7).** Adversarial pre-registration is essential here — commit in advance to reporting all six factors even if some are null or negative. Publishing that "capability-checked effects and structured diagnostics matter, deterministic simulation does not" is far more useful than publishing another "Mo works" claim.
5. **Human review at spec altitude (Experiment 4).** This is the experiment that generates the single most important artifact for the language's *positioning*: the answer to "can humans review Mo code by reading the intent layer alone?" A positive result here is what makes Mo *habitable* for teams; a negative result forces a redesign of the review workflow before Experiment 3's longitudinal study runs.

The maintainability study (Experiment 3) and the token-cost study (Experiment 6) run in parallel with the above but their headline results land at month 6 and month 3 respectively.

### The thresholds the project should commit to publicly, in advance

- **Experiment 1 (null-hypothesis):** all three of {≥ 5 pp task-success delta over the best baseline; ≥ 15% relative defect-rate reduction; ≤ 15% higher iteration-count median}.
- **Experiment 2 (cold-start):** monotone-increasing ablation ladder with each rung ≥ +3 pp; ≥ 60% gap-closure at the top rung; ≥ 90% retry-saturation by n = 5.
- **Experiment 3 (maintainability):** median time-to-modify ≤ 0.80× baseline; regressions/ticket ≤ 0.60× baseline; comprehension quiz ≥ +1.0 raw point.
- **Experiment 4 (spec-altitude review):** ≥ 90% of body-review defect detection at ≤ 60% of the time; comprehension non-inferior at Δ ≥ −0.5.
- **Experiment 5 (defect corpus):** combined static + runtime catch ≥ 60% overall; static-only ≥ 40%; false-positive rate on post-fix ≤ 5%.
- **Experiment 6 (tokens):** amortized-total ratio ≤ 1.25× at batch 50; marginal per-task ratio ≤ 0.90×; cost-per-success ratio ≤ 1.10×.
- **Experiment 7 (ablation):** ≥ 3 of 6 factors with main effect ≥ +3 pp FDR-corrected; factor ranking stable across models (Kendall τ ≥ 0.6).

Publish all seven thresholds on the project site before any results run. This is the single largest credibility multiplier available.

### Two or three things that would make this evidence more credible than any prior agent-language evaluation

1. **Independent replication built into the pre-registration.** Berger et al. was retrospective; the Ray et al. team did not commission it. This project should commission it in advance — fund one academic lab (CISPA, CMU, UCSD, UCL, or Princeton NLP are all plausible) to reproduce Experiments 1 and 5 end-to-end without the project team's help, and publish the delta. This has never been done in an agent-language evaluation.
2. **A hostile-lab adversarial task set.** Pay a rival team — someone with a stake in the "just use Python + tooling" position — to construct 100 tasks *designed* to make Mo look worse than Python on the same protocol. Publish those results alongside the friendly benchmark. This is the analog of Csmith attacking CompCert: it is what makes the CompCert claim credible thirteen years later.
3. **A capability × time curve, not a snapshot.** The Android/Rust six-year time series is the reason that story moved industry policy. Commit to a weekly re-run of the contamination-audited benchmark for the full 24 months and publish the curve. Pre-register the hypothesized slope. This is what "a language whose value grows with agents" actually looks like as evidence.

### Fatal mistakes to avoid

- **Building the evaluation harness on top of SWE-bench Verified as the primary benchmark.** OpenAI's own 138-sample audit found 59.4% material issues plus direct contamination. Any Mo score against Verified is now a lower-bound-quality data point at best. Use Verified as one stratum inside a bigger, held-out, contamination-audited task set that the project builds itself.
- **Author-grading the human studies.** The Shepperd 31% researcher-group effect is not a small correction — it is larger than every "type systems reduce bugs" effect in the entire empirical PL literature combined. Blind the graders and publish the inter-rater agreement statistics.
- **Reporting a single-model, single-snapshot number.** The Chen–Zaharia–Zou GPT-4 drift result (84% → 51% in three months on a fixed task) shows that a snapshot is scientifically meaningless. Version-pin, use open-weights checkpoints where available, and report per-snapshot results.
- **Chasing "our language is safer" as a headline.** Berger et al. shows that this claim does not survive careful reanalysis in the general case. What *does* survive is "eliminates class X of bugs by construction, verified across N tasks in the Chromium/Android format" — an architecturally specific, defect-class-elimination claim, not a general safety claim.
- **Publishing cross-language LLM performance numbers without publishing the harness and reproducing them per-language.** Dan Luu's `pl-tokens` work shows a widely-cited prior benchmark had test-harness bugs that produced false Rust failures. The state of the art in blog-post benchmarks is unreliable enough that harness + per-language reproduction is a hard requirement.
- **Using the Elixir/Erlang "nine 9s" figure as a threshold anchor.** It does not appear to trace to a peer-reviewed primary source. If it does surface during data collection, it can be used as motivational context only, not as an evidentiary anchor.
- **Treating "Mo direct-write pass rate" as the only metric.** Quasar's authors ran into exactly this — LLMs cannot write QUASAR directly, so their evaluation reports transpile-from-Python and safety-property counts as first-class metrics. Mo's evaluation should structurally match: direct-write, transpile-from-Python, and safety-property metrics all reported.

### The one non-obvious opportunity

The Vericoding cross-language result — Dafny 82%, Verus/Rust 44%, Lean 27% under identical LLM harness — is currently the strongest single piece of evidence in the entire literature that language design directly determines how much of a verification an agent can do. This is a fresh, primary-source result (September 2025) that no prior agent-language project has built on because it is too new. A Mo evaluation that positions itself as the first system to move the Vericoding-style curve — "under the same LLMs and the same harness, agent + Mo produces ≥ 90% first-pass verified programs on tasks where Dafny sits at 82%" — is a *specific*, *falsifiable*, *primary-source-anchored* claim with a large ceiling and a well-defined baseline. It also lands in a conference audience (PLDI/POPL/OOPSLA and CAV/ITP) that is receptive to language-design-as-verification-lever arguments and unsympathetic to naive "our language reduces bugs" claims. That is the single opportunity most worth building the year-one evaluation program around.

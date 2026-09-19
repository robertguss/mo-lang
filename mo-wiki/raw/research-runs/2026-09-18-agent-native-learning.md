---
source_url: https://ampcode.com/user-content/attachments/2e8d753513f09b2a52d4d459bb0639cab187daa50d2b1583432f8bfeb1ba4a22-Teaching-agents-an-unfamiliar-language-what-to-load-up-front-what-to-retrieve-on-demand.md
ingested: 2026-09-18
sha256: a0097267d51db3c5971a5dcd7fc1048303e816a6caa0dbadf1dd7ac408704159
---
# Teaching agents an unfamiliar language: what to load up front, what to retrieve on demand

Compact synthesis of published evidence on how LLM-based coding agents pick up a language or library they were not trained on — via compiler feedback, short primers, worked examples, and demand-driven documentation. Structured for the Mo onboarding decision: what goes in the initial system context, and what should sit behind a lookup tool.

## Bottom line

Six findings recur across the literature and together give a defensible default for Mo:

1. **Compiler feedback alone fixes compilation, not behavior.** A controlled study across 16 models (135M–70B) on 699 C tasks measured a 5.3–79.4 percentage-point rise in compilation success from adding a gcc feedback loop, with syntax errors down 75% and undefined-reference errors down 87%, while the number of behaviorally correct solutions did not change meaningfully across three RosettaCode tasks reviewed by hand ([From LLMs to Agents in Programming](https://web3.arxiv.org/pdf/2601.12146)).
2. **Tests are the highest-signal feedback; raw compiler messages are middle-of-the-pack; "human" natural-language critiques are worst.** FeedbackEval Repair@1 averaged across five frontier models: test feedback 61.0%, simple feedback 56.9%, compiler feedback 55.8%, human feedback 50.5% ([FeedbackEval](https://arxiv.org/html/2504.06939v1)).
3. **Retrieved documentation moves behavioral pass rates, not just compile rates.** DocPrompting lifts CodeT5 execution-based pass@1 by 2.85 points (a 52% relative gain) on CoNaLa ([DocPrompting](https://arxiv.org/abs/2207.05987)); version-aware RAG on evolving APIs adds up to 14.2 F1 for GPT-4o-mini on Matplotlib and up to 8.87 F1 for Mistral-7B ([LibEvolutionEval](https://arxiv.org/html/2412.04478)); ARKS/EvoR reports "two to four times of execution accuracy" over baseline RAG on modified libraries and long-tail languages ([ARKS](https://ar5iv.labs.arxiv.org/html/2402.12317)).
4. **Small open models can learn a genuinely unseen language in-context.** On Isabelle (a formal-proof language "chosen partly because there is limited data available for it on the internet"), Llama-2 and StarCoder learn from demonstrations without fine-tuning; keyword descriptions alone give GPT-4/GPT-3.5 non-trivial performance, unpaired programs saturate the gain around 5–7 examples, and randomising keyword strings barely hurts — models don't rely on the surface names of the keywords ([Evaluating In-Context Learning of Libraries](https://ar5iv.labs.arxiv.org/html/2311.09635)).
5. **Excessive context hurts.** Feeding the full source file rather than the targeted erroneous snippet dropped industrial CodeLlama-7B/Falcon-7B/Bloom-7B/CodeT5+ CI-fix pass rates to 8–19%, versus 47–49% for "error log + erroneous snippet" — and the paper explicitly warns: "Excessive information (e. g., full files) lowers performance." Best configuration reached 63% ([How LLMs fix compilation errors in large industrial codebases](https://arxiv.org/html/2510.13575v1)).
6. **Repair loops plateau fast — around 3 iterations.** Across four open 7B models on the industrial CI corpus, gains stopped between iterations 3 and 5; a small 4B model with a compiler loop can pull within touching distance of a 70B model without one, and Qwen 3 4B ran 18% → 97.4% compilation with the loop ([From LLMs to Agents in Programming](https://web3.arxiv.org/pdf/2601.12146)).

Practical translation for Mo: keep the initial prompt short and structured (grammar sketch, effect/capability cheatsheet, 5–7 idiomatic examples, one worked round-trip through `moc`). Put everything else — stdlib docs, brick catalogues, error explanations, similar-code lookup — behind a documentation-retrieval tool. Wire a test-driven feedback loop for behavioral correctness and a compiler feedback loop for surface fixes. Cap the loop at ~3 iterations. Expect the loop to add tens of points on "compiles" and much less on "does the right thing" unless tests or executable examples are in the loop too.

## 1. The compile-versus-behavior separation is the load-bearing distinction

The literature keeps two failure modes apart and repeatedly finds that different interventions solve them.

### Compiler feedback dramatically lifts *compilation*

The clearest quantitative separation comes from a 16-model study that measured compilation deltas independently of semantic scores. The agent template was minimal: role prompt, task, up to five iterations, each iteration re-fed with `{CODE}` and the raw gcc error log ([From LLMs to Agents in Programming](https://web3.arxiv.org/pdf/2601.12146)).

Compilation lifts (RosettaCode C, 699 tasks, one-shot baseline vs. compiler agent):

| Model | Baseline compile | Agent compile | Δ |
|---|---:|---:|---:|
| SmolLM 2 135M | 2.9% | 12.7% | +9.8 pp |
| SmolLM 2 360M | 7.4% | 25.5% | +18.1 pp |
| Gemma 2 2B | (not shown) | (large) | up to +79.4 pp reported overall |
| Code Llama 7B | 48.2% | 78.8% | +30.6 pp |
| Qwen 3 4B | 18.0% | 97.4% | +79.4 pp |
| Llama 3.3 70B | (high) | 99.9% | small headroom |

Every one of the 16 models improved on compilation; not one regressed. Syntax errors fell 75.5%, undefined references 86.8%, and language-mismatch errors 43.6% — a common baseline failure was "the model was asked for C and produced Python" ([From LLMs to Agents in Programming](https://web3.arxiv.org/pdf/2601.12146)).

### The same feedback moves behavior far less

The same paper reviewed representative tasks by hand and reported that "the number of correct solutions is not significantly different, indicating that the functionality of the code generated by the agent does not differ considerably from that of the baseline models" ([From LLMs to Agents in Programming](https://web3.arxiv.org/pdf/2601.12146)). Some small models even lost surface similarity on ROUGE/BLEU/CodeBERTScore after the loop (Gemma 3 1B ROUGE-1 0.268 → 0.217; SmolLM 2 135M CodeBERT precision 0.641 → 0.615) — the code compiled but drifted from the reference.

A survey of self-repair reached the same conclusion at higher scale: gains are "often marginal and quite inconsistent … sometimes not present at all," and are bottlenecked by the model's ability to critique its own code; substituting a stronger feedback source (a stronger model, or a human) produced substantially larger gains ([Is Self-Repair a Silver Bullet for Code Generation?](https://openreview.net/forum?id=y0GJXRungR)).

### Tests, when available, are the strongest feedback

FeedbackEval measured Repair@1 across five frontier models and four feedback types on HumanEval and CoderEval:

| Feedback type | Avg Repair@1 |
|---|---:|
| Test | 61.0% |
| Simple ("please fix") | 56.9% |
| Compiler | 55.8% |
| Human (NL critique) | 50.5% |

Test feedback wins on every model. Compiler feedback is roughly on par with a bare "please fix" instruction, which lines up with the C-agent result: the compiler tells you the code parses and links, not that it does the right thing ([FeedbackEval](https://arxiv.org/html/2504.06939v1)).

### Practical translation for Mo

- Treat the `moc` compiler loop as a **compile-success intervention** and cap the iteration count around three; industrial CI-fix pass rates flatten between iterations 3–5 for CodeLlama/Falcon/Bloom/CodeT5+ ([How LLMs fix compilation errors in large industrial codebases](https://arxiv.org/html/2510.13575v1)).
- Wire executable examples or a synthesized test into the feedback surface if you want the loop to actually move behavioral correctness. This is what ARKS/EvoR does (execution feedback on LLM-generated tests) and it reports 2–4× execution accuracy over static RAG ([ARKS](https://ar5iv.labs.arxiv.org/html/2402.12317)).
- Report the two metrics separately in Mo's generation/erosion studies. RQ-level "compile rate" and "test pass rate" are different phenomena and interventions optimize them differently.

## 2. Retrieval-augmented docs is the biggest win specifically for unfamiliar APIs

Retrieval attacks a different failure than compiler feedback: the model doesn't know the target library well enough to produce a plausible attempt in the first place.

- **DocPrompting** (retrieve docs → generate): +2.85 pass@1 (52% relative) and +4.39 pass@10 (30% relative) for CodeT5 on Python CoNaLa ([DocPrompting](https://arxiv.org/abs/2207.05987)).
- **LibEvolutionEval** (version-specific completion of eight libraries, incl. torch and matplotlib, across their release history) shows that version-aware RAG consistently beats version-aware prompting, which beats plain in-file completion. Every one of six (model, library) cells improves under RAG; deltas from in-file to version-aware-RAG:

  | Model | PyTorch | Matplotlib |
  |---|---:|---:|
  | StarCoder2-7B (FIM) | +4.5 | +5.7 |
  | Mistral-7B (left context) | +1.8 | +8.87 |
  | GPT-4o-mini (instruction + 1 example) | +5.84 | +14.2 |

  Retrieved bundle: API signatures, names, types, mandatory/optional parameters, usage examples, natural-language descriptions; top-3 hits ([LibEvolutionEval](https://arxiv.org/html/2412.04478)).
- **ARKS/EvoR** (Scipy/Tensorflow with post-cutoff API changes, plus long-tail Ring and Pony) reports "two to four times of execution accuracy" using active retrieval over evolving knowledge (documentation, code snippets, execution feedback, and web search combined). EvoR's default excludes web search because it "contains large portions of noisy information" and "only marginally improves the results" — a real finding about content quality, not retrieval per se ([ARKS](https://ar5iv.labs.arxiv.org/html/2402.12317)).
- **Gorilla** replaces most of the API-call hallucination problem with retriever-aware training; the retriever also lets the model track "test-time document changes" — i.e. it handles APIs the base model has never seen ([Gorilla](https://arxiv.org/abs/2305.15334)).
- **CodeRAG-Bench** finds that retrieval helps "in various settings" but flags two current bottlenecks: retrievers miss when lexical overlap is low, and generators fail to use extra context under tight budgets — a warning about how tightly Mo should format the retrieved bundle ([CodeRAG-Bench](https://arxiv.org/abs/2406.14497)).

Two consistent format lessons across these studies:

- Retrieved bundles are structured (signature + types + parameters + short NL description + usage snippet), not full pages. LibEvolutionEval uses top-3, formatted as commented code placed before the left context. RepoCoder caps retrieved code at half the prompt and pulls at most 10 snippets ([RepoCoder](https://aclanthology.org/2023.emnlp-main.151.pdf)).
- What you retrieve should be picked by the *task*, not by the query alone. RepoCoder's iterative retrieval (use the model's prior draft as the next query) and ARKS's LLM-generated query beat vanilla one-shot retrieval, because the second-round query reflects what the model actually needs to finish the function.

## 3. Learning a genuinely unseen language in-context

Two studies zoom in on the "the model has essentially never seen this" case.

**ICL for esoteric programming languages** ([Openreview](https://openreview.net/pdf/00ce834667c5790f9c1f2d812a599f561d5f2620.pdf)) evaluates GPT-4o, GPT-4o-mini, Llama-3.3-70B-Instruct-Turbo, and DeepSeek V3 on four esolangs — Minipy, Pyth, 0815, Rhokell — chosen to have 1,000-10,000× fewer online examples than Python. Zero-shot familiarity is essentially nil ("For the code identification task none of the models were able to correctly identify the programming language from the code examples"). With documentation and verified examples inserted iteratively into the prompt, accuracy climbs, then plateaus. No case is reported where documentation/examples reduced accuracy. Raw online prevalence is *not* the best predictor of ICL success — syntactic similarity to Python and the documentation actually put in the prompt matter more.

**Evaluating In-Context Learning of Libraries for Code Generation** ([arXiv](https://ar5iv.labs.arxiv.org/html/2311.09635)) is the most Mo-relevant paper in this sweep. It tests LLaMA-2, StarCoder, GPT-3.5-Turbo, and GPT-4 on (a) a wholly-novel 20-module vision library (VisProg) and (b) Isabelle proofs. Key findings:

- Small open models (LLaMA-2, StarCoder) learn a novel 20-module library from demonstrations without any fine-tuning.
- GPT-4 learns from natural-language *descriptions* or from raw *implementations* at parity with demonstrations.
- Format-by-family effects: LLaMA benefits more from descriptions; StarCoder benefits more from implementations. "Choose the supervision format based on model pretraining."
- For Isabelle (unfamiliar language, not just unfamiliar library), unpaired programs "saturate after 5–7 examples," and models "do not depend strongly on keyword semantics when learning a new programming language in-context" — random keyword aliases barely hurt.
- Description-based learning (12 Isabelle keywords, each explained briefly) delivers non-trivial performance *without any paired demonstrations*. This is the strongest evidence that a short, well-organized keyword/effect cheatsheet earns its place in the initial prompt.

Small models still work well on constrained-syntax tasks. **Grammar Prompting** attaches a specialized BNF grammar (minimally sufficient for each demonstration's output) to each example, then makes the model predict a BNF for the test input before emitting output; the authors report competitive DSL generation across SMCalFlow, GeoQuery, PDDL, and SMILES with in-context learning only ([Grammar Prompting](https://arxiv.org/abs/2305.19234)). For Mo specifically, this argues for shipping a machine-readable Mo grammar sketch (or a "grammar of the Mo you'll write today" subset per task) alongside examples.

## 4. Small and cheap models: the evidence

- **Compile-loop leverage is largest for small models.** SmolLM 2 135M went from 2.9% → 12.7% compile pass; Qwen 3 4B from 18% → 97.4%; and "in some cases, smaller models with a compiler outperform larger models with a compiler." The authors specifically flag Qwen 3 4B as a laptop-runnable substitute for larger models when a compiler loop is available ([From LLMs to Agents in Programming](https://web3.arxiv.org/pdf/2601.12146)).
- **Small open coders can learn novel libraries in-context.** LLaMA-2 and StarCoder learn the 20-module VisProg library from demonstrations without fine-tuning; the ability is "not limited to the largest proprietary models" ([Evaluating ICL of Libraries](https://ar5iv.labs.arxiv.org/html/2311.09635)).
- **The scaling premium is expensive.** Assessing SLMs from 0.4B–10B: Qwen2.5-Coder 7B beats 1.5B by 20.4% relative on HumanEval pass@1 (65% vs 54%) — at 261% higher VRAM (23.7 GB vs 6.55 GB). 3B is a middle ground: 59% pass@1, 10.8 GB. OpenCodeInterpreter 6.7B reaches 67% pass@1 ([Assessing Small Language Models for Code Generation](https://arxiv.org/html/2507.03160v4)).
- **SLM ensembles as judges beat single big-model generation.** DeepSeek-Coder 1.3B, OpenCoder 1.5B, Qwen2.5-Coder 3B, Phi-4 mini, Gemma-3 4B — used together to select among candidate implementations — recover a good fraction of the quality gap versus larger models on multilingual code generation ([SLM-as-Judge](https://arxiv.org/html/2602.11911v1)).
- **Low-resource languages remain hard even for large models.** Julia, Lua, R, Racket pass@1 sit well below Python for every model tested; fine-tuning on a Python→target parallel corpus and translation-rule prompts help, but the gap does not close ([Enhancing Code Generation for Low-Resource Languages](https://arxiv.org/html/2501.19085v1)). Mo, until its corpus grows, sits closer to Racket than to Python for a base model.

The pattern: a 3–4B open coder with a compiler+test loop and a good retrieval tool is a defensible cheap-tier target for Mo authoring, provided the language is presented well in-context and the compiler feedback is machine-readable.

## 5. Concrete guidance for Mo: initial context vs. retrieval

The literature does not give one prescription, but three consistent formatting lessons apply.

### Ship in the initial prompt (small, task-independent, high-signal)

- **Grammar sketch, task-specialized.** A BNF/EBNF subset "minimally sufficient" for the class of task at hand. Grammar Prompting shows this works even when the LLM predicts the specialized grammar itself before emitting code ([Grammar Prompting](https://arxiv.org/abs/2305.19234)).
- **Keyword/effect/capability cheatsheet with one-line descriptions.** For Isabelle, 12 keyword descriptions were enough for description-only ICL to work ([Evaluating ICL of Libraries](https://ar5iv.labs.arxiv.org/html/2311.09635)). Mo's `effects`, `capabilities`, `never`/`invariant`, contract syntax, and diagnostic tags belong here.
- **5–7 idiomatic worked examples.** Unpaired examples in the target language saturated Isabelle ICL around 5–7 ([Evaluating ICL of Libraries](https://ar5iv.labs.arxiv.org/html/2311.09635)); esolang studies report diminishing returns after a small number of verified examples ([ICL for Esoteric PLs](https://openreview.net/pdf/00ce834667c5790f9c1f2d812a599f561d5f2620.pdf)).
- **One "hello, Mo" round-trip.** A single example that shows source → `moc` invocation → stable diagnostic on a deliberate error → fix → runtime event ring output. This grounds the agent in the joint language/runtime story the Mo wiki page describes ([[projects/mo-lang]]).
- **Format the whole bundle in the style the target family responds to.** LLaMA-family prefers natural-language descriptions; StarCoder-family prefers implementations ([Evaluating ICL of Libraries](https://ar5iv.labs.arxiv.org/html/2311.09635)). Mo's tests across models should log which format each family reads best and route accordingly.

### Retrieve on demand (large, task-specific, updates over time)

- **Standard library and brick documentation.** Structured entries — API name, signature, parameter table, one-line NL description, one usage snippet — top-K around 3 hits per query, following LibEvolutionEval's format. Retrieval helped in 6/6 (model, library) cells for version-specific completion ([LibEvolutionEval](https://arxiv.org/html/2412.04478)).
- **Similar-code and prior-fix snippets, ranked by task.** RepoCoder-style iterative retrieval (use the current draft, not the natural-language intent, as the next query) once the agent has an initial attempt ([RepoCoder](https://aclanthology.org/2023.emnlp-main.151.pdf)).
- **Compiler-error explanations, matched by stable diagnostic ID.** Mo's stable diagnostics are the natural retrieval key. Historical human fixes indexed per error type worked well in the industrial CI-fix study (up to +18 pp when combined with the erroneous snippet, model-dependent) ([How LLMs fix compilation errors](https://arxiv.org/html/2510.13575v1)).
- **Runtime event traces and test failures.** Once the code runs, the queryable runtime is the retrieval source. Test feedback outperformed all other feedback in FeedbackEval ([FeedbackEval](https://arxiv.org/html/2504.06939v1)); ARKS/EvoR's execution-feedback loop delivered its 2–4× gain ([ARKS](https://ar5iv.labs.arxiv.org/html/2402.12317)).

### Keep out of the initial context

- **Full source files or full API docs**, unless the file is small and directly relevant. The industrial CI-fix study is explicit: full source dropped pass rates to 8–19% vs 47–49% for targeted snippet + log ([How LLMs fix compilation errors](https://arxiv.org/html/2510.13575v1)).
- **Unfiltered web content.** ARKS/EvoR excluded web search by default in its recommended configuration ([ARKS](https://ar5iv.labs.arxiv.org/html/2402.12317)).
- **Free-form natural-language critiques as a substitute for tests.** "Human"-style critiques were the worst feedback format tested in FeedbackEval ([FeedbackEval](https://arxiv.org/html/2504.06939v1)) and the qualitative concern in the self-repair survey ([Is Self-Repair a Silver Bullet?](https://openreview.net/forum?id=y0GJXRungR)).

### Loop discipline

- Feed **(prior code + structured diagnostic + minimal relevant retrieved context)** each iteration — this triple beat all six other combinations across CodeLlama, CodeT5+, Falcon, and Bloom in the industrial study ([How LLMs fix compilation errors](https://arxiv.org/html/2510.13575v1)).
- **Cap at three iterations.** The same industrial study saw no significant gain beyond iteration 3 in most configurations; the C-agent study reports diminishing per-iteration change (Gemma 3 27B iteration 3→4: 0.1 rows changed on average) ([From LLMs to Agents in Programming](https://web3.arxiv.org/pdf/2601.12146)).
- **Terminate on repeated identical error.** ARKS/EvoR terminates on "the same error in three consecutive iterations" ([ARKS](https://ar5iv.labs.arxiv.org/html/2402.12317)) — a good default for Mo when `moc` reports the same stable diagnostic twice in a row.

## 6. Direct implications for Mo's evaluation lane

- **Report compile-rate and test-pass-rate separately** in the generation and erosion studies. The C-agent paper shows models can go from 18% to 97% compilation without semantic improvement; a headline number that mixes them will misattribute wins to Mo's runtime when the actual mechanism is compiler pressure ([From LLMs to Agents in Programming](https://web3.arxiv.org/pdf/2601.12146); [FeedbackEval](https://arxiv.org/html/2504.06939v1)).
- **Test the null hypothesis with a compiler-loop-only agent.** A 4B model with a `moc` loop is a serious baseline for compile-success on Mo. If Mo's language guarantees don't shift the *behavioral* metric on top of that, the language claim is not what's carrying the win.
- **Instrument a "small model tier" in every generation study.** Qwen2.5-Coder 1.5B/3B/7B, DeepSeek-Coder 1.3B/6.7B, OpenCoder 1.5B, Phi-4 mini, Gemma-3 4B are the standard SLM comparison set in the recent literature ([SLM-as-Judge](https://arxiv.org/html/2602.11911v1); [Assessing SLMs for Code Generation](https://arxiv.org/html/2507.03160v4)). If Mo's model-agnostic story holds, a 3–4B model with Mo's initial-prompt bundle plus retrieval tool should show measurable lift over the same model on a matched Go or Elixir corpus.
- **Prefer test-feedback loops for the runtime-effectiveness claim.** Mo's queryable runtime with structured events is the natural implementation of "test feedback" and "execution feedback" — the two feedback families that actually move behavioral pass rates ([FeedbackEval](https://arxiv.org/html/2504.06939v1); [ARKS](https://ar5iv.labs.arxiv.org/html/2402.12317)).
- **Use stable diagnostic IDs as retrieval keys.** The industrial CI-fix study got its largest deltas from combining the erroneous snippet with a matched historical fix example ([How LLMs fix compilation errors](https://arxiv.org/html/2510.13575v1)). Mo's stable diagnostic identifiers turn that into a first-class API rather than an ad-hoc grep.

## Gaps in the literature relative to Mo's question

Three questions the papers don't answer well:

- **No paper isolates the marginal value of a machine-readable diagnostic** (structured error record with an ID, a source span, and a suggested-fix hint) versus raw compiler text, for the same model. This is exactly Mo's proposition. It is a defensible in-house study for the Mo repository.
- **No paper reports how initial-context size trades off against retrieval breadth** under a fixed token budget, for the "learn an unseen language" setting. LibEvolutionEval fixes total context and finds RAG helps; ICL-for-libraries fixes format and finds descriptions/implementations/demonstrations all work; nothing combines the two axes.
- **Small-model retrieval-integration failure is under-quantified.** CodeRAG-Bench flags that "generators fail to improve with limited context lengths or abilities to integrate additional contexts" ([CodeRAG-Bench](https://arxiv.org/abs/2406.14497)), but does not name the models. For Mo's cheap-tier target this is the failure mode most worth stress-testing directly.

## References

- [DocPrompting: Generating Code by Retrieving the Docs](https://arxiv.org/abs/2207.05987) — retrieval-augmented code generation with documentation; +2.85 pass@1 (52% rel) on CoNaLa.
- [RepoCoder: Repository-Level Code Completion Through Iterative Retrieval and Generation](https://aclanthology.org/2023.emnlp-main.151.pdf) — iterative retrieval using the model's own draft as the next query.
- [Self-Refine: Iterative Refinement with Self-Feedback](https://arxiv.org/abs/2303.17651) — test-time, training-free self-critique loop.
- [Self-Edit: Fault-Aware Code Editor for Code Generation](https://arxiv.org/abs/2305.04087) — 89% / 31% / 48% relative pass@1 gains on APPS-dev / APPS-test / HumanEval across nine models 110M–175B.
- [Is Self-Repair a Silver Bullet for Code Generation?](https://openreview.net/forum?id=y0GJXRungR) — self-repair gains are marginal and inconsistent; stronger feedback source is the bottleneck.
- [From LLMs to Agents in Programming: The Impact of Providing an LLM with a Compiler](https://web3.arxiv.org/pdf/2601.12146) — 16-model C RosettaCode study; +5.3–79.4 pp compile, 75% fewer syntax errors, behavior unchanged.
- [In-Context Learning for Esoteric Programming Languages](https://openreview.net/pdf/00ce834667c5790f9c1f2d812a599f561d5f2620.pdf) — Pyth, 0815, Minipy, Rhokell; docs+examples help, prevalence is not the best predictor.
- [Evaluating In-Context Learning of Libraries for Code Generation](https://ar5iv.labs.arxiv.org/html/2311.09635) — LLaMA-2 and StarCoder learn novel 20-module lib; Isabelle unpaired examples saturate at 5–7; keyword-aliasing barely hurts.
- [Grammar Prompting for DSL Generation with LLMs](https://arxiv.org/abs/2305.19234) — specialized BNF grammar per example; competitive on SMCalFlow, GeoQuery, PDDL, SMILES.
- [How LLMs Fix Compilation Errors in Large Industrial Codebases](https://arxiv.org/html/2510.13575v1) — 40K CI errors; up to 63% CI pass; full source hurts (8–19%); best is "log + snippet [+ historical fix]".
- [LibEvolutionEval: A Benchmark and Study for Version-Specific Code Generation](https://arxiv.org/html/2412.04478) — version-aware RAG lifts F1 by up to 14.2 for GPT-4o-mini on Matplotlib.
- [Gorilla: Large Language Model Connected with Massive APIs](https://arxiv.org/abs/2305.15334) — retriever-aware training; surpasses GPT-4 on API-call writing; adapts to test-time doc changes.
- [CodeRAG-Bench: Can Retrieval Augment Code Generation?](https://arxiv.org/abs/2406.14497) — retrieval helps but retrievers miss on low lexical overlap and generators struggle under tight budgets.
- [ARKS: Active Retrieval in Knowledge Soup for Code Generation](https://ar5iv.labs.arxiv.org/html/2402.12317) — 2–4× execution accuracy over baseline RAG; excludes noisy web search by default; terminates on repeated identical error.
- [Improving Code Generation via Small Language Model-as-Judge](https://arxiv.org/html/2602.11911v1) — DeepSeek-Coder 1.3B, OpenCoder 1.5B, Qwen2.5-Coder 3B, Phi-4 mini, Gemma-3 4B ensemble as judges.
- [Assessing Small Language Models for Code Generation](https://arxiv.org/html/2507.03160v4) — 20 SLMs 0.4B–10B on HumanEval, MBPP, Mercury, HumanEvalPack, CodeXGLUE; Qwen2.5-Coder scaling premium.
- [Enhancing Code Generation for Low-Resource Languages](https://arxiv.org/html/2501.19085v1) — R, Racket, Julia, Lua translation examples and rules; low-resource gap persists.
- [FeedbackEval: A Benchmark for Evaluating LLMs on Repair with Different Feedback Types](https://arxiv.org/html/2504.06939v1) — Test 61.0% > Simple 56.9% > Compiler 55.8% > Human 50.5% Repair@1 across five frontier models.

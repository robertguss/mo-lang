---
source_url: https://robotsatlas.com/posts/moonbit-jezyk-programowania-pod-ere-ai-z-chin
ingested: 2026-09-12
sha256: 6f537caff91f6c479b5b71fb37740e5ba4dacaea68085101f98cf7a70620d2f6
---
# MoonBit: a programming language designed for the AI era, built in China | Robots Atlas

MoonBit: a programming language designed for the AI era, built in China | Robots Atlas

# MoonBit: a programming language designed for the AI era, built in China

Sir Robot 9 July 2026 · 6 min read

Sir Robot

9 July 2026 · 6 min read AI-assisted · editorial review

MoonBit — a new programming language developed by a team in China — is drawing attention as a candidate for the "language of the AI era." A study accepted by IEEE Transactions on Software Engineering shows that, despite a far smaller training corpus, models learn to generate MoonBit code more effectively than the comparable language Gleam. The takeaway is simple: a language's design and toolchain determine how well AI writes code in it.

### Key takeaways

- The study "No Resource, No Benchmarks, No Problem?" (arXiv:2606.16827) has been accepted by IEEE Transactions on Software Engineering
- On the McEval-Hard benchmark, Qwen 2.5 Coder 32B reaches pass@1 of 32.60% in MoonBit versus 26.08% in Gleam, despite a roughly seven-times-smaller code corpus
- MoonBit bundles compiler, build system, tests, documentation and an AI assistant into a single toolchain
- Formal verification based on Hoare triples is built into the native toolchain and checks real production code
- The Mooncakes package manager has passed 10,000 libraries and 4 million downloads, and the team behind the language is based in China

## Why the language matters to AI at all

AI's most direct impact on software is the reshaping of the entire engineering pipeline. As developer tools turn "AI-native," the entry point itself — the programming language — deserves a fresh look. One concrete signal was the recent decision to rewrite the core of the high-performance open source project Bun in Rust: once AI lowers the cost of migration, infrastructure starts shifting toward languages with stronger guarantees, higher performance and easier machine checking.

Greg Brockman, co-founder of OpenAI, put it plainly:

> Rust is a perfect language for agents, because if it compiles it's ~correct.

Greg Brockman, OpenAI

But Rust predates the generative-AI era, and its goal was safe low-level programming, not collaboration between agents. Andrej Karpathy, a member of OpenAI's founding team and the person who coined "vibe coding," noted that language models are changing the entire constraints landscape of software — C-to-Rust ports and COBOL legacy upgrades become easier because models are good at "translating" code — yet Rust itself is far from the optimal target for LLMs. Which language best fits AI remains an open question.

## What the IEEE study shows

That question has now reached software-engineering research. The paper "No Resource, No Benchmarks, No Problem? Evaluating and Improving LLMs for Code Generation in No-Resource Languages" (arXiv:2606.16827), accepted by IEEE Transactions on Software Engineering, studies two young languages — MoonBit and Gleam — as "no-resource languages," meaning ones with too little public code, tutorials and examples for a model to have seen them well during pre-training.

The result is counterintuitive. Although MoonBit's visible corpus is roughly seven times smaller than Gleam's by GitHub repository count, models learn it more effectively. On the hard McEval-Hard benchmark, Qwen 2.5 Coder 32B reaches a clearly higher pass@1 in MoonBit than in Gleam — both after continued pre-training and after additional instruction transferring:

| Training stage | MoonBit (pass@1) | Gleam (pass@1) |
| --- | --- | --- |
| After continued pre-training | 25.86% | 12.47% |
| After instruction transferring | 32.60% | 26.08% |

Scroll the table to see more

In-context methods — few-shot and RAG — also yield larger gains for MoonBit.

The authors attribute this to the language's "AI-friendly" design: a well-designed language helps a model learn more than corpus size alone would suggest. That inverts the common intuition that the quality of generated code depends mainly on the number of examples in the training data.

## The language as a toolchain

MoonBit is hard to reduce to syntax. From the start it was built alongside a compiler, build system, test framework, documentation tools and an AI assistant — a complete chain from writing code to shipping a product. In practice, AI-assisted coding is not about generating a fragment once, but about a loop of "generate — compile — diagnose — fix — test." The quality of compiler feedback determines how quickly a model corrects its own mistakes.

MoonBit folds formal verification into that chain too. By defining Hoare triples, it lets developers prove selected parts of the code correct without building a full proof chain. Unlike academic languages such as Rocq, MoonBit proves real production code rather than an abstracted version of it.

The classic example is binary search — deceptively simple, notoriously error-prone. Joshua Bloch, author of "Effective Java," documented in 2006 an integer-overflow bug in the Java standard library's binary search that ran in production for nearly a decade before it was found.

## A built-in sandbox for agents

The second axis is deploying AI-generated code. In the agent ecosystem a SKILL.md file supplies instructions and workflows, but on its own it is only text — the real work is done by the code underneath. MoonBit lets developers write asynchronous logic, compile it to Wasm bytecode and publish it through Mooncakes, so a user or agent runs it with a single command. Wasm is portable, embeddable and isolable — the same logic can go into a cloud function, a browser or an agent runtime.

On top of that sits a permissions model. Each Skill can attach a policy file declaring which environment variables it needs and which network endpoints it may reach. The sample tool hn-brief, published on Mooncakes, pulls popular Hacker News posts and generates a summary with the DeepSeek model — its policy permits only two addresses and requires a DEEPSEEK_API_KEY. This is not an unbreakable OS-level sandbox, but an explicit, auditable declaration of dependencies — more controllable for agent scenarios than blindly running a script.

## Why this matters

Historically the biggest barrier for a new language was the cold start of its ecosystem: no libraries, few examples, and developers reluctant to migrate. The IEEE study suggests AI shortens that accumulation cycle. If a model learns a language more effectively because of its design rather than its corpus size, then a language designed "for AI" can close the gap faster than its number of public repositories would allow. For MoonBit this is a late-mover argument — with no historical baggage, the language can be designed around the generate–compile–verify loop from scratch.

That does not remove the engineering barrier. Ecosystem maturity, industrial validation and long-term maintenance still decide whether a language survives. AI weakens some traditional ecosystem barriers but guarantees nothing — it pushes competition back onto language design and toolchain quality. That the team behind MoonBit is based in China adds a geographic dimension: fundamental innovation in developer tooling is no longer solely a Silicon Valley affair.

Key takeaway

AI does not remove the ecosystem barrier — it pushes competition back onto language design and toolchain quality.

## What's next

- The researchers laid out a full training path — continued pre-training plus instruction transferring — for no-resource languages, a repeatable method for other young languages, not just MoonBit
- The Mooncakes ecosystem is growing past 10,000 libraries and 4 million downloads, with use cases in browsers, cloud components and multi-agent orchestration — the next test is industrial validation beyond showcase projects
- Karpathy's open question remains: which language will prove the optimal target for language models — MoonBit is one answer, not the only one

## Sources

- arXiv — No Resource, No Benchmarks, No Problem? Evaluating and Improving LLMs for Code Generation in No-Resource Languages
- 量子位 (QbitAI) — 冷门新语言 AI 写不动？IEEE 论文：从零到及格线，MoonBit 给出完整训练路线
- GitHub — Rewrite Bun in Rust (PR #30412)
- Andrej Karpathy / X — LLMs change the whole constraints landscape of software completely
- Greg Brockman / X — rust is a perfect language for agents, given that if it compiles it's ~correct

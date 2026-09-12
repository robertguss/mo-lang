---
tool: Perplexity
prompt: prompts-language-landscape / prompt 3 (languages built for AI authors)
run: 2026-09-12
run_by: Robert
sha256: de1326f48c9af9deffd072e6c90abd7d3a3e02e80464f1b9a8c5b146298101a0
---
# LLM-Authored Programming Languages: Evidence Base (2023–2026)

## Executive summary

Between 2023 and 2026 a distinct field appeared: languages, DSLs and serious proposals whose stated design goal is that a **model, not a human, is the primary author**. This report catalogues 49 such entries — 42 from Alasdair Allan's [agentlanguages.dev](https://agentlanguages.dev/) index plus 7 additional projects — classifies each as **syntactic** (easier for models to emit), **verification-oriented** (contracts, proofs, checkable specs) or **orchestration-oriented** (agents calling agents), and records status, primary claim, evidence, and biggest weakness for each. It also covers the academic literature on LLM-friendly language design and grammar-constrained decoding, which is often conflated with this field but is a different thing.

Five findings dominate:

1. **Only 4 of 49 entries publish head-to-head model-success numbers**, and 3 of those are graded by the language's own author. No third-party reproduction of any published benchmark exists in the field.
2. **The best result in the field — Vera, 98.7% Pass@1 across 9 model configurations — still loses to TypeScript** (99.7% for 8 of 9 models) on the same suite. Aver and AILANG lose to Python on their one third-party comparison ([VeraBench](https://github.com/aallan/vera-bench)).
3. **The strongest peer-review-track result, Quasar (UPenn, arXiv:2506.12202), works by keeping Python as the authoring surface** and transpiling underneath — 42–56% execution-time reduction, 52–53% fewer approval interactions on ViperGPT/GQA and CaMeL/AgentDojo. That design concedes the field's core premise.
4. **Grammar-constrained decoding has already made syntactic validity nearly free** for any existing language — SynCode removes 96.07% of Python and Go syntax errors ([arXiv:2403.01632](https://arxiv.org/abs/2403.01632)); Sun et al. measure the total available token gain from a bespoke grammar at **10–15%** ([arXiv:2404.16333](https://arxiv.org/abs/2404.16333), [arXiv:2512.08266](https://arxiv.org/abs/2512.08266)). This removes most of the syntactic camp's headroom.
5. **Cold-start is the field's unaddressed risk**: LLMs perform dramatically better on languages present in their training data, and every entry here is either brand-new or explicitly forbids AI training on its corpus (Prove's licence). Armin Ronacher's [essay](https://lucumr.pocoo.org/2026/2/9/a-language-for-agents/) and the [anup.io Markov critique](https://www.anup.io/til-markov-language/) state this most cleanly.

### Category counts (this report's classification)

| Category | Count | Representative entries |
|---|---|---|
| **Syntactic** — reshape surface syntax for model emission | 20 | MoonBit, Axis, Codong, ilo, LLMLang, Magpie, NERD, Tacit, X07, Markov (proposal) |
| **Verification-oriented** — contracts, proofs, effect types, differential oracles | 18 | Vera, AILANG, Aver, NanoLang, Vow, Thermite, Intent, Modula-9, Zero, Jacquard |
| **Orchestration-oriented** — agents, tools, workflows, approvals | 11 | Fabro, BAML, Pel, Quasar, Boruna, Marsha, Plumbing, CodeSpeak |
| **Total** | **49** | |

The catalogue's own buckets are Syntactic 14 / Verification 17 / Orchestration 7 / Adjacent 1 / Unclassified 3 ([agentlanguages.dev](https://agentlanguages.dev/)); the differences come from adding 7 non-catalogue entries and forcing the four residual entries (Koru, Spec, Valea, Plumbing) into one of the three mandated categories, and from filing MoonBit as syntactic rather than verification.

### The four projects with published head-to-head model-success numbers

| Project | Category | Benchmark | Result | Grader |
|---|---|---|---|---|
| **Vera** | Verification | [VeraBench](https://github.com/aallan/vera-bench), 9 models × 60 problems | Vera 98.7% · Python 96.7% · **TypeScript 99.7%** | Language author (Allan) |
| **AILANG** | Verification | Own [dashboard](https://ailang.sunholo.com/docs/benchmarks/performance) — 33 tasks × 8 models × 3 modes | AILANG 96.8% vs Python 97.0% (VeraBench 5-model subset) | Self + VeraBench |
| **Fabro** | Orchestration | Self-published SWE-Bench-Lite, 300 instances | GPT-5.4 **65.7%**, Sonnet 4.6 57.7%, Haiku 4.5 54.0% | Self |
| **Quasar** | Orchestration | ViperGPT/GQA + CaMeL/AgentDojo ([arXiv:2506.12202](https://arxiv.org/abs/2506.12202)) | 42–56% faster execution, 52–53% fewer approvals vs Python baseline | Peer-review track (under review) |

The honest reading: the field has one peer-review-track win (Quasar), one strong self-graded win that still loses to TypeScript (Vera), one verification project that measurably loses to Python on the one comparison it appeared in (Aver, 92.4% vs Python 97.0%), and one orchestration harness whose 65.7% SWE-Bench number has never been reproduced by a third party (Fabro).

### The most damning single datapoint in the catalogue

**ilo** — the one project that ran its own agent evaluation and published the failure — records 11 of 13 scripted personas failing outright on Haiku 4.5, with 12 of 13 exhausting a 3-attempt ceiling ([agentlanguages.dev/languages/ilo](https://agentlanguages.dev/languages/ilo/)). Its spec grew from ~16,000 tokens to ~51,000 tokens as the design shrank, and per-generation token savings vs Python are "eaten by context overhead in short sessions." That this is the exception is the strongest signal about the rest.

---

**Scope note.** Every factual value below was fetched during this research session. Where a value comes from the maintainer's own editorial (the catalogue at agentlanguages.dev, or a project README), it is attributed as such rather than presented as independent measurement. Where I could not confirm a value from a page I fetched, the field reads `n.a.`

**Two things are being counted separately, per the brief:**

- **(a) Languages / DSLs / serious proposals** whose stated design goal is that a model, not a human, is the primary author. These are in `## Catalog`.
- **(b) Grammar constraints and decoding techniques** — machinery that forces an existing model to emit a valid string in an existing language. These are in `## Academic work…` and are labelled `decoding technique`. They are not languages and are not counted in the catalog totals.

---

## Summary of catalog

**Total entries: 49.**

Forty-two come from the [agentlanguages.dev catalogue](https://agentlanguages.dev/), maintained by Alasdair Allan ([repo: aallan/agentlanguages](https://github.com/aallan/agentlanguages)), whose taxonomy originates in his May 2026 essay ["Three camps alike in dignity"](https://negroniventurestudios.com/2026/05/20/three-camps-alike-in-dignity/). Seven more were found independently in this session and are not in that catalogue: **Jacquard, BAML, Aether, CodeSpeak, Markov, ll-lang, ALaS**.

| Category (my classification, dominant) | Count |
|---|---|
| Syntactic | 20 |
| Verification-oriented | 18 |
| Orchestration-oriented | 11 |
| **Total** | **49** |

The catalogue's own buckets are Syntactic 14, Verification 17, Orchestration 7, Adjacent 1, Unclassified 3 ([agentlanguages.dev](https://agentlanguages.dev/)). My counts differ because (i) I add seven entries the catalogue does not list, (ii) I force the three "Unclassified" entries (Koru, Spec, Valea) and the one "Adjacent" entry (Plumbing) into one of the three mandated categories, and (iii) I classify **MoonBit** as Syntactic where the catalogue files it under Verification — MoonBit's AI-native argument is about grammar shape and a constrained sampler, not about proofs ([MoonBit AI blog](https://www.moonbitlang.com/blog/moonbit-ai)).

### Notable gaps in the evidence base

1. **Almost nobody publishes a closed-loop benchmark.** Of 49 entries, exactly four publish head-to-head model-success numbers against a mainstream language: **Vera** (VeraBench), **AILANG** (its own dashboard), **Fabro** (self-published SWE-Bench-Lite), and **Quasar** (peer-reviewed ViperGPT/GQA evaluation). Every one of those except Quasar is graded by the language's own author.
2. **No third-party reproduction exists for any entry.** I found no independent replication of any published benchmark in this catalogue.
3. **The one project that published a hostile number on itself is ilo**, whose CI baseline records 11 of 13 scripted agent personas failing outright ([agentlanguages.dev/languages/ilo](https://agentlanguages.dev/languages/ilo/)). That it is the exception is the most damning fact about the field.
4. **Heavy single-author concentration and very recent creation dates.** Of the 38 catalogue entries with a GitHub repo, most were created in 2026 and most are one-person projects. Median star counts are in the single digits; the distribution is dominated by three outliers (Zero, Fabro, NanoLang).
5. **Survivorship and dead-end risk is real and already visible**: Marsha (2023) has had no maintainer activity since August 2023, and Google's Aether was archived in May 2026.
6. **Star counts in the catalogue's editorial are stale.** Where I checked the live GitHub API this session, several counts are materially higher than the catalogue's figures (e.g. Zero 3.3k → 5,360; Fabro 1,221 → 1,595; NERD 135 → 172; Codong 67 → 73). I report both and label which is which.

---

## Catalog

### Syntactic

Entries whose primary move is to reshape the surface syntax — token density, one canonical form, no ambiguity, machine-shaped notation.

**Axis**
- Origin: Vladimir Melnic (independent) — [agentlanguages.dev/languages/axis](https://agentlanguages.dev/languages/axis/)
- First public: single initial commit **24 May 2026**; repo created 2026-05-24 ([github.com/vmelnic/axis](https://github.com/vmelnic/axis))
- Category: Syntactic (secondary: Verification-oriented)
- Status (2026): last push **2026-05-28**, 3 stars, no tagged releases, no `LICENSE` file despite `Cargo.toml` declaring MIT ([repo](https://github.com/vmelnic/axis); [catalogue](https://agentlanguages.dev/languages/axis/)). Effectively dormant one month after launch.
- Primary claim: a backend API language aimed explicitly at **small** models (1B/3B/7B): twelve top-level constructs cover a production backend, with an LL(1) grammar and prefix-only expressions so the toolchain can ship per-parser-state logit masks for constrained decoding ([catalogue](https://agentlanguages.dev/languages/axis/)).
- Evidence it works: three in-repo projects with passing integration tests — `todolist/` 20/20, `advanced/` 32/32, and a marketplace app with "zero application source code" outside `.axis` files; 73 KB spec at v0.2 ([catalogue](https://agentlanguages.dev/languages/axis/)). No model-success benchmark.
- Biggest weakness: the central claim — that a 1B model can drive this — is **untested in public**. There is no benchmark, 3 stars, zero forks, and a single commit dump followed by four days of activity and then silence. The licence ambiguity makes it unusable for anyone serious.
- Sources: https://github.com/vmelnic/axis · https://agentlanguages.dev/languages/axis/

**B-IR (and TBIR, Loom)**
- Origin: Jason Hall, Chainguard — [agentlanguages.dev/languages/b-ir](https://agentlanguages.dev/languages/b-ir/)
- First public: **January 2026** (blog post); repo created 2026-01-11 ([github.com/imjasonh/loom](https://github.com/imjasonh/loom))
- Category: Syntactic
- Status (2026): **abandoned thought experiment** — last push 2026-01-12, 0 stars ([repo](https://github.com/imjasonh/loom)).
- Primary claim: a narrative of three iterations in which Hall asked frontier models to design a language for their own consumption: Gemini produced B-IR with multi-byte unicode opcodes; Claude Opus replaced it with control-character TBIR and then *itself* substituted short English keywords; the final Loom keeps token density but adds unambiguous scope, mandatory pre/postconditions, and stable error codes ([catalogue](https://agentlanguages.dev/languages/b-ir/)).
- Evidence it works: none quantitative. The reported result is qualitative and interesting: **the model converged back onto readable keywords on its own**, and the third iteration "ends up resembling existing languages with cleaner error codes and unambiguous scope" ([catalogue](https://agentlanguages.dev/languages/b-ir/)).
- Biggest weakness: it is a blog post with a two-day-old Python bootstrap behind it. As evidence it cuts *against* the syntactic camp — the model rejected the dense encoding.
- Sources: https://github.com/imjasonh/loom · https://agentlanguages.dev/languages/b-ir/

**Codong**
- Origin: Brett (`brettinhere`), independent — [agentlanguages.dev/languages/codong](https://agentlanguages.dev/languages/codong/)
- First public: v0.1.0 **24 March 2026**; repo created 2026-03-21 ([github.com/brettinhere/Codong](https://github.com/brettinhere/Codong))
- Category: Syntactic
- Status (2026): last push **2026-04-12**, 73 stars, MIT, Go ([repo](https://github.com/brettinhere/Codong)). Catalogue records v0.1.3 (28 Mar 2026), 92 commits, 67 stars ([catalogue](https://agentlanguages.dev/languages/codong/)). No activity for five months.
- Primary claim: "designed for AI to write, humans to review, machines to execute" — one canonical function per task, nine bundled dependency-free modules, structured JSON errors carrying `fix` and `retry` fields, `?` propagation; compiles via Go IR to a static native binary ([catalogue](https://agentlanguages.dev/languages/codong/)).
- Evidence it works: 1,427 tests (1,425 passing); project-reported **~39% token reduction** on its compact error format and a **~170× speedup** from the v0.1.3 compilation cache ([catalogue](https://agentlanguages.dev/languages/codong/)). Both figures are self-reported; neither measures model success rate.
- Biggest weakness: the token/cache numbers measure the compiler, not the thesis. The repo also lists a `claude` bot among contributors, so "AI to write, humans to review" describes the compiler's own provenance as much as its intended use — and the project stopped moving in April 2026.
- Sources: https://github.com/brettinhere/Codong · https://agentlanguages.dev/languages/codong/

**Faber Romanus**
- Origin: Ian Zepp — [agentlanguages.dev/languages/faber-romanus](https://agentlanguages.dev/languages/faber-romanus/)
- First public: **July 2026**; repo created 2026-07-12 ([github.com/faberlang/faber](https://github.com/faberlang/faber))
- Category: Syntactic
- Status (2026): last push **2026-09-01**, 1 star, MIT ([repo](https://github.com/faberlang/faber)). v1.0.0 ships a macOS arm64 CLI; **the compiler ("Radix") is closed source** ([catalogue](https://agentlanguages.dev/languages/faber-romanus/)).
- Primary claim: a typed compute language for a split audience — agents author, humans read. Latin is the canonical lexical identity, and the project states its English keywords were chosen keyword-by-keyword by a **council of different models** picking the highest-probability token for each concept, so the default surface is the one models already want to emit; other locales render the same HIR ([catalogue](https://agentlanguages.dev/languages/faber-romanus/)).
- Evidence it works: none published. The catalogue notes only that a CLI and an MIT autograd/ML library (Gradus) ship.
- Biggest weakness: the catalogue itself names an "honesty gap" — the tensor/inference *surface* is large while device residency and GPU execution remain compiler and host concerns, so "a catalogue reader should not take the glyph surface as a shipped serving product" ([catalogue](https://agentlanguages.dev/languages/faber-romanus/)). A closed compiler with 1 star and no benchmark cannot be evaluated.
- Sources: https://github.com/faberlang/faber · https://agentlanguages.dev/languages/faber-romanus/

**ilo**
- Origin: Daniel Morris — [agentlanguages.dev/languages/ilo](https://agentlanguages.dev/languages/ilo/)
- First public: **February 2026**; repo created 2026-02-24 ([github.com/ilo-lang/ilo](https://github.com/ilo-lang/ilo))
- Category: Syntactic (secondary: Verification-oriented)
- Status (2026): last push **2026-08-13**, 7 stars, MIT, Rust ([repo](https://github.com/ilo-lang/ilo)). Working compiler, package manager, HTTP server, streaming primitives.
- Primary claim: every design choice is argued against **total** token cost — generation plus retries plus context loading. Builtins carry short fixed aliases (`mapr`, `fld`, `rdjl`, `jpth`), no parentheses on parameters, last expression returns. The distinctive move is process: the language is developed by running scripted agent personas against real tasks and filing every confusion as a **language bug** ([catalogue](https://agentlanguages.dev/languages/ilo/)).
- Evidence it works: this is the most honest entry in the field, and the numbers are bad. A committed **August 2026 CI baseline records 13 scripted personas on Haiku 4.5: 1 produced working code, 1 partially, 11 failed**, with 12 of 13 exhausting a three-attempt ceiling. The token thesis also inverted: the project measured its own spec at ~16,000 tokens vs Zero's 4,300, `SPEC.md` has since reached 179 KB (~51,000 tokens), and per-generation savings of ~600 tokens vs Python are "eaten by context overhead in short sessions." Modular skills now run at ~98% of a 14,000-token CI-enforced cap ([catalogue](https://agentlanguages.dev/languages/ilo/)).
- Biggest weakness: self-diagnosed. The spec grew against the thesis; adoption is single-digit stars, a few hundred lifetime crates.io downloads, and two GitHub issues ever; and the closed-loop benchmark the project's own strategy identifies as the thing that would make its claim checkable has not been published ([catalogue](https://agentlanguages.dev/languages/ilo/)).
- Sources: https://agentlanguages.dev/languages/ilo/ · https://github.com/ilo-lang/ilo

**Laze**
- Origin: `kerv` — [agentlanguages.dev/languages/laze](https://agentlanguages.dev/languages/laze/)
- First public: **April 2026**; repo created 2026-05-12 ([github.com/kerv/laze](https://github.com/kerv/laze))
- Category: Syntactic
- Status (2026): created and last pushed **the same day, 2026-05-12**; 4 stars; no licence file ([repo](https://github.com/kerv/laze)). Dead.
- Primary claim: minimal indentation-based syntax with no punctuation; a single Python script parses `.laze`, generates C in memory, and pipes it to `cc -O2`. The bet is that LLMs are most accurate emitting text-shaped readable input, so ergonomics *for the model* outrank expressive power ([catalogue](https://agentlanguages.dev/languages/laze/)).
- Evidence it works: none. The author frames it as a weekend experiment in what an LLM produces when asked to design a language for itself ([catalogue](https://agentlanguages.dev/languages/laze/)).
- Biggest weakness: one day of work, no evaluation, no licence. The catalogue explicitly declines to rate it against working compilers.
- Sources: https://github.com/kerv/laze · https://agentlanguages.dev/languages/laze/

**LLMLang**
- Origin: Paul Williams (`paulprogrammer`), Denver CO — [agentlanguages.dev/languages/llmlang](https://agentlanguages.dev/languages/llmlang/)
- First public: **18 May 2026** (repo created 2026-05-18) ([github.com/paulprogrammer/llmlang](https://github.com/paulprogrammer/llmlang))
- Category: Syntactic (secondary: Verification-oriented)
- Status (2026): last push **2026-08-28**, 1 star, GPL-3.0 with runtime exception, Rust. Catalogue records v0.4.0 with 16 tagged releases cut between 18 and 24 May 2026 ([repo](https://github.com/paulprogrammer/llmlang); [catalogue](https://agentlanguages.dev/languages/llmlang/)).
- Primary claim: token density taken to the extreme — prefix-arity AST in single-character ASCII operators (`+ - > $ ~ ? . #`), De Bruijn indices (`^0`, `^1`) instead of variable names, affine ownership checked at compile time, plus compiler-injected OpenTelemetry spans and an OpenCL JIT for pure `map` bodies ([catalogue](https://agentlanguages.dev/languages/llmlang/)).
- Evidence it works: ~13,300 lines of Rust/C, 31 self-hosted test programs, 47 compiler unit tests ([catalogue](https://agentlanguages.dev/languages/llmlang/)). No model-success measurement.
- Biggest weakness: the README discloses "This entire repository has been largely vibecoded with humans acting as the product owners, and the LLM acting as the developer" ([catalogue](https://agentlanguages.dev/languages/llmlang/)) — a one-week feature sprint, 0–1 stars, and no evidence that De Bruijn-indexed single-character opcodes are easier for a model than named variables. B-IR's result (the model discarded exactly this encoding) argues against it.
- Sources: https://github.com/paulprogrammer/llmlang · https://agentlanguages.dev/languages/llmlang/

**Lume**
- Origin: Marcelo Augusto Vilas Boas (Itaú Unibanco tech lead) — [agentlanguages.dev/languages/lume](https://agentlanguages.dev/languages/lume/)
- First public: **16 May 2026** (all seven commits dated that day) ([github.com/mavboas/lume](https://github.com/mavboas/lume); [catalogue](https://agentlanguages.dev/languages/lume/))
- Category: Syntactic
- Status (2026): created and last pushed **2026-05-16**, 1 star, MIT, Go, `v0.1.0-experimental`, no tagged releases ([repo](https://github.com/mavboas/lume)). Dormant.
- Primary claim: an AI-first backend language transpiling to Go, immutable by default with one canonical form per operation — but the distinctive move is in the toolchain: `lume kb` builds a local knowledge base from the project's docs and diagnostics, then `lume kb pack "<question>" --max-tokens N` assembles a **token-budgeted context pack** to paste into a prompt ([catalogue](https://agentlanguages.dev/languages/lume/)).
- Evidence it works: ~6,000 lines of Go, 69 test functions ([catalogue](https://agentlanguages.dev/languages/lume/)). No benchmark.
- Biggest weakness: the catalogue flags an overclaim directly — the GitHub description says the syntax is "strict enough for the compiler to prove correctness," but "what is actually shipped is conventional type-system soundness," and the README's own "Planned Language Ideas" list (HM inference, ADTs, `Result`/`Option`, effects, refinement types) is not in the compiler ([catalogue](https://agentlanguages.dev/languages/lume/)).
- Sources: https://github.com/mavboas/lume · https://agentlanguages.dev/languages/lume/

**Magpie**
- Origin: "Magpie Language Developers" — [agentlanguages.dev/languages/magpie](https://agentlanguages.dev/languages/magpie/)
- First public: **April 2026** per catalogue; repo created 2026-02-27 ([github.com/magpie-lang/magpie](https://github.com/magpie-lang/magpie))
- Category: Syntactic
- Status (2026): last push **2026-03-09**, 54 stars, MIT, Rust, v0.1, no releases ([repo](https://github.com/magpie-lang/magpie)). Six months idle.
- Primary claim: **SSA is the surface syntax** — every value `%`-prefixed and typed at definition, explicit basic blocks, branches and ownership transitions as first-class operations. The bet is that removing surface ambiguity cuts LLM error rates more than added verification does ([catalogue](https://agentlanguages.dev/languages/magpie/)).
- Evidence it works: site-published compile/runtime benchmarks — 155 ms compile for the sample program vs Rust 234 ms and TypeScript 268 ms; execution 32 ms matching Rust; peak memory 1.6 MB vs Rust 1.4 MB and TypeScript 69.2 MB ([catalogue](https://agentlanguages.dev/languages/magpie/)).
- Biggest weakness: those benchmarks measure the *compiler*, not the thesis — nothing published tests whether models actually write SSA more reliably than Python. The catalogue records 44 commits, 3 stars at cataloguing, a small stdlib, and no LSP, registry, or IDE plug-ins ([catalogue](https://agentlanguages.dev/languages/magpie/)).
- Sources: https://github.com/magpie-lang/magpie · https://agentlanguages.dev/languages/magpie/

**Mog**
- Origin: Voltropy — [agentlanguages.dev/languages/mog](https://agentlanguages.dev/languages/mog/)
- First public: **March 2026** per catalogue; repo created 2026-02-01 ([github.com/voltropy/mog](https://github.com/voltropy/mog))
- Category: Syntactic (secondary: Verification-oriented)
- Status (2026): last push **2026-03-09**, 142 stars, MIT, Rust, **no tagged release** ([repo](https://github.com/voltropy/mog)). Six months idle.
- Primary claim: a statically typed, embedded-only language explicitly designed for LLMs to write, whose **full spec fits in 3,200 tokens**. Flat operators mean `a + b * c` is a compile *error*; capabilities (`fs`, `http`, `log`) must be declared in source and granted by the host; there is no standard library at all ([catalogue](https://agentlanguages.dev/languages/mog/); [Mech write-up](https://www.mech.app/articles/mog-a-3-200-token-language-spec-for-capability-based-agent-sandboxing/)).
- Evidence it works: 1,146+ compiler tests plus 186 tests for `rqbe` (a ~15,000-line safe-Rust port of QBE); 128 commits; a 17-chapter guide. The first version was authored by Voltropy's own Volt agent in a single three-week continuous session ([catalogue](https://agentlanguages.dev/languages/mog/)). No model-success benchmark.
- Biggest weakness: the security model — the whole point of a capability sandbox — is candidly unaudited: "Mog has not been audited, and it is presented without security guarantees. It should be possible to secure it, but that work has not yet been done" ([catalogue](https://agentlanguages.dev/languages/mog/)). No release tag and no commits since March 2026.
- Sources: https://github.com/voltropy/mog · https://agentlanguages.dev/languages/mog/ · https://www.mech.app/articles/mog-a-3-200-token-language-spec-for-capability-based-agent-sandboxing/

**NERD**
- Origin: Guru Sattanathan — [agentlanguages.dev/languages/nerd](https://agentlanguages.dev/languages/nerd/)
- First public: **January 2026**; repo created 2025-12-31 ([github.com/Nerd-Lang/nerd-lang-core](https://github.com/Nerd-Lang/nerd-lang-core))
- Category: Syntactic
- Status (2026): last push **2026-01-24**, 172 stars (catalogue records 135), Apache-2.0, C, latest release v0.1.4 Jan 2026 ([repo](https://github.com/Nerd-Lang/nerd-lang-core); [catalogue](https://agentlanguages.dev/languages/nerd/)). Eight months idle.
- Primary claim: "No Effort Required, Done" — strip every symbolic operator and replace it with an English keyword (`plus`, `minus`, `times`, `eq`, `gt`, `mod`), on the argument that BPE tokenisers fragment punctuation but treat common English words as single tokens. First-class MCP client and `llm claude "prompt"` primitives ([catalogue](https://agentlanguages.dev/languages/nerd/); [nerd-lang.org/llms.txt](https://www.nerd-lang.org/llms.txt)).
- Evidence it works: none. No token-count measurement is published for the tokeniser claim that the whole language rests on ([catalogue](https://agentlanguages.dev/languages/nerd/)).
- Biggest weakness: the premise is testable in ten minutes and untested. It is also probably wrong for code — `+` is a single token in cl100k-family tokenisers. The README labels itself "🚧 Early days" and warns the implementation might change completely; there is no type system ([catalogue](https://agentlanguages.dev/languages/nerd/)).
- Sources: https://github.com/Nerd-Lang/nerd-lang-core · https://agentlanguages.dev/languages/nerd/

**Sever**
- Origin: Avital Tamir — [agentlanguages.dev/languages/sever](https://agentlanguages.dev/languages/sever/)
- First public: **February 2026** per catalogue; repo created 2025-06-29 ([github.com/AvitalTamir/sever](https://github.com/AvitalTamir/sever))
- Category: Syntactic
- Status (2026): last push **2025-07-05**, 70 stars, **no licence**, Zig ([repo](https://github.com/AvitalTamir/sever)). Fourteen months idle; explicitly a thought experiment.
- Primary claim: two surface forms over one AST — a dense `SEV` format of single-character opcodes (`P D L R C`) and type tags (`I F B S`), plus a human-readable `SIRS` JSON mirror, with a claimed 29-tool MCP server integrating the model into the compilation loop ([catalogue](https://agentlanguages.dev/languages/sever/)).
- Evidence it works: none. The README disclaims the entire repository as Claude-generated and frames the project as a thought experiment or art piece ([catalogue](https://agentlanguages.dev/languages/sever/)).
- Biggest weakness: the author does not claim it works. The catalogue reads it as "conceptual art adjacent to engineering." Every substantive capability (native Zig backend, 29 MCP tools) is marked *claimed*, not verified ([catalogue](https://agentlanguages.dev/languages/sever/)).
- Sources: https://github.com/AvitalTamir/sever · https://agentlanguages.dev/languages/sever/

**Tacit**
- Origin: `weetster` — [agentlanguages.dev/languages/tacit](https://agentlanguages.dev/languages/tacit/)
- First public: **April 2026**; repo created 2026-04-19 ([github.com/weetster/tacit](https://github.com/weetster/tacit))
- Category: Syntactic (secondary: Verification-oriented)
- Status (2026): last push **2026-05-23**, 4 stars, Apache-2.0/MIT, Rust, v0.7.7 (19 May 2026), 237 commits ([repo](https://github.com/weetster/tacit); [catalogue](https://agentlanguages.dev/languages/tacit/)). Phase 6 frozen by ADR 0089 on 2026-05-17.
- Primary claim: human-oriented surface syntax is treated as a lossy intermediate. The **AST is authoritative**; every valid AST has exactly one canonical text serialisation; definitions are content-addressed by BLAKE3 hash of that form; variables are De Bruijn indices; parse errors produce typed `Hole` nodes with structured diagnostics instead of failing; effects are explicit in signatures ([catalogue](https://agentlanguages.dev/languages/tacit/)).
- Evidence it works: ~90 architecture decision records, a frozen feature phase covering modules, hash-pinned lockfiles, stable `tacit-test-v1` JSON test output, fixed-width integer arithmetic, six stdlib packages, and a C-header host ABI with a Rust embedding demo ([catalogue](https://agentlanguages.dev/languages/tacit/)). No model benchmark.
- Biggest weakness: discipline without evidence. Debugger, diff/blame, IDE support, public registry, and arbitrary FFI are explicitly out of scope until a later ADR; release artefacts target only Linux x86_64 with a glibc 2.35 floor; 4 stars; no commits since May 2026 ([catalogue](https://agentlanguages.dev/languages/tacit/); [repo](https://github.com/weetster/tacit)).
- Sources: https://github.com/weetster/tacit · https://agentlanguages.dev/languages/tacit/

**X07**
- Origin: author not named in repo — [agentlanguages.dev/languages/x07](https://agentlanguages.dev/languages/x07/)
- First public: **April 2026** per catalogue; repo created 2026-01-15 ([github.com/x07lang/x07](https://github.com/x07lang/x07))
- Category: Syntactic
- Status (2026): last push **2026-07-12**, 8 stars, Apache-2.0/MIT, Rust; 471 commits, 108 tagged releases, docs site at 0.2.10 ([repo](https://github.com/x07lang/x07); [catalogue](https://agentlanguages.dev/languages/x07/)).
- Primary claim: **eliminate text syntax entirely**. A program is a canonical `*.x07.json` AST document with a versioned schema; edits are RFC 6902 JSON Patch operations the toolchain applies mechanically; diagnostics ship as stable JSON with quickfixes applied by `x07 fix --write` ([catalogue](https://agentlanguages.dev/languages/x07/)).
- Evidence it works: an `/agent` portal advertising 14 skills, 258 schemas, 17 examples, 410 packages, 19 stdlib modules — a documentation surface larger than most of the catalogue ([catalogue](https://agentlanguages.dev/languages/x07/)). No model-success benchmark.
- Biggest weakness: the catalogue names it precisely — "the gap between the published toolchain depth and the visible user base is the entry's defining quality": 8 stars, 0 forks, 0 open issues, and no named author ([catalogue](https://agentlanguages.dev/languages/x07/)). A JSON-AST-only source format also discards diffability and every existing code tool.
- Sources: https://github.com/x07lang/x07 · https://agentlanguages.dev/languages/x07/

**Koru**
- Origin: anonymous (`korulang`) — [agentlanguages.dev/languages/koru](https://agentlanguages.dev/languages/koru/)
- First public: **December 2025**; repo created 2025-12-28 ([github.com/korulang/koru](https://github.com/korulang/koru))
- Category: Syntactic (catalogue: Unclassified)
- Status (2026): last push **2026-09-12**, 25 stars, **no licence**, Zig; pre-alpha, described as having "only ever been compiled on a single computer" ([repo](https://github.com/korulang/koru); [catalogue](https://agentlanguages.dev/languages/koru/)).
- Primary claim: a Zig superset (every `.kz` file is valid Zig; Koru constructs marked with `~`) whose distinctive move is **event continuations with mandatory branch handling** — events declare inputs and possible output branches up front, and invoking one requires handling each branch. The "AI-First" claim is architectural (bounded event contexts aid model reasoning), and the catalogue reads the tagline as deliberate satire ([catalogue](https://agentlanguages.dev/languages/koru/)).
- Evidence it works: n.a. The compiler itself was authored using Claude Opus 4.1–4.5 and Sonnet 4.5 ([catalogue](https://agentlanguages.dev/languages/koru/)).
- Biggest weakness: no agent tooling ships at all — no SKILL.md, AGENTS.md, MCP server, or structured JSON diagnostics — so the AI-first claim is unbacked by machinery, and the catalogue's unclassified bucket exists for exactly that reason ([catalogue](https://agentlanguages.dev/languages/koru/)). No licence.
- Sources: https://github.com/korulang/koru · https://agentlanguages.dev/languages/koru/

**Valea**
- Origin: Hans Voetsch (Google) — [agentlanguages.dev/languages/valea](https://agentlanguages.dev/languages/valea/)
- First public: **March 2026**, announced on Hacker News; repo created 2026-03-12 ([github.com/hvoetsch/valea](https://github.com/hvoetsch/valea))
- Category: Syntactic (catalogue: Unclassified)
- Status (2026): created 2026-03-12, last push **2026-03-13**, 4 stars, **no licence file** per the GitHub API (catalogue says MIT), Rust ([repo](https://github.com/hvoetsch/valea); [catalogue](https://agentlanguages.dev/languages/valea/)). One day of activity.
- Primary claim: five declared properties — deterministic syntax, explicit semantics with no hidden allocations or exceptions, machine-readable diagnostics, canonical formatting, small surface. The README sketches the loop: agent gets a goal, writes Valea, reads `valea check --json`, applies fixes ([catalogue](https://agentlanguages.dev/languages/valea/)).
- Evidence it works: none. The catalogue: "Public information beyond the repository README is limited."
- Biggest weakness: the catalogue includes it explicitly as "a marker of the **noise floor** of the field — projects with this much intent, this little code, and this much manifesto are now common enough that the catalogue has an unclassified bucket for them" ([catalogue](https://agentlanguages.dev/languages/valea/)).
- Sources: https://github.com/hvoetsch/valea · https://agentlanguages.dev/languages/valea/

**MoonBit**
- Origin: IDEA Research / MoonBit team (Haoxiang Fei, Yu Zhang, Hongbo Zhang, Yanlin Wang, Qing Liu) — [moonbitlang.com/blog/moonbit-ai](https://www.moonbitlang.com/blog/moonbit-ai)
- First public: language launched **October 2022** per its own AI blog post of 18 Feb 2024 ([MoonBit](https://www.moonbitlang.com/blog/moonbit-ai)); the academic position paper was presented at the **LLM4Code 2024 workshop at ICSE**, Sat 20 Apr 2024, as an 8-minute talk ([conf.researchr.org](https://conf.researchr.org/details/icse-2024/llm4code-2024-papers/9/MoonBit-Explore-the-Design-of-an-AI-Friendly-Programming-Language), [ACM DOI](https://dl.acm.org/doi/10.1145/3643795.3648376)).
- Category: Syntactic (catalogue files it under Verification)
- Status (2026): the catalogue calls it "the most mature project in the catalogue by a clear margin" — 2,115+ stars, full toolchain, multiple production backends, IDE integrations in both major desktop IDEs, working debugger ([catalogue](https://agentlanguages.dev/languages/moonbit/)). No public GitHub repo for the compiler itself.
- Primary claim: an AI-friendly language design in which the grammar is shaped for constrained generation — two samplers (local and global), a real-time semantics-based sampler, a speculation buffer with backtracking, and a deliberately non-nesting structure claimed to be KV-cache-friendly ([MoonBit AI](https://www.moonbitlang.com/blog/moonbit-ai)). A companion post argues ">70% of code may be generated by large models" and criticises Python's suitability ([MoonBit AI coding](https://www.moonbitlang.com/blog/ai-coding)).
- Evidence it works: the AI blog reports a "significant improvement in compilation rates" from the sampler at roughly **3% performance penalty** — but gives no baseline, no benchmark suite, and no absolute numbers ([MoonBit](https://www.moonbitlang.com/blog/moonbit-ai)). The workshop paper page publishes no numeric results ([conf.researchr.org](https://conf.researchr.org/details/icse-2024/llm4code-2024-papers/9/MoonBit-Explore-the-Design-of-an-AI-Friendly-Programming-Language)).
- Biggest weakness: a documented credibility problem on unrelated performance marketing. Chris Allen's ["MoonBit developers are lying to you"](https://bitemyapp.com/blog/moonbit-developers-are-lying-to-you/) (15 Sep 2025) calls MoonBit's "30% faster than Rust" FFT claim "a lie by omission," reporting corrected Rust at 3.2–3.4× faster, GPT-5-authored Rust at 2.33× faster, Rayon at ~6× faster, and correction PRs left unmerged for about two weeks; a commenter on the [Hacker News thread](https://news.ycombinator.com/item?id=45246019) attributes the original 33% gap to mimalloc. Separately, the catalogue's own open question is whether general-purpose framing survives against narrower agent-native languages ([catalogue](https://agentlanguages.dev/languages/moonbit/)).
- Sources: https://www.moonbitlang.com/blog/moonbit-ai · https://www.moonbitlang.com/blog/ai-coding · https://conf.researchr.org/details/icse-2024/llm4code-2024-papers/9/MoonBit-Explore-the-Design-of-an-AI-Friendly-Programming-Language · https://bitemyapp.com/blog/moonbit-developers-are-lying-to-you/

**ll-lang** *(not in the agentlanguages.dev catalogue)*
- Origin: Roman Melnikov (`Neftedollar`) — [dev.to write-up](https://dev.to/neftedollar/why-we-built-ll-lang-a-statically-typed-functional-language-for-llms-2hg8)
- First public: repo created **2026-04-08**; write-up posted 26 April ([github.com/Neftedollar/ll-lang](https://github.com/Neftedollar/ll-lang))
- Category: Syntactic
- Status (2026): last push **2026-06-01**, 8 stars, licence `NOASSERTION`, F# ([repo](https://github.com/Neftedollar/ll-lang)). Three months idle.
- Primary claim: "a language for one narrow, practical job: helping LLMs generate correct code faster by spending fewer tokens on syntax and getting compile-time feedback instead of runtime surprises… not a 'replace every language' project" — a statically typed functional language that compiles to F#, TypeScript, Python, Java and C# ([dev.to](https://dev.to/neftedollar/why-we-built-ll-lang-a-statically-typed-functional-language-for-llms-2hg8)).
- Evidence it works: self-hosting, with a bootstrap fixpoint of `compiler1.fs == compiler2.fs`, and an MCP server (`lllc mcp`) documenting 30 tools for compile, diagnostics, repair, AST inspection, and navigation ([dev.to](https://dev.to/neftedollar/why-we-built-ll-lang-a-statically-typed-functional-language-for-llms-2hg8)). No token-saving or success-rate measurement despite that being the stated goal.
- Biggest weakness: the token claim is the entire premise and is unquantified; `NOASSERTION` licensing blocks adoption; 8 stars and no activity since June 2026. Scoping it to five transpile targets also means models must still know the target ecosystems.
- Sources: https://dev.to/neftedollar/why-we-built-ll-lang-a-statically-typed-functional-language-for-llms-2hg8 · https://github.com/Neftedollar/ll-lang

**ALaS (AI Language Specification / Artificial Language for Autonomous Systems)** *(not in the catalogue)*
- Origin: `dshills` — [Medium write-up](https://dshills.medium.com/programming-without-people-designing-a-language-for-llms-2192618d2540)
- First public: repo created **2025-06-12**; article **13 June 2025** ([github.com/dshills/alas](https://github.com/dshills/alas))
- Category: Syntactic
- Status (2026): last push **2025-06-17**, 7 stars, MIT, Go ([repo](https://github.com/dshills/alas)). **Dead since June 2025** — five days of activity.
- Primary claim: "a programming language designed for machine generation and manipulation by AI/LLM systems… optimized for programmatic generation rather than human readability," using canonical JSON as its primary representation, composable nodes for branching/looping/memory/tool-calls, a typed plugin architecture, schema-first validation, and LLVM compilation, with readability explicitly optional ([repo description](https://github.com/dshills/alas); [Medium](https://dshills.medium.com/programming-without-people-designing-a-language-for-llms-2192618d2540)).
- Evidence it works: the author claims it is "real, typed, validated, and now compilable down to highly optimized machine-level code" with the invariant "if it validates, it compiles and runs," and notes interpreters, the LLVM toolchain, and UI integration are works in progress ([Medium](https://dshills.medium.com/programming-without-people-designing-a-language-for-llms-2192618d2540)). No numbers.
- Biggest weakness: no benchmark, no adoption, and abandoned within a week of announcement. Author self-description: "I'm not a compiler designer." It is chiefly useful as the earliest clear statement (June 2025) of the JSON-AST-as-source idea that X07 and Zero later pursued with real engineering.
- Sources: https://dshills.medium.com/programming-without-people-designing-a-language-for-llms-2192618d2540 · https://github.com/dshills/alas

**Markov** *(proposal only; not in the catalogue)*
- Origin: Davis Haupt — [davi.sh blog](https://davi.sh/blog/2026/02/markov-ideas/)
- First public: **15 February 2026** (blog post)
- Category: Syntactic
- Status (2026): **proposal only, no implementation** — the post is a set of design ideas ([davi.sh](https://davi.sh/blog/2026/02/markov-ideas/)).
- Primary claim: a language shaped for LLM authorship that nonetheless keeps humans in the loop: "First and foremost, Markov will still be human-readable and editable" ([davi.sh](https://davi.sh/blog/2026/02/markov-ideas/)).
- Evidence it works: none — there is nothing to run.
- Biggest weakness: the most important critique of the whole field was written in response to it. [anup.io](https://www.anup.io/til-markov-language/) names the **cold-start problem**: "LLMs perform dramatically better on languages already present in their training data," so any new language starts at a structural disadvantage no amount of grammar elegance fixes — while noting that token-efficiency gains of the sort Markov chases are available without a new language at all (TOON achieves ~40% fewer tokens).
- Sources: https://davi.sh/blog/2026/02/markov-ideas/ · https://www.anup.io/til-markov-language/

---

### Verification-oriented

Entries whose primary move is to make agent-written code *checkable* — contracts, effect types, SMT/model checking, proof export, differential oracles, machine-readable repair.

**AILANG**
- Origin: Mark Edmondson / Sunholo — [agentlanguages.dev/languages/ailang](https://agentlanguages.dev/languages/ailang/)
- First public: **September 2025**; repo created 2025-09-26 ([github.com/sunholo-data/ailang](https://github.com/sunholo-data/ailang))
- Category: Verification-oriented
- Status (2026): **actively maintained** — last push **2026-09-12**, 34 stars, Apache-2.0, Go; v0.20.1 with 110 published releases and 2,958 commits ([repo](https://github.com/sunholo-data/ailang); [catalogue](https://agentlanguages.dev/languages/ailang/)).
- Primary claim: a purely functional, effect-typed substrate for AI-generated code — Hindley-Milner with row polymorphism, capability-carved effects (`IO`, `FS`, `Net`, `Clock`, `AI`) granted at the CLI with `--caps`, and **no loops at all** (lambda calculus, pattern matching and ADTs are the only control forms). The compiler is written autonomously by AI agents via a coordinator ([catalogue](https://agentlanguages.dev/languages/ailang/)).
- Evidence it works: a benchmark dashboard running **33 tasks across 8 frontier models in three modes (zero-shot, self-repair, full agentic) on every release** ([catalogue](https://agentlanguages.dev/languages/ailang/), [dashboard](https://ailang.sunholo.com/docs/benchmarks/performance)). Independently, Vera's cross-language sweep on a zero-training-data 5-model subset scored **AILANG 96.8%** against Vera 98.2%, Aver 92.4% and Python 97.0% ([vera-bench](https://github.com/aallan/vera-bench)).
- Biggest weakness: on the only comparison graded by someone else, AILANG **lost to Python**. The catalogue's own framing of the open question is ecosystem depth: whether agent-authored development can produce a standard library competitive with MoonBit's roughly two-year head start ([catalogue](https://agentlanguages.dev/languages/ailang/)). "No loops" is a large bet that models generate recursion more reliably than iteration, and no published number isolates it.
- Sources: https://github.com/sunholo-data/ailang · https://agentlanguages.dev/languages/ailang/ · https://github.com/aallan/vera-bench

**Aver**
- Origin: `jasisz` — [agentlanguages.dev/languages/aver](https://agentlanguages.dev/languages/aver/)
- First public: **February 2026**; repo created 2026-02-24 ([github.com/jasisz/aver](https://github.com/jasisz/aver))
- Category: Verification-oriented
- Status (2026): **actively maintained** — last push **2026-09-12**, 60 stars, MIT, Rust; v0.21 on crates.io as `aver-lang` ([repo](https://github.com/jasisz/aver); [catalogue](https://agentlanguages.dev/languages/aver/)).
- Primary claim: co-locate intent, effects and verification with the body. Every function carries a prose intent (`?`), an effect declaration (`!`), and a colocated `verify` block; pure verify blocks **export as Lean 4 theorems and Dafny lemmas**, and effectful ones lift through "Oracle," which quantifies over bounded effect parameters in the exported theorem ([catalogue](https://agentlanguages.dev/languages/aver/)).
- Evidence it works: three working backends (bytecode VM, native Rust codegen, WASM-GC lowered to wasip2), demonstrated by seven games compiled to WebAssembly GC — Snake at 4.3 KiB, a roguelike at 25.6 KiB ([catalogue](https://agentlanguages.dev/languages/aver/)). In the one third-party grading, VeraBench's zero-training-data subset put **Aver at 92.4%**, the lowest of the four languages compared and 4.6 points below Python ([vera-bench](https://github.com/aallan/vera-bench)).
- Biggest weakness: it is the clearest counter-example to the field's premise — an artefact-rich, actively maintained verification language that **models write measurably worse than Python**. Proof export to Lean/Dafny is also an upper-bound check, not an automated gate: nothing published shows agents actually discharging those obligations unattended.
- Sources: https://github.com/jasisz/aver · https://agentlanguages.dev/languages/aver/ · https://github.com/aallan/vera-bench

**BHC / hx**
- Origin: Raffael Schneider — [agentlanguages.dev/languages/bhc-hx](https://agentlanguages.dev/languages/bhc-hx/)
- First public: **April 2026** per catalogue; `hx` repo created 2026-01-15 ([github.com/arcanist-sh/hx](https://github.com/arcanist-sh/hx))
- Category: Verification-oriented
- Status (2026): `hx` last push **2026-09-12**, 34 stars, MIT, Rust ([repo](https://github.com/arcanist-sh/hx)). Catalogue: hx v0.6.0 (Feb 2026), 12 releases, 129 commits; BHC v0.2.1 (Jan 2026), 389 commits, 11 stars, one contributor ([catalogue](https://agentlanguages.dev/languages/bhc-hx/)).
- Primary claim: **not a new language.** Schneider argues in a public essay trilogy at [raskell.io](https://raskell.io/articles/what-programming-languages-become-when-ai-writes-the-code/) that Haskell's types-as-proofs and purity already give LLMs the formal scaffolding they need, and that Haskell loses agent benchmarks because of toolchain friction — so the work is `hx` (a Rust binary wrapping GHC/Cabal/GHCup/HLS behind one interface) and BHC (an in-development Haskell 2026 compiler with per-profile runtimes) ([catalogue](https://agentlanguages.dev/languages/bhc-hx/)).
- Evidence it works: none yet. The catalogue is explicit: "no conformance suite or benchmark numbers ship in the repository today," parser/type-checker/Core IR/one codegen path are substantially complete, and WASM/GPU lowerings are in progress ([catalogue](https://agentlanguages.dev/languages/bhc-hx/)).
- Biggest weakness: the load-bearing empirical claim — that Haskell's poor agent-benchmark performance is *toolchain*, not *language* — is asserted and unmeasured. Writing a new Haskell compiler solo is also a multi-year arc with one contributor and 11 stars. The catalogue's own summary: "essays and infrastructure now, language-level claims later."
- Sources: https://github.com/arcanist-sh/hx · https://agentlanguages.dev/languages/bhc-hx/ · https://raskell.io/articles/what-programming-languages-become-when-ai-writes-the-code/

**Codex** (Damian Tedrow's language; unrelated to OpenAI Codex)
- Origin: Damian Tedrow with a multi-agent AI team — [agentlanguages.dev/languages/codex](https://agentlanguages.dev/languages/codex/)
- First public: **March 2026**; repo created 2026-03-14 ([github.com/damiant3/NewRepository](https://github.com/damiant3/NewRepository))
- Category: Verification-oriented (secondary: Orchestration-oriented)
- Status (2026): last push **2026-09-10**, 15 stars, **licence not published**, repo language reported as HTML ([repo](https://github.com/damiant3/NewRepository); [catalogue](https://agentlanguages.dev/languages/codex/)).
- Primary claim: a literate, self-hosting language on bare-metal x86-64 where the acceptance test for any change is that the self-host remains a **byte-identical fixed point of itself** with no OS, libc or GC underneath. Dependent, linear and effect types carry capabilities; proof blocks run a five-phase verifier; the `punctual` keyword enforces hard real-time bounds at compile time via instruction counting. Authored and maintained end-to-end by AI agents ([catalogue](https://agentlanguages.dev/languages/codex/)).
- Evidence it works: ~28,000 lines of Codex across 54 files producing a 2.3 MB self-sustaining CDX binary that boots under QEMU multiboot, compiles its full source in a project-measured **22 seconds on bare metal**, and verifies its own Ed25519 signature; a 137-test battery plus fixed-point, text-round-trip and semantic-equivalence gates completing in ~140 seconds; 377 library modules across 26 quires; an OS kernel with 22 drivers; a full TCP/IP stack; 53 transpiler plugs; 630 application modules across 47 apps; 9 IoT board drivers with 88 register-level sub-tests. **Self-hosting about a week from first commit; reference compiler retired at 41 days** ([catalogue](https://agentlanguages.dev/languages/codex/)).
- Biggest weakness: every number is self-reported inside a repository named `NewRepository` with **no published licence**, 15 stars, and a claimed scope (compiler + OS + TCP/IP + 3D engine + real-time verifier, agent-authored in weeks) that is extraordinary enough to require independent reproduction before it should be believed. None exists.
- Sources: https://github.com/damiant3/NewRepository · https://agentlanguages.dev/languages/codex/

**Hale**
- Origin: Riley Rook — [agentlanguages.dev/languages/hale](https://agentlanguages.dev/languages/hale/)
- First public: **May 2026**; repo created 2026-05-15 ([github.com/hale-lang/hale](https://github.com/hale-lang/hale))
- Category: Verification-oriented (secondary: Orchestration-oriented)
- Status (2026): **actively maintained** — last push **2026-09-12**, 35 stars, Apache-2.0, Rust ([repo](https://github.com/hale-lang/hale)).
- Primary claim: one primitive — the **locus** — replaces class, module, actor and service; loci communicate over a typed topic bus, and the same source runs as a test, a single binary, or a mesh of binaries by editing only the main locus. Contracts scale from per-function effect certificates (`@no_syscall`, `@effects(only:)`) to program-wide reachability claims (`forbid reaches(A, B)`) checked at compile time, with **unknown call targets treated as violations** and minimal countermodel witnesses on failure. The case for LLM authorship is subtractive: no async colouring, no lifetimes, no lock selection ([catalogue](https://agentlanguages.dev/languages/hale/)).
- Evidence it works: an MCP server shipped inside the compiler binary, an LSP with contract-surfacing hover, and machine-readable topology dumps with countermodel witnesses; a benchmark repo compares Hale against Go, Node and Python at [hale-lang/bench](https://github.com/hale-lang/bench) ([catalogue](https://agentlanguages.dev/languages/hale/)). I could not confirm the bench result values from a fetched page: `n.a.`
- Biggest weakness: "fail closed on unresolvable indirection" is the crux and the cost — a checker that treats any unknown call target as a violation will reject large classes of legitimate dynamic code, and no published number shows how often that happens in agent-written programs. No model-success benchmark; four months old; 35 stars.
- Sources: https://github.com/hale-lang/hale · https://agentlanguages.dev/languages/hale/

**Intent**
- Origin: `lhaig` — [agentlanguages.dev/languages/intent](https://agentlanguages.dev/languages/intent/)
- First public: **February 2026**; repo created 2026-02-13 ([github.com/lhaig/intent](https://github.com/lhaig/intent))
- Category: Verification-oriented
- Status (2026): last push **2026-07-16**, 7 stars, Apache-2.0, Go; v0.2.0 released 16 Feb 2026; catalogue records last commit 25 March 2026 with LSP, REPL and release-mode contract stripping unbuilt ([repo](https://github.com/lhaig/intent); [catalogue](https://agentlanguages.dev/languages/intent/)).
- Primary claim: mandatory contracts everywhere — `requires`/`ensures` on functions, `invariant` on entities, `invariant`+`decreases` on loops. An `intent` block links natural-language goals to specific contract references via `verified_by`, and **the compiler refuses to resolve a reference with no matching contract**. `intentc verify` discharges what it can to Z3; the remainder becomes enforced runtime checks in Rust (panic), JS (throw) or WASM (trap) from one source file ([catalogue](https://agentlanguages.dev/languages/intent/)).
- Evidence it works: milestones 1–6 complete (language surface, Z3 verifier, three backends), a 1,764-line design spec, and a four-target showcase — CLI binary, browser dashboard, Node server, and a **155-byte** browser WASM artefact — running against unmodified compiler output ([catalogue](https://agentlanguages.dev/languages/intent/)).
- Biggest weakness: no evidence models write valid contracts. The mechanism guarantees an `intent` block *names* a contract, not that the contract captures the intent — the gap Thermite's authors describe as reviewable evidence rather than a closed theorem. 45 commits, 5–7 stars, idle since March/July 2026.
- Sources: https://github.com/lhaig/intent · https://agentlanguages.dev/languages/intent/

**Modula-9**
- Origin: Alex T. Vermeulen — [agentlanguages.dev/languages/m9](https://agentlanguages.dev/languages/m9/)
- First public: **August 2026**; repo created 2026-08-29 ([github.com/atverm/m9c](https://github.com/atverm/m9c))
- Category: Verification-oriented (secondary: Syntactic)
- Status (2026): **actively maintained** — last push **2026-09-12**, 0 stars, GPL-3.0; self-hosting at v0.4.1 (2 Sep 2026) ([repo](https://github.com/atverm/m9c); [catalogue](https://agentlanguages.dev/languages/m9/)).
- Primary claim: a Wirth-lineage language for code an agent writes and a human reviews — mandatory range and overflow checks with **no flag to disable them**, and correctness that is *differential rather than deductive*: an implementation is validated by executing it against the code it replaces, in whatever language the incumbent is written in. Its motto: "Nothing here is asserted; it is compared against an oracle" ([catalogue](https://agentlanguages.dev/languages/m9/)).
- Evidence it works: mandatory checks cost **about 3% of runtime**; the bootstrap gate compares 31 modules across three stages requiring stage 3 = stage 2 = stage 1; the emitted C is checked in so a fresh clone builds with `cc` alone; 33-module, ~29,300-line stdlib including an M9-written language server (`m9lsp`) that republishes `m9c --check` diagnostics so an editor squiggle cannot disagree with the build; `m9fmt` gated for idempotence and comment survival across the corpus. The compiler, stdlib, two ports and the tutorial service were written by an agent under the author's review in the project's **first two weeks** ([catalogue](https://agentlanguages.dev/languages/m9/)).
- Biggest weakness: the differential-oracle method only works where an incumbent implementation exists — it validates *ports*, not new functionality, which is most of what agents are asked to write. Two weeks old, 0 stars, no package registry, and the Object Pascal oracle is a permanent dependency.
- Sources: https://github.com/atverm/m9c · https://agentlanguages.dev/languages/m9/

**NanoLang**
- Origin: Jordan Hubbard (FreeBSD co-founder; Senior Director, GPU Compute Software at Nvidia) — [agentlanguages.dev/languages/nanolang](https://agentlanguages.dev/languages/nanolang/)
- First public: **September 2025**; repo created 2025-09-30 ([github.com/jordanhubbard/nanolang](https://github.com/jordanhubbard/nanolang))
- Category: Verification-oriented (secondary: Syntactic)
- Status (2026): **actively maintained** — last push **2026-09-12**, **627 stars** (third-highest in the catalogue), Apache-2.0, C; v3.3.7 (April 2026), 51 tagged releases, ~2,156 commits, bootstrap 100% ([repo](https://github.com/jordanhubbard/nanolang); [catalogue](https://agentlanguages.dev/languages/nanolang/)).
- Primary claim: **mandatory shadow test blocks on every function** — the compiler refuses to compile a function without one — plus 6,170 lines of Coq proving the language core (193 theorems, zero axioms), with multi-target codegen across C, WASM, LLVM IR, PTX and RISC-V ([catalogue](https://agentlanguages.dev/languages/nanolang/)).
- Evidence it works: the compiler compiles itself; 51 releases; 18 keywords against C's 32; Simon Willison tested it ([HN thread](https://news.ycombinator.com/item?id=46684958)). No model-success benchmark.
- Biggest weakness: the author disclaims the premise. Hubbard on HN: "Nanolang is a total thought experiment," and the repo's own GitHub topics include `thought-exercise` and `vibe-coding`, applied by him. The README notes the language has "been used in production by exactly one person, who also wrote it." The proof scope is also narrower than it sounds — **NanoCore is a proved subset, not the surface language**; algebraic effects, async/await, FFI, the VM and multi-target codegen sit outside the proof set. A top comment on the thread states the field's core objection: "llms don't need new languages, we do" ([HN](https://news.ycombinator.com/item?id=46684958); [catalogue](https://agentlanguages.dev/languages/nanolang/)).
- Sources: https://github.com/jordanhubbard/nanolang · https://agentlanguages.dev/languages/nanolang/ · https://news.ycombinator.com/item?id=46684958

**Pact** (Viktor Kikot's language — **not** Kadena's Pact; see exclusions)
- Origin: Viktor Kikot — [agentlanguages.dev/languages/pact](https://agentlanguages.dev/languages/pact/)
- First public: **April 2026**; repo created 2026-04-02 ([github.com/KikotVit/pact-lang](https://github.com/KikotVit/pact-lang))
- Category: Verification-oriented
- Status (2026): last push **2026-04-14**, 1 star, MIT, Rust ([repo](https://github.com/KikotVit/pact-lang)). Catalogue: v0.5, six tagged releases, 204 commits, 496+ tests ([catalogue](https://agentlanguages.dev/languages/pact/)). Five months idle.
- Primary claim: built "so that LLMs can read, write, and debug backend code with fewer iterations" — every function and route opens with an `intent` clause and a `needs` list declaring effects (`needs db, time`); errors are part of the signature (`-> User or NotFound`); data flows through left-to-right pipelines; and the runtime ships HTTP, SSE, SQLite, JWT, an LSP and a 5-tool MCP server inside a single ~5 MB binary. The bet is that surfacing intent, effects and outcomes at the signature level lets agents skip the reverse-engineering pass ([catalogue](https://agentlanguages.dev/languages/pact/); [repo](https://github.com/KikotVit/pact-lang)).
- Evidence it works: 496–515+ tests, 204–223 commits, a batteries-included single binary ([catalogue](https://agentlanguages.dev/languages/pact/); [repo](https://github.com/KikotVit/pact-lang)). No benchmark of the "fewer iterations" claim.
- Biggest weakness: the README is explicit that it works for small APIs and CRUD services and is **not production-ready**; it is tree-walking-interpreted, at 1 star, and has not been touched since April 2026 ([catalogue](https://agentlanguages.dev/languages/pact/)). The name also collides badly with Kadena's established Pact.
- Sources: https://github.com/KikotVit/pact-lang · https://agentlanguages.dev/languages/pact/

**Prove**
- Origin: Magnus Knutas (Botwork) — [agentlanguages.dev/languages/prove](https://agentlanguages.dev/languages/prove/)
- First public: **February 2026**; site [prove.botwork.se](https://prove.botwork.se)
- Category: Verification-oriented
- Status (2026): v1.3.1 (April 2026) with a documented release history — v1.0.0 (22-module stdlib, C codegen, region memory, 13-pass optimiser, ML-powered LSP), v1.1.0 (March 2026, structured concurrency + GUI), v1.2.0, v1.3.0/1.3.1 (April 2026, tree-sitter sole parser). **No GitHub repo** — source is on a self-hosted Gitea at code.botwork.se ([catalogue](https://agentlanguages.dev/languages/prove/)).
- Primary claim: verbs encode intent and IO category directly in the declaration (`transforms`, `validates`, `derives`, `creates`, `matches`; `inputs`, `outputs`, `dispatches`; `attached`, `detached`, `listens`, `renders`), and the compiler enforces verb semantics, refinement-type constraints and `ensures`/`requires`/`explain` contracts ([catalogue](https://agentlanguages.dev/languages/prove/)).
- Evidence it works: a clear multi-release trajectory and a 22-module stdlib ([catalogue](https://agentlanguages.dev/languages/prove/)). No benchmark.
- Biggest weakness: **the licence forbids the thing the category is about.** The Prove Source License v1.0 covers all `.prv` source and "prohibits AI training use, dataset inclusion, embedding, and synthetic data generation" ([catalogue](https://agentlanguages.dev/languages/prove/)) — so Prove code can never enter model weights, guaranteeing the cold-start penalty is permanent. Combined with no GitHub presence, it is the least inspectable entry in the catalogue.
- Sources: https://agentlanguages.dev/languages/prove/ · https://prove.botwork.se

**reqlan**
- Origin: Tony Cerqui — [agentlanguages.dev/languages/reqlan](https://agentlanguages.dev/languages/reqlan/)
- First public: **June 2026**; repo created 2026-06-21 ([github.com/littletuna4/reqlan](https://github.com/littletuna4/reqlan))
- Category: Verification-oriented (secondary: Syntactic)
- Status (2026): last push **2026-09-09**, 3 stars, AGPL-3.0-only, TypeScript ([repo](https://github.com/littletuna4/reqlan)).
- Primary claim: the model does not need to hold the specification in its head — the graph has to still resolve. Named requirement "ideas" in `.rq` files carry edges to other ideas, files, symbols and tests; **dangling edges fail the checker**; and the same index feeds an LSP, a CLI, and an MCP server so an agent can query a neighbourhood instead of ingesting a specs folder. Implementation stays in the host language ([catalogue](https://agentlanguages.dev/languages/reqlan/)).
- Evidence it works: a Langium grammar, editor extension with LSP, CLI, native Rust core, MCP server and HTML export all ship ([catalogue](https://agentlanguages.dev/languages/reqlan/)). No benchmark.
- Biggest weakness: the catalogue states the limits plainly — "It is not a general-purpose programming language or a theorem prover. The file extension collides with an existing RDF query language. **The graph is only as good as the edges people keep drawing**" ([catalogue](https://agentlanguages.dev/languages/reqlan/)). AGPL-3.0-only also limits commercial adoption.
- Sources: https://github.com/littletuna4/reqlan · https://agentlanguages.dev/languages/reqlan/

**SEMAPRAX**
- Origin: Wavect GmbH — [agentlanguages.dev/languages/semaprax](https://agentlanguages.dev/languages/semaprax/)
- First public: **August 2026**; repo created 2026-08-07 ([github.com/wavect/semaprax](https://github.com/wavect/semaprax))
- Category: Verification-oriented (secondary: Orchestration-oriented)
- Status (2026): **actively maintained** — last push **2026-09-12**, 18 stars, Apache-2.0, Rust; public **prerelease**, self-described pre-alpha ([repo](https://github.com/wavect/semaprax); [catalogue](https://agentlanguages.dev/languages/semaprax/)).
- Primary claim: keep readable source as the canonical Git projection while exposing a deterministic, versioned **semantic graph** as the preferred agent interface. Persistent declaration IDs separate identity from display names, and revision-bound semantic patches **fail closed on stale source**; types, effects, contracts, ownership and call relations resolve before native and WASM lowering from shared validated HIR ([catalogue](https://agentlanguages.dev/languages/semaprax/)).
- Evidence it works: a working compiler and CLI that parse, format, check, run and test multi-file projects; emit semantic-graph JSON and bounded context; apply semantic patches; and build native, Core WASM, browser, npm and Rust artefacts, with a VS Code extension, MCP workspace adapter, cross-platform CI, and a quality script tying product claims to executable completion-matrix rows ([catalogue](https://agentlanguages.dev/languages/semaprax/)).
- Biggest weakness: unusually well self-documented. The repo disclaims a general ownership/lifetime system, a package ecosystem, stable ABIs, a production toolchain and complete cross-platform validation; **contracts are runtime checks today, not SMT proofs**; and the graph machinery imposes more concepts and versioned schemas than a text-only language, with full graph output "far larger than source" — so the compiler's own guidance tells agents to read source when it fits ([catalogue](https://agentlanguages.dev/languages/semaprax/)). That last point undercuts the graph-first premise.
- Sources: https://github.com/wavect/semaprax · https://agentlanguages.dev/languages/semaprax/

**Thermite**
- Origin: `dollspace-gay` and `maxinelevesque` — [agentlanguages.dev/languages/thermite](https://agentlanguages.dev/languages/thermite/)
- First public: **June 2026**; repo created 2026-06-04 ([github.com/dollspace-gay/Thermite](https://github.com/dollspace-gay/Thermite))
- Category: Verification-oriented (secondary: Syntactic)
- Status (2026): last push **2026-08-08**, 53 stars, MIT, Rust + Lean 4 ([repo](https://github.com/dollspace-gay/Thermite)).
- Primary claim: treat verification as a **per-obligation evidence record** rather than a binary compiler verdict. Every function declares `req`, `ens` and `fx`; the Forge tool records, for each clause, whether it received checked reconstruction, an all-input proof, bounded checking, runtime enforcement, or an explicit trust escape — and counterexamples remain failures rather than being relabelled as a lower assurance tier ([catalogue](https://agentlanguages.dev/languages/thermite/)).
- Evidence it works: Forge parses and checks Thermite, lowers certified programs to Rust, builds native executables, and emits freestanding `no_std` libraries; the repo ships conformance programs, proof-bearing gates, translation-validation batteries, and an audit command that re-derives the recorded trust chain ([catalogue](https://agentlanguages.dev/languages/thermite/)). No model benchmark.
- Biggest weakness: the project states the honest limit better than its critics could. Operationally, "Verus, Lean, Mathlib, Z3, the reconstruction tools, and optional bounded-checking tooling sit around the Rust compiler; the complete path is tested on x86-64 Linux," making it heavier and less portable than the syntax suggests. Semantically: "machine checks can establish that an implementation meets its formal contract, while the correspondence between that contract and the intended behaviour remains reviewable evidence rather than a closed theorem" ([catalogue](https://agentlanguages.dev/languages/thermite/)) — which is the ceiling on the entire verification camp.
- Sources: https://github.com/dollspace-gay/Thermite · https://agentlanguages.dev/languages/thermite/

**Vera**
- Origin: Alasdair Allan (also the catalogue's maintainer — a conflict of interest worth stating) — [veralang.dev](https://veralang.dev/)
- First public: repo created **2026-02-22**; v0.1.0 shipped 4 July 2026 ([github.com/aallan/vera](https://github.com/aallan/vera); [catalogue](https://agentlanguages.dev/languages/vera/))
- Category: Verification-oriented
- Status (2026): **the most actively developed entry** — last push **2026-09-12**, 413 stars, MIT, Python reference compiler; latest release v0.0.158 (22 May 2026 tag), catalogue records v0.1.9 at 5 Aug 2026 after 205 tagged releases and ~2,400 commits ([repo](https://github.com/aallan/vera); [catalogue](https://agentlanguages.dev/languages/vera/)).
- Primary claim: "a programming language designed for large language models to write." **There are no variable names** — bindings are typed De Bruijn slots (`@Int.0`); contracts are mandatory; effects are typed; Z3 discharges obligations; programs compile to WebAssembly and run under wasmtime, in-browser, or as a `wasi:http` component that unmodified `wasmtime serve` will run ([repo](https://github.com/aallan/vera); [catalogue](https://agentlanguages.dev/languages/vera/)).
- Evidence it works: the strongest evidence base in the field. 9,382 tests at 95% coverage (80% CI floor), 196 conformance programs across 9 of 14 spec chapters, 164 builtins ([catalogue](https://agentlanguages.dev/languages/vera/)). **VeraBench** (28 July 2026 sweep, 9 model configurations, 3 providers, all 60 problems): **Vera 98.7%, Python 96.7%, TypeScript 99.7%**; Vera beats Python for 6 of 9 models by 3–5 points, draws 1, loses 2; against TypeScript it wins 1, draws 5, loses 3. On a zero-training-data 5-model subset: Vera 98.2%, AILANG 96.8%, Aver 92.4%, Python 97.0%. Vera-from-natural-language scores 87–97%. Only 1 of 540 Vera programs never compiled, and all 4 model refusals occurred in Python/TypeScript ([vera-bench](https://github.com/aallan/vera-bench)).
- Biggest weakness: **Vera loses to TypeScript**, which hit 100% for 8 of 9 models — so the best result the field has produced still shows a mainstream language matching or beating the purpose-built one. The benchmark is authored, run and graded by the language's own author, who also maintains the catalogue that ranks it; the project publishes the caveats itself (single run per model, no pass@k, one problem worth 1.7 points so most gaps are one or two problems wide) ([catalogue](https://agentlanguages.dev/languages/vera/); [vera-bench](https://github.com/aallan/vera-bench)). Sixty problems is also a small, self-selected suite.
- Sources: https://github.com/aallan/vera · https://github.com/aallan/vera-bench · https://agentlanguages.dev/languages/vera/ · https://veralang.dev/

**Vow**
- Origin: Paulo Matos — [agentlanguages.dev/languages/vow](https://agentlanguages.dev/languages/vow/)
- First public: repo created **2026-02-25**; v0.2.0 released 20 May 2026 ([github.com/vow-lang/vow](https://github.com/vow-lang/vow); [catalogue](https://agentlanguages.dev/languages/vow/))
- Category: Verification-oriented
- Status (2026): **actively maintained** — last push **2026-09-11**, 8 stars, MIT, Rust ([repo](https://github.com/vow-lang/vow)).
- Primary claim: every function declares a `vow` block of `requires`/`ensures` and loops carry `invariant`; the compiler lowers these to obligations for the **ESBMC bounded model checker** before any code ships. Diagnostics emit JSON with counterexamples and explicit Caller/Callee blame, and the compiler binary embeds and auto-installs a Claude Code skill generated from the same compiler version — "the source of truth for any harness writing Vow code; cannot drift from the toolchain you are running" ([catalogue](https://agentlanguages.dev/languages/vow/)).
- Evidence it works: self-hosting under a **bootstrap triple test** — stage 0 → compiler A → compiler B → compiler C, with `sha256sum` of B and C required to match; mutation testing as `vowc mutants` with a tiered oracle; and three substantial example programs (a CDCL SAT solver with watched literals and Luby restarts, a UCI chess engine, and a Lean 4 kernel checker targeting the Lean Kernel Arena). A `benchmarks/` directory implements the vericoding benchmark ([arXiv:2509.22908](https://arxiv.org/abs/2509.22908)) ([catalogue](https://agentlanguages.dev/languages/vow/)).
- Biggest weakness: the author names it himself — "ESBMC integration is in place and discharges contracts for the example programs, but the corners are still being found… The compiler is written in Vow but **its own vows are not all verified end-to-end**. Closing that loop is the single most important piece of work ahead" ([catalogue](https://agentlanguages.dev/languages/vow/)). Bounded model checking is also bounded: it proves absence of violations up to a depth, not in general. 8 stars.
- Sources: https://github.com/vow-lang/vow · https://agentlanguages.dev/languages/vow/

**Zero**
- Origin: Chris Tate and Matt Van Horn / **Vercel Labs** — [github.com/vercel-labs/zerolang](https://github.com/vercel-labs/zerolang)
- First public: introduced **15 May 2026**; repo created 2026-05-15 ([repo](https://github.com/vercel-labs/zerolang); [InfoQ](https://www.infoq.com/news/2026/08/vercel-ships-zero-ai/))
- Category: Verification-oriented (secondary: Syntactic)
- Status (2026): **by far the most-starred entry — 5,360 stars** — Apache-2.0, C, 658 commits, 8 contributors, v0.2.0 tagged 28 May 2026, last commit 30 May 2026 ([repo](https://github.com/vercel-labs/zerolang)). InfoQ reports the line moved on to v0.3.x and a current v0.3.4 with graph-first mode, a `zero import` ~12× speedup in v0.3.2, and >5,200 stars ([InfoQ](https://www.infoq.com/news/2026/08/vercel-ships-zero-ai/)).
- Primary claim: "The programming language for agents" — an "experimental graph-first programming language where agents work with semantic program structure instead of raw source text" ([repo](https://github.com/vercel-labs/zerolang)). Concretely: structured JSON diagnostics with **stable error codes** (`NAM003` means "unknown identifier" and will keep meaning that), typed repair plans an agent applies without parsing prose, `zero fix --plan --json`, `zero query`/`zero patch`, graph hashes, `--json` on every subcommand, version-matched skills served through the CLI, capability objects on `main`, no hidden allocator, no implicit async ([catalogue](https://agentlanguages.dev/languages/zero/); [InfoQ](https://www.infoq.com/news/2026/08/vercel-ships-zero-ai/)).
- Evidence it works: Hello World at **16.2 KiB building in 1 ms**; direct ELF/Mach-O/PE emitters with no LLVM; two compilers in-tree (`zero-c` C bootstrap and a self-hosting `compiler-zero`); v0.3.0 rejects source-projection input outright; a World capability is required for any function touching the outside world ([InfoQ](https://www.infoq.com/news/2026/08/vercel-ships-zero-ai/); [catalogue](https://agentlanguages.dev/languages/zero/)).
- Biggest weakness: **no model-success benchmark at all** — the best-resourced, most-starred project in the field publishes compiler metrics, not evidence that agents write Zero better than TypeScript. The README and homepage are explicit that this is a "pre-1 experiment": syntax and APIs are not a contract, breaking changes are expected, **security vulnerabilities should be expected**, and Vercel Labs recommends running Zero only in isolated environments; cross-compilation covers a documented subset and there is no package registry ([catalogue](https://agentlanguages.dev/languages/zero/)). The reception included open hostility to the pattern of Vercel Labs AI launches ([Darren Shepherd](https://x.com/ibuildthecloud/status/2055848496163598726)). Its star count also reflects Vercel's distribution, not usage.
- Sources: https://github.com/vercel-labs/zerolang · https://www.infoq.com/news/2026/08/vercel-ships-zero-ai/ · https://agentlanguages.dev/languages/zero/ · https://x.com/ibuildthecloud/status/2055848496163598726

**Jacquard** *(not in the agentlanguages.dev catalogue)*
- Origin: Josh Winters / FriendMachine — [research.friendmachine.co/jacquard](https://research.friendmachine.co/jacquard/)
- First public: repo created **2026-07-06**; announced on Hacker News 14 July 2026 ([github.com/jbwinters/jacquard-lang](https://github.com/jbwinters/jacquard-lang); [HN](https://news.ycombinator.com/item?id=48894630))
- Category: Verification-oriented
- Status (2026): **actively maintained** — last push **2026-09-12**, 119 stars, Apache-2.0, OCaml ([repo](https://github.com/jbwinters/jacquard-lang)). Self-described "a research prototype, not a production language" at v0.1.
- Primary claim: "a small programming language designed for a regime in which most code is written by machine-learning models and reviewed by people" ([repo](https://github.com/jbwinters/jacquard-lang)). Effects (network, files, clock, randomness) appear in signatures and the **runtime refuses ungranted effects**; identity is content-addressed and semantic; algebraic effects support multi-shot handlers; a Warp test framework ships alongside.
- Evidence it works: the design method is the notable datum — the language was created by having AI analyse the ASTs of mainstream languages to find what models handle reliably ([HN](https://news.ycombinator.com/item?id=48894630)). 119 stars in two months with continuous commits. No model-success benchmark.
- Biggest weakness: no benchmark, self-labelled research prototype, and OCaml as the implementation language narrows the contributor pool. The "reviewed by people" framing also sits awkwardly with content-addressed semantic identity, which is precisely what makes review by reading diffs harder.
- Sources: https://github.com/jbwinters/jacquard-lang · https://news.ycombinator.com/item?id=48894630 · https://research.friendmachine.co/jacquard/

**Aether** *(not in the catalogue; archived)*
- Origin: **GoogleCloudPlatform** GitHub organisation — [github.com/GoogleCloudPlatform/aether](https://github.com/GoogleCloudPlatform/aether)
- First public: repo created **2025-08-22** ([repo](https://github.com/GoogleCloudPlatform/aether))
- Category: Verification-oriented (secondary: Syntactic)
- Status (2026): **ARCHIVED 7 May 2026** — 21 stars, 31 commits, Apache-2.0, Rust ([repo](https://github.com/GoogleCloudPlatform/aether)).
- Primary claim: "a modern systems programming language with **LLM-first design principles**" ([repo description](https://github.com/GoogleCloudPlatform/aether)) — S-expression syntax with an ownership model.
- Evidence it works: none. The repo describes itself as a "demonstration of vibe coding," "not intended for use in a production environment," and "not an officially supported Google product" ([repo](https://github.com/GoogleCloudPlatform/aether)).
- Biggest weakness: it is the field's clearest **negative result**: an LLM-first language launched under a Google Cloud Platform org, 31 commits, and archived within nine months. Worth including precisely as a survivorship datapoint.
- Sources: https://github.com/GoogleCloudPlatform/aether

---

### Orchestration-oriented

Entries whose primary move is coordinating agents, tools, effects and approvals — the program is a workflow, and the model is a runtime component rather than only an author.

**Boruna**
- Origin: `escapeboy` — [agentlanguages.dev/languages/boruna](https://agentlanguages.dev/languages/boruna/)
- First public: **April 2026** per catalogue; repo created 2026-02-21 ([github.com/escapeboy/boruna](https://github.com/escapeboy/boruna))
- Category: Orchestration-oriented (secondary: Verification-oriented)
- Status (2026): last push **2026-07-18**, 5 stars, MIT, Rust; v0.2.0, 34 commits, 1 release ([repo](https://github.com/escapeboy/boruna); [catalogue](https://agentlanguages.dev/languages/boruna/)).
- Primary claim: deterministic, capability-safe workflow execution for auditable AI systems. DAG workflows whose steps are `.ax` files; **every side effect — LLM calls, HTTP, database, filesystem — is declared and policy-gated at the VM level**; hash-chained tamper-evident evidence bundles; deterministic replay; human approval gates. "When a regulator asks what exactly ran and what the model returned, you can prove it" ([catalogue](https://agentlanguages.dev/languages/boruna/)).
- Evidence it works: 557+ tests passing across a 9-crate Rust workspace covering compiler, bytecode VM, orchestrator and MCP server (10 tools) ([catalogue](https://agentlanguages.dev/languages/boruna/)).
- Biggest weakness: the regulated-industries thesis is a bet on a market that has not arrived, made by one person with 5 stars and one release. Nothing published tests whether agents can *author* `.ax` workflows — the language's evidence is all about auditability of execution, not authorship.
- Sources: https://github.com/escapeboy/boruna · https://agentlanguages.dev/languages/boruna/

**Fabro**
- Origin: Bryan Helmkamp / Qlty Software — [agentlanguages.dev/languages/fabro](https://agentlanguages.dev/languages/fabro/)
- First public: **March 2026**; repo created 2026-03-13 ([github.com/fabro-sh/fabro](https://github.com/fabro-sh/fabro))
- Category: Orchestration-oriented
- Status (2026): **actively maintained** — last push **2026-09-12**, **1,595 stars** (catalogue records 1,221), MIT, Rust ([repo](https://github.com/fabro-sh/fabro)).
- Primary claim: the coding-agent harness as a graph-execution problem. A `.fabro` file is a **Graphviz `digraph`** whose node shapes map to handler types (`Mdiamond` start, `box` agent step, `parallelogram` shell, `diamond` conditional, `hexagon` human gate, `component` parallel fan-out); edge labels carry a condition grammar; and a second CSS-like `model_stylesheet` notation assigns model, provider and `reasoning_effort` per node by selector precedence (`*` < shape < `.class` < `#id`) ([catalogue](https://agentlanguages.dev/languages/fabro/)).
- Evidence it works: 47 Rust crates, ~392k lines, 96 release tags, a daily changelog; and a self-published SWE-Bench-Lite scoreboard in `evals/swe-bench`: **GPT-5.4 at 65.7% resolve rate over 300 instances, Sonnet 4.6 at 57.7%, Haiku 4.5 baseline at 54.0%** ([catalogue](https://agentlanguages.dev/languages/fabro/)).
- Biggest weakness: the catalogue lists three honestly. "Documentation polish runs ahead of demonstrable adoption"; **no third-party reproduction of the SWE-Bench numbers has been published**; and "the graph-based-process pattern itself is not novel — LangGraph and other harnesses have been there." Concentration is extreme: Helmkamp authored 3,624 of 3,840 commits ([catalogue](https://agentlanguages.dev/languages/fabro/)).
- Sources: https://github.com/fabro-sh/fabro · https://agentlanguages.dev/languages/fabro/

**Lumen**
- Origin: `alliecatowo` — [agentlanguages.dev/languages/lumen](https://agentlanguages.dev/languages/lumen/)
- First public: **February 2026**; repo created 2026-02-13 ([github.com/alliecatowo/lumen](https://github.com/alliecatowo/lumen))
- Category: Orchestration-oriented
- Status (2026): last push **2026-07-01**, 1 star, MIT, Rust; v0.1.10 (Feb 2026), 352 commits ([repo](https://github.com/alliecatowo/lumen); [catalogue](https://agentlanguages.dev/languages/lumen/)).
- Primary claim: markdown-native source (`.lm.md` unifying code and docs in one artefact) with algebraic effects in signatures after a slash, `grants` constraining every tool call with explicit caps, `@deterministic` rejecting nondeterministic ops at compile time, and `pipeline`/`machine`/`memory` as first-class process kinds ([catalogue](https://agentlanguages.dev/languages/lumen/)).
- Evidence it works: ~5,300 passing tests across 12+ crates covering compiler, VM, runtime, CLI, LSP, JIT codegen, WASM bindings, tensor ops and provider integrations; LIR bytecode on a register VM with ~100 opcodes ([catalogue](https://agentlanguages.dev/languages/lumen/)).
- Biggest weakness: **it does not actually target the brief.** The catalogue says so: "Lumen is for humans authoring agent workflows, not for agents to author general code — it earns its place in the catalogue via the orchestration-camp criterion of first-class effect declarations for model calls" ([catalogue](https://agentlanguages.dev/languages/lumen/)). Also 1 star, and the contributor list reflects agent runs of the project's own multi-agent dev team rather than human adopters.
- Sources: https://github.com/alliecatowo/lumen · https://agentlanguages.dev/languages/lumen/

**Marsha**
- Origin: David Ellis / Alan Technologies — [agentlanguages.dev/languages/marsha](https://agentlanguages.dev/languages/marsha/)
- First public: **1 August 2023** (Show HN, item 36864021); repo created 2023-04-20 ([github.com/alantech/marsha](https://github.com/alantech/marsha); [catalogue](https://agentlanguages.dev/languages/marsha/))
- Category: Orchestration-oriented
- Status (2026): **abandoned.** The GitHub API reports a 2026-09-12 push (repo housekeeping), but the catalogue documents that the last maintainer activity on main — PRs #159–#164 and issue #165 — is dated **1–8 August 2023**, with no maintainer PRs or issues since; both principals moved on ([repo](https://github.com/alantech/marsha); [catalogue](https://agentlanguages.dev/languages/marsha/)). 467 stars, MIT, Python.
- Primary claim: **the LLM is the compiler.** A `.mrsh` file is a markdown-shaped spec with three sections per function — typed declaration, English description, input/output examples. The toolchain prompts an LLM to produce Python satisfying the declaration, synthesises a test suite from the examples, and iterates with corrective feedback until tests pass or the attempt budget is exhausted ([catalogue](https://agentlanguages.dev/languages/marsha/)).
- Evidence it works: essentially none. The only quantitative statement is a roadmap target — "We aim for 80%+ accuracy on our examples," with the roadmap looking to push that above 90%. The `setup.py` PyPI classifier is `Development Status :: 2 - Pre-Alpha`, and the compiler requires `OPENAI_ORG`/`OPENAI_SECRET_KEY` with other or local LLMs listed as planned but unimplemented ([catalogue](https://agentlanguages.dev/languages/marsha/)).
- Biggest weakness: it is the field's oldest and most complete failure case — a well-starred 2023 project that never got past pre-alpha and was dropped within four months. The catalogue includes it "because the 'LLM is the compiler' framing it shipped in 2023 anticipates the 2025 orchestration papers in this camp, **not because the alpha implementation is under active development**" ([catalogue](https://agentlanguages.dev/languages/marsha/)).
- Sources: https://github.com/alantech/marsha · https://agentlanguages.dev/languages/marsha/

**Pel**
- Origin: Behnam Mohammadi (CMU Tepper PhD 2025; now UT Dallas Jindal School, Quantitative Marketing) — [arXiv:2505.13453](https://arxiv.org/abs/2505.13453)
- First public: arXiv **v1 3 April 2025**, v2 9 June 2025 ([arXiv](https://arxiv.org/abs/2505.13453))
- Category: Orchestration-oriented
- Status (2026): **paper only.** "No public implementation, package, or repository has been released; independent evaluation would require either a reference compiler or access to the BEACON codebase" ([catalogue](https://agentlanguages.dev/languages/pel/)). Cited by 5 ([arXiv](https://arxiv.org/abs/2505.13453)).
- Primary claim: a homoiconic, Lisp-shaped language (also drawing on Elixir, Gleam and Haskell) whose **minimal grammar is designed for constrained LLM generation**, with capability control expressed at the syntax level, piping, closures, natural-language conditions, a REPeL interaction loop using Common Lisp-style restarts, and automatic parallelisation from static dependency analysis ([arXiv](https://arxiv.org/abs/2505.13453)).
- Evidence it works: **none.** The catalogue states it directly: "The paper is a design and rationale document rather than a benchmark study." Pel is the implementation substrate for the author's separate BEACON multi-agent framework (SSRN 5191583), which reports advantages over single-model generative AI on retrieval accuracy, cost-efficiency and interpretability — but those are BEACON's numbers, not Pel's ([catalogue](https://agentlanguages.dev/languages/pel/); [arXiv](https://arxiv.org/abs/2505.13453)).
- Biggest weakness: a single-author preprint with no implementation, no benchmark, and 5 citations, arguing for grammar design choices whose entire justification is that they suit constrained decoding — a claim that grammar-constrained decoding research (below) evaluates empirically and Pel does not.
- Sources: https://arxiv.org/abs/2505.13453 · https://agentlanguages.dev/languages/pel/

**Plasm**
- Origin: Ryan Roberts / PlasmTools — [agentlanguages.dev/languages/plasm](https://agentlanguages.dev/languages/plasm/)
- First public: **April 2026**; repo created 2026-04-24 ([github.com/PlasmTools/plasm-core](https://github.com/PlasmTools/plasm-core))
- Category: Orchestration-oriented (secondary: Syntactic)
- Status (2026): last push **2026-09-11**, 9 stars, Apache-2.0 reported by the API; catalogue records **Business Source License 1.1** with a 2030-04-24 change date to Apache-2.0 ([repo](https://github.com/PlasmTools/plasm-core); [catalogue](https://agentlanguages.dev/languages/plasm/)). v0.1.x.
- Primary claim: APIs are authored as typed capability graphs, and agents write compact path-expression programs against a **live teaching table of opaque `e#`/`m#`/`p#`/`r#` symbols** instead of memorising vendor JSON schemas; programs lower to reviewable execution plans (dry-run before live HTTP), with federated sessions keeping one append-only symbol space across catalogs ([catalogue](https://agentlanguages.dev/languages/plasm/)).
- Evidence it works: an executable `plasm_language_matrix` end-to-end conformance suite (parse → DAG → dry → live) and dozens of packaged API catalogs (GitHub, Linear, Notion, …) shipping as capability-graph specs plus mappings ([catalogue](https://agentlanguages.dev/languages/plasm/)). No model benchmark.
- Biggest weakness: the catalogue notes conformance runs "against dedicated fixtures — **not production API catalogs**," and that the Lean-oriented formal sketch in the language definition "is not a complete verification story" ([catalogue](https://agentlanguages.dev/languages/plasm/)). The BSL 1.1 licence excludes competing execution-as-a-service products, and session-scoped opaque symbols mean an agent's program is meaningless without the live session — the opposite of a durable artefact.
- Sources: https://github.com/PlasmTools/plasm-core · https://agentlanguages.dev/languages/plasm/

**Quasar**
- Origin: Stephen Mell, Botong Zhang, David Mell, Shuo Li, Ramya Ramalingam, Nathan Yu, Steve Zdancewic, Osbert Bastani (University of Pennsylvania) — [arXiv:2506.12202](https://arxiv.org/abs/2506.12202)
- First public: arXiv **v1 13 June 2025** ([arXiv](https://arxiv.org/abs/2506.12202))
- Category: Orchestration-oriented (secondary: Verification-oriented)
- Status (2026): **paper only, under review.** "No public implementation, repository, or release has been published; the OpenReview submission is under review at the time of cataloguing, and conference acceptance has not been announced" ([catalogue](https://agentlanguages.dev/languages/quasar/)).
- Primary claim: LLMs write a **Python subset** that is transpiled to Quasar, which inserts the guarantees underneath — so the model keeps emitting a language it already knows while the runtime gains uncertainty quantification and approval inference ([arXiv](https://arxiv.org/abs/2506.12202)).
- Evidence it works: **the strongest peer-review-track numbers in the field.** On the ViperGPT visual-question-answering agent over GQA, LLMs emitting Quasar instead of Python retain task performance while cutting execution time by **42%** and user-approval interactions by **52%**, with conformal prediction achieving a chosen target coverage. The OpenReview revision (id TvpaeQVTGQ) extends the evaluation to the CaMeL agent on the AgentDojo prompt-injection benchmark and revises the headline figures upward to **up to 56%** execution-time reduction and **up to 53%** fewer approvals ([arXiv](https://arxiv.org/abs/2506.12202); [catalogue](https://agentlanguages.dev/languages/quasar/)).
- Biggest weakness: nothing to run — no transpiler, no runtime, no repo, and no accepted venue as of cataloguing, so the numbers are unreproducible by anyone but the authors (though the ViperGPT/GQA and CaMeL/AgentDojo baselines themselves are public). Note also that Quasar's own design **concedes the field's central premise**: the winning move was to keep Python as the authoring surface.
- Sources: https://arxiv.org/abs/2506.12202 · https://agentlanguages.dev/languages/quasar/

**Plumbing**
- Origin: William Waites (Chancellor's Fellow, University of Strathclyde) / Leith Document Company — [agentlanguages.dev/languages/plumbing](https://agentlanguages.dev/languages/plumbing/)
- First public: version 0p1, **March 2026** ([catalogue](https://agentlanguages.dev/languages/plumbing/); introduced on [John Carlos Baez's blog, 11 March 2026](https://johncarlosbaez.wordpress.com/2026/03/11/a-typed-language-for-agent-coordination/))
- Category: Orchestration-oriented (catalogue: "Adjacent")
- Status (2026): binary downloads for Linux x86_64 and macOS Apple Silicon shipping a compiler, interpreter and MCP server; **no public Git repository**; free for educational and personal use with a separate commercial licence ([catalogue](https://agentlanguages.dev/languages/plumbing/)).
- Primary claim: a typed language for agent coordination built on a **symmetric monoidal category** with typed channels — the bet being that orchestration languages eventually need a category-theoretic substrate, and that such a substrate is more valuable as a typed coordination layer than as another workflow framework ([catalogue](https://agentlanguages.dev/languages/plumbing/); [Baez blog](https://johncarlosbaez.wordpress.com/2026/03/11/a-typed-language-for-agent-coordination/)).
- Evidence it works: n.a. — no benchmark or evaluation published. The broader research programme is Waites' arXiv paper *Artificial Organisations* ([arXiv:2602.13275](https://arxiv.org/abs/2602.13275), 5 Feb 2026), which describes a Perseverance Composition Engine evaluated over 474 composition tasks — but that paper is about organisations, not about Plumbing's own performance, and the catalogue links it as Plumbing's "paper," which is a mismatch worth flagging.
- Biggest weakness: no repository, no benchmark, a proprietary commercial licence, and — per the catalogue's own classification — it is *infrastructure around* agent-authored code rather than a language agents author. Category theory as a coordination substrate is also a hard sell to the audience that writes agent harnesses.
- Sources: https://agentlanguages.dev/languages/plumbing/ · https://johncarlosbaez.wordpress.com/2026/03/11/a-typed-language-for-agent-coordination/ · https://arxiv.org/abs/2602.13275

**Spec**
- Origin: M. Abdullah Onus — [agentlanguages.dev/languages/spec](https://agentlanguages.dev/languages/spec/)
- First public: **April 2026**; repo created 2026-01-13 ([github.com/mronus/spec](https://github.com/mronus/spec))
- Category: Orchestration-oriented (catalogue: Unclassified)
- Status (2026): created 2026-01-13, last push **2026-01-14**, 8 stars, MIT, TypeScript ([repo](https://github.com/mronus/spec)). A v0.2 **design proposal** with a browser POC; one day of commits.
- Primary claim: a language-agnostic IR for agent-driven development. Six specialised agents (Product, Architect, Scrum, Developer, Tester, DevOps) collaborate to produce `.spec.ir` artefacts — contract, module, infrastructure, data, types, interfaces, functions, events, tests, pipeline — and separate language agents (Java, Go, Terraform) consume the IR downstream ([catalogue](https://agentlanguages.dev/languages/spec/)).
- Evidence it works: the only figure is a claim, not a measurement: incremental modification in **~200 tokens of context instead of the ~1,500 a comparable Java change requires** ([catalogue](https://agentlanguages.dev/languages/spec/)). A browser React/TypeScript POC orchestrates the six agents end-to-end with feedback loops and resume support.
- Biggest weakness: a thought experiment with no compiler (`.spec.ir` artefacts are not executable), one day of commits, and an unvalidated token claim. Its value is argumentative: the catalogue reads it as "a structured argument that 'language for agents to write' might be the wrong unit of analysis, and that 'IR for agents to coordinate over' is the unit that matters" ([catalogue](https://agentlanguages.dev/languages/spec/)).
- Sources: https://github.com/mronus/spec · https://agentlanguages.dev/languages/spec/

**BAML** *(not in the agentlanguages.dev catalogue)*
- Origin: BoundaryML, Seattle (Vaibhav Gupta et al.) — [github.com/BoundaryML/baml](https://github.com/BoundaryML/baml)
- First public: the project is described by its creators as ~3 years old as of July 2026 ([HN](https://news.ycombinator.com/item?id=48927917)); the original design essay is ["AI agents need a new syntax"](https://boundaryml.com/blog/ai-agents-need-new-syntax). Exact first-release date: `n.a.`
- Category: Orchestration-oriented
- Status (2026): **the most heavily released project here** — 9.2k stars, 636 releases, latest `0.18.1-nightly` on 2026-09-10, 114 contributors, Apache-2.0 ([repo](https://github.com/BoundaryML/baml)).
- Primary claim: "The programming language for agents" ([repo](https://github.com/BoundaryML/baml)) — a DSL for defining LLM functions and their schemas with fully-qualified names everywhere. Note the **repositioning**: the founding blog post is human-oriented ("Prompts should be easy to find and read" — [BoundaryML](https://boundaryml.com/blog/ai-agents-need-new-syntax)), while by 2026 the creators say "As we were building it, we realized humans weren't going to be the ones writing the code" ([HN](https://news.ycombinator.com/item?id=48927917)).
- Evidence it works: 9.2k stars and 114 contributors make it the most *adopted* entry in this report by a wide margin. Its one quantitative agent-authorship claim: "AI agents saved 30% tokens navigating baml codebases vs TypeScript ones" ([HN](https://news.ycombinator.com/item?id=48927917)) — self-reported, no methodology published.
- Biggest weakness: the agent-authorship framing is retrofitted onto a tool that succeeded as human developer ergonomics, and the creators still say "We do aim to keep humans in the loop" ([HN](https://news.ycombinator.com/item?id=48927917)). The repositioning drew direct scepticism on the same thread: "The 'for agents' is a bit of a turn off for me… Are they just trying to jump on the AI hype train" ([hdjrudni, HN](https://news.ycombinator.com/item?id=48927917)). BAML is also not a general-purpose language — it defines typed LLM function boundaries, with real logic still in Python/TypeScript.
- Sources: https://github.com/BoundaryML/baml · https://news.ycombinator.com/item?id=48927917 · https://boundaryml.com/blog/ai-agents-need-new-syntax

**CodeSpeak** *(not in the catalogue; borderline inclusion)*
- Origin: Andrey Breslav, original designer of Kotlin, now founder of CodeSpeak — [The Pragmatic Engineer interview, 12 Feb 2026](https://newsletter.pragmaticengineer.com/p/the-programming-language-after-kotlin)
- First public: interview published **12 February 2026**; the site's own launch date is not stated ([codespeak.dev](https://codespeak.dev/); [Pragmatic Engineer](https://newsletter.pragmaticengineer.com/p/the-programming-language-after-kotlin))
- Category: Orchestration-oriented
- Status (2026): **not yet launched.** The product site says "Until it launches, our web tool recovers what's already buried in your chats," offers an "Intent Studio," and publishes **no repository, no version, and no benchmark** ([codespeak.dev](https://codespeak.dev/)).
- Primary claim: "a new programming language based on English… neither a formal language, nor just prompting," designed for engineers rather than casual users, in which trivial code is replaced by concise plain-English descriptions ([Pragmatic Engineer](https://newsletter.pragmaticengineer.com/p/the-programming-language-after-kotlin)). The current product page frames it differently — as capturing intent from agent chats, turning it into structured requirements mapped to code, and enforcing them on every change ([codespeak.dev](https://codespeak.dev/)).
- Evidence it works: none. The only number anywhere is a target: it "aims to shrink typical application code by roughly 10x," leaving "the essence of software engineering — only the things the human uniquely knows" ([Pragmatic Engineer](https://newsletter.pragmaticengineer.com/p/the-programming-language-after-kotlin)).
- Biggest weakness: **the positioning has already drifted from "language" to "requirements-capture tool,"** which is itself informative about the difficulty of the language framing. There is no public implementation to inspect, no repo, and no measurement — its only real asset is the credibility of Kotlin's designer. Treat every 10x claim as marketing until an artefact ships.
- Sources: https://newsletter.pragmaticengineer.com/p/the-programming-language-after-kotlin · https://codespeak.dev/

---

## Academic work on LLM-friendly language design and constrained decoding

Each item is labelled **language proposal** (a new or modified language/representation intended for model authorship) or **decoding technique** (machinery that constrains a model's output into an existing language). Per the brief, these are distinct kinds of thing and are not mixed into the catalog counts above.

### Language proposals

**AI Coders Are Among Us: Rethinking Programming Language Grammar Towards Efficient Code Generation** — `language proposal` — [arXiv:2404.16333](https://arxiv.org/abs/2404.16333)
Zhensu Sun, Xiaoning Du, Zhou Yang, Li Li, David Lo (v1 25 Apr 2024, v2 14 Aug 2024; ISSTA'24). The strongest empirical paper in this area. The authors propose **AI-oriented grammar**: a grammar that abandons human readability in favour of what a model can emit in fewer tokens, and demonstrate it with **SimPy**, a Python variant preserving the identical AST. Measured token reduction of **13.5% with CodeLlama and 10.4% with GPT-4**, with round-trip conversion back to standard Python — so the gains are obtained without abandoning the Python ecosystem. This is the honest version of the syntactic camp's claim: the effect is real, it is roughly 10–13%, and it does not require a new language.

**Token Sugar** — `language proposal` — [arXiv:2512.08266](https://arxiv.org/abs/2512.08266)
Zhensu Sun, Xiaoning Du, Chengran Yang, Zhou Yang, Li Li, David Lo (9 Dec 2025; ASE'25). The same group's follow-up, replacing whole-grammar redesign with 799 pattern→shorthand pairs applied as a source-level sugar layer. Reports up to **15.1% source-token reduction** and up to **11.2% generation-token savings** at near-identical Pass@1. Important as a *counter-argument to new languages*: most of the token benefit the syntactic camp promises is reachable as a reversible transformation over an existing language, keeping the model's training-data advantage intact.

**LLMON: An LLM-native Markup Language** — `language proposal` — [arXiv:2603.22519](https://arxiv.org/abs/2603.22519)
Michael Hind, Basel Shbita, Bo Wu, Farhan Ahmed, Chad DeLuca, Nathan Fulton, David Cox, Dan Gutfreund (IBM Research; v1 23 Mar 2026, v2 30 Mar 2026). Proposes a markup language designed for model production and consumption rather than human authoring. The paper offers only "preliminary empirical evidence," which places it with the bulk of this field rather than with the Sun et al. line of work.

**Pel** — `language proposal` — [arXiv:2505.13453](https://arxiv.org/abs/2505.13453) — catalogued above. A design-and-rationale paper for a homoiconic language whose minimal grammar is intended to suit constrained LLM generation; no benchmark study.

**Quasar** — `language proposal` (with verification machinery) — [arXiv:2506.12202](https://arxiv.org/abs/2506.12202) — catalogued above. Notable methodologically: rather than inventing a new surface, it has models emit a Python subset and transpiles it, which sidesteps the cold-start problem entirely and still reports 42–56% execution-time and 52–53% approval-interaction reductions.

**Prompting Is Programming: A Query Language for Large Language Models (LMQL)** — `language proposal` (human-authored) — [arXiv:2212.06094](https://arxiv.org/abs/2212.06094)
Luca Beurer-Kellner, Marc Fischer, Martin Vechev (ETH Zurich SRI Lab; 12 Dec 2022; PLDI'23). Introduces Language Model Programming and its implementation LMQL, combining prompting, scripting, output constraints and control flow. Reports retained or improved accuracy on several downstream tasks while reducing computation or pay-per-use API cost by **26–85%**. Included for completeness and labelled carefully: **humans write LMQL**, so it is not an entry in the catalog above, but it is the most-cited academic precedent for "the prompt is a program" and its constraint mechanism is a direct ancestor of the decoding work below.

**DSPy: Compiling Declarative Language Model Calls into Self-Improving Pipelines** — `language proposal` (human-authored framework) — [arXiv:2310.03714](https://arxiv.org/abs/2310.03714)
Omar Khattab, Arnav Singhvi, Paridhi Maheshwari, Zhiyuan Zhang, Keshav Santhanam, Sri Vardhamanan, Saiful Haq, Ashutosh Sharma, Thomas T. Joshi, Hanna Moazam, Heather Miller, Matei Zaharia, Christopher Potts (5 Oct 2023). Represents LM pipelines as declarative, parameterised text-transformation graphs and compiles/optimises them against a metric. Within minutes of compilation, DSPy pipelines let GPT-3.5 and llama2-13b-chat beat standard few-shot prompting by **>25% and >65%** respectively, and beat expert-written demonstrations by **5–46% and 16–40%**. Excluded from the catalog because humans write DSPy programs in Python; included here because it is the canonical demonstration that *compiling* an LM program beats hand-writing prompts — the intellectual core of the orchestration camp.

**Executable Code Actions Elicit Better LLM Agents (CodeAct)** — `decoding/agent technique`, not a language — [arXiv:2402.01030](https://arxiv.org/abs/2402.01030)
Uses **existing Python** as a unified action space for agents. Evaluated across 17 LLMs, reporting up to **20% higher success rate** than JSON/text action formats, plus the CodeActInstruct dataset (7k instances). Its result is the single most important piece of counter-evidence in this report: the best-performing "agent language" in the literature is Python, unchanged.

### Decoding techniques

**PICARD: Parsing Incrementally for Constrained Auto-Regressive Decoding from Language Models** — `decoding technique` — [arXiv:2109.05093](https://arxiv.org/abs/2109.05093)
Torsten Scholak, Nathan Schucher, Dzmitry Bahdanau (10 Sep 2021; EMNLP 2021). The ancestor of this whole line: reject inadmissible tokens at each decoding step via incremental parsing, so the decoder cannot leave the formal language. Transformed fine-tuned T5 models "with passable performance" into state-of-the-art on the Spider and CoSQL text-to-SQL benchmarks. No single headline number is stated on the abstract page.

**Grammar-Constrained Decoding for Structured NLP Tasks without Finetuning** — `decoding technique` — [arXiv:2305.13971](https://arxiv.org/abs/2305.13971)
Saibo Geng, Martin Josifoski, Maxime Peyrard, Robert West (23 May 2023; EMNLP 2023 main). Generalises GCD — including *input-dependent* grammars — into a unified framework for information extraction, entity disambiguation and constituency parsing, with no finetuning. Reports that grammar-constrained LMs substantially outperform unconstrained ones and can beat task-specific finetuned models; the abstract page states no specific figure.

**Efficient Guided Generation for Large Language Models (Outlines)** — `decoding technique` — [arXiv:2307.09702](https://arxiv.org/abs/2307.09702)
Brandon T. Willard, Rémi Louf (19 Jul 2023). The paper behind the Outlines library: reformulate generation as transitions between finite-state-machine states and build an index over the model's vocabulary, giving model-agnostic guidance by regular expression or CFG. Claims little overhead per token and significant improvement over prior solutions; no numeric result is given in the abstract. This is the work most often conflated with "a language for LLMs" — it is the opposite move, constraining a general model into an existing format.

**SynCode: LLM Generation with Grammar Augmentation** — `decoding technique` — [arXiv:2403.01632](https://arxiv.org/abs/2403.01632)
Shubham Ugare, Tarun Suresh, Hangoo Kang, Sasa Misailovic, Gagandeep Singh (3 Mar 2024). An offline-constructed DFA mask store derived from the grammar's DFA, sound and complete with respect to context-free grammars. **Eliminates all syntax errors in JSON generation and removes 96.07% of syntax errors in generated Python and Go.** This is the number that most directly threatens the syntactic camp: if 96% of syntax errors in *existing* languages can be removed by decoding, syntax-driven arguments for a new language lose most of their headroom.

**Grammar-Aligned Decoding** — `decoding technique` — [arXiv:2405.21047](https://arxiv.org/abs/2405.21047)
Kanghee Park, Jiayu Wang, Taylor Berg-Kirkpatrick, Nadia Polikarpova, Loris D'Antoni (v1 31 May 2024, v3 12 Dec 2025; NeurIPS 2024). Identifies a real defect in naive GCD — masking distorts the model's distribution — and proposes ASAp (adaptive sampling with approximate expected futures), which guarantees grammatical output while provably matching the LLM's distribution conditioned on the constraint. Reports higher-likelihood outputs than existing GCD; no single headline figure on the abstract page.

**XGrammar: Flexible and Efficient Structured Generation Engine for Large Language Models** — `decoding technique` — [arXiv:2411.15100](https://arxiv.org/abs/2411.15100)
Yixin Dong, Charlie F. Ruan, Yaxing Cai, Ruihang Lai, Ziyi Xu, Yilong Zhao, Tianqi Chen (22 Nov 2024; MLSys '25). Separates context-independent from context-dependent tokens, transforms grammars to shrink the dependent set, uses a persistent stack for the rest, and overlaps grammar computation with GPU execution. **Up to 100× speedup over prior solutions and near-zero-overhead structured generation** when co-designed with the inference engine.

**XGrammar-2: Efficient Dynamic Structured Generation Engine for Agentic LLMs** — `decoding technique` — [arXiv:2601.04426](https://arxiv.org/abs/2601.04426)
Linzhang Li, Yixin Dong, Guanjie Wang, Ziyi Xu, Alexander Jiang, Tianqi Chen (v1 7 Jan 2026, v2 26 Mar 2026). Targets *agentic* workloads where the required structure changes mid-generation: tag-triggered structure switching (TagDispatch), substructure-level cache reuse across grammars (Cross-Grammar Cache), an Earley-based adaptive mask cache, JIT compilation and repetition-state compression. **Over 6× faster compilation than prior engines with near-zero end-to-end overhead.**

**Flexible and Efficient Grammar-Constrained Decoding** — `decoding technique` — [arXiv:2502.05111](https://arxiv.org/abs/2502.05111)
Kanghee Park, Timothy Zhou, Loris D'Antoni (v1 7 Feb 2025, v2 15 Jul 2025). Aligns subword tokenisers with context-free grammars and computes token masks while preserving state-of-the-art online efficiency, achieving **17.71× faster offline preprocessing** than prior approaches — the practical blocker for applying GCD to a large or frequently-changing grammar.

**What this section implies for the catalog.** The decoding literature has, between 2021 and 2026, made grammatical validity a solved and nearly free problem for *any* grammar, including Python's and TypeScript's. That removes syntax-error elimination as a reason to build a new language, and leaves the syntactic camp arguing only about token economy — where Sun et al. measure the available gain at roughly 10–15% and obtain it without a new language. The arguments that survive are semantic: effect capture, contract checkability, and machine-readable repair, which is where the verification camp lives.

---

## Entries considered and excluded

Each was checked against the brief's test — *is the design goal that models, not humans, are the primary authors, in a 2023–2026 language/DSL/serious proposal?*

- **Kadena Pact** — a blockchain smart-contract language with **zero AI or LLM authoring positioning**; latest release 4.13.1 (4 Nov 2024), 608 stars, BSD-3. Included here only to disambiguate it from Viktor Kikot's PACT, which is in the catalog. ([github.com/kadena-io/pact](https://github.com/kadena-io/pact))
- **Mojo** — a general-purpose Python-superset systems/GPU language; its own FAQ's only AI-authoring mention is that "Mojo AI skills can help your AI coding assistant translate Python," which is assistant support, not a design goal. ([mojolang.org/docs/faq](https://mojolang.org/docs/faq/))
- **DSPy** — self-described "framework for programming—not prompting—language models"; humans write the Python. 37.9k stars, v3.3.1 (21 Aug 2026). Discussed in the academic section instead. ([github.com/stanfordnlp/dspy](https://github.com/stanfordnlp/dspy))
- **LMQL** — "a programming language for LLMs" from ETH Zurich's SRI Lab, but humans author the queries. Discussed in the academic section. ([lmql.ai](https://lmql.ai/))
- **Guidance** — a library for steering and constrained generation, not a language models author; 21.7k stars, v0.3.2 (18 Mar 2026), last commit 21 May 2026. ([github.com/guidance-ai/guidance](https://github.com/guidance-ai/guidance))
- **Outlines** — a structured-output library implementing the guided-generation paper; a decoding technique, not a language. 15.8k stars, v1.3.3 (6 Aug 2026). ([github.com/dottxt-ai/outlines](https://github.com/dottxt-ai/outlines))
- **SGLang** — an LLM serving framework (35.8k stars, reported 400k+ GPUs) whose relevant contribution is ~3× faster JSON decoding via a compressed FSM: infrastructure, not a language. ([github.com/sgl-project/sglang](https://github.com/sgl-project/sglang))
- **SudoLang** — inverts the brief: **humans** write constraint programs that an LLM interprets. Claims "20%-30% fewer tokens than natural language"; 1.2k stars. ([github.com/paralleldrive/sudolang-llm-support](https://github.com/paralleldrive/sudolang-llm-support))
- **CodeAct** — uses existing Python as an agent action space; an agent technique with no new language. Covered in the academic section. ([arXiv:2402.01030](https://arxiv.org/abs/2402.01030))
- **CoRE / AIOS Compiler** — defines a syntax for structuring natural-language, pseudo-code and flow programs that an LLM *interprets and executes*; the LLM is the runtime, and humans author the instructions. Borderline, excluded on the authorship test. ([arXiv:2405.06907](https://arxiv.org/abs/2405.06907))
- **Voyager** — an LLM-powered Minecraft agent with "an ever-growing skill library of executable code"; the skills are ordinary JavaScript and no new language is proposed. ([arXiv:2305.16291](https://arxiv.org/abs/2305.16291))
- **Prompty (Microsoft)** — "an asset class and format for LLM prompts designed to enhance observability, understandability, and portability **for developers**," aiming to "accelerate the developer inner loop"; explicitly human-facing tooling. v0.2.3-beta, 24 Jul 2025. ([github.com/microsoft/prompty](https://github.com/microsoft/prompty))
- **ell** — "a language model programming library" and "lightweight, functional prompt engineering framework" whose examples are ordinary Python functions; human-facing. ([github.com/MadcowD/ell](https://github.com/MadcowD/ell))
- **PromptQL (Hasura)** — now positioned as "Multiplayer AI with shared context… We made AI a team sport"; a product for team AI threads with no claim that models author programs in a new language. ([hasura.io/promptql](https://hasura.io/promptql))
- **Wasp / MAGE** — Wasp is a human-facing full-stack framework "designed from day 1 to work nicely with other pieces of the stack, such as React and Node.js"; MAGE is an app generator *powered by* Wasp, not a language for models to author. ([wasp.sh](https://wasp.sh/blog/2024/01/23/wasp-launch-week-five))
- **LangGraph DSL, AutoGen DSLs, HELM DSLs, Sketchflow, CoLA, "AI-Lang", Yare, NL-Lang, LLM4Decompile DSLs** — I could not confirm, from any page fetched in this session, the existence of a 2023–2026 language or serious proposal under these names whose stated design goal is LLM authorship. For **LLM4Decompile** specifically, the primary paper is about decompiling binaries with LLMs, not about a new language ([arXiv:2403.05286](https://arxiv.org/abs/2403.05286)). For the remainder: `n.a.` — treat as unverified rather than nonexistent.
- **March** — a general-purpose language with no AI-authoring positioning on its homepage; excluded despite surfacing in searches near Markov. ([march-lang.org](https://march-lang.org/))

### Critiques of the entire premise (fetched this session)

These belong in the evidence base because the field's strongest counter-arguments are not in any paper.

- **Armin Ronacher, "A Language for Agents"** ([lucumr.pocoo.org, 9 Feb 2026](https://lucumr.pocoo.org/2026/2/9/a-language-for-agents/)) — argues for familiar syntax over novel syntax, and names two risks purpose-built languages inherit: under-representation in model weights (his example: Zig is "underrepresented in the weights") and tooling churn.
- **anup.io on Markov** ([anup.io](https://www.anup.io/til-markov-language/)) — the **cold-start problem**, stated most cleanly: "LLMs perform dramatically better on languages already present in their training data." Also notes that token savings are achievable without a new language (TOON at ~40% fewer tokens). This is the argument that every entry in the catalog above must answer and almost none does.
- **Zenn, "LLM-oriented language skepticism"** ([zenn.dev, 17 May 2026](https://zenn.dev/dead_master/articles/2026_05_17_llm_oriented_language_skepticism)) — LLM-oriented languages bake "current transitional weaknesses into the language design as permanent constraints," so "in a world where LLMs are sufficiently intelligent, 'languages for LLMs' structurally lose their value."
- **Hacker News on NanoLang** ([news.ycombinator.com](https://news.ycombinator.com/item?id=46684958)) — the author concedes "Nanolang is a total thought experiment," and the sharpest comment in the field is here: "llms don't need new languages, we do."
- **Chris Allen on MoonBit** ([bitemyapp.com, 15 Sep 2025](https://bitemyapp.com/blog/moonbit-developers-are-lying-to-you/)) — documents a specific, checkable benchmark misrepresentation by the most mature project in the catalogue, with corrected numbers.
- **Darren Shepherd on Zero** ([x.com, 2026](https://x.com/ibuildthecloud/status/2055848496163598726)) — "I'm officially banning Vercel Labs from creating anymore AI related projects," representative of the reception the highest-profile entry received from infrastructure practitioners.

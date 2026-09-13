---
tool: Perplexity
prompt: prompts-mo-parallel-tracks / brief for prompt 2
run: 2026-09-13
run_by: Claude (via Perplexity session 2c696217)
session_url: https://www.perplexity.ai/computer/tasks/2c696217-8105-4eea-98c1-c131b407077c
sha256: 4817e638e978c8648436af07b47cdd05b4ea9e086594d29a57c322900c2f9bd1
---
# Deep Research Prompt 2: Ecosystem, Standard Library, and Platform Depth for a New Programming Language

## Context and premise

A new general-purpose programming language is being designed for a world where AI agents write nearly all the code and human engineering teams operate and adopt the resulting software. The language aims to be used to build real production software — backend services, APIs, data pipelines, developer tools, infrastructure components — not just toy programs. Success requires that engineers, CTOs, and platform teams choose it because they can build reliable software quickly and confidently.

A recurring lesson from language history is that the standard library, the platform story, and the first-party ecosystem are more important than the language surface itself for determining whether real production adoption happens. Rust's early years, Node's package explosion, Go's batteries-included stdlib, Elixir's Phoenix, Laravel's ecosystem, Ruby on Rails, Deno vs Node, Bun's rapid rise, and Roc's platform model are all pieces of evidence in this space, some positive and some cautionary.

The people building this language need to know:

1. What does a modern language actually need in its standard library and platform on day one, so that agents can build real production services in it without pulling in a fragile third-party dependency graph?
2. What does the historical record show about which stdlib and ecosystem strategies succeeded and which failed?
3. How should first-party frameworks, kits, and platforms be structured in an era where agents are cheap and can generate boilerplate but supply-chain risk is high?
4. What are the specific pieces this language must ship, and in what order?

## Your task

Produce a comprehensive, evidence-rich, opinionated research report that a language designer could use to design the first two years of stdlib and ecosystem strategy for their language. Assume the reader is a highly technical language designer and engineering leader who knows the field but wants to be forced to confront evidence rather than intuition. Do not be shallow. Go deep on the parts that matter.

## What to cover

### Part 1: The historical record of stdlib and platform strategies

Cover the following language ecosystems in depth. For each, name what they shipped, when, why, what worked, what did not, and what modern engineers actually depend on.

- **Go.** The batteries-included stdlib (net/http, encoding/json, database/sql, crypto, io, sync, context). What was in v1, what came later, what was rejected. The `context` package as a case study in retrofitting a critical primitive. Modules and the pre-modules era. Third-party de facto standards (gorilla, gin, echo, sqlx, gorm, viper) — why they exist despite the batteries claim.
- **Rust.** The intentionally minimal std, the crates.io ecosystem, tokio and async runtime fragmentation, the crypto story (RustCrypto, ring, rustls), the HTTP stack (hyper, reqwest, axum, actix-web), the DB story (sqlx, diesel, seaorm), serde as the load-bearing foundation. What Rust deliberately kept out of std and why. The stability guarantee and its cost.
- **Elixir/Phoenix/OTP.** How Erlang's OTP set the stage, how Elixir extended it, how Phoenix became the de facto framework, LiveView as a bet, the Ecto story, Broadway, Oban, the "first-party opinion" model. What Elixir shipped in Elixir itself vs in Phoenix vs in third-party libraries.
- **Node.js.** The npm explosion, left-pad, the security incidents, how the ecosystem outgrew any single stdlib strategy, the "small modules" philosophy, deno and bun as reactions.
- **Deno.** The permissions model, the URL-based module system, the standard library (deno_std), the retreat from purity, the pivot to npm compatibility, the JSR registry. Why the ambitious clean-break strategy did not achieve dominance.
- **Bun.** The batteries-included runtime bet, the aggressive stdlib expansion (bun:sqlite, bun:test, bun:ffi, native S3/Redis), the strategic bet against small modules. What has actually shipped and what is real vs marketing.
- **Ruby on Rails / Laravel / Django.** How the framework relates to the language, how the "opinionated defaults" model worked, generators as a distribution mechanism, the "kit" model (Devise, Cancan, Pundit, Spatie packages). What made Rails and Laravel the dominant framework in their language and how much of the language's adoption they drove.
- **Roc.** The platform concept — the language has no I/O, platforms provide it. What has actually shipped years in, what basic-cli and basic-webserver actually cover, what platform authoring requires. The cautionary tale here.
- **Zig.** The evolving stdlib, the strategy of small language + curated stdlib, the async story and its reversal. What Zig has intentionally shipped and what it has intentionally left out.
- **MoonBit.** The AI-native positioning, what the stdlib actually contains, the toolchain-first approach, what production users have and have not been able to build.
- **Others as relevant.** Kotlin (JVM inheritance vs Kotlin-native stdlib), Swift (Foundation vs open-source Foundation), OCaml (the historical stdlib gap and Jane Street's fix), Clojure (the "the language ships opinions, libraries ship code" model).

For each language, cover both the successes and the mistakes. Where a decision looked wrong in hindsight, say so. Where a decision looked right, name what evidence supports that.

### Part 2: What do modern production services actually require?

Independent of any language, produce a grounded, evidence-based inventory of what a modern backend service ecosystem actually needs, categorized by whether it typically belongs in stdlib, in first-party kits/frameworks, or in third-party libraries.

- Networking: TCP, TLS, HTTP/1.1, HTTP/2, HTTP/3, WebSockets, gRPC, DNS.
- Data serialization: JSON, CBOR, MessagePack, Protobuf, Avro, YAML/TOML, CSV.
- Cryptography: hashing, symmetric/asymmetric crypto, JWT, TLS, password hashing, secure random, constant-time comparisons.
- Databases: SQL driver interfaces, connection pooling, transactions, migrations, prepared statements. Postgres, MySQL, SQLite drivers specifically. NoSQL/KV drivers. Redis-protocol clients.
- Concurrency: task/process primitives, structured concurrency, cancellation, timeouts, backpressure, work stealing.
- Observability: structured logging, metrics (Prometheus/OpenMetrics), tracing (OpenTelemetry), profiling.
- Text and encoding: UTF-8, Unicode normalization, regex, string manipulation, i18n basics.
- Time: monotonic clocks, wall clocks, timezones, durations, deadlines.
- Filesystem: reading, writing, streaming, watching, atomic operations, temp files, path manipulation.
- Compression: gzip, zstd, brotli.
- Process management: subprocess spawning, signals, environment.
- Testing: unit tests, property tests, fuzz tests, snapshot tests, mocking, fixtures.
- Configuration: env vars, config files, secrets, feature flags.
- Web framework primitives: routing, middleware, request/response, sessions, CSRF, auth.
- Background jobs, scheduling, queues.
- Email, SMS, push notification abstractions.
- AI/LLM integration: HTTP clients for major providers, streaming, tool use, structured outputs.
- Deployment: container-friendly binaries, cross-compilation, static linking.

For each: is this typically in stdlib, in a first-party kit, or third-party? What is the failure mode when it is in the wrong tier? Reference specific incidents (log4shell, event-stream, colors.js, xz, ua-parser-js, PyPI/npm supply-chain events).

### Part 3: The "shape" of a successful stdlib

Beyond specific pieces, what characterizes successful stdlibs versus unsuccessful ones? Cover:

- Stability guarantees: what has "no breaking changes ever" cost Go and Java, and what has flexibility bought Rust and Python?
- Size and coherence: is there a right size, or a right shape? When does a stdlib become too big to maintain and too small to be useful?
- The "one obvious way" principle vs "many good libraries" principle. Where has each actually paid off?
- Testing infrastructure in stdlib: what does it mean when the test runner is built-in (Go, Rust, Zig, Deno) vs external (Python, Node, Ruby)?
- HTTP servers in stdlib: what has Go's net/http bought them, and what has Rust's decision to leave it out cost or saved?
- Cryptography in stdlib: the case for and against. Reference the "don't roll your own crypto" argument versus the "audit is only meaningful if it is first-party" argument.
- Database drivers: why does almost no language ship them in stdlib, and what does that cost the ecosystem?

### Part 4: The "kits" model — first-party generated code

Some ecosystems have adopted the model of shipping first-party features as generated source code that lives in the user's repo, rather than as dependencies. Examples:

- Phoenix's generators (auth, contexts, LiveView components).
- Laravel's generators, Nova, Jetstream, Breeze.
- shadcn/ui and its imitators (the copy-paste component library model).
- Rails generators, though weaker than Phoenix's.
- Create-react-app and its descendants as a degenerate case.

Research this model deeply. What has actually worked, what has failed, and what does the evidence say about maintainability of generated code that lives in the user's repo? What is the update story? What are the failure modes? Is this model actually a supply-chain defense, or a supply-chain problem in disguise?

### Part 5: Supply-chain risk and the modern registry

Given the 2024–2026 record of supply-chain incidents (npm event-stream, PyPI colors, xz backdoor, ua-parser-js, node-ipc, various npm typosquats and dependency confusion attacks, the crypto library incidents):

- What are the defenses that have actually been deployed by registries and languages? Cover npm (provenance, 2FA requirements), PyPI (attestations, trusted publishing), crates.io, Go's checksum database and sum.golang.org, Deno's URL model, and any others.
- What is the evidence that any of these have actually reduced incidents? Not claims, evidence.
- What are the strongest proposals in the literature and in practice? Reference Sigstore, in-toto, SLSA, capability-based module systems, reproducible builds, transparency logs. What is the state of the art and what is the state of the actual deployment?
- Specifically: what does the evidence say about age gates, transparency logs, WebAuthn-required publishing, capability manifests, and reputation signals as defenses? Which have been tried, and what happened?

### Part 6: Adoption dynamics — how ecosystems actually grow

- What predicts whether a language's ecosystem crosses from "toy" to "production-viable"? What are the leading indicators? Reference specific studies of language adoption if they exist.
- How did Rust, Elixir, Go, TypeScript, Kotlin, and Swift actually grow their ecosystems in the first 3, 5, and 10 years? Look at real numbers — package counts, download counts, employer counts, GitHub metrics.
- What role did first-party frameworks (Phoenix, Laravel, Rails, Django, Next.js) play in each?
- What role did a "killer app" or "killer use case" play? What role did corporate backing play (Mozilla for Rust, Google for Go, Apple for Swift, JetBrains for Kotlin, Microsoft for TypeScript)?
- Where does the "batteries-included from a benevolent authority" model succeed, and where does the "let the community sort it out" model succeed?

### Part 7: The specific stack for a modern services language shipping today

Independent of the specific new language being designed, if you were building a language for backend services today and wanted it to be seriously usable in production without a fragile third-party dependency graph, what would you ship on day one?

- Name the specific packages, modules, and platform pieces.
- Name what you would deliberately not ship, and why.
- Name what you would ship as first-party but not in stdlib (kits, official frameworks).
- Name what you would leave to the community, and how you would seed it.
- Sequence the first 24 months of ecosystem investment.

### Part 8: Synthesis — "if I ran this project"

Given everything above, produce a concrete, opinionated recommendation:

- What is the right stdlib and platform strategy for a new language whose users are AI agents and whose customers are engineering teams building production services?
- What is the right first-party framework strategy?
- What is the right supply-chain and registry strategy?
- What is the sequence: what must ship in the first 6 months, first 12 months, first 24 months?
- What are the two or three specific bets that most differentiate a successful ecosystem strategy from a failed one?
- What are the fatal mistakes to avoid?

## Requirements

- **Primary sources.** Cite official docs, release notes, RFCs, post-mortems, published papers, and named developers' technical writing. Where a claim rests on a blog post, name the author and their basis.
- **Quantitative where possible.** Real numbers on package counts, download counts, adoption timelines, incident counts, patch times.
- **Historical honesty.** Where a decision was later reversed or regretted, say so. Where a decision was defended but wrong, say so.
- **Long-form and comprehensive.** This is a research report, not a summary. Depth on every part.
- **Cite everything inline.** Every non-obvious claim needs a source.
- **Name the frontier.** Which people, teams, and projects are doing the most credible work on modern language ecosystems right now?
- **Be specific.** "A good stdlib" is not an answer. Named packages, named modules, named APIs, named tradeoffs.
- **Do not editorialize until Part 8.** Report evidence in Parts 1–7. Recommend in Part 8.

Deliver as a single long-form report with clear section headers matching Parts 1–8.

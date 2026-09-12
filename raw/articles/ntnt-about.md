---
source_url: https://ntnt-lang.org/about
ingested: 2026-09-12
sha256: d69d4ccd774d6a0104e06116a085b811369c1a099d458ffbf0f15a1c9208e150
---
# About NTNT — The Agent-Native Programming Language

About NTNT — The Agent-Native Programming Language

# A language for the agent era.

NTNT (pronounced “intent”) is an agent-first programming language built for a world where AI agents write most of the code — and humans define the intent.

## Origin Story

NTNT started as a question: if an AI agent is going to write most of your code, what does the language need to do differently?

Traditional languages are designed for humans writing code by hand. Syntax is crafted for readability. Error messages assume the author made a typo. Documentation is a nice-to-have. None of that is quite right when your primary developer is an LLM.

NTNT was built to answer: what if the language was designed from the start for human-AI collaboration? What if requirements weren’t separate from the code — they were verifiable tests woven into the development loop? What if contracts weren’t just good practice — they were how agents understood what to build?

## Created By

Josh Cramer has been writing, architecting, and managing the production of code for over 25 years. He watched the industry go from raw PHP on shared hosting to TDD, containers, CI/CD, and API-first development. Every one of those shifts was built by humans to solve human problems.

Then AI agents started writing code, and he noticed something: every tool in the modern stack was created by humans to solve human problems. Is that paradigm actually optimal when machines are the ones writing the code? Or is there a different set of tools and patterns that would work better for the way agents build software?

NTNT started with those questions. Once the work began, new ones followed. What if the language could have any feature he wanted built in? What if security, auth, databases, and job queues were part of the language instead of third-party dependencies? What if the code for a typical app could be 2-3x less verbose by changing how the language works?

The effort started as experimental and exploratory, and has since grown into a language that runs numerous production apps and websites, including this one and Josh’s own site.

## Technical Details

- Runtime: Rust (Axum + Tokio for async HTTP, tree-walking interpreter)
- Type system: Gradual, two independent axes: `NTNT_LINT_MODE` (static) and `NTNT_TYPE_MODE` (runtime). Start untyped, add types incrementally.
- Standard library: 480 built-in functions across 27 modules, including HTTP, auth (OAuth/OIDC/JWT), databases, crypto, concurrency, background jobs, CSV, markdown, and more
- Deployment: Single binary, Docker-ready, native hot-reload in development
- Database support: PostgreSQL (connection pooling via deadpool), SQLite, Redis (KV store)
- Concurrency: Spawn/await tasks, typed channels (Tx/Rx), select, schedule, parallel, race
- Background jobs: Language-native job DSL with priority queues, cron, unique jobs, dead letter handling. Memory, PostgreSQL, and Redis backends.
- Syntax inspiration: Ruby (interpolation), Python (readability), Rust (contracts, channels)

## Project Status

NTNT is actively developed. Here’s where things stand:

Core Language ✓ Complete

HTTP Server ✓ Production-ready

Type System ✓ Gradual (two-axis)

Intent-Driven Dev ✓ Fully working

Standard Library ✓ 480 functions / 27 modules

Auth (OAuth/JWT) ✓ Built-in

Concurrency ✓ Channels, select, spawn

Background Jobs ✓ Language-native DSL

LSP / IDE Support → Planned

WASM Compilation · Future

## Design Philosophy

- Simple & Intuitive — Readable by humans reviewing it, predictable for agents writing it.
- Strong & Robust — Catch mistakes early, fail clearly, never silently corrupt.
- Consistent — One pattern for everything. `len()` works on strings, arrays, and maps. `query()` works on PostgreSQL, SQLite, and Redis.
- Secure by Default — A comprehensive standard library reduces the need for third-party dependencies, and with fewer dependencies comes less exposure to the supply chain attacks that have become routine in npm, PyPI, and crates.io. Auto-escaping, SSRF protection, and security headers ship with the language.
- Progressive Types — Start untyped, add annotations where they help, enable full type checking when you want it.
- Agent-Native Tooling — `ntnt inspect` returns structured JSON of every function, route, and contract. `ntnt validate` returns machine-readable errors. An agent can understand an entire codebase in one call.
- Verification Built In — Intent files, `@implements` annotations, and `ntnt intent check` are part of the language itself, not a separate test framework bolted on after the fact.
- Batteries Included — HTTP, auth, databases, crypto, jobs, concurrency, CSV, markdown. All in the standard library, all shipping with the binary. No package manager by design.
- Documentation as a Constraint — The compiler refuses to build until every public function is documented. Documentation stays accurate because the build depends on it.
- Less Code, More Done — Routes, database queries, auth flows, and job definitions that take dozens of lines in other languages take a few in ntnt.

## Get Involved

NTNT is open source under the MIT license. The best way to contribute is to use it, break it, and file issues.

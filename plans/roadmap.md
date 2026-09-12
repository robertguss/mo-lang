---
title: "Roadmap: the path after alignment"
created: 2026-09-12
updated: 2026-09-12
type: plan
tags: [roadmap]
sources: [raw/notion/open-questions-2026-09-12.md]
status: proposed
---

# Roadmap: the path after alignment

Once you've gone through [[q01-comments|Q1]]–[[q16-escape-hatch|Q16]], here is the path I'd propose. Each step produces something you can read or run.
1. **Write the Mo design document, v0.** Not a formal spec: a 15-page narrative that states the philosophy, the laws, the semantics, and the syntax, with the refund example as the running thread. This is the artifact we compare against other languages and show to people. I'd draft it from the journal; you'd edit by taste, the way you did with the syntax.
2. **The comparison pass.** Take the v0 doc and hold it against Elixir, Go, Rust, Gleam, Roc, Koka, Austral, Zig, and Elm, one page each: what Mo does differently, what it gives up, what it should steal that we missed. This is the research you asked for at the start, done against a concrete design instead of in the abstract.
3. **Lock v0.** After the comparison, convert "directions we like" into decisions, in one sitting.
4. **Write the grammar.** A formal grammar for the syntax, small enough to print on two pages, and a corpus of 30–50 tiny Mo programs that exercise every construct. The corpus doubles as the first training material for agents.
5. **Build the interpreter.** In Zig. Lexer, parser, type checker, capability checker, contract runtime, tests runner. Milestone: the refund module runs and its tests pass, `rejects` included. This is where an agent starts writing Mo for real, and where the design meets reality.
6. **Build the first program** ([[q14-first-real-program|Q14]]) in Mo, using agents, with you reading at the spec altitude only. This is the test of the founding premise.
7. **Then** the C backend, the simulator, the SMT pass, and the platform split, in whatever order the first program demands.
Steps 1–4 are days. Step 5 is weeks. Step 6 is where we find out if the idea is right.

## Related
- [[program-menu]]
- [[q14-first-real-program]]
- [[q13-implementation-language]]
- [[session-02]]
- [[q15-the-name]]
- [[language-landscape]]
- [[comparison-pass]]

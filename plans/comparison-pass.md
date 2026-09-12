---
title: "Comparison pass: brief for the worker session"
created: 2026-09-12
updated: 2026-09-12
type: plan
tags: [roadmap, research]
sources: [raw/articles/agentlanguages-dev-catalogue-2026-09-12.md]
status: in-progress
---

# Comparison pass: brief for the worker session

Thirteen pages in `research/comparisons/`, one per shortlist entry in [[language-landscape]]. Written by a worker session (Opus) with fresh web research; reviewed by Claude (Fable) and Robert. This page is the full brief. Robert's rule: nothing here is decided until he says so — these pages *inform* the v0 design doc, they don't change directions on their own.

## Orientation (do first, every session)

1. Read `HANDOFF.md`, `SCHEMA.md`, `index.md`, the tail of `log.md`.
2. Read `research/concepts/language-landscape.md` (the shortlist and why each entry is there) and `deep-dives/steal-list.md` (what session 1 already took).
3. Skim `directions/` titles (30) and `questions/` titles (17) so you know which Mo decision each language touches. `index.md` has one line per page.

## Tools

- **Web research:** `source ~/.zshenv && python3 tools/exa.py search "..." -n 10` / `contents URL` / `answer "..."` / `research "task"`. Also plain WebFetch/WebSearch. Prefer primary sources: language site, spec, repo, papers.
- **Papers:** arXiv API (`https://export.arxiv.org/api/query?search_query=...`) — wait ≥3s between calls, it rate-limits hard. Semantic Scholar `https://api.semanticscholar.org/graph/v1/paper/search?query=...`.
- **Citations:** `python3 .claude/skills/grounded-citations/scripts/sources.py --ledger research/comparisons/.ledger.json add URL --title "..."` returns `[n]`; cite inline as `[n]`; finish with `render --cited-in PAGE >> PAGE` and `verify PAGE`. One shared ledger for the whole pass; never renumber.
- **Raw sources:** save any page or paper you lean on to `raw/articles/<slug>.md` or `raw/papers/<slug>.md` with frontmatter `source_url`, `ingested: YYYY-MM-DD`, `sha256` of the body. `raw/` is immutable once written.
- **Lint:** `python3 tools/lint.py` must be clean before every commit.
- **Commit** after each finished page: `git add -A && git commit -m "Comparison: <Language>" && git push`. Commit trailers per the session's system reminder.

## Page template (`research/comparisons/<slug>.md`)

```markdown
---
title: "Mo vs <Language>"
created: 2026-09-12
updated: 2026-09-12
type: comparison
tags: [research, <one or two from the taxonomy>]
sources: [raw/articles/<slug>.md, ...]
confidence: medium
---

# Mo vs <Language>

**One line:** what this language is and why it's on the list.

## What it is (status as of Sep 2026)
Release stage, activity, who's behind it, domain. 3–6 sentences, cited.

## The ideas, one by one
For each distinctive idea (3–7 of them):
- **Idea** — what it does, in two sentences with a ≤8-line code snippet if syntax matters.
  - *Mo today:* which direction / question / syntax pick already covers this (link it: `[[d15-effects-via-capabilities|direction 15]]`).
  - *Verdict:* **steal** / **already have** / **reject** / **open** — and one sentence why.

## What it gives up
The costs the language accepts, and whether Mo accepts the same ones.

## Evidence
Anything measured: performance numbers, adoption, study results, LLM benchmarks. Cited. "No evidence found" is a valid line.

## What Mo should take from this
Bullet list, each item a concrete proposal or a question for Robert. Mark anything that would **contradict an existing direction** with ⚠️ and name the direction — do not resolve it, surface it.

## Related
- [[language-landscape]]
- links to the directions/questions/picks this page touched (≥2)

## Sources
(rendered by sources.py)
```

Keep pages under ~180 lines. Snippets under 10 lines. Three-column tables max. Phone-readable.

## The thirteen, with what to look for

1. **elixir** — Elixir v1.20's gradual set-theoretic types (inference-first, no annotations, "verified bugs"); OTP supervision shapes vs Mo's declared `supervisor` (Q7); what Elixir 1.20+ shows about typed BEAM ergonomics. Touches d7, d14, d18, q7.
2. **go** — what Go's "simplicity by law" is *precisely* (gofmt, no generics for a decade, stdlib policy, module proxy + checksum DB for Q17); `if err != nil` vs Mo's `try`; goroutines vs Mo processes. Touches d12, d23, q11, q17.
3. **rust** — traits, enums, exhaustiveness, `Result`/`Option`, the borrow checker's cost to humans and agents (find studies), compile-time causes; what Mo keeps (d22) and drops. Touches d22, d23, q5, p15.
4. **roc** — platforms in detail (how a platform is written, the app/platform boundary, the effect interpreter), Perceus-style memory, the Zig rewrite numbers, Roc's abilities vs Mo traits. Touches q11, d24, d25, q13.
5. **koka** — effect types + handlers vs Mo's capability parameters (d15); Perceus with reuse (the memory model Mo wants); compile-to-C. Touches d15, d16, d10, d24.
6. **austral** — linear types, capability-based security, the "no magic" spec; how capabilities are obtained at the root and threaded; what linearity would buy Mo for resources/deadlines. Touches d15, p13, q16, q17.
7. **hylo** — mutable value semantics precisely (projections, `inout`, `set`, `sink`), how it avoids aliasing, generics; new compiler status. Touches d13, d10, p3.
8. **unison** — content-addressed definitions, codebase-as-database, exact dependencies by hash, hash-cached tests, why text files were dropped and what that cost adoption. Touches q10, d29, d23, q17.
9. **moonbit** — the shipping "AI-native toolchain": what MoonBit Pilot does, the ICSE 2024 semantics-aware sampling paper, multi-backend, what its language actually looks like, adoption. The closest competitor; be specific. Touches d1, q9, q10, q13.
10. **bosque** — regularized programming (no loops, no mutable state, no reference equality), Mark Marron's papers, why the project stalled (find the history), what Bosque 2.0 / recent commits look like. Touches d4, d10, q12, p11.
11. **spark-ada-and-dafny** — contracts as language with prover + runtime semantics (SPARK); Dafny's 82% LLM proof rate (vericoding benchmark 2509.22908), Dafny-as-IL (2501.06283), Marmaragan (2502.07728); what contract *shapes* LLMs discharge well. Touches d3, d22, q8, p8.
12. **agent-native-cluster** — one page for Intent, Vera, Thermite, Vow, Aver, AILANG, Hale, Tacit, Zero, Codong, Axis, plus Neam and NTNT (not in the catalogue; verify they exist). For each: two lines + what overlaps Mo. Then: *what did 42 fresh attempts converge on?* Touches d1, d3, q9, q10, q12.
13. **verse** — functional logic + transactional semantics (every function inside a transaction that can roll back), structured concurrency, Simon Peyton Jones's papers; could transactions replace or complement crash-and-restart (d18, d21)? Wildcard; be skeptical. Touches d18, d21, d14.

## Order

Do them in the order above (1 → 13). One page at a time, commit after each. If a page needs more than ~90 minutes, write what you have, mark `confidence: low`, and move on.

## When done

- Append to `log.md`: one entry per page (`## [date] ingest | Comparison: <Language>`).
- Add each page to `index.md` under Research.
- Write `research/concepts/comparison-synthesis-draft.md`: the ⚠️ contradictions across all 13, the top ten steals, and open questions for Robert — a *draft* for Fable to finish, not a decision.
- Update `HANDOFF.md` "Where we stopped".

## Progress

Finished pages, in order (worker session):
1. [[elixir|Elixir]]
2. [[go|Go]]
3. [[rust|Rust]]
4. [[roc|Roc]]
5. [[koka|Koka]]
6. [[austral|Austral]]
7. [[hylo|Hylo]]
8. [[unison|Unison]]
9. [[moonbit|MoonBit]]
10. [[bosque|Bosque]]
11. [[spark-ada-and-dafny|SPARK Ada + Dafny]]
12. [[agent-native-cluster|Agent-native cluster]]
13. [[verse|Verse]]

## Related
- [[language-landscape]]
- [[roadmap]]
- [[steal-list]]

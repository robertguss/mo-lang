---
title: "Direction 34: Packages are recipes; the spec is shared, the bodies are yours"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [security, stdlib, agents, philosophy]
sources: [research/concepts/supply-chain-defenses.md, research/comparisons/aube.md]
number: 34
status: liked
origin: "Robert (session 3), to be proven"
confidence: low
---

# Direction 34: Packages are recipes; the spec is shared, the bodies are yours

Robert's idea (session 3), in his words: packages "were originally built by humans for other humans to make it faster and easier for humans to build software. But now we have AI ... there is less need for 3rd party packages and engineers should be building more of their own packages and libraries ... because the maintenance burden is negligible because agents will maintain it." Packages become "recipes or blueprints ... a set of instructions and/or code examples, but the AI agent implements it themselves and custom tailors it to the repo." It is "more about sharing intent and ideas, rather than source code." He flagged it as a crazy idea that still has to be built and proven, and the kind of first-principles rethink Mo exists for.

## The shape (Claude's rendering, Robert: "I think so")

- **The standard library and platform are the box of bricks.** Every primitive people need, first-party, audited once. They are the *only* shared code. The ceiling from [[q11-platform-and-stdlib|Q11]] rises to cover everything where "subtly wrong" is a security or data-loss event: crypto, TLS, compression, Unicode, time zones, regex, HTTP, JSON, and database drivers (Robert: a Postgres driver is a brick).
- **A package is the booklet.** It is the spec altitude of [[two-altitudes]] and nothing below it: `intent`, a `needs` ceiling, `pub` signatures with contracts, `test` and `rejects` blocks, and optionally example bodies. It must parse as Mo, not prose.
- **The agent builds it from your bricks**, in your repo, tailored to the project. The compiler checks the result against the booklet: shape, tests, and that its capabilities stay under `needs`.
- **It is then your code.** No dependency exists. Every program is zero-dependency by construction.

```ruby
recipe RateLimiter
  intent "Token bucket per client; refills from the clock"
  needs Clock
  pub fn allow?(l: Limiter, id: ClientId, now: Time) : (Limiter, Bool)
  test "refills at the declared rate" ... end
  rejects "a burst beyond capacity" ... end
end
```

## Why it holds up

- Every incident in the 2024–26 record was code execution ([[supply-chain-defenses]]). A recipe executes nothing.
- No transitive graph: no version conflicts, no worm propagation.
- A recipe update is a spec diff, which [[d20-human-pulled-in-when-shape-changes|direction 20]] already routes to a human.
- The attack moves to prompt injection of the agent. Mo survives it because generated code cannot exceed `needs` ([[d15-effects-via-capabilities|direction 15]], [[d31-effects-never-hide-in-a-value|direction 31]]) and the manifest is visible at install.

## What stays

Source-code packages remain allowed as the exception, under the [[q17-package-management-and-supply-chain|Q17]] rules, showing `needs:` at install. If recipes prove out, they may go away.

## First tested by

Three recipes from the [[program-menu]] (rate limiter, JWT, CSV) implemented by agents into the example corpus: token cost, defect rate against the recipe's own tests, and how often generated code tried to exceed `needs`. See [[d35-mo-is-an-ecosystem]] for the first-party side.

## Related
- [[d35-mo-is-an-ecosystem]]
- [[d30-supply-chain-security]]
- [[q17-package-management-and-supply-chain]]
- [[q11-platform-and-stdlib]]
- [[two-altitudes]]

# Audit deliverable: a stopping rule for capabilities and recipes

**Date:** 17 September 2026
**Author:** the auditor (a Perplexity session, independent of Fable)
**Charter:** as accepted by Robert 17 Sep 2026; the auditor does not design, execute, or accept work, only reads evidence and files readings for the decision log.
**Status:** draft for Robert. Fable's parallel draft, if written, is to be read alongside this one and not before it.
**Purpose:** state, before program 7 runs, what evidence would confirm and what evidence would refute the project's **secondary** thesis claim — that capabilities and recipes deliver zero third-party runtime dependencies without paying a measurable reliability, speed, or velocity penalty against the mainstream package-based baselines.

---

## Robert's ratifications, 17 Sep 2026

Ratified in-session on 17 Sep 2026, before program 7 exists. Any change to the below is a decision-log row with a stated reason.

- **P1:** hard row, 0 third-party runtime packages. Any dep > 0 fails P1.
- **P2a:** ≥ 2 of 3 drift bugs caught by `mo check --recipe`. As written.
- **P2b:** no recipe in program 7 needs a just-trust-me clause. As written.
- **P2c:** ≤ 1 of 5 seeded regeneration-drift cases missed. As written.
- **P3:** Mo ≤ 1 escape AND Elixir ≥ 3 escapes. Amendments accepted:
  - **Clean-differential footnote:** if both languages have 0 escapes, P3 still clears but the differential claim is downgraded to "capabilities confine, and so does Elixir with review."
  - **Hard fail:** if Mo has > 1 escape regardless of Elixir's count, P3 fails. The confinement claim is Mo's to earn on absolute grounds, not on differential.
- **P4:** Mo maintainer time on a change-6-style modification ≤ 1.5× Elixir's. As written.
- **Retirement mapping** (severity-graded, committed in advance):

  | Outcome | Retirement |
  |---|---|
  | P1 fails (any dep > 0) | **T-A or T-B**, Robert picks based on *why*: if bricks were adequate but recipes weren't, **T-B**; if bricks were also inadequate, **T-A** |
  | P3 fails (Mo escapes > 1) | **T-A** — the confinement claim was the strongest one; its failure retires the whole claim |
  | P2 fails, P1 and P3 clear | **T-C** — recipe experience is bad, zero-dep ships, fix follows |
  | P4 fails, others clear | **T-C** — velocity issue, fix follows |
  | P2 and P4 both fail | **T-B** — bricks yes, recipes no |
  | Everything clears | claim vindicated |

- **Workflow requirement:** Fable drafts a parallel independent reading of program 7's capabilities/recipes evidence against this rule and files it alongside the auditor's before Robert reads either. Disagreements become decision-log rows.
- **Prerequisite (auditor's separate finding):** the bricks page must ship before program 7's first commit. Chapter 6's shelf boundary is unspecified without it, and this rule cannot bind well against a moving target. This is item #1 on the ratified M-3 roadmap ordering.

---

## 0. Why this pre-registration matters

The pivot of 14 Sep 2026 rewrote the thesis as:

> software written by agents can be reliable and need no third-party code, and a runtime and process model built for that, with capabilities and recipes on top and the language as their surface, delivers it.

That is a **conjunction**: reliability AND zero third-party code. The runtime audit binds the reliability half. This document binds the "zero third-party code" half — the capabilities and recipes layer — as it operates on a real program.

Chapter 6 is unusually strong on the design (three shelves: bricks, kits, recipes; six-layer registry with age gates, transparency log, capability manifests). But the design has never been stressed by a real program. Program 4 was the closest — it found "nothing held an implementation to its recipe, so its copies of the recipe's tests could drift" — and led to `mo check --recipe` gaining `never` support. Nothing since has tested the shelf structure at production shape.

Program 7 is the pilot for this claim too. Same program, different rule.

---

## 1. What "the capabilities/recipes claim" actually is, made specific

The claim, restated from chapter 1 and chapter 6:

> Mo programs of production shape can be written using only bricks (first-party stdlib and platform) and recipes (community intent, agent-generated bodies checked against the recipe), with zero third-party runtime dependencies, at no measurable reliability, speed, or velocity penalty against equivalent Elixir programs that use the standard hex ecosystem for the same functionality.

Four sub-claims fold inside this:

- **P1: Zero third-party dependencies is achievable.** Program 7 ships with 0 third-party runtime packages, using only bricks and recipe-generated code for every function that a normal Elixir program would use `hex` for (probably: crypto, JSON handling, HTTP server, database driver, background job queue, rate limiting, TLS, logging, metrics).
- **P2: Recipes actually work as advertised.** `mo check --recipe` catches drift when the maintainer's implementation strays from the recipe's contract; the recipe surface is expressive enough to state real production contracts.
- **P3: Capability confinement is real.** A hidden capability-abuse suite (10 shapes: log-writing HTTP client that shouldn't, JSON parser that opens files, rate limiter that talks to the network, etc.) finds ≤ 1 escape in Mo where a capability is used beyond its declared scope; the Elixir counterpart finds ≥ 3. **Amendment (ratified 17 Sep 2026):** if both languages have 0 escapes, P3 still clears with a footnote ("capabilities confine, and so does Elixir with review"); if Mo has > 1 escape regardless of Elixir's count, P3 fails.
- **P4: No velocity penalty on maintenance.** When a change 6-style modification requires updating a piece of functionality that in Elixir would be `hex update`, the Mo maintainer's time to make the equivalent modification (regenerating a recipe body, updating a brick's usage) is within 1.5× of the Elixir maintainer's `hex update` + audit time.

The order matters: P1 is the strongest claim (present or absent, binary); P2 is the mechanism; P3 is what makes zero-dependency worth having; P4 is the cost check.

---

## 2. What the record shows today, 17 Sep 2026

- **P1: Not tested at program 7 scale.** The current programs (log analyzer, key-value store, notes service, agent harness, ledger, job queue) are small enough that "zero dependencies" is roughly free — the stdlib covers their needs. Program 7 is chosen to exercise the shelf structure specifically because it needs functionality that would in Elixir be handled by `hex` packages. **Status: pre-registration for program 7.**
- **P2: Weakly tested.** Program 4 exposed the drift problem and drove `mo check --recipe`'s `never` support. No large-recipe program has been written that stresses the recipe surface at production shape. **Status: mechanism exists, not stress-tested.**
- **P3: Not tested.** No capability-abuse suite has been run against any Mo program. Chapter 6 makes strong claims about `mo add`'s capability manifest and the age-gate mechanics, but there is no adversarial evidence yet. **Status: not tested.**
- **P4: Not tested.** No maintenance round has required a hex-style dependency update. Change 6's forthcoming spec might; if it does, it can produce the first data point. **Status: not tested.**

The auditor's summary: the capabilities/recipes layer has **less evidence than the runtime layer** and **less evidence than the language layer** — it has the strongest design and the weakest experimental record. This is the layer where a pre-registration matters most because there is no history to argue from.

---

## 3. The proposed stopping rule

The rule below is stated as **the pre-registration for program 7's capability/recipe evidence**. It should be filed alongside the runtime pre-registration, sealed before program 7's first commit.

### Tier 1 — the achievement (P1)

**Program 7 shall ship with exactly zero third-party runtime dependencies.**

- The lockfile shows only bricks (stdlib, platform) and recipes whose bodies are in Mo's own repo, generated by the maintainer's agent from the recipe's intent.
- Any dependency added via `mo add` from an outside registry is counted; the count must be 0.
- Bricks and kits do not count (they are first-party).
- Reference bodies copied from first-party recipes do not count (they are audited platform code by chapter 6's rules).

**If the count is > 0:** P1 fails. The auditor asks *why* — which functionality could not be covered by bricks or recipes. That answer is the finding.

### Tier 2 — recipe mechanism (P2)

**Program 7 shall use at least 3 non-trivial recipes** (not counting recipes whose whole implementation is < 50 lines), and:

- **P2a:** `mo check --recipe` catches at least 2 of 3 pre-registered drift bugs (the auditor writes 3 wrong-implementation seeds; Fable does not see them) inserted into recipe implementations.
- **P2b:** The recipe surface is expressive enough that no recipe requires a "just-trust-me" clause (an `intent` that cannot be checked against a body). If any recipe in program 7 needs one, P2b fails and the finding is a recipe-surface gap.
- **P2c:** Recipe body regeneration on a spec change (P4 measures) does not introduce drift that `mo check --recipe` misses in > 1 of 5 seeded cases.

**If P2a or P2c fails:** the recipe mechanism is not tight enough for production use; the claim is downgraded from "recipes replace packages" to "recipes are prototype-level."
**If P2b fails:** the recipe surface has a design gap; chapter 6 gains a follow-up task.

### Tier 3 — capability confinement (P3)

**Under a hidden capability-abuse suite of 10 shapes:**

- Mo finds ≤ 1 shape where a capability is used beyond its declared scope. (An escape is any capability call, or any subsequent call chain, that reaches an effect outside the capability's manifest.)
- The Elixir counterpart, using dependencies that could plausibly be malicious (a made-up JSON parser that logs to a file, a rate limiter that phones home), finds ≥ 3 escapes.

If Mo's escape count is > 1: **P3 fails.** The confinement claim is not backed. Chapter 6's capability-parameter model does not hold up under adversarial pressure.
If Elixir's counterpart escape count is < 3: the differential is smaller than the design assumes; P3 clears but with a footnote (the null hypothesis "Elixir with strict review is fine" gains weight).

### Tier 4 — velocity on maintenance (P4)

**On at least one change-6-style maintenance modification during program 7's build,** the Mo maintainer's time to complete the equivalent of a `hex update + audit + integrate` cycle shall be ≤ 1.5× the Elixir maintainer's time on the same modification.

If Mo maintainer time is 1.5×–2.5×: **P4 amber.** The zero-dependency win is expensive; project must decide whether the win is worth the ongoing cost.
If Mo maintainer time is > 2.5×: **P4 red.** The recipe/brick model is too slow to maintain; the claim retires.

---

## 4. Definitions the rule depends on

- **"Third-party runtime dependency."** Any package obtained via `mo add` from an outside registry that ships bytes the runtime uses. Excludes: bricks, first-party recipes with reference bodies, in-repo path dependencies, and dev-time-only tooling.
- **"Non-trivial recipe."** A recipe with ≥ 3 exported functions, ≥ 5 contracts (`requires`/`ensures`), and an implementation of ≥ 50 lines. Below that threshold, the recipe is toy and does not stress the mechanism.
- **"Drift bug."** An implementation change that violates the recipe's contract but not any local test. Three drift bugs per Tier 2 test: subtle enough that a fresh reader would not spot them, obvious enough that a contract check should catch them.
- **"Capability-abuse shape."** A dependency (Mo recipe or Elixir hex package) that appears to do one thing but attempts a second effect. Example: a JSON parser that also tries to open a file. The 10 shapes are chosen by the auditor (or a session Fable spawns for this purpose) and sealed before program 7's first commit.
- **"Change-6-style modification."** A functional change that alters a piece of program 7 which, in Elixir, would live behind a hex dependency (say, changing the JSON library's error-handling shape, or replacing the HTTP server's TLS configuration).

---

## 5. What "retires" means for the capabilities/recipes claim

**T-A: Full retirement.** Chapter 6's model is not viable for production programs; Mo's zero-dependency stance is aspirational, not a delivered feature. Chapter 1 loses the "no third-party code" leg of the conjunction; the thesis collapses to "reliable software written by agents," and the BEAM/OTP with strict review becomes a plausible tie.

**T-B: Scoped retirement.** Bricks work; recipes do not. Mo can deliver zero-dependency at the cost of shipping a much larger stdlib and no community-contributed shelf. This is a defensible design (Go took this path) but is a different project than the one chapter 6 describes.

**T-C: Deferred retirement.** The rule fires on P2 or P4 but not P1 or P3. In that case, program 7 ships zero-dependency but the recipe experience is bad; project keeps the claim and files fixes as follow-up work (a better recipe surface, faster body regeneration, etc.).

**Auditor's honest reading.** T-B is a real possibility. Bricks are proven; recipes are a bet. If program 7 shows that recipes are painful to write and painful to check, the project should be willing to accept T-B rather than defend a mechanism that is not paying off.

---

## 6. What the rule does *not* bind

- **Ecosystem adoption.** Whether third parties publish recipes is not measured here.
- **The registry itself.** Chapter 6's six-layer registry rules are a separate design; this rule tests only what a program using the mechanism looks like.
- **Bricks' completeness.** If bricks are missing something program 7 needs, that is a stdlib gap, not a capabilities/recipes failure. The auditor tracks such gaps separately.
- **The runtime claim.** Program 7's reliability rows are measured by the runtime rule, not this one. Same program, different measurements.
- **The language layer's catches.** `never`/`invariant` rule.

---

## 7. When the rule is evaluated

- **Before program 7's first commit:** the hidden capability-abuse suite is sealed by the auditor (or by a Fable-spawned session that does not touch program 7); the drift-bug set for P2a is sealed; the change-6-style modifications for P4 are named in advance.
- **After program 7's final Mo commit:** the lockfile is inspected for P1; the recipe count and drift-bug catches for P2 are read; the capability-abuse suite runs for P3.
- **When the maintenance modification lands:** P4 time is recorded, both languages.
- **The reading:** the auditor files `audit/mo-audit-YYYY-MM-DD-program-7-caps-reading.md` in this directory, before Fable's reading is filed. Robert picks T-A, T-B, or T-C if the rule fires.

---

## 8. What clears the rule, made concrete

- Program 7 lockfile: 0 third-party runtime packages, 4 recipes (rate limiter, JSON parser, TLS wrapper, background jobs) with ≥ 50-line implementations, plus bricks (stdlib HTTP server, crypto, DB driver). P1 clears.
- Drift-bug seeds: 3/3 caught by `mo check --recipe`. P2a clears with margin.
- No recipe needs a just-trust-me clause; body regeneration on a spec change does not introduce undetected drift. P2b, P2c clear.
- Capability-abuse suite: 0 escapes in Mo, 4 in Elixir. P3 clears clean.
- Change-6-style modification: Mo maintainer 25 minutes, Elixir maintainer 20 minutes. P4 clears (1.25×).

Under that outcome, the second leg of the thesis conjunction is vindicated. Chapter 6 becomes reference-implementation grade.

---

## 9. What retires the rule, made concrete

- Program 7 lockfile: 2 third-party runtime packages (a JSON parser that would have needed 400 lines of recipe body to reimplement, and a TLS wrapper that needed system-library glue). P1 fails.
- Drift-bug seeds: 1/3 caught. P2a fails.
- Recipe regeneration introduces drift the checker misses on 2/5 seeded cases. P2c fails.
- Capability-abuse suite: 3 escapes in Mo (a `Fs` capability leaked through a recipe body that used it beyond scope, a `Net` capability chain to a logging call). P3 fails.
- Change-6-style modification: Mo maintainer 90 minutes, Elixir maintainer 20 minutes. P4 red (4.5×).

Under that outcome, T-A or T-B is the honest response. Robert picks.

---

## 10. Auditor's honest priors

Recorded 17 Sep 2026, before program 7:

- **~0.35 chance:** clean T-B outcome. Bricks clear P1 for functionality they cover, recipes fail on 1–2 things, project accepts scoped retirement.
- **~0.25 chance:** T-C outcome. P1 clears, P3 clears, P2 or P4 fails; recipe surface needs fixes but the direction is right.
- **~0.20 chance:** clean win (all tiers clear). Chapter 6's design vindicated on program 7's specific shape.
- **~0.15 chance:** T-A retirement. Recipes are impractical, brick stdlib is not big enough, program 7 ships with 3+ deps and the zero-dependency claim collapses.
- **~0.05 chance:** something the auditor cannot predict, probably registry-shaped (age gates or capability manifests interacting with a real program in a way the design did not anticipate).

Sum: 1.00 (checked).

---

## 11. Auditor's second flag on ordering

Program 7's design shape is described in chapter 1 and the program menu but has not been fully specified. Two things must be true before program 7 can start:

1. The bricks page (Fable's roadmap item #4) must exist, so the shelf boundary is unambiguous — what a program can rely on before needing a recipe.
2. The dependency claim's cost must be stated — how big the audited platform code is, what its update cadence is, what its own dependency surface looks like.

**Auditor's recommendation:** the bricks page should land before program 7 starts, not after, so the capabilities audit can name specific bricks in the drift-bug seeds and the P4 modifications. Otherwise the rule is written against a moving target.

---

## 12. The rule in three sentences

1. If program 7 ships with 0 third-party runtime dependencies (P1), and its recipe surface catches 2/3 drift bugs (P2a), and the capability-abuse suite finds ≤ 1 Mo escape vs. ≥ 3 Elixir escapes (P3), and maintainer time on a change-6-style modification is ≤ 1.5× Elixir's (P4), the capabilities/recipes claim is vindicated.
2. If any tier fails as specified, the claim retires under T-A, T-B, or T-C at Robert's choice.
3. The pre-registration — hidden capability-abuse suite, drift-bug seeds, named maintenance modifications — must be sealed by the auditor before program 7's first commit, and the reading is filed by the auditor before Fable's is read.

---

## 13. What the auditor asks of Robert

Four things:

1. **Accept, amend, or reject the rule.** If amended, name the specific numeric changes.
2. **Choose T-A, T-B, or T-C in advance,** or defer explicitly.
3. **Decide whether the bricks page ships before program 7,** which the auditor recommends.
4. **Confirm Fable will draft a parallel reading** independently.

The auditor does not need Fable's answers before program 7. But the pre-registration must be sealed before program 7's first commit.

---

## 14. Related pages

- `audit/mo-audit-2026-09-17-stopping-rule-never-invariant.md` — the language-layer rule.
- `audit/mo-audit-2026-09-17-stopping-rule-runtime.md` — the primary (runtime) rule.
- `mo-wiki/spec/design-v0/01-premise.md` — the thesis conjunction, reliability AND zero third-party code.
- `mo-wiki/spec/design-v0/06-packages.md` — bricks, kits, recipes, and the registry.
- `mo-wiki/plans/roadmap.md` — the bricks page as roadmap item #4; program 7 as #6.

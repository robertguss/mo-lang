# Audit deliverable: a stopping rule for `never` and `invariant`

**Date:** 17 September 2026
**Author:** the auditor (a Perplexity session, independent of Fable)
**Charter:** as accepted by Robert 17 Sep 2026; the auditor does not design, execute, or accept work, only reads evidence and files readings for the decision log.
**Status:** draft for Robert. Fable's parallel draft, if written, is to be read alongside this one and not before it.
**Purpose:** state, before the next erosion generation runs, at what point the language layer's third-layer claim — "the language removes classes of bug that tests miss" — is retired if the evidence keeps going the way it has.

---

## 1. Why this document exists

The state-of-project page says it plainly, on 16 Sep 2026:

> the laws have not caught a bug that tests would have missed, in any language, in ten rounds and nine round-9 sessions.

Chapter 1 of the design v0 states that the language's job is layer 3 of the thesis, and that "a law belongs in the language when it removes a class of bug." Chapter 10 §4 records that after generation 5, no `never` has tripped on a wrong edit written to press on a law, and that the one `never` false positive of round 8 cost the maintainer two loops. Chapter 10 §4's recommendation is "keep `never` and `invariant`; record false positives as a column from round 9 on." That recommendation contains no retirement condition.

Every research program that runs long enough on a claim that keeps failing eventually faces the same question: **at what evidence point do we retire the claim rather than run one more round hoping it turns?** Mo has run ten rounds hoping it turns. This document proposes the answer, so that the answer exists in writing *before* generations 6–10 add their evidence, rather than being negotiated after.

The auditor does not decide. Robert decides. The auditor's job is to make sure the decision is legible.

---

## 2. What "the claim" actually is, made specific

Loose statements of "the laws catch bugs" have two failure modes: they either promise too much (any law that fires once is vindicated) or promise nothing (any run of failures can be reframed). The claim needs to be made precise before a stopping rule can bind it.

The claim, restated from chapter 1 and chapter 10 §4:

> `never` clauses and `invariant`s, as language-level checks that run on values at rest and after every state update, catch a non-trivial class of change-induced bugs that the program's own tests, the toolchain's type and effect checks, and the runtime's supervision and deadline laws would not catch. The `never`/`invariant` layer is worth its cost — false positives, additional program text, additional maintainer attention — because that class exists and matters.

Three sub-claims are folded inside this:

- **C1: existence.** There exists at least one bug, in the corpus of rounds and erosion generations, that no test caught, no type/effect check flagged, no runtime law bounded, and that a `never` or `invariant` did catch.
- **C2: rate.** Across the maintenance-round corpus, the fraction of change-induced bugs that only a `never` or `invariant` catches is non-trivial — meaningfully above zero over a fair sample.
- **C3: cost.** The catches in C2 are worth the false-positive rate and the program-text burden.

C1 is the weakest; it needs one case, ever, in the whole record. C2 is a rate claim; it needs a base and a fraction. C3 is a value judgment; a stopping rule cannot bind it directly, but it can bind the inputs (catch rate and false-positive rate) that determine it.

**What the record shows today, 17 Sep 2026, on these three sub-claims:**

- **C1: zero cases.** No bug in any control round (1–10) or erosion generation (1–5), in any language, has been caught by a `never` or `invariant` that no test also caught. Round 3 had one bug caught by a test *and* a `never` together, which is not a case for C1. Round 7's `never` at rest on the log states a class of defect (torn line) that Elixir's round-10 program did carry — but that Elixir defect was found by Fable's outside probe, not by an Elixir invariant, so it does not confirm C1 either. C1 has zero supporting cases and zero disconfirming cases in the same direction: it is simply unsupported, not falsified.

- **C2: undefined, because the denominator is small and the numerator is zero.** The maintenance-round corpus is 5 erosion generations across 4 languages = 20 change sessions. The total change-induced defect count across those 20 sessions is small (~5–10 defect causes total across all four languages). Zero were caught by a `never`. The rate is 0/(5–10). That is uninformative at this sample size.

- **C3: cost is real and measured.** One `never` false positive in round 8 cost two loops. Change 5 in generation 5 had three `never`s written by the Mo maintainer, none of which tripped; the labor to write them was paid and returned nothing. The `invariant` construct is under separate reconsideration in chapter 10 §4 option C. Cost is not zero; catches are.

The auditor's reading of the current state: the record supports keeping `never` and `invariant` on the ground of C3-hope (they might yet earn out) but not on the ground of C1 or C2 evidence.

---

## 3. What a stopping rule must look like

A stopping rule that binds must have five properties:

1. **Pre-registered.** Written before the evidence it will judge is collected.
2. **Directional.** States separately what evidence keeps the claim, what evidence retires the claim, and what evidence is ambiguous.
3. **Numeric.** Uses counts, not adjectives.
4. **Sample-bounded.** States the minimum sample size at which the rule fires; a rule that could fire on n=1 is not a rule.
5. **Cost-inclusive.** Considers false positives and program-text burden alongside catches, so the rule does not vindicate a check that catches once and costs many loops.

The rest of this document proposes such a rule, and then argues for its numbers.

---

## 4. Proposed rule

The rule below is stated in three tiers matching C1, C2, C3. All three must clear their threshold for `never`/`invariant` to remain in the language after generation 10.

### Tier 1 — existence (C1)

**By the end of erosion generation 10, at least one bug shall have been caught in the Mo maintenance corpus by a `never` or `invariant` where no test in the same program's suite (including hidden suites), no Mo-provided type/effect/capability/deadline check, and no runtime supervision, would have flagged the same bug on the same input.**

- **If zero such cases exist by generation 10:** C1 fails. The construct set retires. (See §5 for the "retires to what" clarification.)
- **If one or more such cases exist by generation 10:** C1 clears. Proceed to Tier 2.

**Auditor's note.** The "no test would have caught" clause is doing heavy work. Fable, if writing this rule, might weaken it to "no test in the suite as written" — but the honest form is "no reasonable test the maintainer would have written." Since we cannot ask the counterfactual maintainer, the rule uses "no test in the same program's suite" as the operational form, with the auditor's flag: if a `never` catches a bug that any competent test would have caught, that case is a case for tests, not for `never`.

### Tier 2 — rate (C2)

**Across generations 6 through 10 combined, the count of Mo defect causes caught by `never` or `invariant` alone (per Tier 1's definition) shall be at least 2, and at least as high as the count of Mo defect causes caught by tests-only over the same generations.**

- **Denominator.** 5 generations × 1 Mo maintainer per generation = 5 Mo change sessions. Add the ~5 Mo defect causes carried in from generations 1–5 and any new ones in 6–10. Rough expected N: 5–15 Mo defect causes across generations 6–10.
- **Numerator (target).** At least 2 caught by `never`/`invariant` alone.
- **Comparator.** At least tied with tests-only catches — i.e., the language layer is at parity with the test layer as a defect-catching mechanism over this window.
- **If < 2 such catches, OR strictly fewer than the tests-only count, by generation 10:** C2 fails. The construct set retires.

**Auditor's note on why 2, not 1 or 3.** One is a single-case win that could be lucky. Three would require a rate that the corpus historically does not produce for any single check (MO0317 is the highest-impact diagnostic in the corpus and it hits 6/7 sightings across roughly the same window). Two is the smallest count that is not a one-off, chosen deliberately at the low end so the rule does not require heroic performance to keep the construct. If the construct cannot clear the low end, that is the finding.

### Tier 3 — cost (C3)

**Across generations 6 through 10 combined, the false-positive rate of `never`/`invariant` clauses that trip on correct code (not on a wrong edit) shall be at most 1.5× the true-positive count from Tier 2. And the median Mo maintainer's program shall contain at most 5 hand-written `never`/`invariant` clauses per 1,000 lines of Mo code.**

- **If false positives exceed the cap, OR the density exceeds the cap:** C3 fails. The construct set retires *even if Tier 1 and Tier 2 clear* — because a check with real catches that costs disproportionate labor is a bad trade.
- **Density measurement.** Counted per generation from the Mo maintainer's shipped program, averaged across generations 6–10.

**Auditor's note.** Generation 5 already showed three `never`s and zero trips on ~1,500 lines, giving ~2 per 1,000 lines. The 5-per-1,000 cap is intentionally loose and allows the density to grow if maintainers find them useful. If maintainers start writing 10 per 1,000 to defend against the fifth generation's Mo-only defect (which no `never` caught), that is signal that the construct is being asked to do work it cannot do.

---

## 5. What "retires" means, made specific

"Retire" is a designed term of art, not a suggestion. Because it appears in a pre-registered rule, its meaning must be as unambiguous as the threshold. Two interpretations exist, and Robert picks one:

**R-A: Retire from the language.**
`never` and `invariant` are removed from Mo's grammar. The `never` clauses in existing programs are converted to test-suite entries (an assertion in a `# run:` transcript or a `test "the invariant holds"` block) by an automated `mo fix`. The diagnostic MO0403-adjacent surface remains for `Time.fixture()` and other proven-value checks. The language surface shrinks; chapter 2 and chapter 3 lose their sections on `never`.

**R-B: Retire from the reading rule, keep in the language.**
`never` and `invariant` stay as language constructs for the user who wants them, but they are no longer counted as part of the claim "the language removes classes of bug." Chapter 1's third layer is rewritten to say the language layer's job is *readability at spec altitude and machine-checkable contracts*, not "removes classes of bug tests miss." The `never` construct is downgraded from language-level claim to project-setting-level tool, similar to what happened to the counted shape laws after round 6.

**Auditor's recommendation.** R-B, unless Tier 3 fails badly (density > 10 per 1,000 lines with false positives > 3× catches), in which case R-A. R-B is honest and reversible: if a future round produces evidence that vindicates the construct, R-B can reverse without a language-grammar change. R-A is stronger but harder to undo and imposes a migration on any code already using `never`. The corpus is small enough today (175 `.mo` files) that R-A migration would be one worker session; that will change fast, so the choice window is short.

Robert's call. This is a design decision, not an audit finding.

---

## 6. What the rule does *not* bind

To be fair to the construct and to Fable's likely reading, list what this rule intentionally leaves alone:

- **Class-of-defect claims stated in the source that are checked only in tests.** A `test rejects` block that trips a `requires` is not a `never`; it is the contract-test law, which is a separate claim with its own record (very good — round-9 first-fix rates above 0.9 for MO0311 and adjacent).
- **The `verified:` line and MO0317.** These are toolchain-honesty diagnostics, not language-layer defect catchers. Their value is not covered by this rule.
- **The `never` at rest on the log** (round 7's `store.mo`). This is a state-invariant on persistent data structures. If chapter 10 §4's reading holds — that this exact construct catches a class Elixir cannot state — then generations 6–10 can produce the case that clears Tier 1 on the strength of this one construct alone. That would be a clean C1 win.
- **Types, effects, capabilities, deadlines.** All separately claimed, all separately validated, all outside this rule's scope. Do not confuse a `never` retirement with a type-system retirement; they are different layers of the thesis.

If the rule fires and `never`/`invariant` retire, the language is *still* differentiated on types, effects, capabilities, deadlines, the runtime surface, and the `verified:` line. This rule is a scoped retirement, not a project retirement.

---

## 7. When the rule is evaluated

- **Continuously, after each of generations 6, 7, 8, 9, 10.** After each generation's reading, the auditor updates a small ledger:
  - Tier 1: any new cases?
  - Tier 2: current count of `never`/`invariant`-only catches; current count of test-only catches over generations 6–N.
  - Tier 3: current false-positive count; current density.
- **Final evaluation at generation 10's reading.** The rule fires or does not fire at that point, on the numbers as recorded.
- **The ledger is auditor-owned.** Fable does not write it. Fable can read it. Robert can amend it, but any amendment is a decision-log row with a stated reason.

---

## 8. Two edge cases the rule handles

**Case A: a `never` fires between generations 6–10 on a bug tests also caught.**
- Tier 1: does not count (must be tests-not-catching).
- Tier 2: does not count.
- Tier 3: does not count as a false positive either.
- Effect: neutral. The construct did its job but so did the test. The rule does not vindicate.

**Case B: an `invariant` fires on a bug where the test suite is arguably deficient — a test *could* have been written but wasn't.**
- Auditor call. The `never`/`invariant` gets credit under Tier 1 and Tier 2 *only if the test that would have caught it is one no reasonable maintainer under this workload would have written*. Otherwise it counts as tests-would-have-caught, and the case is neutral.
- This is the judgment call in the rule. It is unavoidable. The auditor documents each case's reasoning in the ledger; Robert can overturn.

---

## 9. What clears the rule, made concrete

The clearest possible version of "the rule clears" over generations 6–10 looks like:

- Generation 6's Mo maintainer inherits generation 5's shipped defect (the folder that its own `verify` refuses after compact+rename). They add a `never` on the invariant that would catch that class ("a compact must not leave a rename count that a subsequent rename fails to raise"). Generation 7's change presses on the archive path in a way that would produce the same bug shape via a different code path; the `never` fires and no test in the generation-7 hidden suite would have caught it.
- Generation 8 introduces a change to lease semantics where the same-worker-holds-two-leases invariant is stated as a `never on (worker, live_leases)`. A generation-8 maintainer writes a leak; the `never` catches it. The suite's tests do not.
- Total across 6–10: 2 catches, 0 or 1 false positives, density ~3 per 1,000 lines.

That is a version of the future where the language layer earns its row. It is a specific version; the rule is agnostic between it and other specific versions that clear the same thresholds.

The auditor is not predicting this happens. The auditor is stating what "it happened" would look like, in advance, so Fable cannot retroactively adjust what counts.

---

## 10. What retires the rule, made concrete

The clearest possible version of "the rule retires" over generations 6–10 looks like:

- Generation 6's Mo maintainer adds 4 `never`s, none trip on the wrong edits, one trips on a rekeyed retry (false positive).
- Generation 7's Mo defect is a race condition on the archive scan — no `never` states the invariant, and no test in the suite catches it; it is found by Fable's outside probe.
- Generations 8, 9, 10 produce Mo defects at rates similar to Go's and Elixir's, none caught by `never`, some caught by tests, some caught only by Fable's probing.
- Total across 6–10: 0–1 catches, 2–4 false positives, density growing to ~4–5 per 1,000 lines as maintainers try harder.

That is the version where the rule fires. Robert then chooses R-A or R-B.

The auditor thinks (17 Sep 2026, on the evidence) that this second version is more likely than the first. That is not a decision; it is a prior, stated so it can be checked against.

---

## 11. The rule in three sentences

1. If, by the reading of erosion generation 10, `never` or `invariant` has caught at least 2 Mo defects that no test would have caught, at a false-positive rate below 1.5× the catches, at a density below 5 per 1,000 lines, the construct set stays and the language-layer claim on it is vindicated.
2. If any of those thresholds fails, the construct set retires under R-A or R-B at Robert's choice.
3. The ledger is maintained by the auditor after each generation and cannot be revised after the fact.

---

## 12. Auditor's honest priors

Written as priors, before the evidence, so they can be checked.

- **Most likely (subjective probability ~0.65): the rule fires at generation 10 and R-B is the right retirement.** Historical base rate: no language check has caught a bug tests missed in ten rounds. The prior on that continuing is high.
- **Second most likely (~0.25): the rule clears at Tier 1 (one clean case, probably the log-integrity case chapter 10 §4 already flags), fails at Tier 2 (single catch, not two).** In that case, Robert has a live decision: promote the log-integrity-`never` to a language-supported pattern (a specific typed construct, not the general `never`), and retire the general form.
- **Least likely (~0.10): the rule clears fully.** The corpus expands (program 7 arrives; the ledger's `invariant`s finally exercise the construct on state changes), and the maintenance work under those programs produces the 2+ catches at low false-positive rate.

Priors recorded 17 Sep 2026, auditor session `04d60aca`, before generation 6 runs.

---

## 13. What the auditor asks of Robert

Three things:

1. **Accept, amend, or reject the rule.** If amended, state the specific numeric changes; a rule with adjectives is not a rule.
2. **Choose between R-A and R-B, or defer to generation 10's reading.** Deferring is fine but should be a stated decision, not a silent one.
3. **Confirm that Fable's parallel reading of this same question shall be drafted independently and filed alongside.** If Fable's reading differs on thresholds or on retirement mechanics, that disagreement is itself a row.

The auditor does not need Fable's answers to any of this before the next generation begins. But the auditor does need Robert's answer before generation 6's reading, so that the reading is against a rule that exists, rather than against a rule being written under pressure.

---

## 14. Related pages

- `mo-wiki/spec/design-v0/01-premise.md` — the three-layer thesis and its layer-3 claim.
- `mo-wiki/spec/design-v0/10-language-after-the-rounds.md` §4 — the current position on `never`/`invariant`.
- `mo-wiki/state-of-the-project.md` — the "laws catch what tests miss" row, current standing "not shown; the biggest open risk."
- `mo-wiki/plans/erosion-round.md` — the generation record; the ledger from §7 lives here or beside it.

---
title: "Author: Niklaus Wirth (Pascal, Modula-2, Oberon)"
created: 2026-09-13
updated: 2026-09-13
type: concept
tags: [research, compiler, performance]
sources: [raw/research-runs/2026-09-13-authors-the-elders.pplx.md]
confidence: high
---

# Author: Niklaus Wirth (Pascal, Modula-2, Oberon)

Wirth is the one designer in this set who shrank his language on every iteration and who tied language decisions to a measured budget. He is the strongest precedent for Mo's compile-speed-as-a-feature position and the strongest critic of Mo's growing mechanism count.

## Ethos in his own words

"Software is getting slower more rapidly than hardware becomes faster." ([A Plea for Lean Software, 1995](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf))

"A primary cause of complexity is that software vendors uncritically adopt almost any feature that users want." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf))

"But it is not the inherent complexity that should concern us; it is the self-inflicted complexity." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf))

"Time pressure is probably the foremost reason behind the emergence of bulky software." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf))

"A programmer's competence should be judged by the ability to find simple solutions, certainly not by productivity measured in "number of lines ejected per day."" ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf))

"Actually, a language is not so much characterized by what it allows to program, but more so by what it prevents from being expressed." ([Good Ideas, Through the Looking Glass, 2005](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf))

"At the very least, their cost to the user must be known before a language is released, published, and propagated. This cost must be commensurate with the advantages gained by the feature." ([Good Ideas](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf))

"Simple, elegant solutions are more effective, but they are harder to find than complex ones, and they require more time, which we too often believe to be unaffordable." ([Turing lecture, CACM February 1985](https://www.arabou.edu.kw/faculties/computer/Documents/ReadingList/ITC/a1984-wirth.pdf))

"I never could separate the design of a language from its implementation, for a rigid definition without the feedback from the construction of its compiler would seem to me presumptuous and unprofessional." ([Turing lecture](https://www.arabou.edu.kw/faculties/computer/Documents/ReadingList/ITC/a1984-wirth.pdf))

## Defining decisions

Shrink, do not grow. Oberon was "derived from Modula-2 by eliminating less essential features (like subrange and enumeration types) in addition to features known to be unsafe (like type transfer functions and variant records)," under the rule "Reducing complexity and size must be the goal in every step—in system specification, design, and in detailed programming." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf)) Result: "The Oberon core occupies fewer than 200 Kbytes, including editor and compiler." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf))

Self-compilation time as the quality metric. Primary evidence is the measurement itself: "It now measures less than 2900 lines of program and compiles itself in about 3 seconds, which is proof of its efficiency," and "The entire system compiles itself in less than 10 seconds." ([Project Oberon](https://people.inf.ethz.ch/~wirth/ProjectOberon/PO.System.pdf)) The budget rule is recorded by his student rather than by Wirth: "He used the compiler's self-compilation speed as a measure of the compiler's quality," and only optimisations whose own cost was "fully compensated" were admitted ([Oberon — The Overlooked Jewel, Michael Franz](https://dcreager.net/pdf/Franz2000.pdf), secondary).

Checks always generated. "Considered extravagant and hardly necessary only years ago, run-time checks are generated automatically. Due to their efficiency they hardly affect run-time speed, but are a great benefit to programmers." ([Project Oberon](https://people.inf.ethz.ch/~wirth/ProjectOberon/PO.System.pdf))

Constrain manpower deliberately. "The consciously planned shortage of manpower enforced a single, but healthy, guideline: Concentrate on essential functions and omit embellishments that merely cater to established conventions and passing tastes." ([Project Oberon](https://people.inf.ethz.ch/~wirth/ProjectOberon/PO.System.pdf)) Judgment: agents remove exactly this constraint, and Mo's laws are an attempt to reinstate it artificially.

No type-system loopholes. "The loophole lets the programmer breach the type checking by the compiler," and "A chain is only as strong as its weakest member." ([Good Ideas](https://people.inf.ethz.ch/wirth/Articles/GoodIdeas_origFig.pdf))

## Where he contradicts Mo

"Prolific programmers contribute to certain disaster." ([A Plea for Lean Software](https://blog.frantovo.cz/s/1576/Niklaus%20Wirth%20-%20A%20Plea%20for%20Lean%20Software%20-%20OCR.pdf)) Mo's premise is a prolific author by construction. His feature-cost rule also demands a published ledger charging every Mo mechanism against compile time and reader effort; Mo does not have one.

## What Mo could take

| idea | maps to | status |
|---|---|---|
| Self-compilation time as the headline metric, published per release | [[d23-compile-speed-first-class]] | strengthens Mo |
| A feature-cost ledger charging each law and mechanism to the user | [[q12-law-numbers]] | new idea for Mo |
| Remove features between versions and count removals as progress | [[d05-old-ideas-rethought-ai-first]] | new idea for Mo |
| Runtime checks always generated, never optional | [[tiger-style-and-power-of-ten]] | already in Mo |
| No loophole, but supply the mechanism that makes it unnecessary | [[q16-escape-hatch]] | strengthens Mo |
| "Characterized by what it prevents" as the framing sentence | [[d19-negative-space-is-the-contract]] | already in Mo |

## Related

- [[d23-compile-speed-first-class]]
- [[q12-law-numbers]]
- [[negative-space-programming]]
- [[d27-simple-and-elegant-like-ruby]]
- [[prompts-research-agenda-2026-09]]
- [[author-edsger-dijkstra]]
- [[author-tony-hoare]]

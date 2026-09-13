---
title: "Author: Edsger Dijkstra (structured programming, guarded commands)"
created: 2026-09-13
updated: 2026-09-13
type: concept
tags: [research, verification, philosophy]
sources: [raw/research-runs/2026-09-13-authors-the-elders.pplx.md]
confidence: high
---

# Author: Edsger Dijkstra (structured programming, guarded commands)

Dijkstra is the source of Mo's two deepest tensions: that tests cannot establish absence of bugs, and that banning a construct is worthless if the ban can be satisfied mechanically. A guarded command is a statement prefixed by a boolean guard; only true guards are eligible, and which eligible guard runs is deliberately unspecified.

## Ethos in his own words

"Program testing can be used to show the presence of bugs, but never to show their absence!" ([Notes on Structured Programming, EWD249](https://www.cs.utexas.edu/~EWD/ewd02xx/EWD249.PDF))

"The art of programming is the art of organizing complexity, of mastering multitude and avoiding its bastard chaos as effectively as possible." ([EWD249](https://www.cs.utexas.edu/~EWD/ewd02xx/EWD249.PDF))

"The competent programmer is fully aware of the strictly limited size of his own skull; therefore he approaches the programming task in full humility, and among other things he avoids clever tricks like the plague." ([The Humble Programmer, EWD340](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html))

"On the contrary: the programmer should let correctness proof and program grow hand in hand." ([EWD340](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html))

"The purpose of abstracting is not to be vague, but to create a new semantic level in which one can be absolutely precise." ([EWD340](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html))

"I see a great future for very systematic and very modest programming languages." ([EWD340](https://www.cs.utexas.edu/~EWD/transcriptions/EWD03xx/EWD340.html))

"The tools we use have a profound (and devious!) influence on our thinking habits, and, therefore, on our thinking abilities." ([EWD498](https://www.cs.utexas.edu/~EWD/transcriptions/EWD04xx/EWD498.html))

"In the discrete world of computing, there is no meaningful metric in which "small" changes and "small" effects go hand in hand, and there never will be." ([EWD1036](https://www.cs.utexas.edu/~EWD/transcriptions/EWD10xx/EWD1036.html))

"we do not know how to reach simplicity in a systematic manner." ([EWD1284](https://www.cs.utexas.edu/~EWD/transcriptions/EWD12xx/EWD1284.html))

## Defining decisions

Abolish the go to, with a stated cognitive reason. "our intellectual powers are rather geared to master static relations and that our powers to visualize processes evolving in time are relatively poorly developed," so the goal is "to shorten the conceptual gap between the static program and the dynamic process." ([EWD215](https://www.cs.utexas.edu/~EWD/transcriptions/EWD02xx/EWD215.html)) The verdict: "The go to statement as it stands is just too primitive, it is too much an invitation to make a mess of one's program." ([EWD215](https://www.cs.utexas.edu/~EWD/transcriptions/EWD02xx/EWD215.html)) The caveat Mo needs: "The exercise to translate an arbitrary flow diagram more or less mechanically into a jumpless one, however, is not to be recommended." ([EWD215](https://www.cs.utexas.edu/~EWD/transcriptions/EWD02xx/EWD215.html))

A coordinate system the programmer cannot fake. Progress should be describable by textual indices whose "values of these indices are outside programmer's control." ([EWD215](https://www.cs.utexas.edu/~EWD/transcriptions/EWD02xx/EWD215.html)) Judgment: Mo's seeded deterministic simulation with a replayable message log is the modern instance of this idea.

Guarded commands and useful nondeterminism. "The potential non-determinacy allows us to map otherwise (trivially) different programs on the same program text, a circumstance that seems largely responsible for the fact that now programs can be derived in a more systematic manner then before." ([EWD472](https://www.cs.utexas.edu/~EWD/transcriptions/EWD04xx/EWD472.html)) Hoare built CSP's alternatives on them ([CSP](https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf)).

Programs as formulas. "It really helps to view a program as a formula," against a discipline that he says "has accepted as its charter 'How to program if you cannot.'" ([EWD1036](https://www.cs.utexas.edu/~EWD/transcriptions/EWD10xx/EWD1036.html))

## Where he contradicts Mo

Mo's tier-2 verified line is computed from tests, contracts and properties; Dijkstra's sentence about presence and absence makes that a confidence marker, not a proof. Mo's while ban can be satisfied by a fake constant bound, which is exactly the mechanical translation he warned against. And Mo's numeric shape laws try to legislate a simplicity that he says cannot be reached systematically ([EWD1284](https://www.cs.utexas.edu/~EWD/transcriptions/EWD12xx/EWD1284.html)).

## What Mo could take

| idea | maps to | status |
|---|---|---|
| Rename or qualify the verified line so it never implies proof from tests | [[q08-verification-tiers]] | strengthens Mo |
| Bounded loops must carry a real termination argument, not a fictional constant | [[d19-negative-space-is-the-contract]] | contradicts Mo |
| Deterministic replay as the progress coordinate system the author cannot fake | [[d21-autonomous-crash-fixing]] | already in Mo |
| Explore all admissible interleavings, not one seed | [[q08-verification-tiers]] | new idea for Mo |
| Contracts must carry the body's whole obligation, since small edits are not small | [[d02-spec-altitude]] | strengthens Mo |

## Related

- [[q08-verification-tiers]]
- [[d19-negative-space-is-the-contract]]
- [[tiger-style-and-power-of-ten]]
- [[spark-ada-and-dafny]]
- [[prompts-research-agenda-2026-09]]
- [[author-tony-hoare]]
- [[author-niklaus-wirth]]

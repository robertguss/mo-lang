---
title: "Author: Tony Hoare (CSP, Algol W, Hoare logic)"
created: 2026-09-13
updated: 2026-09-17
type: concept
tags: [research, verification, processes]
sources: [raw/research-runs/2026-09-13-authors-the-elders.pplx.md]
confidence: high
---

# Author: Tony Hoare (CSP, Algol W, Hoare logic)

Hoare supplies Mo with three things: a scorecard for language design, the argument for mandatory runtime checks, and the process model that Go and Erlang both descend from. CSP means communicating sequential processes: isolated processes that share nothing and interact only by synchronous channel communication.

## Ethos in his own words

"The price of reliability is the pursuit of the utmost simplicity. It is a price which the very rich find most hard to pay." ([The Emperor's Old Clothes, 1980](https://dl.acm.org/doi/pdf/10.1145/358549.358561))

"I conclude that there are two ways of constructing a software design: One way is to make it so simple that there are obviously no deficiencies and the other way is to make it so complicated that there are no obvious deficiencies. The first method is far more difficult." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561))

"A feature which is omitted can always be added later, when its design and its implications are well understood. A feature which is included before it is fully understood can never be removed later." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561))

"I was eventually persuaded of the need to design programming notations so as to maximize the number of errors which cannot be made, or if made, can be reliably detected at compile time." ([The Emperor's Old Clothes](https://dl.acm.org/doi/pdf/10.1145/358549.358561))

"The readability of programs is immeasurably more important than their writeability." ([Hints on Programming Language Design, 1973](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf))

"The previous two sections have argued that the objective criteria for good language design may be summarized in five catch phrases: simplicity, security, fast translation, efficient object code, and readability." ([Hints](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf))

"His task is consolidation, not innovation." ([Hints](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf))

## Defining decisions

Security as a language property, checks always on. "A consequence of this principle is that every occurrence of every subscript of every subscripted variable was on every occasion checked at run time against both the upper and the lower declared bounds of the array." ([Emperor](https://dl.acm.org/doi/pdf/10.1145/358549.358561)) How it aged, in his words: customers "urged us not to" add an option to switch checks off, followed by "I note with fear and horror that even in 1980, language designers and users have not learned this lesson," and "In any respectable branch of engineering, failure to observe such elementary precautions would have long been against the law." ([Emperor](https://dl.acm.org/doi/pdf/10.1145/358549.358561))

Null references. "This led me to suggest that the null value is a member of every type, and a null check is required on every use of that reference variable, and it may be perhaps a billion dollar mistake." ([Null References: The Billion Dollar Mistake, QCon 2009](https://www.infoq.com/presentations/Null-References-The-Billion-Dollar-Mistake-Tony-Hoare/)) He assigns the blame to designers: "A programming language designer should be responsible for the mistakes made by programmers using the language." ([InfoQ](https://www.infoq.com/presentations/Null-References-The-Billion-Dollar-Mistake-Tony-Hoare/))

CSP, with its limits stated. "This paper suggests that input and output are basic primitives of programming and that parallel composition of communicating sequential processes is a fundamental program structuring method." ([CSP, 1978](https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf)) The published model is synchronous and static: "There is no automatic buffering" (the raw extract's "buffeting" corrected here, 17 Sep 2026), and "it is consequently a rather static language: The text of a program determines a fixed upper bound on the number of processes operating concurrently; there is no recursion and no facility for process-valued variables." He also names the gap: "it fails to suggest any proof method to assist in the development and verification of correct programs." ([CSP](https://www.cs.cmu.edu/~crary/819-f09/Hoare78.pdf))

A verifying compiler as a separate instrument. "A verifying compiler uses mathematical and logical reasoning to check the correctness of the programs that it compiles," and "The verifying compiler does not itself have to be verified, though it would be desirable to do so, at least partially." ([The Verifying Compiler, 2003](https://www.csl.sri.com/users/shankar/GC04/hoare-compiler.pdf))

## Where he contradicts Mo

"If anyone is to be allowed to introduce inefficiency it should be the user programmer, not the language designer." ([Hints](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf)) Mo makes deadlines, Result consumption and fault injection mandatory. He also wants intent expressible at every level — "it should enable this to be expressed at various levels, from the overall strategy to the details of coding and data representation" ([Hints](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf)) — where Mo's spec altitude fixes one level. And his warning on orthogonality as a simplicity substitute applies to Mo's mechanism count: "as a substitute for simplicity they are very questionable." ([Hints](http://flint.cs.yale.edu/cs428/doc/HintsPL.pdf))

## What Mo could take

| idea | maps to | status |
|---|---|---|
| Included-before-understood features can never be removed: an admission test for laws | [[q12-law-numbers]] | strengthens Mo |
| Five criteria as Mo's published scorecard per release | [[d23-compile-speed-first-class]] | strengthens Mo |
| Checks always on, no disable flag, justified by his customer story | [[tiger-style-and-power-of-ten]] | already in Mo |
| Prover kept separate and not itself required to be verified | [[d32-proving-is-a-separate-tool]] | already in Mo |
| Intent expressible below the signature, not only at it | [[d02-spec-altitude]] | contradicts Mo |
| A published "what this model does not solve" section, as CSP has | [[d19-negative-space-is-the-contract]] | new idea for Mo |

17 Sep 2026: the intent-below-the-signature row was ruled **already in Mo** on 13 Sep. His inefficiency objection was also measured: contract cost was re-measured at step 21 and the derived deadline shipped at step 22. See [[research-agenda-2026-09-response]].

## Related

- [[d32-proving-is-a-separate-tool]]
- [[d14-processes-are-the-only-identity]]
- [[q08-verification-tiers]]
- [[spark-ada-and-dafny]]
- [[prompts-research-agenda-2026-09]]
- [[author-edsger-dijkstra]]
- [[author-niklaus-wirth]]
- [[research-agenda-2026-09-response]]

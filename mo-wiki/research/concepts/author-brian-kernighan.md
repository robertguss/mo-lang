---
title: "Author: Brian Kernighan (Unix tools, AWK, The Practice of Programming)"
created: 2026-09-13
updated: 2026-09-13
type: concept
tags: [research, philosophy, tooling]
sources: [raw/research-runs/2026-09-13-authors-the-elders.pplx.md]
confidence: high
---

# Author: Brian Kernighan (Unix tools, AWK, The Practice of Programming)

Kernighan is the field's best writer about programming practice and its most effective critic of languages that are strict without being expressive.

## Ethos in his own words

"C is the best balance I've ever seen between power and expressiveness." ([Interview with Brian Kernighan, 2000](https://ioi.di.unimi.it/kernighan.php))

"I think that the real problem with C is that it doesn't give you enough mechanisms for structuring really big programs, for creating ``firewalls'' within programs so you can keep the various pieces apart." ([Interview, 2000](https://ioi.di.unimi.it/kernighan.php))

"C++ I think is basically too big a language, although there's a reason for almost everything that's in it." ([Interview, 2000](https://ioi.di.unimi.it/kernighan.php))

"The languages that succeed are very pragmatic, and are very often fairly dirty because they try to solve real problems." ([Interview, 2000](https://ioi.di.unimi.it/kernighan.php))

"There are only two real problems in computing: computers are too hard to use and too hard to program." ([Linux Journal, 2003](https://www.linuxjournal.com/article/7035))

"Code should be clear and simple-straightforward logic, natural expression, conventional language use, meaningful names, neat formatting, helpful comments-and it should avoid clever tricks and unusual constructions." ([The Practice of Programming](https://theswissbay.ch/pdf/Gentoomen%20Library/Software%20Engineering/B.W.Kernighan,%20R.Pike%20-%20The%20Practice%20of%20Programming.pdf))

## Defining decisions

Attack a teaching language used in production. "Comparing C and Pascal is rather like comparing a Learjet to a Piper Cub - one is meant for getting something done while the other is meant for learning - so such comparisons tend to be somewhat farfetched." ([Why Pascal is Not My Favorite Programming Language, 1981](https://www.lysator.liu.se/c/bwk-on-pascal.html)) On the fixed array bound: "This botch is the biggest single problem with Pascal." ([bwk on Pascal](https://www.lysator.liu.se/c/bwk-on-pascal.html))

Name the missing escape. His conclusion about a strict language without an override is three words: "There is no escape." ([bwk on Pascal](https://www.lysator.liu.se/c/bwk-on-pascal.html)) This is the strongest primary-source argument bearing on [[q16-escape-hatch]].

Teach with complete programs. "The examples in this section are each complete, in the sense that they will run as presented; I have tried to avoid code fragments that merely illustrate syntax." ([A Descent into Limbo](https://www.vitanuova.com/inferno/papers/descent.html))

Document removals as design. Limbo, in his description: restricted pointers with "no & (address of) operator", "no address arithmetic", "no implicit coercions between types", "There is no preprocessor", and an adt that "does not support inheritance, and has no constructors, destructors or overloaded method names." ([A Descent into Limbo](https://www.vitanuova.com/inferno/papers/descent.html))

Label wrong-but-plausible code in the tutorial. "If the input contains any multi-byte Unicode characters, this code is plain wrong." ([A Descent into Limbo](https://www.vitanuova.com/inferno/papers/descent.html))

## Where he contradicts Mo

Mo's laws are unoverridable compiler errors. Kernighan's Pascal essay is the canonical account of that design failing on programs the rule did not anticipate. His historical claim that successful languages are "fairly dirty" ([Interview, 2000](https://ioi.di.unimi.it/kernighan.php)) is a direct bet against Mo's cleanliness.

## What Mo could take

| idea | maps to | status |
|---|---|---|
| Simplicity, clarity, generality, automation as the judging criteria for every law | [[d04-style-rules-become-laws]] | strengthens Mo |
| Pascal's "no escape" as the case for one narrow, auditable override | [[q16-escape-hatch]] | contradicts Mo |
| Every documentation example is a complete runnable program | [[d01-agents-write-the-code]] | new idea for Mo |
| Show the plausible-but-wrong version and label it wrong | [[q09-compiler-diagnostics]] | new idea for Mo |
| Limbo's removal list as precedent for Mo's negative space | [[d06-never-oop]] | already in Mo |

## Related

- [[q16-escape-hatch]]
- [[d04-style-rules-become-laws]]
- [[negative-space-programming]]
- [[go]]
- [[prompts-research-agenda-2026-09]]
- [[author-dennis-ritchie]]
- [[author-rob-pike]]

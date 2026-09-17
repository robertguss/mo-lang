---
title: "Author: Ken Thompson (Unix, C, Go)"
created: 2026-09-13
updated: 2026-09-17
type: concept
tags: [research, security, philosophy]
sources: [raw/research-runs/2026-09-13-authors-the-elders.pplx.md]
confidence: medium
---

# Author: Ken Thompson (Unix, C, Go)

Ken Thompson wrote B, co-wrote C and Unix, co-designed Plan 9, UTF-8 and Go. He publishes rarely, so the primary record is thin: one Turing lecture, a handful of interviews, and Go's design rationale written mostly by his collaborators.

## Ethos in his own words

"I am a programmer. On my 1040 form, that is what I put down as my occupation." ([Reflections on Trusting Trust, CACM 1984](https://dl.acm.org/doi/pdf/10.1145/358198.358210))

"The moral is obvious. You can't trust code that you did not totally create yourself." ([Reflections on Trusting Trust](https://dl.acm.org/doi/pdf/10.1145/358198.358210))

"No amount of source-level verification or scrutiny will protect you from using untrusted code." ([Reflections on Trusting Trust](https://dl.acm.org/doi/pdf/10.1145/358198.358210))

"The three of us got together and decided that we hated C++." ([InformationWeek Q&A, 2011](https://www.informationweek.com/software-services/q-a-ken-thompson-creator-of-unix))

"[In developing Go,] we started off with the idea that all three of us had to be talked into every feature in the language, so there was no extraneous garbage put into the language for any reason." ([InformationWeek Q&A](https://www.informationweek.com/software-services/q-a-ken-thompson-creator-of-unix))

"There are obviously too many features if you can do something that many ways—and they are more or less equivalent." ([Interview, Computer, May 1999](https://www.cs.princeton.edu/courses/archive/spring03/cs333/thompson))

"When in doubt, use brute force." ([reproduced in The Art of Unix Programming](http://www.catb.org/esr/writings/taoup/html/ch01s06.html), secondary reproduction)

## Defining decisions

Trusting trust. Thompson demonstrated a self-reproducing compiler backdoor invisible in source, then generalised: "As the level of program gets lower, these bugs will be harder and harder to detect. A well-installed microcode bug will be almost impossible to detect." ([Reflections on Trusting Trust](https://dl.acm.org/doi/pdf/10.1145/358198.358210)) The attack aged into the central supply-chain problem: xz-utils was compromised through build machinery, not reviewed source ([Andres Freund, oss-security, 29 March 2024](https://www.openwall.com/lists/oss-security/2024/03/29/4)). The two answers the field converged on are reproducible builds ([reproducible-builds.org](https://reproducible-builds.org/)) and diverse double-compiling ([David A. Wheeler](https://dwheeler.com/trusting-trust/)).

Unanimous consent on features. Go's three designers required all three to agree before a feature entered ([InformationWeek Q&A](https://www.informationweek.com/software-services/q-a-ken-thompson-creator-of-unix)). Judgment: Mo has one designer plus a model, so Mo's substitute for unanimity has to be a written admission test, not a conversation.

Redundancy counts as excess. "There are obviously too many features if you can do something that many ways." ([Interview, Computer 1999](https://www.cs.princeton.edu/courses/archive/spring03/cs333/thompson)) This is the same principle the Go team invoked in 2025 to stop error-syntax proposals: "do not provide multiple ways of doing the same thing." ([go.dev blog](https://go.dev/blog/error-syntax))

## Where he contradicts Mo

Mo's [[d03-source-carries-its-evidence]] makes readable source the trust substrate. Thompson's lecture says explicitly that source-level scrutiny cannot establish trust, and Mo compiles through Zig to C, inheriting two toolchains it does not build.

Sources not found: no primary Thompson statement on xz or 2023-2026 supply-chain events, and no primary source for the widely quoted "one of my most productive days was throwing away 1000 lines of code" — both n.a.

## What Mo could take

| idea | maps to | status |
|---|---|---|
| Bootstrap and build provenance, not only source readability | [[d30-supply-chain-security]] | contradicts Mo |
| Reproducible builds plus diverse double-compiling as release requirements | [[q17-package-management-and-supply-chain]] | new idea for Mo |
| Redundancy is excess: one way to do each thing | [[d04-style-rules-become-laws]] | already in Mo |
| A written admission test standing in for unanimous designer consent | [[q12-law-numbers]] | new idea for Mo |

17 Sep 2026: the trusting-trust row was ruled **agree** on 13 Sep and the bootstrap surface measured — see [[research-agenda-2026-09-response]] and the [[decision-log]].

## Related

- [[d30-supply-chain-security]]
- [[d03-source-carries-its-evidence]]
- [[go]]
- [[supply-chain-defenses]]
- [[prompts-research-agenda-2026-09]]
- [[author-dennis-ritchie]]
- [[author-rob-pike]]
- [[research-agenda-2026-09-response]]
- [[decision-log]]

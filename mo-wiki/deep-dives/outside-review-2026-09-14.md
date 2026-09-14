---
title: "Outside review, 14 Sep 2026: a deep review of Mo after round 6"
created: 2026-09-14
updated: 2026-09-14
type: deep-dive
tags: [meta, laws, processes, verification, roadmap, security]
sources: [decisions/decision-log.md, plans/control-run-6.md, spec/design-v0/02-laws.md]
confidence: medium
contested: true
contradictions: [outside-review-2026-09-14-response]
---

# Outside review, 14 Sep 2026

Robert ran an outside review of the whole vault after round 6 and pasted it to Fable on 14 Sep 2026 in the afternoon. Filed verbatim below; Fable's reaction is [[outside-review-2026-09-14-response]]. The reviewer read the vault as it stood before step 27 and before Robert's reframing of the control run, so several of its recommendations were already built or decided when it arrived; the response says which.

## The review, verbatim

> First: this is one of the most rigorously documented language-design projects I've read, hobby or professional. The wiki structure, the numbered directions/questions/decisions, the pre-registered predictions, and the willingness to run round 6 as a genuine falsification test and publish "**Failed, all four**" as the top-line result — that's the mark of a serious research project, not a vanity language.
>
> **What I like — and think you should protect.** The premise is coherent: agents write bodies, humans read spec altitude, style rules become laws with error codes. `MO0311` (a `requires` with no `test rejects` that trips it) is enforced by no other compiler. The failure model (chapter 3) is world-class and a moat. Capabilities as unforgeable parameters obtained only at `main` are the correct answer to the supply-chain problem; recipes as spec-altitude-only packages are the first package model that takes agent economics seriously. The decision log and its process. Directions 37 and 40 (structured runtime events, the runtime surface as a capability) are the best bet on the AI-first axis. Zig for the toolchain, for the honest reasons.
>
> **What I disagree with.** "No warnings, every diagnostic is an error" combined with numeric shape laws (70/500/6/3/12) takes friction the language does not need: the shape laws are load-bearing on the aesthetic argument, not the safety argument; make them project-configurable defaults and keep only the laws that eliminate a category of bug (bounded loops, bounded mailboxes, deadlines, integer overflow). The keyword collisions (`state`, `result`, `old`, `never`, `invariant` as English nouns) are a real problem that step 25 half-fixed; consider sigils or contextual keywords with strong lookahead rather than patching per position. The "no try-catch, no unwrap" law is right in spirit but `try` is Rust's `?` by another name, so the law should say "no unwrap, no panic, no catch_unwind" rather than "no exceptions". Anonymous functions as call arguments only (d31) will bite the first time someone wants a returned partial application; watch the count of "wanted a closure, wrote a struct". The interpreter's performance ceiling: 404 MiB and 57 s under `mo run`, 192 MiB and 14 s native, against Go's 73 MiB and 7.3 s; nudge the C backend earlier. "Zero dependencies by construction" via recipes will not survive contact with a Postgres driver, a TLS stack, gRPC, S3, protobuf, compression, or HTTP/2: either the bricks shelf becomes enormous, a $10M-a-year engineering line elsewhere, or recipes have to work for more than tiny pure-computation modules; the wiki does not price this.
>
> **Tensions underweighted.** The null hypothesis is stronger than round 6 made it look: the baselines with Mo's checks bolted on were 30% smaller and 3 times faster, and no check earned a bug anywhere; Mo's real differentiators (capability supply chain, the runtime surface, hot reload, time-travel debugging, recipes) were not exercised by logstat and jobq, so **Mo is being tested on the wrong programs**; program 7 must depend on them. "Ruby's look with Go's discipline": what is left after forbidding chaining, blocks, and metaprogramming is Elixir's look with static types; own it. Compile speed is measured on a tiny corpus; at 5,000 files with cross-module inference and capability flow it is unproven, and it is the assumption the agent-loop pitch rests on. The Fable, Robert, and Opus-worker process is a research finding in itself and could be a first-class artifact.
>
> **The strategic fork.** (1) Mo is a language whose thesis is that agents write better code with the compiler as teacher; round 6 is a partial disconfirmation and two more rounds on capability-shaped programs are owed. (2) Mo is a runtime and process model that happens to have a language attached: the failure model, capabilities, the recipe registry, the runtime surface, hot reload, time-travel; its competitor is the BEAM, not Go with contracts. The wiki publicly frames (1) and privately builds (2); make the switch explicit.
>
> **Small things.** A machine-parseable `verified:` line. Document `test rejects` as "prove this contract is reachable and trips". The `never` over a `var` copy is a language bug; fix it before any feature. Formalize the numbered-directions extension of the LLM-wiki pattern as its own artifact.
>
> **Bottom line.** Mo is a serious project executed with more rigor than 95% of language work. Capabilities, the failure model, and the runtime surface are novel and defensible. The shape laws and the keyword grammar are the weakest part and what the control runs punish. The founding premise is not yet proven and round 6 gives real evidence against it in the small; the stronger pitch, an agent-native runtime with a language shaped to expose it, is untested because the programs that exercise it have not been run. Keep the wiki, the decision log, and the failed rounds.

## Related
- [[outside-review-2026-09-14-response]]
- [[outside-review-2026-09-13]]
- [[control-run-6]]
- [[decision-log]]

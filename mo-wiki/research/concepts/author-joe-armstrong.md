---
title: "Author: Joe Armstrong (Erlang)"
created: 2026-09-13
updated: 2026-09-17
type: concept
tags: [research, processes, errors]
sources: [raw/research-runs/2026-09-13-authors-the-elders.pplx.md]
confidence: high
---

# Author: Joe Armstrong (Erlang)

Armstrong's thesis is the specification Mo's process and failure model is derived from. It also contains the two requirements Mo has not answered: live code upgrade and stable storage.

## Ethos in his own words

"The central problem addressed by this thesis is the problem of constructing reliable systems from programs which may themselves contain errors." ([PhD thesis, 2003](https://erlang.org/download/armstrong_thesis_2003.pdf))

"The essential problem that must be solved in making a fault-tolerant software system is therefore that of fault-isolation." ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf))

"Each independent activity should be performed in a completely isolated process. Such processes should share no data, and only communicate by message passing." ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf))

"The structure of the program should exactly follow the structure of the problem." ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf))

The four slogans: "Let some other process do the error recovery." / "If you can't do what you want to do, die." / "Let it crash." / "Do not program defensively." ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf))

"errors occur when the programmer doesn't know what to do." ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf))

"You cannot build a fault-tolerant system if you only have one computer." ([A History of Erlang, HOPL III 2007](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf))

"Language features that were not used were removed." ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf))

## Defining decisions

Six requirements as the runtime's specification: "R1. Concurrency", "R2. Error encapsulation — Errors occurring in one process must not be able to damage other processes in the system", "R3. Fault detection", "R4. Fault identification — We should be able to identify why an exception occurred", "R5. Code upgrade — there should exist mechanisms to change code as it is executing, and without stopping the system", "R6. Stable storage — we need to store data in a manner which survives a system crash." ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf))

Handle errors remotely, for conceptual integrity. "This, combined with the extreme case of hardware error, and the failure of entire processors, leads to the idea of handling errors, not where they occurred, but at some other place in the system," because "For reasons of conceptual integrity we want one uniform mechanism." ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf))

Workers and supervisors as distinct roles. "One process, the worker process, does the job. Another process, the supervisor process. observes the worker," giving "a clean separation of issues. The processes that are supposed to do things (the workers) do not have to worry about error handling." ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf)) Productised as supervision trees: "the job of a node in the supervision tree is to monitor its children and restart them in the event of failure." ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf))

No sharing, and pay for it. "we rejected any ideas of sharing resources between processes because of the difficulties of error handling," and "In order to make systems reliable, we have to accept the extra cost of copying data between processes and always making sure that the processes have enough data to continue by themselves if other processes crash." ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf))

Dynamic typing, and failed retrofits. "Phil Wadler and Simon Marlow worked on a type system for over a year and the results were published," then "The results of the project were somewhat disappointing," and "Several other projects to type check Erlang also failed to produce results that could be put into production." The partial win was Dialyzer: "any types it does infer are guaranteed to be correct." ([A History of Erlang](https://www.labouseur.com/courses/erlang/history-of-erlang-armstrong.pdf))

Question modules themselves. "The basic idea is - do away with modules - all functions have unique distinct names - all functions have (lots of) meta data - all functions go into a global (searchable) Key-value database," because "It's very difficult to decide which module to put an individual function in." ([erlang-questions, 24 May 2011](http://erlang.org/pipermail/erlang-questions/2011-May/058768.html))

## Where he contradicts Mo

Mo keeps files with a 500-line law, re-imposing the placement problem he rejected. Mo bets on static types where Erlang's record says retrofits are hard. Mo's bounded mailboxes with deadlines depart from his stated property that "Message passing is assumed to be unreliable with no guarantee of delivery" ([Thesis](https://erlang.org/download/armstrong_thesis_2003.pdf)). And R6 stable storage, a named requirement at the same level as isolation, is unanswered in Mo — which settles the supervisor-as-storage dispute against Mo.

Source gap: no primary verbatim transcript of "The Mess We're In" (Strange Loop 2014) was reachable, so nothing is quoted from it: n.a.

## What Mo could take

| idea | maps to | status |
|---|---|---|
| R6 stable storage as a named requirement with its own protocol | [[state-model]] | contradicts Mo |
| R5 live code upgrade: state explicitly that Mo declines it, and why | [[d19-negative-space-is-the-contract]] | new idea for Mo |
| "Enough data to continue by themselves" as the restart-state rule | [[d14-processes-are-the-only-identity]] | strengthens Mo |
| Dialyzer's rule: report only what is certainly an error | [[q09-compiler-diagnostics]] | strengthens Mo |
| Functions, not files, as the unit of identity and review | [[d29-edit-by-declaration-id]] | already in Mo |
| The four error slogans as written law | [[d18-two-kinds-of-failure]] | already in Mo |

17 Sep 2026: the R6 row is answered — chapter 3's failure model names what a restart loses and when a reply is durable (ruled 13 Sep, [[research-agenda-2026-09-response]]). The "500-line law" above was struck: the shape laws are project settings, not laws. And the BEAM comparison he is owed has run: [[control-run-10]] and the [[erosion-round]].

## Related

- [[d18-two-kinds-of-failure]]
- [[d08-beam-qualities-without-the-beam]]
- [[d33-bounded-mailboxes]]
- [[elixir]]
- [[prompts-research-agenda-2026-09]]
- [[reliability-and-testing-philosophies]]
- [[author-tony-hoare]]
- [[d42-elixir-round]]
- [[research-agenda-2026-09-response]]
- [[control-run-10]]

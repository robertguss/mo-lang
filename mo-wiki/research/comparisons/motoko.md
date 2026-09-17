---
title: "Mo vs Motoko"
created: 2026-09-12
updated: 2026-09-17
type: comparison
tags: [research, processes, agents]
sources: [raw/research-runs/emerging_languages_2022_2026.md, raw/articles/motoko-actors-async.md, raw/articles/icp-inter-canister-calls.md, raw/articles/motoko-upgrade-compatibility.md, raw/articles/motoko-changelog.md, raw/articles/motoko-github-repo.md, raw/articles/caffeine-how-it-works.md, raw/articles/venturebeat-caffeine-launch.md, raw/articles/motoko-book-async.md, raw/articles/motoko-docs-home.md]
confidence: medium
---

# Mo vs Motoko

**One line:** a 1.x actor language whose makers say it was designed for AI agents to write. On the list as a follow-up from [[landscape-second-lane]], because it pairs [[d14-processes-are-the-only-identity|direction 14]] (isolated actors) with [[d01-agents-write-the-code|direction 1]] (agents as authors).

## What it is (status as of Sep 2026)

Motoko is the language for Internet Computer "canisters", now maintained at `caffeinelabs/motoko`. That repository was created in 2018 and has 588 stars.[133] 1.0.0 is dated 11 December 2025 in the changelog, and the latest repository release is 1.16.0 (9 September 2026), per Robert's emerging-languages run.[127] The saved changelog excerpt confirms steady 2026 releases, for example 1.9.0 on 2 June.[132] Robert's run quotes the docs home calling Motoko "designed for AI agents building backends".[127] The docs-home copy Claude fetched is shorter and lacks that line.[128] The AI framing is clearest at Caffeine, DFINITY's app builder. Caffeine calls Motoko "the first language designed specifically for AI-built apps" and says users "never interact with Motoko directly".[134]

## The ideas, one by one

- **Actors are the unit, and only immutable data crosses.** Actors "are isolated and communicate solely through message passing". Arguments and results of `shared` functions must be *shared types*, which are immutable, "to prevent shared mutable state from being introduced via messaging".[129] An actor runs its messages "sequentially, meaning one after the other and never in parallel".[136]
  - *Mo today:* processes are the only identity, and each handles one message at a time through `update` ([[d14-processes-are-the-only-identity|direction 14]], [[p10-process|pick 10]]).
  - *Verdict:* **already have.** Motoko is a second shipping precedent, after Erlang ([[elixir]]).

- **A trap reverts the message: commit points.** "If an atomic shared function traps during execution, it has no visible effect. Any state changes are reverted, and messages sent are revoked." Commit points are returning, `throw`, and every `await`.[129] So "a trap will only revoke changes made since the last commit point … All preceding effects will have been committed and cannot be undone."[129]
  ```motoko
  public shared func pay() : async () {
    balance -= 10;      // tentative
    await ledger.log(); // commit point: the line above is now permanent
    assert ok();        // a trap here reverts only what came after the await
  };
  ```
  (Illustrative, following the documented rules.)
  - *Mo today:* a crash restarts the process ([[d18-two-kinds-of-failure|direction 18]]). [[verse]] proposes that `update` should discard state writes and queued effects on a crash.

  Answered since (17 Sep 2026): built — steps 4 and 18.
  - *Verdict:* **steal as evidence.** A production platform already reverts state *and* revokes sends per message. **But** in Motoko every suspension is a commit point, which bears directly on Mo's direct-style calls (⚠️ below).

- **Clean and non-clean rejects.** A failed call returns either a *clean* reject, meaning "the callee never executed the method. Safe to retry", or a *non-clean* reject, meaning "may or may not have executed. Use idempotent APIs". Calls can have a bounded wait with a timeout.[130] `try`/`catch` exists only for these messaging errors, and only in async code.[136]
  - *Mo today:* `ask … within:` returns `Result`, with `Timeout` as rain ([[q07-process-api|Q7]], [[d17-mandatory-deadlines|direction 17]]).
  - *Verdict:* **steal** the distinction. A timeout means "outcome unknown", not "didn't happen", and the error type should say which.

- **State that survives upgrades, with checks.** Actor variables are `stable` by default and persist across upgrades. "Motoko rejects incompatible changes of stable declarations", and `dfx` also checks statically.[131] Caffeine runs a data-loss check before every deploy: "If it could, the update is rejected and the AI rewrites it."[134] Migrations are written in two passes, and the framework refuses code "that could delete information unless explicitly instructed".[135]
  - *Mo today:* process `state` blocks ([[p10-process|pick 10]]), with nothing said about changing them across versions. A human is pulled in when the shape changes ([[d20-human-pulled-in-when-shape-changes|direction 20]]).
  - *Verdict:* **open.** It fits Mo: a destructive change to a `state` block is a shape change.

- **Per-sender message order.** Messages to one destination "will be executed in the order you sent them". Messages to different actors, and replies, have no order guarantee.[136]
  - *Mo today:* [[q07-process-api|Q7]] doesn't state an ordering guarantee.
  - *Verdict:* **steal** the explicit statement.

- **"Designed for AI agents" as a platform claim.** Caffeine describes a team of AI agents writing Motoko that users never see.[134] VentureBeat reports the data-loss guarantees are "technically grounded" but "remain to be tested at scale".[135] Claude's reading: the language predates the framing (repo from 2018),[133] and the AI-specific parts are the upgrade checks and the platform, not the syntax.
  - *Mo today:* humans read at spec altitude ([[d02-spec-altitude|direction 2]]). Caffeine hides the language from humans entirely.
  - *Verdict:* **reject** hiding the language. **Note** that the strongest real product in this space bets on guarantees about persistent data.

## What it gives up

- **Platform independence.** Motoko is built around Internet Computer canisters; call attributes include cycles, the network's metered compute.[129] Mo stays platform-neutral ([[q11-platform-and-stdlib|Q11]]).
- **Whole-function atomicity.** Every `await` commits, so a handler that awaits can end half-done.[129]
- **Control over inbound order.** "You have no control over the order in which incoming messages are executed."[136]

## Evidence

- **Release cadence:** 1.0 in Dec 2025, 1.16 in Sep 2026.[127][132]
- **Product traction:** Caffeine's alpha had a 26% daily-active rate, from "a self-selected group of early adopters".[135]
- **LLM success on Motoko:** no benchmark found.

## What Mo should take from this

- **Evidence for [[verse]]'s proposal** (discard a crashed `update`'s state writes and queued effects): Motoko ships exactly that per message.[129]
- ⚠️ **Tension between [[d16-direct-style-io|direction 16]] (direct-style I/O that suspends) and whole-`update` rollback.** In Motoko each suspension is a commit point, so a trap undoes only the work since the last `await`.[129] If `ask` or an effectful call inside `update` suspends, Mo must either commit there (as Motoko does) or buffer the whole message until it ends. Not resolved here.

  Answered since (17 Sep 2026): chapter 3's failure model answers it (`spec/design-v0/03-semantics.md`).
- **Proposal:** `ask` errors separate "never ran" from "outcome unknown", following the clean/non-clean reject distinction.[130]
- **Question for Robert:** is a destructive change to a process's `state` block a shape change that needs a migration and a human ([[d20-human-pulled-in-when-shape-changes|direction 20]])? Motoko and Caffeine reject such upgrades by default.[131][134]
- **Question for Robert:** when an `ask`'s target process crashes, does the caller get rain (Motoko's reject)? And is that consistent with [[d18-two-kinds-of-failure|direction 18]], given the bug stays the callee's?[130][136]

  Answered since (17 Sep 2026): chapter 3 answers it — a restart clears the mailbox and reruns the state initializers (`spec/design-v0/03-semantics.md`).
- **Proposal:** [[q07-process-api|Q7]] states the ordering guarantee: in send order per sender, none across senders.[136]

## Related
- [[language-landscape]]
- [[landscape-second-lane]]
- [[d14-processes-are-the-only-identity]]
- [[d01-agents-write-the-code]]
- [[q07-process-api]]
- [[verse]]
- [[elixir]]

## Sources

[127] raw/research-runs/emerging_languages_2022_2026.md — Robert's research run: Emerging Programming Languages 2022–2026 (Perplexity, landscape prompt 1)
[128] https://docs.internetcomputer.org/motoko/home — Motoko documentation home
[129] https://docs.internetcomputer.org/languages/motoko/fundamentals/actors/actors-async — Motoko: Actors & async data
[130] https://docs.internetcomputer.org/guides/canister-calls/inter-canister-calls — ICP: Inter-canister calls
[131] https://docs.internetcomputer.org/languages/motoko/fundamentals/actors/compatibility — Motoko: Verifying upgrade compatibility
[132] https://docs.internetcomputer.org/languages/motoko/reference/changelog — Motoko changelog
[133] https://github.com/caffeinelabs/motoko — caffeinelabs/motoko repository
[134] https://help.caffeine.ai/hc/en-us/articles/46899814439700-How-Caffeine-Works — How Caffeine Works (Caffeine help centre)
[135] https://venturebeat.com/technology/dfinity-launches-caffeine-an-ai-platform-that-builds-production-apps-from — Dfinity launches Caffeine (VentureBeat, Oct 2025)
[136] https://motoko-book.dev/advanced-concepts/async-programming.html — Motoko Book: Async programming

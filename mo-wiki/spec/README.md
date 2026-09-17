# spec/

The artifacts a human reads, kept apart from the wiki's reasoning pages. Nothing here is a wiki page in the linter's sense: no frontmatter, no index entry; a wikilink names one by its stem. Rewritten 17 Sep 2026 to match what exists.

- `design-v0/` — the design in ten chapters plus a readme (`00-readme.md` lists them): the premise, the laws, the semantics with the failure model and the runtime surface, the syntax, the three verification tiers, packages as bricks, kits, and recipes, the toolchain, the interpreter milestone and every open bet, the standard library table, and chapter 10, the language after the rounds. Each chapter is amended with dated notes at its foot; the chapters hold the result, the wiki holds the reasoning.
- `grammar.md` — the formal grammar, with session 5's decisions at its foot.
- `errors.md` — the diagnostic catalog, one entry per code (`MO0412`): what, why, and the fix.
- `programs/` — the spec altitude of each program on the menu, written for a worker to implement without further design help: `01-job-queue.md` and its changes `01b` to `01f` (the maintenance and erosion rounds, one change per generation), the log analyzer, the kv store, the web backend, the agent harness, the ledger. Each names the round that ran it.

The laws have no separate file: they are chapter 2, and their numbers are the diagnostic codes in `errors.md`.

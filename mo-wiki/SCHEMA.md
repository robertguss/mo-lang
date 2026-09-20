# Mo Lang Wiki — Schema

Read this first, every session. Then `index.md`, then the last ten entries of `log.md`. Only then touch anything.

## Domain

The design of **Mo**, a from-scratch programming language for the AI era, co-designed by Robert Guss and Claude. This vault is the single record of the design: what we like, what is asked, what is decided, what we researched, and what happened in each session. It replaces the two Notion pages that held sessions 1–2 (exported verbatim into `raw/notion/`).

This repo is a monorepo (Robert, session 3). The wiki lives in `mo-wiki/`, which is the Obsidian vault root and the only thing Obsidian syncs. The spec (`mo-wiki/spec/`: design-v0, grammar, error catalog) is prose humans read, so it lives inside the vault as an artifact folder, like `raw/`. Code lives beside the vault and never inside it: `examples/` (the Mo corpus), `toolchain/` (Zig). Wiki pages may cite `spec/` and `examples/`; nothing outside `mo-wiki/` links to a wiki page. Worker sessions get a folder as their write scope (`examples/`, `toolchain/`) and never write to `mo-wiki/`, with one exception each: a worker's one wiki write is the stdlib table it extends (`spec/design-v0/09-stdlib.md`), and the Hermes research lane writes only under `mo-wiki/`, on its own branch, through a PR the lead reads before merging (17 Sep 2026).

## Layout

```
README.md            front door for humans (repo root)
HANDOFF.md           the prompt that starts the next session (repo root, nothing else)
CHANGELOG.md         what shipped, per session (repo root)

audit/               the auditor's charter, the ratified stopping rules, its readings (mo-audit-<date>-<subject>.md), Fable's parallel readings (fable-reading-<date>-<subject>.md), and evidence/<date>/ bundles of raw pointers and outputs (not wiki pages)
examples/            the Mo program corpus (not wiki pages)
toolchain/           the Zig compiler, runtime, platforms, benchmarks (later)

mo-wiki/                the Obsidian vault root; everything below is relative to it
  SCHEMA.md          this file
  index.md           every wiki page, one line each, by section
  log.md             append-only action log
  directions/        one page per "direction we like" (d01–d43, numbered, never renumbered)
  questions/         one page per question for Robert (q01–q18), answer in frontmatter
  decisions/         decision-log.md (every choice, in order, with status) + one page per locked decision at the v0 lock
  syntax/            the 16 syntax picks (p01–p16) + the example programs
  deep-dives/        long-form explorations of one topic
  plans/             roadmap and other plans
  sessions/          one page per design session
  research/          comparisons/, concepts/, languages/ (and prompts/) — pages backed by reading
  maps/              maps of content, one per subject, living
  state-of-the-project.md   the lead's standing account, rewritten at every pause
  raw/               immutable sources: notion/ exports, articles/, papers/, research-runs/
  spec/              artifacts humans read: design-v0/, grammar.md, laws, error catalog (not wiki pages)
  tools/             lint.py, exa.py and other vault tooling
```

Wiki pages are the `.md` files in `mo-wiki/{directions,questions,decisions,syntax,deep-dives,plans,sessions,research,maps}` and the root's `state-of-the-project.md`. Everything else is either raw, an artifact, or tooling. A wikilink may still name an artifact under `spec/` by its stem, or `index`, `log`, `SCHEMA`, or `HANDOFF`; the linter resolves those and checks nothing else about them (17 Sep 2026).

## Page types

| type | lives in | what it is |
|---|---|---|
| `direction` | directions/ | an idea Robert reacted well to; not a decision. Numbered `dNN`. |
| `question` | questions/ | something needing Robert's call. Options + recommendation + why + answer. Numbered `qNN`. |
| `decision` | decisions/ | a locked rule with rationale and a "reopen if". Numbered `DNN`. |
| `syntax-pick` | syntax/ | one syntax choice Robert made, with the snippet. Numbered `pNN`. |
| `example` | syntax/ | a complete Mo program in the current style |
| `deep-dive` | deep-dives/ | full reasoning on one topic, with options weighed |
| `plan` | plans/ | a sequence of steps we intend to follow |
| `session` | sessions/ | what happened in one sitting, chronological |
| `comparison` | research/comparisons/ | Mo held against one other language or system |
| `concept` | research/concepts/ | a researched topic (e.g. supply-chain attacks 2025–26) |
| `research` | research/languages/ | a language's history and what Mo takes from it, from the plang history run (13 Sep 2026) |
| `map` | maps/ | a map of content: one topic, the pages behind it, in reading order; living, rewritten as pages land (16 Sep 2026) |
| `synthesis` | the wiki root | a standing account across the whole project (`state-of-the-project`), rewritten at every pause (16 Sep 2026) |

## Frontmatter (required on every wiki page)

```yaml
---
title: "Direction 13: Local var with mutable value semantics"
created: 2026-09-12
updated: 2026-09-12
type: direction            # from the table above
tags: [state, syntax]      # from the taxonomy below only
sources: [raw/notion/design-journal-2026-09-12.md]
# type-specific:
number: 13                 # direction, question, syntax-pick, decision
status: liked              # direction: liked | locked | dropped
status: pending            # question: pending | answered | withdrawn
answer: in                 # question: pending | in | no | counter
origin: "Robert"           # direction: who it came from
# optional quality signals:
confidence: high | medium | low
contested: true
contradictions: [other-page-slug]
---
```

Every page starts with `# Title` matching the frontmatter title, then body, then a `## Related` list. Minimum two outbound `[[wikilinks]]` per page.

## Tag taxonomy

Add a tag here before using it. Keep it under 30.

- **Philosophy:** `philosophy`, `laws`, `meta`, `roadmap`
- **Language:** `syntax`, `types`, `state`, `effects`, `processes`, `errors`, `contracts`, `negative-space`
- **Verification & tooling:** `verification`, `compiler`, `tooling`, `runtime`, `performance`
- **Ecosystem:** `stdlib`, `security`, `agents`
- **Research:** `research`, `history`, `languages`
- **Maps and the state page (16 Sep 2026):** `thesis`, `programs`, `corpus`, `process`

## Conventions

- File names: lowercase, hyphens. Numbered pages keep their prefix forever (`d13-…`, `q08-…`, `p05-…`); a renumbering is a lie about history.
- Numbers are stable, so text may refer to "direction 13" or "Q8"; always also link: `[[d13-local-var-and-inout|direction 13]]`.
- Code is shown in fenced blocks with the `ruby` hint (closest highlighter to Mo's look).
- Robert's words are quoted as his; Claude's recommendations are marked as recommendations. Never blur who said what.
- Readable prose: short paragraphs, narrow tables (three columns max), snippets under 20 lines. This is about Robert reading comfortably, nothing more.
- `updated:` is bumped on every edit. `created:` never changes.
- **Provenance:** a claim that comes from a specific raw source gets `^[raw/...]` at the end of the paragraph when the page draws on 3+ sources; single-source pages rely on `sources:`.
- `raw/` is immutable. Corrections go on wiki pages. Each raw file carries `source_url`, `exported`/`ingested`, and a `sha256` of its body so drift is detectable.

## How the design work flows through the vault

1. **An idea Robert reacts well to** → new `directions/dNN-slug.md`, `status: liked`, and a line in `index.md`.
2. **Something needing his call** → new `questions/qNN-slug.md` with options, recommendation, why, and `answer: pending`. Robert answers in chat (or by editing the page). Claude sets `answer:` and `status:`, appends the settled details under a `## Answer` heading.
3. **A long unpack** → `deep-dives/slug.md`, linked from the direction or question it serves.
4. **Research** is a two-lane job. Claude does web research and saves sources to `raw/articles/` or `raw/papers/` with frontmatter. Robert runs deep-research tools of his own: Claude writes the prompts (short, one topic each, filed in `research/prompts/`), Robert runs them and drops the results in `raw/research-runs/<date>-<topic>.md`. Both lanes must include academic papers (arXiv, conference proceedings), not only blog posts. Findings are synthesized into `research/concepts/` or `research/comparisons/` pages that cite the raw files.
5. **The v0 lock** → each locked rule becomes `decisions/DNN-slug.md` with `reopen if:`; the source direction gets `status: locked` and a link. History is never rewritten.
6. **Every session** → from session 7 on, the session's record is its `CHANGELOG.md` section and its `log.md` entry, and `state-of-the-project.md` carries the narrative; the `sessions/` pages stop at session 6 (17 Sep 2026). Before that: `sessions/session-NN.md` written at the end (what happened, what is next), the root `HANDOFF.md` rewritten to hold only the next session's prompt, `log.md` appended, `CHANGELOG.md` gets its entry.
7. **Every decision, Robert's or Claude's** → a row in `decisions/decision-log.md` at the checkpoint it was made, with who, status, and what first tests it (Robert, session 5: the log must show how things change over time). The status column reads `provisional`, `locked`, `overturned`, `accepted` (a step or round taken as read), `decided` or `recommended` (the lead's call, standing), `for Robert` (awaiting his eye), `open`, `recorded`, or `—` (a plain record); a status changes by a later row, never by an edit (17 Sep 2026). Status changes are appended, never rewritten.

## Working agreements with Robert (non-negotiable)

1. **One question at a time.** Never ask two.
2. **Exploration mode.** Nothing is formally decided; capture things he likes as directions. Formal locking happens later in one sitting (→ `decisions/`).
3. **Show code, don't describe.** Options as short code, a recommendation, the why, then one question. Be concise; define any PL-design term in ≤3 lines before using it — he is a strong SWE but new to the vocabulary, and he skips long essays.
4. "Unpack this" / "ELI5" → deeper, still in tight bullets with a snippet.
5. Fresh **web research** over training data when a topic calls for it; two lanes — Claude writes prompts into `research/prompts/`, Robert runs them (Perplexity) into `raw/research-runs/`; papers required.
6. **Nothing is final until measured** (direction 28).
7. **Lead and workers** (Robert, 19 Sep 2026, evening): Astra leads in OMP in
   the existing lead pane. Workers use OMP with GPT Sol at high reasoning;
   every assignment gets a fresh clean session, including saved-WIP
   continuations. No resumed, forked or imported worker conversations.
   `mo-lead` owns launch and acceptance. At most three workers, each in its
   own Herdr tab. Workers own implementation and code; the lead owns briefs,
   review, documentation and decisions and may run independent builds/tests.
   Implementation and lead verification use separate worktrees; read-only
   review may share the lead checkout. Preserve bounded write scopes and
   historical work. Robert authorized resuming the server part A and step 42
   after recording this workflow; use `HANDOFF.md` for the current queue.
8. **The lead decides** (Robert, session 5; Astra succeeds Fable): the lead's
   recommendation is the decision within approved scope, recorded as a
   decision-log row with who, status, and first tested by. Robert reviews the
   log, not the queue. Overturning is cheap and expected. Scope and evidence
   requirements still apply; use the latest authorization
   recorded in `HANDOFF.md` rather than a superseded pause.
9. **Frame every report** (Robert, session 5, evening): each report on a worker's result says where that work sits in the whole, in a sentence or two: what phase it belongs to, what it unblocks, and what is left, against the "Where we are" table on `plans/roadmap.md`, which is updated at every acceptance.
10. **Tools** (Robert, 14 Sep 2026, morning): Fable and the workers install or download whatever tool a step needs, without asking, with the package managers on the machine: Homebrew, `mise`, `uv`, `go install`. A Python project is made with `uv init` and everything it needs goes into its virtual environment, its checkers included (`uv add --dev mypy ruff`, run as `uv run mypy`); nothing Python is installed globally or as a `uv tool` (Robert, 14 Sep 2026, afternoon). Record what was installed in the decision log.
12. **The auditor** (Robert, 17 Sep 2026): a Perplexity session only he opens reads raw evidence cold and files `audit/mo-audit-<date>-<subject>.md`; three stopping rules under `audit/` are ratified and change only by a decision-log row with a reason. The lead writes its reading of a subject as a decision-log row or `audit/fable-reading-<date>-<subject>.md` before it opens the auditor's file on that subject, files a disagreement as a row citing both, never opens an audit session, never reads or writes a hidden suite the auditor seals, and leaves raw pointers and outputs under `audit/evidence/<date>/` so an audit session can read the repo cold. Since 17 Sep evening the exchange is automated (PR #3, `audit/WORKFLOW.md`): the lead publishes `ready` records under `audit/handoffs/` on `main`, the auditor's intake polls hourly and answers by pull request, Robert tells the lead when it has (no poller on the lead's side, his choice), the lead runs `fable_poll.py check` and integrates; Robert gets outcome summaries. The whole loop: `plans/the-audit-workflow.md`.
11. Notion is retired for this project (it was his work workspace). Never write Mo content there. The old pages are exported in `raw/notion/`; deleting them is his call.

## Robert's taste (learned the hard way)

- Ruby is his favorite language. Mo must be as simple and elegant as Ruby/Python: borrow what he likes, keep out what he doesn't. Hates OOP and classes. Loves Elixir/BEAM, Go, Rust qualities, Elm. Wants a single static binary and a fast compiler (Rust's slowness is the anti-pattern). Cares a lot about supply-chain security and a Go-like stdlib.
- Rejected on sight: Rust/Gleam braces; `def`/`end`; `end` label comments; `.with(...)`; `->` case arms; `::` module paths; 40-line function limit (70 it is); phone-fit as a design criterion. **Phones are not a thing in this project** (Robert, session 3, firmly): never justify a language, spec, or tooling choice by mobile reading; he only mentions his phone when prose is hard to read there.
- Chose: `fn name(arg: Type) : Ret ... end`, bare `x = ...` immutable bindings with `var`, `case v ... Pattern: expr ... end`, `module Payments.Refund`, `state.count = 0` inside `update`, `try` prefix, predicate `?` methods.

## Checkpoints

Claude updates the vault at natural checkpoints (a question answered, a topic closed), not after every message. A checkpoint is: edit pages → bump `updated:` → update `index.md` if pages were added → append one `log.md` entry → commit.

## Update policy on conflict

When something new contradicts an existing page: keep both with dates, mark `contested: true` and `contradictions: [slug]` on both, and surface it to Robert. Directions can contradict each other; that is exactly what the lint pass is for. Nothing is silently overwritten.

## Lint

`python3 mo-wiki/tools/lint.py` (from the repo root) checks: broken wikilinks, orphans, index completeness, required frontmatter, tags in taxonomy, raw sha256 drift, contested/low-confidence pages, pages over 200 lines, log size. Run it at the end of every session and record the result in `log.md`.

## Search

`qmd` is installed and `mo-wiki/` is a collection named `mo-lang`. `qmd query "..."` for hybrid search, `qmd search "..."` for keyword. Run `qmd update && qmd embed` after a session adds pages.

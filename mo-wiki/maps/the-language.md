---
title: "The language"
created: 2026-09-16
updated: 2026-09-16
type: map
tags: [syntax, laws]
status: living
---

# The language

A map of content for layer 3: what Mo looks like, why, what the compiler enforces, and what the rounds say should change. The spec chapters are the result; the directions, questions, and syntax picks are the reasoning.

## The spec

- [[00-readme]] — the eight chapters in twenty minutes
- [[02-laws]] — shape, bounding, honesty, and contract laws; the formatter
- [[04-syntax]] — the whole surface with the refund module as the thread
- [[05-verification]] — the three tiers and the `verified:` line
- [[09-stdlib]] — the standard library table
- [[grammar]] and [[errors]] — the grammar, and the diagnostic catalog `zig build errors` generates
- [[10-language-after-the-rounds]] — chapter 10: six candidate changes with the round row behind each, code options, and what was decided

## The taste

- [[d27-simple-and-elegant-like-ruby]], [[d07-elixir-flavored-functional]], [[d06-never-oop]], [[d10-immutable-by-default]], [[d11-statically-typed]], [[d13-local-var-and-inout]], [[d26-developer-and-agent-happiness]]
- [[syntax-overview]], [[base-example]], [[full-example-q1-q7]], [[draft-example-ruby-shaped]]
- The picks: [[p01-blocks-keyword-end]], [[p02-definition-line]], [[p03-bindings]], [[p04-conditionals]], [[p05-pattern-matching]], [[p06-results-and-propagation]], [[p07-types-struct-enum-refinement]], [[p08-contracts]], [[p09-module-header-and-never]], [[p10-process]], [[p11-loops-and-anonymous-functions]], [[p12-tests]], [[p13-capabilities-and-logging]], [[p14-modules]], [[p15-methods-traits-generics]], [[p16-one-line-if-value]]

## The laws, and what they cost

- [[d04-style-rules-become-laws]], [[d19-negative-space-is-the-contract]], [[d31-effects-never-hide-in-a-value]], [[d17-mandatory-deadlines]], [[d18-two-kinds-of-failure]]
- [[q12-law-numbers]], [[q04-integer-types-and-overflow]], [[q05-option-and-no-nil]], [[q06-verified-line]], [[q09-compiler-diagnostics]]
- Where the laws met agents: [[control-run-6]] (three laws removed), [[interpreter-step-27]] (the removals), [[control-run-8]] (the six-parameter law costing a loop, the `never` false positive), [[control-run-9]] (first-fix rates per diagnostic)

## The questions still open

- [[q01-comments]], [[q02-strings-and-interpolation]], [[q03-numbers-and-units]], [[q10-semantic-ids-and-editing]], [[q15-the-name]], [[q16-escape-hatch]]
- [[d29-edit-by-declaration-id]] and [[id-addressed-editing]] — editing by id, not by text
- [[d22-rust-plus-refinements-types]] and [[d32-proving-is-a-separate-tool]] — refinements and `mo prove`

## The comparisons

- [[plang-mo-synthesis]], [[plang-decision-matrix]], [[plang-design-camps]], [[plang-implementation-menu]], [[steal-list]], [[tiger-style-and-power-of-ten]]
- The history: [[plang-history-lambda-to-1970s]], [[plang-history-1980s-to-2000s]], [[plang-history-2010-to-2026]], [[plang-history-2026-09-index]]
- [[research/README]] — the surveys of other languages

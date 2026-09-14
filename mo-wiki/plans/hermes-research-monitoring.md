---
title: "Hermes research monitoring"
created: 2026-09-14
updated: 2026-09-14
type: plan
tags: [research, runtime, verification, security]
sources: []
---

# Hermes research monitoring

Hermes maintains an independent research lane alongside the implementation lead. This plan defines research operations, not language decisions or measured Mo improvements.

## Cadence

- Daily scan at 06:00 America/New_York, including daylight-saving changes.
- Monday synthesis at 08:00 America/New_York, disclosing the actual observation window and missing runs.
- Short daily notifications; a quiet day is valid, not a reason to manufacture recommendations.

## Questions and evidence

Begin with runtime reliability versus Elixir/BEAM: supervision, overload and bounded mailboxes, cancellation/deadlines, durability and replay. Preserve the null hypothesis that BEAM already supplies enough of the value.

Also monitor capabilities and recipes (authority propagation, conformance, upgrades and maintenance cost), and verification/agent tooling (contracts, invariants, defect detection and feedback latency).

Each pass reads current project decisions first, searches primary papers and original engineering sources, deduplicates against saved evidence, and closely reads the most relevant results. Social posts are discovery leads rather than sufficient evidence. Quiet discovery periods can advance existing reading questions.

For each material finding record the source and version, what was actually read, methods and limits, implications for the current Mo design, contrary evidence, and a falsifiable test or justified no-change recommendation. Distinguish reported results from independently reproduced measurements. Attribute research judgments to Hermes.

## Persistence and review

Use this wiki, not a competing knowledge base. Preserve raw evidence with the schema's URL, ingestion date and body hash; synthesize into existing research concept/comparison pages where appropriate. Add dated daily and weekly research notes under research/concepts with required frontmatter and related links. Maintain index and append-only log. Preserve contested evidence and existing history.

Work in an isolated research checkout on a dedicated research branch. Commit explicit research/wiki paths and publish a reviewable PR against main; never auto-merge. No implementation, language decisions, experiments, build-worker control, or changes to the implementation lead's handoff/roadmap are part of this lane.

Run the wiki linter and report new issues separately from the existing baseline. If upstream changes conflict, stop publication and report the conflict rather than resolving design disagreements automatically. Do not publish credentials or private operational/account details.

## Related

- [[d08-beam-qualities-without-the-beam]]
- [[d28-nothing-final-until-measured]]
- [[d34-packages-are-recipes]]

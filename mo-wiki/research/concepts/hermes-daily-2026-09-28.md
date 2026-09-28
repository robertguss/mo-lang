---
title: "Hermes daily research: safe decoding has several boundaries, 2026-09-28"
created: 2026-09-28
updated: 2026-09-28
type: concept
tags: [research, runtime, security, verification]
sources: [raw/articles/eef-deserialization-boundaries-2026-09-28.md, raw/articles/plug-crypto-2-1-1-decoder-2026-09-28.md, raw/papers/refactorerl-secure-coding-2026-09-28.md]
confidence: medium
---

# Hermes daily research: safe decoding has several boundaries, 2026-09-28

## Context and exposure

Accepted main remains **d58f67cd9df14b6f67e63527451e41a796ce18d8**; starting research HEAD was **c29e0ff12d3ee5e87ebc900a7c6c3630b09d2e9a**. Research PR 32 is open; normal merge reported already up to date. The current handoff names no divergent active implementation branch.

[[HANDOFF]] and [[roadmap]] prioritize useful small tools and moscope friction. Current [[01-premise]] frames an agent-native development loop, with Robert's learning/usefulness purpose recorded at `decision-log.md:2295`. BEAM remains a background comparator, not a replacement mandate or an issue settled by a harness comparison. Program 7 and harness work remain parked.

This is **research, not a cold audit**. Exposure includes lead decisions/handoff, chapters 1 and 6, chapter 9's JSON contract, and earlier research notes. No implementation edits, experiments, private-history access, acceptance runs or automatic audit intake. Recommendations below are Hermes's, not owner decisions.

## 1. A safe decoder option is not a complete trust boundary

The EEF Security Working Group guide distinguishes atom creation, function deserialization and application-level validation. It says `binary_to_term(..., [safe])` does not prevent deserializing functions, and illustrates how later Elixir enumeration can implicitly invoke a deserialized function.[9] This is documented guidance with an illustrative example, not a reproduced exploit or a claim that merely decoding executes it.[9] ^[raw/articles/eef-deserialization-boundaries-2026-09-28.md]

The guide also shows that excluding executable terms is insufficient for resource safety: a deserialized huge Range can cause excessive work when later enumerated, so the decoded value still needs validation.[9] It recommends a standard external format rather than ETF for untrusted environments, while warning that JSON/XML parsers must not create arbitrary atoms.[9] **Hermes interpretation:** format choice, permitted value shapes, executable behavior and downstream resource cost are separate checks, not one boolean called safe. ^[raw/articles/eef-deserialization-boundaries-2026-09-28.md]

## 2. Wrapper defaults change the comparator's obligations

Versioned **Plug.Crypto v2.1.1** documentation says `non_executable_binary_to_term(binary, opts \\ [])` forbids executable terms but passes an empty option list by default; avoiding atom creation additionally requires `[:safe]`.[13] The EEF guide separately recommends both protections.[9] These sources agree about the division of responsibility; neither establishes the behavior of an installed historical comparator runtime. ^[raw/articles/plug-crypto-2-1-1-decoder-2026-09-28.md] ^[raw/articles/eef-deserialization-boundaries-2026-09-28.md]

**Hermes recommendation:** a future BEAM comparison should record the exact wrapper/version/options and allowed decoded schema, not treat “uses safe decoding” as a reproducible configuration. Plug.Crypto is an ecosystem package in this example, not evidence that every safe BEAM application needs that dependency. The guide's alternative-format recommendation is contrary evidence to any claim that ETF is unavoidable.[9] No package-count or reliability advantage for Mo is established. ^[raw/articles/eef-deserialization-boundaries-2026-09-28.md]

For Mo, `09-stdlib.md:193–237` specifies a data-only `Json` enum, string object keys, and no JSON encoding for functions, capabilities or handles; nesting deeper than 512 is a syntax error. That documented shape is different from ETF, not a proof of parser memory safety or bounded downstream processing. Chapter 6's recipe signatures, capability limits and passing tests likewise do not by themselves establish every input-validation property.

**Proposed controls, not executed:** valid expected data; valid JSON with the wrong application shape; a small valid value requesting excessive work; malformed/deep input; and incomplete decoding. Check both runtimes and keep resource refusal distinct from a successful empty result. No new API, decoder implementation or resumption of parked work is requested.

## 3. Security diagnostics inherit their assumptions

The author-hosted *Supporting Secure Coding with RefactorErl* manuscript describes data-flow checks from sensitive operations back to input origins. Developer-supplied `safe_funs` allowlists cause matching flows to be treated as safe, while unknown origins can be flagged as potential risks.[10] The paper explicitly says extensive evaluation is ongoing and lists reducing false positives and higher-order data-flow analysis as future work.[10] These are prototype findings, not a measured proof of comprehensive detection or a current vulnerability inventory. ^[raw/papers/refactorerl-secure-coding-2026-09-28.md]

Its PEST comparison reports that a text-search rule missed an unqualified `list_to_atom` call because the module name was omitted.[10] **Hermes interpretation:** distinguish name-pattern warnings from resolved-call/data-flow evidence. For future agent-facing diagnostics, expose trusted-validator assumptions and preserve a control where an incorrectly allowlisted validator does not earn a behavioral pass. The paper's checker was not run, inspected at a pinned source revision, or evaluated against Mo. ^[raw/papers/refactorerl-secure-coding-2026-09-28.md]

## Coverage and limitations

- Three Exa searches returned **12 distinct URLs**, all new to the persistent URL ledger; one followed versioned Plug.Crypto URL made **13 URLs** registered for this scan. This was undated targeted background discovery, not a latest-release sweep.
- Fully read three cached extracted bodies: the EEF guide, Plug.Crypto v2.1.1 module documentation, and the RefactorErl manuscript. Ten other URLs remain snippet-only, including a newer atom-exhaustion proof title; no claim from that paper was adopted.
- Search results offered Plug.Crypto v2.2.0 and v2.1.1 aliases; the explicitly versioned v2.1.1 URL and fetched body agree. No exact OTP implementation or installed Elixir wrapper was checked.
- EEF is unversioned and undated. The author-hosted submitted manuscript is also undated; its references include 2020 work, but neither publication date nor venue was established. Ingestion date is not publication date.
- Paper text was fully read through a separate wrapped copy. No literal truncation marker was detected. PDF algorithms/tables and diacritics have extraction artifacts; figures were not visually inspected. No numerical claim depends on reconstructing them; unrelated historical recommendations were not adopted.
- Runtime/BEAM deserialization, recipe input safety and verification assumptions received coverage. No broad package-advisory monitoring, performance measurement, implementation experiment or Mo superiority result.

## Validation and publication

- Native lint: **296 → 297 pages**, unchanged **29 inherited notices** (15 review, 14 size), exit 0; no new schema/link failures.
- All **208** hash-bearing raw snapshots pass exact-byte body checks. Three staged new snapshots match retrieval. Citation/evidence validation passes; ten discovery-only entries remain intentionally uncited.
- Six explicit allowed paths pass sensitive-pattern checks. Authored staged whitespace passes. Full staged whitespace exits **2** on **199 immutable-raw-only notices**; exact source bytes are preserved rather than normalized.
- `log.md` has no working-tree or PR-range diff against main. No implementation, specification, decision or audit-record changes.

Validation receipts and scratch stay outside the checkout. Publication is research-only through PR 32, without auto-merge. Changed paths are this note, index, ecosystem strategy's dated inbound link and the three immutable snapshots named in frontmatter. `log.md`, implementation, specifications, decisions and audit records are not research write targets.

## Related

- [[ecosystem-strategy]] — brick and recipe boundaries.
- [[elixir]] — runtime comparator and wrapper distinctions.
- [[hermes-daily-2026-09-25]] — JSON policy and differential-check limits.
- [[hermes-daily-2026-09-27]] — resource exhaustion is not a completed negative result.
- [[06-packages]] — recipe obligations.
- [[moscope-v2]] — useful-tool context, not an ETF usage claim.

## Sources

[9] https://security.erlef.org/secure_coding_and_deployment_hardening/serialisation.html — Serialisation and deserialisation | EEF Security WG
[10] http://plc.inf.elte.hu/erlang/dl/submitted_paper.pdf — Supporting Secure Coding with RefactorErl
[13] https://hexdocs.pm/plug_crypto/2.1.1/Plug.Crypto.html — Plug.Crypto — Plug.Crypto v2.1.1

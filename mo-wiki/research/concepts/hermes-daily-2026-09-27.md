---
title: "Hermes daily research: search budgets are not negative results, 2026-09-27"
created: 2026-09-27
updated: 2026-09-27
type: concept
tags: [research, runtime, security, verification]
sources: [raw/articles/otp-28-re-resource-errors-2026-09-27.md, raw/articles/re2-readme-2026-09-27.md, raw/papers/davis-redos-2018-2026-09-27.md]
confidence: medium
---

# Hermes daily research: search budgets are not negative results, 2026-09-27

## Context and exposure

Accepted main remains **d58f67cd9df14b6f67e63527451e41a796ce18d8**; starting research HEAD was **79a0ce4e435787328b1ca932f8047f7b7d029002**. PR 32 is open and normal merge reports already up to date. The current handoff names no divergent active implementation branch. Remote `moscope/real-data-v2` is still **eff64c56d9198ff7734c0b19d3ce59d998734903**, incorporated into main.

[[HANDOFF]] and [[roadmap]] prioritize useful small tools and moscope friction. The current agent-native [[01-premise]] and Robert's learning/usefulness purpose (`decision-log.md:2295`) govern this reading. The BEAM comparison is background, not a replacement mandate or a question settled by a harness comparator. Program 7 and harness work remain parked.

This is **research, not a cold audit**. Exposure includes lead decisions/handoff, chapters 1 and 6, chapter 9's rules/string rows, and prior research notes. No private histories, experiments, implementation edits, acceptance runs or automatic audit intake. Recommendations below are Hermes's, not owner decisions.

## 1. A bounded search can stop without establishing absence

The fetched **OTP 28.5.0.5 / stdlib 7.3.0.1** `re:run/3` documentation says exceeded match limits are reported as `nomatch` unless `report_errors` is supplied; that option distinguishes matching-limit errors and compilation errors.[1] This is a documented API behavior, not a newly reproduced defect.[1] ^[raw/articles/otp-28-re-resource-errors-2026-09-27.md]

The same manual separately says `run/3` yields control to the Erlang process scheduler at intervals regardless of the match-limit option.[1] **Hermes interpretation:** scheduler responsiveness, total work consumed, and whether a negative result is conclusive are distinct properties. A future BEAM comparator should retain explicit resource-error outcomes rather than treating every `nomatch` as completed evidence of absence. This does not establish the behavior of Elixir's `Regex` wrapper.[1] ^[raw/articles/otp-28-re-resource-errors-2026-09-27.md]

**Documentation limitation:** the introduction says OTP 28 switched to PCRE2, while the later limit descriptions retain PCRE/pcre_exec wording; the earlier resource-limit overview says an error is returned without mentioning `report_errors`.[1] Use the more specific `run/3` return contract for the claim above, but do not promote the retained implementation prose or its sample transcript into exact-version execution evidence. No installed runtime or wrapper was checked. ^[raw/articles/otp-28-re-resource-errors-2026-09-27.md]

**Hermes recommendation:** retain a distinct incomplete/resource-exhausted outcome in any future search or verification API. Proposed controls are an ordinary match, an ordinary completed miss, an invalid pattern, and a deliberately exhausted budget. The latter must not be counted as a verified miss. These are proposed controls, not tests run today; this is not a claim that moscope uses regex or has this bug.

## 2. RE2-style matching is a tradeoff, not a drop-in promise

RE2's retrieved README states linear matching time in input length, configurable memory budgets for parsing/compilation/execution, and no recursive stack use; it also warns that complex expressions increase constant factors and that it is not fastest in every circumstance.[2] It excludes backreferences and look-around assertions.[2] ^[raw/articles/re2-readme-2026-09-27.md]

The same README says RE2 does not normalize Unicode, and building it requires C++17 and Abseil.[2] These are documentation claims from an **unpinned main-branch cached snapshot**, not an inspected implementation, dependency audit or performance measurement.[2] ^[raw/articles/re2-readme-2026-09-27.md]

[[ecosystem-strategy]] already proposes “RE2-style” only when a program asks; `09-stdlib.md:3–5,36–55` exposes current string operations, not a regex API. Chapter 6 lists regex among intended bricks, not evidence of a shipped row. **Hermes recommendation:** keep this as background rather than expanding the implementation queue. If a workload later needs regex, agree the supported syntax, normalization policy, compilation/matching budgets and exhaustion result before choosing an engine. “RE2-style” describes a design choice; importing RE2 carries its own implementation/dependency obligations. Capability authority and computational cost should be reviewed separately.

## 3. Resource safety needs evidence beyond a pattern-shape warning

Davis et al.'s **ESEC/FSE 2018** study extracted static patterns from cloneable npm/PyPI repositories, used detectors to propose problematic inputs, and dynamically validated them in the corresponding JavaScript/Python engines.[6] It excluded dynamic patterns, bounded detector resources, and explicitly did **not** establish exploitability or attacker-input reachability for every flagged use.[6] Thus its historical incidence is not a present-day vulnerability count.[6] ^[raw/papers/davis-redos-2018-2026-09-27.md]

Their anti-pattern tests found many false positives, while most detected super-linear patterns had polynomial rather than exponential growth.[6] Their repair review also found that changing the pattern or imposing a length cap could leave the resource problem unresolved.[6] **Hermes interpretation:** do not certify a recipe as resource-safe merely because an agent removed a suspicious pattern shape or added an arbitrary input cap. A future authorized check should cover valid long inputs, adversarial near-misses, explicit exhaustion and semantic preservation after repair. No paper harness or Mo test was executed. ^[raw/papers/davis-redos-2018-2026-09-27.md]

## Coverage and limitations

- Three Exa discovery requests returned **9 distinct URLs**, none previously in the URL ledger. The targeted OTP request returned one result; the other two returned four each. No date filter: this is new background reading for the wiki, not a release-news claim.
- Three cached bodies preserved with immutable exact-byte hashes. Fully read the RE2 README and paper's extracted text. OTP reading was limited to its introduction, resource-limit overview, and `run/3` through limit/error options; most regex syntax/reference material remains unread.
- The paper was read through a separate wrapped copy. No literal truncation marker was detected in captured bodies; PDF layout interleaves some text/tables and damages glyphs. No figures were visually checked; no numerical inference depends on reconstructing those tables.
- Runtime/BEAM, resource-safe matching and verification received targeted discovery. Recipe relevance is computational-cost evidence, not a separate capability-mechanism or ecosystem-advisory sweep. Six other URLs remain snippet-only, including an unreviewed RE2 pull request; its reported bug/fix is not adopted as fact.
- OTP title/body versions agree, but series docs are not the installed historical comparator. RE2 has no pinned commit here. No comparative reliability, speed, memory, dependency-reduction or Mo-superiority result.

## Validation and publication

- Native lint: **295 → 296 pages**, unchanged **29 inherited notices** (15 review, 14 size), exit 0; no new schema/link failures.
- All **205** hash-bearing raw snapshots pass exact-byte body checks. The three staged new snapshots match retrieved bodies. Citation/evidence validation passes; six discovery-only entries remain intentionally uncited.
- Six explicit allowed paths pass sensitive-pattern checks. Authored staged whitespace passes. Full staged whitespace exits **2** on **126 immutable-raw-only notices**; source bytes are preserved rather than normalized.
- `log.md` has no working-tree or PR-range diff against main. Publication is confined to research PR 32, with no auto-merge. Changed paths: this note, index, ecosystem strategy's dated inbound link, and the three raw snapshots named above. Implementation, specs, decisions and audit records are untouched; scratch and receipts remain outside the checkout.

## Related

- [[ecosystem-strategy]] — deferred regex-brick context.
- [[elixir]] — runtime comparator and wrapper distinctions.
- [[hermes-daily-2026-09-25]] — preserving errors rather than flattening results.
- [[hermes-daily-2026-09-26]] — Unicode policy and provenance.
- [[06-packages]] — recipe and brick obligations.
- [[moscope-v2]] — useful-tool context, not a regex implementation claim.

## Sources

[1] https://www.erlang.org/docs/28/apps/stdlib/re.html — re — OTP 28.5.0.5 (stdlib 7.3.0.1)
[2] https://github.com/google/re2/blob/main/README.md — README.md
[6] https://davisjam.github.io/files/publications/DavisCoghlanServantLee-EcosystemREDOS-ESECFSE18.pdf — An Empirical Study at the Ecosystem Scale

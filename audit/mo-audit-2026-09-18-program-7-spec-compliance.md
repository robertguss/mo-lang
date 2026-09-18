# Audit reading: program 7 specification and hidden-suite readiness

**Date:** 2026-09-18  
**Author:** Mo Auditor (independent model session)  
**Charter:** raw-evidence review; only Robert may amend or reject the reading.  
**Scope:** independent compliance/readiness review of the sealed program-7 spec against the ratified runtime/capabilities rules; **not hidden-suite authoring** and not a program-7 result.  
**Status:** filed independently before lead synthesis; review cut `64982b23b1dfed0bd0af3430125589da43058ac0`, baseline `aace4ee36516c9dc67cdb7b0d0c8cab3a5f9c024`. The ready record pins `4176bd3f2161afdcdcff7cca5ca2fc0b44368af7`.  
**Explicit gap in this reading:** no hidden cases/seeds, concrete P4 modification, private sealing artifacts, runnable program-7 fault rig or final implementation were authored or validated here. Robert's recent-changes review is not substituted for the separate pre-implementation sealing session. The ready request remains outstanding.

## Reading

The spec names enough behavioral surfaces to permit most requested adversarial tests, but **“spec sealed” is not “hidden suites ready” or permission to skip the pre-build gates**. There are unresolved specification ambiguities and a material P4 dependency-target gap. No S-A/S-B/S-C or T-A/T-B/T-C outcome can be assigned before program results exist.

The exact record `audit/handoffs/program-7-spec/program-7-spec-ready-001.json:8–14` asks the auditor to author ≥50 defects, a ten-shape R3 probe, ten P3 abuse shapes, three P2a seeds, five P2c seeds, and a named P4 modification, keep them sealed from Fable, and return readiness. It explicitly requests no verdict. This file is instead Robert's separately authorized broad-review reading. Its neutral filing record must not be interpreted as a suite-ready response.

## What the auditor read cold and checked

- Charter/manual/workflow and the runtime/capabilities stopping rules, including their controlling ratification blocks and clarifications; no decision-log contents or parallel reading.
- `mo-wiki/spec/programs/07-redis-subset.md` at the review cut and the exact ready record.
- `mo-wiki/plans/interpreter-step-38.md` as a prerequisite plan, not a completed step; the `Net` requirements in `mo-wiki/spec/design-v0/09-stdlib.md:241–270`.
- `git diff 4176bd3f2161afdcdcff7cca5ca2fc0b44368af7 64982b23b1dfed0bd0af3430125589da43058ac0 -- mo-wiki/spec/programs/07-redis-subset.md` was empty. The actual tool-backed `program7_seal_unchanged: true` is filed in `audit/evidence/2026-09-18/recent-specs/auditor-checks.json`. This confirms the named spec did not drift between those pins, not that the experiment is ready.

## Findings

### P7-1 — Medium: P4's named package-backed modification is not yet secured

The capabilities rule's accepted expansion requires TLS, hashed ACL passwords, and a **named hex-installed component** (`audit/mo-audit-2026-09-17-stopping-rule-capabilities.md:37–39`). Its P4 compares the equivalent functional change behind a dependency against `hex update + audit + integrate` (`:121–136`), not simply arbitrary application edits.

The new page supplies TLS and Argon2id (`07-redis-subset.md:184–203`), and a metrics endpoint as the *likely* P4 landing place (`:207–217`). However the Elixir paragraph only allows `mix`/`hex` and names `argon2_elixir` **or whatever the maintainer picks** for hashes (`:309–314`). No particular metrics package, installed version, update pair or common modification is required. A compliant maintainer can write the text endpoint directly; an eventual label change then need not involve a dependency at all. This does not prove a future P4 run must fail; it means the expanded spec alone has not guaranteed its intended signal.

**Readiness requirement, not a rule amendment:** the independent sealing session must name the actual package-backed target and equivalent functional change in advance, with allowed maintainer-visible information and hidden seed material separated. If the target remains metrics, establish its package-backed Elixir footing before the build rather than inventing a dependency update after seeing the implementation. This review does not choose the modification.

### P7-2 — Medium: persistence rewrite instructions omit non-string expiries

`07-redis-subset.md:175–179` prescribes rewrite representations: strings as `SET ... PXAT`, hashes as one `HSET`, lists as one `RPUSH`, sets as one `SADD`, and streams as `XADD`/`XSETID`. It does not say how expiry is retained for the non-string types, despite supporting generic expiry (`:62–65`) and requiring expiry-for-expiry replay equivalence (`:237–247`). A literal implementation of only the listed non-string rewrite commands would lose their TTLs. The broader invariant forbids that result, so this is a specification gap, **not permission to skip a crash/rewrite/expiry test**.

An independent hidden suite can demand that expiries survive rewrite/restart under the higher-level promise. A clarified encoding rule would remove avoidable maintainer discretion; any sealed-page change must follow its own versioned amendment requirement (`:24–29`). No spec was changed here.

### P7-3 — Medium: protocol resource limits have two incompatible readings

`07-redis-subset.md:117–119` first limits a command to 512 MB, then says the program caps a bulk at 64 MiB and a multibulk at 1,024 elements times that. The latter product does not state whether the earlier total-command cap still applies, how units differ, or what error/close behavior is required when individually legal bulks exceed it. The pre-registered deviations only repeat the per-bulk cap (`:324–325`). The Redis compatibility promise is therefore insufficient as the sole oracle for the aggregate boundary.

Ordinary parser/length-error tests are authorable under `:113–116`; boundary/resource tests need a single aggregate rule and rejection oracle before sealing. Do not launch huge allocations to resolve a wording ambiguity experimentally.

### P7-4 — Medium: skip authority needs a deterministic reconciliation

The suite is declared authoritative where it disagrees with the command set (`07-redis-subset.md:128–131`), while the skip list allows out-of-set commands, unsupported CONFIGs, internal DEBUG behavior and timing assumptions (`:142–152`). The final deviation clause says anything else the suite wants is a failure, not a skip (`:318–326`). Maintainers are assigned the same eventual skip list, which is helpful, but the set is not supplied by this sealed page.

The allowed timing skip class is especially discretionary. Before first implementation commit, record the exact Redis tag/commit and skip names/reasons, show how skips follow the allowed deviations, and use the same list for both sides. Afterward, retain the explicit late-skip count. This is a readiness gate already in the spec, not evidence that any improper skip has occurred.

## Hidden-suite authorability matrix — no cases or seeds disclosed

| Required deliverable | Clauses permitting it | What is still outstanding |
|---|---|---|
| ≥50 runtime defects in the exact 15 crash-consistency / 10 restart / 10 deadline-mailbox / 10 capability / 5 replay composition | Persistence `:165–180`, blocking commands `:75–85`, ACL `:182–194`, nevers `:233–250`, simulation `:276–285`, measurements `:293–303`; composition in runtime rule `:144` with authorship clarification `:36` | Independent authoring, category ledger and private seal; fault/kill control points, clock policy and canonical replay comparison method. Clarify the resource and persistence ambiguities above. |
| Ten R3 wait shapes | Blocking list/stream commands `:75–85`, timeout/cancellation promises `:239–249`; runtime rule `:109–110` | Independent authoring and observable time/cancellation oracles. Timeout 0 is deliberately indefinite but cancellable; do not count that documented client request alone as a runtime-law escape. Mailbox saturation and chained waits need runtime-level arrangements, not only wire requests. |
| Ten P3 capability-abuse shapes | Recipe `needs` declarations `:264–274`, ACL boundaries `:243`, capability rule `:113–136` | Independent malicious-body authoring, manifest/scope oracles and matched Elixir experiment. ACL denial and capability confinement are distinct: ten ACL failures would not replace ten dependency-effect abuse shapes. |
| Three P2a drift seeds | Four named recipe surfaces with contracts/tests `:264–274`; capability rule `:102–106,133–134` | The recipe declarations/contracts must be pinned sufficiently for executable seeds, which must violate contracts without being caught by local tests. No body or seed is authored here. |
| Five P2c regeneration seeds | Same recipe surfaces; P4 endpoint candidate `:214–217` | Sealed spec-change/regeneration protocol and independent seed authoring, not simply five ordinary test failures. |
| Named P4 modification | Metrics candidate `:214–217`, counterpart `:309–314` | Concrete package-backed equivalent change and timing boundary; see P7-1. **Not named by this review.** |

These are clauses permitting tests, not proof a runnable suite has been written. The spec's phrase “at least three non-trivial recipes” (`:264`) imports the rule's full definition: ≥3 exports, ≥5 contracts and ≥50 implementation lines each (`capabilities rule:133`). Four names alone do not establish that gate, and contracts merely written as intent do not clear P2b.

The runtime measurements also require evidence beyond the hidden-defect suite: 100 sequential verification-drift edits, 100 exact replays, an independent ten-fault diagnostic session, matched fault/load rigs, size/boot/dependency data and cost rows. The spec names these (`:287–303`); none was measured here. Ratified R6 has **no token budget**, and R4/R7 are separately scored, not extra Tier-1 rows (`runtime rule:15–38`). No new thresholds are proposed.

## Standing concerns, required next evidence and falsifier

- The separate authoring session must preserve secrecy and establish seal timing before either program's first implementation commit, as the ratified rules require. Public filing of this review neither creates that seal nor releases hidden materials. No hidden artifact was created or published.
- Step 38 is a named prerequisite plan; its required duplex and handshake tests are not replaced by this spec review. No implementation-ready claim is made.
- State/decision-log files are left untouched for parallel-work isolation. Findings remain scoped concerns for integration, not governance edits.
- **Would change this readiness reading:** privately sealed, independently authored artifacts with category/count validation and evidence of pre-build timing; a named package-backed P4 change; resolved boundary/skip oracles and pinned recipe contracts; separate proof of the runtime prerequisites. Public handoffs should expose only readiness metadata, not cases or seeds.
- **Candidate falsifier:** after an actually pre-registered matched build, ≤2 reliability rows clearing triggers S-A; a Mo P3 escape count >1 triggers T-A. The new production-shaped spec makes those questions possible; its existence is not evidence against either falsifier.

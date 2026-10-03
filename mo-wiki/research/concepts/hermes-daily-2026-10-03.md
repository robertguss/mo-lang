---
title: "Daily research 2026-10-03: startup is not recovery readiness"
created: 2026-10-03
updated: 2026-10-03
type: concept
tags: [research, runtime, processes, verification, security]
sources: [raw/articles/elixir-genserver-1-18-4-2026-10-03.md, raw/papers/xu-configuration-errors-osdi-2016-2026-10-03.md]
confidence: medium
---

# Daily research 2026-10-03: startup is not recovery readiness

## Context and decision relevance

Hermes research, not an independent cold audit. Read the lead's handoff,
roadmap, recent decision rows and chapters 1, 3, 5 and 6; relevant exposure
must be disclosed in any later audit. Manual-only audit intake is unchanged.
Mo context is `origin/main` at `3def7d41c9e88d9bef5f64be7e21c838397109e4`;
research started at `eff78b0c687f20fc2c8841d621c7b6f7c0b34c6d` on the open
research PR. Main was already integrated. The current handoff names no active
implementation branch; parked work remains parked, not a queue to restart.

The current goal is useful small tools and learning; the agent-native feedback
loop remains context, not the preserved BEAM-superiority thesis. This is
background reading for future process-based tools and trustworthy verification,
not a new release alert or a moscope defect claim. Yesterday separated work
admission from cancellation; today separates startup acknowledgment from the
conditions a service needs to recover.

## Findings

### 1. An acknowledged start has a specific, limited meaning

Elixir 1.18.4 documents that `GenServer.start_link/3` blocks until `init/1`
returns.[13] Work can be deferred with `{:ok, state, {:continue, arg}}`, which
invokes `handle_continue/2` immediately after entering the loop.[13]
Hermes inference: an acknowledged start is not evidence that this deferred
work has completed; a readiness assertion must identify which work it covers.[13]

There is also an explicit absence case: `init/1` can return `:ignore`, allowing
the rest of a supervision tree to start without that server and without an
immediate restart attempt.[13] The documentation warns that other processes should
not require that ignored server.[13]
**Hermes recommendation:** distinguish “supervisor started,” “required child
present,” and “required initialization complete” in proposed acceptance checks.
Do not score these as one successful-start event.

### 2. A healthy startup does not exercise every recovery setting

Xu et al.'s OSDI 2016 study inspected reliability, availability and serviceability
configuration in HDFS, YARN, HBase, Apache, MySQL and Squid.[10] Its fault examples
include settings used only on failover, logging or other later paths; the RAS
selection is deliberately not a representative sample of all configuration.[10]
PCHECK derives early checkers from code that consumes configuration values,
rather than relying only on declared types or manually written constraints.[10]

The paper separately evaluates 37 newly discovered and 21 historical latent
configuration errors, and then 830 collected configuration files.[10] For the latter
it reports 282 true errors and three false alarms.[10] Many reported errors depend
on the test environment: a setting may be valid on its original host and invalid
on the evaluation host.[10] These are historical author-reported results, not a
current deployment failure rate or a BEAM comparison.[10]

**Hermes recommendation:** when a tool claims recovery readiness, include a
controlled failure that actually invokes its configured recovery path. A clean
startup or restart counter alone should not stand in for that evidence.

### 3. Safe preflight and complete verification are different obligations

PCHECK avoids executing some effects: it substitutes metadata/reachability
checks for file-content/network operations, removes calls with unknown effects,
and cannot emulate paths requiring indeterminate runtime inputs.[10] Its authors
explicitly describe it as neither sound nor complete; valid-but-inadequate
resource/performance settings and corrupt file contents can escape it.[10]
The three reported false alarms arose from missed control dependencies that
caused the checker to emulate execution that would not really occur.[10]

**Hermes synthesis:** a recipe's declared authority and startup preconditions
should not be confused with proof that its recovery will work. Chapter 6's
signature/capability/test conformance and chapter 5's tested-versus-proven
vocabulary are useful places to express that distinction, not permission to
extend the checker in this research lane. A check that refuses a dangerous
probe should report the resulting coverage gap, not certify the skipped effect.

## Suggested controls — not executed or authorized here

- Positive: all required initialization finishes and a representative operation
  succeeds before the readiness receipt is issued.
- Negative: a required child is absent, or deferred setup fails after the start
  acknowledgment; neither case may produce the same readiness verdict.
- Recovery: valid startup settings but unusable recovery configuration; invoke
  the recovery path under a separately approved boundary and require evidence of
  the failure, not only successful restart.
- Verifier: include an unreachable faulty branch and a deliberately skipped
  effect; distinguish false alarm, detected fault and untested obligation.

These are Hermes proposals, not Mo requirements, new defects, implemented
features or measured advantages. No source implementation or runtime was
exercised; no Mo-versus-Elixir performance/reliability conclusion follows.

## Coverage and source limits

- Three Exa queries: versioned Elixir supervision, OTP initialization, and
  primary systems papers on startup/configuration failure testing.
- Twelve distinct discovery URLs; ten new to the local URL ledger. One
  additional versioned GenServer URL was fetched to avoid grounding runtime
  claims in rolling OTP 29 search snippets.
- Two material sources read: the relevant Elixir 1.18.4 callback/start sections,
  and the complete returned OSDI 2016 paper text. Other discovered URLs remain
  discovery-only. Capability/recipe coverage is synthesis of these sources and
  current Mo specs, not a separate capability-literature survey.
- GenServer URL and fetched version heading agree. This is versioned manual
  evidence, not verification of an installed Elixir/OTP pair. No publication
  date is asserted for the manual; the paper predates this ingestion by years.
- Cached Exa text is preserved byte-for-byte with body hashes. Wrapped reading
  copies avoided long-line display truncation; no literal tool truncation
  markers were found. PDF column/table artifacts remain; figures were not
  visually inspected and reported experiments were not reproduced.

## Activity and validation

Added this note and two immutable snapshots; updated the index and the Elixir
comparison's dated follow-up. `log.md`, specs, decisions, implementation and
historical raw evidence remain untouched.

- Native lint: 302 to 303 pages, exit 0; the same 29 inherited notices
  (15 contested/low-confidence review flags and 14 size notices), no new issues.
- All 218 stored raw body hashes match exact bytes after the closing frontmatter
  delimiter. The two staged bodies also match their retrieval captures.
- Citation/evidence verification passes. Unused discovery-only ledger entries
  are expected warnings, not evidence silently credited as read.
- Authored staged whitespace passes. Full staged whitespace exits 2 with 21
  raw-only notices; immutable source bytes were preserved, not normalized.
- Explicit staged-path and sensitive-pattern checks pass; authored diff
  reviewed, raw bytes matched to public captures. No `log.md` diff.
- Publication uses the existing review-only PR #33; remote state is checked
  after pushing, with the receipt retained outside the checkout. No auto-merge.

## Related

- [[elixir]]
- [[hermes-daily-2026-10-02]]
- [[reliability-and-testing-philosophies]]
- [[06-packages]]
- [[05-verification]]

## Sources

[10] https://www.usenix.org/system/files/conference/osdi16/osdi16-xu.pdf — Early Detection of Configuration Errors to Reduce Failure Damage
[13] https://hexdocs.pm/elixir/1.18.4/GenServer.html — GenServer — Elixir v1.18.4

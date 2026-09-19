---
title: "Agent-native research: findings and proposed first trial"
created: 2026-09-18
updated: 2026-09-18
type: concept
tags: [agents, research, verification, tooling, roadmap]
sources:
  [
    raw/research-runs/2026-09-18-agent-native-learning.md,
    raw/research-runs/2026-09-18-agent-native-editing.md,
    raw/research-runs/2026-09-18-agent-native-restrictions.md,
    raw/research-runs/2026-09-18-agent-native-evidence.md,
  ]
confidence: medium
status: discussion
---

# Agent-native research: findings and proposed first trial

## Status and authority

Amp read Robert's four reports, checked selected consequential primary sources,
and consulted the oracle. This is a research synthesis, not an implementation
acceptance or an exhaustive fact-check of the reports. Raw bodies are preserved
unchanged with hashes under `raw/research-runs/`.

Robert agreed to a bounded maintenance task as the first candidate for
discussion. The Agent application's authentication-error policy change is the
lead/oracle proposal below, not a locked task or acceptance specification.
Documentation is authorized. No workers, setup, experiments or implementation
may begin until Robert explicitly approves and the lead confirms readiness.
Program 7 remains suspended under [[01-premise]]; this trial replaces none of
its retained obligations.

Robert also requested independent opinions from multiple models with web access,
possibly without repo access. They may challenge everything, including the need
for a new language/runtime. [[agent-native-independent-review-prompt]] supplies
the same self-contained context; model agreement is not independent proof.

## What the reports support, and what they do not

### Learning: test a small entry point and targeted lookup

The report favors a short introduction plus task- and diagnostic-directed
learning. Retain that as a hypothesis. Its example counts, retrieval sizes,
model-size targets and repair limits are not universal Mo requirements.
^[raw/research-runs/2026-09-18-agent-native-learning.md]

The cited C study reports Qwen 3 4B compilation rising from 18.0% to 97.4%, but
compares one baseline attempt with up to five feedback attempts. Its main
semantic measures are similarity proxies; it examines functionality for three
selected tasks. This does not establish smaller-model behavioral parity in Mo,
nor prove that compiler feedback cannot improve behavior.[1] Measure both.

Use authoritative versioned material already present: the error catalog, prelude
inventory, executable examples and CLI. An index of links may suffice before
adding embeddings or a retrieval service. Never teach invented `moc` commands:
the CLI is `mo`. Cold discovery does not mean forbidding documentation.

### Editing: distinguish targeting, application and behavior

The useful proposal is ordinary source plus targeted semantic help. A correctly
addressed edit can still apply partially or change behavior incorrectly; stable
line hashes, learned patch application and declaration identities are different
mechanisms. Preserve invalid intermediate programs during multi-step changes.
^[raw/research-runs/2026-09-18-agent-native-editing.md]

LSP explicitly permits abort, transactional, undo and text-only transactional
failure handling. Rename can fail on invalid code, but the specification does
not require a fully compiling workspace for every rename.[2] Projectional
editing does not establish total correctness. Reject automatic guessing through
stale or ambiguous edits as a safety argument.

Mo already has narrow `mo fix` operations and `.mo.ids`. The latter preserves
identity while a declaration's name stays the same; renaming creates a new
identity (`toolchain/src/ids.zig`). Do not advertise a rename-stable semantic
editing service as built. Defer a new editing API until observed failures
justify it; keep editing unchanged in the first onboarding comparison.

### Restrictions: assign each guarantee to its actual boundary

The report's useful taxonomy covers errors, authority, concurrency, deadlines,
retries and persistence. Its examples mix agent-authored defects, defects in
agent systems and human incidents; these are not interchangeable evidence about
agent coding. Its runtime-first conclusion is not established across all six.
^[raw/research-runs/2026-09-18-agent-native-restrictions.md]

Compiler acceptance, runtime/library enforcement, native-platform/OS isolation,
the coding agent's permissions and verifier authority are separate boundaries. A
consumed `Result` can still be mishandled. Supervision does not imply durable
recovery, a deadline does not undo a remote action, and actors do not eliminate
distributed races. Price prevention against repair effort and legitimate uses
made harder. Neither adding nor removing a particular law is authorized here.

### Evidence: protect verification, not merely its report

Retain artifact/configuration identity, expected-versus-executed checks, actual
fault observations, attempt accounting and inspection permissions. A signature,
hash or event history cannot establish truthful execution when the implementing
agent controls its producer and the checks being reported.
^[raw/research-runs/2026-09-18-agent-native-evidence.md]

The report calls `--runxfail` a failure-hiding mechanism. pytest documents that
it runs and reports marked tests as unmarked; failing assertions still fail.[3]
Reject adoption of its unsupported universal 80% mutation threshold, three-pass
quarantine rule or blanket retry ban. Predeclared repetitions, repair attempts
and selective rerunning until green require different accounting. A seed alone
does not establish replay of uncontrolled nondeterminism. Keep hidden suites
sealed rather than publishing their contents as evidence.

**Exposure disclosure:** this attachment labels itself an auditor draft. The
lead encountered that label during the supplied research batch, before a new
independent reading was filed. This synthesis is therefore not a cold
independent audit reading. The attachment's E-1–E-8 are unratified proposals,
and its old program-7 framing is superseded; no audit gate changes here.

## Proposed milestone: one independently verified maintenance workflow

**Question:** can a fresh agent use the complete Mo loop to make a bounded
behavioral change, and does a compact version-correct primer plus targeted
lookup improve independently verified completion time or cost?

**Candidate:** `examples/programs/agent`. Its `Agent.Model.tried` retries model
errors while attempts and time remain. Propose a new application policy: after
an HTTP 401 response, make no further request in that call and return the
existing status error. Preserve other retry/deadline behavior. This is a policy
change, not a claim that today's implementation violates its present
specification.

Use a local scripted HTTP endpoint and disposable data. Discover commands and
APIs, reproduce behavior, edit/check, run/inspect, repair, then freeze a
candidate for independent verification. Exercise the interpreter and compiled
binary with contracts enabled. Observe what today's runtime surface actually
exposes; do not invent missing observations or add features mid-trial. No TLS or
crash-durability acceptance claim is in scope. Containment is not acceptance of
those outstanding subsystems.

**Comparison:** current documentation/search versus a small primer plus task-
and diagnostic-directed lookup into the same authoritative material. Keep
editing tools, compiler, application and agent scaffold fixed. Do not include
the solution in the guide. The lead/oracle propose one affordable model and one
stronger reference model as a small pilot; model selection, repetitions,
budgets, ordering and escalation policy remain to be agreed. Broader model
evaluation remains later work. This tests the onboarding package, not each
component's individual effect or general language superiority.

**Verifier:** protected acceptance code, configuration, expected check inventory
and results, outside the implementing agent's write authority. Independently
authored public tests can serve this trial; do not open existing hidden suites.
Cases should distinguish terminal errors, transient-error recovery, exhaustion,
deadlines and success regressions. Guard against a trivial solution that avoids
requests or disables all retries. Before comparative scoring, negative controls
must demonstrate rejection of failed builds/processes, empty/incomplete checks,
timeouts, stale artifacts, deliberately wrong candidates and unrealized faults.
These are proposed trial validity conditions, not new historical audit gates.

**Accounting:** measure discovery through independent verdict, including model
waiting, lookups, tool latency, repair and verification; count all attempts,
failures, tokens, billed cost/compute, human input and frontier assistance.
Record artifact/toolchain/harness/configuration identities and cache conditions.
Separate compilation, behavioral success, regressions and incomplete
verification; separate cheap-model-alone from assisted outcomes. Report every
planned trial, not only successes or best-of-five. A faster but less reliable
result is a tradeoff; noisy results remain inconclusive. No numerical pass
threshold has been adopted. Finishing the study does not require the preferred
approach to win.

Before execution: explicit Robert approval and lead readiness confirmation,
environment/evidence boundary verified, a frozen trial specification, and any
necessary instrument repairs. Neither a documentation commit nor an outside
reviewer's recommendation starts work. See [[roadmap]] and [[decision-log]].

## Sources

[1] https://arxiv.org/html/2601.12146 — Compiler feedback study
[2] https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification — LSP 3.17 specification
[3] https://docs.pytest.org/en/stable/how-to/skipping.html — pytest skip and xfail semantics

## Related

- [[agent-native-independent-review-prompt]]
- [[control-run-9]]
- [[01-premise]]
- [[roadmap]]
- [[decision-log]]

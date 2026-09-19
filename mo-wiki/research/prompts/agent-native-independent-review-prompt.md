---
title: "Mo: independent strategic and technical review prompt"
created: 2026-09-18
updated: 2026-09-18
type: concept
tags: [agents, research, thesis, roadmap, verification]
sources:
  [
    spec/design-v0/01-premise.md,
    spec/design-v0/02-laws.md,
    spec/design-v0/03-semantics.md,
    spec/design-v0/05-verification.md,
    spec/design-v0/06-packages.md,
    plans/control-run-9.md,
    plans/control-run-10.md,
    plans/erosion-round.md,
    research/concepts/agent-native-research-synthesis.md,
    decisions/decision-log.md,
  ]
status: review-brief
---

# Mo: independent strategic and technical review prompt

Copy everything between BEGIN REVIEW PROMPT and END REVIEW PROMPT into a fresh
agent session. No repository access or other attachment is required. Give each
reviewer the same version; withhold other reviewers' responses until its first
assessment is complete. This is an informed strategic review, not a cold
independent audit of raw experimental evidence.

BEGIN REVIEW PROMPT

Packet version: **1.0, 18 September 2026 (US Eastern)**. Source inventory
anchor:
[`986fdc7`](https://github.com/robertguss/mo-lang/commit/986fdc7bc46db62cc8e0a0da73878d635e90213e).
Later discussion decisions are stated explicitly below; no implementation
changed in preparing this packet. Report newer evidence separately rather than
silently substituting it for this snapshot.

## Your assignment: challenge everything

You are an independent technical and strategic reviewer of **Mo**, an
experimental programming language, runtime and toolchain created by Robert Guss
with AI agents. Assess whether its goals are worthwhile, whether its
architecture and current direction are justified, and what should change. **You
may challenge everything, including whether a new language or custom runtime
should exist.** Continuing, narrowing, reusing another runtime, turning the work
into tooling for an existing language, or stopping are all admissible
recommendations. Sunk cost is not justification.

Do not flatter the project, assume novelty, or manufacture criticism for
balance. Explain agreement as carefully as disagreement. Evaluate the strongest
plausible version of Mo and the strongest practical alternatives. Robert likes
Elixir/BEAM and will continue using it; the aspiration is another useful option,
not replacing it or winning every comparison. That preference must not prevent
an honest opportunity-cost assessment.

You have web access. Research decision-changing questions using primary sources,
papers, official documentation and implementations. Cite direct URLs and
dates/versions where relevant; distinguish measured results, design claims and
your inferences. Do not imply you inspected source or ran experiments when you
did not. If links fail, state it and proceed conditionally. Do not require the
repository to begin: the context below is the review packet. Identify missing
evidence precisely rather than filling gaps with favorable or unfavorable
assumptions.

Return analysis and proposed experiments only. Do not implement, deploy, start
workers, open audit sessions, contact maintainers or change project state. Do
not seek out or reproduce hidden acceptance suites. Implementation is paused
pending Robert's explicit approval **and** the lead's readiness agreement. Your
recommendations do not authorize execution.

## 1. Goals, preferences and assumptions—each is open to challenge

**G1 — Agents are the users of code.** The target workflow assumes agents
author, read, maintain and diagnose code. Humans specify outcomes, authority and
acceptable risk, then judge behavior and evidence; human source review is not a
required safety step. This is a product assumption, not an empirical claim that
humans everywhere have stopped coding. Challenge its feasibility and
consequences, particularly who supplies trustworthy requirements and notices a
wrong specification.

**G2 — Reliable outcomes at low total cost.** Make it practical for affordable
models to build and maintain reliable software, not merely compile. Stronger
models may be faster or need fewer repairs, but smaller/cheaper models should
have a useful path to success. Model size, open weights, license, serving cost
and capability are separate axes. Broad parity with frontier models has not been
demonstrated.

**G3 — A fast, trustworthy feedback loop.** Discover → learn → edit → check →
run → inspect → repair → verify. A failure should explain what happened, why,
the relevant language/API rule, what evidence is available, and how to
investigate or repair it. The inspiration is Elm's helpful errors, adapted for
machine consumers. “Instant” is an aspiration: tool latency and time to verified
behavior must both be measured.

**G4 — Learn an unfamiliar language on demand.** Mo has no established training
corpus. The working assumption is that models need version-correct discovery, a
small introduction, examples and task-/error-directed documentation rather than
memorizing a large manual. Prior training exposure cannot be proved absent
merely because a language is new. Both ordinary cold discovery and short-guide
onboarding should be tested.

**G5 — A language with runtime support, not just syntax.** The preferred form is
functional/procedural, statically typed and compiled, with BEAM-inspired
isolation and supervision, explicit authority, bounded waits, structured
failures and inspectability. The question is which parts genuinely require a new
language/runtime and which could be provided by libraries, tools, protocols, a
DSL or a typed frontend over an existing runtime.

**G6 — Reduce supply-chain risk and operational burden.** Favor a useful
first-party library, explicit permissions and easily deployed binaries. The
historical strategy emphasizes no third-party application runtime packages and
generated implementations of shared specifications. Neither “first-party” nor
“generated here” establishes safety; scrutinize maintenance, patch distribution,
assurance and the actual trusted computing base.

**Current prioritization:** improve the complete loop for existing features
before expanding the language, except where a missing capability blocks
representative applications. No wholesale syntax rewrite, particular restriction
removal, TLS replacement or new verification threshold has been approved. These
are current project choices, not constraints on your critique.

## 2. What Mo currently is—not just the ambition

This is an early working research prototype, not a production-ready language or
a mature ecosystem. The following is the lead's source-grounded inventory, **not
your independent verification**. No new full acceptance run was performed while
preparing this brief. Old documentation sometimes mixes implemented behavior,
aspirations and superseded claims; the qualifications here are deliberate.

**Toolchain:** implemented in Zig. Lexing/parsing, a type/capability checker,
bytecode interpreter, formatter, tests and diagnostics exist. The development
interpreter is the reference execution path; release builds emit C and use Zig's
C toolchain, with a C runtime and shared native components. Linux builds can be
static; macOS uses the system library. Maintaining agreement between the
interpreter and compiled runtime is a real cost. There are corpus/differential
checks, not a formal equivalence proof.

**Language:** immutable bindings by default, local mutable values (`var`), sized
integers, structs, data-carrying enums, pattern matching, explicit
function-boundary types, function generics with trait bounds and
implementations, generic built-in containers, contracts/refinements and explicit
`Result`/`Option` handling. No classes or conventional exception-catching. `try`
propagates expected errors. Contract violations, overflow and certain runtime
violations crash a process. Ruby/Elixir-like block syntax was selected partly
for familiarity and the founder's taste; its agent benefit is unproven.
User-defined parameterized structs/enums are not supported.

This small example illustrates the existing syntax, not the whole language:

```ruby
module Tour
fn split(total: UInt32, people: UInt32) : UInt32
  requires people > 0
  total / people
end
test "a bill splits evenly"
  assert split(90, 3) == 30
end
test rejects "a bill for nobody"
  split(90, 0)
end
```

`requires` is checked dynamically on execution; the checker also requires a
corresponding rejection test. That test demonstrates a particular rejection, not
correctness of all callers or proof that the contract expresses the right
requirement. `ensures` checks postconditions and `invariant` constrains process
state. `never` checks prohibited conditions over values recorded during
test/property runs; it is not a continuous production monitor. Static
general-purpose proving (`mo prove`) is not implemented.

**Restrictions worth scrutinizing:** finite collection/range loops rather than
`while`; recursion has a depth bound, not a general termination proof; waiting
effect calls require deadlines; explicit bounded mailboxes; consumed
results/options; exhaustive matching; no implicit nil/numeric conversions;
anonymous functions restricted to call arguments with read-only captures; no
import cycles; unused/rebound bindings rejected; one formatting style.
Diagnostics are errors rather than warnings. Shape limits currently include 70
function-body lines, six parameters, nesting depth three and twelve
process-state fields. These counted limits have already been reclassified
conceptually as project defaults, but configurable project settings remain
outstanding. An earlier file-length limit was removed after it cost repair work.
Do not assume every restriction is indispensable or fully enforced across every
path.

**Processes and failure:** a process owns state and handles typed messages
through an `update`, under a supervisor. Lightweight processes, multicore
scheduling, bounded mailboxes, deadline-bearing calls and restart budgets exist.
Mailbox overflow crashes the sender rather than automatically returning
backpressure. A failed update rolls back local state changes and buffered sends,
**not** file/network effects already performed or another process's completed
work. Timeout means the caller stopped waiting; an action may already have
occurred. Restart does not itself restore durable state: a program must arrange
recovery through storage. A supervisor is not a database transaction manager.
BEAM-inspired does not mean BEAM feature parity, distribution, mature OTP
libraries or proven operational reliability.

**Authority:** capabilities originate at the program's platform/root and are
passed explicitly, with narrowing and restrictions on capture/transfer. Native
platform/stdlib implementations are trusted. Source-level capability checking is
not automatically OS-level confinement, protection against native bugs, or a
sandbox for the external coding agent. Runtime inspection has separate read and
action authority; access to state may expose secrets.

**Feedback and editing:** `mo check --json`, `mo test`, seeded `mo test --sim`,
`mo run`, `mo build`, `mo fmt` and limited `mo fix` operations exist.
Diagnostics have stable codes, explanations, locations and some
machine-applicable fixes. A generated error catalog and a prelude API inventory
exist. `.mo.ids` sidecars record declaration identities/hashes and verification
stamps. Identity persists while a declaration's name stays the same; a rename
creates a new identity. Do not infer a complete rename-stable semantic editing
API. Source remains ordinary text.

**Verification:** unit/rejection/property tests, runtime contracts and seeded
simulation/fault injection exist. Simulation is not a proof and does not control
every external source of nondeterminism; the compiled test path does not
implement seeded simulation. A tool-generated `verified:` line and sidecar
detect stale/manual changes within that mechanism, but are not an independent
attestation against an agent controlling source, sidecars or the runner.
Contract checks are enabled by default, with measurement overrides that
verification must account for. Historical targets of <50 ms incremental checking
and <100 ms per changed-function testing are targets, not established general
performance guarantees.

**Inspection:** an opt-in HTTP/JSON surface can expose processes, state, events,
crashes, sources, memory and slow updates; authorized operations include
send/pause/resume. The runtime retains bounded events and crash reports. A
compiled binary must opt into the surface. Full MCP integration, complete
just-in-time teaching, production snapshot-plus-message-log restore, time-travel
debugging and hot code reload must not be assumed implemented. The proposal is
that protocols expose authoritative services, not that MCP itself supplies
semantics or safety.

**Programs and reuse:** examples include a log analyzer, TCP key-value store,
HTTP notes service, durable job queue, agent harness and payments ledger. They
exercise real features but are not evidence of product-market fit or broad
correctness. A recipe mechanism checks generated implementations against
declared interfaces/contracts and tests. The broader package model proposes
first-party native “bricks,” source-owned first-party kits, and community
recipes containing specifications/tests from which agents generate bodies. A
full registry/security lifecycle is not built. Zig, generated C/runtime code,
native components and OS services remain dependencies/trusted inputs even when
there are zero third-party application packages.

## 3. Evidence that should constrain your judgment

These are **historical project reports**, not freshly reproduced findings or a
controlled cross-language/model ranking. Some runs used different harnesses,
toolchain versions and environments; sample sizes are small. Treat counts of
failing checks separately from counts of underlying defects. Distinguish failure
of a particular generated application from impossibility in a language.

- **Working software and useful feedback:** multiple applications and
  interpreted/compiled corpus checks exist. Some early Mo applications passed
  adversarial suites. A historical job-queue comparison reported a warm Mo
  feedback loop of 0.81 s versus about 7 s for Elixir's combined checks; these
  are particular commands on particular programs, not matched universal latency
  measurements or total authoring time. The same work also reported more Mo
  authoring time and repair loops. Do not select only the favorable column.
- **BEAM counterevidence:** a historical Elixir queue needed no third-party
  runtime package (OTP supplied JSON), recovered service through its supervision
  tree under a process-kill probe, and exceeded the Mo application's throughput
  in that comparison. The contemporary Mo application stopped answering after a
  queue failure; later program/runtime changes addressed parts of that behavior.
  This undermines claims of unique automatic recovery, not the possibility of
  useful Mo tradeoffs. Later durability findings limit cross-platform
  performance comparisons.
- **Small-model counterevidence:** prior maintenance trials used models recorded
  as Kimi, DeepSeek, GPT-5.5, local Qwen and Haiku. Some reached
  compilation/own-test success while missing the required scheduling behavior.
  The Haiku row reported 28 failing Mo checks over four causes, versus 22 Go
  checks over six causes and 18 Python checks over two causes; the principal Mo
  miss was never making a due scheduled job available. These are not
  interchangeable rankings by defect count. A local Qwen run edited nothing in
  all three languages while sessions shared one server, so it cannot establish a
  Mo-specific model floor. Names are historical project labels; independently
  verify provider versions before reasoning about current capabilities.
- **Contracts have not yet earned the strongest claim:** at the generation-six
  checkpoint, the `never`/`invariant` catch ledger recorded zero qualifying
  catches against a previously agreed threshold of two by generation ten. This
  asks whether specified language contracts catch change-induced bugs ordinary
  tests would miss; it does **not** say all typing, checks or contracts are
  useless. Missing requirements remain missing even when a program compiles and
  passes its self-authored tests. Earlier changes also required narrowing
  contract semantics after false positives and measuring runtime costs.
- **Security and durability remain unresolved:** the custom TLS component had
  certificate-validation, protocol and coverage findings. Corrective Step 39
  remains unaccepted. Saved old checkpoints include 27 certificate cases
  accepted when rejection was required and 63/64 abuse cases; later upstream
  edits exist, so these are not current measurements. On macOS, a
  plain-fsync/full-sync mismatch invalidated some speed comparisons;
  directory-sync durability and other readiness obligations remain open. No
  production-security claim follows from earlier green tests.
- **The instruments have failed too:** audit/lead probes found runners returning
  success after failed or timed-out work, empty selections succeeding, failed
  fuzz batches undercounted, and abuse scoring not establishing that the
  intended stimulus/state occurred. These prove instrument defects; they do not
  prove every historical campaign was false-green. Repairs need negative
  controls before reuse. Old evidence and corrections are retained, not silently
  rewritten.

The project uses a lead, implementation workers and a separately invoked
auditor. This is useful separation of roles, not proof of independent judgment:
models may share training data, assumptions, prompts and incentives, and the
lead supplied this packet. Some private worktrees/evidence from an environment
move have not been verified as restored. You cannot audit raw performance or
suite results from this summary alone.

## 4. Program 7 and the direction change

**Program 7 is an experiment/application number, not a compiler version.** It
was planned as `mored`, a Redis-compatible subset with binary RESP, persistence,
authentication/ACLs, TLS, metrics and maintenance changes, compared with an
Elixir counterpart under matched conditions. It was intended to test runtime
reliability, capabilities/recipe claims and costs using pre-registered checks
and an auditor's hidden suites. It has not begun as the planned comparative
build/run.

Robert has suspended its execution and prospectively superseded the requirement
to justify Mo through BEAM superiority and the associated runtime-claim
retirement mapping (historical labels S-A/S-B/S-C). No old gate has been
declared passed. Historical sealed specifications and evidence remain preserved.
Capability/recipe obligations (T-A/T-B/T-C) and the separate generation-ten
contract-catch obligation (R-B) have not been retired; Program 7's execution of
its obligations is suspended. Do not treat the identifiers as enough information
to adjudicate those rules.

A replacement scope, metrics and decision rules must be agreed and versioned
before use. Assess whether this is an appropriate product-goal correction, risks
moving the goalposts, or both. “Another option” removes a universal superiority
requirement, **not** the need for a falsifiable value proposition, minimum
safety requirements or a reason to spend resources here.

## 5. Recent research and current proposals—not established conclusions

Four externally supplied reports addressed unfamiliar-language learning, program
editing, restrictions across runtime concerns, and machine-readable verification
evidence. The lead and an advisory model reviewed them; selected source checks
found overstatements. No raw report or the advisory model's answer is required
to review this packet. Do not treat their agreement as evidence.

**Tentative synthesis:** retain a short versioned primer plus targeted lookup;
ordinary source with narrow semantic help; explicit separation of compiler,
runtime, OS and verifier authority; and independently protected acceptance with
complete attempt accounting. Defer wholesale syntax changes, projectional-only
editing, a broad new semantic-edit API, arbitrary language-rule changes and
elaborate attestation infrastructure until observed needs justify them.

Three useful starting sources—not a closed bibliography:

- https://arxiv.org/html/2601.12146 — compiler-feedback study. It reports Qwen 3
  4B compilation improving from 18.0% to 97.4%, but compares one baseline
  attempt against up to five feedback attempts, relies mainly on similarity
  proxies, and examines functionality for three selected tasks.[1] Verify the
  paper yourself; it neither proves smaller-model Mo parity nor broadly proves
  compiler feedback cannot improve behavior.
- https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/
  — check WorkspaceEdit failure handling and rename. The editing report
  overstates universal atomicity/compilation prerequisites.[2] Structured edits
  are not behavioral proofs.
- https://docs.pytest.org/en/stable/how-to/skipping.html — `--runxfail` ignores
  xfail marking rather than hiding failing assertions.[3] One report
  mischaracterized it. Its proposed universal mutation threshold, retry ban and
  consecutive-pass rule were not adopted.

The evidence report labels itself an auditor draft and was encountered in the
research batch before a new independent reading. That review cannot be called
cold independence. Its proposed evidence requirements are unratified. This is a
process limitation to disclose, not a reason to suppress its useful arguments.

**First milestone under discussion:** a bounded maintenance task in the existing
Agent application. Its model-call implementation retries errors while attempts
and time remain. Proposed new policy: after an HTTP 401 response, issue no more
requests for that call and return the existing status error; preserve other
retry/deadline behavior. This is a new policy, not necessarily a current-spec
defect. Exercise the full
discovery/learning/edit/check/run/inspect/repair/verify loop against a scripted
local HTTP endpoint, under interpreted and compiled execution, with contracts
enabled and protected independent behavioral checks. Do not call it TLS or
durability acceptance.

Compare current documentation/search against a small version-correct primer plus
task-/error-directed lookup, holding editing tools and the rest of the scaffold
fixed. A small pilot with an affordable model and a stronger reference model is
proposed; the larger model campaign remains later work. Measure all planned
attempts from initial discovery to independent verdict, including failures,
tokens, elapsed time, serving cost, human help and stronger-model escalation.
Report standalone and assisted outcomes separately. Repetitions, budgets,
models, exact acceptance cases and escalation policies remain open. The
experiment is not authorized, pre-registered or sealed. Critique whether this
task is too trivial, too narrow, or too unrelated to the runtime thesis to be
the right first test.

## 6. Questions your assessment must answer

**Q1 — Should Mo exist in this form?** What problem is sufficiently important
and insufficiently served to justify a new language/runtime? Compare it fairly
with the best existing-language agent toolkit, a DSL/library, a typed frontend
over a mature runtime, and the current custom approach. Name a plausible initial
workload/user and adoption path. Separate differentiation from novelty, and
identify a realistic case where Mo should not be used.

**Q2 — What belongs where?** For language semantics/types, compiler, application
library, runtime, agent tool protocol, OS sandbox and independent verifier,
assign the responsibilities that matter. Which guarantees cannot be retrofitted
without changing semantics? What is merely a convenient integrated default?
Would an agent-native specification/IR or semantic API offer more than new
source syntax? Include costs of dual runtime maintenance and the boundary
between observable state and secrets.

**Q3 — Are the restrictions helping the intended users?** Select the most
consequential ones rather than commenting mechanically on all of them. For each,
give a realistic prevented mistake, a legitimate task it obstructs, an
alternative, and a discriminating test. Challenge no-warnings, counted limits,
closures, mailbox overflow, error handling, mandatory deadlines, contracts and
replay claims as relevant. Do not equate “cannot ignore a value” with “handles
it correctly.”

**Q4 — What teaches agents fastest without misleading them?** Evaluate the role
of syntax familiarity, a primer, compiler explanations, searchable/versioned API
descriptions, executable examples, semantic edits and future
training/fine-tuning. Optimize useful information and round trips, not tokens or
compiler milliseconds alone. How should tools represent uncertainty, ambiguous
fixes and invalid intermediate programs? Which opportunities are missing from
our proposal?

**Q5 — What replaces human source review?** How are requirements, test oracles
and authority changes governed? What prevents weakening tests/contracts,
fabricating evidence, secret exfiltration, or interpreting “green” too broadly?
Which guarantees are realistic against accidental mistakes versus an adversarial
coding agent? Do not answer “use another model” without explaining its shared
failure modes, authority and independent evidence.

**Q6 — Is the supply-chain/runtime strategy defensible?** Compare first-party
native components, wrapping maintained libraries and generated recipe bodies.
Include vulnerabilities, updates, correlated failures, provenance, maintenance
cost and trust in the compiler/OS. Critique building TLS and the distinction
between no external package and no dependency. Avoid implying recipes' public
tests prove every generated implementation correct.

**Q7 — What should Program 7 become, and when?** Retain, shrink, split, replace
or defer it, with reasons. Propose a falsifiable claim and fair comparator(s),
prerequisites, fault model, behavioral evidence, cost measures and precommitted
decisions for negative/inconclusive results. Identify which old claims remain
unanswered. Do not rewrite historical experiments to support the new
positioning.

**Q8 — Is the proposed first maintenance trial informative?** What can it
establish, what can it not, and what is the cheapest stronger alternative? How
would you prevent a solution that skips all requests, disables retries, changes
the tests or overfits visible cases? Separate measuring a workflow from
attributing causality to language design. Explain how a later realistic workload
would validate transfer.

**Q9 — How should cross-model evaluation work?** Define success at a stated
cost/risk budget, representative tasks, repeated fresh sessions, comparable tool
access, guide/scaffold ablations, serving/concurrency controls, matched resource
budgets, failure accounting and confidence/uncertainty reporting. Separate
larger-model help used to build the ecosystem from help used per task. Consider
novelty/training contamination, model churn, cache effects, tool-call competence
and correlated benchmark overfitting. Do not choose universal model-size, retry
or pass-rate thresholds without justification.

**Q10 — What should happen next, and what should stop?** Give a short
dependency-aware roadmap, not a feature wishlist. Distinguish blocking
correctness/security work from a safely isolated prototype experiment. Identify
neglected opportunities, the largest avoidable investment, and what evidence
would cause you to reverse your recommendation. You may recommend stopping the
project or preserving only part of it.

## 7. Required response format

1. **Verdict:** a concise recommendation (continue, narrow, pivot, pause or
   stop), strongest reason for it, strongest objection to it, and qualitative
   confidence. Do not imply confidence is a calibrated probability unless it is.
2. **Understanding:** restate the goal in your own words; distinguish goals,
   proposed means, assumptions and verified knowledge. Say whether you accessed
   any repository files and which claims you could independently check.
3. **Assessment table:** use G1–G6 and Q1–Q10 as references. Columns: item;
   agree/disagree/uncertain; why; evidence status/source; what would change your
   mind. Combine related rows when useful; no forced balance or invented
   consensus.
4. **Alternatives and ranked actions:** compare credible alternatives on
   equivalent obligations; list the highest-priority keep/change/defer/drop
   recommendations, their costs/risks, and what not to build next. Separate
   constraints you accept from preferences you challenge.
5. **Research/experiment proposals:** at most five decision-changing studies.
   For each specify the hypothesis, competing explanation, minimum setup,
   independent oracle, metrics, confounders, rough resource requirement, and
   distinct actions for positive, negative and inconclusive results. Prioritize
   information gained per unit cost; avoid arbitrary thresholds after seeing
   results.
6. **Program 7 and first-trial recommendation:** address Q7/Q8 explicitly,
   including readiness and preserved historical obligations. Give the most
   important unanswered question to Robert first; list other uncertainties
   without blocking the entire review.
7. **Sources and limits:** direct citations supporting consequential external
   claims, contrary evidence, inaccessible sources, unverified Mo claims, and
   assumptions about budget/team that materially affect your recommendation. If
   your own model/version is not reliably known, say so rather than guessing.

Aim for a rigorous but readable 2,500–4,000 words, extending only when material
evidence requires it. Cover the questions by grouping them rather than repeating
yourself. Write for an experienced software engineer, define specialist terms
briefly, and use concrete failure sequences or examples. Independent judgment is
the deliverable: do not infer a desired answer from the founder's enthusiasm or
from this packet's tentative recommendations.

Optional project entry points, if available:
https://github.com/robertguss/mo-lang and https://robertguss.github.io/mo-lang/
. Current direction is in the opening sections of `HANDOFF.md`,
`mo-wiki/spec/design-v0/01-premise.md`, `mo-wiki/plans/roadmap.md` and
`mo-wiki/state-of-the-project.md`. Public lead results are in
`mo-wiki/plans/control-run-9.md`, `control-run-10.md` and `erosion-round.md`;
`audit/README.md` describes preserved obligations. Source ownership:
`toolchain/src/main.zig`, `ids.zig`, `diag.zig`, `caps.zig`, `sim.zig`,
`surface.zig`, `emit_c.zig`, and `toolchain/runtime/mo_rt.c`. These are optional
corroboration paths, not required reading or permission to access hidden suites.
Historical lower sections and older README prose may contradict the newer
direction; report contradictions instead of silently choosing the most favorable
version.

## Sources

[1] https://arxiv.org/html/2601.12146 — Compiler feedback study
[2] https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification — LSP 3.17 specification
[3] https://docs.pytest.org/en/stable/how-to/skipping.html — pytest skip and xfail semantics

END REVIEW PROMPT

## Related

- [[agent-native-research-synthesis]]
- [[reading-pack-2026-09]]
- [[01-premise]]
- [[roadmap]]

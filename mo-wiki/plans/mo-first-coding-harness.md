---
title: "Mo-first coding harness: bounded first deliverable"
created: 2026-09-18
updated: 2026-09-19
type: plan
tags: [agents, tooling, verification, roadmap]
sources:
  [
    spec/programs/05-agent-harness.md,
    research/concepts/agent-native-research-synthesis.md,
  ]
status: in-progress
---

# Mo-first coding harness: bounded first deliverable

## Orientation

Robert approved the lead/oracle recommendation on 18 Sep 2026: build a small
Mo-first coding harness in Mo, initially maintaining existing Mo applications.
Robert's 19 Sep overnight instruction now authorizes the Astra lead to decide
and drive bounded setup, implementation and verification while he is AFK.
The lead establishes technical readiness and records each slice. This does
not seal an experiment or accept an outstanding audit obligation.

Current worker instruction (19 Sep): keep Astra as lead in this Mac session
and spawn fresh Astra workers at low reasoning in Herdr panes. The former
oracle requirement and Amp worker configuration are superseded. See `mo-lead`
for ownership and verification. The lead/worker model does not select the
harness's reference model.

**Historical relocation instruction, 18 Sep 2026, 11:44 PM ET:** move the Astra lead to Robert's
Mac, where he confirms OrbStack works. Keep orb worker configuration unchanged.
`HANDOFF.md` owns arrival checks. Nine final credential-free executor probes
passed in this orb; the two earlier failed probe runs are also retained at
`audit/evidence/2026-09-18/executor-feasibility/`. This is evidence of a tested
Linux container configuration, not a built Mo executor, protected verdict, Mac
validation or general security certification. Temporary privileged setup was
dismantled and controller changes restored. A dedicated delegated subtree and
bounded output-drain behavior are requirements learned from the probe.

Readiness is scoped by work unit: full model-comparison budgets need not block a
provider-independent fixture runner, but each brief must explicitly name its
prerequisites, bounds and remaining unmet obligations. No implementation or
login is authorized by the completed probe approvals or this relocation.

**Mac inspection, 18 Sep 2026, 11:58 PM ET:** the clean handoff checkout,
native arm64 Zig 0.16.0 and OrbStack Docker endpoint are verified. No named
Linux machine exists; a dedicated executor, Linux checkout/toolchain and
protected verdict remain unverified. The Codex session lacks Amp oracle/thread
tools; Robert's workflow choice is pending. Evidence is at
`audit/evidence/2026-09-18/mac-arrival/`. No setup or implementation had started
at that checkpoint. The 19 Sep Herdr/overnight instructions above resolve the
workflow and start authority.

The useful result is: **task + isolated checkout → candidate patch + independent
behavioral verdict**, with command outcomes, time, usage and failures recorded.
Two questions stay separate: is Mo useful for implementing this developer tool,
and does Mo-specific guidance help the agent change Mo applications reliably?
Neither result by itself proves a new language/runtime is necessary.

Pi is a design reference and the practical baseline, not a feature checklist.
The librarian inspected it; the lead also cloned and read
[revision 36b60d2](https://github.com/earendil-works/pi/tree/36b60d2e8985899743c4cf5bd5f8929832a3f05d/packages/coding-agent).
Borrow its separation of provider integration, agent loop and coding session,
and its read/write/edit/command tool set. Pi explicitly delegates real isolation
to the OS or an external executor; project trust is not containment.

Existing `examples/programs/agent` supplies a custom HTTP model loop, file
tools, budgets and transcripts. It lacks command execution in its tool dispatch;
restart fails interrupted runs rather than resuming them. Reuse selectively,
without assuming the recorded guarantees have been independently accepted.

## Write scope and ownership

The lead chooses each bounded implementation slice under Robert's overnight
authority. Before launch, append an exact path allowlist for each part and
its independent acceptance owner. The designated worker owns future code under
`toolchain/` and `examples/`; the lead owns requirements and acceptance
readings. Do not choose a new worker environment implicitly or assume private
restoration.

During a coding trial, the target agent can change only a disposable application
checkout. Freeze and protect the running harness and its source, compiler,
guide, task requirements, executor policy, and final verification code/results.
The target Agent application may be a separate copy of the harness's ancestor;
editing that copy must not change the harness actually executing the trial.

## Parts, in order after implementation approval

### A. Truthful evidence and bounded execution

First bounded implementation brief: [[mo-executor-foundation]], with exact
worker write scope, isolated-machine setup and lead-owned acceptance controls.

Define a protected external runner that binds a verdict to the exact candidate,
toolchain, configuration and expected check inventory. Development tests in the
writable checkout are feedback, not final authority. Acceptance checks assert
observable behavior independently of the implementation; `verified:` and a
successful compiler exit alone do not establish correctness.

Before scoring agent work, demonstrate rejection of failed builds/processes,
empty or incomplete check selections, timeouts, stale candidate outputs and
known-wrong candidates. Include a control where the requested fault never
occurs: absence of the stimulus is incomplete evidence, not a pass.

A writable checkout alone is not isolation. Select an established OS-isolated
executor with bounded CPU, memory, wall time and output, descendant cleanup,
restricted filesystem/network access and credentials outside the task boundary.
Protect verifier outputs from the target agent and target programs. Do not build
a new sandbox or rely on Mo source capabilities to constrain child processes.

Treat candidate code and commands as potentially malicious, including during
final verification. Execute them inside isolation; keep the authoritative runner
and verdict writer outside that boundary. A negative control must show that
forged success output or an attempted result overwrite cannot produce
acceptance.

### B. One complete coding path

One session, one provider and one reference model; thin headless CLI plus
machine-readable events. Read/search, targeted edits, writes and bounded command
execution must support check → inspect failure → repair. Keep the model/tool
loop separate from provider and execution adapters without a plugin framework.

Supply version-matched Mo documentation, available command help, diagnostics and
existing runtime inspection where useful. Preserve diagnostic detail; do not
invent commands or require an interface redesign before use. Return distinct
success, refusal, failure, timeout and cancellation outcomes, exit status when
available, and explicit output truncation. Do not equate transport success with
tool success. Stop explicitly at step, context, time or usage limits.

Use a narrow trusted adapter for provider HTTPS/auth and external execution
where needed, with maintained TLS and verified certificates. Pin and disclose
that adapter and its dependencies: this is not an end-to-end zero-dependency
claim. Its exact transport, provider and implementation require a readiness
decision.

**Provider candidate identified; readiness incomplete (18 Sep 2026):** Robert
requires independent OpenAI subscription OAuth for the harness. At the Pi pin
above, `packages/ai/src/auth/oauth/openai-codex.ts` implements device and
browser login, and `providers/openai-codex.ts` selects the dedicated
subscription Responses transport. The lead/oracle recommend a pinned `pi-ai`
adapter for authentication and inference only; Mo retains tool dispatch and the
agent loop. Do not invoke the full Pi/Codex agent as a substitute or reuse Amp
credentials.

Prefer device login: forward the real verification link and short-lived code
through an operator-only channel when an authorized flow starts. It avoids the
orb/laptop localhost callback mismatch. If needed, browser fallback must accept
the complete redirect through private input, check the expected callback and
nonempty matching state, and never ask for tokens or redirect URLs in chat.

Keep a harness-specific credential store inaccessible to candidate processes,
not merely outside the checkout; preserve serialized refresh/deletion and atomic
replacement. Pi's default AI credential store is in-memory; its coding-agent
file store is permission-restricted plaintext, not a keychain. Pi login returns
credentials and some upstream errors include raw response bodies: expose only
allowlisted auth status fields, never raw results/errors in transcripts. Local
logout deletes the credential; server-side revocation is not established.

The code demonstrates Pi's use of the Codex OAuth registration and subscription
backend, not blanket authorization for independent client reuse. Resolve client
identity/support expectations, account eligibility, reference-model access and
network/storage policy before live integration. OpenAI's
[authentication guidance](https://developers.openai.com/codex/auth) recommends
API keys for programmatic Codex workflows; that does not establish either a ban
or permission for this personal third-party subscription integration. No login
or entitlement test has occurred. Subscription allowance is not API dollar cost.

Record completed model/tool results before subsequent work. Interrupted runs
fail explicitly; no automatic replay of commands with uncertain outcomes. A
timeout does not prove a command did nothing. Report usage from trusted
provider/executor observations; missing usage remains unknown, not zero. Do not
claim exact billing caps or crash durability without evidence for those claims.

### C. Calibration and useful application tasks

Start with the Agent's terminal-401 policy change as workflow calibration, not a
language-value test. The lead recommends an Agent-specific requirement for the
test copy: after receiving 401, make no further request in that call and return
the status error; preserve other retries and deadlines. The shared recipe
currently promises retries on model errors. Before implementation, version the
new requirement and explicitly resolve its recipe binding; no silent exemption
or shared-recipe rewrite. Approval of this project is not a completed policy
spec.

Independently observe request counts and outcomes for immediate 401, transient
failure followed by 401, transient recovery, exhaustion, deadline and normal
success. Reject solutions that skip all requests or disable all retries. Then
choose two or three bounded fixes/features in existing Mo applications, with
frozen requirements and behavioral checks before model runs. Include a task
exercising failure diagnosis or required progress if appropriate; do not inflate
the first task into a durability or distributed-systems project.

### D. Practical comparison, then affordable-model evaluation

Compare with actual Pi under matched model, task, guidance, available tool
capabilities, budgets and isolation. Pin Pi and document unavoidable differences
in schemas, editing semantics, prompts, context policy and tool integration. The
operator's tools are not automatically tools available to either harness. Match
conditions before interpreting outcomes; no comparison of unlike scaffolds as
proof about language syntax. Do not build a second Elixir harness first.

Calibrate reliability with the reference model, then add one affordable model.
Any stronger-model assistance is a separately recorded treatment. The future
onboarding comparison remains a separate question: use the same guidance in both
harnesses rather than confounding it with this product comparison.

## Numbers and interpretation

Report three separate ledgers: harness correctness, independently accepted task
outcomes, and effort/cost to develop and maintain the harness in Mo. Record all
planned attempts, failures, timeouts, incomplete runs, tokens, available billed
cost, human intervention and stronger-model assistance. Record end-to-end time
and tool/model/verification latency separately, with cache and environment
state.

Before scored runs, freeze task identities, provider/model versions, budgets,
repetitions, ordering and verdict rules. Those numerical limits are unresolved,
not invented in this brief. No 2× threshold, production assurance, or
superiority claim is adopted. A negative result can motivate a repair or
narrower scope; inconclusive evidence stays inconclusive. Neither substitutes
for retained audit obligations. Shared compiler bugs require independent
behavioral checks even when both Pi and the Mo harness agree.

## Done when and readiness

The first implementation is complete only when its controlled negative cases are
rejected, one full coding path produces a correctly bound external verdict, and
cancellation, interruption and limit behavior are exercised. Report failures
honestly; all tasks need not succeed to finish an evaluation. The broader pilot
finishes with its full attempt ledger, not when a preferred outcome appears.

Before a worker brief is ready, the lead must resolve and record:

- Pi provider candidate: resolve registration/support, account/model access and
  maintained TLS/auth adapter contract; permitted network boundary.
- Astra/low Herdr worker configuration is selected; verify executor isolation, resource
  limits, credential separation and protected storage before readiness.
- Exact code write scopes, command/API feasibility and acceptance ownership.
- Versioned first-task policy and recipe relationship, budgets and trial plan.
- Required environment restoration and instrument repairs; any omitted legacy
  obligation explicitly remains unmet rather than being silently waived.

No TUI, dynamic plugins, multi-agent coordination, automatic resume, automatic
compaction, self-modification or compiler changes in the first deliverable.
Unexpected missing runtime support returns to the lead for a bounded decision.
Program 7 stays suspended; this project does not inherit its number, seal or
retirement gates. Step 39 remains unaccepted. Containing the pilot is not
acceptance of Mo TLS, Darwin full-sync or any outstanding durability claim.

## Related

- [[05-agent-harness]]
- [[agent-native-research-synthesis]]
- [[roadmap]]
- [[decision-log]]

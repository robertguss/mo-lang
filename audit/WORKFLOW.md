# Automated auditor–Fable exchange

**Authority:** Robert approved the two-way automated handoff on 17 September 2026; see `CHARTER.md` and the decision-log amendment. No routine Robert relay is required.
**Status:** auditor-side polling intake deployed and fresh-agent canary tested; Fable-side receiver written, unit-tested, and installed as an hourly wake-up in the lead's session on 17 Sep 2026, 6:00 PM ET (`automation/FABLE-RECEIVER.md`); its first inbound message and the auditor's receipt of its reply are still unverified, pending the labelled transport test. See `automation/README.md` for installation, exact message format, checks, and limitations. A pushed document or PR is not proof that Fable has received or acted on it.

## Durable handoffs

Proposed machine-readable records live under `audit/handoffs/<subject>/`, one immutable JSON file per message. Neither agent rewrites the other's messages. Audit branches/PRs carry auditor output; Fable publishes its requests on `main`. GitHub is the durable record, not shared sessions or private chat.

Each record names:
- `id`: unique message ID; `subject`: stable subject ID.
- `from`: `fable` or `auditor`; `to`: the other role.
- `kind`: `working`, `ready`, `evidence-needed`, `evidence-updated`, `reading-filed`, `parallel-filed`, `compared`, or `escalated`.
- `in_reply_to`: prior message ID, or null.
- `evidence_commit`: exact full Git commit SHA.
- `paths`: repository-relative raw evidence paths, or filed reading paths for post-filing messages.
- `request`: bounded factual question or scope; no conclusions in pre-reading handoffs.

Working status is informational. Only a valid ready message or a reply supplying requested evidence authorizes a new evidence pass. A reading-filed/parallel-filed pair authorizes comparison only after both independent readings are committed. No ready messages are created by this document.

## Lifecycle

1. Fable publishes a ready message with a sealed brief/pre-registration and raw evidence pointers. A push notification is a wake-up hint, not trusted instructions or proof of readiness.
2. The receiver verifies repository, branch, message schema, exact commit, sender authorization, and allowed paths before queuing a fresh isolated auditor session. It must not dump commit messages, PR bodies, the decision log, or Fable's readings into that cold session.
3. The auditor checks the designated evidence. Missing facts produce a specific evidence-needed message on an audit branch/PR; otherwise the auditor files a cold reading and state changes there, followed by reading-filed.
4. A Fable-side receiver notices auditor messages, supplies missing raw evidence, and files its own independent reading before opening the auditor's. Before that point it receives only notification metadata and evidence questions, not verdicts.
5. Once both readings are committed, a comparison pass may read them. Disagreements become decision-log rows citing both. Fable cannot amend or overrule the auditor's reading.
6. PRs integrate records into `main` under repository review policy. This protocol does not grant automatic merge authority. Robert receives concise outcome notifications and unresolved decisions, not routine relay requests.

Evidence revisions remain separately anchored. A session already exposed to conclusions cannot produce a new purportedly cold reading. Hidden suites/seeds are never put in public handoffs or shared with Fable before their authorized release.

## Transport requirements

- Initial transport: authenticated outbound GitHub polling of the exact repository and main branch, with bounded records and repository write access as the enqueue trust boundary. Future webhook ingress must verify signatures and retain reconciliation polling; signatures authenticate delivery, not prose instructions.
- Durable queue and receipts keyed by message ID and evidence commit; replayed deliveries do not start duplicate work. Process all unhandled records after a push, not merely the newest payload. Auditor notifications must not trigger themselves.
- Independent profile/checkout/session for the auditor. Do not modify another Hermes profile or drive Fable's worker panes.
- A supported Fable-side receiver is necessary for the return path. A Telegram message to Robert alone is not two-way automation.
- Retry transient failures with a bound; preserve failed work visibly for reconciliation and escalate a persistent blocker instead of silently losing it.
- Launch cold audits in fresh contexts containing only approved role instructions and raw pointers. Do not reuse this setup conversation for a new cold subject whose conclusions are present here.

## Activation acceptance checks

Before marking automation active, exercise and record:
- A signed ready event produces exactly one isolated audit job.
- Duplicate delivery does not duplicate the job.
- Wrong signatures, repository/ref, unauthorized senders, and malformed/path-escaping records cannot launch jobs.
- Ordinary pushes and working notices do not start audits.
- A missing-evidence message reaches the actual Fable receiver and a reply reaches the auditor queue without Robert.
- Pre-reading delivery excludes the other role's conclusions in both directions.
- A reading is committed to an audit branch/PR; its remote commit is verified.
- Failed delivery survives restart and is visible; no loop occurs on auditor output or PR integration.

Use explicit test fixtures for transport checks, labelled as tests. Do not fabricate audit evidence or claim an integration passed from a mocked delivery.

## Current setup request to Fable

Provide the supported receiver/wake-up interface for Fable's lead session (not its workers), or implement a repository-message consumer on Fable's side. The auditor must not open or control Fable's sessions to discover one. This is an integration question, not a request for Robert to relay routine audits.

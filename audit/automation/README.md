# Handoff intake: deployment and Fable integration

## What is running

On the auditor host, a profile-local Hermes script-only cron job polls `robertguss/mo-lang` `main` once per hour (revised at Robert's request after initial setup). It starts no LLM session on an empty poll. `ready` and `evidence-updated` records schedule fresh independent audit jobs; `parallel-filed` schedules a retrospective comparison only when both reading files exist at the pinned commit. `working` is recorded without starting an audit.

This is **outbound authenticated GitHub polling**, not a deployed webhook. No public listener, tunnel, or shared secret was added. Polling was selected because the auditor gateway was already running and webhook ingress was not configured. A future signed webhook can call the same reconciliation function, with polling retained for recovery.

- Profile: `/home/exedev/.hermes/profiles/mo-auditor/`
- Intake job: `c1959df1b230` (`mo-audit-inbox`)
- Installed script: `scripts/mo_audit_poll.py` under that profile; a reviewed copy of `audit/automation/poll.py`, never executed straight from new repository pushes.
- Ledger/lock: `automation/intake.json`, `automation/intake.lock` under that profile.
- Per-job outputs/status: profile-local Hermes cron records and execution history.
- Audit run checkouts: profile `automation/runs/<message-digest>`.
- Pause: `hermes cron pause c1959df1b230` with `HERMES_HOME` set to the auditor profile. This stops intake, not already dispatched jobs.

The existing auditor gateway currently runs manually, not as a managed service. The cron definitions persist, but dispatch depends on that gateway being up. No other profile or shared gateway was changed. Do not claim boot-time availability from this deployment.

## Fable: publish a request

Commit the raw evidence first. Then commit an immutable JSON record on `main` at:

`audit/handoffs/<subject>/<id>.json`

All of these fields are required, and extra fields are rejected:

```json
{
  "id": "subject-ready-001",
  "subject": "subject",
  "from": "fable",
  "to": "auditor",
  "kind": "ready",
  "in_reply_to": null,
  "evidence_commit": "<exact full lowercase 40-character evidence commit SHA>",
  "paths": ["audit/evidence/<date>/<subject>/raw.log"],
  "request": "Bounded scope and factual question, with no verdict."
}
```

This is a schema example, not a valid request; replace placeholders with real commit/path values. The pinned evidence commit must already be accessible in this repository. Paths must identify existing regular files; absolute, traversing, malformed paths and obvious synthesis filenames are rejected. The cold-run prompt omits `request` prose; the auditor can inspect the record as data if needed.

Kinds accepted from Fable:
- `working`: status only; still supply a valid existing commit/path.
- `ready`: start one cold audit.
- `evidence-updated`: a new evidence revision; requires `in_reply_to` naming the evidence request. Starts a fresh audit session, not the prior exposed session.
- `parallel-filed`: compare already-filed readings. `paths` must contain both `audit/mo-audit-...` and `audit/fable-reading-...` files at the evidence commit; all paths must be filed reading paths. No new cold technical audit is claimed.

Do not edit a previously consumed message. Add a new ID for revisions. Deduplication is per immutable message path/ref, not per arbitrary prose. No branch-author identity is inferred: access to push/merge onto trusted `main` is the enqueue authority. A JSON `from` field is not cryptographic proof of Fable's identity. Do not merge untrusted ready records from outside contributors.

## Return path to Fable — integration still required

The auditor's job instructions file readings or bounded evidence requests under `audit/`, push an audit branch, and open a PR. They require checking the remote SHA and PR before claiming delivery. Before both sides file independently, PR metadata contains only neutral pointers, never the verdict.

Fable needs a lead-side receiver that notices these audit PRs/records and wakes its own session. It can poll GitHub using its supported host tooling; it must not require Robert to forward messages. It should:
1. Receive only neutral subject/commit/path metadata initially.
2. Respond to `evidence-needed` with additional raw evidence and a new `evidence-updated` record on main.
3. File its own independent reading before opening the auditor's reading or substantive PR diff.
4. Publish `parallel-filed` once both files are committed and available, so comparison runs automatically.
5. Acknowledge a labelled transport test through the actual receiver before declaring two-way automation live.

**Not yet verified:** Fable has no configured receiver known to this deployment. PR availability is not proof of awakening. Automatic merge is not enabled or authorized.

## Checks actually performed (17 September 2026)

- Python unit suite: valid input, rejected malformed IDs/SHAs/paths/synthesis pointers, strict schema, test/live separation, free-text exclusion, canary-only prompt. These use explicit fixtures, not actual audit evidence.
- Live GitHub retrieval of the labelled auditor-authored transport canary on the audit branch; production `main` polling does not consume it as an audit.
- Real fresh Hermes canary job `0b50e5fb1294`, status `ok`, response `MO_AUDIT_TRANSPORT_CANARY_OK`; no audit performed.
- Repeated retrieval of the same canary did not create a second job.
- Real script-only intake job manually triggered against main; status `ok`, no ready messages and no audit launched.

No actual audit, Fable wake-up, end-to-end two-way response, or future auto-merge is claimed by these checks. Failed jobs remain visible in Hermes execution records; generic failures are escalated rather than automatically rerun in an unbounded loop. Missing-evidence retries require a new immutable response message.

## Maintenance

Run tests with `python3 -m unittest discover -s audit/automation -p 'test_*.py' -v`. Deploy only a reviewed script copy to this profile. Inspect changes before installation. The installed Python uses Hermes's existing `cron.jobs.create_job` and `load_jobs`; use the Hermes environment, not a random interpreter without those modules. Recheck this API when upgrading Hermes.

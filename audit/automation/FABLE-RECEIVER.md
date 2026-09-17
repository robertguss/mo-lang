# Fable's receiver: how the lead hears the auditor

**Status (17 Sep 2026, 6:00 PM ET):** receiver written, unit-tested, and run once against GitHub (it retrieved the auditor's labelled canary from PR #3's branch and printed its neutral line). Robert decided the same evening (6:20 PM ET) that he will tell the lead when the auditor has posted something, so no hourly cron runs on the lead's side; the lead runs `check` by hand on his word, and `publish` for its own records. **Not yet verified:** a message addressed `to: fable` arriving through it, and the auditor's intake recording a reply from it. The transport test below does both; until it has run, two-way automation is not live.

## What runs

- **`audit/automation/fable_poll.py check`** polls github.com/robertguss/mo-lang through the machine's `gh` login: every open pull request whose head branch starts with `audit/`, then `main`, for `audit/handoffs/<subject>/<id>.json`. Records `from: fable` are skipped (they are the lead's own). Records addressed `to: fable` are validated with the same rules as the auditor's intake (exact fields, lowercase token ids, path matching id, full SHA, canonical paths, bounded request) and printed once as one neutral line: kind, subject, id, reply-to, evidence commit, paths, and the PR or `main` where the record sits. The free text is printed only for `working`, `evidence-needed`, `escalated`, and `transport-test`. For `reading-filed` and `compared` the script prints pointers and says whether the lead's own reading for that subject is already on `main` ("FILE FIRST" when it is not); it never fetches the auditor's reading. Invalid records are printed once with the reason and remembered. The ledger is `~/.mo-lead/fable-intake.json` on the lead's machine, outside the repository, so an hour's poll writes no commit.
- **`audit/automation/fable_poll.py publish`** writes one immutable record `from: fable, to: auditor` after validating it with the intake's rules for Fable and checking every path is a regular file at the pinned commit with `git cat-file`. It refuses to overwrite an existing id. The lead commits that one file by path and pushes it to `main`.
- **The wake-up** is every fresh lead session's onboarding (`CLAUDE.md` and the `mo-lead` skill run `check` before any work) and, mid-session, Robert: he tells the lead an auditor record or PR exists (a pointer, not its content), and the lead runs `check`, which announces it with pointers only. What the lead does with each line: answer `evidence-needed` by committing raw evidence and publishing `evidence-updated` naming the request's id; on `reading-filed`, file its own reading first if missing, then publish `parallel-filed` naming both files; on `escalated`, put the item in front of Robert; on `transport-test`, reply with a `working` record that names the canary. It never opens the auditor's reading before the lead's is committed.

## Limitations, said plainly

- There is no unattended poller on the lead's side, by Robert's choice: the inbound leg's latency is his. The auditor's intake still polls `main` hourly for the lead's records, so the outbound leg is unattended. The ledger survives across lead sessions, so nothing is re-announced.
- Polling is hourly, like the auditor's, so a full exchange (ready, reading, parallel, comparison) takes several hours of wall clock at best. That is the cadence Robert chose.
- The receiver trusts `main` and the `audit/*` branches of this repository as the enqueue boundary, as the auditor's intake does; the `from` field is data, not identity. Records on branches that are not `audit/*` are not read.
- GitHub trees over the API limit are reported as truncated and may hide records; the repository is far from that limit.

## The transport test (labelled, harmless)

1. The auditor posts, on an audit branch with a pull request, a record of kind `transport-test`, `from: auditor`, `to: fable`, subject `automation-transport-test`, whose paths name existing files and whose request says it is a test. (The existing canary of 17 Sep is `to: auditor`; the receiver announces it only with `--canary`, which the dry run used.)
2. Robert tells the lead the record exists; the lead runs `check`, which prints its line. The lead replies on `main` with `publish --kind working --subject automation-transport-test --id automation-transport-test-fable-ack-<n>` whose request names the canary's id and says it is a test acknowledgement, pinned to a commit containing the canary's path.
3. The auditor's hourly intake records the `working` message (status only, no audit). Its intake ledger showing that record, and the lead's ledger showing the canary, is the evidence that both directions work without Robert. Both sides note the result under `audit/` and only then is the workflow called live.

## Rules the lead follows on this path

Raw evidence is committed and pushed before any `ready`; the paths in a `ready` are raw outputs, scripts, corpus files, and the sealed brief, never RESULTS.md, the decision log, or a reading. A consumed record is never edited. The lead's reading is committed before the auditor's is opened; a session that has seen the auditor's conclusions does not write a reading called cold. Hidden suites and seeds never appear in a handoff. Unresolved substantive disagreements go to Robert as decision-log rows citing both files, in a short summary, not as relay requests.

## Tests

`python3 -m unittest discover -s audit/automation -p 'test_*.py' -v` runs the auditor's seven tests and the receiver's eighteen (schema in both directions, the test/live boundary, synthesis pointers, the publisher's checks against a throwaway git repository, the ledger). No test touches GitHub.

# Fable's source review of Astra's overnight harness work

19 Sep 2026, about 7:25 to 7:42 AM ET. Robert asked the incoming lead to review
the ten components GPT-6-Astra built and accepted overnight (commits
`3b6c7536..edb75165`). Four read-only Claude Opus reviewers, one per area, each
told to be sceptical and to separate what it traced in code (CONFIRMED) from
what it suspects (PLAUSIBLE). No builds, machine runs or the full suite: a
worker was using the host. Reviewers ran only local unit tests (84 Python tests
pass). Nothing here is a fix; fixes are queued in `HANDOFF.md`.

Size of the night, measured by the lead: about 7,400 lines of Python, 1,400 of
JavaScript and 900 of Mo; 16,658 tracked files under `toolchain/harness/`, of
which about 113 are source.

## Verdicts

| area                                               | verdict                                                                                                      |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `executor/workspace_files.py`                      | keep                                                                                                         |
| `executor/remote.py`, `adapter.py`                 | keep with fixes (E1, E5)                                                                                     |
| `executor/workspace_controller.py`, `workspace.py` | keep with fixes (E2, E4, E6)                                                                                 |
| `executor/recovery/`                               | rewrite machine-side `recover()`; four tests hold nothing up (E3)                                            |
| `executor/application/`                            | keep                                                                                                         |
| `executor/workspace_http/`                         | keep with fixes (H1 to H7)                                                                                   |
| `provider/auth/`                                   | keep                                                                                                         |
| `provider/turn.mjs`, `provider/bridge/`            | keep with fixes; cannot succeed live as written (P1 to P3); `bridge/run.py` and `mo.mjs` unreproducible (P5) |
| Mo agent (`examples/programs/agent/`)              | keep with fixes (M1 to M8)                                                                                   |

## Executor, workspace, recovery (CONFIRMED unless marked)

- **E1, high.** `remote.py:218-237`: `reap()` turns any exception into
  `systemctl poweroff`. `cleanup()` (`remote.py:136-139`) allows `docker rm -f`
  at most 2 s and lets `TimeoutExpired` escape, so a slow daemon powers off the
  machine. Mock-tested only, by the README's own account.
- **E2, high, reproduced.** `workspace_controller.py:335-341` writes
  `calls/<id>.result`, but `calls/` exists only after `claim()` (line 274). Any
  pre-claim refusal (`foreign_run`, corrupt state, `recovery_closed`, lock
  deadline) raises `FileNotFoundError`; the host sees `transport_unknown` and
  quarantines. `test_claim_foreign_and_active_exclusion` makes a successful call
  first (`test_workspace.py:108`) and so misses it.
- **E3, medium, demonstrated.** `recovery/machine.py:46-48` pre-seeds
  `cleanup: unresolved, execution: unknown` and ends in a blanket `except`
  (193-194). With `read_json` replaced by a function raising `NameError`, these
  still pass: `test_foreign_state_retained`,
  `test_missing_root_is_not_runtime_absence`,
  `test_dispatched_missing_storage_requires_proof`,
  `test_conflicting_local_manifest_refused_before_transport`. The positive-path
  tests did fail, so they are real.
- **E4, medium.** `workspace_controller.py:320` catches `ValueError`, which
  swallows `JSONDecodeError`: a truncated `state.json` is reported as
  `refusal/completed`. Reachable: `remote.py:68-71` renames without `fsync` and
  E1 powers the machine off.
- **E5, medium, latent.** `adapter.py:154` concatenates caller-supplied `name`
  into a systemd `ExecStopPost`; the machine side never validates it. Safe today
  because the host sends a UUID.
- **E6, low.** `workspace.py:225` catches `ValueError`; `files.Refusal`
  subclasses it, so programming errors become refusals.
- **E7, complexity.** `recovery/machine.py:43-198` is one function of about 30
  branches with one error code. `workspace_controller.py:214` re-hashes the tree
  (up to 64 MB) on every `write_file`; `workspace_files.py:191` is O(n²).
- **Good.** `workspace_files.py` (per-component `O_NOFOLLOW`, `st_nlink`,
  `S_ISREG`, setuid checks); `policy_errors` (`remote.py:81-123`) with exact
  `Env` equality; isolation flags re-read from `docker inspect`; mutation-style
  tests against real hostile filesystem entries.

## Workspace HTTP

- **H1.** `bridge.py:212,220`: non-command ops wait 2 s, then `_end` closes IPC
  while the owner is still inside a call it allows 7 s (`workspace.py:137`); the
  owner gets EPIPE (`owner.py:169-172`) and exits. One slow file op ends the
  run. `local.py:211-217` asserts this as intended.
- **H2.** `bridge.py:206,227`: a readable socket after the body is treated as
  pipelining, so a legal half-close (`shutdown(SHUT_WR)`) closes admission for
  the whole bridge. No test half-closes.
- **H3.** `bridge.py:109,114,222,231`: `_end` closes `self.ipc` while a serve
  thread selects on it; the fd number can be reused by a new connection.
- **H4.** `protocol.py:115-118`: more than 65,536 bytes of valid output is
  reported as `failure/output_encoding`; `CONTRACT.md:58` reserves that code for
  invalid base64 or UTF-8, and the cap is undocumented.
- **H5.** `protocol.py:125`: `if key in source` lets a `read_file` success with
  no `text` through as `success`.
- **H6.** `bridge.py:226,228,241`: a client disconnect mid-call is reported as
  `owner_unknown`.
- **H7, contract mismatches.** Missing `Host` gives 403 `unbound`
  (`bridge.py:170`); `Refused('oversized', 413)` uses a core code
  (`bridge.py:146,183`); `empty_old`, `multiple_matches`, `missing_match`,
  `duplicate_call` appear only in `protocol.py:15` and no path produces them;
  `owner.py:130-132` lets `admission_closed` overwrite other refusals.
- **H8, minor.** Headers read one byte per `recv` (`bridge.py:141-144`);
  listener fd leaks if `start()` fails between `bridge.py:82` and `:89`.
- **Tests.** Real sockets, subprocess and HTTP bytes. But `WorkspaceDouble.call`
  (`test_owner.py:73-85`) ignores `args`, so path containment, `exact_edit`
  matching and truncation are untested locally; tests mutate production globals
  (`test_owner.py:33,43,52`).
- **Good.** Token never reaches owner, journal or logs; `hmac.compare_digest`;
  strict decode; journal space reserved before dispatch; 0700/0600.

## Provider

- **P1.** `turn.mjs:12,14` requires `cache_write_tokens`, which the pinned
  upstream says OpenAI never emits; `bridge/server.mjs:97-98` makes unknown
  usage a terminal 422. `test.mjs:90` asserts the bug as intended.
- **P2.** `turn.mjs:25-26` rejects deadlines over 5,000 ms; the bridge passes at
  most 2,000 (`server.mjs:27,89`).
- **P3.** `turn.mjs:89` aborts past 65,536 response bytes; `protocol.mjs:2`
  holds fixture-sized budgets (16 steps, 4,096 tokens, 30 s session).
- **P4.** Nothing is vendored: `setup.py:12-15` downloads from GitHub and npm;
  `pin.json` is a report (148 of 177 artifact files match git). The sha256
  asserts and package-lock integrity are the real pin and are sound.
- **P5.** `bridge/run.py:17,31,38` hardcodes machine-local gitignored paths;
  `bridge/mo.mjs:9` needs an uncommitted `release.json`.
- **Good.** No real secret in any tracked file. `store.mjs:33-91`: 0600 in 0700,
  ancestor checks, `O_NOFOLLOW`, inode recheck, atomic rename. Redirects
  refused, host pinned (`auth.mjs:34,48-50,68`). Adversarial tests. READMEs say
  plainly that nothing live is verified.
- PLAUSIBLE: `store.mjs:112` masks errors in `finally`; `turn.mjs:113` bare
  catch; `journal.mjs:11-16` refuses macOS `/tmp`; no `engines` field.

## Mo agent

- **M1.** `tests/coding-fixture-v1/boundaries.mo:234-236`: the error arm asserts
  `why.contains?("unavailable")`, true of every error string; Ok-arm assertions
  are all guarded (`:228,:231`). The test cannot fail.
- **M2.** `boundaries.mo:223` asserts bounds `run.mo:99,118` already guarantee.
- **M3.** `main.mo` asks `Start` within 45,000 ms; budget is 30 s plus 15 s
  grace, no slack for open, create or polling.
- **M4.** `command-adapter.mo:25`: a completed 200 response is discarded as
  `timeout/unknown` if the deadline has just passed; misreports ground truth.
- **M5.** `run.py:70,127` handle `edit-empty` and `command-failure`, but neither
  is in `CASES` (`:51-56`).
- **M6.** `run.py:171` does not assert refusal reasons for four edit cases.
- **M7.** `exact-edit.mo:43`: `or ""` fallback would write an empty file as
  success; unreachable today, wrong direction.
- **M8, architecture.** `run.mo:130,133,155,179`: fixture-only budget gates
  duplicate `asks?`/`uses?`/`budget_end` with different semantics (an off-by-one
  at the token bound) behind a flag.
- PLAUSIBLE: `run.mo:61` inherits the recording deadline from the configure ask;
  `exact-edit.mo:31-40` is O(n·m); `report.mo:36` prefix-matches raw JSON.
- **Good.** `command-adapter.mo:52-109` validation; `run.py:114` checks the
  on-disk record before each dispatch independently; the terminal-auth matrix
  observes request counts `[1,2,2,2,3,1,0,1,1]` at the socket in both runtimes.

## The lead's reading

The code is sounder than the records made it look, and the records are more
honest than their density suggests. The weakness is acceptance: lead, workers
and reviewers were one model, and it accepted at least five tests that cannot
fail (E3's four, M1) and one that asserts a defect as intended (P1), plus H1's
teardown asserted as intended. "Independent acceptance" in the overnight rows
should be read as "re-run by the same model". None of the ten is withdrawn;
recovery's acceptance is qualified.

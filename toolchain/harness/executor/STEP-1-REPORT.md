## Report to the lead: harness step 1 (executor defects and deletion)

All five parts are done in three local commits. Nothing was pushed, and I didn't touch the machine, Docker or `/opt`. All local suites pass. Two things need your attention: the provider files I rewired never ran, and three provider READMEs plus `attempt.sh` now point at deleted runners.

### Commits (branch `harness/step-1-executor`)
- `8849b899` fixes E1, E2, E4, E5 and E6, and makes the exec-bootstrap loader one copy.
- `85d49365` adds one read-only `inventory.py` and deletes the per-run probes.
- `cf5ed57b` adds one guarded runner, `executor/guarded.py`, and deletes the six runner copies.

Each commit message says what every deleted file was for.

### Tests (all under `guard.py`, on the committed HEAD)
| suite | summary line | exit |
|---|---|---|
| `unittest discover -s toolchain/harness/executor -p 'test_*.py'` | `Ran 96 tests in 5.587s` / `OK` (84 before) | 0 |
| `unittest discover -s …/executor/application` | `Ran 25 tests in 0.428s` / `OK` (17 before) | 0 |
| `workspace_http/local.py` | `Ran 22 tests in 25.778s` / `OK` (22 before) | 0 |

The command that counted 84 doesn't reach `application/` or `local.py`, so I ran those two as well. The application count went up only because `test_policy.py` imports `test_workspace.Controller`.

The failing tests came first:
- **E2, E4, E6:** they failed on the old code with `FileNotFoundError …calls/<id>.result`, `filesystem_refusal`, and no fsync.
- **E1, E5:** on the old code they only produced an ImportError. So I ran them against a scratch copy of the old code with name-only stubs. That showed the real defect: `['systemctl', 'poweroff'] unexpectedly found` after a `docker rm` timeout. The name-validation tests failed with `ValueError not raised`.

### Lines (non-blank, non-comment `.py`; excludes `evidence/`, `attempts/`, `sources/`)
| directory | before | after |
|---|---|---|
| executor | 2229 | 2568 |
| executor/application | 788 | 600 |
| executor/recovery | 1515 | 1262 |
| executor/workspace_http | 1818 | 1641 |
| provider | 172 | 148 |
| provider/auth | 77 | 53 |
| provider/bridge | 89 | 54 |
| **total** | **6688** | **6326** |

Split by kind, code other than tests fell from 5,369 to 4,869 lines and tests rose from 1,319 to 1,457. Counting command: `git ls-files toolchain/harness/executor toolchain/harness/provider`, keep `*.py` not under those three directories, and count lines where `l.strip() and not l.strip().startswith('#')`, grouped by directory.

### Decisions the brief didn't cover
1. **The host stop follows the same rule as the reaper.** `_collect` used to run `orbctl stop` on any failure, including a `docker rm` timeout inside `finalize`. It now stops the machine only when `finalize_report` returns `containment_failed: true`. When the transport fails and the outcome is unknown, it records `cleanup_error` and no longer stops the machine. This reverses an accepted test, `test_host_cleanup_failure_stops_only_named_machine…`.
2. **What counts as proof of an escape:** the candidate's registered cgroup reports `populated 1` in `cgroup.events`. If the cgroup can't be read, or the run never registered, that's not proof, and the machine stays up. The reaper retries 3 times within 7 s, which fits under the reaper unit's `TimeoutStartSec=8s`.
3. **E6: the catch narrowed; `Refusal` still subclasses `ValueError`.** `examples/` and the bridge catch `ValueError`, so changing the base class could break them. Instead there's a new `remote.Invalid(ValueError)` for policy refusals of caller input. Any other `ValueError`, `KeyError` or `TypeError` in the controller is now reported as `controller_failure`, which quarantines the workspace.
4. **E4:** a corrupt `state.json` returns `failure/unknown/quarantined`. That error code already exists. The file's bytes are left as they are, not rewritten.
5. **E5:** the name is checked in the bootstrap before the lock, the run directory or any unit. `supervise`, `reap`, `finalize` and `dispose` check it too. I left it out of `manifest_policy` because existing manifests passed to `authorize` carry no name.
6. **Where the helper lives:** the brief gave no location, and `toolchain/harness/` itself is outside my write scope, so it's in `executor/`. It records the git head and dirty paths instead of copying sources into every attempt.
7. **I edited two live-suite strings,** because four copies becoming one required it. In `recovery/live.py` (step 2's file) I changed the partial-root injection string and the loader in `send_request`. In `test_lifecycle_live.py` I changed the finalizer injection string. Please tell the step 2 worker about the `recovery/live.py` change. `Workspace.call` still calls its own module's `remote`, because the live suites patch `workspace.remote`.

### What I chose not to delete, and why
- **`controller_deadline`, `live_frontend`, `frontend_control`, `live_owner`:** `live.py` and `local.py` import them.
- **`provider/bridge/run.py`:** it also prepares the copy and writes the receipt. I replaced only its runner part. Its hardcoded machine paths (review item P5) are still there.

### Ownership gaps and things I couldn't verify
- **Stale references I couldn't fix:** `provider/README.md`, `provider/auth/README.md`, `provider/bridge/README.md` and `provider/auth/attempt.sh` still name the deleted `run.py` runners. They aren't `.py` files, so they're outside my write scope.
- **Provider code never ran:** the rewired `clean_setup.py`, `auth/setup.py` and `bridge/run.py` need the network or prepared copies at machine-specific paths. Only the helper's empty-home mode ran, with `node --version`.
- **Pre-existing import failure:** `recovery/readiness_probes.py` fails to import (`from live import …`, and no such module is tracked). It already did this before my changes.

### What you need to re-run on the machine
The registration bootstrap changed for every run, so run all of these, one at a time, each under `guarded.py`:
- `selftest.py` (executor17)
- `test_lifecycle_live.py`: this one checks that the host still reaches the stop fallback, now through the `populated 1` proof.
- `test_workspace_live.py` (workspace22)
- `recovery/live.py`
- `workspace_http/live.py`, which includes the deadlines group
- `application/controls.py` (application23)
- `inventory.py` at the end, for the read-only cleanup proof

Two E1 checks also need the real machine:
- the reaper really reads `cgroup.events` under `/sys/fs/cgroup/mo.slice/…/docker-<id>.scope`;
- a stalled Docker daemon leaves `reaped.json` saying `cleanup_unconfirmed` and does not power off.

## Report to the lead: harness step 2 (live suites as tables, tests that can fail)

All four parts are done in five local commits on `harness/step-2-live-tables`.
Nothing was pushed, and nothing ran against `mo-executor-r01`, Docker or `/opt`.
All local suites pass. The live suites are restructured but have **not** run on
the machine, so your reruns are the real test. Counted lines did not go down:
the suites shrank, but the shared runner and new tests added more than that. The
numbers are below.

### Commits

- `34513a69`: part 2 (E3). The four tests now fail when `recover()`'s body is
  broken.
- `da877bd4`: part 3. The HTTP test double's file tools run the real controller;
  `owner.run` and `Bridge.start` take parameters instead of being patched.
- `af361e15`: part 4. The provider READMEs and `attempt.sh` now point at
  `executor/guarded.py`.
- `cbb4950a`: part 1. One runner (`executor/cases.py`) plus case tables, and
  `test_cases.py`.
- `bcf21c4a`: part 4. `recovery/readiness_probes.py` is fixed, not deleted.

### Tests (all under `toolchain/bench/step36/guard.py`, committed HEAD `bcf21c4a`, clean tree)

| suite                                                                          | before (`31ad3ba9`)              | after                             | exit |
| ------------------------------------------------------------------------------ | -------------------------------- | --------------------------------- | ---- |
| `python3 -B -m unittest discover -s toolchain/harness/executor -p 'test_*.py'` | `Ran 96 tests in 5.610s` / `OK`  | `Ran 106 tests in 10.084s` / `OK` | 0    |
| `python3 -B -m unittest discover -s toolchain/harness/executor/application`    | `Ran 25 tests in 0.451s` / `OK`  | `Ran 25 tests in 0.448s` / `OK`   | 0    |
| `python3 -B toolchain/harness/executor/workspace_http/local.py`                | `Ran 22 tests in 25.538s` / `OK` | `Ran 22 tests in 26.274s` / `OK`  | 0    |
| `python3 -B toolchain/harness/executor/recovery/local_suite.py`                | `Ran 71 tests in 4.502s` / `OK`  | `Ran 71 tests in 4.429s` / `OK`   | 0    |

The executor count rises by exactly the 10 tests in the new `test_cases.py`.
`local.py` still has 22 tests: its new coverage went into the existing groups,
because `live.py` shares the same 22 names.

### Part 2: E3

I reproduced the review's finding first. With `recovery.machine.read_json`
replaced by a function that raises `NameError`, the three machine tests passed
(`Ran 4 tests` / `OK`, exit 0). The host test (`…refused_before_transport`) also
passed with `recovery.validate_supporting` broken the same way. Host `recover()`
has no `read_json`; `validate_supporting` is the host-side check the test
depends on.

Each test now pairs its refusal with a positive control of the same shape, which
must be confirmed. It also asserts the stage where recovery stops: the completed
phases, which runtime query was made, the retained terminal record, and whether
transport was reached. `recover()` itself is unchanged. Under the same mutations
on HEAD:

- machine: `test_foreign_state_retained ... FAIL`,
  `test_missing_root_is_not_runtime_absence ... FAIL`,
  `test_dispatched_missing_storage_requires_proof ... FAIL`, then `Ran 4 tests`
  / `FAILED (failures=3)`, exit 1. The host test stays `ok` here because it
  doesn't use `read_json`.
- host: `test_conflicting_local_manifest_refused_before_transport ... FAIL`,
  then `FAILED (failures=1)`, exit 1.
- The failures read `'unresolved' != 'confirmed'` and
  `Lists differ: [] != ['terminal_barrier', '<id>', 'workspace_deleted']`.

The mutation runner is a scratch script: it patches the named function with one
that raises, then runs the four tests by name.

### Part 3: the HTTP test double

- **Real controller.** `WorkspaceDouble.call` now sends `list_files`,
  `read_file`, `search`, `write_file` and `exact_edit` through the real
  `workspace_controller.handle`, on a local directory standing in for the
  machine's workspace root. Commands, freeze, verify and delete are still
  scripted, because they need the machine.
- **New coverage, inside existing groups:**
  - `file-refusals`: lexical escapes (`../escape`, `/etc/passwd`, `a//b`,
    `a/./b`, `answer/..`, write to `../outside`) and links out of the root, at
    the last and at a middle component. The outside file is left unchanged and
    `secret` appears in no response. `exact_edit` missing, multiple and empty
    matches all leave the bytes unchanged.
  - `byte-bounds`: a 64 KiB file is refused whole (`result_too_large`); search
    and listing are cut short and say `truncated: true`.
  - `six-tools`: now asserts the real results.
- **The new tests can fail.** Each of these edits to `workspace_files.py`,
  restored afterwards, fails the suite with exit 1:
  - allowing `..`
  - taking the first of several matches
  - dropping the `truncated` flag
  - dropping `O_NOFOLLOW` in `read_at`. This one returned
    `{'text': 'secret\n'}`.
- **No more patched globals.** `owner.run(..., journal_cap=, clock=, transmit=)`
  and `Bridge.start(owner_module=)` replace the tests' patches of
  `owner.JOURNAL_CAP`, `owner.time`, `owner.send` and `subprocess.Popen`.
  `live.py`'s `start_recorded` uses the same parameter.

### Part 4: stale references

- **Provider docs.** `provider/README.md`, `provider/auth/README.md`,
  `provider/bridge/README.md` and `provider/auth/attempt.sh` now call
  `executor/guarded.py`, with the old 550-second deadline, empty home and
  `evidence/<attempt>` directory. The remaining `run.py` mentions are
  `bridge/run.py`, which still exists. I ran `attempt.sh` in a scratch copy of
  the directory layout: exit 0, it records the attempt with HOME set to
  `.cache/home-t1`, and reusing a name exits 2.
- **`readiness_probes.py`: fixed.** It is the only positive readiness probe
  (slice limits, image and package identity, empty runtime), and `inventory.py`
  only proves absence, so it is worth keeping. The step 1 description was partly
  wrong: `from live import …` worked when the file ran as a script from
  `recovery/`, and failed only as a package import. The constants have moved to
  `cases.py` and the import now points there. The probe body is in `main()`, so
  importing the module no longer runs `orbctl`. The two machine-side scripts are
  byte-identical (checked by AST). It has not run, because it needs the machine.

### Part 1: one runner, case tables

- **`executor/cases.py`** holds what the suites shared:
  - selection from the fixed table: unknown, empty or duplicate names exit 2
    before any output is created
  - one record per case, written to the suite's records file and printed as a
    JSON line
  - the summary line
  - the Mac `docker ps` baseline
  - candidate registration polling
  - the machine-side absence and leftover inventories
  - `resume`, `until`, `then` (cleanup that never hides a case failure) and
    `Shared` (workspaces made on first use).
- **`workspace_http/client.py`** holds the 22-group registry and the HTTP client
  that `local.py` and `live.py` both carried.
- **Each suite** is now a table of `(name, action)` rows plus its own helpers.
- **Kept:** command lines and summary shapes (`{"count": 17, …}` indented,
  `{"controls": 22, …}`,
  `{"groups": N, "passed": N, "actual_workspace": true, "acceptance": false}`,
  `{"controls": 23, …}`). Step 1's two injection strings in `recovery/live.py`
  are unchanged (partial root, and the `machine_call` loader in `send_request`).
- **Names that other files import still resolve:**
  - `selftest.snapshot`, which `application/controls.py` and
    `readiness_probes.py` replace
  - `selftest.resume`, `TREE`, `wait_running` and `assert_clean`, used by
    `test_lifecycle_live.py`
  - `test_workspace_live.lifecycle` and `controller_death`
  - `controls.run`, `controls.CONTROLS` and `controls.load`, used by
    `regressions.py`
  - `live.start_recorded`, `registered` and `response`, used by `review_live.py`
    and `live_frontend.py`.

**Offline check.** `test_cases.py` checks every table against the frozen names.
It then runs each suite's own command line with a stand-in `orbctl` (an empty
machine: its inventories and cleanup-only recovery answer, everything else
fails) and a stand-in `docker` first on `PATH`. Every case fails fast with
`stand-in: no machine`, gets a record, cleanup runs, and the summary prints:

- `"count": 17`
- `{"controls": 22, "passed": 0, …}`
- `{"controls": 23, "passed": 0, …}`
- `{"groups": 1, "passed": 0}` for recovery, which stops at the first failure.

I ran the base commit's suites under the same stand-ins for comparison:

- `selftest`: same `"count": 17`.
- base `test_workspace_live`: crashed after its first case, when the shared
  `repair` workspace couldn't be created. Nothing was deleted and no summary
  printed.
- base `application/controls.py`: printed `{"controls": 0, …}`.
- recovery and HTTP: stopped at their first group, as mine do.

The static check `ruff --select F` finds no undefined names in any changed file.

### Every live case, before (`31ad3ba9`) and after (HEAD)

I read the before lists from the base commit's source text and the after lists
from the new tables. They match in names and order; `test_cases.py` asserts the
same lists.

- `selftest.py` (17 → 17): completion-descendants, wrong-output, nonzero,
  forged-success, overwrite-authority, fault-stimulus-control,
  absent-fault-stimulus, timeout-descendants, cancel-descendants,
  output-overflow, cpu-enforcement, memory-enforcement, pid-enforcement,
  scratch-enforcement, network-filesystem-denial, controller-death,
  supervisor-death.
- `test_workspace_live.py` (22 → 22): invalid-import-never-ready,
  real-failure-inspection-repair-success, duplicate-foreign-calls,
  invalid-paths-utf8-overlap, freeze-independent-positive,
  closed-dispatch-and-empty-checks, missing-stimulus-and-result-overwrite,
  wrong-candidate-forged-success, final-symlink, intermediate-symlink, hardlink,
  fifo, unsupported-mode, tmpfs-byte-quota, tmpfs-inode-quota,
  timeout-descendants, cancel-descendants, exit-descendants,
  supervisor-death-mounted, controller-death-mounted, stale-mutated-snapshot,
  snapshot-permission-drift.
- `recovery/live.py` (16 → 16): create-before, create-response,
  reserve-response, registration-before-reaper, active-owner-death,
  finalize-gap, complete-gap, dispose-gap, repeated-cleanup, foreign-identity,
  malformed-linked, lock-contention, unknown-transport, late-bootstrap,
  application-active, application-snapshot.
- `workspace_http/live.py` and `local.py` (22 → 22, and 22 `test_` methods →
  22): six-tools, output-encoding, schema, framing, byte-bounds,
  identities-capability, duplicate-calls, concurrent-admission, file-refusals,
  deadlines, disconnect, frontend-death, owner-death, lost-response,
  owner-stall, startup-failure, shutdown, protected-verifier,
  application-binding, cleanup-outcome, invalid-selection, journal-order-bound.
- `application/controls.py` (23 → 23): hello-cold-build, logstat-cold-build,
  snapshot-rebuild, failed-build-no-stale, scratch-fresh, source-noexec,
  image-root-immutable, snapshot-immutable, output-bound, timeout-descendants,
  cancel-descendants, exit-descendants, supervisor-death, controller-death,
  build-quota, tmp-quota, effective-resources, empty-checks, policy-rebind,
  forged-verdict, cpu-enforcement, pids-enforcement, memory-enforcement.

### Lines (non-blank, non-comment `.py`; excludes `evidence/`, `attempts/`, `sources/`)

| directory               | other code before | after    | tests before | after    |
| ----------------------- | ----------------- | -------- | ------------ | -------- |
| executor                | 1707              | 1869     | 861          | 1036     |
| executor/application    | 432               | 410      | 168          | 168      |
| executor/recovery       | 942               | 904      | 320          | 361      |
| executor/workspace_http | 1533              | 1514     | 108          | 126      |
| provider                | 148               | 148      | 0            | 0        |
| provider/auth           | 53                | 53       | 0            | 0        |
| provider/bridge         | 54                | 54       | 0            | 0        |
| **total**               | **4869**          | **4952** | **1457**     | **1691** |

I counted the same way as step 1 (its "before" totals match). Take the tracked
files
(`git ls-tree -r --name-only REV toolchain/harness/executor toolchain/harness/provider`),
keep `*.py` files not under `evidence/`, `attempts/` or `sources/`, and count
lines where `l.strip() and not l.strip().startswith('#')`. Group by directory; a
file counts as a test if its name starts with `test_`, so
`test_workspace_live.py` counts as a test and `local.py` as code.

**Where the lines went, per file (before → after):**

- The suites shrank by 250 lines:
  - `selftest.py` 234 → 213
  - `test_workspace_live.py` 258 → 226
  - `recovery/live.py` 331 → 298
  - `workspace_http/live.py` 351 → 305
  - `local.py` 363 → 345
  - `application/controls.py` 207 → 185
  - `review_live.py` 83 → 74
  - `recovery/owner.py` 23 → 15
- The new shared code adds 237: `cases.py` 183 and `client.py` 54.
- `readiness_probes.py` went 88 → 91.
- Live suites plus runner together: **1938 → 1989 (+51)**.
- New tests: `test_cases.py` 207, `test_recovery.py` +41, the test double +18.

The shared runner didn't pay for itself in lines. The gain is one record format,
one summary path, cleanup that always runs, and a local test of all of it.

### Decisions the brief did not cover

1. **Changes on failure paths only.**
   - The shared workspaces (`repair`, `application`) are now made on first use.
     A failed creation fails the cases that need them, and cleanup still runs;
     before, the suite crashed with nothing deleted.
   - When `selftest` cleanup fails after a case failure, the case failure is
     still the one reported, with the cleanup traceback attached as a note.
     Before, the record had separate `error` and `cleanup_error` fields.
2. **Record format.** Every per-case record now has `ok`, `elapsed_seconds` and
   `error` (the traceback). The HTTP suite prints a JSON record per group
   instead of `<group> PASS`. Its `results.json` field is `ok` rather than
   `passed`. `failure.json` is now the failing record rather than
   `{type, detail}`.
3. **Recovery summary.** `recovery/live.py` now prints a summary line,
   `{"groups": N, "passed": N}`; it had none.
4. **Selection errors.** All suites print the same argparse error text for a bad
   selection. `application/controls.py` loses argparse `choices`, so an unknown
   control reads "unknown, empty or duplicate selection". Exit code 2 and "no
   output created" are unchanged, and tested.
5. **Evidence files.**
   - `selftest` now also writes `cases.json` as it goes.
   - `test_workspace_live` copies its sources into `<out>/sources/` rather than
     `<out>/`. The copies now include `cases.py`.
   - The workspace and application leftover inventories use one query. Its keys
     are `exit`/`stdout` everywhere; the workspace suite used `rc`, and
     application cleanup errors now use `workspace_id`.
   - A container or unit listing that is only whitespace now counts as absent in
     recovery too; the HTTP and review suites already counted it that way.
6. **Registration polling.** Recovery's `running()` and `recovery/owner.py` now
   poll registration with one machine call instead of two. `owner.py` writes the
   parsed registration into `ready.json`, not the raw bytes; `live.py` only
   checks that the file exists.
7. **What the test double patches.** It sets `workspace_controller.BASE` to a
   local directory and stubs `os.fchown` for uid 65534 only, inside its own
   subprocess. That process stands in for the machine, and the candidate uid
   doesn't exist on the Mac. `handle()` has no parameter for either, and adding
   one would mean changing machine-side code.
8. **Left as it was.** The `select.select` patch in local `deadlines`
   (lease-active) is still there. A parameter would need a hook in the bridge's
   serve loop, which is production code the brief didn't ask me to change.
9. **Controller behaviour the new test found.** Any `write_file` or `exact_edit`
   in a tree that holds a link is refused (`filesystem_refusal`) before its own
   path is checked, because the controller inventories the whole tree first. The
   test asserts this as current behaviour. I didn't evaluate whether it is
   intended.

### Rule slip

Once, while comparing the smoke outputs, I used `tr -d '\n'` to format output,
against the machine rule. It changed no files; everything else used python3.

### What you need to rerun on the machine

Every live suite changed structure, so run all of them, one at a time, each
under `guarded.py`, with the same command lines as before:

- `selftest.py OUT` (executor17)
- `test_workspace_live.py OUT` (workspace22)
- `recovery/live.py OUT` (16 groups)
- `workspace_http/live.py OUT`, then again with `--application` (22 groups)
- `application/controls.py OUT --image … --toolchain …` (application23)
- `workspace_http/review_live.py OUT`
- `recovery/regressions.py OUT`, which also runs `application/controls.py`
- `recovery/readiness_probes.py OUT`
- `inventory.py` at the end.

`test_lifecycle_live.py` is untouched, but it imports the refactored `selftest`.
The live owner (`live_owner.py`) now starts through
`Bridge.start(owner_module=…)` instead of a `Popen` patch; `live.py`'s
`start_failure` and `frontend-death` groups cover that path.

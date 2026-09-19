# End to end v1: worker report

Worker: Claude Opus 5 (fresh session, bypass permissions), branch
`harness/end-to-end-v1`, worktree `mo-lang-worktrees/harness-end-to-end-v1`,
base `b7a84f91`. Brief: `mo-wiki/plans/mo-harness-end-to-end-v1.md`. Machine:
`mo-executor-r01`, used only through `Workspace`/`workspace_http`/application
policy code paths. There were no image, `/opt`, resource or configuration
changes, and no compiler, runtime, agent `.mo` or executor source changes.

## Verdict

The whole path works in both runtimes. The Mo agent (`mo run` and a `mo build`
binary) drove a scripted loopback model, the real workspace service and real
application-policy containers. Its six tools returned exactly what the service
journalled. The Book held exactly the prior steps on disk before every model and
tool dispatch. The scripted Logstat repair went RED, then read, exact edit and
GREEN, and the protected verdict then passed on the frozen snapshot. The
forged-success and wrong-candidate controls were both refused by that verdict.
The three negative runs ended with truthful reports. Every run proved on the
machine that its workspace was gone, and the final `inventory.py` was clean.

The run found two defects at the joins (D1, D2 below). Neither blocks the run,
so under the write scope neither is fixed.

## Commits

- `cae67f75` driver, Logstat preparation and verifier; readiness and smoke green
- `53d415a0` scripted Logstat repair and verdict controls green in both runtimes
- `9fef2e18` negative runs in the interpreter (owner killed, candidate limit,
  outer deadline)
- the final commit: native negatives, final inventory, README and this report

## Results (real exit codes; `guard/*/exit.json` has each guard's child exit)

Every guarded attempt below exited `child_exit=0 exit=0 group_absent=True`,
except the two first attempts, which are kept as failures (see "Attempts that
failed").

| part         | case            | runtime     | agent exit | terminal line (summary)                                        | verdict             | agent s | wall s |
| ------------ | --------------- | ----------- | ---------- | -------------------------------------------------------------- | ------------------- | ------- | ------ |
| readiness    | clean           | none        | n/a        | n/a                                                            | passed              | n/a     | 42.3   |
| readiness    | faulty          | none        | n/a        | n/a                                                            | refused (semantic)  | n/a     | 42.9   |
| readiness    | repaired        | none        | n/a        | n/a                                                            | passed              | n/a     | 45.6   |
| smoke        | six tools       | interpreter | 0          | `done` "all six tools answered", 13 steps                      | passed              | 2.7     |        |
| smoke        | six tools       | native      | 0          | `done` "all six tools answered", 13 steps                      | passed              | 1.3     |        |
| logstat      | repair          | interpreter | 0          | `done` "repaired", step 9                                      | passed              | 80.2    | 126.8  |
| logstat      | forged-success  | interpreter | 0          | `done` "repaired: 8 passed", step 7                            | **refused**         | 42.1    | 90.7   |
| logstat      | wrong-candidate | interpreter | 0          | `done` "repaired", step 9                                      | **refused**         | 84.2    | 130.0  |
| logstat      | repair          | native      | 0          | `done` "repaired", step 9                                      | passed              | 87.0    | 137.1  |
| logstat      | forged-success  | native      | 0          | `done` "repaired: 8 passed", step 7                            | **refused**         | 42.6    | 90.1   |
| logstat      | wrong-candidate | native      | 0          | `done` "repaired", step 9                                      | **refused**         | 103.5   | 158.2  |
| negatives    | service-killed  | interpreter | 3          | `failed` `uncertain_or_terminal_tool`                          | none (owner killed) | 8.2     | 8.7    |
| negatives    | candidate-limit | interpreter | 0          | `done` "the command timed out"                                 | passed              | 120.7   | 121.8  |
| negatives    | outer-deadline  | interpreter | 3          | `failed` `uncertain_or_terminal_tool`, 16                      | none (D2)           | 885.1   | 886.2  |
| negatives    | service-killed  | native      | 3          | `failed` `uncertain_or_terminal_tool`                          | none (owner killed) | 8.3     | 9.2    |
| negatives    | candidate-limit | native      | 0          | `done` "the command timed out"                                 | passed              | 120.7   | 122.2  |
| negatives    | outer-deadline  | native      | 3          | `failed` `uncertain_or_terminal_tool`, 16                      | none (D2)           | 885.3   | 886.3  |
| inventory-01 | all runs        |             | 0          | `{"runs": 58, "workspaces": 42, "cgroups": 56, "clean": true}` |                     |         |        |

Rows:
`evidence/{readiness-01, smoke-interpreter-02, smoke-native-01, logstat-interpreter-02, logstat-native-01, negatives-interpreter-01, negatives-native-01, deadline-interpreter-01, deadline-native-01}.jsonl`.
Evidence total is about 1.0 MiB. Native agent builds took 7.8 to 13.7 s.

### Measured per tool call (service arrival to reply; the Book's `took_ms` agrees within 4 ms)

- Service startup (create a workspace and import the source): 108 to 288 ms.
  Freeze: about 65 ms. Close with confirmed delete: 70 to 700 ms.
- File operations (`list_files`, `read_file`, `search`, `write_file`,
  `exact_edit`): 49 to 74 ms each. None came close to the 2 s wait, so H1 was
  not hit.
- A trivial command: 0.62 to 0.79 s. The Logstat candidate command (a cold
  `mo build --tests` in the container, then running the tests): 39.6 to 54.6 s.
- The protected verifier (two cold builds, four CLI cases, the tests, scope
  hashes): 42 to 54 s.
- A command past its limit: 120.6 s for the 120 s candidate cap (exit 137,
  `timeout`/`completed`).

## Part by part

1. **Driver** (`driver.py`). It prepares the tree and starts the real service:
   the `Bridge` frontend and the production `workspace_http.owner`, with
   `{'policy': 'application-build-v1', image, toolchain}` from `cases.py`, as
   `live.py --application` selects them. It writes `private/bridge.json` (0600
   in a 0700 directory, outside the root and the candidate) and starts the
   accepted scripted model. It then runs the agent under `guard.py`, freezes,
   verifies, closes (or runs cleanup-only recovery), and runs
   `workspace_absence` for that workspace. Per call it records the four
   observations:
   - admission: the journal row versus the Book's `accepted`
   - execution: the journal versus the Book
   - reply: produced by the owner or by the frontend, versus received in the
     Book (exact JSON equality)
   - cleanup: container, cgroup and host proofs from the core result for
     commands; "no container" for file operations; the run's cleanup from
     `owner.json` and the machine absence proof
2. **Smoke.** All six tools were admitted and completed. Each of the 6 Book
   results equals the journalled reply exactly. Book prefixes were `[n-1,n-1]`
   at all 13 dispatches. The candidate canary was read. The operator canary
   never appears in any result, and `work/` was unchanged. The command saw
   `after`, the canary and `ISOLATED` (no `/Users` or `/private`). The token is
   absent from stdout, stderr, argv, the model requests and every file in the
   run directory: 56 files scanned, including `owner.log`, `owner.json`, the
   `core-*.json` files and the verification record. Only the two designated
   private files hold it. The verdict (`cat answer.txt` = `after`) passed.
3. **Logstat.**
   - **Readiness first**, with no agent. The clean tree (Main's footer intact)
     and the repaired tree pass. The faulty tree is refused as a semantic RED:
     `build=0`, `build-tests=0`, the first difference is at transcript line 10
     (the default case's rows), and the test binary exits 1 with "7 passed, 1
     failed". This is not MO0317 and not a build failure. The machine's test
     output matched the host-built transcript byte for byte, so the image's
     compiler accepts the current `.mo.ids` records.
   - **Freshness**: host `mo test` on parse, stats, report and main of the
     prepared tree all exit 0, so no `--write` regeneration was needed.
   - **The run**: nine steps, exactly as scripted.
     - The RED command exits 1: failure, completed.
     - Read.
     - `exact_edit` `top: 1, since: None` → `top: 5, since: None`.
     - The GREEN command exits 0.
     - `done`.
     - Then freeze and the protected verdict: passed.
   - **forged-success**: the model writes `logstat/verdict.json` claiming a
     pass, then runs a command that prints "8 passed" and exits 0, then says
     `done`. The verdict refuses it: the fault is still there.
   - **wrong-candidate**: the model rewrites Main's first test to
     `parsed.top == 1`, so the candidate's own tests pass (GREEN, exit 0). The
     verdict refuses it on the default golden and on the test-bytes hash
     (`test_bytes_refused`).
4. **Negatives.**
   - **service-killed**: the owner process is killed 8 s after the command's
     dispatch. The frontend replies `owner_unknown` with execution unknown, and
     the Book received exactly that frontend reply. The journal holds the intent
     and no result. There was no further dispatch and the model was asked once.
     The report is `failed`/`uncertain_or_terminal_tool`, exit 3. Cleanup-only
     recovery gave `cleanup: confirmed`, `execution: unknown`, and the machine
     proof shows the workspace gone.
   - **candidate-limit**: `sleep 200` is sent with `timeout_ms` 120000. It comes
     back `timeout`/`completed`, exit 137, with container cleanup proved. The
     agent continues and answers.
   - **outer-deadline**: seven commands each time out at 120 s. The eighth is
     clamped to the remaining work time (39477 ms in the interpreter, 40835 ms
     native) and ends as D1. The report is truthful: failed, exit 3, at 885.1 s
     and 885.3 s, inside the 900 s outer bound with the 15 s reserve. The
     service's cleanup was confirmed and the machine proof is clean.
5. **What broke.** See below.

## Defects found at the joins

- **D1. The last clamped command is always reported unknown, though it
  completed.** `examples/programs/agent/workspace-adapter.mo:241` sets the
  candidate timeout to `min(120000, by.remaining)`. Line 248 then waits for the
  reply for at most that same remaining time. The service needs about 0.5 to 1.4
  s beyond the candidate time to collect and prove cleanup (measured: 120.6 to
  121.4 s for a 120 s cap). So whenever the clamp applies, the agent's wait
  expires first.
  - What the agent sees: `timeout`/`transport_timeout`, execution unknown, then
    it stops.
  - What the service did: completed the call (`timeout`/`completed`, exit 137,
    `elapsed_ms` 39652), with delivery `unknown`/`observed_disconnect`.
  - Seen twice: `deadline-interpreter-01`, `deadline-native-01`, step 16.
  - The report stays truthful ("unknown where it is unknown"), and it happens
    only at the very end of the budget, so it does not block the run. Not fixed.
  - Smallest fix: take the candidate timeout as `remaining − margin`, a
    collection margin of a few seconds. That is a Mo change with regenerated
    verified lines. It is the same family as review item M4.
- **D2. After a client disconnect, the operator can no longer freeze or
  verify.**
  - When the agent gives up on a call, the frontend sees the disconnect
    (`bridge.py:226`, `_end('observed_disconnect')`). `_end` closes `self.ipc`
    (`bridge.py:110`).
  - The operator's later `freeze()` goes through `_operator` (`bridge.py:294`)
    on that closed socket and fails with
    `OSError: [Errno 9] Bad file descriptor`.
  - The owner still finishes and cleans up (`cleanup: confirmed`), but no
    protected verdict can be taken of that workspace.
  - Seen twice: `outer-deadline` in both runtimes.
  - It does not block this slice, because no negative case needs a verdict. But
    it means any real run that ends in a timed-out call loses its verdict. This
    is related to H3 and H6. Not fixed (executor source; not blocking).
- **H6 (seen differently).** In the deadline runs the disconnect was journalled
  as delivery `unknown`/`observed_disconnect`. The call result itself stayed the
  owner's true `completed`, so no `owner_unknown` appeared. A killed owner
  correctly produced `owner_unknown`.
- **Not hit:** H1 (file operations took 49 to 74 ms against a 2 s wait), H4 (no
  output over 64 KiB), H5 (every `read_file` success carried `text`).

## Decisions the brief did not cover

1. **Which owner.** The production `workspace_http.owner`, not the test
   `live_owner` that records raw transport, so the path is the one a real run
   uses. Dispatch timing and Book observation come from a test-side subclass of
   `Bridge` (`service.py`) that only wraps `_dispatch`.
2. **Verdict shape.** The accepted verifier has one script and checks on stdout
   or stderr, and requires exit 0. The script therefore prints one transcript
   and exits 0:
   - build statuses
   - each CLI case's stdout, real exit and stderr
   - the tests' real exit and full output
   - SHA-256s of `mo.root`, `.mo.ids`, parse/report/stats, the four fixture
     inputs, and Main from its first test to the end

   One exact check compares it with the transcript computed on the trusted side
   from the four goldens, the prepared tree and the host-built test output.
   stderr expectations for the two error cases are bound from the clean host
   build.

3. **The candidate's own command** builds and runs Main's tests only, because
   the goldens never enter the candidate. The CLI goldens are checked only by
   the verdict.
4. **The wrong-candidate control** is the test-tamper case (fault left, first
   test rewritten), because it is the one where the candidate's own feedback
   goes GREEN. The forged-success control is a written verdict file plus a
   command that prints success.
5. **The trees.**
   - "Repaired" is byte-identical to "normalized" (the receipt records
     `repaired_equals_normalized: true`).
   - "Clean" in readiness is the original tree with Main's footer intact.
   - The agent runs start from the faulty tree, whose footer was removed during
     preparation.
6. **"Service killed"** means the owner process holding the workspace was killed
   (`process.kill()` on the retained child), then the accepted cleanup-only
   recovery ran.
7. **Scope checks** do not include a file listing, so an extra file (the forged
   verdict file) is not itself a refusal reason. Behaviour and the scope hashes
   are.
8. **Imports.** The accepted scripted model (`fake_bridge.Model`), the guard
   wrapper (`common.invoke`) and the Book reader (`matrix.steps_in`) are
   imported from `../application-workspace-v1/` read-only, not copied.

## Attempts that failed (kept)

- `smoke-interpreter-01`: driver bugs only. The Book's step keys are
  `kind`/`name`, not `tool`. And the token scan compared `/var/...` against
  resolved `/private/var/...` paths, so it scanned the two private files. A
  direct scan showed the token only in those two files.
- `logstat-interpreter-01`: my `nine_steps` check applied to forged-success,
  which is 7 steps by design. Every other check, and both refusals, held.

## Limitations

- The model is scripted. This proves plumbing, not model ability or language
  value, and no live provider was involved.
- One machine, with sequential runs and no concurrency. Timings are
  single-sample per runtime.
- The Book-prefix observation is made at dispatch arrival from the driver's
  process (the frontend's `_dispatch`, the model's request). It reads the
  on-disk log, not the agent's memory.
- `inventory.py` IDs are gathered from the run directories under
  `$TMPDIR/mo-e2e-v1` plus `evidence/`. Deleting the tmp directories loses that
  input; the per-case `ownership.json` copies in `evidence/` keep the workspace
  IDs.
- The full `zig build test` suite was not run, per the brief. Only `zig build`
  ran.
- One orphan-looking `.zig-cache/o/*/test` process was seen at the end. It
  belongs to another worker (cwd `toolchain-step-41-exec`, live parent) and was
  left alone.

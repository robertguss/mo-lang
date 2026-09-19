# End to end v1: the Mo agent on the machine, and the scripted Logstat repair

Brief: `mo-wiki/plans/mo-harness-end-to-end-v1.md`. This run joins the pieces:
the Mo agent's `application-workspace` CLI (in `mo run` and as a `mo build`
binary), a scripted loopback model, the real workspace service (the accepted
`Bridge` frontend and production owner, application policy), real containers on
`mo-executor-r01`, and the protected verdict on the frozen snapshot. It tests
the plumbing only. It says nothing about model ability or the language's value,
and no live provider is involved.

## Files

| file              | what it is                                                                                                                                                                        |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `driver.py`       | The one command. `driver.py PART RUNTIME ATTEMPT [--only a,b]`.                                                                                                                   |
| `service.py`      | Starts the real service for one candidate; a test-side subclass notes each dispatch's arrival, the Book's on-disk step count at that moment, the produced reply and its time.     |
| `prepare.py`      | Logstat trees from HEAD bytes: clean, normalized (Main's footer removed), faulty (`top: 5` → `top: 1` at `main.mo:80`), repaired. Prints a receipt of SHA-256s.                   |
| `logstat_case.py` | The protected verifier script, its trusted expected transcript, and the candidate's own test command.                                                                             |
| `e2e.py`          | Paths; imports the accepted scripted model, guard wrapper and Book reader from `../application-workspace-v1/` read-only.                                                          |
| `evidence/`       | `ATTEMPT.jsonl` rows (real exit codes, summaries, per-call observations, timings), small per-case files (Book log, service journal, ownership receipt, report), `guard/` records. |

Prepared trees, service directories (private token files) and native builds live
outside the repository, under `$TMPDIR/mo-e2e-v1/ATTEMPT/` (override with
`MO_E2E_WORK`). No `.mo` file is ever written under `examples/`.

## Rerun

From the repository root, with `toolchain/zig-out/bin/mo` built
(`cd toolchain && python3 bench/step36/guard.py 1200 -- zig build`) and the
machine released. Every attempt name must be new.

```sh
T=examples/programs/agent/tests/end-to-end-v1
G="python3 toolchain/harness/executor/guarded.py"
$G 1500 $T/evidence/guard/NAME -- python3 -B $T/driver.py readiness none NAME      # clean/faulty/repaired verdicts, no agent
$G 900  $T/evidence/guard/NAME -- python3 -B $T/driver.py smoke interpreter NAME
$G 1500 $T/evidence/guard/NAME -- python3 -B $T/driver.py smoke native NAME         # builds the agent first
$G 1800 $T/evidence/guard/NAME -- python3 -B $T/driver.py logstat interpreter NAME  # repair, forged-success, wrong-candidate
$G 1800 $T/evidence/guard/NAME -- python3 -B $T/driver.py logstat native NAME
$G 1200 $T/evidence/guard/NAME -- python3 -B $T/driver.py negatives RUNTIME NAME --only service-killed,candidate-limit
$G 1300 $T/evidence/guard/NAME -- python3 -B $T/driver.py negatives RUNTIME NAME --only outer-deadline   # about 15 minutes
python3 toolchain/harness/executor/inventory.py NEW_DIR $TMPDIR/mo-e2e-v1 $T/evidence   # read-only; exits 1 if anything is left
```

Each case records admission, execution, reply (produced by the service versus
received in the Book) and cleanup per tool call, from the service journal and
the Book separately, and never folds them into one success count.

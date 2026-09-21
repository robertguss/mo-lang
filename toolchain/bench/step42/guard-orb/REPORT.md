# Step 42 part E: orb guard recovery

## Provenance and race review

- Base: `origin/main` at `9111bb705d21f7e2ebb4309bd13e55ec6833bb38`.
- Recovered reference: `origin/toolchain/step-42-memory` at
  `0a4dffcd460a4f47ac925c6d2fb13c7e081a14ce`. Its historical `guard_test.py`,
  RED/GREEN logs, and guard diff were inspected without changing them.
- The recovered implementation created a dedicated session, used `killpg` for
  timeout/RSS/forwarded signals, and killed remaining group members after a
  forwarded signal. New bounded controls confirm those four paths.
- The recovered implementation did not clean the group when the leader exited
  naturally or from a non-forwarded signal. In both controls, the leader's exit
  status was correct but its signal-ignoring descendant remained alive. A
  process group remains addressable after its leader exits while another member
  exists, so unconditional post-`wait` `SIGKILL` is the smallest closure of that
  race.

The candidate starts the direct child in a new session, sends timeout, RSS,
TERM, and INT signals to that process group, and performs a final group kill
after every leader exit. It still reports the direct child's exit status: normal
status unchanged, or `128 + signal` for signal death. The final kill does not
replace or rewrite that recorded status.

The corrected candidate also installs TERM/INT handlers before `Popen`. A signal
received before the child handle is available is queued and forwarded as soon as
`Popen` returns. This closes the startup interval in which the guard could die
after its newly sessioned child existed but before forwarding was possible.

## Controls

`guard_regression.py` owns and bounds every process it starts. Each case records
the direct child and descendant PIDs, imposes an 8-second harness deadline,
verifies that the child leads a dedicated process group, checks both child and
descendant are not live, verifies a separately sessioned unrelated process is
still live, and independently kills any live test processes so the broken
baseline is safe to test. Zombie state counts as not live; these controls do not
claim that a PID is absent. The descendant acknowledges readiness only after
installing both ignore handlers. The child publishes final readiness only after
that acknowledgment and after installing its SIGINT disposition.

The RSS case injects a temporary fake `ps` through `PATH`; only the guard's
`ps -o rss=` query returns 4,194,305 KiB, and only after payload readiness. This
exercises the production `rss > 4 << 30` kill branch without allocating 4 GiB.
It does not alter the guard or its CLI.

The startup controls inject `sitecustomize` through `PYTHONPATH` into the guard
test process. Its `Popen` wrapper calls the real `Popen`, waits for payload
readiness, publishes proof that the child exists, and then withholds the child
handle from `guard.py`. The harness sends TERM or INT during that deterministic
hold, then releases the return. This is a test-only seam; production code and
CLI have no hook.

Every case uses one absolute 8-second deadline for startup, readiness, guard
wait, inspection, and owned-process cleanup; the ordinary not-live observation
window is the smaller of one second and the remaining case deadline. The suite
has a separate final cleanup of its unrelated control process, bounded by two
seconds. Cleanup is an outer `finally`, re-reads every available PID record, and
runs even if readiness or process inspection fails. The forced-`ps`-timeout case
proves both owned test processes are not live afterward.

| Control              | Exit | Result                                                    | Raw output                                                |
| -------------------- | ---: | --------------------------------------------------------- | --------------------------------------------------------- |
| `origin/main`        |    1 | RED, 0/6; every descendant survived                       | `main-red.log`, `main-red.exit`                           |
| recovered `0a4dffcd` |    1 | RED, 4/6; natural/signal leader-exit descendants survived | `recovered-wip-control.log`, `recovered-wip-control.exit` |
| candidate            |    0 | GREEN, 6/6                                                | `candidate-green.log`, `candidate-green.exit`             |
| syntax parse         |    0 | guard and regression script parse                         | `syntax-check.log`, `syntax-check.exit`                   |

The preceding files are immutable first-pass evidence. Corrected synchronized
evidence is separate:

| Control                           | Exit | Result     | Raw output                                  |
| --------------------------------- | ---: | ---------- | ------------------------------------------- |
| synchronized `origin/main`        |    1 | RED, 0/6   | `synchronized-main-red.log`, `.exit`        |
| synchronized recovered `0a4dffcd` |    1 | RED, 4/6   | `synchronized-wip-red.log`, `.exit`         |
| synchronized corrected candidate  |    0 | GREEN, 6/6 | `synchronized-candidate-green.log`, `.exit` |
| startup `origin/main`             |    1 | RED, 0/2   | `startup-main-red.log`, `.exit`             |
| startup recovered `0a4dffcd`      |    1 | RED, 0/2   | `startup-wip-red.log`, `.exit`              |
| startup corrected candidate       |    0 | GREEN, 2/2 | `startup-candidate-green.log`, `.exit`      |
| forced inspection timeout cleanup |    0 | GREEN, 1/1 | `harness-failure-green.log`, `.exit`        |
| corrected syntax parse            |    0 | GREEN, 2/2 | `synchronized-syntax.log`, `.exit`          |

Commands (run from repository root):

```sh
git show origin/main:toolchain/bench/step36/guard.py > /tmp/step42-guard-main/guard.py
python3 toolchain/bench/step42/guard-orb/guard_regression.py --guard /tmp/step42-guard-main/guard.py

git show 0a4dffcd460a4f47ac925c6d2fb13c7e081a14ce:toolchain/bench/step36/guard.py > /tmp/step42-guard-recovered/guard.py
python3 toolchain/bench/step42/guard-orb/guard_regression.py --guard /tmp/step42-guard-recovered/guard.py

python3 toolchain/bench/step42/guard-orb/guard_regression.py --guard toolchain/bench/step36/guard.py --mode core
python3 toolchain/bench/step42/guard-orb/guard_regression.py --guard toolchain/bench/step36/guard.py --mode startup
python3 toolchain/bench/step42/guard-orb/guard_regression.py --guard toolchain/bench/step36/guard.py --mode harness-failure
```

Each filed run used `set -o pipefail`, piped combined output through `tee`, and
wrote `${PIPESTATUS[0]}` to the adjacent `.exit` file.

## Limits

- The 4 GiB watchdog still measures only the direct child RSS. It is explicitly
  **not aggregate process-tree memory accounting**.
- Process-group ownership cannot contain a descendant that deliberately escapes
  into another session/process group. The regression descendant does not escape;
  it tests the intended inherited-group ownership.
- TERM/INT are forwarded first. If the direct child ignores them, the guard
  continues until its configured timeout or RSS limit; final cleanup occurs when
  the direct child exits.
- Linux orb evidence only. No Zig build, full suite, runtime benchmark, or
  Darwin-specific check was run under this guard-only assignment.

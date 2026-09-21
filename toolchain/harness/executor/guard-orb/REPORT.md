# In-process guarded-wrapper repair

## Design finding and repair

At base `1839785eead517324e63232dc2261a5be8882dc2`, `guarded.py` started a
standalone guard in process group G, and that accepted guard started the payload
in process group P. Overflow and wrapper-signal cleanup killed G, then inspected
only G. Killing the cleanup supervisor could therefore leave P alive while the
wrapper reported `group_absent: true`.

The repair makes `guard.py` import-safe and exposes its one supervision core.
The standalone CLI remains a thin caller. `guarded.py` imports that core in
process, so the recording wrapper now owns one payload `Popen` and group P.
There is no second watchdog or duplicated cleanup implementation.

The core installs TERM/INT handlers before `Popen`, queues startup signals,
forwards them to P, and optionally starts one two-second escalation deadline.
Repeated signals do not reset that deadline. Timeout, direct-child RSS over 4
GiB, outer deadline, output overflow, probe failure, and every leader exit all
converge on final group `SIGKILL`, bounded leader reaping, and bounded group
inspection. The RSS value remains the direct child's RSS, not aggregate tree
memory.

`exit.json` retains `child_returncode` and normalized `child_exit` independently
from wrapper policy and its underlying `reason`. Overflow and outer deadline map
to 124 only when cleanup is confirmed. Unknown/failed supervision or cleanup
maps to 125 and wins over policy. Group inspection reports `absent`, zombie-only
`not_live`, `live`, or `unknown`; only the first sets literal `group_absent`.

## Controls

The baseline control checks the immutable base wrapper. Its finite binary
overflow payload had a signal-ignoring same-group descendant. Before harness
fallback cleanup both payload and descendant were live, output continued to
grow, yet the wrapper had already returned 124 and reported the wrong group
absent: `0/1`, expected RED (`baseline-overflow-red.log`, exit 1).

The candidate wrapper controls cover natural 0, nonzero 23, explicit 137, signal
exit 138, responsive TERM/INT, repeated TERM against an ignoring group,
held-`Popen` startup TERM/INT, outer deadline, finite overflow plus sleep, fast
binary overflow after leader exit, hanging RSS probe, timeout/nonzero/persistent
cleanup probes, zombie-only group reporting, cwd/HOME recording, and a forced
harness probe timeout whose `finally` cleans the observed group. Each case
checks pre-fallback liveness, the dedicated group, output stability after
cleanup, the unrelated sentinel, and a 12-second wall deadline.

| Run                              | Result       | Timing/status highlights                                                                 | Raw files                             |
| -------------------------------- | ------------ | ---------------------------------------------------------------------------------------- | ------------------------------------- |
| Extracted base overflow          | RED, 0/1     | wrapper returned in 0.84 s with payload and descendant live; output unstable             | `baseline-overflow-red.log`, `.exit`  |
| Candidate wrapper                | GREEN, 19/19 | ordinary 0.52–0.62 s; repeated-signal escalation 2.68 s; persistent-group failure 3.54 s | `candidate-final.log`, `.exit`        |
| Accepted direct core             | GREEN, 6/6   | timeout 0.77 s; RSS 0.27 s                                                               | `direct-core.log`, `.exit`            |
| Accepted direct startup          | GREEN, 2/2   | TERM/INT 0.29 s each                                                                     | `direct-startup.log`, `.exit`         |
| Accepted harness-failure cleanup | GREEN, 1/1   | forced probe failure 0.15 s                                                              | `direct-harness-failure.log`, `.exit` |
| Syntax parse                     | GREEN        | four Python sources parsed                                                               | `syntax.log`, `.exit`                 |

All filed commands used `set -o pipefail`, combined output through `tee`, and
wrote `${PIPESTATUS[0]}` to the adjacent exit file. The baseline ran the wrapper
from a detached worktree at the named base; candidate payload/control code came
from this tree.

## Bounds and limitations

- Supervision polls at 0.1 seconds. Each `ps` probe is capped at 0.5 seconds,
  leader reaping at two seconds, and group cleanup observation at three seconds.
  Wrapper TERM/INT escalation is two seconds. The outer fallback is
  `SECONDS + 5`; its branch control advances the wrapper's monotonic test clock,
  so its 0.57-second wall time is branch proof, not real-time `SECONDS + 5`
  evidence.
- The 16 MiB value is a trigger, not a hard retained cap. Polling and concurrent
  writes produced 17,825,792–17,825,900-byte retained logs. Both were stable
  0.25 seconds after wrapper cleanup; the fast case retained child exit 0 while
  wrapper policy returned 124.
- A successful `ps` snapshot proves group state at that instant. A timed-out or
  nonzero probe is `unknown`/125. Zombie-only rows are cleanup-confirmed but not
  literal absence. Deliberate `setsid` escape remains outside process-group
  containment.
- Linux orb evidence only. No Zig, server, runtime, memory benchmark, full
  suite, or Darwin-specific check was run.

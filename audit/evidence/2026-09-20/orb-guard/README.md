# Independent Linux guard acceptance

Lead verification in `/tmp/mo-lead-orb-baseline`, branch
`lead/verify-orb-baseline`. Worker
source7939578ea7b589e1af5ef67f77b3964115b27cdd; production and harness bytes
match tested4f36e065 exactly. Final worker commit corrects report timing prose
only. Oracle reviewed both source iterations; the startup signal window,
unsynchronized readiness and cleanup findings were corrected before acceptance.
Main merge70c07d3208a302dd0d4612157f9d400252def229.

These are independent lead executions, not copied worker results. Each log has
an adjacent actual exit file. Commands ran from the verification root:
`python3 toolchain/bench/step42/guard-orb/guard_regression.py --guard PATH --mode MODE`.
Main and WIP guard files were extracted unchanged with `git show` from 9111bb70
and0a4dffcd into `/tmp/mo-guard-lead-controls/{main,wip}.py`.

| mode/revision             | observed summary | exit |
| ------------------------- | ---------------- | ---- |
| core/main                 | 0/6              | 1    |
| core/WIP                  | 4/6              | 1    |
| core/candidate            | 6/6              | 0    |
| startup/main              | 0/2              | 1    |
| startup/WIP               | 0/2              | 1    |
| startup/candidate         | 2/2              | 0    |
| harness-failure/candidate | 1/1              | 0    |

The REDs are expected failures retained as controls. Candidate checks establish
no live child/descendant at post-exit observation and an unrelated live control.
Zombie PIDs may remain pending reaping. RSS injection tests the real threshold
branch, not real allocation of4GiB. Extra direct commands through the guard
preserved `/bin/true` exit0 and `/bin/sh -c 'exit 23'` exit23 (shell transcript,
not separately filed logs).

Acceptance is guard-only on Linux, not whole Step42: startup TERM/INT
forwarding, timeout/RSS group termination, final group cleanup after
natural/signal leader exit and direct-child status preservation. RSS accounting
is direct-child only; descendants deliberately escaping the process group are
not contained. A direct child ignoring forwarded TERM/INT remains bounded by
timeout/RSS. Reported8s is a working deadline/pass threshold, with separately
bounded process probes and cleanup, not a strict total runtime guarantee.

The compiler/native baseline follows separately under `../orb-baseline/`. No
Darwin result, machine containment claim or CI gate follows from this work.

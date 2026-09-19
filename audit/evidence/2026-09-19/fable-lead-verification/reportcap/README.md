# The report cap and the collection margin, lead verification (3:06 PM ET)

Branch `lead/verify-reportcap` at `78b093f3` (`main` plus the worker's
`agent/report-cap` at `1784d930`, base `90add2f3`), pushed.

- Darwin full suite, detached under `guard.py 2400`, load average above 12
  (another worker and the machine run beside it): `Build Summary: 5/5 steps
  succeeded; 263/263 tests passed`, `run test 263 pass (263 total) 19m
  MaxRSS:463M`, exit 0 (`darwin-full-suite.log`, `exits.txt`).
- On the machine, the end-to-end `outer-deadline` case, native
  (`examples/programs/agent/tests/end-to-end-v1/evidence/lead-deadline-native-02*`),
  exit 0, no failed check. Before the fix the last clamped command was always
  `transport_timeout`, execution unknown. Now step 16 was sent `timeout_ms`
  35838, the service answered after 36,585 ms, the Book received exactly the
  reply the owner produced, execution `completed` on both sides, container and
  cgroup proved absent; the run ended `over_budget`/`steps` at 881 s, inside
  the 900 s bound. Inventory after it: `{"runs": 83, "workspaces": 58,
  "cgroups": 65, "clean": true}`.
- The Linux full suite on the VM at `e3736f7d` was still running at acceptance;
  the change is Mo source in the agent only. Its result is added below.

## The Linux full suite (3:07 PM ET)

On the VM at `e3736f7d`: `Build Summary: 5/5 steps succeeded; 263/263 tests
passed`, `run test 263 pass (263 total) 20m MaxRSS:467M`, exit 0
(`linux-full-suite.log`, `linux-exits.txt`).

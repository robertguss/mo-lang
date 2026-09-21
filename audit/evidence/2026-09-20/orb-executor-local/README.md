# Provider-independent Linux executor checks

Lead runs at the revision in revision.txt, with the accepted direct guard. Each
command ran from the repository root under /usr/bin/time -p, pipefail, tee, and
an adjacent exit file recording PIPESTATUS[0]. No wrapper was used:
executor/guarded.py has a separately reviewed payload-ownership defect.

| command after python3 toolchain/bench/step36/guard.py                | result              | seconds |
| -------------------------------------------------------------------- | ------------------- | ------- |
| 180 -- python3 -B toolchain/harness/executor/recovery/local_suite.py | 71 tests, OK, exit0 | 6.94    |
| 600 -- python3 -B toolchain/harness/executor/test_cases.py           | 14 tests, OK, exit0 | 7.53    |
| 180 -- python3 -B toolchain/harness/executor/workspace_http/local.py | 22 tests, OK, exit0 | 29.49   |

These are local logic, filesystem and subprocess-double checks. They do not
establish container isolation, CPU throttling, resource enforcement or a live
machine boundary. No production adapter or policy changed.

environment.txt records read-only observations: x86_64 Linux, Docker executable
but no socket, no orbctl or Clang on PATH, systemd252. Its last two lines are
the workload slice's cgroup.controllers and cgroup.subtree_control: CPU is
available in its parent but not delegated to workload scopes. No controller,
daemon or shared ancestor was modified. The application package pins an aarch64
Zig archive and historical Mo artifact; x86_64 replacement identities and an
owned execution target remain prerequisites.

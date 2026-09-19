# Credential-free executor feasibility — 18 Sep 2026 ET

Lead-owned exploratory probes, not a sealed suite, independent audit reading, Mo
harness acceptance or production-security claim. Robert authorized each
escalation: read-only inspection, temporary privileged Docker, then reversible
CPU-controller setup. No implementation worker, OAuth login or external service.

Source: https://ampcode.com/threads/T-01a0b649-dbdd-7299-b541-d4c48f1aecf4.
Repository base: `df87bba67240dbcca72f31e310609dee0daebf70` on local/origin
main. Environment: Linux x86_64 Amp E2B orb, Docker 29.8.1, runc 1.5.1, systemd
252, cgroup v2, installed static BusyBox 1.36.1. Not Robert's Mac.

## Raw files

- `probe.py`: final executed probe, retained byte-for-byte.
- `results.txt`: first run, exit 1; five PASS records, then PID observation
  failed because the container's init had already exited (`/proc/0/cgroup`).
- `results-2.txt`: second run, exit 1; eight PASS records, then the host-side
  attach client timed out while its undrained output pipe was full.
- `results-3.txt`: final run, exit 0; nine PASS records, no cleanup-failure
  rows.

The first two script revisions were not retained separately. The final revision
keeps the PID fixture's init alive while a child reaches the process limit, and
drains/discards output in bounded chunks after stopping the producer. Earlier
failures are probe defects/limitations, not hidden successful runs. Exit codes
above are from the shell tool; the text files contain merged output, not
separate machine-written exit-status records. The pipeline used `pipefail`.

## Setup used, recorded from the lead transcript

These are reconstruction instructions, **not a portable installer**. Do not run
the privileged Amp-specific setup on the Mac or an existing Docker daemon.
Verify the destination and obtain scoped setup approval first.

1. Created private `/tmp/mo-executor-feasibility` (0700) and `daemon.json` with
   `{}`. An initial `/dev/null` config attempt was replaced before any tests.
2. Started `mo-executor-probe` through `amp orb service start`, cwd the private
   directory, with the following foreground command (no portal):

```sh
sudo -n dockerd --config-file /tmp/mo-executor-feasibility/daemon.json \
  --host unix:///tmp/mo-executor-feasibility/docker.sock --group root \
  --data-root /tmp/mo-executor-feasibility/data \
  --exec-root /tmp/mo-executor-feasibility/exec \
  --pidfile /tmp/mo-executor-feasibility/docker.pid --storage-driver vfs \
  --bridge none --iptables=false --ip6tables=false --ip-forward=false \
  --ip-masq=false --exec-opt native.cgroupdriver=cgroupfs \
  --cgroup-parent /amp.slice/amp-workload.slice/mo-executor-probe
```

3. `sudo -n systemctl set-property --runtime amp-svc-mo-executor-probe.service CPUQuota=100%`
   enabled ancestor CPU control. This limits the temporary daemon service, not
   its sibling container cgroup; each container separately requests
   `--cpus=.25`. No existing workload numeric limit was changed.
4. Imported an offline rootfs tar: installed `/usr/bin/busybox` copied to
   `bin/busybox`, `bin/sh` symlinked to `busybox`, empty `work`, `reference`,
   `tmp` directories. Image `mo-executor-fixture:local`; no registry access.
   Created host files `reference` (`DUMMY-REFERENCE\n`) and `sentinel`
   (`DUMMY-SECRET\n`), both 0644; these are not credentials.
5. Ran `python3 /tmp/mo-executor-feasibility/probe.py` with `2>&1 | tee` and
   `set -o pipefail`; outputs above. The script owns and removes named test
   containers in `finally`. No Mo/compiler tests were run.

BusyBox SHA-256:
`d7cce939adb09a41a22a5f846d22ba8d576b38dbb2b46a5c77a3a3e27ec52520`. Image ID:
`sha256:7a68968d5d87e4cedc7e779f3b0047f456a963e49116d71af27471cb4c91898f`. Final
script SHA-256:
`20e42abb1e47d224926a2fb6043e627bfc4fab350c3e1a3c3c7d53bee153a7a5`.

## Observations and limits

The final run checked effective `cpu.max=25000 100000`, `memory.max=33554432`,
`memory.swap.max=0`, `pids.max=16`; measured actual CPU throttling; triggered
OOM exit 137 with `OOMKilled=true`; observed the PID ceiling's rejection event;
filled 8 MiB scratch with a finite 12 MiB write; stopped three processes
including a new-session child after a controller deadline; retained 4096 output
bytes and stopped/drained a finite 1 MiB producer. Other assertions are in
`probe.py`.

Network evidence is loopback-only interfaces, no IPv4 route and a failed
TEST-NET connection, not an exhaustive network attack suite. Filesystem checks
include a writable positive control and read-only reference, but root write
denial is also explained by non-root permissions; Docker was configured with
read-only root, not independently challenged by a privileged writer. Seccomp
mode and dropped capabilities were observed, not exhaustively tested. Output and
wall bounds are enforced by the Python probe/controller, not by Docker alone or
by a Mo implementation. No hostile-kernel, secret-exfiltration,
protected-verdict, stale-artifact or production lifecycle guarantee was tested.

The container uses the orb's kernel; outer VM isolation is not inner isolation
between candidate code and trusted credentials/controllers. The daemon socket
was never mounted in candidates. Existing real secret files were not inspected.

## Teardown and lesson

Docker/runc also enabled cpuset/io/hugetlb controllers in ancestors. This was
detected after execution, not pre-approved as a production setup. Do not adopt
the sibling cgroup path as the final executor design; own a dedicated delegated
subtree and test supervisor-failure cleanup before acceptance.

Lead terminal checks confirmed no containers, stopped Amp service, absent
socket, no temporary mounts, and removal of the empty project cgroup. The
transient systemd unit became `not-found`. An attempted `CPUQuota=infinity`
reset was invalid; a later empty reset found the already-removed unit. Neither
changed existing workload limits. Introduced controllers were then disabled
bottom-up, restoring the exact original sets:

| cgroup             | restored subtree controllers |
| ------------------ | ---------------------------- |
| root               | cpuset cpu io memory pids    |
| amp.slice          | cpu io memory pids           |
| amp-workload.slice | memory pids                  |

Unchanged workload properties: CPUWeight 50, CPU quota infinity, MemoryHigh
31138512896, MemoryMax 31675383808, TasksMax infinity. These teardown
observations are transcribed from tool output, not a separate raw capture in
this bundle. Final probe/results were copied here before deleting the temporary
daemon/image and fixture directory. No service or privileged configuration
remains from this probe. No claim is made about uninspected unrelated processes
or services.

Robert subsequently chose to move the lead to his Mac with OrbStack. The current
handoff and harness brief govern next work. This bundle is evidence to inspect,
not permission to repeat privileged setup, launch workers or authenticate.

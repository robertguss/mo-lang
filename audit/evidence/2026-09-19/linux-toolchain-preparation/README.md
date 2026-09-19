# Linux Zig archive preparation — 19 Sep 2026

The lead downloaded the official aarch64 Linux Zig 0.16.0 archive to a private
temporary directory using `download.py` under a 180-second guard in owned Herdr
pane w4:p12. `download.exit` is 0. The pane closed after the shell returned.

`archive.json` records the temporary path, exact URL, 51,211,944 bytes and SHA-256
verified against the fetched official index and the independently read value:
`ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17`.
`download-commands.json` retains both curl commands and actual results.
Source: <https://ziglang.org/download/index.json>.

The archive-only statement above describes the initial download checkpoint.
Subsequent trusted build attempts are recorded below.

## Trusted builds, 19 Sep 2026, 1:45 AM ET

`install-build.py` installed verified Zig and exact source e3a01bb in the
isolated machine. Native j2 hit 1.5 GiB OOM; cleanup then addressed an already
removed unit and returned nonzero. `install-build-01/` retains both failures.
`build-retry.py` retried j1 at the same limits: CPU 150%, memory 1536M, 128 tasks,
private network, systemd RuntimeMaxSec 900, control-group kill. It hit the
900-second deadline, exit 1. `build-02/final-state.stdout.txt` proves build units
and Zig processes absent; host child groups are empty. Machine ownership was
then released to workspace tests. No candidate policy limits were increased.

`cross-build.py` extracted the identical trusted source tar into a fresh Mac
temporary directory with its own Zig cache and ran `zig build -j1
-Dtarget=aarch64-linux-musl` under guard 900, an outer guard and a 4 GiB
process-group RSS monitor. `cross-build-01/result.json` records the exact command,
source and output paths: exit 0, 43 seconds, peak RSS 3,353,706,496 bytes,
no owned descendants. Binary SHA-256 is
`4d14520aaf25403396e14501efbab2f5cd3d7f29bba4ad7c124155c06c806c72`,
15,923,616 bytes. It has not been transferred or executed in Linux.

Commands and actual stdout/stderr/exits are retained per attempt. These are
trusted compiler preparation results, not candidate or application acceptance.
No compiler sources were edited. Linux execution is the next distinct check
once the workspace worker releases the machine with positive cleanup.

## Trusted Linux runtime verification, 19 Sep 2026, 1:47 AM ET

After workspace worker release, `runtime-smoke.py` transferred the cross-built
ELF, checked its full SHA-256 again, and installed it at
`/opt/mo-harness/bin/mo-e3a01bb-aarch64-linux-musl`. Exact e3a01bb guard.py was
transferred separately with a recorded hash; no hand-written compiler source.
The source tree remains the same archived e3a01bb baseline.

`runtime-smoke-01/` passed all seven commands: Model's 3 tests, versioned and
generic conformance checks, driver check, native driver build, and nine HTTP
auth cases in each runtime. Both matrices have counts 1,2,2,2,3,1,0,1,1 and all
18 listeners close. All 248 scanned Mo/IDs/Zig source files remain byte-identical.
Service runtime 47.639 seconds, native driver build 37.54 seconds. The service's
reported 512 KiB memory peak is not credible compiler-sizing evidence; no new
candidate resource policy is inferred from it.

The independent systemd service used private network, 600-second RuntimeMaxSec,
1536M memory, 150% CPU, 128 tasks and control-group cleanup. Unit/cgroup and owned
host process groups are confirmed absent. Transfer, identity, runtime and cleanup
exit 0. This establishes trusted Linux interpreter/native execution for these
checks. It does not turn the two failed native bootstrap builds into successes,
or establish candidate Mo application execution under the BusyBox policy.

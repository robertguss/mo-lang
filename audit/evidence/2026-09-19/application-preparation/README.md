# Application machine readiness and parent provisioning

Lead reading: open after your own source reading. Inspection and provisioning
are prerequisites, not application acceptance. inspect.py and provision.py
ran under 120-second outer/90-second transport guards in owned lead pane.
Both attempts exit 0, no remaining local process groups. Remote commands use
explicit mo-executor-r01, never the shared Mac Docker daemon.

inspect-01 observed no dedicated Docker containers, one pinned BusyBox image,
exact trusted Mo hash and Zig 0.16, empty old 512MiB parent. Guest free/df report
shared VM totals, so provision-01 separately reads outer cgroup memory.max 2GiB,
swap.max 0 and CPU 2. It creates only /etc/systemd/system/mo-application.slice,
then reloads/starts and reads exact memory 1536MiB, swap 0, CPU 1 and 192 tasks.
The previous executor configuration is byte-identical and its512MiB cap remains.
No candidate ran. Existing old memory.events OOM counters are historical.

Configuration SHA256 ab7ea2ac24e3248cc436348ea11251db3d650c160bf443907b16bda6e1e00702.
New parent was empty and the machine idle at explicit release to the fresh
application worker at 2:28 AM ET. That worker has exclusive bounded test ownership
until its final cleanup/release. Keep the new capped parent for lead acceptance;
no global resource setting, Docker daemon configuration or existing opt input
was changed. Worker may use only new application-build-v1 staging/task resources.

provision.py deliberately refuses an existing configuration; do not replay it
blindly. Its immutable remote.py/status records provide exact input and output.
Original Zig archive was rehashed read-only before release:
/private/tmp/mo-linux-toolchain-bcqwt2vz/zig-aarch64-linux-0.16.0.tar.xz,
SHA256 ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17.

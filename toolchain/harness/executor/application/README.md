# Isolated application build v1

Worker base: `5e5682274d0d02ac5532f07a075c11a8e52345e3`, branch
`harness/application-build-v1`. This is a bounded implementation of
`mo-wiki/plans/mo-application-build-v1.md`. No repair mutation, provider call,
compiler change or language-value claim belongs to this slice.

`Workspace(..., policy='application-build-v1', image='sha256:<image-content-id>',
toolchain='<sha256-of-package-manifest>')` selects the application policy at
creation. Registration fixes all three values; reservation and authorization
reject mismatches. Commands cannot supply an alternate policy. Default callers
keep the existing BusyBox image, policy, limits and parent.

The application policy uses 1 GiB RAM and memory+swap, one CPU, 128 PIDs,
120-second maximum, 64 KiB combined output, readonly image, UID/GID 65534,
network none, no capabilities, no-new-privileges and the separate
`mo-application.slice`. Each candidate gets empty executable `/build` (512 MiB,
16384 inodes, nosuid/nodev), and noexec `/tmp` (16 MiB, nosuid/nodev). Existing
64 MiB/4096-inode noexec source workspace handling is reused. The same independent
deadline service and cleanup-proof-before-disarm lifecycle handles both policies.

The lead released the dedicated machine with an outer 2 GiB memory limit,
zero swap and two CPUs; the application parent is 1536 MiB, zero swap, one CPU
and 192 tasks. Guest `free` and `df` show shared underlying VM totals and are
not headroom evidence. The old 512 MiB parent is unchanged. No concurrent native
bootstrap is allowed. A failed application build must retain its evidence;
limits cannot be increased without lead release.

## Packaging

`package.py` checks the compiler length/hash and the original Zig archive hash,
then compares installed distribution bytes/modes to archive entries. It creates
a new context containing only the fixed Dockerfile and `toolchain/{mo,zig,lib}`.
The package manifest stays outside the candidate image and binds source,
archive, actual files, recipe and packaging script. The resulting immutable
Docker image ID, not a tag, is passed to workspace creation.

`build_image.py ATTEMPT ARCHIVE` is explicitly machine-gated: upload into a new
owned `/opt/mo-harness/application-build-v1/<attempt>` subtree, package and build
offline under a systemd service with a 600-second deadline and released resource
limits, retain image ID/manifest, and stop the service. No download or compiler
source checkout is needed in the image. Image assembly has no RUN instruction;
Docker daemon work remains outside the caller service cgroup, within the verified
outer machine boundary. Do not interpret caller-service peak as whole-build peak.

## Controls and evidence

All Python/Mo/Zig checks run in the owned right/no-focus Herdr pane via
`executor/guarded.py SECONDS NEW_ATTEMPT -- COMMAND...` (maximum 1800 seconds), which
wraps the repository numeric guard, kills its process group and records remaining
processes. It preserves command, the child's real exit, elapsed time, output, HEAD
and dirty paths. Use a new attempt directory for every run, including failed
attempts. `executor/inventory.py NEW_DIRECTORY EVIDENCE...` is the read-only
machine cleanup proof after a machine run.

Local policy tests: `python3 -B toolchain/harness/executor/application/test_policy.py`.
Existing local controls: `python3 -B -m unittest discover -s toolchain/harness/executor -p 'test_*.py'`.
Live application controls: `controls.py NEW_DIRECTORY --image SHA256_ID --toolchain HASH`.
Its 23 fixed names are in `CONTROLS`; offline image-content verification is the
24th application control group. `--controls` accepts only a nonempty unique
selection. This selection is recorded before work begins. Local checks are not
application build proof. Existing workspace22, executor17 and lifecycle controls
must also be rerun after machine release.

The tiny program and Logstat are archived from
`e6f04ce6358c85f22a86f26be0b5b388495fcc6e` into ignored `.cache/` only. All source
bytes are exact. `.mo.ids` retains the exact five matching records from the
aggregate JSON, serialized as a subset to fit the 64 KiB file bound. Receipts
record the original aggregate hash, selected paths and imported bytes. Goldens
stay with the trusted controller. Compile from `/build`; run Logstat from
`/workspace/logstat`. Readonly snapshot verification independently rebuilds in
fresh scratch and binds nonempty source/check inventories, image and toolchain.

All completion claims, actual source identities, known failures, resource
observations, cleanup and final immutable commit IDs are recorded in the worker
report when verification finishes. The lead independently reviews and accepts.

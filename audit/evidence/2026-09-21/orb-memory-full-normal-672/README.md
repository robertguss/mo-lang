# Exact integration full NORMAL310

Integration7dcf48acabaf4b5623021baeb08d0de132943003, source
672b1b54aa799ebc38a915d62f8eaa350ecb7d9d on accepted
7ee9edc2cca78578ffa29d313a0ac1b3cdc64547. Validator:
https://ampcode.com/threads/T-01a0c217-68f4-70c6-84b5-8283e6125331. Adjacent raw
command/environment, logs/exit, identity, inventory and cleanup receipts
describe the one authorized full-normal run.

Lead/Oracle independently verified both archive hashes and manifests:

- Evidence e6b7c8c2cf9ab33b05b5093823f93e4d0208b3ce93b90a7873ad6510c8f0729a,
  validator
  .amp/transfer/672b1b54-full-normal/verification-672b1b54-full-normal-green.tar.gz,
  lead /tmp/verification-672b1b54-full-normal-green.tar.gz.
- Full nine-file capture archive
  c670137174c9ee416fc2d886859a3d0b041badf6fd719bc9a97e222e37918185, validator
  .amp/transfer/672b1b54-full-normal/large-restart-captures-672b1b54.tar.gz,
  lead /tmp/large-restart-captures-672b1b54.tar.gz.

Lead extractions: /tmp/mo-672-full-green/ and /tmp/mo-672-full-captures/.
Actual0/build5/5/tests310/310, no skips. Source inventory309 to310 includes
root's anonymous test; one new shutdown declaration explains the change.
Expected/interpreter/native restart stderr each90006894bytes,25reports, newline
EOF, SHAa879d3cf18a5c5544d1d4d348ff627647b8c8d09f160bcb6118f894eced19c28;
independent cmp equal. RSS increases61440/4317184bytes strictly below16MiB,
restarts25/kept1; completed/reaped/error-null metadata. Parcel9normal+9audit,
positive balanced allocations/live0; all8shutdown and4fiber results exact.
Expected16guard kills, two8/8 summaries and6parcel crash diagnostics preserved.
Outer formatter artifacts retained; final owned cleanup/scoped0/zombies0.

Lead reading (open after your own): recognize exact-integration normal coverage
only, not acceptance or comparable timing. Some child streams remain discarded
or incompletely asserted, so clean retained outer logs are not proof of all
descendant diagnostics. Next unit is source-only diagnostic-contract readiness
for generic/module, surface/crash-kept and build paths. No implementation or new
execution released. All seven acceptance obligations remain open.

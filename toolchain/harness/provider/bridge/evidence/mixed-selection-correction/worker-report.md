# Mixed Mo selection runner correction

GPT-6-Astra worker; exact parent `c17d65a561361e3daf707ef54aa5f2db4bbd43e6`.
Narrow scope: `bridge/run.py`, README and new evidence only. The immutable core
patch and every historical attempt remain unchanged. No machine operations,
package changes, live calls, push, rebase or other worker writes.

The runner validated `final,mo` but only provisioned the released Mo source and
selected its executable wrapper for the exact string `mo`. The retained red
`mixed-selection-red` passed `final`, then failed `mo` with ENOENT for
`bridge/release.json`; actual exit 1. It made one synthetic provider call and did
not execute Mo.

Both gates now check actual selected membership (`'mo' in selected`), preserving
`foundation` as a separate special case. The Mo-capable runner receives the
original selection rather than replacing it with `mo`. No control/library files
changed and no named control was added.

The retained green `mixed-selection-green` uses the same `final,mo` selection:
2/2 named controls, exit 0. The initial final control made one provider call.
The reserved Mo control ran interpreter and own compiled CLI variants; each
made two provider calls and one inert command, with three on-disk Book steps.
Provider order and disk/native history checks passed. Total: five synthetic
provider calls and two inert commands. Own CLI build and both runtime commands
exited 0. Node v24.20.0; Zig 0.16.0.

Accepted examples were archived from the already released exact commit
`e6f04ce6358c85f22a86f26be0b5b388495fcc6e`. Source archive SHA-256:
`f80c2a984c013892afd0a25904578e181b5823da538d702a13dd25f6d9b35de8`.
Approved compiler was copied read-only into owned ignored cache; SHA-256:
`acf1d5934260e4f55ca3f6d1b0bf998149f57bb0e2572c25a315ef4b3a12738a`.
Both fresh copies verified all 220 pinned runtime files. Exact commands, source
hashes, actual exits and observations are in the two attempt directories.

Both attempts used the owned right/no-focus run pane `w4:p1X`, outer 600-second
guards, shorter direct Node/process-group bounds and 120/60-second Mo guards.
Both outer process groups are absent. Green fixture sockets were zero; all bridge
listeners/socket cleanup assertions passed. Pane shell-idle and close receipts
and the final empty task-process scan are retained here. New evidence hashes and
byte count are in `manifest.json`; prior evidence manifests were not rewritten.

No broader regressions were rerun: this corrects only runner routing; the mixed
selection exercises both affected gates and preserves the selected order. Core
acceptance and integration remain the lead's decision.

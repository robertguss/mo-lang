Reviewed `08525c614b32b71b4f6101ecc93eb6e8f6d68797` against `90858791f441d125f0187a6751beffec6ef2312b` using local Git reads only. No tests, builds, remote operations, edits, or agents.

**1. Incomplete retained proof can produce confirmed cleanup — P2 validation defect.**

- **Lines:** `recovery/machine.py:118–125`, then `131–132,153–158`.
- **Trigger:** A valid receipt contains a dispatched execution whose execution directory is absent. Its matching terminal record contains `executions[eid] = {"host_confirmed": false}`. With empty container/unit inventories and no workspace mounts, that nonempty dictionary satisfies the proof-presence check.
- **Consequence:** Recovery records the execution as completed and returns `cleanup="confirmed"` without requiring positive cgroup or service cleanup evidence. The neighboring branches require all three proof flags to be exactly `True` at lines 101 and 108.
- **Smallest correction/control:** Apply that same three-flag validation before accepting either terminal or `completed_executions` proof. Extend `test_dispatched_missing_storage_requires_proof` (`test_recovery.py:178–186`) with nonempty proofs containing missing, false, and non-Boolean flags.
- **Boundary:** This is malformed **trusted operator state**, not candidate-controlled authority. Current normal proof producers validate these flags; I found no ordinary producer path generating this malformed record. The defect is the new recovery reader’s acceptance behavior.

**2. Remote result validation checks identities only — concrete acceptance gap; normal-path failure unproven.**

- **Lines:** `recovery/__init__.py:182–185`.
- **Trigger:** Transport returns matching workspace/run identities with, for example, `cleanup="confirmed"`, `execution="success"`, and unresolved execution IDs.
- **Consequence:** `result.update(response)` accepts and persists the contradictory result, including arbitrary error values or additional fields. This does not enforce the result contract described in `recovery/README.md:54–58`.
- **Smallest correction/control:** Validate allowed fields, statuses, bounded error codes, and completed/unresolved identities before merging; require `execution="unknown"` and no unresolved executions for confirmed cleanup. Add matching-identity malformed-response controls alongside the transport-timeout test.
- **Boundary:** The response comes from trusted installed code; the current machine implementation preserves `execution="unknown"`. This is not demonstrated candidate forgery or an observed production failure.

**Named-control evidence limitation:** `live.py:196–205` tests a foreign run ID only by asserting unresolved cleanup, then restores ownership and cleans up. It does not establish that foreign state remained untouched before refusal. The local counterpart (`test_recovery.py:159–167`) does check unchanged state and absent terminal. Add equivalent immediate assertions to the live control. Likewise, `malformed-linked` (`live.py:206–215`) exercises a receipt symlink specifically; its name should not be read as live coverage of every malformed-record boundary.

I found no substantiated candidate-authority escape in the inspected descriptor/path/selection checks. Trusted-record tampering and hypothetical path races alone do not establish one. Lifecycle ordering and interrupted cleanup were excluded as requested.

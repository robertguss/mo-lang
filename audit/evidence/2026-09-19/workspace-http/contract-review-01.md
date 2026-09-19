# Independent HTTP contract review

GPT-6-Astra low, read-only native Herdr worker p2A. Exact source68e50ed6;
session 01a0b8ce-2ad2-7500-8c8d-23aa23913a32. No implementation/tests/machine work.

Existing APIs support the separate owner **with contract corrections**:

- **Lease:** pre-dispatch clamping cannot prevent late execution; registration establishes a fresh deadline afterward. Define lease as admission expiry. Sources: plan:127–133; `workspace.py:178–198`; `adapter.py:149`.
- **Cleanup:** a serialized owner cannot begin cleanup while blocked inside `command()`. Expiry must request cleanup, with unresolved status until proved. Recovery cannot acquire the live owner’s lock. Sources: `workspace.py:209–237`; `recovery/__init__.py:105–130,177–192`.
- **IPC:** require bounded result delivery, outcome persistence before notification, and cleanup independent of frontend acknowledgments. Close inherited pipe duplicates; terminal admission must override late results. Plan:48–71 currently leaves this ordering unspecified.
- **Before effects:** “persist … result” before effects is impossible. Persist claims/intent beforehand, outcomes afterward. Existing recovery records already persist generated execution identity before reservation; no new core API is needed. Sources: plan:59–68; `workspace.py:187–191`; `recovery/__init__.py:139–147`.

Minimal design: one exclusive Workspace child, frontend admission/timers, bounded IPC, terminal cleanup after in-flight work, and explicit recovery after proved owner death. Neither cleanup nor execution has an unconditional wall-time guarantee (`application/HTTP-CONTRACT.md:54–69`). Recovery confirmation preserves original execution as unknown (`recovery/__init__.py:150–174`).

Verified the requested main HEAD. No files changed or tests/builds run.

Delivery via `herdr agent prompt w4:p1` failed with `PermissionDenied: Operation not permitted`; the report was **not delivered**. Idle.

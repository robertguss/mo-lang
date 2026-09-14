# Mo Lang

A programming language for the AI era, designed and built by Robert Guss and Claude. Start every session by invoking the `mo-lead` skill (`.claude/skills/mo-lead/SKILL.md`): it holds the roles, the worker loop in Herdr, and the acceptance checklist. Then read `HANDOFF.md` for the current state and queue, then `mo-wiki/SCHEMA.md` for the working agreements.

- The lead session directs, verifies, decides, and records. An Opus worker in Herdr pane `w3M:p2` (agent `mo-opus`, one fresh session per step) writes all code under `toolchain/` and `examples/`.
- Commit wiki work with `git add <paths>`, never `git add -A`: the worker shares the tree.
- Robert's decisions and the lead's are rows in `mo-wiki/decisions/decision-log.md`; he reviews the log, not the queue.
- Never use `tr` in shell commands (aliased on this machine); use python3.
- Install any tool a step needs without asking: Homebrew, `mise`, `uv` (`uv init` for Python projects), `go install`.

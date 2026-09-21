# Moscope declaration correction and authorized retry

Robert authorized fixing the prior parser error and retrying. Candidate
02727b71b085d39f5847bf1eef470cac3f3c292d, parent7aa1e81e, changes declaration
line wrapping only. Lead inspected exact diff; Oracle reviewed the correction
and unchanged-compiler reuse. No fixture/oracle/runtime edits.

One interpreter invocation under the accepted60-second guard, isolated checkout
/tmp/mo-moscope-02727b71. command.json records argv/environment/cwd; exit.json
records real exit1 and PGID661455 absent. Independent ps snapshot is empty.
smoke.stdout is0 bytes, smoke.stderr175 bytes: MO0101 expected a name at
model.mo:82:3 on `message: Message`. Accepted token.zig reserves `message`.
Search did not run. No further retry or build occurred; tracked worktree clean.

Reused first green build's binary SHA256:
3ef07d08ed6d0c802a2597bd956579873851855961cf2e5f01cf87018d273b78. Incremental
source bundle requires7aa1e81e (full parent bundle preserved in
../moscope-first-smoke/); SHA256:
04d477daec0d79d383010b4f34eee770a67cff64695fa16354e04e068fc4a426.

Split streams were redirected directly; wrapper output_bytes0 is not their size
and does not establish split-output budget enforcement. This is failed smoke
evidence, not acceptance or runtime safety evidence.

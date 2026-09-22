# Mo Lang — handoff, 22 Sep 2026, 4:15 PM ET

Start as `CLAUDE.md` says: the `mo-lead` skill, this page, `mo-wiki/SCHEMA.md`,
then the auditor inbox
(`git fetch origin && python3 audit/automation/fable_poll.py check`). This page
holds only the present. The full previous handoff (2,160 lines of checkpoints,
12–22 Sep) is `git show 0c51691c:HANDOFF.md`.

## Where things are

- **Purpose** (Robert, 21 Sep): to learn by creating his own language, useful to
  him and ideally to others, with or without adoption.
- **main** holds the toolchain (about 64k lines of Zig and C: checker,
  interpreter, C backend to static binaries, processes, contracts, simulator),
  209 `.mo` files, and the programs under `examples/programs/`.
- **Newest:** moscope v2, a CLI that searches Claude Code session histories,
  plus two runtime fixes it exposed: the native `Json.decode` use-after-free and
  `mo run` never freeing temporaries. Merged 22 Sep at eff64c56 after
  independent Darwin verification (full corpus 277/277). Evidence:
  `audit/evidence/2026-09-22/moscope-v2-verify/`.
- **Last full corpus:** Darwin 277/277 (22 Sep). Linux 276/276 (21 Sep, before
  v2; no Linux replay of v2 yet).
- **Auditor inbox:** empty at 3:29 PM ET, 22 Sep.

## Next, in order (recommended)

1. **Use moscope on real history** and write down every friction point, in the
   tool and in the language.
2. **Fix language papercuts at the root**, each with a test that fails first.
   Known ones: a multi-line `expose` list does not parse (MO0101); `message`
   cannot be a field name (reserved); `10.minutes` is rejected (MO0208 wants
   `minute`/`seconds`).
3. **Guard flake:** `toolchain/bench/step36/guard.py` exited 125 on correct
   output in fs_scope step 40's native test binary, in 2 of 4 full Darwin runs.
   Check main, then find the cause (suspect: the 0.5 s `ps` probe under load).
4. Then pick the next small tool Robert would actually use.

## Parked (not closed; none of this is on main)

| line                                   | where it stopped                                      |
| -------------------------------------- | ----------------------------------------------------- |
| `mo-wiki/plans/interpreter-step-42.md` memory safety  | candidate 77163596 unreviewed, seven obligations open |
| `mo-wiki/plans/mo-workspace-server-4a.md`             | Linux correctness 278/278; measurements blocked       |
| `mo-wiki/plans/mo-first-coding-harness.md`            | waits on an executor boundary and provider login      |
| Program 7 (Redis subset vs Elixir)     | suspended 20 Sep; spec and evidence kept as history   |
| `mo-wiki/plans/interpreter-step-39.md` TLS/durability | unaccepted                                            |

Resume any of these from its plan page and its latest evidence bundle, not from
scratch.

## Waiting on Robert

1. **Operating model.** The 22 Sep work ran in Claude Code sessions (one wrote,
   a separate one verified), not in an Amp lead with Oracle review and orb
   workers. `CLAUDE.md` and `mo-lead` still describe the Amp model.
2. **Auditor scope.** Every change, or only toolchain changes and public claims?
   v2's two runtime fixes have no auditor reading yet.
3. Optional: delete the merged branches `moscope/real-data-v2` (origin) and
   `lead/verify-moscope-v2` (local).

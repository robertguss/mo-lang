---
title: "The harness in Mo: migration and the capabilities it needs"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [agents, tooling, security, stdlib]
sources: [plans/mo-first-coding-harness.md]
status: in-progress
---

# The harness in Mo

## Orientation

Robert, 19 Sep 2026: fix every finding of the overnight review, write as much of
the harness in Mo as possible "to really test Mo", keep Python and JavaScript at
the minimum their roles need, and cut Astra's verbosity. He also decided Mo
gains a scoped child-process capability ([[decision-log]], 8:11 AM ET). This
page is the map and the order; each step below gets its own brief and a fresh
Opus worker. Every step leaves a working system.

Measured today, source only: 7,358 lines of Python and 1,416 of JavaScript under
`toolchain/harness/`, against about 5,100 lines of Mo in
`examples/programs/agent/` (plus the rebuilt application workspace). The design
map behind this page is a read-only Opus review, checked by the lead where
marked.

## What Mo lacks today (lead verified in `toolchain/PRELUDE.md` and source)

- No child process, Unix socket, signal, `chmod`/`chown`, or `write_bytes`.
- No HTTPS on `Http.send`; the TLS client is unaccepted (step 39).
- **`Fs.scoped` is a lexical check only** (`toolchain/src/stdlib.zig`, `pathIn`
  and `climbsOut`: `resolvePosix` and a `..` count). A symlink inside a scope
  reaches outside it. This is a hole in the language's own authority claim, not
  only a harness need, so it is fixed first.

## New capabilities, in order

| #   | capability                                                                                                                                                                                                                                                                                                                 | why                                                        | unlocks                                                                   |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------- |
| 1   | A scope that holds: every path component opened refusing symlinks; regular files only; hardlink count 1; no setuid. Decide on the design page whether this becomes what `scoped` means or a separate `scoped_strict`                                                                                                       | closes the hole above; it only removes reach               | `workspace_files.py` and five duplicate hardened readers, about 500 lines |
| 2   | `Fs.replace(path, text)`: atomic temp and rename, private mode                                                                                                                                                                                                                                                             | the journal and state files                                | about 150 lines                                                           |
| 3   | `platform.exec`, narrowed before use: a fixed program, a fixed argument template with typed holes and no shell, an explicit environment, a working folder inside an `Fs` scope, `within:`, bounded captured output, process-group kill at the deadline, the real exit code or signal. `Exec.fixture()` for `mo test --sim` | Robert's decision; the executor's docker and systemd calls | about 800 lines of `remote.py`, `adapter.py` and runners                  |
| 4   | `Fs.write_bytes`                                                                                                                                                                                                                                                                                                           | package verification                                       | about 80 lines                                                            |
| 5   | HTTPS and a streaming body on `Http.send`                                                                                                                                                                                                                                                                                  | the provider turn                                          | about 400 lines of JS, **after step 39 is accepted**                      |

The design map's reviewer argued against row 3: a child inherits none of Mo's
checked authority, so a typed handle can launder unbounded power. Robert's
decision stands; the objection shapes the design. `platform.exec` is never
handed down whole: `main` narrows it to named programs and templates (as
`fs.scoped("logs").read_only` narrows an `Fs`), a process holding a narrowed
`Exec` can run nothing else, and the checker treats it like any capability
(`MO0407` rules apply). Containment of the child stays the operating system's
job: Mo starts `docker` and `systemd-run`; it does not pretend to sandbox. Unix
sockets are not added: the bridge and owner split that wanted them goes away.

## Target shape

1. Mac: the Mo agent, as now.
2. Mac: a Mo session program replacing `workspace.py`.
3. Machine: one Linux Mo program serving the six tools over `Http.listen`, with
   the workspace state machine, journal and recovery decisions. Replaces
   `workspace_http/` (bridge, owner, protocol) and most of
   `workspace_controller.py` and `recovery/`.
4. Machine: docker, systemd, cgroup and mount calls made from Mo through row 3;
   until it lands, a trimmed `remote.py` of about 450 lines.
5. Mac: the JavaScript provider adapter, auth and turn only, about 450 lines,
   about 250 once row 5 lands. The OAuth token never crosses Mo's TLS before
   step 39 is accepted.
6. One tool schema, in Mo. One table-driven live runner and one inventory script
   in Python for tests.

## Steps

| #   | step                                                                                                                                                                                                                        | removes        |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| 1   | The two high executor defects (E1 power-off, E2 refusal crash) fixed in place, failing control first; delete six duplicate guarded runners and about fourteen per-run evidence and probe scripts; one helper, one inventory | about 1,000 py |
| 2   | Six hand-written live suites become case tables; the five tests that cannot fail (E3, M1) are replaced by ones that can                                                                                                     | about 1,400 py |
| 3   | Capabilities 1 and 2 in the toolchain, accepted against the hostile-filesystem cases already in `test_workspace.py`                                                                                                         | —              |
| 4   | The Linux Mo six-tool server, run beside `workspace_http/` on the same protocol until outputs match, then cut over. Findings H1 to H7 are closed by the new design's controls, not patched in Python first                  | 666 py         |
| 5   | Workspace state machine and recovery decisions into that server (closes E3, E4, E6, E7)                                                                                                                                     | about 700 py   |
| 6   | The Mo session program replaces `workspace.py`                                                                                                                                                                              | 261 py         |
| 7   | Capability 3, then docker and systemd calls move into Mo (closes E5 by construction: no string-built commands)                                                                                                              | about 450 py   |
| 8   | Mo agent findings M2 to M8, including folding the flag-gated budget branches in `run.mo` into the existing budget logic                                                                                                     | —              |
| 9   | Step 39 accepted, then capability 5 and the provider turn; provider findings P1 to P5 with it                                                                                                                               | about 250 js   |

Briefs so far: [[mo-harness-step-1-executor]] and [[mo-harness-step-8-agent]] (both accepted 19 Sep), [[mo-harness-step-2-live-tables]], and beside the plan [[toolchain-raw-memory-report]]. Step 2 follows step 1, since both touch the executor's runners. **Order changed 19 Sep, 9:51 AM ET:** capability 3 (`Exec`) moves ahead of step 4, so the Mo six-tool server runs `docker` itself and serves all six tools natively; a Python shim for `command` would be throwaway work. **Measured so far:** step 1 took Python from 6,688 to 6,326 counted lines and step 2 raised it to 6,643 (better tests, a shared runner); the estimates in the Steps table are not holding, and cleaning Python is not where the reduction is. Step 3 is the
first toolchain step and needs the lead's design page first.

## The size question (Robert, 19 Sep 2026, 8:20 AM ET)

Robert asked whether Mo lets the same features be written in less code. **The
reductions on this page do not show that.** They are estimates by one reviewer,
and they are mostly deletion of duplicates and evidence machinery plus code
*moving* into Mo, where it will add lines that nobody has estimated yet. No
like-for-like Python-to-Mo size has been measured.

So it is measured, not claimed. For every module that moves:

1. The Python or JavaScript is first cleaned (steps 1 and 2), so the comparison
   is not against Astra's verbose draft. A second writing is always shorter than
   a first; without this the result would flatter Mo.
2. The same behavioural tests must pass against both versions before cutover
   (step 4 already runs them side by side).
3. At acceptance the lead records, per module, on this page: non-blank,
   non-comment source lines before and after in each language, test lines
   separately, the features dropped or added (so a smaller program that does
   less is not counted as a win), and the defects found in each by the same
   controls.
4. Counted with one script, committed beside the table, so the auditor can
   reproduce it.

This is one application by one author, so it is evidence about this harness,
not a general claim about the language.

| module | before (lang, lines) | after (Mo lines) | tests before / after | feature differences | defects found before / after |
|---|---|---|---|---|---|
| (filled at each acceptance) | | | | | |

## Numbers and done when

After step 7: at most 600 lines of Python (tests and packaging) and 600 of
JavaScript under `toolchain/harness/`, every review finding closed or moved to a
named step, the full suite green on Darwin and the machine run green on Linux,
and the Mo share of harness source reported at each acceptance.

## Related

- [[mo-capabilities-for-the-harness]]
- [[mo-first-coding-harness]]
- [[mo-application-workspace-v1]]
- [[decision-log]]

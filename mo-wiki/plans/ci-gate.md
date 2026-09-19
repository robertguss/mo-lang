---
title: "A CI gate: the compiler and corpus checked on every pull request"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [verification, tooling, compiler]
sources: [plans/interpreter-step-43.md, plans/interpreter-step-42.md]
status: briefed
---

# A CI gate

## Orientation

Two audits (18 and 19 Sep 2026) found the same gap: the only tracked workflow
publishes the wiki, so nothing but the lead's own runs stands between a change
and `main`, and an outside reader cannot reproduce a completed full suite. The
auditor's own attempt timed out at 180 s. Measured today: the full suite takes
11 to 12 minutes on the Mac (14 cores) and 18 to 35 minutes on a 4-core x86_64
Linux machine, because the corpus builds one program at a time; and it writes
generated files into the source tree (`examples/**/zig-out`,
`toolchain/.zig-cache`), so two runs cannot share a tree and an orphan from one
run has deleted another's outputs. This step makes the suite reproducible by
anyone and gates pull requests on it. Worker: a fresh Claude Opus session,
bypass permissions, own worktree and Herdr tab, launched after step 42 lands
(both edit `toolchain/src/corpus.zig`). The lead owns the wiki, audit and
acceptance. Nothing here changes the lead's acceptance checklist: CI is a floor,
not a replacement.

## Write scope

`.github/workflows/ci.yml` (new; `site.yml` untouched), `toolchain/build.zig`,
`toolchain/src/corpus.zig` and the test helpers it uses, `toolchain/README.md`
(a "Running the suite" section), `.gitignore`. No language or runtime change,
no harness, no wiki, no `audit/`, `HANDOFF.md`. No push: the lead pushes the
branch and opens the pull request that proves the gate. Never use `tr`; `ls`
is aliased, use `/bin/ls`.

## Parts

1. **Generated files leave the source tree.** Every file the suite makes
   (`mo build` outputs, brick caches, temporary corpora) goes under one
   directory chosen by an environment variable (say `MO_TEST_OUT`), defaulting
   to a fresh temporary directory per run, never under `examples/`. Prove it:
   run the suite from a read-only copy of `examples/`; and run two filtered
   suites at once in one tree, both green. RED first: a test that fails today
   because a run leaves files under `examples/`.
2. **The corpus builds in parallel.** Today the corpus step is serial (load
   average 1.0 on 4 cores for half an hour). Build and run corpus programs
   with a bounded worker pool sized from the CPU count, output still
   deterministic and failures still attributed to their program. Numbers: wall
   time before and after on this Mac; the lead measures Linux.
3. **Two gates in one workflow.** On every pull request and push to `main`:
   *fast* (Zig 0.16.0 pinned by exact version, `zig build`, the unit tests by
   filter, `mo fmt --check` and `mo check` over `examples/`, the rejects'
   first diagnostics), which must finish inside 10 minutes; and *full*
   (`zig build test --summary all`, unfiltered) on `ubuntu-latest` and
   `macos-latest`, with a timeout above the measured time, the summary line and
   exit code in the job summary, and the log uploaded as an artifact. Every
   step's real exit status propagates; no `|| true`, no `continue-on-error`.
   Least privilege: `permissions: contents: read`; actions pinned by commit
   SHA; no secrets; nothing from a fork's pull request runs with write access.
4. **The known flake is named, not hidden.** The TLS corpus test "a fatal
   alert where a hello belongs" fails about 1 in 5 alone on Darwin. Do not
   retry it silently and do not skip it: report its rate from 20 runs on each
   platform in the report, and if it makes the gate useless, propose a
   quarantine list that prints every quarantined test in the job summary; the
   lead decides.
5. **Negative controls**, described for the lead to run on the proving pull
   request: a planted failing unit test, a planted corpus mismatch, and a
   planted formatter difference each turn the gate red with the failure named;
   removing them turns it green.

## Done when

Every local process under `toolchain/bench/step36/guard.py`, each quoted run
teed into a filed log with an exit file beside it (under
`toolchain/bench/ci-gate/`). `zig build` exit 0; the focused tests and both
proofs of part 1 with real summary lines and exit codes; `actionlint` clean on
the workflow (install it with Homebrew). **The unfiltered full suite, Linux and
the pull request are the lead's.** Small commits as yourself with a
`Co-Authored-By` line naming your model. **Write your final report to
`toolchain/CI-GATE-REPORT.md` and commit it last, with a clean worktree.**
While anything runs, wait in the foreground.

## Related

- [[interpreter-step-42]]
- [[interpreter-step-43]]
- [[decision-log]]

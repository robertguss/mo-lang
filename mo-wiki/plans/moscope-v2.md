---
title: "Moscope v2: useful on real Claude Code history"
created: 2026-09-22
updated: 2026-09-22
type: plan
tags: [tooling, verification]
sources: [plans/moscope-serial-acceptance.md]
status: done
---

# Moscope v2: useful on real Claude Code history

## Orientation

Robert asked for a review of the accepted serial moscope (c52db2f3) and then for
the review's recommendations to be carried out. Moscope v1 passed 66 interpreter
and 74 native synthetic cases on Linux. The review then ran it on Robert's own
`~/.claude/projects` on Darwin: 588 MB, 347 JSONL files. It recorded only
aggregate counts, exit codes, timings and memory.

| observation on real history (v1)                             | consequence                                           |
| ------------------------------------------------------------ | ----------------------------------------------------- |
| native binary: SIGSEGV in 76 of 77 project folders           | the native build is unusable on real data             |
| interpreter: 60 s deadline, 1.4 GB RSS, "No matches." exit 2 | 97 files contain the query; every scanned result lost |
| 282 `tool_reference` parts, 7 U+FFFD files, 3 lines > 1 MiB  | every real search exits 2; the 0/1/2 contract is void |
| 46 of 94 excerpts do not contain the query (mo-lang folder)  | excerpt is the block's first 240 graphemes            |
| 50 of 94 excerpts carry `\xE2\x80\x94`-style escapes         | ordinary prose (em dashes) is unreadable              |
| `search -- "--no-verify" DIR` rejected; no `--help`          | a dash-leading query is impossible                    |
| 180 MB folder: 15.3 s, 680 MB RSS                            | whole corpus retained in memory before searching      |

The native crash is the Mo runtime's, not moscope's: a nine-line program whose
only work is `Json.decode` of a value nested 18 deep segfaults when built with
`mo build`, while `mo run` decodes depth 30. Claude Code `attachment`
bookkeeping records carry tool schemas nested about 15 deep. The review also
found five in-verifier expectations re-pinned to the program's own output
(attempt 14 to 15), so those were goldens, not independent oracles.

An aggregate structural survey of the same history (no content retained) grounds
the new policy: no malformed or blank lines; no repeated UUID inside any file;
`tool_reference` parts are exactly `{type, tool_name}`; two `document` parts;
eight `user` lines over 1 MiB (largest file 16 MB); conversation records nest at
most about 14 deep; every conversation record has `sessionId` and `cwd`.

## Decisions

1. **Real data is the first gate.** Every change is run on the real history with
   only aggregate receipts (exit, counts, time, RSS). Transcript text never
   enters the repo. Synthetic fixtures remain the committed regression suite.
2. **Warnings versus errors.** Record-level surprises (malformed JSON, oversized
   line, U+FFFD, unknown block or part types, nonobject records, missing type,
   unknown conversation-shaped types, bad field shapes, repeated UUID) are
   warnings: the record or block is skipped, counted by category, and the search
   continues. Errors are what makes the scan itself incomplete: unlistable or
   unreadable paths, traversal limits, retention and output limits. Exit 0 =
   matches, 1 = none, 2 = usage or error. `--strict` makes warnings count as
   errors, keeping v1's fail-closed contract available.
3. **Search while reading.** Options are known before the scan, so each block is
   matched as it is parsed and only matching blocks are kept, each with a
   bounded excerpt. For all-words mode, each message keeps flags for which terms
   it has matched so far. Sessions keep only their label, id, cwd and latest
   eligible-conversation timestamp. Memory now scales with matches, not corpus
   size. All-words output shows the blocks that contain at least one term, not
   every eligible block.
4. **No processing deadline.** Ctrl-C is the cancel for a local CLI. The
   per-call filesystem timeout stays. Byte-admission limits (64 MiB file, 1 GiB
   aggregate) and record-count limits guarded v1's retain-everything design and
   go with it. The line limit rises to 32 MiB because real tool results exceed 1
   MiB.
5. **Known shapes from the survey.** `tool_reference` becomes an opt-in tool
   block labelled with its tool name. `document` result parts are known and
   excluded like images.
6. **UUIDs.** A repeated UUID inside one file keeps the first record and warns.
   The structural-equality store of every decoded record goes (it never
   triggered on real data and was the largest retained structure).
7. **Useful output:**
   - The excerpt is a 240-grapheme window starting 80 graphemes before the first
     match, with `...` marking clipped ends.
   - Printable Unicode passes. C0, DEL, C1, bidi, zero-width, line/paragraph
     separator, BOM, interlinear and tag characters are escaped (`\xNN` or
     `\u{XXXX}`), and backslash doubles.
   - Paths print joined to the directory as the operator typed it.
   - Each session heading is followed by a copy-pasteable
     `resume: cd <cwd> && claude --resume <id>`, POSIX-quoted when needed.
   - Ignored bookkeeping is one summary line, not one line per kind.
8. **CLI.** `--` ends options; `-h`/`--help` prints help to stdout and exits 0;
   `--strict` is added.
9. **Verification honesty.** The app-local verifier becomes one small runner
   over golden triples, with `--bless` to rewrite them after a reviewed diff.
   They are called goldens. No binaries are committed. v1's verifier and records
   remain in history and under `audit/evidence/2026-09-21/`.
10. **Docs split.** `README.md` is a user guide: build, run, flags, output, exit
    status, limits. `ACCEPTANCE.md` holds v1's acceptance record and v2's
    real-data receipts.
11. **The runtime crash is fixed at its root, in a separate commit.**
    Root cause: `json_read` in `toolchain/runtime/mo_rt.c` held pointers into
    scratch arrays that nested reads reallocate (a use-after-free). Past 16
    containers in one document it crashes, or silently drops values: an array
    of 16 objects decodes as one. Every native program that decodes JSON is
    affected, on Linux as well as Darwin. The fix keeps indices. It changes the
    accepted toolchain's bytes, so it needs lead/auditor acceptance before
    `main`. Moscope does not work around it.

## Parts

1. This plan.
2. Model and limits: `Options.strict`, `Matcher`, excerpt-carrying `Block`,
   candidate `Message` with term flags, `SessionInfo`, `Scan` with errors and
   warning categories. Limits trimmed per decision 4.
3. Parse: matching at parse time, warnings, `tool_reference`/`document`, UUID
   policy, session cwd/latest.
4. Scan: no clock or deadline, no byte admission, errors only for
   filesystem/traversal.
5. Search/render: final match selection, session order (unchanged rule), excerpt
   window, new terminal-safety rule, joined paths, resume line, warning summary.
6. Main: `--`, help, `--strict`, no Clock.
7. Tests: module tests updated/added for each decision. Fixtures gain `cwd` and
   warning cases. Goldens are rewritten and each diff reviewed by hand. The
   corpus `# run:` cases stay green.
8. Verifier: `acceptance/check.py` (interpreter and optional native, goldens,
   `--bless`) replaces `verify.py`, `final_regression.py`, `test_verify.py` and
   the manifest.
9. README/ACCEPTANCE split.
10. Real-data receipts: interpreter and native on the full history and the
    mo-lang folder, before and after (exit, match count, warning categories,
    time, RSS).
11. Runtime fix with a native red/green regression test in
    `examples/stdlib/json.mo`, and the unfiltered `zig build test-corpus`.

## Done when

The full real history completes in the interpreter with matches printed and exit
0 for a query that exists and 1 for one that does not. Memory is well below
v1's. Every module's tests pass under `mo test` and the standard corpus passes
for moscope's cases. Goldens pass under `check.py` in both runtimes. The README
describes v2 only. What v2 does not claim: hostile-input hardening, Linux
re-verification, and auditor review.

## Result

Done on branch `moscope/real-data-v2`, 22 Sep 2026, on Darwin. Independently
verified on Darwin and merged to main at eff64c56 the same afternoon (4:00 PM
ET); see the [[decision-log]] and
`audit/evidence/2026-09-22/moscope-v2-verify/`. No Linux replay or auditor
reading yet.

| check                                             | result                                                   |
| ------------------------------------------------- | -------------------------------------------------------- |
| real history, native (588 MB)                     | exit 0, 138 matches, 3.0 s, 15 MB RSS; absent query exit 1 |
| real history, interpreter                         | exit 0, 138 matches, 7.4 s (v1: deadline, "No matches.") |
| native vs interpreter stdout on real history      | identical                                                |
| excerpts holding the query                        | 138 of 138 (v1: 48 of 94)                                |
| `check.py`, interpreter / native                  | 34/34 / 34/34                                            |
| moscope module tests                              | 40 tests and properties, all nine modules                |
| JSON regression, native old / fixed runtime       | SIGSEGV / pass                                           |
| unfiltered `zig build test-corpus` (Darwin)       | exit 0, 189 s (first run caught an unformatted test; fixed) |

The interpreter first still peaked at 1.4 GB on the full history. A bare
decode-only Mo program showed the same 1.28 GB, so the cause was the runtime:
`mo run` gave its Server and Vm the process arena as `gpa`, so no temporary the
interpreter freed was ever released. A follow-up commit gives `mo run`
`std.heap.smp_allocator`. The full history then peaks at 28 MB in the
interpreter (native 14 MB). It adds a red/green corpus test and was checked by
a full corpus run under Zig's DebugAllocator. The detailed
receipts are in `examples/programs/moscope/ACCEPTANCE.md`.

## Related

- [[moscope-serial-acceptance]]
- [[decision-log]]

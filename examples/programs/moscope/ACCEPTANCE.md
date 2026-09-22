# moscope: acceptance and measurement record

The user guide is [`README.md`](README.md). This file records how each version
was checked. The plans are `mo-wiki/plans/moscope-serial-acceptance.md` (v1) and
`mo-wiki/plans/moscope-v2.md` (v2).

## v1: serial synthetic acceptance (21 Sep 2026)

v1 (c52db2f3, integrated at 6eaacb28) was accepted after independent lead replay
and Oracle review.

| gate                    | result                                                        |
| ----------------------- | ------------------------------------------------------------- |
| interpreter             | 66/66 exact stdout/stderr/status                              |
| ordinary native (Linux) | 74/74: eight cold builds, 59 CLI cases, seven module binaries |
| full corpus             | 276/276 Zig tests                                             |

The raw evidence, including every failed attempt, is under
`audit/evidence/2026-09-21/moscope-*`. v1's app-local verifier (`verify.py`,
`final_regression.py`, `test_verify.py` and a manifest) is in git history at
6eaacb28. The acceptance claimed Linux serial synthetic correctness only. It
explicitly excluded private data, Darwin and performance.

## v2: measured on real history (22 Sep 2026)

A review ran v1 on Robert's own `~/.claude/projects` on Darwin: 588 MB and 347
JSONL files. It recorded only exit codes, counts, timings and peak RSS; no
transcript text enters the repo. The query was `zig build`, which occurs in 97
files.

| run                                  | v1                                                     | v2                                                        |
| ------------------------------------ | ------------------------------------------------------ | --------------------------------------------------------- |
| interpreter, full history            | exit 2, "No matches.", deadline hit at 60.2 s, 1.44 GB | exit 0, 138 matches, 7.4 s, 1.42 GB; 28 MB after the allocator fix                       |
| native, full history                 | SIGSEGV in 76 of 77 project folders                    | exit 0, 138 matches, 3.0 s, 15 MB                         |
| native, absent query                 | SIGSEGV                                                | exit 1, 3.0 s                                             |
| diagnostics                          | 295 "incomplete" lines, 18 ignored-kind lines          | one warning category (7 records with U+FFFD) and one note |
| excerpts holding the query           | 48 of 94 (mo-lang folder only)                         | 138 of 138                                                |
| native stdout equals interpreter     | not measurable                                         | yes, byte for byte                                        |
| mo-lang folder (180 MB), interpreter | 15.3 s, 680 MB                                         | 2.5 s, 521 MB                                             |

`--include-tools`, `--all-words` and `--strict` were also run natively on the
full history. They exited 0, 0 and 2, every excerpt held a query term, and peak
RSS stayed at about 15 MB.

What caused each v1 failure and what v2 changed:

- **Native crash:** the Mo runtime's JSON decoder (`toolchain/runtime/mo_rt.c`,
  `json_read`) kept pointers into scratch arrays that it reallocated. Past 16
  objects or arrays in one document it could crash or silently drop values (an
  array of 16 objects decoded as one). Claude Code `attachment` records exceed
  that. The decoder now keeps indices, and `examples/stdlib/json.mo` has a
  deep-and-wide regression test that segfaults natively on the old runtime and
  passes on the fixed one.
- **Always exit 2:** record-level surprises (282 `tool_reference` parts, 7
  records with U+FFFD, 3 lines over 1 MiB) each made v1 incomplete. v2 counts
  them as warnings, knows `tool_reference` and `document` parts, and raises the
  line limit to 32 MiB. `--strict` keeps the old fail-closed behaviour.
- **Deadline discarding results:** the 60-second deadline expired during the
  scan, and the search phase then stopped before its first message. v2 has no
  overall deadline, streams, and keeps only matching blocks.
- **Interpreter memory:** the remaining 1.4 GB peak was the interpreter's, not
  moscope's. A bare Mo program that only decoded the history's lines peaked at
  1.28 GB, and memory grew about 13.6 MB each time the same 16 MB file was
  decoded. Region compaction was working. The cause was that `mo run` handed
  the process arena to its Server and Vm as `gpa`, so every temporary the
  interpreter freed (the JSON decoder's key tables and string buffers, and
  about 90 similar sites) stayed until exit. `mo run` now uses
  `std.heap.smp_allocator` (`toolchain/src/main.zig`). The full history now
  peaks at 28 MB in the interpreter and 14 MB native, with identical stdout.
  A corpus test decodes the same JSON 50 times under `mo run` and in a binary:
  memory grows 588 MiB on the old toolchain and 2 MiB on the fixed one, per
  200 decodes. The full corpus also passed with Zig's DebugAllocator
  (double-free detection, poisoned frees) standing in, to catch any use after
  free that the arena had been hiding.

What v2 does not claim: Linux re-verification, hostile-input hardening, or
auditor review. The v2 checks are the 34 cases in `acceptance/check.py`
(interpreter and native, both 34/34 on Darwin), 40 module tests and properties, and the three
corpus `# run:` cases. The unfiltered `zig build test-corpus` exits 0 on Darwin with the fixed runtime.

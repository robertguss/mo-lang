# moscope serial acceptance manifest

This is an execution plan, not evidence that the cases passed. `verify.py plan`
prints the machine-readable version without starting a child process. Every
payload is launched directly through the accepted `guard.supervise` API, one at
a time, with separate raw stdout and stderr files. A stage stops if supervision
fails or its process group is not literally absent after cleanup.

## Identity and bounds

- Candidate source starts at `f961c686cacf513daec22e771e73832a227298e5` on
  prerequisite `dad7b3743da38d929f632d70db42e592cd1b755e`.
- The accepted compiler is supplied by absolute path and must be the
  15,849,056-byte binary with SHA-256
  `3ef07d08ed6d0c802a2597bd956579873851855961cf2e5f01cf87018d273b78`.
- The guard is byte-identical to the prerequisite and has SHA-256
  `7a5eadf9794110efec179872b02833df8fb4a12a3ad8fb8244074f903a8d23c2`.
- Stdout and stderr each have a sampled 16 MiB stop threshold and a strict 16
  MiB final acceptance limit. Because guard policy is polled, the sampled
  threshold is not a hard disk-write cap. After confirmed process-group absence,
  the verifier rejects an oversized final file before reading or hashing it. CLI
  cases get 60 seconds, generated line cases 90 seconds, module tests 120
  seconds, and each cold native build 900 seconds. These outer limits do not
  verify the application's own filesystem or processing deadlines.
- The environment contains only an owned HOME/TMPDIR, locale/timezone, and a
  PATH for the compiler's native linker. `mo` is never resolved through PATH.

## Stages

1. **Probe (review gate).** Re-run only the existing four-match phrase case
   against its independently authored stdout/stderr/status triple. File the raw
   streams, hashes, exact argv/environment, termination, elapsed time, guard
   reason/RSS, capture sizes, and cleanup observation. Review that report with
   the lead before broad execution.
2. **Interpreter exact and CLI.** Run all eight existing triples, all seven Mo
   modules, then generated argument/flag, matching, eligibility, identity,
   ordering, malformed-input, escaping, filesystem, and realistic-boundary
   cases. Compare stdout, stderr, and status to independent expectations; status
   1 and 2 are expected outcomes where specified.
3. **Production seams.** Run deterministic Mo fixture tests for counters,
   admission/retention, diagnostics/output bounds, filesystem timeout, and
   processing deadline, including post-fold expiry preserving prior results.
4. **Native.** Cold-build ordinary `main.mo` with contracts on and no surface,
   inspect generated C for `mo_nprocesses == 0`, build every module with
   `--tests`, and run the same exact CLI and module-test expectations against
   the native binaries from fresh caches.
5. **Release metadata.** Only after behavior is green, run real formatter and
   `mo test --write` for every `.mo` file, including zero-test modules, to
   create app-local verified blocks and `.mo.ids`. Re-run both runtimes after
   those tool-owned edits.

The verifier creates only owned disposable trees, restores unreadable fixture
permissions before removal, and records each cleanup. Symlink, FIFO, directory
candidate, sparse-file, and non-root unreadable cases are isolated. An unsafe
signal, watchdog, output-cap, cleanup, or zombie result stops the stage; normal
application compile/assertion/output failures are retained as attempts before a
source fix and serial rerun. Source inventory uses no-follow entry inspection:
it records directories, regular-file sizes/hashes, symlink targets, other entry
types, and the app-local `.mo.ids` when present.

## Interpreter checkpoint

The corrective interpreter suite runs 66 serial cases: all eight original
triples, 51 additional CLI/filesystem/boundary cases, and all seven modules with
27 non-writing tests. It covers query/term/line boundaries, LF/CRLF/no-LF,
malformed and replacement input, ordering, root and discovered symlinks, FIFO,
directory candidates, sparse file admission, genuine non-root unreadable file
and subtree controls, actual depth 24/25 traversal, exact and over-limit lines,
production counters, aggregate admission, filesystem timeout, post-fold
processing expiry, terminal escaping, isolated eligibility/tool/malformed/UUID
semantics, excerpt/output admission, and fixed constants. Large count limits use
production-called admission predicates and focused state fixtures rather than
giant materialized corpora. Every expectation is exact for status and both
streams. Earlier attempts and ordinary failures remain in the external evidence
archive. This checkpoint does not include native execution, release metadata, or
the full corpus.

## Native checkpoint

The ordinary native stage performs eight sequential cold builds: `main.mo` and
all seven modules with `--tests`. Contracts remain on (no `--no-contracts`) and
the runtime surface remains off (no `--surface`). Before any generated binary
runs, the recorder hashes each generated C file and requires exactly one
`const uint32_t mo_nprocesses = 0;` declaration. It then applies the same 59
independent CLI expectations and runs all seven module-test binaries. The stage
records 74 guarded payload receipts total: eight builds, 59 CLI cases, and seven
module binaries. Release metadata and the full corpus remain separate pending
gates.

## Metadata and final regression status

The first metadata attempt completed all seven formatter writes and
`mo test --write` for `limits.mo` and `model.mo`. It stopped without retry when
`mo test --write main.mo` exited 1 with MO0304 for the nested predicate in
`search.mo`. Ten process groups were literally absent. After the reviewed pure
`all_words_present?` extraction, the full sequence reran from command one: seven
formatter writes, seven individual `test --write` commands, and seven formatter
checks all passed exactly with 21 absent groups. `mo.root`, the shared
`examples/programs/.mo.ids`, and every other out-of-scope path were unchanged;
the complete app-local `.mo.ids` and verified blocks are tool-generated.

`final_regression.py` is the unexecuted lead-owned final gate recorder. From the
integrated `toolchain/` directory it records guarded, unfiltered
`zig build -j4 --summary all` and `zig build test-corpus -j4 --summary all`
commands with configured budgets of 900 and 7200 seconds. It uses fresh absolute
caches, a pinned absolute Zig, sanitized environment, two-second signal
forwarding grace, a budget-plus-five outer deadline, and the same fail-closed
capture and process-group rules. The external harness's 1800-second wrapper
remains outside this recorder and is not modified here. Neither command has been
executed by this worker.

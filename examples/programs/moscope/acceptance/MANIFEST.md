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

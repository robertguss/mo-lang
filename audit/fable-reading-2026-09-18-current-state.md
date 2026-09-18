---
subject: current-state
author: Amp (OpenAI assistant, project lead; exact model identifier unavailable)
date: 2026-09-18, 5:25 PM ET
filed_against: 2bff798665f29828d97bcba66d883839f9cc7e3b
read_before_auditor:
  yes; PR 12's reading and audit/state.md changes have not been opened
---

# Lead reading: current state before opening PR 12

Robert authorized this session to take the lead role after requesting review of
PR 12. This reading is filed before opening the auditor's conclusions. It is not
a cold reading of the project's history: this session has read the existing
decision log, handoff, earlier lead readings, and the auditor's raw
current-state evidence. The oracle also inspected the implementation during
orientation, without opening audit readings. Those exposures are disclosed; this
file does not claim independent discovery of the raw probes.

## Evidence and boundary

Current main is `2bff798665f29828d97bcba66d883839f9cc7e3b`. PR 12's head is
`7368afcedf2134db98fddcafa5138bef1fbfd12e`. Its raw evidence files read before
this filing are `audit/evidence/2026-09-18/current-state/`: `harness-probe.py`,
`harness-mock-results.json`, `tls-chain-checks.json`, and
`fuzz-accounting-mock.log`. No hidden suite or seed was opened.

This is source inspection and inspection of preserved outputs, not a new
toolchain acceptance run. In particular, the TLS results in the PR are not
assumed to describe today's main: step 39 A/B have since landed. A test's source
revision must accompany any claim about its current result.

## Reading

1. **Step 39 and the TLS brick remain unaccepted.** The move checkpoint's raw
   worker logs report A at 240/240 and B at 242/242, exit 0. The other gates
   remain unmet: Limbo reports 27 accepted-but-should-reject, and the C WIP
   abuse run reports 63/64. The five-file C/D patch is saved, not applied in
   this clean checkout; E/F have not started. Worker explanations of the 27
   cases are not permission to change the zero threshold.
2. **The PR's original four chain acceptances and ALPN failure need version
   qualification.** Current `tls.zig` includes A's extension/path checks and B's
   ALPN bound. Preserved A/B probe outputs report the four refusals and the
   65-name control succeeding. Those worker results need independent acceptance;
   they do not establish full X.509 correctness or close Limbo.
3. **The committed fuzz driver is not a sound zero-failure instrument.** The raw
   mocked run supplies a failing batch whose inputs pass separately, yet the
   driver reports zero crashes. C/D's saved changes do not repair the committed
   executable path until applied and verified. A mock proves this counting
   defect, not a real TLS crash or its frequency.
4. **Suite runners still lose the aggregate failure status.** The VM runner
   discards the command status. The Mac runner records it, but the function
   finishes with cleanup/drain, and the script prints done without accumulating
   failure. The isolated probe reports a success status after both injected exit
   1 and exit 124. Logging an exit is not propagating it.
5. **The abuse table does not require the intended fault to be delivered.**
   `server_rows` catches `OSError`, records it as a string, and decides pass
   using expected Mo output and a health probe; `sent[i]` is absent from that
   predicate. The mock's 20/20 with every injection throwing shows a logical
   hole, not that any actual historical abuse case was undelivered. The fix must
   distinguish an expected peer refusal from failure to reach the intended state
   and inject the prescribed action.
6. **Selection validation is incomplete.** `abuse.py --runtimes typo` is not
   rejected; non-`run` labels select the binary path. `defects6b.py --only typo`
   selects no category and exits 0 with zero checks. The raw evidence
   distinguishes a mocked runtime-selection run from a real zero-selection
   invocation. Neither result demonstrates an application defect.

## Consequences, before reading the auditor

The project must not promote counts to stronger claims than their instruments
support. Keep existing raw results, distinguish historical from current
revisions, and run negative controls on status propagation, empty selections,
fault injection, fuzz batches, and fault-tolerant corpus assertions before using
repaired instruments for new acceptance. Do not silently rewrite a sealed suite;
a corrected instrument is versioned and its timing disclosed.

Program 7 still needs the auditor's seal and the measured baseline/skip list.
The existing decision permits server-only `mored` without the flawed client
chain path, but that is not permission to call the TLS brick complete or to use
`TlsClient` against untrusted chains. The latest queue orders step 39 first.
Orientation also found a line-only socket interface inadequate for binary RESP,
no implemented snapshot-plus-log restore path matching R5, and the recorded
directory-sync gap; these require explicit readiness resolution, not changes to
sealed requirements by implication.

No acceptance, benchmark claim, ratified threshold, or retirement mapping is
changed by this reading. No fresh Mo execution or Darwin verification is
claimed. The next operation is to publish this reading, then read PR 12 and
record the comparison against its pinned revision.

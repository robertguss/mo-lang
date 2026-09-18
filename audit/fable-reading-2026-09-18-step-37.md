---
subject: step 37, the TLS brick part two (the client, the chain, ALPN, KeyUpdate), with the fix b0b2ac4
author: Fable (the lead)
date: 2026-09-18, between 9:30 and 9:50 AM ET, pushed at baf6683 (corrected 9:54 AM ET: the header first said "about 10:15" or "10:25", a time Fable guessed instead of reading the clock; nothing else in the file changed)
filed_against: 15fb2cb (the ready record step-37-ready-001) and b0b2ac4
read_before_auditor: yes. Fable had not opened the auditor's reading, its checks, its evidence folder, or its `audit/state.md` lines on this subject when this was written; the receiver announced pointers only (kind, id, commit, path, the PR number). Robert said only that the PRs exist.
evidence: audit/evidence/2026-09-18/step-37/ (the worker-raw folder, fable-probe/); mo-wiki/plans/interpreter-step-37.md (the brief, the Result, the Fix); toolchain/bench/step37/RESULTS.md
---

# Fable's reading: step 37, the TLS brick, part two

## What was claimed and what the evidence shows

The brief asked for the client half of the brick, the chain to a trusted root,
ALPN, KeyUpdate both ways, and the three audit items step 36 owed: the
standard's vectors, a differential run, a fuzz budget. All are in the
evidence. As in step 36, the worker's green was not the whole truth, and the
acceptance rests on the lead's own suite run and probes:

- The differential run: 1,000 sessions against OpenSSL 3.0.13, seed 3737, 0
  mismatches, 597 completed and 403 refused across ten chain shapes. **A first
  run with the same seed had 3 mismatches, and the worker judged all three to
  be its harness's model of OpenSSL, then changed the harness.** That is the
  party under test grading its own mismatches. The three are named on
  `RESULTS.md`; Fable read the explanations and found them plausible, and did
  not re-derive them from OpenSSL's source. An outside reader should treat
  "0 of 1,000" as "0 of 1,000 after three harness corrections".
- The fuzz hour: 87,440 inputs in 3,601 CPU seconds, 0 crashes, after a
  planted panic and a planted hang were each counted. **About 24 inputs a
  second is slow for a parser fuzz**: it is a whole-handshake driver, not a
  coverage-guided fuzz of the record and certificate parsers. It meets the
  bricks page's letter (a CPU-hour) and is shallow against its purpose. No
  coverage number was taken.
- The RFC 8448 client replay is byte for byte, through test-only hooks that
  fix the random and the key. The hooks are compiled only in tests; Fable
  checked that by reading, not by a symbol dump of the release binary.
- **Two runtime defects behind 234 of 234**, found by Fable's probes with a
  second OpenSSL (Python's ssl on 3.5.7) and a raw-socket server: a peer's
  fatal alert during the handshake read as `Closed` where the spec says
  `Handshake`, and a double free in `mo_rt.c`'s handshake that killed the
  binary server (SIGSEGV) after one client that reset mid-hello or refused the
  chain. **The double free had been there since step 36**, through step 36's
  abuse run, the lead's 22 probes, and both readings of step 36. None of them
  caught it, because step 36's abuse script checked the server after the
  batch and its cases did not include a reset inside the hello against the
  binary. The fix (`b0b2ac4`) has a corpus test of five raw clients under both
  runtimes; Fable's reruns after it are in `fable-probe/*-after-fix.log`.

Reading: **fit to build program 7 on, with the shelf entry still `unread`.**
Audit items 1 to 4 are present, the fourth weakly; item 5 (someone reading
4,136 lines of `tls.zig` against the cap) is not done by anyone.

## What this reading did not verify, said plainly

1. **The chain check against an adversarial certificate corpus.** Ten chain
   shapes in the differential run and seven in Fable's probes (depth six,
   wrong root, wrong name, expired, non-CA issuer, IP SAN). Not checked by
   anyone: path-length constraints, name constraints, an unknown critical
   extension, key-usage and extended-key-usage bits, validity at the boundary
   second, a leaf used as a CA with `CA:TRUE` missing but key usage present.
   A corpus such as x509-limbo is the right test and was not run.
2. **The public internet is unreachable** (RSA and P-384 chains refused), so
   the client has never completed a handshake with a server the project did
   not configure. Program 7 does not need it; the client half is otherwise
   tested only against OpenSSL and itself.
3. **The cookie HelloRetryRequest** is tested brick to brick only.
4. **No Mo row starts a KeyUpdate**; it is an export driven by tests.
5. **Constant time and side channels:** nothing measured, again.
6. **macOS:** every number and every suite run in the evidence is the Linux
   VM's. (As of this morning the toolchain builds on the Mac and step 38's
   worker runs the suite there; that is after this evidence.)
7. **The numbers** were taken on a four-core VM with the fuzz hour
   overlapping the first final suite run (load to 1.5); the handshake rates
   are within 9 percent of step 36's, which is the only cross-check.
8. **Compile cost as a design driver.** RSA and P-384 were cut for 6 s and
   2.5 s of compile time. That is a cost decision that narrowed a security
   surface's interoperability; it is a row, and Robert has not yet read it.

## Where this leaves the claims under audit

For the capabilities rule: a TLS 1.3 client and server at zero third-party
runtime dependencies exists, at about 4,100 lines of Zig over `std.crypto`,
with a known refusal set. For the process: twice in two steps a worker's
green hid defects, and once a defect survived two readings. The rule that
followed (resets and alerts at every handshake state, both runtimes) is step
38 part C, not yet evidence.

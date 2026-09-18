# Audit reading: step 37 TLS code and step 36 harness changes

**Date:** 2026-09-18  
**Author:** Mo Auditor, independent model session  
**Charter:** raw evidence before parallel synthesis; only Robert may amend or reject this reading.  
**Scope:** TLS client/chain/ALPN/KeyUpdate changes, runtime handshake failure handling, and the revised step-36 harness. Not a security certification or a program-7 stopping-rule test.  
**Status:** filed cold against `64982b23b1dfed0bd0af3430125589da43058ac0`. Ready record `step-37-ready-001` pins `15fb2cb4ee6d43b449e5c811dde730c111983b18`; `toolchain/` and `examples/` have no diff between these anchors. Comparison base is `aace4ee36516c9dc67cdb7b0d0c8cab3a5f9c024`. Entry remote main was `fa4260a6ac93f40a3d0033c1bd99d6965a877a5f` (The board, 18 Sep 9:26 AM ET: generation six resumed on the Mac, step 38's worker started); that later tip is not the audited implementation.

**Explicit gap in this reading:** the complete project suite did not produce a completed result attributable to this reading. A background invocation returned without its expected log, and a foreground invocation exceeded the tool's response timeout. No project-suite pass is claimed from those attempts. Historical performance and the complete fuzz hour were not rerun. This is a targeted code/evidence review, not an exhaustive audit of all Zig dependencies or all runtime capability behavior.

## Reading

**Do not treat this cut as a generally validated certificate-chain implementation.** Real, completed brick-to-brick handshakes accept four independently generated certificate shapes that OpenSSL rejects: an intermediate's path-length violation, a CA without certificate-signing key usage, a server leaf restricted to client authentication, and an unknown critical leaf extension. The named fixture cases and passing native tests do not cover those constraints.

The step-36 immediate-recovery scheduling defect is genuinely repaired. The revised abuse script passed both runtimes with recovery between cases. The independent Zig-client matrix and runtime-requested KeyUpdate export also now exist and pass native tests. These are substantive improvements, not grounds for overlooking the chain-validation counterexamples.

This is a plain technical verdict, not S-A/S-B/S-C or T-A/T-B/T-C: the program-7 stopping-rule experiment is not this subject. The sealed brief explicitly names a narrower set of chain checks; it does not individually enumerate every X.509 extension above. The findings therefore distinguish observed security limitations from a claim that each is a verbatim omitted Done-when bullet. A narrow brief cannot make a broader certificate-validation claim safe by implication.

## What the auditor read cold

- Audit guide, charter, operating manual, workflow, and the prior auditor's step-36 reading; no Fable parallel reading, decision-log synthesis, RESULTS.md, or worker synthesis report.
- Step-37 sealed brief at `6f449c9`, cut at the actual `## Result` heading (not the inline quotation of that heading).
- TLS engine: certificate structure guard, chain/name/date/signature checks, record and handshake state transitions, ALPN, CertificateVerify/Finished, KeyUpdate, exports, and relevant native tests.
- Changes to `net.zig`, `tls_rows.zig`, `sources.zig`, `mo_rt.c`, and `mo_rt.h`, including fix `b0b2ac4a8491cbd32da2a1763d75d6a523346b67` and its engineering commit explanation (not an independent reading).
- Step-36 abuse/handshake scripts; step-37 differential and fuzz drivers/common helper; named raw differential, fuzz, performance and suite outputs.
- Linked Zig 0.16.0 `std/crypto/Certificate.zig` parser implementation. No claim of a complete standard-library audit.

The initial separate clone later contained additional audit outputs not produced by this reading. Publication was isolated in another worktree/branch at the same pinned commit. Only this reading's explicitly identified outputs were copied; unowned additional probe results are not evidence here. No lead sessions or worker panes were opened.

## Independently verified findings

### 1. Certificate restrictions are not enforced (high priority)

Source: `toolchain/src/bricks/tls.zig:538–567,648–731`.

`isCa` checks only the first basicConstraints Boolean. It does not read pathLenConstraint. `checkChain` checks issuer names, cryptographic signatures, CA Booleans for intermediates, host, and dates. It does not enforce keyUsage, extendedKeyUsage, or reject unsupported critical extensions. `signedBy` is deliberately a restricted cryptographic signature checker, not a full X.509 path validator.

The new [chain-checks.py](evidence/2026-09-18/tls-independent-code/chain-checks.py) builds fresh Ed25519 chains using cryptography 41.0.7, feeds actual records between two connections using the unmodified brick's exported ABI, and checks that **both** connections become ready. It uses a ReleaseSafe shared-library build, no test hooks and no authentication bypass. The same certificates are checked by `openssl verify` with `-purpose sslserver`, `-verify_hostname localhost`, and the same fixed verification time. Generated private keys are ephemeral and not filed.

[Actual output](evidence/2026-09-18/tls-independent-code/chain-checks.json):

| Case | Brick client/server ready | Client alert | OpenSSL exit/result |
|---|---|---:|---|
| Valid control | true / true | -1 | 0, OK |
| Intermediate pathLenConstraint=0, but another intermediate below it | true / true | -1 | 2, error 25: path length constraint exceeded |
| Intermediate keyUsage lacks keyCertSign | true / true | -1 | 2, errors 79/26/32, including key usage does not include certificate signing |
| Leaf extendedKeyUsage contains only clientAuth | true / true | -1 | 2, error 26: unsuitable certificate purpose |
| Unknown critical leaf extension | true / true | -1 | 2, error 34: unhandled critical extension |

These are real cryptographic handshakes, not mocked acceptance or a fabricated reference response. They do not show an arbitrary untrusted root being accepted. They show that a certificate signed under a trusted chain can be accepted outside the issuer's restrictions, and that unsupported critical semantics are ignored. Both Mo runtimes use this same engine, but these particular counterexamples were exercised at the ABI, not separately through each Mo row.

### 2. Step-36 recovery placement is fixed; accounting remains narrowly defined

`toolchain/bench/step36/abuse.py:89–135` now yields one case at a time. The loop at `157–164` performs its healthy echo before resuming the generator. The live rerun passed all eight rows per runtime, including the two 10.0-second timeout cases, early overflow rejection, full oversized payload attempt, and retry. [Raw rerun](evidence/2026-09-18/tls-independent-code/abuse.log).

The case named `64kib` constructs **65,535 body bytes** plus the five-byte header, not exactly 65,536 body bytes. The source accurately prints 65,535 in its description. `sendall` can encounter early rejection and its exception is intentionally swallowed, so this proves a whole oversized buffer was attempted, not that the server consumed the whole body. Early record-header rejection is appropriate.

`handshake.py:31–53` now checks process status, scans for errors, requires a count, and reports that connection count. Its explicitly allowed exit codes are 0 and 1, not only 0. The comment's OpenSSL-specific justification was not independently replicated here. This closes the unchecked-status issue conditionally, but `echoes lost` is still only the separate echo-probe failure count, not failures across all measured handshakes. The historical method remains `s_time`, not a loop of `s_client` processes.

### 3. The added native functionality passes its tests

The independent command `zig test toolchain/src/bricks/tls.zig -lc` with Zig 0.16.0 returned 0: **all 26 tests passed**. [Complete output](evidence/2026-09-18/tls-independent-code/native-tests.log).

This includes the four-cell suite/key matrix against Zig's independent client, client/server megabyte traffic with and without ALPN, fixture chain accept/refusal cases, both KeyUpdate initiators, client-side malformed inputs, and RFC 8448 client replay. The replay uses test-only entropy/layout/authentication accommodations; its pass is a byte-trace/key-schedule observation, not replacement evidence for certificate authentication. Separate authenticated tests and the new counterexamples matter.

The new `mo_tls_key_update` ABI and shared key-update function address the previous missing runtime-request operation. This does not assert a new public Mo-language KeyUpdate row was required or added.

The post-alert fix checks `mo_tls_read` state after feeding a handshake rather than interpreting `mo_tls_feed == ok` as continuing progress. The C cleanup helper frees the engine only while the connection still owns it, avoiding the prior cleanup's unconditional second free after socket release. These changes are causally consistent with the reported failure modes; no fault-reintroduced double-free experiment was run here.

## Evidence accounting and limitations

### Differential

The filed `diff-3737.log` contains **1,000 JSON session records with 1,000 distinct IDs**, **516 mo-client** and **484 mo-server**. Reapplying the pinned `diff.compare` to every saved pair returned **0 mismatches**, matching the filed count. [Recheck output](evidence/2026-09-18/tls-independent-code/differential-recheck.json). This rechecks the recorded observations with the same comparison algorithm; it is not a fresh 1,000-session network run or an independent oracle.

The differential is a substantial interoperability test, but generated parameters are narrower than arbitrary protocol inputs. In the mo-client path, the sampled `groups` value is not passed to `openssl s_server` (`diff.py:267–296`); the brick's client has a fixed suite offer. Sampled group variation cannot be credited uniformly to both roles. The fixture chain set does not contain the independently demonstrated extension restrictions. Consequently zero mismatches on this generator does not refute the counterexamples above.

### Fuzz hour

The raw `fuzz-3701.txt` prints: **87440 inputs in 2186 batches, seed 3701: 0 crashes; 3601 CPU s (60.0 min), 3569 s wall**. It records planted panic exit 134 and planted hang exit 3 before the timed budget. These are inherited measurements, not a rerun here.

A material reporting limitation is visible in `fuzz.py:169–190`: after a batch fails, the script increments `crashes` only for inputs that also fail when rerun alone. A failing batch whose inputs all pass alone leaves the crash count unchanged; the failed batch itself is not preserved as a counted failure. Thus a printed zero does not logically exclude batch-only, stateful, or nonreproducing failures. This is a control-flow finding, not evidence that such a failure occurred during seed 3701. The harness also has no final nonzero exit keyed to its mismatch/crash count; consume the reports rather than treating process exit alone as a gate.

### Suites and performance

Raw suite A1 and B1 record `exit=124`; A2, B2, C1 and C2 each report **5/5 steps succeeded; 234/234 tests passed**, `exit=0`. Do not silently discard the timed-out attempts or convert these historical passes into an independently rerun whole-project pass. The independent interpreter build returned 0; its empty successful build log is filed only as supporting execution output.

The stamped historical performance capsule prints best-of-five measurements. Client-to-OpenSSL handshakes/s are run/binary **1001/1354** for Ed25519 and **286/295** for P-256. Mo-to-Mo rates are **942/1445** and **271/280** respectively. Mo-to-Mo plain/TLS bulk MB/s are **43.7/38.6** for run and **336.9/256.6** for binary; these use decimal MB/s and a 100 MiB payload. Warm jobq before/after are **0.10 s / 0.09 s**, cold **20.1 s / 21.8 s**, sizes **5,429,960 / 5,541,240 bytes**.

Do not infer a clean causal chain-check cost from selected best samples. The Ed25519 binary chain row is **1382 handshakes/s**, while its self-signed row is **1239**; run rows are **927** and **1036**. The apparent reversal is itself reason to retain run conditions and variance rather than claiming chain checks speed up handshakes. These numbers are preserved, not replacement performance claims.

## Standing concerns

1. Certificate-restriction enforcement and unsupported critical extensions remain open; the completed-brick claim needs a bounded disposition and independent verification.
2. Keep the successful step-36 scheduling repair, while retaining the method and count definitions and exact oversized payload size.
3. Preserve failing batches even when single-input replay does not reproduce them; a zero-count report must not erase failed batch evidence.
4. Historical fixture interoperability and crash-budget completion are not security certification. Track generator exclusions and independently demonstrated counterexamples.

No stopping rule or implementation is changed by this reading.

## What would flip this reading

- A pinned clean fix plus the same actual-handshake counterexamples rejecting, with the valid control still passing, would resolve the reproduced chain findings. A documented narrower supported policy would clarify scope but would not change the current observed acceptance behavior.
- A failed-batch counter/report with preserved batch inputs and a labelled batch-only failure self-check would support a stronger fuzz-accounting claim. Supply raw output, not a prose assurance.
- A complete independently attributable suite rerun and expanded differential cases for chain restrictions would strengthen completion evidence. The candidate falsifier is concrete: one forbidden certificate shape reaching ready or one failed batch lost from the final report is sufficient to refute the corresponding broad validation claim.

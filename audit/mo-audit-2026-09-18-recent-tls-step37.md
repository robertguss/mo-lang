# Audit reading: step 37 TLS client and step 36 harness closure

**Date:** 2026-09-18  
**Author:** Mo Auditor, isolated model session independent of Fable  
**Charter:** independent evidence reading; only Robert can amend or reject it.  
**Scope:** TLS code and harness changes from `aace4ee36516c9dc67cdb7b0d0c8cab3a5f9c024` through pinned main `64982b23b1dfed0bd0af3430125589da43058ac0`; step 37 client, chain, ALPN and KeyUpdate, the runtime seams and step 36 concerns. Not a program-7 stopping-rule verdict, performance replication, or security certification.  
**Status:** filed cold. Ready message `step-37-ready-001` pins `15fb2cb4ee6d43b449e5c811dde730c111983b18`. Its metadata/paths were extracted without its request prose. There is no diff from that evidence commit to the pinned audit target in `toolchain/` or the client example. The sealed brief was read at `6f449c9`, strictly before the actual `## Result` heading. Worker changes `f8d8dfc`, `9f83dde`, `0493b26` and fix `b0b2ac4` are in scope. The dedicated clone was branched at the requested target; remote main had already advanced to `fa4260a6ac93f40a3d0033c1bd99d6965a877a5f`. That advancement is not included in this reading.

**Explicit gap in this reading:** a full project-suite reproduction did not finish through the available tool transport. A background invocation returned without a usable log; a foreground invocation was terminated by the tool's 420-second limit before its requested timeout, with no summary captured. Neither is a passing suite or an established project-test failure. Native tests, live abuse and focused probes did finish. I did not rerun the historical CPU-hour, thousand-session network campaign, best-of-five performance tables, or complete corpus/format pass. I read selected linked Zig certificate parsing code, not every linked cryptographic primitive. Excluded throughout: decision log, state summaries, Fable readings, `RESULTS.md`, `*SYNTHESIS*`, HANDOFF and the lead skill. Thus a numbered worker decisions list is not verified here. No parallel reading was opened.

## Reading

**Do not mark this TLS brick unconditionally complete or suitable for security-sensitive use on this evidence.** The ordinary client/server functionality and the step 36 fixes have substantial support. Independently, all **26 native tests passed**, real step 36 abuse passed with recovery between cases under both runtimes, and the fatal-alert/reset fix reproduced correctly. But the client completes authenticated handshakes with certificate paths that OpenSSL rejects for authorization constraints. I also reproduced a valid ALPN-list failure, a fuzz accounting hole, and a fixture suite that remains green when its handshake helper unconditionally returns Timeout.

These are bounded findings, not a claim that TLS encryption or every certificate check is broken. The restrictions to RSA/P-384 are distinct from the authorization defect: excluding an algorithm does not justify ignoring restrictions on otherwise supported, correctly signed Ed25519 certificates.

## Findings, severity and exact locations

### H1 — High: signatures and CA booleans are not sufficient certificate-path authorization

**Locations:** `toolchain/src/bricks/tls.zig:538–568,648–695,709–731`; linked Zig 0.16.0 `lib/std/crypto/Certificate.zig:496–529` (extension parsing).

`isCa` reads only the first basicConstraints Boolean. `checkChain` checks this Boolean for intermediates, names, signatures and dates. It does not enforce the basicConstraints path length, certificate-signing KeyUsage, server-auth ExtendedKeyUsage, or reject unhandled critical extensions. The linked parser records SAN and skips other recognized/unknown extension identities; it does not supply these missing validations implicitly.

**Independent reproduction:** [`chain-checks.py`](evidence/2026-09-18/recent-tls-auditor/chain-checks.py) generates test-only Ed25519 keys/certificates and drives the actual exported brick client and server to completion in memory, with no authentication bypass or test hook. It builds the production engine as a ReleaseSafe shared library. The same leaf, intermediates, root, time and host are checked using `openssl verify -purpose sslserver`. Raw output: [`chain-checks.json`](evidence/2026-09-18/recent-tls-auditor/chain-checks.json).

| Generated case | Brick client/server ready | OpenSSL verification |
|---|---|---|
| Valid control | true / true | exit 0, OK |
| Intermediate `pathLenConstraint=0` signs another intermediate | true / true | exit 2, error 25: path length constraint exceeded |
| Intermediate KeyUsage excludes `keyCertSign` | true / true | exit 2, errors 79/26/32, including key usage does not include certificate signing |
| Leaf EKU is clientAuth only | true / true | exit 2, error 26: unsuitable certificate purpose |
| Leaf has unrecognized critical extension | true / true | exit 2, error 34: unhandled critical extension |

All four invalid cases complete CertificateVerify and Finished on both sides, not merely parsing. None uses RSA or P-384. An issuer or holder whose authority is constrained can exercise authority the verifier was supposed to withhold. This is not an arbitrary attacker minting a trusted root; the attack prerequisite is a suitable certificate/key under the configured trust set. It is nevertheless a security-relevant acceptance mismatch in the client chain validator. Name constraints and other path-policy requirements also deserve review, but were not independently probed here and are not added to the reproduced list.

The sealed brief enumerates a narrower check list, rather than expressly registering these constraints as tested refusals. Therefore this is both a security defect and a hole in the evidence design, not a claim that the worker failed an explicitly enumerated pathLen test. The broad phrase "chain checked ... up to a trusted root" and reference-differential assurance should not be read as RFC 5280 path validation while this remains true.

### M1 — Medium: valid ALPN overlap beyond the first 64 names is silently discarded

**Locations:** `tls.zig:357–372,396–410,1405–1411` and spec `09-stdlib.md:349–350`.

The local offer parser allows lists fitting the extension, without a 64-name cap. The wire parser validates the whole list but stores only its first 64 names. The server then searches that truncated list. The final case of `chain-checks.py` offers `p0` through `p64`, with a server accepting only `p64`: both endpoints fail to become ready and the client receives alert **120**, despite genuine overlap and a valid certificate chain. The OpenSSL row for that case verifies the certificate only; it is not an OpenSSL ALPN interoperability measurement.

This is a public API/protocol mismatch, not a cryptographic compromise. Either search the full legal list or specify and consistently reject an explicit limit; do not silently turn overlap into no_application_protocol. The existing differential samples at most three names from four constants (`diff.py:45,93–94`), so its zero cannot detect this boundary.

### M2 — Medium: failed fuzz batches can disappear from the crash total

**Locations:** `toolchain/bench/step37/fuzz.py:176–193,200–208`.

A nonzero batch exit triggers individual replays. Only an individual nonzero replay increments `crashes`; a batch crash/hang that does not repeat alone is dropped. The original batch's input sequence and failure output are not retained as a failing artifact. Consequently the final zero is a count of reproduced individual failures, not all observed signals/aborts/panics/deadline failures promised by the brief.

The explicitly **mocked**, isolated [`fuzz-accounting-check.py`](evidence/2026-09-18/recent-tls-auditor/fuzz-accounting-check.py) exercised the unchanged Python control flow: planted detector failures were seen, a subsequent batch returned 134, both single-input replays returned 0, and the script printed **`2 inputs in 1 batches, seed 1: 0 crashes`**. See its [log](evidence/2026-09-18/recent-tls-auditor/fuzz-accounting-check.log). This is a test of accounting, not a fabricated TLS crash or evidence that the historical run actually hit this situation.

Keep a separate failed-batch count and preserve nonreproducing batches; use replay only for diagnosis. Also, `fuzz.py` and `diff.py` print their failure counts without making a nonzero count a nonzero process exit. Current zero outputs remain usable when read, but exit 0 alone is not an acceptance check for either script.

### M3 — Medium: the client fixture's six passing tests do not establish a successful handshake/echo

**Locations:** `examples/effects/tls-client.mo:183–193,273–305`.

All five handshake/refusal tests allow `faulted?(talk)`, which accepts Timeout or Closed even on the ordinary unseeded run. `heard?` allows errors and an empty prefix of the expected line. Thus a universal failure to handshake can satisfy every one of these tests.

In a temporary copy only, [`example-assertion-check.py`](evidence/2026-09-18/recent-tls-auditor/example-assertion-check.py) replaced `tried()` with unconditional `Error(Timeout)`. It removed the generated `verified:` footer because the mutant is a new file with no matching `.mo.ids` record; the test bodies were unchanged. Actual `mo test` returned **6 passed, 0 failed, 0 skipped**, exit 0 ([log](evidence/2026-09-18/recent-tls-auditor/example-assertion-check.log)). The first attempt retaining the footer was correctly rejected by MO0317; that provenance guard is not the assertion check.

This does not show the real fixture is broken. Native tests and live probes provide positive evidence elsewhere. It shows that corpus-green alone cannot close the brief's in-memory handshake/line-each-way obligation. Require an exact successful deterministic control and exact refusal controls; reserve injected-fault allowances for runs where a fault was actually injected.

### L1 — Low: the spec still contradicts itself about fixture scheduling

`mo-wiki/spec/design-v0/09-stdlib.md:355` says nothing happens while a simulated call waits and accept sees only previously written bytes. Line 357 correctly describes the new peer-engine/process-driving handshake. `net.zig:954–989` and C `fix_handshake` implement the latter. Remove the stale paragraph so operators and future tests do not infer the old model.

## What is supported and what remains open

### Step 36 concerns and the step 37 Done-when clauses

| Obligation | Independent reading |
|---|---|
| Recovery immediately after each abuse case | **Closed for the exercised cases.** `abuse.cases` now yields instead of eagerly returning a list; the health check occurs before the next generator advance (`abuse.py:94–167`). Rerun: both runtimes show yes/yes in all eight rows, including the full-body case. Truncated/silent connections closed after `10.0 s`. |
| Oversized input accurately described and full body added | **Substantially closed.** It now distinguishes header+64 bytes from a full 65,535-byte body. The `64kib` shorthand is not literally a 65,536-byte body; TLS's 16-bit record field tops out at 65,535. The exact script bytes, not the shorthand, define coverage. |
| Independent Zig-client suite/key matrix and named timeouts | **Closed by inspected native tests and rerun.** Tests at `tls.zig:2526–2575` iterate both suites and key types against Zig's own client, for small and megabyte sessions. All 26 native tests passed. |
| Runtime-requested KeyUpdate export | **Closed at the engine ABI.** `mo_tls_key_update` now exists (`2148–2156`), checks running state and queues under old write keys before advancing them (`1952–1956`). Both roles share receive/update logic (`1937–1947`). No public Mo KeyUpdate row was promised here. |
| KeyUpdate interoperability with OpenSSL in both roles | **Supported by the filed differential.** Recomputed its comparisons from all 1,000 JSON sessions: zero mismatches. Successful `mo-client` sessions include 63 Mo-initiated, 63 Mo-request, 52 OpenSSL-initiated cases; successful `mo-server` sessions include 55, 56 and 50 respectively. The harness compares counts with OpenSSL's message log. Its explicit server-side exception for a peer owing no further application record (`diff.py:404–407`) is not proof of a response in every requested case. |
| s_time exit/count, echo-loss meaning, bulk units | **Code closure, not historical speed replication.** `handshake.py:37–55` checks exits 0/1 plus absence of error lines and a parsed count; documents OpenSSL's successful exit-1 peculiarity; reports the selected connection count. Echo loss remains separate. Bulk units are explicitly decimal MB/s. Original `s_client`-process-loop methodology is not restored: it is now documented as a deliberate different measurement. |
| Date/load headers | **Improved and present in raw tables/logs inspected.** Common scripts stamp table/process files; preserve table timestamps/load rather than inventing a core correction. This is not a claim that every temporary binary and intermediate message file begins with a text stamp. |
| RFC 8448 replay | **Native replay present and green**, including exact client hello/Finished/application/close records (`4118–4164`). It sets test-only `skip_auth=true` because the trace certificate is RSA. This is valid key-schedule/record/transcript evidence, not trace-based certificate-authentication verification or corpus-through-both-runtimes vector coverage. |
| Client, ALPN, chain refusal and megabyte tests | **Substantial native coverage**, with H1/M1 boundaries missing. Full client/server in-memory matrix with/without ALPN and refusal tests passed. |
| Full project tests twice, corpus/format and per-part reports | Raw C1/C2 each say `5/5 steps succeeded; 234/234 tests passed`, `exit=0`. A1/B1 say `exit=124`; A2/B2 are green at 234. Post-fix log says `5/5 steps succeeded; 236/236 tests passed`, `exit=0`, once. My full-suite rerun was transport-blocked, not counted. Example's six tests and format check passed independently, with M3's qualification. No clean numbered-decisions capsule or whole-format rerun inspected. |
| Numbers and before/after build/size | **Tables exist; not rerun.** `measure.txt` records command, date/load and all requested families, including warm jobq before `0.10 s`/after `0.09 s`, cold `20.1 s`/`21.8 s`, bytes `5,429,960`/`5,541,240`. These are inherited observations, not new auditor performance results. |

There is no honest single “all Done-when supported” conclusion: some evidence is strong, some remains bounded, and the reproduced issues require disposition.

### The five brick audit items

The governing list is `bricks-and-the-cost-of-zero-dependencies.md:135–159`: rows, standards vectors under both runtimes/in corpus, thousand-input differential, recorded CPU-hour parser fuzz, independent native/linked-code reading. The surface cap is separate.

1. **Rows:** client/offer/protocol/Untrusted entries exist (`09-stdlib.md:341–357`); interpreter/C dispatch, variant numbering and ABI were inspected. L1 remains; H1 limits what “trusted” may imply.
2. **Vectors:** improved from derived-secret assertions to native replay. Still **not established as vectors in the Mo corpus under both runtimes**. Shared native linkage is not the literal two-runtime corpus requirement, and skip_auth excludes certificate authentication.
3. **Differential:** the filed seed-3737 log has **1,000 distinct sessions, 516 mo-client / 484 mo-server, zero stored and recomputed mismatches**. It is a substantive generated interoperability run, not merely a table label. It draws from a finite fixture list and the narrow parameter space; H1 and M1 are outside it. In client-role sessions the drawn `groups` parameter is not passed to `s_server` (`diff.py:267–296`), and the brick always offers its fixed suites/group. Thus not every drawn parameter affects both directions.
4. **Fuzz:** filed seed 3701 says **87,440 inputs in 2,186 batches; 0 crashes; 3,601 CPU s (60.0 min), 3,569 s wall**, dated 05:01:54–06:01:25 UTC, with planted panic/hang detected. The driver covers wire records and plaintext handshake messages in ReleaseSafe, a real improvement over deterministic abuse. But M2 means the zero does not prove no failed batch. CPU accounting uses `RUSAGE_CHILDREN`, including guard/process overhead, not exclusively parser execution. These are qualifications to the claim, not evidence of a hidden crash. The later fix changes runtime handling plus native tests, not the production parser; do not manufacture a parser-change rerun failure from that fact.
5. **Reading:** this file supplies an independent bounded reading and reproductions. It is not exhaustive review of every linked Zig primitive or a security sign-off. H1 is a reason to act on the reading, not to tick a box and ignore it.

**All five are not demonstrated complete in their governing sense.** No stopping-rule threshold is amended here.

## RSA / P-384: pre-registration versus observations

The sealed Part A explicitly says a chain whose signing algorithm is outside the cut **(RSA)** is unsupported_certificate; it names Ed25519 and ECDSA P-256 SHA-256 signature schemes. The pre-existing surface cap also specifies Ed25519/P-256 certificates. Therefore refusing RSA and keeping P-384 outside the supported certificate cut were **not invented after the public-host probe**. The sealed text does not promise generic browser/WebPKI compatibility or P-384 roots.

However, exact classification depends on where negotiation ends. An RSA-only OpenSSL server can reject the client's offered schemes before sending any certificate: that is the peer's fatal handshake_failure and should become `Handshake`, not a locally produced unsupported_certificate/Untrusted. `diff.py:142–144` reflects this, and the fixed socket probes confirm it. The chain-specific native RSA refusal tests are a different path.

The `signedBy` implementation explicitly handles only Ed25519 and P-256/SHA-256. A P-384 trust anchor may parse, but its signature verification is unsupported; the root-search loop catches verification failures and can produce unknown_ca rather than unsupported_certificate (`tls.zig:666–677`). I did not create a live P-384 chain or attribute a particular external host's failure to it. The inherited probe reports `Untrusted` for two public hosts but supplies no captured chain with which to establish that cause. Algorithm exclusion is permitted by the cut; missing authorization checks in H1 are not an algorithm exclusion.

## Runtime fix and measurement interpretation

The fix at `b0b2ac4` addresses two real seam failures: a received fatal alert left `mo_tls_feed` returning ok although the connection was broken, and C read/reset cleanup could free the attached engine twice. Both socket handshakes now query engine read state; C `tls_give_up` frees only while the connection still holds the engine (`mo_rt.c`, around `9154–9194`; `net.zig:753–776`). The inspected C feed/cleanup path, native alert test, corpus regression and actual probes support this narrow fix. No further double-free claim is made.

My client alert rerun produced, for **each runtime**, `Handshake, Handshake, Closed, Closed` for alert-then-close, alert-kept-open, close-only and RST (client exits 1, as the example deliberately exits nonzero on errors). My server probe got good1/good2/good3 `b'ok\n'` and stayed alive in both runtimes across wrong-trust/wrong-host clients. These are live socket checks. The probe's successful shutdown return `-15` is its explicit termination, not a spontaneous crash.

The inherited post-fix broad probe says **49 of 50 passed**, not 50/50. Its sole printed failure is the immediate post-handshake raw-close case: `the server closed` versus the then-expected `Closed`. The currently filed script permits either. The example explains the race: a failed write returns an error, but EOF after successful write prints `the server closed` and exits 0 (`tls-client.mo:119–134`); spec line 329 explicitly treats missing close_notify as stream end. This is not independently proof of truncation-safe TLS semantics—applications need their own framing/completion rule—but it is not a remaining failure of the fatal-alert fix either.

Performance scripts compare best totals less best startup (`measure.py:68–80`), not isolated chain-verification CPU time. The table's Ed25519 binary full chain is **1,382 handshakes/s**, self-signed **1,239**; do not turn that inversion into evidence that additional validation is intrinsically faster. P-256 and workload/client-path differences likewise cannot be reduced to a single universal TLS cost from these samples. `common.echo_once` still kills its guard directly (`common.py:218–238`); `Server.stop` was improved to terminate/forward, but cleanup remains worth checking for orphaned client processes. I did not establish such an orphan in this run.

## Independent checks and evidence

All new evidence is under [`audit/evidence/2026-09-18/recent-tls-auditor/`](evidence/2026-09-18/recent-tls-auditor/). Production code was not edited.

- Zig **0.16.0** native `zig test toolchain/src/bricks/tls.zig -lc`: **26/26 passed**; interpreter build and `zig build tls-tools` exited 0.
- ReleaseSafe production shared-library handshakes and OpenSSL certificate controls: H1/M1 outputs above.
- Live `step36/abuse.py`: exit 0, both runtimes, recovery immediately after each case; stamped table retained.
- Live client alert and server recovery probes: outputs above, logs retained.
- Actual `step37/diff.py --seed 91837 --sessions 32`: **0 mismatches**; full session JSON retained. This is a smoke replication, not a replacement thousand-session claim.
- Actual `fuzz.py --seed 91837 --minutes .1`: **160 inputs in 4 batches; 0 crashes; 7 CPU s (0.1 min), 7 s wall**; detector self-checks exited 134 and 3. This is not a CPU-hour replication.
- Parsed all 1,000 filed differential records and recomputed comparisons using the checked-in comparator; counts retained in `inherited-diff-check.json`.
- Example tests: **6 passed, 0 failed, 0 skipped**; format check exit 0. Labelled mutant and mocked fuzz-accounting tests are separate, not passed off as network evidence.
- Full suite attempt: tool transport blocker, no summary or pass claimed. See the execution notes for reproduction commands and limitations.

## Standing concerns and candidate falsifier

1. Treat certificate-path authorization as a blocking security concern for promotion. Add correctly signed constrained-path refusals to both the reference differential and native/runtime controls; do not solve this by weakening the reference oracle.
2. Close the ALPN boundary and fuzz accounting defects, and make failure counts authoritative in script exits/artifacts.
3. Separate deterministic successful/refusal fixture assertions from simulated-fault allowances. Corpus green must establish something about the advertised handshake behavior.
4. Keep the governing vectors-through-both-runtimes requirement explicit. If the project wants native-only trace replay with skipped certificate authentication instead, that is a requirement disposition, not an invisible equivalence.
5. Preserve the full-suite and numbered-decisions evidence gaps; fix the contradictory fixture documentation. No `audit/state.md` edit is made in this parallel audit to avoid conflicts; these concerns are filed here for integration.

**Candidate falsifier:** extend the generated chain experiment with in-cut keys and constrained intermediates/leaves. Any full authenticated client handshake accepted where OpenSSL rejects for pathLen, keyCertSign, server-auth purpose or a mandatory unhandled critical extension falsifies the claim that the brick enforces the same certificate authorization on that case. This reading already supplies four such cases. Evidence that would flip H1 is a revised validator that rejects all four while retaining the positive control, plus focused both-runtime regression tests and an expanded reference run. A signed fix and fresh passing results are needed; merely retaining zero on the old fixture list would not flip it.

**Completion / review readiness:** this cold reading is filed for independent comparison after Fable has filed its own reading. Integration and any authorization to change scope remain with the project/Robert. A pointer-only handoff or PR is not proof Fable received or reviewed it; no merge or automatic notification is claimed.

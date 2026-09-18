# Audit reading: step 36 — TLS server half

**Date:** 2026-09-18  
**Author:** Mo Auditor (fresh isolated model session, independent of Fable)  
**Charter:** independent evidence reading; only Robert can amend or reject it.  
**Scope:** step 36's TLS 1.3 server, its two fixes, the five brick audit items, and the measurement conditions. This is not a program-7 stopping-rule test or a security certification.  
**Status:** filed cold against main `aace4ee36516c9dc67cdb7b0d0c8cab3a5f9c024` (`audit: parallel-filed records for step 35 and the speed probe, both readings committed`); ready record `step-36-ready-001` pins evidence `cb61ac625d4b2e2a07b338105fa32780cdf66272`. Main's remote SHA matched at entry and before branching. The four specifically named implementation/example/bench files have no diff between that evidence commit and main.

**Explicit gap in this reading:** the safe evidence inspected does not establish every Done-when clause. I did not read `RESULTS.md`, the decision log, any Fable reading, or the plan's Result/Fix sections. Pane reports were not displayed wholesale: only exact standalone test/build-success lines were eligible, and fix1 lines 187–219 were excluded. This leaves the numbered worker decisions, warm jobq build/size before-and-after measurements, and independently attributable whole-corpus/whole-format results unverified. The full project test suite and original performance measurements were not rerun. I reviewed the server native code, not all linked Zig standard-library implementation code.

## Independence and recovery

The previous child stopped before changing this checkout following contaminated terminal evidence. This is a new context without its conclusions; its exposed context was not reused. I received the location to exclude, not the excerpt. This reading was derived from the authorized pre-Result brief, implementation, raw numerical/test output, and new checks. Bundle README descriptions are provenance claims, not substitutes for test output. No parallel comparison was performed. Manual notification remains the operative arrangement; filing a PR does not demonstrate that Fable awakened or read it.

## Reading

**The evidence supports a functioning, substantially tested server half after the two fixes, but not an unqualified assertion that every original Done-when requirement, or the full brick's shelf gate, is satisfied.** The named alert/timeout outcomes are reproducible in both runtimes. The fixes are real and appropriately narrow. However, the abuse script does not perform the per-case recovery checks its labels promise; the four-cell native interoperability matrix is not all against Zig's independent client; and some brief requirements lack safely inspected evidence or an implementation entry point. These are narrower conclusions than rejecting the server's observed functionality.

The five brick items are **rows, standards vectors, differential run, fuzz budget, independent reading**. The surface cap is an additional constraint, not a replacement for the reading item. Step 36 is not evidence that all five are complete. No S-A/S-B/S-C or T-A/T-B/T-C verdict follows from this subject.

## What the auditor read cold

- Audit folder guide, charter, operating manual, workflow and automation README; the named ready record and evidence README, including the daily load note.
- `mo-wiki/plans/interpreter-step-36.md`, only the content preceding `## Result`; the brick audit-budget/cap requirements in `mo-wiki/deep-dives/bricks-and-the-cost-of-zero-dependencies.md:135–167`; the `## Tls` spec section.
- Worker commit change inventories for `9c753e1`, `dd2e385`, `4cb0fc8`; permitted fix messages and actual diffs for `6af598d44c77650dc749cb36dbd5804390e4dd85` and `0fe966992da8ec77443afa8e9af842e40a1fa27f`.
- `toolchain/src/bricks/tls.zig` production engine and relevant test code; `tls_rows.zig`; the echo example; bench `abuse.py`, `common.py`, `handshake.py`, `bulk.py`, `guard.py`, and README.
- Original raw handshake, bulk, idle and abuse tables; allowlisted PASS/count lines from the probe and suite logs, and timeout/test lines from the before-fix log. The sole exact standalone pane summary recovered was fix1 line 31: `All 16 tests passed.` No other pane content is relied upon.
- New reproducible checks and actual output: [`evidence/2026-09-18/step-36/auditor-checks.py`](evidence/2026-09-18/step-36/auditor-checks.py) and [`auditor-checks.json`](evidence/2026-09-18/step-36/auditor-checks.json).

## What the evidence shows

### Fixes and Done-when

| Requirement | Observation and limit |
|---|---|
| Brick tests / KeyUpdate fix | Before-fix raw log reaches test 11 and the 300-second timeout. Fix1 adds `mo_tls_sent` to the KeyUpdate flush loop, bounded write polling, and client-thread shutdown/join cleanup. Its diff is test code only. Independently rerun: **all 16 native tests passed**, including KeyUpdate, RFC schedule, rejection cases and the suite/key matrix. The filed post-fix project log says `Build Summary: 5/5 steps succeeded; 225/225 tests passed`; this larger run is inherited, not independently rerun. |
| Certificate-path fix | Fix2 changes the example to `tls/cert.pem` and `tls/key.pem` and moves the bench cwd/copy layout accordingly. Independently, the example ran from `examples/effects` and printed `listening on 18443` and `served 0 connections, then went quiet`; its three Mo tests passed and its format check exited 0. Live abuse also built and exercised the binary. This supports this example, not an independently rerun whole corpus. |
| Both suites and key types | Raw OpenSSL handshake/echo rows cover both suites, both keys and both runtimes. Native matrix tests at `tls.zig:2099–2109` use `TestClient`, which shares the brick's record layer/key schedule (`1801–1809`). They do **not** fulfill literally the brief's entire matrix against Zig's independent `std.crypto.tls.Client`. Native Zig-client tests plus OpenSSL interoperability are valuable, but not identical to that specified test. |
| Abuse outcomes and recovery | Original and new runs return alert 10 for HTTP, 70 for TLS1.2, 40 for P-256-only, 22 for oversized header; truncated/silent connections close after `10.0 s`; HRR case echoes. Both runtimes show yes/yes in all rows. But recovery placement is wrong; see below. |
| Runtime-requested KeyUpdate | The brief asks for a KeyUpdate sent on runtime request, although unused this step. The inspected exports (`tls.zig:967–1089`) expose no such request operation; `keyUpdate` only answers a client's request (`926–935`). This clause is not demonstrated by the client-request round trip. The two fixes do not add it. |
| Rows, README, numbers, decisions | Tls spec rows and runtime/build changes exist in the worker commits. Four original bench tables exist and carry the numbers below. Safely inspected evidence does not verify the full warm-build/size comparison or numbered decisions list. Their possible presence in excluded synthesis is not proof of absence, but cannot be credited here. |

**Recovery-check defect, reproduced without changing engineering code.** `abuse.cases()` builds and returns a list (`abuse.py:83–119`); Python completes all seven cases before the loop at `142–145` begins. Therefore the seven `serving after` checks all run after the entire batch, not immediately after their corresponding case. A separately labelled **mocked control-flow check** produced:

```
http, tls1_2, p256only, truncated, silent, oversized, retry,
health, health, health, health, health, health, health
```

The mock establishes scheduling, not TLS behavior. The real rerun establishes the printed alert/timeout outcomes and end-of-batch health. It does not establish the promised immediate recovery after each abusive input. The oversized case sends a header declaring 65,535 bytes plus 64 body bytes, not an actual 64-KiB body: useful early length rejection, but label the exercised shape accurately.

### Five audit items and the cap

| Item | Step-36 evidence | What remains |
|---|---|---|
| Rows | `Platform.tls`, `Tls.server`, `TlsServer.accept`, fixture, error/crash semantics in chapter 9; shared engine and interpreter seam inspected. | No claim of exhaustive C-runtime or capability-enforcement verification from this reading. |
| Standard's vectors | RFC 8448 section-3 derived-secret assertions in native test `1744–1789`; independently green. | This is a key-schedule subset, not full trace replay or vectors exercised through both Mo runtimes in the corpus as the brick gate specifies. |
| Differential run | OpenSSL handshake/echo matrix, abuse and extra conformance cases exist. | No recorded thousand-generated-input reference differential with mismatch count in this inspected bundle. The sealed brief explicitly assigns the OpenSSL differential run to step 37. Interoperability examples are not that run. |
| Fuzz budget | Deterministic malformed-input tests and abuse cases. | No dated one-CPU-hour parser fuzz run / zero-crash count shown. The server-half scope does not silently waive it. Treat it as outstanding for the completed brick; the pre-Result brief does not explicitly schedule the hour. |
| Independent reading | This reading inspects the server engine against the cap and records limitations. | It is a bounded reading, not exhaustive review of all linked Zig code or the future client. The full shelf requirement is not closed by treating the cap as item five. |

The production engine uses `std.crypto` primitives; supports the two named SHA-256 suites, X25519, Ed25519/P-256 certificates and client KeyUpdate; and does not implement tickets, resumption, TLS1.2, PSK or client authentication. ALPN is ignored, consistent with the step's explicit deferral, but the full shelf cap includes ALPN. The **client, certificate-chain validation and ALPN**, together with the specified differential run, belong to step 37 under the sealed brief. Serving a configured certificate chain here is not client-side chain validation. No independent evidence here closes the deferred requirements in advance.

### Original numbers, preserved as printed

Source: `audit/evidence/2026-09-17/step-36/worker-raw/`.

| runtime | key | suite | handshakes/s | echoes lost |
|---|---|---|---:|---:|
| run | ed25519 | aes128gcm | 1026 | 0 |
| run | ed25519 | chacha20 | 1046 | 0 |
| run | p256 | aes128gcm | 765 | 0 |
| run | p256 | chacha20 | 754 | 0 |
| binary | ed25519 | aes128gcm | 1196 | 0 |
| binary | ed25519 | chacha20 | 1172 | 0 |
| binary | p256 | aes128gcm | 804 | 0 |
| binary | p256 | chacha20 | 818 | 0 |

| runtime | over | MB/s (100 MiB each way) | µs a round trip (1000 of them) |
|---|---|---:|---:|
| run | plain | 488.1 | 27 |
| run | aes128gcm | 202.7 | 38 |
| run | chacha20 | 121.3 | 40 |
| binary | plain | 477.1 | 23 |
| binary | aes128gcm | 267.7 | 28 |
| binary | chacha20 | 155.3 | 25 |

| runtime | over | before | after 1000 | per connection |
|---|---|---|---|---|
| run | plain | 21492 KiB | 24384 KiB | 2.9 KiB |
| run | TLS_AES_128_GCM_SHA256 | 21784 KiB | 31356 KiB | 9.6 KiB |
| binary | plain | 15092 KiB | 20992 KiB | 5.9 KiB |
| binary | TLS_AES_128_GCM_SHA256 | 15656 KiB | 28248 KiB | 12.6 KiB |

Computed plain/TLS bulk-rate ratios, rounded to three decimals: run AES **2.408×**, run ChaCha **4.024×**, binary AES **1.782×**, binary ChaCha **3.072×**. Thus three aggregate echo measurements exceed a twofold bulk cost. They do not isolate a single record read/write: the plain client is Python sockets while TLS uses OpenSSL and pipes. `bulk.py:85–86` computes decimal MB/s even though payload size is expressed in MiB; retain that distinction. The microsecond table is the bench's equivalent line-round-trip workload, not a rerun of a separately named echo-1k executable.

`handshake.py:26–42,57–64` uses `openssl s_time -new`, not the pre-registered `s_client` process loop. Its `echoes lost` counts separate echo probes, **not failed handshakes among every s_time connection**; s_time's return code is not itself checked. This is a measurement-method deviation worth documenting, not proof the printed rates are false. Defaults select best of five; the safe tables alone do not retain all five samples or prove invocation flags. `common.rss_of` includes the watchdog process and descendants, so the idle delta is a harness-inclusive RSS observation, not exact engine allocation size.

The extra filed probe prints **22/22 passed**, including 60,001 returned bytes, 50/50 concurrent echoes per runtime, client KeyUpdate then application data, unsupported-suite refusal, certificate checks and dropped-socket recovery. Its RSS observations are `61504 -> 62772 KiB (+1268)` for run and `17360 -> 17996 KiB (+636)` for binary. These are inherited observations; I inspected its script but did not rerun it. The script has a lead-checkout absolute import path, another reason not to execute it unchanged in an isolated checkout.

### Load condition

The daily README reports a four-core VM with a spinning one-core process until **21:26 UTC**. The step-36 README specifically reports a quiet-machine observation, load **0.38 at 6:48 PM ET**, after that process was killed, and places these benchmarks before the fixes. The fixes change tests and file paths, not the timed engine.

**The condition is material to interpreting or comparing rates, but it is not evidence that this step's tables were measured under the earlier one-core loss.** The later subject-specific provenance is more pertinent than the daily note's blanket wording. I did not reconstruct per-run load from raw `uptime`/`ps` records, which are not in the inspected tables. Do not apply a guessed core-count correction or compare absolute rates with differently loaded runs without preserving this caveat. Current checks are correctness runs, not replacement performance measurements.

## Auditor's independent verification

Using pinned Zig **0.16.0** installed through uv's tool cache, without editing project code:

- TLS native suite: **16/16 passed** (including the repaired KeyUpdate test).
- Interpreter build: exit **0**.
- Example format check: exit **0**.
- Example Mo tests: **3 passed, 0 failed, 0 skipped**.
- Example run from corpus cwd: exit **0**, expected listen/idle output.
- Live abuse script: exit **0**, both runtimes' seven rows show expected outcomes and end-of-batch recovery; this includes a newly built binary.
- Mocked ordering trace: confirmed all seven health checks follow all seven cases; clearly separated from real network evidence in the JSON.

Not rerun: complete `zig build test`, complete interpreted/compiled corpus, historical performance best-of-five runs, thousand-connection memory measurement, extra 22-case probe, fault-reintroduced KeyUpdate timeout test, or a CPU-hour fuzz campaign. No new performance claim is made.

## Standing concerns filed with this reading

1. **Do not promote the server-half evidence to a completed TLS shelf audit.** Track full vector/corpus coverage, thousand-input differential, dated parser fuzz hour, linked-code reading and the deferred client/ALPN work explicitly.
2. **Close the Done-when evidence mismatches rather than silently weakening the brief.** Per-case recovery placement, independent-client matrix coverage, runtime-initiated KeyUpdate, handshake failure accounting/method, and clean corpus/format/build-size/decisions evidence need explicit disposition. This reading does not authorize implementation or amend a requirement.
3. **Keep cold evidence free of embedded synthesis.** Standalone command/output capsules are needed instead of terminal-pane transcripts containing decision-log material. This recovery avoided the identified excerpt; future intake should not depend on a human-provided forbidden line range.

These are mirrored by a pointer in `audit/state.md`; no prior concern or ratification is changed.

## What would flip this reading

- A clean pinned capsule demonstrating the remaining Done-when items, immediate successful echo **between** each abuse case, genuine independent-client suite/key coverage, and the runtime-requested KeyUpdate behavior (or Robert's explicit authorized scope amendment) would support a stronger completion statement.
- A generated malformed-record/handshake differential plus the recorded CPU-hour fuzz budget is a candidate falsifier of the server's robustness claim: any accepted forbidden shape, incorrect alert, crash, unbounded wait or failed healthy echo after a case would overturn that claim for this cut. This reading does not assert that deterministic abuse is a substitute for this experiment.
- Load-stamped repeated measurements with the same client paths could revise the cost interpretation; no adjustment is inferred from the earlier machine condition alone.

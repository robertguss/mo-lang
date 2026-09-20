# Step 44 report: bounded byte chunks from `Conn`

Worker: GPT-5.6-Sol, bounded implementation worker in a fresh OMP session. Branch
`toolchain/step-44-conn-chunks`; plan
`mo-wiki/plans/interpreter-step-44.md`.

- Exact base: `c4462935fdbcf99d3b8b53258828d028d68594bc`.
- Final implementation and evidence commit before this report:
  `b209b8bebee357ea48a32aa6dd1d49d96ccf80b0`.
- Final delivery tree: that commit plus this report commit (`this`); the report
  commit's exact hash is sent to Astra after the commit.
- Measurement checkpoint: `9c67ec1f1cfbf95ae625d0227ef9de8f86467c7a`.
- Every `mo`, Zig build/test, socket probe and measurement ran through
  `toolchain/bench/step36/guard.py` with a hard deadline. No subagents, push,
  Linux run, machine run or unfiltered suite.

## Commits

| commit | change |
| --- | --- |
| `dd35d185615323b8b7557f77ab9deb2f83690c84` | public prelude, checker, emitter and VM dispatch |
| `25f3be08c89d89095d45933f4fc43bf117a6a72d` | interpreter, fixture and native runtime implementation |
| `a99f37df4c68602af2d8ab104675c6fdcc1df786` | fixture corpus, real-socket probe and throughput drivers |
| `9c67ec1f1cfbf95ae625d0227ef9de8f86467c7a` | benchmark payload identity and workload geometry |
| `b209b8bebee357ea48a32aa6dd1d49d96ccf80b0` | focused raw evidence and exit records |
| `(this)` | final report; committed last |

## Delivered contract

`Conn.chunks(into: Handle(P), max_bytes: UInt64, idle: Duration) -> none`
registers the connection's sole input reader. `P` must declare exactly the
required shapes:

```mo
message Chunk(bytes: List(UInt8))
message Closed
message Idle
```

The implementation has these observable rules in both runtimes and fixtures:

- `max_bytes` is validated as the full `UInt64` value before reader ownership,
  source creation, input mutation or payload allocation. The accepted range is
  1 through 65,536; zero, 65,537 and UInt64's maximum crash without truncation.
- Every `Chunk` is nonempty, contains the original bytes, and is at most
  `max_bytes`. No UTF-8 or line interpretation is performed. Boundaries are
  deliberately unspecified.
- Bytes retained by an earlier successful `read_line` are delivered first.
  Available short data is delivered while the peer remains open.
- One connection has one reader. Duplicate `chunks`, `lines` after `chunks`,
  `chunks` after `lines`, and a pull read already waiting are rejected before a
  second source is installed. A later `read_line` returns `Busy`.
- Mailbox backpressure pauses the source. Each chunk's `List(UInt8)` is owned by
  its packed message before the source buffer is reused.
- Normal input EOF drains pending chunks, sends one `Closed`, and retires only
  the input source. The local write half remains usable. Local full close is
  silent; idle sends one `Idle` and closes; target death closes the connection;
  a broken stream sends `Closed` and becomes unusable.
- TLS sources read authenticated plaintext through the existing TLS engine.
  Starting TLS after `chunks` is rejected by the existing `used` guard. The TLS
  corpus completes a handshake, installs chunks on the client, writes a line in
  the reverse direction, and receives the server's plaintext without TLS EOF.
- `Conn.lines` remains on its prior path. `Chunk` is a fixed runtime message
  name in generated C.

## Contract findings and decisions

1. **A public fixture cannot initiate directional EOF.** `Conn.close` remains a
   full close; it was not reinterpreted. The fixture now has an internal
   `write_closed` direction used by the runtime-level regression test. Public
   half-close behavior is proven over real sockets under both runtimes.
2. **`Closed` means input termination, not peer receipt of a reply or remote
   FIN.** The half-close probe sends arbitrary bytes, shuts down only its write
   half, receives `Closed` in Mo, and then receives a response written on the
   still-open reverse direction.
3. **Generic process message checking compared resolved type IDs.** That
   rejected a valid `List(UInt8)` field instantiated through `Handle(P)`. The
   checker now unifies the required and declared field types while still
   requiring the exact field name; the focused positive/negative checker test
   covers `bytes` versus `data`.
4. Generic runtime crashes are not `test rejects` contract failures. Duplicate
   registration and late-handshake preconditions are therefore covered at the
   runtime level and by `used`/source-state assertions rather than mislabelled
   corpus tests.

## Focused verification

All paths below are under `toolchain/bench/step44/`; every paired `.exit` file
contains the reported exit code.

| check | result | raw evidence |
| --- | --- | --- |
| preimplementation checker RED | exit 1: `Conn` has no `chunks` | `red-check-03.log`, `red-check-03.exit` |
| final `zig build` | exit 0 | `final-build-01.log`, `final-build-01.exit` |
| exact generic message shape | exit 0; 1/1 | `checker-shape-test-01.log`, `.exit` |
| chunks source under injected faults | exit 0; 2/2 | `chunks-fault-test-01.log`, `.exit` |
| bounds, ownership, directional EOF, reverse write, target death | exit 0; 2/2 | `directional-eof-test-04.log`, `.exit` |
| chunks fixture corpus | exit 0; 8/8 | `chunks-test-write-07.log`, `.exit` |
| chunks schedule sweep | exit 0; 8 tests × 40 seeds, faults 0 | `chunks-sim-03.log`, `.exit` |
| native compiled chunks fixture corpus | exit 0; 8/8 | `chunks-build-tests-01.log`, `chunks-binary-test-01.log` and exits |
| TLS chunks fixture corpus | exit 0; 1/1 | `chunks-tls-test-write-09.log`, `.exit` |
| TLS fault sweep | exit 0; 40 seeds at 20%, held under faults | `chunks-tls-sim-faults-01.log`, `.exit` |
| native compiled TLS chunks corpus | exit 0; 1/1 | `chunks-tls-build-tests-01.log`, `chunks-tls-binary-test-01.log` and exits |
| unchanged established TLS client corpus | exit 0; 7/7 | `existing-tls-client-test-01.log`, `.exit` |

The generated `examples/step44/.mo.ids` and both files' `verified:` lines came
from successful `mo test --write` runs.

## Real-socket positive controls

The exact unchanged client is `workspace_http.client.connect`. It sends the
155-byte JSON body without a newline and without `shutdown`, then reads the
response before closing.

| scenario | interpreter | native binary | observation | raw evidence |
| --- | ---: | ---: | --- | --- |
| unchanged client F1 | exit 0 | exit 0 | status 200 before close; server read 342 request bytes in 6 chunks | `f1-positive-run-04.*`, `f1-positive-binary-03.*` |
| arbitrary bytes plus half-close | exit 0 | exit 0 | 10 bytes, sum 1119, NUL, invalid UTF-8, split multibyte sequence, 4 sends; response after input EOF; 4 chunks | `half-close-run-02.*`, `half-close-binary-02.*` |
| unfinished oversized header | exit 0 | exit 0 | client sent 2,083 bytes without EOF; server returned 431 after 1,088 bytes/17 chunks, before close | `oversize-run-02.*`, `oversize-binary-02.*` |

The native probe build is `probe-build-02.log` plus `.exit`, exit 0.

## Serialized measurements

Astra granted an exclusive slot. Baseline build and all three drivers ran
sequentially; no competing lead workload ran. Every sample exited 0. The
baseline detached worktree was removed only after the logs and exit records
were retained.

Settings:

- fixed payload: 16 MiB (`16,777,216` bytes), best of five;
- each driver runs interpreter first, then native;
- lines: identical committed benchmark source and payload before/after,
  4,096-byte records, SHA-256
  `6bb102b33c34bab0a6f26a93213745b23bf6edcddf5a7b587b4e46e73c61fc8e`;
- chunks: `max_bytes = 65,536`, payload SHA-256
  `341aacac661ccb210720bedaa9ead5d668fe5ea41a73532fc147c71e34040df1`;
- payload bytes are the throughput denominator. Chunk counts and boundaries are
  not treated as a performance oracle.

### All five samples (MB/s)

| workload | runtime | samples | best |
| --- | --- | --- | ---: |
| lines, base `c4462935` | interpreter | 1531.577, 1609.634, 1571.961, 1584.245, 1491.236 | 1609.634 |
| lines, base `c4462935` | native | 1007.545, 1667.577, 1719.763, 1698.342, 1699.891 | 1719.763 |
| lines, current `9c67ec1f` | interpreter | 1451.876, 1427.534, 1469.714, 1136.395, 947.375 | 1469.714 |
| lines, current `9c67ec1f` | native | 1641.633, 1624.335, 1636.462, 1471.164, 1703.119 | 1703.119 |
| chunks, current `9c67ec1f` | interpreter | 67.551, 68.740, 67.258, 62.545, 66.783 | 68.740 |
| chunks, current `9c67ec1f` | native | 176.168, 181.265, 186.752, 168.372, 194.214 | 194.214 |

Unchanged lines best-of-five delta: interpreter **-8.69%**, native **-0.97%**.
The measurement does not support a zero-overhead claim. `Conn.chunks` has no
baseline because the row did not exist at the base; its measured absolute best
is 68.740 MB/s in the interpreter and 194.214 MB/s native.

Load averages:

| run | start | end |
| --- | --- | --- |
| lines base | 5.26, 5.34, 5.26 | 5.26, 5.34, 5.26 |
| lines current | 5.58, 5.41, 5.29 | 5.58, 5.41, 5.29 |
| chunks current | 5.02, 5.30, 5.25 | 5.02, 5.30, 5.25 |

Raw records: `measure-base-build.log/.exit`, `measure-lines-base.log/.exit`,
`measure-lines-current.log/.exit`, and `measure-chunks-current.log/.exit`.

## Changed paths

- `toolchain/PRELUDE.md`
- `toolchain/src/{check,emit_c,http,net,prelude,sim,sources,vm}.zig`
- `toolchain/runtime/mo_rt.{c,h}`
- `examples/step44/{chunks.mo,chunks-tls.mo,.mo.ids}`
- `toolchain/bench/step44/`: focused corpus/probe/measurement sources and raw
  evidence
- `toolchain/STEP-44-REPORT.md`

## Remaining limits and cleanup

- The worker did not run Linux, a machine target or the unfiltered compiler
  suite; those belong to lead acceptance.
- The public fixture still cannot initiate half-close. The internal directional
  EOF regression and real sockets cover the required semantics without adding
  a test-only public API.
- No throughput claim is made beyond the recorded machine/load/sample set.
- Focused process cleanup after measurements found no owned `mo`, native probe,
  throughput driver or socket-probe process (`pgrep` exit 1). The detached
  baseline path no longer exists. Generated development-only logs were removed;
  only the named evidence set remains.

---

# Step 44 correction addendum: review findings

This addendum is separate from the original delivery report above. The original
delivery at `9ad0162aa1994bb67c012ee85e78503c8573043a` was not accepted. Its
text and evidence remain verbatim for provenance; they are not represented as
independent acceptance of the corrected tree.

- Original delivery base for this correction:
  `9ad0162aa1994bb67c012ee85e78503c8573043a`.
- Final correction code, fixture, probe and evidence commit:
  `02833a52219a428034bb6c81e9893b6d3421fcf6`.
- This report-only addendum is committed after that code/evidence commit.
- All correction build, check, test, probe and measurement commands used the
  existing bounded guard. No unfiltered suite, formatter, benchmark, Linux run,
  machine run, push or merge was performed.

## Corrected findings

1. `linesFixture` now retires immediately after sending `Idle`; it no longer
   falls through to dispatch a closed fixture source. The deterministic
   optimized RED reached the source-kind dispatch unreachable with exit 134
   (`review-fixes/lines-idle-red-03.*`). The GREEN passed all 9 fixture tests in
   the interpreter and native binary (`lines-idle-green-01.*` and
   `idle-native-test-01.*`, both exit 0, 9/9).
2. The strict TLS target now requires a fault-free handshake, exact plaintext in
   both directions, bounded nonempty chunks and no premature terminal message.
   It passes 2/2 in the interpreter and native binary
   (`tls-test-write-03.*`, `tls-native-test-01.*`, both exit 0). Fault injection
   is isolated in `chunks-tls-faults.mo`; `tls-faults-test-write-02.*` exits 0
   with one test over 40 seeds at 20% faults and holds under faults.
3. A temporary ALPN mismatch makes the strict positive TLS test fail at
   `assert successful?(got)`. Both interpreter and native negative controls
   recognize that intentional inner test exit 1 and themselves exit 0:
   `tls-positive-oracle-run-02.*` and
   `tls-positive-oracle-native-02.*`.
4. The real-socket half-close oracle compares the complete ordered byte list,
   not a byte count and sum. Interpreter and native both observed exact hex
   `4100e282acf0288c2842`, including NUL, invalid UTF-8 and a split multibyte
   sequence, then wrote the post-EOF response:
   `ordered-bytes-run-01.*` and `ordered-bytes-native-01.*`, exit 0.

All correction evidence paths below are relative to
`toolchain/bench/step44/review-fixes/`; each named `.exit` contains the stated
outer exit status.

## Focused control proofs

| control | interpreter evidence | native evidence | observed contract |
| --- | --- | --- | --- |
| full-width bounds | `bounds-run-01.*`, exit 0 | `bounds-native-01.*`, exit 0 | 1 and 65,536 accepted with exact bounded input; 0, 65,537 and 18,446,744,073,709,551,615 parsed without truncation and rejected by child exit 70 |
| pending pull reader | `pending-pull-run-02.*`, exit 0 | `pending-pull-native-01.*`, exit 0 | a real `Conn.read_line` was observed at exact `waiting_in=Conn.read_line`; `chunks` registration then refused it with child exit 70 |
| TLS after chunks | `late-tls-run-01.*`, exit 0 | `late-tls-native-01.*`, exit 0 | registration completed, the real `TlsClient.connect` call started, and the used-connection guard refused it with child exit 70 |
| blocked writer/input overlap | `blocked-writer-run-03.*`, exit 0 | `blocked-writer-native-01.*`, exit 0 | exact `waiting_in=Conn.write` before and after exact `input-progress`; exact control lines `writer-blocked\n` then `input-progress\n`; `input_exact=true`, `answered=true`, unread data peer, child and outer exit 0 |

The blocked-writer proof precomputes the existing 16 MiB write payload before
arming chunks and the cooperative observer. A writer return is logged exactly
as `Ok` bytes or `Error` and is never success evidence. Neither passing run
returned from the writer. The data peer requested `SO_RCVBUF=4096` before
connect, observed 326,640 immediately after connect, reapplied the same 4,096
request, then observed and enforced 4,096 before the proof. These are observed
values only; no kernel-cause claim is made. The data peer remained unread
through both waiting observations and the exact input acknowledgement.

## Preflight and driver history

All bounded failures are retained rather than replaced:

| evidence | status | bounded resolution |
| --- | ---: | --- |
| `lines-idle-red-01.*` | 1 | fixed the fixture's statement-shaped case arm |
| `lines-idle-red-02.*` | 1 | fixed the one-field pattern and refreshed generated verification metadata |
| `lines-idle-red-03.*` | 134 | deterministic behavioral RED: optimized source dispatch reached unreachable; the one-line source retirement fix led to `lines-idle-green-01.*` and `idle-native-test-01.*`, both exit 0 and 9/9 |
| `tls-test-write-01.*` | 1 | fixed the split boolean expression; final strict target is `tls-test-write-03.*`, exit 0 and 2/2 |
| `tls-faults-test-write-01.*` | 1 | corrected the fixture-root module import; `tls-faults-test-write-02.*` exits 0 over 40 seeds at 20% faults |
| `tls-positive-oracle-run-01.*` | 1 | the inner positive oracle failed correctly, but the driver matched the wrong output case; `tls-positive-oracle-run-02.*` recognizes the exact failure and exits 0 |
| `tls-positive-oracle-native-01.*` | 1 | corrected the built executable path; `tls-positive-oracle-native-02.*` recognizes the exact inner failure and exits 0 |
| `controls-check-01.*` | 1 | corrected the initial control probe's statement-shaped case arm; `controls-check-02.*` exits 0 |
| `controls-native-build-01.*` | 1 | removed an invalid runtime-surface declaration form |
| `controls-native-build-02.*` | 1 | consumed Results, corrected durations, narrowed Platform capabilities and reduced nesting; `controls-native-build-03.*` exits 0 |
| `pending-pull-run-01.*` | 1 | a single snapshot missed the active wait; the bounded cooperative observer led to `pending-pull-run-02.*` and `pending-pull-native-01.*`, both exit 0 |
| `controls-check-03.*` | 1 | corrected named message construction and observer nesting; `controls-check-04.*` and `controls-native-build-04.*` exit 0 |
| `blocked-writer-run-01.*` | 1 | the writer returned before the wait was observed; process rows were retained, and the proof was changed to require exact pre-input and post-input wait observations rather than treating return as evidence |
| `blocked-writer-run-02.*` | 1 | post-connect effective receive buffer was 326,640, above the unchanged 16,384 ceiling; the driver stopped, retained `blocked-writer returned=Error(Closed)`, then reapplied the same 4,096 request in the next authorized revision |

Final static preflights `controls-check-05.*`,
`blocked-driver-pycompile-01.*` and `blocked-driver-pycompile-02.*` all exit 0
with empty logs. `controls-native-build-05.*` exits 0 and names the native
artifact. `blocked-writer-run-03.*` and `blocked-writer-native-01.*` are the
subsequent passing behavior proofs. No failure was silently corrected or
retried within its grant.

## Correction changed paths

- `toolchain/src/sources.zig`
- `examples/step44/chunks.mo`
- `examples/step44/chunks-tls.mo`
- `examples/step44/chunks-tls-faults.mo`
- `examples/step44/.mo.ids` (generated verification/declaration records)
- `toolchain/bench/step44/http_chunks_probe.mo`
- `toolchain/bench/step44/socket_probe.py`
- `toolchain/bench/step44/review-fixes/control_probe.mo`
- `toolchain/bench/step44/review-fixes/behavior_probe.py`
- `toolchain/bench/step44/review-fixes/tls_oracle_probe.py`
- `toolchain/bench/step44/review-fixes/*.log`
- `toolchain/bench/step44/review-fixes/*.exit`
- `toolchain/STEP-44-REPORT.md` in the final report-only commit

## Performance observations, cleanup and limits

The original serialized measurements remain observations: unchanged-line
best-of-five was **-8.69%** in the interpreter and **-0.97%** native. No causal
claim and no zero-cost claim follows. Longer and interleaved line measurements
remain owed.

Scoped cleanup after each correction group found no owned `mo`, guard, native
probe or Python driver process. Final blocked-writer cleanup found no process
and no socket on ports 57,434, 57,435, 57,440 or 57,441; the generated Python
bytecode cache was removed and confirmed absent. Raw failure and success logs
and their actual exit files remain committed.

This worker evidence is not integrated-code acceptance. Lead integration,
independent checks, current full-suite timing and Linux verification remain
owed. The correction did not run the unfiltered suite and makes no claim that
the current full suite passes.

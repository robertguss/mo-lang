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

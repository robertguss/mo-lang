# Provider bridge v1 worker receipt

Worker: GPT-6-Astra, low; local implementation worktree
`harness-provider-bridge-v1`, branch `harness/provider-bridge-v1`.
Exact clean base: `5494e8fe5bf9c646f50d3a45fa6f485f2333a597`.
Scope: only new `toolchain/harness/provider/bridge/`. No nested agents, packages,
pins, foundation/auth/Mo/executor/wiki edits, push or rebase. This is a worker
receipt for independent lead review, not automatic acceptance.

This is the harness provider integration slice: it joins the accepted one-turn
provider adapter to the existing Mo fixture contract while retaining native
history separately from recorded Mo steps. No live auth/inference, real account,
executor isolation, candidate command execution or application-repair claim.

## Results

| Check | Actual result |
|---|---|
| Final independent bridge controls | 27/27, exit 0; 61 isolated scenarios, 58 upstream HTTP fixture requests |
| Reserved Mo control | 1/1 named control; interpreter and compiled variants both exit 0 |
| Each Mo variant | provider → inert command → provider; 2 provider calls, 1 command, 3 Book steps |
| Own Mo native CLI build | exit 0, exact archived accepted examples |
| Unchanged foundation | 28/28, exit 0, fresh owned prepared copy |
| Empty, literal unknown, invalid-name and duplicate selections | each exit 2 before copying/loading Node; zero cases and provider calls |
| Final unexpected egress probes | 3/3 denied in independent controls |
| Cleanup | all bridge listeners/sockets closed; fixture sockets 0; final outer process groups absent; no matching task processes; both sequentially owned run panes closed |

Final proof is `selection-fixed-independent/{receipt.json,output.log,observations.json}`,
`selection-fixed-mo/{receipt.json,output.log,observations.json}`, and
`foundation-01/{receipt.json,output.log,outbound.json}`. Request payloads/order,
native IDs/signatures and state are retained, without authorization headers.
The Mo observations contain success records plus a separate finally/cleanup
observation for each runtime; these are not four runtime executions.

Mo did not run before explicit lead release. The lead supplied accepted integrated
commit `e6f04ce6358c85f22a86f26be0b5b388495fcc6e`. The worker used `git archive`
of that commit's `examples/` and copied the approved read-only compiler into its
owned ignored cache. No mutable main documentation was used as source identity.
Every later provider dispatch independently read Book's on-disk steps and matched
them to the journal's accepted prefix. The command dispatch independently found
the already-recorded model step. Both native replays retained `call_1|fc_1`, the
original function call IDs and `opaque-native-signature`. Native tool results
retained literal output text and `isError=false` despite the word “error”.

## Identity and retained attempts

- Node `v24.20.0`, npm `11.19.0` in foundation/independent runner; final Mo
  runner prints actual Zig `0.16.0` at `/opt/homebrew/bin/zig`.
- Pi source `36b60d2e8985899743c4cf5bd5f8929832a3f05d`; unchanged exact
  TypeScript runtime plus foundation observational patch. All 220 runtime files
  match committed hashes in every fresh copy and in the read-only source after
  testing. Six foundation files were compared with exact base and prepared source
  in `source-check.json`.
- Registry artifact/source mismatch remains: 148/177 embedded sources match;
  29 differ/are absent. No reproducible-build claim. Selected catalog SHA-256
  `3d3b5959b8bdd6dfd96b435501b298f32ab9406b1fe8a84555f00651ed039744`.
- Archived accepted examples SHA-256:
  `f80c2a984c013892afd0a25904578e181b5823da538d702a13dd25f6d9b35de8`.
- Copied Mo compiler SHA-256:
  `acf1d5934260e4f55ca3f6d1b0bf998149f57bb0e2572c25a315ef4b3a12738a`.
- Exact commands and per-attempt source hashes/exit codes are in each receipt.
  Final commands include the outer 600-second guard, shorter 580/550/540-second
  child/group bounds and direct Node RSS watchdog; Mo commands have 120/60-second
  guards with separate owned process groups. No tool/package installation.

23 attempt directories are retained: 13 exited 0, 6 exited 1, and 4 exited 2.
The four exit-2 attempts are the final selection rejections, before dependency
copying or Node/provider loading. Of the six exit-1 attempts,
`red-01` is the expected missing-implementation red; `empty-selection` and
`invalid-selection` are expected negative controls. The three unexpected failures:

1. `independent-01`: denying DNS lookup also blocked numeric loopback listen.
   Fixed with a no-DNS literal `127.0.0.1` callback; external lookup stays denied.
2. `independent-02`: socket idle deadline raced the sanitized provider timeout.
   Body/provider/reply waits remain two seconds; socket closing allows bounded
   journal/response grace. Deadline controls then passed.
3. `mo-01`: default Node chunked response was unreadable by Mo's HTTP client.
   Added explicit encoded Content-Length to bridge and inert command responses.
   Both runtime variants passed thereafter.

`unknown-selection` is an unfortunately named retained attempt selecting the
then-valid `unknown` usage control; it passed 1/1 with two provider calls testing
missing/partial usage. It was not an invalid-name test and is not claimed as one.
After the lead requested reconciliation, that control was renamed `unknown-usage`.
A shared `controls.json` now validates selections in Python before dependency
copying or Node startup, and again in Node before provider import. Literal
`unknown`, empty selection, `not-a-control`, and duplicate `final,final` each
exit 2 with zero cases/provider calls in `reject-unknown`, `reject-empty`,
`reject-invalid`, and `reject-duplicate`. Earlier genuine invalid-name/empty
assertion failures remain in `invalid-selection` and `empty-selection`. Initial `protocol-01` was the early three-assertion protocol
check, not part of the final 28-control count. Nothing was overwritten or removed.
The aggregate retained evidence is below 16 MiB; the final exact byte count and
file hashes are in `bundle.json`.

## Bounded decisions and limits

- JSON value equality ignores object key order, but retains exact accepted string
  values. Each newly appended model result must parse to exactly the offered
  tool/arguments projection; no coercion or omitted default arguments.
- Structured command/edit results validate state/execution and refusal consistency.
  Terminal/uncertain execution is persisted but cannot dispatch another turn.
  Success/failure/refusal continuation and literal error words are separately
  exercised with the actual pinned parser.
- Content-Length is a compatibility requirement discovered by actual Mo testing.
- Provisioning is a trusted operator API, with one run per bridge listener and no
  HTTP registration/reset. The operator must provision once per production
  process; the test process creates separate fresh bridge instances sequentially.
  This library does not impose a process-global singleton on trusted callers.
- Private journals use exclusive startup and serialized atomic replacement;
  restart refuses any prior path. There is no crash-durability or client-receipt
  claim. A failed terminal snapshot leaves the previous non-resumable tombstone;
  a broken filesystem cannot be claimed to contain a persisted terminal label.
- Final answers are offered, never declared Book-recorded. Trusted Run continuation
  implies Book acknowledgment but does not independently prove disk writes against
  a forged caller. The Mo control adds independent disk observations.
- The reply byte limit and finite reply wait are enforced in code; the suite does
  not claim an OS-level stalled-output-socket proof. Streaming request, cumulative
  native context, step and journal byte bounds are exercised directly.
- Abort suppresses late actions; it does not prove upstream cancellation or
  executor cleanup. All transport and command data in controls are synthetic.

The lead still owns immutable patch review, integrated-tree reruns and any
acceptance decision. Existing full compiler-suite results supplied with release
are not represented as worker-run compiler regression results here.

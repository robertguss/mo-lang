# Changelog

What shipped, newest first. One entry per session or per milestone. The reasoning behind each change is in `mo-wiki/decisions/decision-log.md`; the per-chapter "Session N changes" sections in `mo-wiki/spec/design-v0/` hold the same history next to the text it changed.

## Server wire blocker filed; byte-source step briefed — 19 Sep 2026, evening

- F1 at `8b0ff352` demonstrates that the unchanged client's body is withheld
  by line-only input until the client times out and closes.
- Step 44 is briefed to add bounded binary `Conn.chunks` through existing
  runtime sources. This is a planned unblock, not a shipped capability or
  accepted server. Clients and D2's independent operator path stay unchanged.

## OMP workflow and authorized WIP resumption — 19 Sep 2026, evening

- Astra leads in the existing OMP pane; workers use GPT Sol at high reasoning.
  Every assignment starts a fresh clean session, including saved-WIP continuations.
- Workers own implementation code; the lead owns review and acceptance and
  may independently run builds/tests. Separate worktrees/tabs and the
  three-worker limit remain.
- Robert authorized resuming the Mo server part A and step 42 from their
  preserved WIP commits. No new code accepted; Linux verification stays owed.

## Step 41: `Exec`, a child process narrowed to fixed commands — 19 Sep 2026, 3:33 PM ET

- `platform.exec` exists only in `main`; it makes a `Program` (one absolute
  path), which makes a `Command` (fixed arguments and whole-argument holes);
  only a `Command` runs or travels. No shell, no `PATH`, an empty environment
  by default, no descriptors but 0, 1 and 2, its own session and group, the
  deadline kept by killing the group, bounded output with `truncated`.
  `Exec.fixture` answers runs in tests and `mo test --sim` injects `Timeout`
  and `Failed`. `MO0407` covers `Exec` and `Program`, now also in a message
  line's field (and `Platform` there too).
- A run waits on a thread of its own, never the pool's four. One run of
  `/usr/bin/true` costs 1.1 to 1.2 ms against 0.93 ms for C.
- Also fixed: a module's own variant now hides a stdlib struct of its name; a
  `flows` rule follows a list literal written at the call.
- A Claude Opus 5 worker. Lead: Darwin full suite 268 of 268 and probes in
  both runtimes. **Linux is owed** (Robert deferred Linux runs today); the
  fork path runs only there.

## The agent's report cap lifted; a late command's reply is no longer lost — 19 Sep 2026, 3:06 PM ET

- `report_cap()` was 256 KiB because of a runtime defect that is fixed; it is
  now derived from the profile (23,068,672 bytes), a defence no correct run
  meets. Reports up to the largest a run can make render whole and identical in
  both runtimes.
- End to end v1's defect D1: a clamped command now leaves a 5 s collection
  margin, so its reply arrives and its execution is known. Seen on the machine.
- A Claude Opus 5 worker. Lead: Darwin full suite 263 of 263; the machine's
  outer-deadline run green with a clean inventory.

## The Mo agent runs end to end on the machine — 19 Sep 2026, 2:20 PM ET

- For the first time the Mo agent (`mo run` and a `mo build` binary) drove the
  real workspace service and real containers on `mo-executor-r01`: six tools,
  each result equal to what the service journalled, the Book holding exactly
  the prior steps before every dispatch.
- The scripted Logstat repair: a semantic RED, read, exact edit, GREEN, and the
  protected verdict on the frozen snapshot. The verdict refuses a forged
  success and a candidate that rewrote its own test.
- Negative runs (owner killed, candidate limit, outer deadline) end with
  truthful reports; every workspace proved gone; inventories clean.
- Two defects found at the joins, queued: the last clamped command is always
  reported unknown (D1); after a client disconnect no verdict can be taken (D2).
- A Claude Opus 5 worker; the lead reran smoke, Logstat, two negatives and the
  inventory on the machine. A scripted model: plumbing, not model ability.

## Step 43: every number in source is held to its range — 19 Sep 2026, 1:59 PM ET

- The auditor's PR 15 findings fixed. One reader of numbers
  (`toolchain/src/number.zig`) replaces a 32-digit buffer in the checker and
  two saturating parsers in the lowerings: a literal past its type is `MO0217`
  in `mo check`, `mo run` and `mo build`, however many digits or leading zeros
  it has. Before, `UInt64` took 18446744073709551616, `UInt8` took a
  zero-padded 256, and a 54-digit literal silently became 2^127 - 1.
- `mailbox:` is 1 to 4,294,967,295 and `max_restarts:` 0 to 4,294,967,294, else
  `MO0217`; both used to panic the compiler past 32 bits, and
  `max_restarts: 4294967295` was silently read as "no budget".
- Found by the worker's sweep: float literals such as `1_.5` ran as `0`, and a
  400-digit float read as infinity; `N.days` past a Duration is now a
  diagnostic, not a run-time trap.
- The fuzz driver refuses a budget that is not finite and positive (exit 2) and
  a campaign that ran no input exits 1.
- A Claude Opus 5 worker. Lead: Darwin full suite 263 of 263; Linux x86_64
  build and the 15 focused tests green on Robert's VM.

## Step 40: a scope that holds, and `Fs.replace` — 19 Sep 2026, 1:08 PM ET

- A narrowed `Fs` now walks its path one folder at a time from the scope's
  folder without following links, and every row acts on the descriptor it
  resolved, in both runtimes. Closed: a program's own `fs.scoped("link")`
  rooting a scope outside; links inside a scope being followed; writes, removes
  and renames acting through links; a FIFO hanging both runtimes; the gap
  between check and use. `list_kinds` reports `Link`; `fs.kind_of` gives
  hardlink count and setuid.
- `Fs.replace`: atomic write by temporary file, sync, rename, folder sync, mode
  0600; the old file whole after a kill; 1,000 replaces with no partial read.
- Cost: shallow reads, writes and appends 25 to 40% cheaper; a path 16 folders
  deep 3.5 times dearer; `list_kinds` 3.3 times dearer in the interpreter and
  5.7 times cheaper in the binary.
- Two Claude Opus 5 workers (the first's tab closed mid-step; the second
  reviewed and finished it) and a Linux follow-up. Lead: Darwin full suite 249
  of 249; Linux x86_64 on Robert's VM 6 of 6 after a Linux-only test harness
  bug was fixed.

## A runtime use-after-free fixed; harness step 2 accepted — 19 Sep 2026, 10:37 AM ET

- Both runtimes: an `answer` to an ask a process kept was held as a bare value
  into the process's region until the update committed; a returning frame past
  the 1 MiB frame budget compacted the region first, so the asker got freed
  memory (native: raw bytes printed; interpreter: a panic). `answer` now packs
  when it runs, as `send` always did. New corpus program `deferred-large.mo`
  and a test that rebuilds the native runtime compacting at every safe point.
  Found by the application workspace rebuild, fixed by a Claude Opus 5 worker.
- Harness step 2: six live suites as case tables on one runner, recovery's four
  tests now fail when `recover()` is broken, the HTTP double runs the real file
  controller, the runner accepts only `None` or `Fields` from a case. Python
  rose from 6,326 to 6,643 counted lines.
- Lead: full suite 244 of 244, exit 0; all eight live suites green after one
  regression the lead's live rerun caught. `guard.py` kills its child but not
  the group; an orphan from a killed run broke the next run once.
- Research PR 14 (Hermes) reviewed and merged.

## Application workspace rebuilt; executor and Mo agent review fixes accepted — 19 Sep 2026, 9:03 AM ET

- Fable leads with Claude Opus workers (Robert, 19 Sep). Astra's unfinished
  application workspace was discarded and rebuilt from `030290b8`: the Mo agent
  routes all six tools to the workspace service, with the seven carried wire
  findings each closed by a control that failed first, in both runtimes.
- Executor: a slow `docker rm` no longer powers off the machine (only a proven
  populated cgroup does), pre-claim refusals no longer crash, corrupt state is
  quarantine, the unit name is validated, state writes sync; six duplicate
  runners became one, per-run probes became one inventory. Python 6,688 to
  6,326 counted lines.
- Mo agent: the boundary test can now fail (six mutants), two dormant matrix
  cases run (24 of 24 per runtime), refusal reasons asserted, a completed
  response is reported completed, the outer deadline has slack, one budget rule
  in `steps.mo` with an explicit `Counting` value.
- Lead checks: full suite 243 of 243, exit 0, on the combined tree; every live
  suite on `mo-executor-r01` green (17, lifecycle, 22, recovery, 22, 22, 23) and
  a clean inventory. An earlier full run was 242 of 243 on a TLS test that
  fails about 1 in 5 alone; unexplained, with step 39.
- Not met: the Mo agent against the real service on the machine end to end; the
  two fault-injected power-off checks.

## Workspace HTTP accepted — 19 Sep 2026, 6:38 AM ET

- Six remote tools use a private one-run interface with cleanup ownership beyond
  request lifetime. Corrected response draining and fragmented IPC deadlines.
- Lead local22/inherited59, real22 per profile, old runtime regressions, review
  controls and two new extras pass; full243/243,5/5 and17339 unchanged files.
- Cross-attempt100 executions/131 workspace IDs/97 cgroups absent,34 groups gone;
  active parents empty/shared5 unchanged. Mo application routing starts separately.

## Cleanup-only workspace recovery accepted — 19 Sep 2026, 4:27 AM ET

- Private ownership before effects, exact cleanup reconciliation and terminal
  barriers cover owner loss and delayed dispatch without replaying work.
- Lead local59/schema21, recovery16, old runtime regressions and real lost-response
  extra pass. Full243/243,5/5;11128 tracked files unchanged; owned cleanup proved.
- Preserve unexplained historical transport/TLS failures and two API-unresolved
  reboot-lost outcomes despite physical cleanup. HTTP routing follows separately.

## Isolated application builds accepted — 19 Sep 2026, 3:16 AM ET

- Pinned Mo/Zig image and explicit application policy compile and execute real
  Hello/Logstat within unchanged 1 GiB/120-second candidate limits. Lead actual
  image-content checks, 23 runtime groups, old regressions and extra snapshot
  build pass; cleanup and shared Mac container identity are verified.
- Full rerun passes 243/243 and 5/5. Retain the earlier TLS TCP-count mismatch
  and ten passing focused runs; its originating client remains unidentified.
- Cleanup-only recovery starts before HTTP exposure; lost reservation responses
  and late dispatch must retain ownership without retrying work.

## Offline native-history bridge accepted — 19 Sep 2026, 2:34 AM ET

- Added one-run loopback provider bridge with exact recorded continuation,
  preserved native IDs/signatures, bounded private journal and fail-closed usage.
- Independent27 protocol groups, actual Mo in both runtimes,28 provider cases
  and two extra HTTP controls pass. Full suite 243/243,5/5; source bytes preserved.
- Retained and corrected real Mo HTTP framing and mixed-selection runner failures.
  Commands remain inert fixtures; real application packaging proceeds separately.

## Coding, workspace and private auth accepted — 19 Sep 2026, 2:18 AM ET

- Coding fixture adds recorded inert-command repair orchestration and exact edit.
  Independent full suite 243/243,5/5 and both runtime matrices pass; cancellation
  report race and cold-native false-pass failures are retained with corrections.
- Persistent isolated workspace adds safe file operations, real command feedback
  and protected snapshot verification. Lead27 unit/22 workspace/17 executor,
  lifecycle and two extras pass with positive cleanup and unchanged shared Docker.
- Private auth adds pinned device OAuth and explicit private-store handling.
  Offline28 auth/28 provider/two lead controls pass after late-body cleanup fix;
  no real login or inference is claimed.
- Trusted Linux compiler execution/native build pass. Application image policy
  and provider bridge independent acceptance continue as separate slices.

## Versioned terminal-401 policy accepted — 19 Sep 2026, 1:19 AM ET

- Agent.Model stops immediately after HTTP 401 through a separately versioned
  recipe; other retries and deadlines retain their behavior. The shared generic
  recipe remains byte-identical.
- Lead 18-case interpreter/native matrix and six additional controls pass.
  Final integrated full suite passed 243/243 and 5/5 steps after generated
  dependency and formatter corrections. Both earlier full-suite failures and
  the real 401-then-unexpected-request baseline red remain in evidence.

## Offline provider foundation accepted — 19 Sep 2026, 1:16 AM ET

- Integrated the pinned provider-only library with explicit usage presence,
  sanitized failures, no retries and native continuation messages. Source and
  registry artifact differences and the minimal parser hook are disclosed.
- Lead fresh setup passed after correcting missing cache initialization;
  seven regenerated records match, all 28 parser controls and two extra lead
  controls pass. Historical evidence stayed unchanged. No live auth/inference
  or Mo integration is claimed.

## External fixture executor accepted — 19 Sep 2026, 1:06 AM ET

- Integrated the bounded Python executor for the dedicated isolated machine.
  Protected host checks bind candidate identity, effective policy and cleanup.
  Lead review corrected reaper ordering before acceptance.
- Independent verification passed 15 unit tests, 17 live controls, collector
  death during uncertain cleanup, and explicit exit-137 signal accounting.
  Final candidate/service inventory was empty; shared Mac Docker IDs/states
  were unchanged across the lead run. Application/provider acceptance is separate.
- Auth and provider foundations are integrated but acceptance remains open:
  auth full suite is 242/243 pending formatting; provider clean setup exposed
  missing cache initialization. Both failures are retained and assigned back.

## Astra/Herdr workflow and overnight authority — 19 Sep 2026, 12:10 AM ET

- Robert keeps Astra as lead on his Mac and selects fresh Astra workers at low
  reasoning in Herdr panes, superseding Amp orbs and the oracle requirement.
  A real worker launch confirmed the selected model/effort; its readiness
  review was retained and its pane closed after receipt.
- Robert authorizes the lead to drive setup, implementation and verification
  while he sleeps and make decisions previously awaiting approval. Updated
  active guidance; the harness implementation pause is superseded, while
  bounded scope, independent verification and outstanding audit gates remain.

## Mac arrival inspection — 18 Sep 2026, 11:58 PM ET

- Verified the clean handoff checkout, native Zig 0.16.0 and OrbStack Docker
  endpoint. Historical worktree paths, branches, transfer package and receiver
  ledger are present; auditor pointer check found zero new records.
- No named Linux machine exists. Dedicated execution remains unverified;
  Codex lacks the requested Amp oracle/thread tools and the workflow choice is
  pending. Recorded arrival evidence and current readiness without starting
  setup, authentication, workers or implementation.

## Mac lead handoff and executor feasibility — 18 Sep 2026, 11:44 PM ET

- Robert directs the Astra lead to move to his Mac with OrbStack; workers stay
  in fresh medium/xxlarge orb threads. Updated the handoff, active guidance and
  readiness/status pages; destination verification is still owed.
- Preserved the final nine-PASS executor probe and both failed precursor runs,
  with setup, cleanup and evidence limitations. Temporary Docker and controller
  changes were removed/restored. No harness implementation, login or worker.

## Amp orb/thread workflow — 18 Sep 2026, 11:14 PM ET

- Active guidance now keeps the Astra lead in the same thread and launches each
  approved worker/new work unit/phase in a fresh medium-mode xxlarge orb.
  Replaces Herdr mechanics with explicit state transfer, stable handoff,
  role-aware onboarding and lead-side verification; preserves audit rules.
- Recorded the subscription OAuth research and provisional Pi provider adapter.
  No login, worker, setup or implementation started; readiness remains
  incomplete.

## Mo-first coding harness selected — 18 Sep 2026, 10:29 PM ET

- Robert approved the lead/oracle recommendation: a Mo-written, Mo-first coding
  harness, initially maintaining existing applications, with Pi as its practical
  comparator. The bounded brief defines scope, evidence boundaries, exclusions
  and unresolved readiness decisions. No worker or implementation started.
- Recorded the final review's byte-identical duplication of the Kimi attachment;
  there are four distinct bodies, not five. No new acceptance evidence.
- Program 7 remains suspended; Step 39 and retained audit obligations unchanged.

## External review agreement — 18 Sep 2026, 9:36 PM ET

- Recorded Robert's agreement with the oracle-assisted review synthesis:
  trustworthy instruments, workflow/onboarding calibration, then a useful
  application against a well-equipped existing-language comparator. Application
  choice and detailed scope remain open; the reviewer packet is unchanged.
- The 401 proposal requires an approved versioned recipe-policy change, not an
  implicit implementation fix. Requirements, conformance and verification are
  separate obligations; later workload design should consider progress and
  uncertain external effects.
- Documentation only. No bounded start or lead-readiness confirmation recorded;
  implementation stays paused. Program 7 and Step 39 dispositions are unchanged.

## Research synthesis and outside review brief — 18 Sep 2026

- Four supplied reports preserved with hashes and reviewed with the oracle;
  findings, selective source corrections and unratified proposals separated. The
  evidence attachment's auditor designation and prior exposure are disclosed;
  this is not a new cold audit reading or adoption of its suggested gates.
- A bounded Agent maintenance/onboarding trial is proposed for discussion. A
  self-contained prompt equips external models with web access to challenge
  everything, including whether a new language/runtime is justified.
- No workers, setup, implementation or experiments until Robert explicitly
  approves starting and the lead confirms readiness. Program 7 stays suspended;
  Step 39 remains unaccepted. Documentation only; no new toolchain results.

## Agent-native direction; implementation paused — 18 Sep 2026

- Robert approved Mo as an agent-native additional option, not a BEAM
  replacement; prioritize the complete fast, trustworthy agent loop before
  feature expansion.
- Program 7 is on hold; its superiority thesis and runtime-claim retirement
  framing are superseded prospectively. Historical specs and evidence remain
  unchanged; no old gate is passed and no correctness requirement is waived.
- Four research briefs are running with Robert. The roadmap separates agreed
  direction from proposals; no replacement experiment, syntax overhaul or TLS
  strategy is approved. Implementation remains paused, and step 39 unaccepted.
- Documentation only. Upstream code changes were preserved, not verified here.

## Lead transition and PR 12 — 18 Sep 2026

- Robert authorized Amp as lead. The current-state lead reading was published
  before the auditor's conclusions were opened; PR 12 was reviewed and merged
  unchanged, with the comparison and fresh harness-control outputs preserved
  under `audit/`.
- False-success runner, empty-selection, fuzz-accounting and abuse-stimulus
  paths reproduced on current main. The audit's TLS/ALPN failures predate step
  39 A/B; their worker outputs are not independent acceptance. No toolchain code
  changed and step 39 remains incomplete.
- Program 7's R2/RC1/R4 measurement discrepancies recorded for explicit
  reconciliation before its seal and builds. The handoff and board retain
  baseline, implementation-readiness and environment-restoration gates. No
  ratified threshold or retirement mapping changed.

## Session 12, Robert's Mac, morning — 18 Sep 2026, 11:34 AM ET

- **Step 39 paused for Robert's VM move** (4:33 PM ET): parts A/B committed (chain restrictions and ALPN), C/D saved as an unfinished patch, E/F unstarted. Worker suite outputs A 240/240, B 242/242; **not lead acceptance**. Limbo's 27 accepted-but-should-reject and C's 63/64 abuse run remain unresolved, Darwin full-sync is unimplemented. The worker is ended, local-only evidence and refs are packaged, and `HANDOFF.md` names the continuation and outstanding gates.

- **Generation six run and read** (`mo-wiki/plans/erosion-round.md`): change 6 (the archive pruned, a speed budget, the rename rule's `next_id`, the generation-five bug as a ticket) by four maintainers across the VM's wedge and a move to the Mac. Nothing eroded under the six old suites; no defect in any program under the corrected seventh suite; generation five's Mo-only defect fixed; Mo's lease path back from 425 to about 3,700 pairs a second at 32 workers (1.01× change 3). P1 and P2 held, P3 and P4 failed, P6 failed for the sixth time (no law tripped on a wrong edit), P7 void (the spec named the cause). Time and loops recorded, compared with nothing.
- **Five auditor readings and one research note received** (PRs 7 to 10): Fable's four readings filed first, every finding conceded. **The TLS brick is not complete**: its client accepts four certificate chains OpenSSL rejects (path length, `keyCertSign`, extended key usage, an unknown critical extension), a valid ALPN overlap past 64 names fails, the fuzz count can hide a failed batch, and `tls-client.mo`'s tests pass with the handshake replaced by a `Timeout`. Step 39 queued with the auditor's script as its gate.
- **The lead's own errors found and recorded**: the sealed seventh suite had never been run and started every server below the spec's `--retain-ms` minimum (the corrected `defects6b.py` sealed before any suite ran); generation five's third-suite column was never measured (a usage error the runner swallowed; measured today); P7's threshold re-read with evidence in view, withdrawn. New rules: a hidden suite is smoke-run on the previous generation before its seal; a runner writes every exit status and stops on a failed build; one mutant per new corpus test file at every acceptance.
- **Found in the runtime**: plain `fsync` on macOS where Go uses `F_FULLFSYNC` (the Mac's speed comparisons with Go withdrawn; the fix in step 39); `mo test --sim` without bound on a perpetual timer (the 13.4 GB process); `for _ in 0..n` building its range; no `Fs` row that syncs a folder.
- **Step 38 accepted** (11:59 AM ET; `mo-wiki/plans/interpreter-step-38.md`): a `Conn` reads while a write on it waits, in both runtimes, plain and TLS; `TCP_NODELAY` on every connection (bulk in windows of 16 lines on Linux 8.8 s to 0.19 s); 64 handshake abuse cells with a negative control. The lead's suite 237 of 237; a mutant run ten times (the old runtime red at one core every time); a pipelining probe 16 of 16, byte-exact; the abuse table against cells the lead committed before seeing it. Not verified: a KeyUpdate during duplex, a ThreadSanitizer build. **Step 39 queued** (`interpreter-step-39.md`): the TLS brick's corrections from two auditor readings, a client that refuses plaintext records after the handshake keys, and `F_FULLFSYNC` on macOS.
- **Program 7's spec needs a revision 2** before the auditor's sealing session (Redis's persistence tests are `external:skip` in `--host` mode; no package-backed target for P4; expiries on rewritten non-string keys; one aggregate size cap; the skip list's author; RC2's core operation).

## Session 11, the VM, night — 18 Sep 2026, 3:50 AM ET

- **Step 37, the TLS brick, part two, accepted** (one Opus session 10:37 PM to 2:15 AM ET, one fix session after; Fable's brief, verification, and reading, `mo-wiki/plans/interpreter-step-37.md`). The client side (`Tls.client`, `TlsClient.connect`), the chain checked to a trusted root with the name and the dates, ALPN by `offer`, a KeyUpdate either side can start; the differential run against OpenSSL 3.0 at 1,000 sessions and 0 mismatches, the fuzz hour at 87,440 inputs and 0 crashes, the RFC 8448 client replay byte for byte; the four findings of the auditor's step-36 reading closed. Fable's probes against a second OpenSSL (Python's 3.5.7) found a peer's alert reported `Closed` and a double free that crashed the binary server after a client's reset; fixed in `b0b2ac4`, 236 of 236. The cut refuses RSA and P-384, so the public internet is out of reach by design; two runtime rows carried to step 38 (full-duplex `Conn`, `TCP_NODELAY`).
- **Program 7's spec sealed** (`mo-wiki/spec/programs/07-redis-subset.md`) and published to the auditor: `mored`, a Redis subset against Redis 7.2's own test files with a pre-registered skip rule, RESP2, an AOF, ACL users with Argon2id, TLS, a Prometheus endpoint, four recipes, the Elixir counterpart under matched conditions, the deviations named before any build.
- **The generation-four memory control probe pre-registered** (`mo-wiki/plans/gen4-memory-control-probe.md`): three hypotheses with Fable's numbers written before the run, to settle `AUD-COMP-GEN4-RSS-001` for Robert.

## Session 11, the VM, late evening — 17 Sep 2026

- **The auditor's step 36 reading, received and answered.** The receiver found it at onboarding (PR #5) with a labelled transport test (PR #4). Fable's own reading (`audit/fable-reading-2026-09-18-step-36.md`) was filed at `258d1e2` before the auditor's was opened; both PRs merged; `parallel-filed` and a test acknowledgement published; the exchange's inbound leg verified. The comparison conceded four points to the auditor (rows of 18 Sep in the decision log) and corrected the step 36 Result's load caveat, which was the lead's error.

## Session 10, the VM, night — 17 Sep 2026

- **Step 36, the TLS brick, part one** (one Opus session 3:27 to 6:41 PM ET and two narrow fix sessions after; Fable's brief, verification, and reading, `mo-wiki/plans/interpreter-step-36.md`). `toolchain/src/bricks/tls.zig`, 2,077 lines: a TLS 1.3 server engine over bytes (the two suites, X25519 with one HelloRetryRequest, Ed25519 and P-256 certificates from PEM, KeyUpdate, close_notify), driven by each runtime from its own sockets; `platform.tls`, `Tls.server(cert:, key:)`, `TlsServer.accept(conn, within:)` giving back a `Conn` that is the same `Conn`; `Tls.fixture()`; the spec's `## Tls`; `examples/effects/tls-echo.mo` with two PEM pairs; `bench/step36` against OpenSSL 3.0 as the client. On the VM: 1,026 and 1,196 handshakes a second, bulk 203 and 268 MB/s over AES-128-GCM against 488 and 477 plain, round trips inside 2×, 9.6 and 12.6 KiB per idle connection, +394 KiB per binary, fourteen abuse rows as named. Verification found two defects behind the worker's reported green: the brick's KeyUpdate test hung on every run (a missing `mo_tls_sent` in the test's loop; fixed with deadlines on every socket write, `6af598d`) and the example read its certificate by a repo-root path (`0fe9669`). After both: 225 of 225 in 10 min 47 s on a quiet machine, and Fable's 22 probes green under both runtimes. Six rows, three `semantic` for Robert.
- **The evidence bundle and the auditor's `ready` record** for step 36 under `audit/evidence/2026-09-17/step-36/` and `audit/handoffs/step-36/`.
- **The machine, made honest.** A 43-hour orphan from the 16 Sep measurement session had held one of the VM's four cores through step 35's numbers and the speed probe; killed 5:26 PM ET, the condition written on the evidence README, the skill now reads the load before a measurement. The Zig cache and the Trash cleared at Robert's ask; disk from 79 to 45 percent.
- **Paused** at 10:15 PM ET at Robert's ask, with step 37's brief not written and no worker running.

## Session 10, the VM, evening — 17 Sep 2026

- **Step 35, the crypto brick** (one Opus session on the VM, medium effort, 15:50 to 17:56 UTC; Fable's brief, probes, and reading, `mo-wiki/plans/interpreter-step-35.md`). `toolchain/src/bricks/crypto.zig`: SHA-256, SHA-512, HMAC-SHA256, HKDF-SHA256, AES-256-GCM, ChaCha20-Poly1305, X25519, Ed25519, Argon2id, constant-time equality, and OS entropy as C-ABI exports over `std.crypto`, the standards' vectors as its tests; the interpreter imports it and `mo build` compiles and links it once per target and CPU (`-mcpu native` without `--target`), cached under `zig-out/mo-build/.bricks/`. The rows on `Hash`, `AesGcm`, `ChaCha`, `X25519`, `Ed25519`, `Password`, and the capability `Random` (`platform.random`, `Random.fixture()` from the run's seed in tests), in `09-stdlib.md`'s new `## Crypto` and `## Random`. Five corpus files; `bench/step35` with the differential run against python's `cryptography` (18 rows, 1,000 inputs each, 0 mismatches under both runtimes) and the fuzz harness (the worker's ten minutes, 659,600 inputs, and Fable's hour, 3,855,200: 0 crashes). Numbers on the VM: SHA-256 of 1 MiB 245 MB/s under `mo run`, 532 in a binary, 1,548 for the brick called straight; AES-GCM 329 and 595 MB/s; Ed25519 sign 10,000 in 1.7 and 1.1 s; `Password.hash` 171 and 145 ms; jobq's warm build unchanged, its binary 406 KiB larger. Fable's own probe against `cryptography` equal under both runtimes on 29 lines, the Argon2id tag rederived independently, the size crash and MO0409 on a captured `Random` checked. Carried: `List(UInt8)` at 6.3× and 2.9× the raw call, a byte-string value for a later step. Seven rows, one `semantic` for Robert.

## Session 10, the Mac, afternoon — 17 Sep 2026

- **The bricks page** (Fable, `mo-wiki/deep-dives/bricks-and-the-cost-of-zero-dependencies.md`; M-3 item 1, the capabilities rule's prerequisite for program 7). What a brick is, in three tests; the cost of the shelf measured against Zig's standard library, which the toolchain already trusts (about 70,000 lines to read, 12,000 to 15,000 to write, estimated); five audit items a brick must carry and a capped cut of each standard; a brick written once in Zig and linked into both runtimes from the crypto brick on; a vendored C library inside the platform as the fallback, never application FFI. Program 7 needs two bricks, crypto and a TLS 1.3 server, which are the next three worker steps; its Prometheus endpoint is a recipe and the P4 comparison. Five decision rows.
- **The auditor role taken up** (Robert installed it; Fable wired it into the wiki). Three stopping rules Robert ratified under `audit/`: the runtime layer on program 7 (S-A/S-B/S-C), capabilities and recipes on program 7 (T-A/T-B/T-C), and the language's catch claim at generation ten (R-B automatic). Linked from chapter 1, chapter 10 §4, the state page, the board, the handoff, and the `mo-lead` skill. The board reordered under M-3: the bricks page, the generation-four speed probe, then program 7. Fable's disagreements filed as rows for Robert before program 7 exists: program 7's Redis subset needs no hex in Elixir, so its spec adds TLS, hashed ACL passwords, and a metrics endpoint; the language rule's R-A trigger fires on one false positive at zero catches; the runtime rule's open clauses read in advance.

## Session 10, the Mac, morning — 17 Sep 2026

- **Research PR 2 read and merged** (Fable; the Hermes lane on `research/hermes-monitoring`, wiki only, no code, no spec or decision edits by the agent). Two daily notes, `mo-wiki/research/concepts/hermes-daily-2026-09-16.md` and `-17.md`, a monitoring plan, six raw snapshots with pinned hashes: the versioned Elixir and Erlang supervisor defaults against the round-10 source; a restart budget as containment rather than recovery; Yuan et al. (OSDI 2014) on error handlers that exist and are wrong; Pillai et al. (OSDI 2014) on crash consistency, file against directory-entry persistence; the `cap-std` README's own line that a capability API is not confinement. Read as sharpening, not news; the two checklists (the sequence create, compact, rename, reopen, write again; error-path reachability at recipe acceptance) are queued reading for change 6. The decision-log row is for Robert.
- **Chapter 10's restart-budget attribution corrected** (Fable, `mo-wiki/spec/design-v0/10-language-after-the-rounds.md`, the table and §2): the 3-in-5 budget that ended the Elixir node in P6 is Elixir `Supervisor`'s default, not OTP's; Erlang's `supervisor` defaults to 1 in 5 s. The P6 reading stands.
- **The fresh-eyes pass** (Fable with five Opus readers and one Opus applier, the rest of the morning; six commits). Every section of the wiki read against the state page and the spec; 344 defects reported and applied as dated notes, in-place corrections of errors, links, statuses, and frontmatter, never as rewritten history. The eight plang research syntheses of 13 Sep, which describe a Mo that was never Mo's design, are bannered and marked contested. The linter knows the spec folder and every page type: 94 findings to 18, all intentional. The detail is `mo-wiki/log.md`, 17 Sep, the fresh-eyes entry.
- **The evidence branches made true** (Fable): `erosion2-*` and `erosion5-*` had never left the Mac though the handoff said every evidence branch was pushed; all eight pushed. Handoff, board, log, state page, and thesis map brought current; lint 94 pre-existing findings, none new.

## Session 9, the Mac, evening — 16 Sep 2026

- **Change 5 and generation five of the erosion round** (Fable's spec `mo-wiki/spec/programs/01f-job-queue-change-5.md`, the sixth hidden suite `erosion-round-suite/defects5.py`, the reading on `erosion-round.md`; four Opus sessions of 11 to 25 minutes). A lease handed to another worker and a queue renamed with jobs in flight as one durable record, the first change whose seam is a law. All four carried it; all four found the spec's archive-rename sentence wrong and fixed it the same way; Mo's shipped the first defect of the round no baseline shared (after a compaction and one more rename the folder refuses to open, its own `verify` refusing a count its own `compact` left behind), and the three `never`s its maintainer wrote caught neither of its bugs. P6: the Mo queue killed under load back in 55 and 99 ms, nothing lost. The speed row per generation, new: Mo 425 pairs a second at 32 workers (generation four's nine-times loss carried), Go 107, Python 4,847, Elixir 5,619 on the Mac's disk.
- **Step 34, placement, parts B and C** (a second Opus session, medium effort, 16:50 to 20:46; Fable's brief, probes, and reading, `mo-wiki/plans/interpreter-step-34.md`). The crossing made cheap in both runtimes: 100,000 asks across two schedulers from 4.0 to 5.6 s to 0.14, the cost a zero-timeout `kevent` on every poke and a lost wake, never the runtime lock; a scheduler now spins 200 µs on its poke and sleeps on one atomic word. Measured at 1, 4, and 14 cores: the queue's pairs and `kv-10k-get` under `mo run` level across cores, the crunchers 7.3×, and `echo-1k`, the binary's `kv-10k-get`, and the queue's creates still slower at 14 by the rule that leaves what `main` starts on the fewest-live scheduler. A regression of part A found and fixed (a spawner that never parked, 4 GB at 200,000 processes). Fable's probe beside it: the change 4 Mo queue makes 452 lease-and-ack pairs a second where every earlier generation makes 4,040, on step 33's and step 34's binaries alike: generation four's first erosion is a performance one, and the round now records speed per generation.
- **Change 5 sealed and generation five pre-registered** (Fable, `mo-wiki/spec/programs/01f-job-queue-change-5.md`, the pre-registration on `erosion-round.md`). A lease handed to another worker, a queue renamed with jobs in flight as one durable record: the first change whose seam is a law, so the first that can show a `never` catching a change-induced bug.

## Session 9, the Mac, morning — 16 Sep 2026

- **Round 9's last row, Haiku 4.5** (three Claude Code sessions at medium effort, 7 to 9 minutes each; Fable's setup, suites, and reading, `mo-wiki/plans/control-run-9.md`). The first model whose change is defective in every language: 0 regressions everywhere; Mo 28 of 189 checks over 4 causes (the old names and malformed fields accepted at create; a due job never moved from scheduled to queued), Go 22 over 6 (its bolted-on `never`s trip on its own change, answer 500, once exit the server), Python 18 over 2 (the retry route and a scheduled delete answer 500). None was green by every check at its commit, and every report's wall-clock is wrong by a factor. The round is closed: P1 held, P4 for four of five, P2, P3, and P5 failed; the Opus-in-Pi baseline unmet. The suite outputs and panes of every row are under `control-run-9-suite/results/`.
- **Change 4 and generation four of the erosion round** (Fable's spec `mo-wiki/spec/programs/01e-job-queue-change-4.md`, the fifth hidden suite `erosion-round-suite/defects4.py`, the reading on `erosion-round.md`; four Opus sessions, their times lost to the Mac sleeping). Idempotent creates by a key the log carries and a restart rebuilds; done and dead jobs older than `--retain-ms` archived into a second file beside the log, readable by id, counted, verified, with a kill between the move's two writes decided at open. Under the fifth suite: Mo 77 of 77 under both runtimes, Python 77, Go 76 (`null` as no key), Elixir 76 (a repeated flag); P6 back in 58 and 85 ms. The seam did not open: nothing new eroded in any language in four generations. Mo's maintainer wrote the `never` for the two-file exclusion and keeps archived jobs in memory, a row for change 5.
- **Step 33, the crash report freed, and the interpreter's abort on a large log** (one Opus session, medium effort, 11:21 to 12:47; Fable's brief, runs, and reading, `mo-wiki/plans/interpreter-step-33.md`). A crash report is written and then freed in both runtimes, the C runtime mapping and unmapping its own memory for it since `free()` kept the blocks resident on macOS: a restarting 20,000-job queue grew 46 MiB a restart as a binary and 28 under `mo run`, and grows under 0.3 and 0 now, 37 and 64 MiB resident after thirty restarts against 1,412 and 902. The abort generation three saw under `mo run` was not the disk: opening any log past about 8,000 jobs tripped a high-water mark that compaction's copy-per-reference had passed; fixed in both runtimes, with a unit test. Carried: one restart at 100,000 jobs takes 1.45 s against the spec's one second.
- **Change 3 and generation three of the erosion round** (Fable's spec `mo-wiki/spec/programs/01d-job-queue-change-3.md`, the fourth hidden suite `erosion-round-suite/defects3.py`, and the reading on `erosion-round.md`; four Opus sessions of 10 to 23 minutes). The store restarts itself from its log after a failure inside it, `503` meanwhile; a budget of 5 in 60 seconds, then exit 70 with the log whole; a chaos switch `--crash-every N`; `/health` counts restarts. Under the fourth suite: Mo 55 of 55 under both runtimes, Go 55, Python 55, Elixir 53 (the budget at the window's edge). P6: the Mo queue killed through the runtime surface under 10,000 requests a second was answering again in 106 ms with nothing lost, where Elixir's takes 285 to 694 ms; the BEAM's row is answered by a program written to chapter 3's pattern. Nothing new eroded in three generations. Found: `max_restarts` on a child line takes only a literal (chapter 10 §2 now asks for a value); the crash report's rendered state is never freed, 44 MB a restart on a 20,000-job queue (step 33).
- **Step 32, crash reports apart from the ring, and the reopening store** (one Opus session, medium effort, 09:01 to 10:04; Fable's brief, probes, and reading, `mo-wiki/plans/interpreter-step-32.md`). Both runtimes keep the last 16 crash reports in a store of their own (`mo run --crashes N`, `MO_CRASHES=N`), each text cut to 4,096 bytes, read newest first, so `/crashes` answers after the ring has turned over under load; `examples/processes/crash-kept.mo` proves it 200 updates past a 64-event ring, and `restart-reopens.mo` shows a restarted process re-reading its file at start, the pattern chapter 3 names. The P6 probe on the change 2 program with the default ring lists the crash under both runtimes, seven seconds later. The standing rows unchanged within noise. Carried: both runtimes still keep every full crash report for the whole run, about 2.3 MB for 16 with 64 KB states, a step of its own.
- **P6 on Mo's change 2 program** (Fable's probe, `mo-wiki/plans/erosion-round-suite/p6-mo.py`, three runs). The queue process crashed from outside through the runtime surface, with a call the API would have refused, under about 10,000 requests a second, under `mo run` and as a binary: from the crash on every request answered `503` within 2 ms, `/health` included, none of 6,638 acknowledged jobs lost on a reopen, and the queue never restarted, by the program's `restart: :never`. Round 8's outage, a hang, is closed by the deferred reply; the restart stays the BEAM's until a Mo program takes it, and the runtime already allows it: a restarted process re-runs its state initializers with its capabilities (`reopen-run.mo`, both runtimes). Change 3 of the erosion round is that program. Found beside it: `/crashes` empty after a crash under load, the event ring having turned over; step 32 keeps crash reports apart from the ring. Chapters 3 and 10 amended.
- **The wiki as a site** (Fable, the morning; `site/`, `.github/workflows/site.yml`). Quartz builds `mo-wiki/` to GitHub Pages on every push to `main`; `mo-wiki/state-of-the-project.md` is the standing account, rewritten at every pause, and seven maps of content sit under `mo-wiki/maps/`.

## Session 8, the Mac — 15 Sep 2026

- **The Mac set up and every suite green** (Fable, half an hour). Zig 0.16.0, Go 1.27.1 with staticcheck, Elixir 1.18.5 on OTP 27.3 pinned in the Elixir worktree alone, `uv`, Pi 0.73.1; thirteen evidence worktrees recreated beside the repo and the toolchain binary copied in; the Go, Elixir, Python, and Mo queues' own suites green on the Mac. The Herdr worker pane is `w44:p2`. Robert to bed at 22:50: the lead decides, the worker is Opus on medium effort, fresh per piece of work.
- **The erosion round, generation two** (four Opus sessions of 12 to 18 minutes; Fable's pre-registration, the third hidden suite, the fourth oracle, and the reading, `mo-wiki/plans/erosion-round.md`). Change 2 (the folder checked at open, `503` and the service still answering, `/queues`, `verify`) to the Mo, Go, Python, and Elixir queues by fresh maintainers. Under round 8's two suites: 0 regressions and 0 new defects in Mo, Go, and Python; Elixir 1 (a torn line refused at open). Under the third suite (66 checks, with a 64 MB RAM disk filled under load): Mo 65, Go 66, Python 65, Elixir 62; Mo and Python share one reading of the rule table. Generation one already answered through the full disk in Mo, Go, and Python; Elixir's node exited on `:enospc` in a second and its change 2 survives the disk but not the restart. The Mo maintainer used `Reply(T)` the first time it was offered. Held P1, P4, P5, P6; failed P2 and P3.
- **Step 31, a deferred reply** (one Opus session, medium effort, 23:22 to 01:09; Fable's brief, probes, and reading, `mo-wiki/plans/interpreter-step-31.md`). Chapter 10 §1 built with zero syntax: `Reply(T)`, `reply_to` in the arm of a message with a reply, `answer` from a later arm, MO0411 for an arm that both answers and keeps or keeps twice; the simulator, the scheduler runtime, and the C runtime; a crash answers every held ask `Down`. The standing rows unchanged within noise; the deferred reply level with the send-and-a-message-back shape at 8 askers (1.00 and 1.11) and 0.46 under `mo run` at 128 held asks, the interpreter's parked fiber, a row for the placement step. Fable's crash probe: eight askers held, the batcher crashed, 8 of 8 `Down`, 8 answered after the restart, both runtimes, 1 and 14 cores.
- **Round 9, the small-model round, read** (`mo-wiki/plans/control-run-9.md`): the local qwen 27B made no edit in any language in 92 minutes; the round's reading: reliability moves with the model on the Mo side only, the diagnostics carried the small models to green, gpt-5.5 matched Opus; P1 and P4 held, P2 (open weights), P3, and P5 failed; Haiku unrun.
- **Round 9, the small-model round, four of five models run** (`mo-wiki/plans/control-run-9.md`; Fable's pre-registration, Pi harness, the suites). kimi-k3: Go 0 regressions and 1 defect in 15 min, Python 0 and 0 in 35, Mo 0 and 1 cause at 97 min (not green at the 90-minute rule). deepseek-v4-flash: Go 0 and 1 in 11 min, Python 0 and 0 in 14, Mo 0 and 2 causes in 17. Both small models' Mo changes miss the run-out lease with backoff that Opus's caught; their Go changes carry exactly Opus's one defect. gemini's key is invalid; gpt-5.5 through Codex and the local qwen 27B run in its place.
- **Measurement 1 complete, and its stronger form** (`mo-wiki/plans/bodies-as-cache.md`). The agent program regenerated twice at 1.0 (34 and 30 minutes): twelve of twelve. logstat with its tests deleted too: 1.0 under the transcripts, 0.74 under the original tests, the eight failures being the rules the tests carried that the spec never stated.
- **The Mac scaling run** (`mo-wiki/plans/mac-scaling-run.md`, the table in step 30's Result). Nothing scales on the M3 Max: every row fastest at 1 core; the disk eight times the VM's; `MO_CORES=1` for the Mac rows until placement is fixed.
- **Chapter 10, the language after the rounds** (Fable, `mo-wiki/spec/design-v0/10-language-after-the-rounds.md`). The nine language rows from rounds 6 to 10 and measurements 1 and 2 in one table, then six sections with the round row, the cost, code options, and a recommendation: a deferred reply token so a batching process can answer an `ask` later and a worker keeps its deadline (the fix for round 8's outage, zero syntax); the restart budget asked for on every `:always` child; the counted shape laws as `mo.toml` settings; `never` and `invariant` kept; MO0317's rewrite. For Robert.
- **P6 on Elixir, probed** (Fable, `mo-wiki/plans/control-run-10-suite/p6.py`). The queue GenServer killed from a second node three times while eight clients ran 11,000 requests a second: `/health` back in 261, 393, and 583 ms, 735 of 99,060 requests failed, none of 32,765 acknowledged jobs lost, on the service and on a fresh open. Five kills 400 ms apart cross OTP's default restart intensity and the node exits with the disk whole. The reading in `control-run-10.md`: P6 is the BEAM's row; after round 10 Mo holds reliability and the loop, the BEAM speed, time to write, the dependency tie, and the runtime row itself. Change 2's Mo program is the first answer to it.

## Session 7, night — 15 Sep 2026

- **Measurement 1, bodies as cache, on five programs** (ten Opus sessions of 11 to 47 minutes; Fable's stripper, verifier, and reading, `mo-wiki/plans/bodies-as-cache.md`). Every function body deleted from logstat, kv, notes, jobq, and the ledger, the intent, types, processes, signatures with contracts, and tests kept; two fresh sessions per program wrote the bodies back. Ten regenerations at completeness 1.0: every kept test, every `.expected` transcript, and jobq's 121 hidden checks, twice. The agent program waits for the Mac session, and the stronger form (tests deleted too) after it.
- **Round 10, the Elixir round, run and read** (two Opus sessions of 31 and 16 minutes; Fable's suites and reading, `mo-wiki/plans/control-run-10.md`). The BEAM null hypothesis in a pane at last: round 7's queue written in Elixir 1.18 on OTP 27 with dialyzer, credo, and ExUnit, then round 8's change. Elixir: 2 defect causes under round 7's suite (a token with a space, a torn line not cut from the file), 0 regressions, the torn cause again under the change's suite; 2,870 pairs a second at 32 workers against Mo's 1,420 on the same disk, 237 MiB against 113; the loop 6.99 s against 0.81; zero run-time dependencies. Mo keeps reliability and the loop; the BEAM takes speed, time to write, and the dependency tie; a crashed process with the service still answering, the runtime's own row, is unprobed on Elixir and was an outage on Mo.
- **Round 8, the maintenance round, run and read** (three Opus sessions of 15, 16, and 34 minutes; Fable's suites and reading). Round 7's three finished job queues, each given the change spec: regressions 0/0/0 under round 7's suite, defects 0/1/0 under the new one (Go answers `201` to a null field), 1,420 lease-and-ack pairs a second for the Mo binary against Go's 428 and Python's 325 on the same disk the same night, memory 113 MiB against 81 and 189, the loop 0.81 s against 14.4 and 7.5, zero dependencies against Go's one tool and Python's package and two tools. Held on all five predictions; the conjunction survives. Recorded beside it: no check in any language caught a change-induced bug, Mo's `never` cost two loops as a false positive after a retry reset its key, and the Mo maintainer took 2.2 times Go's wall-clock and 1.9 times its tokens. The fourth oracle, fourteen inputs from the maintainers' own decision lists, found an outage: a log record with a queued job at its `max_tries` is refused at open by Go and Python and takes the Mo service down at its first lease. The lead pauses here, as decided.
- **Round 8 set up, measurement 2 run** (Fable, about two hours; six Opus sessions of 4 to 10 minutes). The change spec for the maintenance round (`mo-wiki/spec/programs/01b-job-queue-change.md`): scheduled jobs with `delay_ms`, retry backoff with `backoff_ms`, a `POST /jobs/{id}/retry` route, `attempts`/`max_attempts` renamed `tries`/`max_tries`, and the rule that a log the round 7 service wrote still opens and compacts to the new names. The pre-registration (`mo-wiki/plans/control-run-8.md`), three worktrees, and two hidden suites (`control-run-8-suite/`), the defect suite able to have the round 7 service write the old log itself. Measurement 2 of direction 43 (`mo-wiki/plans/sampling-as-verification.md`): round 7's `Jobq.Board` stripped to signatures, contracts, intent, `never`, and tests, regenerated five times by fresh Opus sessions through a frozen harness; all five identical to the original over 132,000 random operations and 0 defects under round 7's suite; the one disagreement, on a hand-written log with a queued job at its `max_attempts`, is a crash in the original and two variants against a skip in three. The spec is complete for this module; sampling finds only what the spec leaves open, and only with directed inputs. First-fix rates per diagnostic recorded for the first time; MO0317 on a changed module's dependents cost every regeneration a loop.

## Session 6, evening — 15 Sep 2026

- **Step 30, processes on every core** (Opus, about 7 h, 4 of them measurement; Fable's brief written whole from the sketch). A scheduler per core in both runtimes, a process on one scheduler for its life, one runtime lock that Mo code and region compaction run without, a poller per scheduler woken by an eventfd, placement by fewest live processes; `Fs.write` and `Fs.append` sync on a pool of four threads with the caller parked off the scheduler; the same seed gives step 29b's trace; `ProcessInfo` and `Started` carry `scheduler`; `MO_STATS=1` prints a line per scheduler; `MO_CORES=1` is the old runtime. Measuring found two bugs the suite could not: the binary's string interpolation shared one buffer across threads, and an idle scheduler's spin ignored its own sockets. Numbers on the VM: 8 crunchers 3.7× faster at 4 cores; the ledger doubled at 1 core from the fsync pool (902 → 1,990 transfers a second); the queue unchanged, fsync-bound on this disk; a kill under load at 4 cores lost nothing, five of five by the worker and five of five by Fable's own client; the 1M replay holds its peak. Costs to read: an ask across schedulers is 3.4× one on the same, and a one-process program pays about 15 percent at 4 cores. The interpreter's 7.78 GB for 10,000 processes at rest is older than this step and carried.
- **Robert's evening decisions**: the Mac (M3 Max, 14 cores) runs the scaling sweep in parallel with round 8; Mo's claim is reliability at zero dependencies, read on both columns together; round 10 is the Elixir round (direction 42); runtime first, the language revised to its evidence in a design page at the pause after round 8.

## Session 6, morning and midday — 15 Sep 2026

- **Step 29b, replay memory on a real log** (Opus, 4 h 40 min, most of it measurement; Fable's brief from step 29's failed probe). Memory is bounded by what the program still reaches inside one `update` as between two: a process region reserves address space instead of 1 GiB, so an update never falls through to malloc, and a call made as a whole statement is a safe point where the frames waiting in calls give back what they no longer reach, so a recursion 9,000 deep holds 4 MiB where it held 89. Fable's real 1M ledger log replays native in 95 s at 2.3 GB where it was killed past 9 GB; the interpreted replay 14% faster; the bench within noise; `MO_STATS=1` reports `spilled`. Chapter 3's Processes list gains the sentence.

- **Step 29, the runtime honest** (Opus, 2 h 47 min, most of it measurement; Fable's brief from program 6's findings). A child whose supervisor line says `restart: :never` stays down after a crash in both runtimes and the simulator, its report says so, an ask to it is `Down`, and a send to it is dropped with a new `Event.Dropped`; `platform.exit` ends a program that holds a delayed send hours away, at once, with the code kept; `reduce` and `fold_lines` compact in generations, so the ledger's 1M-entry replay runs native in 81 s where it took 716 (100k interpreted 512 → 169 s) with a peak that is now the book's own size; under `mo test` simulated time passes to a delayed send only while the test waits, never between two statements; `mo test --sim` counts invariants (`invariants (kept n, tripped m)`) and names the one no message tripped. Fable's probes green under both runtimes but one: a 1M log a real HTTP session wrote replayed past 8 GB fifteen seconds after the fold, so the memory bound is open as step 29b; the suite green; the corpus gains `processes/never-restart.mo`, `programs/never-restart.mo`, `programs/exit-pending.mo`, and a second test in `processes/timer.mo`.

## Session 6, day — 14 Sep 2026

- **Program 6, `ledger`, in Mo** (Opus, 92 min; Fable's spec `mo-wiki/spec/programs/06-ledger.md`). A double-entry payments ledger over HTTP on the store recipe: accounts with overdrafts, transfers, holds that expire by a delayed `Expire` or at the next look, captures, releases, refunds, daily settlement, idempotency keys; seven `never`s over history and four `invariant`s on the journal process, three tripped by tests over a torn or doubled log; group commit. Native 1,168 transfers a second at 32 clients, 198 MB at 100k entries. Fable's 35-check session green under both runtimes. Found: a `restart: :never` process restarts anyway (a runtime bug), `platform.exit` waits on a pending delayed send, replay memory grows faster than the log (1M entries killed at 4.2 GB), and no check caught a bug the tests would not have, for the third program running.
- **Step 28, what round 7 found in the runtime** (Opus, 3 h 45 min including a pause; Fable's brief). A map, set, or struct held by one owner is written in place in both runtimes, by a move analysis shared by both backends: 2,000 overwrites on an 80k-entry map 47 s → 0.13 s interpreted and 21 s → 5 ms native, a tuple `reduce` accumulator moved (999 → 9 ms), `remove` in place with an undo. The `never` at-rest rule looks through branches. Regions give pages back and `MemoryInfo` reports region-resident bytes: memory after a 1M-record replay 183 → 57 MiB native, replay 64 → 43 s. Six stdlib gaps closed: `Fs.list_kinds`, `String.grouped`, `_` as a lambda parameter, `10.seconds` with a check-time diagnostic for a wrong unit, `Option.map`, a fixture clock that moves under the simulator. 186 of 186; Fable's probes under both runtimes; round 7's Mo jobq rebuilt and re-measured, its defect suite still clean.
- **Control run, round 7, pre-registered on Robert's measure: held on all four** (three Opus sessions, 16:40 to 17:56 UTC). Reliability under a 121-check hidden suite: Mo 0, Go 0, Python 0. Native Mo 981 lease-and-ack pairs a second at 32 workers to Go's 478 and Python's 467 on one client, 150 MiB at 100k jobs between Go's 76 and Python's 189, a restart five times Go's; the loop 0.38 s to 18.7 and 8.7; dependencies 0, 1, 3. Agent time recorded only: Mo 74.6 min to 36 and 39, 21 loops to 4 and 10. Four toolchain bug notes (a map write copies the whole map) and six gaps go to step 28. Result and reading on `mo-wiki/plans/control-run-7.md`.
- **The thesis restated** (Robert, on the outside review of 14 Sep; Fable rewrote chapter 1). Mo exists so that software written by agents is reliable and needs no third-party code: the runtime and process model carry most of it, capabilities and recipes next, the language is their surface. The control run now predicts reliability under a hidden defect suite, native speed and memory, the feedback loop, and the dependency count; agent time is recorded, not predicted. Chapter 8 gains the same under "Session 6".
- **Step 27, what round 6 found** (Opus, 48 min; Robert's three calls). The 500-line file law is gone and `MO0302` retired. `state`, `result`, and `old` are ordinary names everywhere but the positions the grammar reserves (`state` inside a process, `result` inside `ensures`, `old` inside `ensures` and `invariant`). A `never` reads values at rest: a `var` copy changed field by field is recorded once its last field is set, so chapter 4's idiom no longer trips a `never` relating two fields. A string knows `\u{X}` and refuses an unknown escape by name; `fold_lines` folds past a line that is not UTF-8 with U+FFFD in it. 185 of 185; Fable's probes under both runtimes.
- **Control run, round 6, pre-registered: failed on all four predictions** (three Opus sessions, 14:30 to 15:23 UTC, on the exe.dev VM). Two tasks, logstat and jobq, in Mo, Go with vet, staticcheck, and contracts, and Python under uv with mypy, ruff, and pydantic. Mo 51.0 min to Go's 32.2 and Python's 39.0; Mo's ten loops were the language's (five keyword or grammar refusals, one shape law, one false `never` trip), the baselines' were tool noise; no check in any language caught a real bug, so chapter 8's null hypothesis stands; Mo's jobq 2,650 lines to Go's 3,578, its program alone longer; native 399 lease-and-ack pairs a second to Go's 858. Three rows for Robert: the laws' re-evaluation, the `never` over a `var` copy, the keywords as names. Result and reading on `mo-wiki/plans/control-run-6.md`.
- **Step 26, the one-line `if` in tail position** (Opus, 25 min; Fable's brief from step 25's acceptance). A one-line `if` that starts a line is a value too: on the last line of a body that gives a value it is that body's value, exactly as the block `if` is; elsewhere it is `MO0310`, a dropped value, with the block form shown. `state` and `old` where a binding's or a parameter's name goes get a sentence naming the keyword instead of the bare "expected a name". 185 of 185; Fable's probes under both runtimes.
- **Step 25, the one-line `if` as a value and keyword field names** (Opus, 95 min over two workers; Robert's two calls; Fable's brief). `x = if c: a else: b` is a value wherever a value goes, `else:` required, one expression a branch, its tree the block form's, so both runtimes lower it unchanged (a test shows identical C and bytecode); as a statement, without `else:`, or with a statement in a branch it is `MO0101` with a sentence that says what to write. The formatter picks the shape by width and comments (`FORMAT.md` I1–I4); `mo fix` no longer rewrites it; 25 `if` values sit on one line in the corpus, from 2. `state` and `old` may name a struct's field, declared, built, read and set after a dot, encoded as named (`types/keyword-fields.mo`); jobq's `status` is `state` again. Step 24's leftovers: `MO0404`'s catalog wording, a read-only `Fs` hidden by any branch of an `if` or `case` refused, `agent` narrowed to spec 05 again (a writer process only for a run granted `write_file`). The first Linux run of the toolchain, on the exe.dev VM: three suite failures fixed, none the poller's; 184 of 184 green. Fable's probes under both runtimes.

## Session 6, evening — 13 Sep 2026

- **Step 24, what program 5 found** (Opus, 84 min; Fable's brief). The read-only `Fs` authority hole closed: a write through a narrowed `Fs` handed to a process is refused at check time. A process's `state` may hold a `Handle(T)`, so a registry can route to a process per key (`processes/registry.mo`; 10,001 handles held in 26 MiB). A delayed send, `send(msg, delay: d)`, the timer three programs asked for, in both runtimes and the simulator (`processes/timer.mo`; 1 ms lag). `Deadline.remaining`; `none` as a type in signatures; the `Event` fields renamed off the keywords; a recipe's own `Request` no longer hides the prelude's; a test's waiting `ask` gives every process rounds. No bench row over 5 percent slower. Fable's probes green under both runtimes. Result on `mo-wiki/plans/interpreter-step-24.md`; seven decision-log rows.
- **Program 5, `agent`, in Mo** (Opus, 77 min; Fable's spec `mo-wiki/spec/programs/05-agent-harness.md`). The agent harness: runs under permissions (each tool holds only its narrowed capability), budgets (one `Deadline` a run, every call on what remains of it), and retries; a scripted mock model so a check needs no network; a new recipe, `Recipes.ModelClient`, whose waiting signature takes a `Deadline`; the operator's view on `platform.runtime`. 19 modules, 4,539 lines. Native 448.7 five-step runs a second with 32 concurrent, 5.38 ms of harness time a step, 89 MiB holding 1,000 runs. Fable's 22-check session green under both runtimes. Found: an authority hole (`MO0404` and a read-only `Fs` in a start argument), the handle law forcing every request through one process for the third program running, a third ask for a timer; two invariants kept this time. Result on `mo-wiki/plans/program-5.md`; nine decision-log rows; step 24 listed.
- **Step 23, the runtime surface** (Opus, 68 min; Fable's brief; chapter 3's new section). Directions 37 and 40 built: a ring of structured runtime events in both runtimes (updates with their durations and waits, starts, ends, restarts, crashes with their reports, overflows, timeouts, sources paused and resumed), printed after a failed seed's interleaving; `platform.runtime` as a capability, `Some` under `mo run` and `mo test`, `None` in a binary unless built with `--surface`, with `processes`, `state`, `recent`, `events`, `crashes`, `sources`, `memory`, `slowest`, and `send`, `pause`, `resume` behind `read_only`; `mo run --surface PORT` serving the rows as JSON over HTTP. Six of jobq's nine questions answered in full, three in part. The ring costs 1.4 percent on a hot native path at 4,096 events. Fable's probes green under both runtimes. Result on `mo-wiki/plans/interpreter-step-23.md`; five decision-log rows.
- **Step 22, what program 1 and round 5 found** (Opus, 50 min; Fable's brief). The derived deadline: a prelude `Deadline`, `reply_by` bound in an `update` arm that answers an `ask`, `within:` taking a `Deadline` and getting what remains, `at_most` tightening and nothing extending, in both runtimes and the simulator, whose time now moves when calls wait; `jobq` rewritten on it (24 chosen literals, 7 derived, no hand-written sums, from 15, 3, and 3). `mo check --recipe` no longer counts the recipe's tests against the 500-line law; `Fs.fixture()` answers `Missing` for a folder that is not there; `json.to_i64`; the store recipe says a torn log is rewritten at the next change and `notes` follows it; `MO0101` at `is` inside a comparison; `MO0206`'s range sentence moved into its one message. No bench row over 10 percent slower. Result on `mo-wiki/plans/interpreter-step-22.md`; five decision-log rows.
- **Control run, round 5, pre-registered.** Three predictions written before the run; two held, one missed by a loop: Mo 14.8 min to Go's 11.6 and Python's 14.9 (1.28 times Go, from 1.73 in round 4); loops Mo 5 (three test mistakes, one grammar form, one honesty law), Go 2, Python 3; no shape-law loop for the fourth round; no check caught a bug in Mo, a test each did in Go and Python; every worker wrote its language directly; Mo 831 lines to Go's 1,552. Result and reading on `mo-wiki/plans/control-run-5.md`.
- **Program 1, `jobq`, in Mo** (Opus, 40 min; Fable's spec `mo-wiki/spec/programs/01-job-queue.md`). The founding premise's first real test: a durable lease-based job queue over HTTP on the store recipe, nine modules, 2,891 lines, `mo check --recipe` green, `--sim 100` under faults. Native 3,180 lease-and-ack pairs a second with one worker, 4,051 with 32; 207 MiB at 100k jobs; a 1M-record replay in 8.9 s; 1,200 silent connections held while a request is answered at once. Fable's 29-check HTTP session green under both runtimes. Found: literal deadlines lie where they nest (two of three derived sums were wrong once), the `invariant` construct kept zero of eight candidates (for Robert), the Q16 ledger stays empty, one toolchain bug (`--recipe` counts recipe tests against the 500-line law), five gaps, nine runtime-surface questions on d37. Result on `mo-wiki/plans/program-1.md`; nine decision-log rows.
- **Step 21, memory and green threads** (Opus, about 2 hours; Fable's brief; Robert's call: no syntax). A process is a stackful fiber on main's thread with a kqueue or epoll poller, not an OS thread, in both runtimes: a process per connection is bounded by descriptors (65,530 idle connections, from 8,026 interpreted and 8,185 native), a process at rest 38.8 KiB interpreted and 22.7 native (from 73.2 and 39.9), the socket bench rows faster (echo-1k 57 → 18 ms, kv-10k-get-c 386 → 210, http-1k 90 → 58), nothing over 10 percent slower. Chapter 7's four bets carry numbers: a field set and a string append now write in place (200,224 → 7 allocations), a map's oldest-key removal 29 s → 180 ms, a message deep-copies 104 to 641 bytes, contracts cost 22 to 41 percent on logstat and 4 to 7 on the servers, overflow checks within noise. `Fs.fixture()` refuses `..` (round 4's bug). Three diagnostics for round 4's loops: a one-line `if` (with a `mo fix`), a variant matched by position, a method binding to a range's last integer. Fable's probe found that an HTTP acceptor holds about 1,000 request-less connections before backpressure pauses accept (flagged for program 1). Unmet: the Linux poller compiles, never ran. Result on `mo-wiki/plans/interpreter-step-21.md`; eleven decision-log rows.
- **The research agenda answered** (Fable, 13 Sep night). The twelve concept pages Robert's Perplexity runs added (two on the LLM literature, two on safety and reliability standards, eight author profiles) mark seventeen ideas "contradicts Mo"; each has a call on `mo-wiki/deep-dives/research-agenda-2026-09-response.md`: agree 8, disagree 6, test 3. Changes: chapter 2's recursion law now says what the toolchain does (a depth bound of 10,000 and a crash; termination is `mo prove`'s obligation), chapter 3 names Armstrong's R6, three rules (the Q16 ledger, no nine-nines, reproducible builds as a release gate), two columns for round 5, one count for program 1. Measured: `mo build` is byte-identical across two independently built `mo` binaries; `mo` itself differs only in the Mach-O UUID and its signature. Nine decision-log rows.
- **VM-first and agent-native runtime features, filed** (from Robert's outside Perplexity session, 13 Sep evening; Fable filed with two factual fixes and a note on each deep dive). Two deep dives, `vm-first-vs-c-first` and `agent-native-runtime-features`, and five liked directions d36–d40: the VM as the reference runtime with C as ahead-of-time compilation of it, a runtime MCP surface, time-travel debugging, hot code reload, structured runtime events. Nothing decided; no decision-log rows until Robert locks one.
- **Ingestion pass** (Perplexity Computer, no design changes). Robert had Perplexity Computer sweep his Perplexity session library for Mo-related research not yet in the vault. Six new files in `mo-wiki/raw/research-runs/`: three deep runs answering the Mo parallel-tracks prompts (`empirical-validation-agent-language.pplx.md` from session `4a4e7abb`, `ecosystem-stdlib-platform-depth.pplx.md` from `45e714aa`, `agent-authoring-research-frontier.pplx.md` from `256a997f`) and the three short briefs from session `2c696217` that framed them. Three adjacent Perplexity runs into `mo-wiki/raw/articles/` as `pplx-*` (search toolbox, sandbox providers, Rust for ETL). One new page in `mo-wiki/research/prompts/`: `prompts-mo-parallel-tracks.md`, pairing each brief with its deep run. Session page `mo-wiki/sessions/session-06.md`. Index and log updated. The three deep runs are inputs for Fable's next research pass — provisional outputs: an `empirical-validation-plan` concept page (revising [[d28]]), an `ecosystem-strategy` concept page (answering [[q11]]), and additions to `research-summary-2026-09` and `case-against-new-languages` from the agent-authoring frontier report. No decision-log rows.

## Session 5, morning — 13 Sep 2026

(Entries for program 3, steps 12, 12b, 13, and control run round 2 are listed under the overnight heading below in the order they landed.)

## Session 5, overnight — 13 Sep 2026

- **Control run, round 4.** Same spec, same model, fresh sessions after steps 17–20, timing valid: Mo 16.1 min, Go 9.3, Python 9.0; loops Mo 5 (four the grammar's one-line forms and a misleading type error, none a law), Go 1, Python 0; no check caught a bug in any language; Mo 849 lines to Go's 1,648. The laws re-evaluated: kept, with an ergonomics step recommended. Result and reading on `plans/control-run-4.md`.
- **Step 20, the runtime owns the loop** (Opus, 105 min; Robert's call). `Listener.serve(into:, idle:)`, `Conn.lines(into:, idle:)`, and `HttpListener.serve` make the runtime accept and read and deliver each connection, line, or exchange to a process as a message, with backpressure at the mailbox bound and `Idle`; a `message` line may carry a capability, which moves (`MO0410`); echo, kv, httpd, notes, workers, and both effects files rewritten with no loop around a waiting call, every `.expected` unchanged, a corpus check that refuses one; `MO0223`, `MO0327` (an invariant that reads `old` needs a `test rejects`), a process may start its supervisor's children without a capability, a plain `mo check` honours `# recipe:`. Before and after on `plans/interpreter-step-20.md`.
- **Step 19, what program 4 found** (Opus, 75 min). A process that nothing holds a handle to is freed once its mailbox is empty (200,000 processes at 21 MB interpreted, 9 MB native; a worker per request serves 20,000 requests where 20,000 ran out of memory before); an `update` waiting on a send it holds crashes with a report instead of hanging; `mo check --recipe Module.Recipe file.mo` holds an implementation to its recipe's signatures, contracts, tests, and `never`s (`MO0326`), and a recipe may hold `never` blocks; `Fs.mkdir`; `mo run --clock` for a fixed clock; three diagnostics say what to write (`or` on a `Result`, importing a message, a struct and variant sharing a name); `Fs.each_line` removed; a mutation test of the contract machinery in the toolchain, 9 of 10 mutants caught, the survivor recorded.
- **Program 4, `notes`, in Mo** (Opus, 55 min). The first program over HTTP and the first built from two recipes (`examples/recipes/store.mo` is new): create, read, list, update, delete over JSON, bearer tokens, a rate limit per client, durable through an append-only log, `notes check` over a real socket. Native: 7,621 creates/s, 23,692 gets/s with 32 clients, 103 MiB at 100k notes, a 1M-line replay in 6.3 s. The recipes saved a design and exposed a gap: nothing checks an implementation against its recipe. Two runtime findings: a started process is never freed, and an `update` that waits on a process it started deadlocks silently. Result and reading on `plans/program-4.md`; everything found goes to step 19.
- **Step 18, the outside review's no-compat fixes** (Opus, 55 min). `invariant` holds after every `update` and trips when false (chapter 4's example is now `state.done >= old(state.done)`); `Handle(T)` counts as a capability, an anonymous function that captures a capability or handle is `MO0409`, a dropped pure value is `MO0310`; calls nest at most 10,000 deep and past it a Mo crash report replaces the Zig trace; grouped patterns `A | B: body` (kv's six identical arms are one); maps and sets equal by content; the sidecar's `verified:` hash covers every used module's bodies; `mo test --faults P --until F` stops injecting partway so a test can assert progress after faults. Both runtimes, spec lines updated with step 18 notes, catalog regenerated.
- **Chapter 3, the failure model** (Fable). What a crash discards, what each timeout leaves, what restart loses, when a reply is durable, poison and escalation, cleanup on crash, restart with live clients, overload; every line from decisions already taken.
- **Step 17, the round 3 follow-ups** (Opus, 35 min). `any(T)` over a refined type generates only values its `where` admits, in both runtimes, and `MO0325` when nothing does; `FsError.NotText` from `read`, `read_lines`, and `each_line` for a file that is not UTF-8, and `Fs.read_bytes`; `Fs.fold_lines`; six diagnostics reworded to say what to write instead (`MO0002`, `MO0101`, `MO0102`, `MO0212`, `MO0309`, `MO0317`); the catalog regenerated. Two corpus programs prove it.
- **The outside review** (Amp, on `main`): `deep-dives/outside-review-2026-09-13.md` with its evidence page; Fable's response and today's baselines on `deep-dives/outside-review-2026-09-13-response.md`; the no-compat fixes are step 18.
- **Control run, round 3.** Same spec, same model, fresh sessions after steps 14–16: Mo 9 loops to green (6 syntax or law diagnostics, 1 real bug caught by a test and a `never`, 2 test mistakes), Go 2, Python 1; wall-clock void for Mo and Go, the machine slept mid-run. Two toolchain bugs (`any(T)` ignores a refinement, `read_lines` returns non-UTF-8) and one gap (no fold over lines) go to step 17. Result and reading on `plans/control-run-3.md`.
- **Step 16, HTTP in the stdlib** (Opus, 65 min). `Http` over `Net` with no new syntax: `Request` and `Response` as prelude structs, `Http.listen`, `accept` giving an `Exchange`, `reply`, `Http.send`, `HttpError`, and `Http.fixture()`; HTTP/1.1 only, one request per connection, `Content-Length` bodies, 1 MiB limits, chunked refused as `501`; `## Http` in `09-stdlib.md` and `PRELUDE.md`; `http.zig` shared by both runtimes' designs and ported to `mo_rt.c`; `effects/http.mo`, `stdlib/http.mo`, and `programs/httpd/` (a hello server driven by its own clients) identical under `mo run` and as binaries. 1,000 round trips: 58.5 ms native, 98.4 ms interpreted; the servers at 2.4 and 4.6 MiB after them.
- **Step 15, processes and `Net` in the C backend** (Opus, 40 min). The runtime gains Mo.Sim's scheduler and Mo.Server's turns: processes on threads of their own taking turns, mailboxes, `ask` with deadlines, supervisors with restart limits, `update` undone on crash, invariants, the crash report as the interpreter prints it; `Net` over POSIX sockets with step 11's deadline outcomes and `Net.fixture()`; `mo build` refuses nothing now, and the differential test covers every process module, `effects/net.mo`, `echo`, and `kv`. Native echo-1k 33.9 ms against 52.2 interpreted; kv-10k-get 345 ms against 476; kv after 50k SETs 19.2 MiB against 37.4. `--sim` has no compiled form.
- **Step 14, follow-ups** (Opus, 45 min). Contracts run in every build, `--no-contracts` for measurement only; three interpreter panics (NaN ordering, 39-digit integers, huge `checked_mul`) fixed; the formatter breaks long list literals and keeps one-line anonymous functions in long calls; `sort_by_desc`, `min_of`, `max_of`, `Fs.each_line`; `build` in the usage text; the catalog regenerated.
- **Step 13, the C backend** (Opus, 83 min). A C11 runtime with the interpreter's value model and region allocator; an emitter from the checked tree; `mo build file.mo [--target triple]` through `zig cc` to a static binary (musl on Linux); `--tests` binaries; differential tests over every corpus program and module against the interpreter, zero differences. Native logstat: 200k lines in 0.14 s; 4k lines in 6.8 ms against 44.6 ms interpreted; `mo build` of logstat 0.86 s, of which C emission is 1.5 ms. Read-only `Fs` refused at check time.
- **Control run, round 2.** Same spec, same model, fresh sessions on today's toolchain: Mo 11.8 min (round 1: 25.5) with zero failed runs, Go 8.2, Python 7.9. Result and reading on `plans/control-run-2.md`.
- **Step 12b, two defaults undone** (Opus, 25 min). Pure-call memoization removed from the reference interpreter; every `never` now runs at the end of every test over the values the run held, not only under `--sim`; `MO0324` when a `never` cannot be checked; `examples/contracts/never-trips.mo` proves it in a plain `mo test`.
- **Step 12, the runtime under real programs** (Opus, 80 min). The corpus test discovers programs; maps and sets get a hash index; state is written in place and undone on crash; a process keeps nothing per request; `Fs.write`, `append` (fsync), `remove`, `rename` with `Mo.Sim` fixtures; `Out.flush` and `Out.fixture`; a function may omit its return type; negative literal patterns; `String.byte_size`; `mo fmt` fuzzed; four diagnostics reworded. kv is durable across restart and stays at 19 MB after 50k SETs (was 616 MB after 10k). 100k map sets and gets: 47 ms.
- **Program 3, `kv`, in Mo** (Opus, 40 min). A TCP key-value store with a line protocol, a store process with `never`s, a listener and a worker per connection, `--sim 100` green. 15k GETs/s over a real socket. Not durable yet (no file write) and not merged to `main` until step 12 fixes the six bugs it found.
- **Step 11, `Net`.** Processes and supervisors run under `mo run`; the `Net` capability (listen, accept, connect, `read_line`, write, close) with deadlines that leave a defined state; blocking calls do not stop the scheduler; `Net.fixture` in `Mo.Sim` with fault injection; an echo server and client over a real socket in `examples/programs/echo/`; `## Net` in `09-stdlib.md` (Opus, 62 min). 1,000 localhost round trips: 56 ms.
- **Step 10, tooling.** The `verified:` line lives in the file (`mo test --write`) with a `.mo.ids` sidecar per program root, so `MO0317` detects a hand edit precisely; `mo fix` rewrites pure loops to `map`/`filter`/`reduce`, deletes unused bindings, drops default parameters; `spec/errors.md` generated from the diagnostic tables, 59 codes, checked by the corpus test; the root README rewritten as a front door (Opus, 60 min).
- **Step 9, `Mo.Sim` with seeds and faults.** `mo test --sim N` (seeded delivery order, send timing, clock advance), `--faults P` injecting `Timeout` and `Missing` into every waiting capability call, `never` over `T.all` checked at the end of every seeded run, `sim (N runs)` on the `verified:` line, failures print the interleaving and a replay command; `examples/processes/racy.mo` fails only under sim (Opus, 45 min). 100 seeds of the refund module: 628 µs.
- **Step 8, the stdlib.** `spec/design-v0/09-stdlib.md` (118 rows: integers and floats, strings, lists, maps and sets, time, files, output, JSON), every row a built-in with a test under `examples/stdlib/`; `zig build` installs a ReleaseSafe `mo`; `logstat` rewritten on the stdlib: 1,174 → 758 lines, 200k lines in 0.95 s and 38 MB (Opus, 60 min).
- **Step 7, programs of many modules.** `use A.B{X, y}` imports functions; a program is a tree of files under `mo.root`; the corpus test runs multi-file programs; `push` grows in place (200k pushes: 3 min 10 s → 0.15 s); a region allocator freed at safe points; pure-call memoization; logstat at 39 µs per line in ReleaseFast (was 3.7 ms); `logstat` runs from its four files with no join script (Opus, 67 min).
- **Program 2, `logstat`, in Mo.** Written by Opus from `spec/programs/02-log-analyzer.md` in 25.5 minutes: four modules, 78 functions, median 4.5 lines. Correct end to end once the file law is lifted for the joined file. Three toolchain bugs and nine stdlib gaps recorded.
- **The control run.** The same spec in Go (12.9 min) and Python (8 min) by the same model; all three verified. Result and reading on `plans/control-run.md`.

## Session 5 — 12 Sep 2026

- **Spec.** `grammar.md`: seven productions fixed (`cmp`, `assert`, `old`, `never`, `add`, `params_untyped`, comprehension) and a "Session 5 decisions" section settling every gap the corpus found. Chapter 2: deadline law narrowed to calls that can wait. Chapter 3: platform chosen by the toolchain; supervisors take parameters. Chapter 4: example and rules updated to match. Chapter 6: recipe example gains a `requires` for its `rejects` test.
- **Corpus.** `examples/`: 50 tiny programs, one construct each, 12 of them in `rejects/` that must fail to compile, plus `GAPS.md`. Written by Opus; the same brief was also run by Grok and Codex on branches `corpus-grok` and `corpus-codex` for the model bake-off.
- **Step 6, Mo runs programs.** `fn main(platform: Platform)`, the `Platform` parts in the prelude, `Mo.Server` over `std.Io` (args, env, stdout, stderr, scoped read-only files with containment, wall clock, exit code), `mo run file.mo -- args`, three programs in `examples/programs/` with `.expected` output checked by the corpus test (Opus, 21 min).
- **Step 5, the formatter.** `mo fmt` (in place, `--check` with a diff, `--stdout`), the rules as a table in `toolchain/FORMAT.md`, idempotence and round-trip tests over the corpus, the loop rule as `MO0501`, `for _`, `MO0319` for a state field with no zero value; the corpus reformatted in one commit (Opus, 35 min). Whole corpus formats in 411 µs.
- **Interpreter step 4, milestone met.** `Mo.Sim` scheduler, `update` as a transaction, `invariant` after every message, bounded mailboxes crashing the sender, supervisors with restart limits, chapter 3's crash report (seed, message log, state before, clause) (Opus, 21 min, about 1,300 lines). The refund queue runs; 52 corpus files; every test in the corpus in 579 µs. Chapter 4 corrected three more times by the compiler.
- **Interpreter step 3.** Bytecode, stack VM with value semantics and overflow traps, tier-2 contracts (`requires`, `ensures`, `old`, refinements), test runner, properties under 200 seeds, `mo test` with the `verified:` line (Opus, 36 min, about 2,500 lines). The refund module from chapter 4 joins the corpus and runs its five tests; every test in the corpus runs in 538 µs. Chapter 4's example fixed: it lacked two `rejects` tests its own law requires.
- **Interpreter step 2.** Tier-1 checker (Opus, 48 min, about 4,000 lines): prelude as data with `PRELUDE.md`, names and types, every chapter-2 law with its own `MO03xx` code, capabilities and `flows` (`MO04xx`), `mo check --json`. All 12 `rejects/` fail with their named code; 38 files clean; whole corpus checked in 251 µs.
- **Interpreter step 1.** Lexer and parser (Opus, 23 min): all 50 corpus files parse; lex + parse of the whole corpus in about 100 µs; incremental rebuild 122 ms. Corpus updated to the Session 5 decisions; 2 gaps remain.
- **Toolchain.** `toolchain/`: Zig 0.16 layout with a stub per stage, the `mo` CLI, a corpus test, `mo-bench`, and `bench/rebuild.sh`. First incremental rebuild: 127 ms.
- **Process.** Work moves to feature branches (`session-05`). Fable delegates code to Opus and reviews. Decision log and this changelog begin.

## Session 4 — 12 Sep 2026

- **Spec.** `pub` replaced by the `expose` line; `use A.B{X, Y}`; every `for` closes with `end`; loops-versus-combinators rule.

## Sessions 1–3 — 12 Sep 2026

- The wiki (`mo-wiki/`), 35 directions, 17 questions, 15 syntax picks, 13 language comparisons, the eight-chapter design v0, the first grammar.

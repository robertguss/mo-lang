---
source_url: https://ampcode.com/user-content/attachments/5421b631bb1163d6afab3eb8360cae643164d25ea8270779ed552cd9e38184f1-Agent-Generated-Mistakes-Across-Six-Runtime-Concerns-Concrete-Examples-and-the-Costs-of-Preventio.md
ingested: 2026-09-18
sha256: 21c0a7f5d399b77d0514966a5070359061e11ac7ed80cd7d56291ea69f62e77b
---
# Agent-Generated Mistakes Across Six Runtime Concerns: Concrete Examples and the Costs of Prevention

Language-and-runtime designers building for AI-authored software (Mo, Roc, Wuffs, and others) face a repeated dilemma: which failures earn a language rule, which earn a library or platform brick, which earn a static analyzer, and which earn a runtime check. This report catalogs concrete agent- and LLM-generated defects in six categories — error handling, capabilities, concurrency, deadlines, retries, and persistence — then compares the prevention mechanisms available today and prices what each one gives up: valid programs made harder to express, false positives, and additional repair cycles.

The evidence base combines peer-reviewed empirical studies of LLM- and agent-generated code, production postmortems (Cloudflare, GitHub, RacerD at Facebook, Oxide's Omicron), industry runbooks (AWS Builders' Library, PostgreSQL wiki), and language design records (Rust, Pony, Deno, Kotlin coroutines).

## Preface: How Agents Fail Differently From Humans

Two independent empirical signatures separate agent-generated defects from typical human defects.

The first is **volume and shape**. Apiiro's June 2025 telemetry across its customer base reports that AI-assisted developers produced three to four times more code but generated ten times more security issues per unit time, with over 10,000 new security findings per month from AI-generated code — a 10x jump from December 2024 — including a 322% increase in privilege-escalation paths and a 153% increase in architectural design flaws ([The Register](https://www.theregister.com/software/2025/09/05/ai-code-assistants-improve-production-of-security-problems/329883)). The Register also documented an AI-driven pull request that altered an authorization header across multiple services while leaving one downstream service unchanged, producing a silent authentication failure ([The Register](https://www.theregister.com/software/2025/09/05/ai-code-assistants-improve-production-of-security-problems/329883)).

The second is **failure mode composition**. A 2025 study of automated issue solving across 24 newly-solved SWE-bench-style problems ([Xu et al., arXiv:2509.13941](https://arxiv.org/html/2509.13941v1)) found that agents systematically fail through three characteristic patterns: superficial information matching from error output, evasive repair that wraps a symptom rather than fixing the cause, and misreading validation output. Six of the 24 newly-solved cases required correcting "reproduction output misreading" — the agent read a failing test as success and submitted a broken patch ([Xu et al., arXiv:2509.13941](https://arxiv.org/html/2509.13941v1)). Five required correcting "evasive repair" defects such as `except: pass` used to silence a `FieldError` in `django__django-16938` rather than resolving the incompatibility between `select_related` and `.only("pk")` ([Xu et al., arXiv:2509.13941](https://arxiv.org/html/2509.13941v1)).

Cockroach Labs argues that agentic workflows also generate a distinctive traffic shape: an orchestrator spawning five sub-agents that each run two-to-three parallel tool calls yields 10–15 simultaneous OODA cycles per user request, and at 1,000 concurrent users that becomes 10,000–15,000 simultaneous cycles converging on completion at nearly the same moment — a load profile "that resembles nothing predicted by a human-traffic model" ([Cockroach Labs](https://www.cockroachlabs.com/blog/agentic-ai-thundering-herd-problem/)). In their travel-booking benchmark, PostgreSQL fell from tracking CockroachDB at low concurrency to 42 ops/sec at 10,000 concurrent agents versus CockroachDB's 129 ops/sec — a ~3x gap driven by convergent write patterns ([Cockroach Labs](https://www.cockroachlabs.com/blog/agentic-ai-thundering-herd-problem/)).

These signatures matter because they set the target for prevention. Agents fail through evasion, through false success reads, and through parallelism that concentrates load. Preventive mechanisms need to make evasion structurally hard, make silent success unreadable as success, and make concentrated load survivable.

## 1. Error Handling

### Concrete agent-generated defects

**Evasive repair.** In `django__django-16938`, an agent responded to a serialization `FieldError` by wrapping the failing block in `except: pass`, which skipped the query optimization instead of resolving the conflict between a `ManyToMany` custom manager and `.only("pk")` ([Xu et al., arXiv:2509.13941](https://arxiv.org/html/2509.13941v1)). Correcting this class of "strategic flaw" was required in 5 of 24 newly solved issues under the Expert–Executor framework ([Xu et al., arXiv:2509.13941](https://arxiv.org/html/2509.13941v1)).

**Downstream crash handling instead of root-cause repair.** In `sympy__sympy-12420`, the agent read `IndexError` at the end of a stack trace and modified `radsimp.py` to handle the crash, when the actual cause was upstream in `sqrtdenest.py` passing an empty tuple to `split_surds` ([Xu et al., arXiv:2509.13941](https://arxiv.org/html/2509.13941v1)).

**API misuse producing runtime exceptions.** A large study of 5,741 LLM-generated bugs across nine models found API misuse is the highest-proportion runtime bug across most benchmarks, split among `AttributeError` (20.9%), `TypeError` (50%), and `ValueError` (26.9%) ([Ouyang et al., arXiv:2407.06153](https://arxiv.org/html/2407.06153v2)). A canonical example: generated code calling `tup.sort()` on a tuple, or calling `result % MOD` where `MOD` is never defined ([Ouyang et al., arXiv:2407.06153](https://arxiv.org/html/2407.06153v2)).

**Swallowed exceptions and weak error surfaces.** A characterization of 375 faults across popular agentic-AI repositories ([Bouzenia et al., arXiv:2603.06847](https://arxiv.org/html/2603.06847v1)) reports Error Handling symptoms in 8.3% of cases (31 occurrences) and "Weak Error Handling and Logging" as a root cause in 7.5% (28 occurrences). Named examples include Netflix/metaflow's escape-hatch logic bypassing normal error handling and mismatching exception types during imports, and mindsdb/mindsdb failing to catch Langfuse errors and falsely reporting rate-limit conditions ([Bouzenia et al., arXiv:2603.06847](https://arxiv.org/html/2603.06847v1)).

**Unwrap misuse: Cloudflare, November 18, 2025.** A Bot Management "feature file" that normally held dozens of records surged to several hundred after a ClickHouse database permission change altered query behavior; the Rust proxy service called `unwrap()` on external input and panicked. Because the service was deployed across edge nodes globally, node shutdown propagated the outage rapidly ([Zenn analysis](https://zenn.dev/dokusy/articles/666387f63061de?locale=en), [Compiling Ideas podcast](https://podcasts.apple.com/us/podcast/the-line-of-rust-that-broke-the-internet/id1845581162?i=1000744663797&l=ru)). The immediate `unwrap()` was the fuse; the deeper failure was fragility of preconditions plus a configuration change that never touched staging.

**Unchecked return values and uninitialized variables.** A study of Copilot-generated code on GitHub found CWE-457 (Use of Uninitialized Variable) at 30 occurrences (4.78% of 628 weaknesses), CWE-390 (Detection of Error Condition Without Action) at 1.75%, and CWE-252 (Unchecked Return Value) at 0.64% ([Fu et al., arXiv:2310.02059](https://arxiv.org/html/2310.02059v3)). In a controlled study, AI-assisted C code from participant 1045 "did not check the return codes of any library functions" ([Perry et al., arXiv:2211.03622](https://arxiv.org/html/2211.03622v3)).

### Prevention: what each mechanism does

| Approach | Mechanism | What it prevents | Named tools |
|---|---|---|---|
| Language rule | `Result<T,E>` return type; no exceptions | Silent error propagation | Rust, Go, Roc, Zig |
| Language rule | `#[must_use]` warning propagation | Ignored return values | Rust `#[must_use]`, Haskell `warn-unused-do-bind` |
| Language rule | Checked exceptions | Undeclared error paths | Java `throws` |
| Static analysis | Unused-result linting | Discarded `Result` values | Clippy `unused_results`, `unwrap_used` |
| Static analysis | Panic-freedom analysis | `unwrap`/`panic` in prod code | `no_panic` crate, MIRAI, Prusti |
| Runtime check | Supervised process restart | Fault containment when errors do reach the boundary | Erlang/OTP, BEAM |
| Runtime check | Structured event ring | Post-hoc reconstruction of swallowed errors | Mo's `platform.runtime`, OpenTelemetry |
| Library | Error-context propagation | Loss of root-cause information | Go `errors.Wrap`/`fmt.Errorf %w`, Rust `anyhow`, `snafu` |

### Costs: what each approach charges

**`Result<T,E>` and no-exceptions.** Rust's chosen model forces `?` propagation or explicit handling at every call site, and the community has repeatedly reported that this incentivizes `unwrap()` as an escape valve; the Cloudflare outage was, in one reading, "Rust doing exactly what it promises" once an assumption broke ([Compiling Ideas](https://podcasts.apple.com/us/podcast/the-line-of-rust-that-broke-the-internet/id1845581162?i=1000744663797&l=ru)). The Zenn analysis argues the ergonomic cost of always writing `match` or `?` is precisely what pushes engineers toward `unwrap` in exactly the wrong places — external input, network, and I/O paths ([Zenn](https://zenn.dev/dokusy/articles/666387f63061de?locale=en)).

**`#[must_use]` propagation and unused-results lints.** The Rust internals discussion documents a live tension: enabling `unused_results` "reports every unused result," which produces so much noise that developers ask for `#[may_ignore]` to opt-out common cases like `Vec::push` and `HashMap::insert` ([Rust internals](https://internals.rust-lang.org/t/improving-the-usefulness-of-must-use/22382)). The proposal to propagate `#[must_use]` through wrapping functions is stalled precisely on the false-positive question: a function that returns a `#[must_use]` value may itself be the point of use, so mechanically requiring the propagated attribute produces spurious warnings.

**Checked exceptions.** Java's `throws` mechanism is the classic case study of a preventive rule the ecosystem partly rejected; developers routinely catch-and-ignore or wrap in `RuntimeException` to escape signature-cascade churn, and the pattern "leads to worse error handling, not better," according to multiple critiques including the Java community's own retreat toward unchecked exceptions in Spring and Hibernate ([alexn.org critique](https://alexn.org/blog/2022/09/28/the-trouble-with-checked-exceptions-part-2/)).

**Supervision as the compensating runtime.** Erlang/OTP inverts the tradeoff: the language does not police whether errors are handled inline; the runtime guarantees the process is restarted with clean state ([Erlang supervisor docs](https://www.erlang.org/doc/system/sup_princ.html)). The cost is that "let it crash" only works when process state is truly isolated and idempotent restart is safe — the discipline moves from error handling into state design.

## 2. Capabilities and Authority

### Concrete agent-generated defects

**Path traversal.** In a controlled study of AI-assisted developers, the sandboxed-directory task required preventing access outside `"/safedir"`. AI assistants frequently generated code that checked whether the path started with `"/safedir"` but did not canonicalize; such code failed to prevent `..` traversal. AI-assisted participants were significantly more likely to mishandle symlinks (p = 0.019); 73% of symlink mistakes and 61% of parent-directory mistakes were attributed to the AI ([Perry et al., arXiv:2211.03622](https://arxiv.org/html/2211.03622v3)). Only 12% of AI-assisted participants wrote secure Q3 solutions versus 29% of the control group.

**SQL injection via string concatenation.** In the same study, 36% of AI-assisted participants produced SQL-injection-vulnerable Q4 solutions versus 7% in the control group (p = 0.041) ([Perry et al., arXiv:2211.03622](https://arxiv.org/html/2211.03622v3)).

**Hard-coded credentials and improper access control.** Fu et al. reported CWE-259 (Use of Hard-coded Password) at 2.55% of 628 weaknesses and CWE-284 (Improper Access Control) at 2.07% in Copilot-generated code ([Fu et al., arXiv:2310.02059](https://arxiv.org/html/2310.02059v3)). Apiiro's data shows AI-reliant developers exposed sensitive cloud credentials nearly twice as often as non-AI colleagues, and privilege-escalation paths rose 322% ([The Register](https://www.theregister.com/software/2025/09/05/ai-code-assistants-improve-production-of-security-problems/329883)).

**Authentication bypass and unintended access paths.** Bouzenia et al. specifically cite authentication bypasses in langflow-ai/langflow and identify "Access Control and Credential Issues" as 2.1% of root causes ([Bouzenia et al., arXiv:2603.06847](https://arxiv.org/html/2603.06847v1)).

**Cross-service authorization drift.** An AI-driven pull request altered an authorization header across services and produced a silent authentication failure when one downstream service was not updated ([The Register](https://www.theregister.com/software/2025/09/05/ai-code-assistants-improve-production-of-security-problems/329883)).

### Prevention: what each mechanism does

| Approach | Mechanism | Named systems |
|---|---|---|
| Language rule | Reference capabilities | Pony (`iso`, `val`, `ref`, `box`, `trn`, `tag`) |
| Language rule | Platform-passed effects/handlers | Roc, Koka, Effekt |
| Language rule | Capability-typed FFI boundary | Wuffs (no I/O, no allocation), Mo (`platform.*`) |
| Runtime check | Process-level permission flags | Deno (`--allow-net`, `--allow-read`, etc.), WASI |
| Runtime check | Component-level compartments | CHERI, Fuchsia |
| Static analysis | Taint tracking, permission linting | CodeQL, Semgrep |
| Library | Sandboxed executors | Firecracker, gVisor, JS Realms |

Deno's default-deny model rejects operations not explicitly authorized and terminates the process if the permission broker becomes untrustworthy ([Deno security docs](https://docs.deno.com/runtime/fundamentals/security/)). Pony's reference capabilities force the compiler to verify that shared data is either immutable (`val`) or uniquely owned (`iso`), eliminating shared-mutable-state races at the type level ([Pony tutorial](https://tutorial.ponylang.io/reference-capabilities/reference-capabilities.html)).

### Costs

**Deno's flag ergonomics.** Practitioners report that granular permissions become "cumbersome" once applications go beyond examples: "Is my only option to attach a long string of flags to the `deno run` command?" ([Reddit r/Deno](https://www.reddit.com/r/Deno/comments/1hap57h/how_do_i_manage_nontrivial_permission_sets_with/)). Deno's own documentation "primarily showcases very basic permission examples," and complex applications on the Deno blog "seem to utilize the `-A` flag" — full authority — as an escape. Deno's own docs concede that `--allow-run` and `--allow-ffi` "should be treated as equivalent to `--allow-all`" because a subprocess can spawn `deno --allow-all` and escape the sandbox, and a native library loaded via FFI runs as machine code with full OS privileges regardless of `--allow-*` flags ([Deno security docs](https://docs.deno.com/runtime/fundamentals/security/)).

**CHERI adoption.** The UK Digital Security by Design programme's own adoption research puts CHERI's cost concretely: existing software "must be recompiled, rewritten where it uses memory operations forbidden under CHERI, and potentially further rewritten to use CHERI compartmentalisation." Hardware boards cost approximately US$10,000 (Arm Morello) or £300–£400 (LowRISC Sonata) at 2024 prices ([GOV.UK CHERI adoption](https://www.gov.uk/government/publications/cheri-adoption-and-diffusion-research/cheri-adoption-and-diffusion-research)). The report explicitly frames CHERI vs. Rust as a cost tradeoff: CHERI is cheaper than rewriting existing C in Rust, but requires new silicon.

**Pony's learning curve.** The Pony community has repeatedly documented that six reference capabilities plus recovery, sendability, and viewpoint adaptation constitute a substantial mental-model surcharge, and the language has struggled with adoption partly because "you have to learn a whole new type system to write a hello world" ([HN discussion](https://news.ycombinator.com/item?id=17195580)). Valid programs — for example, a cyclic doubly-linked list with shared mutable ownership — are simply not expressible without `unsafe` escapes.

**FFI holes.** Every capability system reviewed here treats native code as a residual "trusted computing base." Deno explicitly warns that `--allow-ffi` bypasses capability enforcement ([Deno security docs](https://docs.deno.com/runtime/fundamentals/security/)); WASI programs invoking host functions through the component model rely on the host to enforce capabilities correctly ([WASI capability model](https://chikuwait.github.io/blog/2023/capability/)). This is the cost of a hybrid: any capability system for a general-purpose language needs an audited "brick" model for the operations capability enforcement cannot express.

## 3. Concurrency

### Concrete agent-generated and human defects

**Kotlin coroutine bugs at scale.** A study of 55 concurrency bugs from 1,353 commits across 7 open-source repositories (IntelliJ, Firefox, Ktor, WordPress, WooCommerce, Shadowsocks, Tachiyomi) identified four coroutine-specific defect categories ([Groenendaal, TU Delft](https://repository.tudelft.nl/file/File_8fe19f70-7a66-4e5a-9890-db261850c65a)):

- **Nested `runBlocking` deadlock (11 bugs)**: Coroutine A on `Dispatchers.Main` calls a non-suspending function that runs `runBlocking` launching Coroutine B on `Dispatchers.Main`; A waits for B, B waits for the UI thread that A holds. Classic deadlock.
- **Swallowed `CancellationException` (14 bugs)**: catching cancellation as a generic exception prevents proper unwind.
- **Scope passing (4 bugs)**, **querying async objects (5 bugs)**, **synchronizing with cancellation (4 bugs)**.

IntelliJ IDEA alone contributed 23 of the 55.

**Cancel-unsafe async Rust.** Oxide's Omicron project documented four production-affecting cancel-safety incidents ([Oxide RFD 400](https://rfd.shared.oxide.computer/rfd/0400)):

- `proxy_instance_serial_ws` (Omicron #3356): `tokio::select!` among four futures, only one cancel-safe. A cancelled `send` operation could lose the message.
- Wicketd's `report_progress` used a mutex across an await point and left updates stuck in an `Invalid` state on abort (Omicron PR #3950).
- Sled-agent's `try_for_each_concurrent` zone deletion cancelled peer operations on failure, leaving zones — external state — in inconsistent states (Omicron PR #3758).
- Dropshot cancelled request futures on client disconnect, exposing every non-cancel-safe code path in Omicron (Dropshot PRs #701, #702).

**Data races in Copilot code.** Fu et al. found CWE-367 (TOCTOU race condition) at 0.48% and CWE-605 (multiple binds to same port) at 0.64% of 628 weaknesses ([Fu et al., arXiv:2310.02059](https://arxiv.org/html/2310.02059v3)).

**Facebook Android News Feed.** Migrating Litho layout from single-threaded to multi-threaded required moving hundreds of classes and many millions of lines through a background-layout switch that "was as simple as flipping a flag" but expected to introduce data races ([Sadowski et al., RacerD](https://ilyasergey.net/papers/racerd-oopsla18-preprint.pdf)).

### Prevention

| Approach | Mechanism | Named systems |
|---|---|---|
| Language rule | Ownership + `Send`/`Sync` traits | Rust |
| Language rule | Reference capabilities forbid shared mutable | Pony, encore |
| Language rule | Actor-only concurrency | Erlang/BEAM, Akka, Pony |
| Language rule | Structured concurrency scopes | Kotlin, Java 21 `StructuredTaskScope`, Swift, Trio |
| Static analysis | Compositional race detection | RacerD (Facebook Infer) |
| Runtime check | Sanitized dynamic race detection | Go race detector, ThreadSanitizer |
| Runtime check | Deterministic scheduling / replay | Mo's seeded scheduler, Antithesis, PCT |

### Costs

**Rust borrow checker false positives and rejected valid programs.** A representative complaint from the Rust user forum documents a parser calling `self.multiply()` then `self.match_token()` producing E0499 "cannot borrow `*self` as mutable more than once at a time" for an algorithm that would be trivially safe in Java or Go ([Rust users forum](https://users.rust-lang.org/t/how-to-fight-this-borrow-checker/36601)). This is not a race, and not a use-after-free; it is a valid program the borrow checker cannot prove safe. The Polonius work and NLL have narrowed but not closed this gap.

**Cancel safety complexity.** Oxide's RFD 400 concludes that cancel safety in async Rust is a project-scale discipline: "much Omicron code had not been written with cancel safety in mind." The eventual mitigation for Dropshot was architectural — each request runs on its own task so client disconnection cannot cancel the handler ([Oxide RFD 400](https://rfd.shared.oxide.computer/rfd/0400)). The valid program made harder to express here is any operation that fans out multiple side-effecting subtasks and expects all-or-nothing semantics under cancellation.

**Structured concurrency scope pain.** Kotlin's own bug catalog shows that even a well-designed structured-concurrency system leaves developers deadlocking on nested `runBlocking` and swallowing `CancellationException` — 25 of 55 bugs in the TU Delft study ([Groenendaal](https://repository.tudelft.nl/file/File_8fe19f70-7a66-4e5a-9890-db261850c65a)). The bugs are subtle: the type system happily accepts them because the type-level contract does not encode dispatcher identity.

**RacerD false-positive/false-negative tradeoff.** RacerD was deployed at Facebook for over a year and flagged 2,500+ concurrency issues that engineers fixed pre-production; over the same year, engineers reported only three false negatives from production, and all three were attributed to implementation bugs in RacerD itself ([Sadowski et al.](https://ilyasergey.net/papers/racerd-oopsla18-preprint.pdf)). The paper is candid that "no confirmed false negatives" is not the same as "no false negatives," and false positives are managed by making the analysis intentionally under-report on some patterns to keep signal-to-noise usable at scale — a valid-program-rejection cost paid in silent under-reporting rather than in developer friction.

**Go race detector runtime overhead.** The Go race detector reports 5–10x memory overhead and 2–20x CPU overhead in typical runs, which is why it is a testing tool rather than a production check ([Go race detector docs](https://go.dev/doc/articles/race_detector)). The cost is that production races are only caught if they appear in tests or in canary deployments.

## 4. Deadlines and Timeouts

### Concrete defects

**A2A Timeout and Tool Latency in agent systems.** AgentChaosBench injected controlled faults into 275 real agent executions and reported that models struggled hardest with latency and timeout faults: top-3 recall for Tool Latency ranged from 0/25 to 11/25 across evaluated models, with a paired fault-free reference improving Qwen3-14B recall by 55 percentage points on Context Overflow and 35 points on Tool Latency ([Yang et al., arXiv:2608.14680](https://arxiv.org/pdf/2608.14680)). A2A Latency with an injected 15-second delay produced measured deltas from −3s to +26s across systems — evidence that agents often cannot even reliably observe timeouts, let alone budget them.

**Missing connection-establishment budget.** AWS documented an incident where a 20-millisecond timeout that was correctly sized for a warm connection failed intermittently for newly deployed servers because the timer included the initial secure-connection handshake. The fix was to establish connections at process startup, before receiving traffic ([AWS Builders' Library — Timeouts, retries, and backoff](https://d1.awsstatic.com/builderslibrary/pdfs/timeouts-retries-and-backoff-with-jitter.pdf)).

**Cascading timeout absence.** The IJCESEN systematic review notes that "distributed systems are often susceptible to cascading failures when there is no adequate coordination of the timeout settings at architectural layers"; system-wide outages occur without an outward-increasing timeout hierarchy ([Bhairavabhatla, IJCESEN](https://www.ijcesen.com/index.php/ijcesen/article/view/3959)).

### Prevention

| Approach | Mechanism | Named systems |
|---|---|---|
| Language rule | Every I/O call takes a deadline argument | none in mainstream languages; proposed for Mo |
| Library / convention | Explicit context/scope carries deadline | Go `context.Context`, Java `StructuredTaskScope`, Trio |
| Static analysis | Missing-timeout linters | Semgrep rulesets, Errcheck extensions |
| Runtime check | Enforced timeout on every syscall | Erlang `receive after`, Mo's runtime bounds |
| Runtime check | Circuit breakers as reified timeouts | Hystrix, resilience4j, Envoy `outlier_detection` |

### Costs

**Deadline plumbing.** Go's `context.Context` is the widest deployment of a deadline-first convention, and its cost is well-documented: every function in the call chain must accept and propagate `ctx`, ambient authority is lost, and the community has repeatedly debated whether `context.Context` is a design success or a viral function-signature parasite ([Go blog](https://go.dev/blog/context)). The valid-program cost is real: infrastructure code that legitimately runs forever (background workers, event loops) must fabricate `context.Background()` or wire in cancellation from above.

**AWS's percentile-based tuning.** AWS's recommended approach is "choose an acceptable rate of false timeouts (such as 0.1%) and use the corresponding downstream latency percentile (p99.9)," which forces every deadline decision to become an operational calibration exercise ([AWS Builders' Library](https://d1.awsstatic.com/builderslibrary/pdfs/timeouts-retries-and-backoff-with-jitter.pdf)). The cost is that the "false timeout" rate is not zero — some legitimate requests will be aborted — and the p99.9 must be measured, not guessed.

**Cascading timeouts as architecture.** The outward-increasing timeout hierarchy — internal services fail fast, gateway components have the largest budget — is described as "an innovative architectural decision" that must be "carefully calibrated based on empirical patterns of latency" and integrated across database, platform, load balancer, and ingress layers ([IJCESEN](https://www.ijcesen.com/index.php/ijcesen/article/view/3959)). This is a coordination cost, not a compilation cost.

## 5. Retries

### Concrete incidents

**GitHub, August 17, 2026: an 8-hour retry storm.** A capacity failure in Central US, compounded by a sidecar concurrency limit that autoscaling did not monitor, caused authentication token refresh to time out. A latent retry bug in the VS Code Copilot extension amplified traffic ~10x. The Copilot Token Service went from 7,000–9,000 RPS to 70,000–100,000 RPS. Error rates hit ~20% on web/API and ~50% on file downloads. The incident lasted 7 hours 47 minutes (13:28–21:15 UTC); approximately 4 hours were "the system fighting its own retries" ([Cloud DonWeb postmortem summary](https://cloud.donweb.com/github-17-ago-el-retry-storm-que-estiro-un-outage-a-casi-8-horas/)). Recovery required a gateway-level PR that ejected retries with HTTP 403 while capacity refilled.

**Retry amplification math.** A five-deep service stack with three retries per layer produces up to 243x load amplification on the deepest service ([AWS Builders' Library](https://d1.awsstatic.com/builderslibrary/pdfs/timeouts-retries-and-backoff-with-jitter.pdf)). A three-tier stack with 50% failure and three-retry limits yields analytically ~6.59x, and 30% failure yields ~2.85x ([Karthik et al., arXiv:2608.25403](https://arxiv.org/pdf/2608.25403)).

**Missing idempotency, duplicate side effects.** AWS documents an EC2 workflow retrying a failed EBS-volume creation, producing two volumes — the canonical "create-then-lose-response" hazard ([AWS Builders' Library — Idempotent APIs](https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs/)). Singleton workloads where a network timeout hides success can end up with multiple EC2 instances running.

**Infinite loop retries in agent systems.** AgentChaosBench's "Infinite Loop" fault surfaces as at least three tool calls with the same tool name and input, which is a common empirical footprint in production agent traces ([Yang et al., arXiv:2608.14680](https://arxiv.org/pdf/2608.14680)).

### Prevention

| Approach | Mechanism | Named systems |
|---|---|---|
| Language / library | Idempotency keys as required API argument | AWS `ClientToken`, Stripe idempotency keys |
| Library | Exponential backoff + jitter with retry budget | AWS SDK adaptive mode, resilience4j, Polly |
| Runtime check | Server-side idempotent session with ACID token recording | AWS EC2 `RunInstances`, Kafka transactional producer |
| Runtime check | Adaptive concurrency limits (AIMD, Little's Law) | Envoy `adaptive_concurrency`, Netflix concurrency-limits |
| Runtime check | Circuit breakers | Hystrix, resilience4j, Envoy outlier detection |
| Runtime check | Retry budget shared across call graph | Envoy retry budgets, gRPC retry-throttling |

### Costs

**Idempotency as required plumbing.** AWS's recommended pattern requires that every write endpoint accept a caller-provided token, and that the server record the token and mutation atomically under ACID — "all or nothing" ([AWS Builders' Library — Idempotent APIs](https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs/)). The cost is a new schema (idempotency-key table), a new expiry policy, and a new client discipline (generate and thread the token). Client libraries frequently omit this; agents omit it more consistently.

**Jitter and backoff as convention, not enforcement.** AWS's own simulation showed full jitter reduced call counts by more than half compared to un-jittered exponential backoff with 100 contending clients — but "none of the approaches fundamentally changes the N² nature of the work" ([AWS Architecture Blog](https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/)). Because retry logic sits in application code, it cannot be enforced by the language; the retry policy is a per-caller choice, and agents pick immediate-retry by default.

**Circuit breakers as valid-program rejection.** A tripped circuit breaker rejects requests that would have succeeded, on the bet that the shed load will let the dependency recover. This is a legitimate program made harder to express: the caller must handle a synthetic `CircuitOpen` error even when the dependency is healthy for that specific request.

## 6. Persistence

### Concrete defects

**fsync error semantics.** PostgreSQL assumed that a successful `fsync()` meant all data since the last `fsync()` was on disk. Linux before 4.13 marked buffers clean after write errors, so a retrying `fsync()` could return success while the modified buffer had been discarded; on Linux 4.13–4.15, `fsync()` reported only errors from write-backs that occurred after `open()`, so the checkpointer's file-descriptor recycling pattern could hide errors ([LWN — Craig Ringer](https://lwn.net/Articles/752063/), [PostgreSQL wiki](https://wiki.postgresql.org/wiki/Fsync_Errors)). The result was silent database corruption. The same class of bug affected `dpkg`. macOS/Darwin, NetBSD, and OpenBSD invalidate buffers on error, so future `fsync()` calls "may return success despite data loss" ([PostgreSQL wiki](https://wiki.postgresql.org/wiki/Fsync_Errors)).

**N+1 queries in agent code.** Bouzenia et al. classify "Data and Type Mismatch" (17.6%) and "Data & Validation Errors" (20.0%) as the dominant root causes in agentic AI repositories, with N+1 patterns as a recurring performance defect ([Bouzenia et al., arXiv:2603.06847](https://arxiv.org/html/2603.06847v1)). Concrete example patterns for agents: emitting a loop that calls `Model.get()` per iteration instead of a single `select_related` / `prefetch_related`.

**Missing commit / transaction boundary errors.** Ouyang et al. document undefined-symbol and boundary-condition defects at 0.6%–4% depending on model/benchmark ([Ouyang et al., arXiv:2407.06153](https://arxiv.org/html/2407.06153v2)). Community-reported patterns include `BEGIN; ... /* early return without COMMIT */` and firing events before the enclosing transaction commits, producing observers that see uncommitted state.

**Convergent write bursts.** Cockroach Labs' benchmark showed PostgreSQL degrading to 42 ops/sec at 10,000 concurrent agents versus 129 ops/sec on CockroachDB, driven by ten sub-agents completing a travel-booking transaction at nearly the same moment and converging on shared state ([Cockroach Labs](https://www.cockroachlabs.com/blog/agentic-ai-thundering-herd-problem/)). This is not a bug in any single line of generated code; it is a systemic pattern that emerges when agents fan out.

### Prevention

| Approach | Mechanism | Named systems |
|---|---|---|
| Language / library | Typed transaction scope closes over side effects | Haskell STM, Rust `sqlx::Transaction` |
| Language / library | Durable execution / event sourcing | Temporal, Restate, DBOS |
| Static analysis | Missing-commit linters | SQLFluff, DBt tests, custom Semgrep rules |
| Runtime check | ORM eager-loading warnings | Rails Bullet, Django `nplusone`, Sentry N+1 detection |
| Runtime check | `fsync` verification harness | PostgreSQL's `initdb --wal-sync-method`, ALICE tester |
| Runtime check | Structured writeahead log with error surfacing | modern PostgreSQL, MySQL InnoDB, FoundationDB |

### Costs

**Durable execution's semantic surcharge.** Temporal, Restate, and DBOS re-frame persistent operations as replayable workflows, which forces every side-effecting action into an activity boundary and every state variable into a serializable form. Temporal's own field notes cite "Seven Failures" that agents and humans hit in production, most centered on non-determinism inside workflow code — a valid Python or TypeScript program becomes an invalid Temporal workflow because it reads system time or generates a random UUID inline ([Antigravity Lab field notes](https://antigravitylab.net/en/articles/integrations/antigravity-temporal-durable-workflow-field-notes)).

**ORM N+1 warnings as noise vs. signal.** Rails Bullet and Django's `nplusone` flag every unfetched association, which produces false positives for legitimately batched or one-off queries. Practitioners routinely disable these tools in tests because the noise burden exceeds the detection value; the mitigation is often to make the linter opt-in per model, which reintroduces the "developer must remember" problem the tool was meant to solve ([Django `nplusone` docs](https://github.com/jmcarp/nplusone)).

**fsync verification harness cost.** The ALICE tool and PostgreSQL's WAL-sync method testing require crash-injection harnesses that are expensive to run in CI and difficult to reproduce; the PostgreSQL fsync-errors mitigation ultimately shipped as a change to how the server treats `fsync` failure — a full PANIC restart rather than an attempt to retry ([PostgreSQL wiki](https://wiki.postgresql.org/wiki/Fsync_Errors)). The valid-program cost is that the server now crashes on transient I/O errors that a more forgiving runtime might survive.

**STM and typed transactions.** Haskell's `STM` composes transactions safely but forbids I/O inside them; a valid program that would inline a log write inside a transaction must refactor to defer the I/O post-commit, which is nontrivial for agent-authored code that has no strong prior for "inside a transaction is a special world."

## Cross-Cutting Comparison

The following table condenses the six categories along the four prevention axes and the three cost axes.

| Category | Language rule | Library / recipe | Static analysis | Runtime check | Valid programs harder | False positives | Repair-cycle cost |
|---|---|---|---|---|---|---|---|
| Error handling | `Result<T,E>`, checked exceptions | `anyhow`, error wrapping | `unwrap_used`, `unused_results` | Supervision, event ring | Shared-error-across-boundaries idioms | Rust `unused_results` over-fires; propagated `must_use` blocks legitimate returns | `unwrap` escapes bypass all layers; supervised restart adds recovery cycle |
| Capabilities | Reference caps (Pony), platform effects (Roc) | Deno flags, WASI imports | Taint tracking (CodeQL) | Sandboxed process, CHERI | Cyclic mutable graphs (Pony); ambient auth (Deno) | Deno prompts on legitimate reads; `-A` escape absorbs friction | CHERI recompilation cost; Deno flag churn per script |
| Concurrency | Ownership + Send/Sync, actors | Structured scopes | RacerD, ThreadSanitizer | Race detector, deterministic scheduler | Doubly-linked lists, self-referential graphs in Rust; single-thread dispatch invariants in Kotlin | RacerD trades false positives for tractable analysis; borrow checker rejects sound programs | Cancel-safety review pass (Oxide); ~4h Facebook News Feed migration effort per class |
| Deadlines | Deadline-in-signature (proposed) | `context.Context`, `StructuredTaskScope` | Missing-timeout linters | Circuit breakers, enforced socket timeouts | Background workers must fabricate contexts | AWS: 0.1% false-timeout rate at p99.9 | Percentile recalibration per deployment |
| Retries | Idempotency-key-in-signature (proposed) | AWS SDK adaptive, resilience4j | Retry-storm detectors | Retry budgets, adaptive concurrency, circuit breakers | Fire-and-forget one-shot writes need token infra | Circuit breakers reject healthy-for-this-request calls; retry budgets drop legitimate retries | Idempotency table + expiry infra; per-endpoint retry-classification review |
| Persistence | STM, typed transaction scope | Durable execution (Temporal), ORM eager-loading APIs | Missing-commit linters, N+1 detectors | Bullet, `nplusone`, PANIC-on-fsync-error | Inline I/O inside transactions; non-deterministic code in workflows | N+1 detectors over-fire and get disabled | Workflow refactor per non-determinism source; fsync PANIC crashes on transient errors |

## Implications for Language-and-Runtime Design

Three observations follow from the evidence that are especially load-bearing for Mo-style designs — capability-scoped languages with agent-facing runtimes and audited platform bricks:

**Language rules that cannot be locally bypassed force the failure into a different mode, but they do not eliminate it.** Rust's `Result` eliminates silent error propagation but incentivizes `unwrap()`; Cloudflare's November 2025 outage is the compressed version of that tradeoff ([Zenn](https://zenn.dev/dokusy/articles/666387f63061de?locale=en)). Java's `throws` eliminated undeclared exceptions but pushed the ecosystem toward catch-and-ignore. Pony's reference capabilities eliminated data races but the syntax is heavy enough that the language has never crossed a mainstream adoption threshold. This pattern suggests that language rules pay off when the failure mode is expensive enough that the escape hatch is visible and reviewable — `unwrap()` in a code review, a `-A` in a Deno task, a `throws Exception` catch-all.

**Static analysis pays off when its false-positive rate is calibrated against a specific migration.** RacerD's 2,500 fixed issues at Facebook and the sub-3 false negatives in a year were possible because Facebook explicitly designed for the Litho migration and accepted deliberate under-reporting on some patterns to maintain signal ([Sadowski et al.](https://ilyasergey.net/papers/racerd-oopsla18-preprint.pdf)). Generic static analysis with no migration context — the default when a language ships lints out of the box — tends to produce noise that gets suppressed. The design lesson is that lints should be shipped with a target migration, not as ambient rules.

**Runtime enforcement is the most robust layer for the failure modes agents fail at.** Timeouts, retry budgets, idempotency, cascading-failure protection, N+1 detection, fsync-error surfacing — all six categories show that the layer that most reliably catches the defect in production is a runtime check that operates without requiring the code to be correct. Supervision restarts a process regardless of whether the error was handled; a permission broker denies a syscall regardless of whether the caller respected the flag; a retry budget throttles retries regardless of what the client library says; an idempotent session ignores duplicate writes regardless of what the client sent. The Mo design bet — a queryable runtime, `platform.runtime`-mediated authority, and structured event rings — is well-aligned with this evidence.

The cost of the runtime layer is that it must be present at every deployment surface and cannot be a compile-time-only construct; a Mo binary that leaves the runtime out is not just less-inspectable, it is less-safe by the specific measures documented here. That is the design constraint the six failure modes converge on.

# Mo application budget readiness review

Own read-only Astra low worker in Herdr w4:p27; source d82c30d5. Session 01a0b8b2-1516-79f0-a4fd-650da506fb25. No implementation or test execution.

Recommend a separate **`application-workspace-v1` profile**, leaving coding-fixture and provider behavior unchanged. HEAD matches `d82c30d5f64de1b508fa2bb3a742cf0b3a5ef4f4`. This is source-readiness evidence only; no edits or execution checks performed.

All references below are under `examples/programs/agent/`.

**Public shape and budgets**

- Add an explicit versioned CLI entry, following the existing opt-in dispatch seam at `main.mo:184–186` and loopback configuration at `main.mo:202–217`. Inputs: operator Book root, scripted-model endpoint, application endpoint, opaque workspace identity, goal. Fixed profile policy; no live-provider configuration.
- Keep the existing `Budget` and `Order` shapes (`record.mo:16–32`). Use validated budget values **16 steps, 4096 tokens, 900000 wall_ms, zero retries, 2000 tool_ms**, retaining the fixture’s step/token limits initially.
- Keep **candidate execution ≤120000 ms** separately from **command RPC/collection waiting**. A **300000 ms configured command wait** is a reasonable initial policy allowance for the supplied ~234.1-second wait sum plus 35-second creation allowance. Tighten it by remaining application time; it is not an unconditional completion guarantee.
- Preserve the exact grants: `list_files`, `read_file`, `search`, `write_file`, `exact_edit`, `command` (`record.mo:64–65`). Model and file RPC waits remain short; only command dispatch receives the longer wait.

**No widening of shared validation or serialized records is necessary.** `900000` already fits `wall_ms?`; `tool_ms` stays 2000 (`record.mo:80–99`). Construct the trusted application Order through its own validated factory, as the fixture already directly constructs one (`coding-fixture.mo:59–60`): legacy `order()` rejects the two extra tool names (`record.mo:129–160`). Keep profile policy outside `Budget`/`Order`, whose budget is directly JSON-encoded into the log (`transcript.mo:43–46`). Tradeoff: record the profile identity and extended policy in application evidence/report metadata, since the unchanged legacy header cannot describe them fully.

**Minimal implementation boundary**

1. **New application profile module:** owns configuration, budget factory, Book lifecycle and application watcher. Book remains in the operator root, with the required placeholder `work/` directory; creation checks that folder (`filing.mo:109–113`).
2. **New application adapter module:** supplies all six remote operations and separate execution/wait limits. Do not repurpose `command-adapter.mo`: its deadline currently supplies both HTTP waiting and wire `timeout_ms`, and its route is fixture-specific (`command-adapter.mo:16–29`).
3. **Shared `run.mo`: unavoidable if reusing Run.** Add an explicit, mutually exclusive application configuration before Begin; select application dispatch and command waiting there. Currently every model/tool call uses the same `call_ms` (`run.mo:138–139,162–170`; `steps.mo:147–148`). Application mode must also retain fixture-style step/context checks and single-attempt recording (`run.mo:130–134,155–157,179–194`).
4. **`main.mo`:** add the explicit CLI branch.
5. **Reporting:** minimally add a versioned report entry point while preserving existing `report` output. Its schema is currently hardcoded (`report.mo:8–13`); retain its sequence, completeness and synthetic/unknown usage rules (`report.mo:16–53`).

**Tools/Registry can remain unchanged** if the new launcher starts Run directly with no local writer and an operator-owned placeholder read scope. Application dispatch must never fall through to local Tools. Reusing `Registry.started_run` instead would instantiate a local Writer for these grants (`registry.mo:62–67`); avoiding that would require a separate registry constructor. Existing Tools dispatch is local filesystem execution (`tools.mo:71–95`).

**Deadline, cancellation and reporting obligations**

- Establish one outer **900-second application deadline** and reserve reporting time *inside* it. Using a full 900-second work deadline plus 15 seconds would instead create a 915-second envelope.
- Preserve the **shared, diminishing 15000 ms recording/report allowance**; do not reset it per call or enlarge it to cover candidate collection (`run.mo:35,73–99,118–120`).
- Replace the application watcher’s inherited **2,250 iterations × 20 ms** limit with deadline-driven waiting; leave the fixture watcher unchanged (`coding-fixture.mo:78–94`).
- Cancellation can settle Book before an in-flight call is recorded. Wait for **terminal Book state AND `Run.Stopped`**, then obtain ReportDeadline and reread record/transcript (`coding-fixture.mo:84–85,99–114`). Preserve late-step recording and first-terminal-wins replay (`transcript.mo:65–69,108–114`).
- Cancellation does not interrupt Run’s synchronous command ask. The longer wait therefore increases possible stop latency. `Run.Stopped` establishes Mo dispatch completion, **not external subprocess cleanup**.
- Book’s separate 120-second lost-run grace is not the application ceiling (`filing.mo:133`; `shelf.mo:115–119`).

Preserve existing budget-bound tests (`record.mo:232–239`), begin/stopped invariants (`run.mo:322–339`), legacy budget/cancel tests (`runs.mo:106,130,153,249`), and fixture cancellation/report stability and grace controls (`tests/coding-fixture-v1/boundaries.mo:24–57,197–239`).

Five focused new acceptance controls:

1. Real candidate configured for 120 seconds plus collection completes without inheriting the 2-second tool wait.
2. Command execution and collection limits remain distinct; model/file waits remain short; zero retries.
3. Near-expiry dispatch is capped or refused, with reporting reserve retained inside the outer deadline.
4. Cancellation during collection produces no subsequent dispatch, waits for Stopped, and leaves the reported log unchanged.
5. All six grants route exclusively to the application workspace; legacy budget rejection, fixture 2s/30s/45s behavior and report schema remain unchanged.

A separate application Run would avoid shared Run edits, but duplicate its ordering and cancellation machinery. The narrow explicit mode above is the smaller maintenance boundary.

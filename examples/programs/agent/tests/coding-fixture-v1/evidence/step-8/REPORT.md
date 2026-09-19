# Harness step 8 report: Mo agent findings M1–M8

Worker: Claude Opus 5, worktree `harness/step-8-agent`, base `e87879a4`. Brief:
`mo-wiki/plans/mo-harness-step-8-agent.md`. Findings:
`audit/evidence/2026-09-19/fable-overnight-review/README.md`.

This is the final report given to the lead in the worker pane, verbatim, with
the details it left out added in marked sections. The raw evidence it cites is
in `examples/programs/agent/tests/coding-fixture-v1/step-8/` (committed in
`da39c26c`); this file sits in `evidence/step-8/` because the lead asked for it
here.

Parts 1–5 are done and committed on `harness/step-8-agent`. **Part 6 (M8) is
stopped as the brief says to:** one steps rule can't serve both the legacy
goldens and the fixture, so I made no M8 code change. There are also two places
where the brief ran into the code, described below. Nothing was pushed, and I
didn't touch the full `zig build test`, the machine, Docker or `/opt`.

**Commits** (base `e87879a4`):

- `79da89c9`: M1, M2, M5, M6
- `720ce165`: M4
- `db477e5a`: M3
- `d0be084f`: M7
- `da39c26c`: evidence, the README, and one `verify.py` line

## Needs your decision

**1. M8: the two paths count "steps" differently.**

- The legacy path counts model calls (`steps.mo:123,134`, `taken`). The fixture
  and application paths count recorded steps (`run.mo:155,181`, `n`).
- Both readings are written down: `agent.expected:48` expects r_5 with
  `budget.steps: 2` to end `steps_taken: 2, tokens_used: 21`.
  `mo-wiki/plans/mo-coding-fixture-v1.md:105` says "at most 16 recorded steps".
- I ran each single rule against the controls in a temporary copy:
  - **Recorded steps for every run:** the legacy check exits 0, but the golden
    differs at lines 48 and 62 (r_5 becomes `steps_taken: 1, tokens_used: 12`).
  - **Model calls for every run:** the fixture's `steps` case fails (10 model
    calls, exit 0 done instead of exit 3 over budget). `tokens`, `context` and
    `repair` still pass.
- **Token bound, if you want it settled separately:** my recommendation is the
  legacy reading. A tool may run when tokens equal the budget (`uses?`: `<=`),
  and the next model ask is refused (`asks?`: `<`). The tool costs no tokens,
  and `call_for` already requires `tokens_used <= tokens`. The profiled `>=`
  check in `acting` stops one tool early. No current control sits exactly on the
  bound: removing that check still passes the fixture's `tokens` case. I left it
  unchanged.

**2. M1: the corpus requires every process test to hold under faults, which
rules out a fully strict test.**

- `corpus.zig:714-715` requires every process test to hold under 100 seeds with
  5% faults. A strict version (exact outcome per mode, error arm failing on any
  error) passed the fixed schedule, but under `--sim 100` it reported "0 held
  under faults, 1 passed only without faults". The corpus rejects that.
- Across 100 fault seeds, faults reach the test's own setup and produce about 75
  distinct outcomes (`step-8/part1-fault-outcomes.txt`).
- **What I did instead:**
  - Every boundary run now holds a real `Writer` on its folder with no grant, so
    "file unedited" has to be earned by the grant rule rather than being
    guaranteed by construction.
  - Each mode asserts, unguarded, what held on every seed. A run that ends Done
    must have taken the exact scheduled path.
  - The error arm accepts only nine named setup/observation errors, never the
    run's own failures.
- Result: "1 held under faults, 0 passed only without faults".
- **Limitation:** Done-only checks don't fire in faulted runs.

## Parts 1–5

- **M1, M2, mutants.** The M2 bound (`grace_ms` 0..15000) is removed. Six
  mutants of `run.mo` were run against the new test and the pre-rewrite test:

  | Mutant                                  | New test                                      | Old test             |
  | --------------------------------------- | --------------------------------------------- | -------------------- |
  | none                                    | exit 0, 3 passed                              | exit 0, 2 passed     |
  | grant check removed                     | **exit 1**, `assert seen.unchanged failed`    | **exit 0 (missed)**  |
  | cancel's Stop ignored                   | exit 1                                        | exit 1 (calls 2 > 1) |
  | deadline taken from the report deadline | exit 1                                        | exit 1               |
  | recording failure goes on               | exit 1                                        | exit 1               |
  | grace never spent                       | exit 1                                        | exit 1 (grace 15000) |
  | run never stops                         | **exit 1**, `assert setup_fault?(why) failed` | **exit 0 (missed)**  |

  M1's "cannot fail" overstates it: the old test's unguarded
  `calls <= call_limit` caught four of the six.

- **M5, M6.** `edit-empty` and `command-failure` are in `CASES`, so the matrix
  is now 24 cases per runtime, not 22. The brief says "four edit refusals"; I
  asserted the exact reason for all six (missing, duplicate, overlap, empty,
  original-size, path). With a deliberately wrong reason the case fails (exit
  1).
- **M4.** The failing test was a scripted endpoint answering at 5 ms against a 5
  ms deadline. Against the old adapter:
  `left = "{"state": "timeout", "error_code": "deadline", "execution": "unknown"}"`,
  exit 1. After removing `command-adapter.mo:25`: 3 passed, exit 0, and under
  `--sim 100` "2 held under faults".
- **M3.** Both tests failed first:
  - the slack test: `left = 0, right = 10000`;
  - the watch test: it gave up with 15,000 ms of its deadline left, because the
    poll stopped after 2,250 looks whatever its deadline.

  The fix:
  - The deadline is now derived: wall budget + the run's 15 s report grace + 10
    s = 55 s.
  - Begin takes the order's wall budget.
  - The watch ends on its deadline, not a count.

  After the fix: 2 passed, exit 0; under `--sim 100` "1 held under faults".

- **M7.** A refusal with `invalid_utf8` (the application workspace's code)
  replaces the `or ""` fallback. There's no test: a valid UTF-8 match can only
  start and end on character boundaries, so the branch is unreachable from
  String inputs.

## Numbers (every process under `guard.py`)

- **`verify.py`:** exit 0. All fmt/write rows exit 0, the native build exit 0,
  and every native test run passed. Two examples: boundaries "3 passed, 0
  failed, 0 skipped"; record "14 passed".
- **Legacy CLI goldens:** 12 of 12 (6 interpreter + 6 compiled), `legacy.py`
  exit 0.
- **Coding-fixture matrix:**
  - compiled: 24/24, `run.py` exit 0;
  - interpreter: 24/24, exit 0 on the second attempt. The first attempt stopped
    at case 20 (`command-transport`) when `run.py`'s `invoke` got
    `PermissionError` from `os.killpg` after the child had exited. That's a
    harness flake: it only suppresses `ProcessLookupError`. I didn't change
    `run.py` for it.
- **Application workspace:** `controls.py` 8 of 8 rows passed, exit 0;
  `matrix.py interpreter` 33 of 33, exit 0. I moved both output files out of
  that suite's `evidence/` into mine.
- **Not run:** the application matrix native, `drivers.py`, `real_bridge.py`,
  and the full `zig build test`.

**Mo source lines, before → after:**

| File                 | Lines     |
| -------------------- | --------- |
| `boundaries.mo`      | 242 → 292 |
| `coding-fixture.mo`  | 123 → 161 |
| `run.mo`             | 387 → 392 |
| `exact-edit.mo`      | 53 → 59   |
| `command-adapter.mo` | 133 → 134 |
| `main.mo`            | 501 → 501 |

## Other decisions the brief didn't cover

- **Evidence location.** It's in `tests/coding-fixture-v1/step-8/` (315 KB, no
  `.mo` files; mutant definitions kept as `.py.txt`). The raw matrices were
  trimmed to fit the 1 MiB limit.
- **Recording mode asserts the record stays Running.** The book acknowledged
  nothing, so it wrote neither the step nor the end. That's the observed ground
  truth, not an intended end state.
- **`coding-fixture.mo` is now a process-test file.** I added it to
  `verify.py`'s SIM list; without that, `verify.py` rewrites its verified line
  without the simulation.
- **Regenerated verified lines outside my files.** The records for
  `tests/application-workspace-v1/boundaries.mo` and `driver.mo` in `.mo.ids`
  were regenerated. Their source files came out byte-identical.
- **README.** Its 45-second line now describes the derived 55-second deadline;
  the historical 22/22 lines are unchanged.

`step-8/README.md` indexes the evidence and explains the fault-tolerance choice.

---

## Added: why part 6 (M8, one budget rule) stopped, in full

### What the brief asked

Fold the flag-gated budget checks in `run.mo` (`profiled`, formerly `fixture`)
into `asks?`/`uses?`/`budget_end` so there is one budget rule, resolve the
off-by-one at the token bound, and keep the 12 legacy goldens, the
coding-fixture matrices and the application controls passing. "If one budget
rule cannot serve legacy, fixture and application runs, stop and tell the lead
with the source evidence; do not invent a fourth mode."

### The checks as they stand (at `d0be084f`)

Shared by every run (`steps.mo`):

- `asks?` (`steps.mo:121-124`): asks the model only while
  `run.taken < budget.steps and run.tokens < budget.tokens`. `taken` counts
  model calls only (`advanced`, `steps.mo:113-116`).
- `uses?` (`steps.mo:127-129`): uses the tool while
  `run.tokens <= budget.tokens`.
- `model_outcome` (`steps.mo:206`): over budget "tokens" once
  `run.tokens > budget.tokens`.
- `budget_end` (`steps.mo:132-136`): "wall_ms" if the deadline is spent, "steps"
  if `run.taken >= budget.steps`, else "tokens".

Only for profiled runs (fixture or application), in `run.mo`:

- `thinking`: `if fixture and run.n >= setup.order.budget.steps` → over budget
  "steps". `n` is the number of the last recorded step, model and tool steps
  alike.
- `thinking`: `if fixture and body(request_of(setup, run)).byte_size > 65_536` →
  over budget "context_bytes".
- `acting`:
  `if profiled and (run.n >= budget.steps or run.tokens >= budget.tokens)` →
  over budget "steps" or "tokens".

So there are two differences between the paths. One is the off-by-one at the
token bound (`<=` against `>=`). The other is what "steps" counts: model calls
(`taken`) for legacy, recorded steps (`n`) for profiled runs.

### What each contract says "steps" means

- **Legacy, model calls.** `agent.expected:48` (the `check` golden, run by
  `legacy.py` in both runtimes): run r_5, created by
  `ada POST /runs {"goal": "two steps at most", ..., "budget": {"steps": 2}}`,
  must end
  `{"id": "r_5", "state": "over_budget", ..., "steps_taken": 2, "tokens_used": 21, ..., "error": "steps"}`,
  and the same record appears at `agent.expected:62`. Two model calls (12 + 9
  tokens) and their two tool steps are four recorded steps, so budget 2 counts
  model calls.
- **Fixture, recorded steps.** `mo-wiki/plans/mo-coding-fixture-v1.md:105`: "For
  fixture runs use at most 16 recorded steps". The fixture README (line 45):
  "The fixture caps recorded steps at 16". `run.py`'s `steps` case scripts nine
  `read_file` replies against budget 16 and asserts
  `len(events) == 17 and len(models) == 8` with terminal `over_budget`, exit 3.
  That is 8 model and 8 tool steps.
- **Application.** It uses the same profiled checks and a 16-step profile
  (`application.mo:57`, `matrix.py:239`). I found no application case that ends
  on the steps bound, so the application runs don't settle the question either
  way.

### What I tried

In temporary program roots outside `examples/` (verified lines stripped, the
worktree untouched), I built both one-rule variants with
`step-8/part6-variant.sh.txt`:

1. **One rule counting recorded steps for every run** (`asks?` and `budget_end`
   use `run.n` instead of `run.taken`). Ran the legacy `check` command
   (`mo run main.mo -- check data/demo data/script.txt data/runs.txt`) on a
   fresh copy of `data/`: exit 0, but the output differs from `agent.expected`
   at lines 48 and 62: r_5 becomes `"steps_taken": 1, "tokens_used": 12`.
   Evidence: `step-8/part6-recorded-steps-vs-legacy.diff`. **The legacy golden
   fails.**
2. **One rule counting model calls for every run** (both profiled steps checks
   removed from `run.mo`). Ran the fixture matrix cases through a copy of
   `run.py` pointed at the variant: `steps` failed (model_calls 10, exit 0 done
   instead of exit 3 over_budget); `tokens` (exit 3), `context` (exit 3) and
   `repair` (exit 0) passed. Evidence:
   `step-8/part6-model-calls-vs-fixture.txt`. **The fixture matrix fails.**

Neither single steps rule keeps all the controls the brief requires. Any rule
that serves both would need a per-run choice of what "steps" counts, which is
the "fourth mode" the brief rules out. So I stopped part 6 and made no code
change: the flag-gated checks, the context bound and the token bound are as they
were.

### Decision needed from the lead

1. **What the steps budget counts.** Choose one:
   - (a) **Recorded steps everywhere.** The legacy `check` golden changes at
     `agent.expected:48,62` (r_5: 1 step taken, 12 tokens), and so does the
     steps budget's meaning in the HTTP API.
   - (b) **Model calls everywhere.** The fixture contract changes: the plan's
     "16 recorded steps", the README, and `run.py`'s `steps` expectations (8
     model calls become 16).
   - (c) **Keep two readings, deliberately.** For example, a budget field or the
     order stating what `steps` counts. That is a design change you'd need to
     authorize, and I don't want to invent it.

   With (a) or (b) decided, the fold is small: the profiled checks in `thinking`
   and `acting` go into `asks?`/`budget_end`.

2. **The token bound**, whether or not (1) is settled. I recommend the legacy
   reading everywhere: a tool may run when tokens equal the budget (`uses?`:
   `<=`), and the next model ask is refused (`asks?`: `<`). A budget is a
   ceiling a run may reach; the tool costs no tokens; and `call_for` already
   requires `tokens_used <= tokens`. Removing the profiled `>=` check changes no
   current control: the fixture's `tokens` case (4,097 > 4,096) still ends over
   budget through `model_outcome`, as variant 2 showed. Only a run landing
   exactly on the budget would behave differently.
3. **The 64 KiB context bound** (`context_bytes`) is fixture/application-only.
   It could fold into `asks?`/`budget_end` for every run without changing a
   legacy golden (legacy requests are far smaller), but I left it with the steps
   question so that one change settles all three.

## Added: details the pane report left out

- **Mutant definitions.** They are in `step-8/part1-mutate.py.txt`, each an
  exact one-site string replacement in `run.mo`:
  - grant: the `!call.granted.contains?` refusal removed from `fixture_used`;
  - cancel: `Ok(Stop(_))` in `recorded_profile` goes on instead of stopping;
  - deadline: Begin takes `state.report_by or reply_by`;
  - recording: a failed acknowledgement goes on;
  - grace: `grace_left` never spends;
  - never-stops: `closing` never sends `Close`.

  Full outputs are in `step-8/part1-mutants.txt`, run against the final code at
  `d0be084f`.

- **The M3 test was vacuous twice before it failed properly.** First, a 45 s
  watch deadline equalled the 2,250 × 20 ms poll cap. Second, the run was never
  created, because the `work` folder was missing and the `if made is Ok(...)`
  guard was false. It now uses a 60 s deadline and makes `work`; the RED output
  is `step-8/part4-m3-red.txt`.
- **The M4 test tolerates faults on the listen and the send.** It accepts only
  the adapter's transport failures, never the deadline misreport, so it holds
  under `--sim 100`.
- **The last focused run on the committed tree**, each `mo test --sim 100`, all
  exit 0 with no stale verified line:
  - coding-fixture `boundaries.mo`: 3 passed ("2 held under faults");
  - `run.mo`: 2 passed;
  - `steps.mo`: 7;
  - `command-adapter.mo`: 0;
  - `exact-edit.mo`: 0;
  - `main.mo`: 5;
  - `coding-fixture.mo`: 2 ("1 held under faults");
  - application-workspace `boundaries.mo`: 1;
  - `application.mo`: 0.
- **Ownership note.** This report is the only file under
  `tests/coding-fixture-v1/evidence/`, which the brief left outside my write
  scope; it is here because the lead asked for it here.

---

## Part 6 resumed: the lead's decision carried out (commit `109e8685`)

The lead decided:

- **(a)** "steps" keeps its two written meanings, chosen once as one explicit value;
- **(b)** the token bound takes the legacy reading for every run, with a control
  sitting exactly on the bound in both counting modes.

Both are done. Book and Record serialization are untouched: the value lives in the
Run's state, not in Order, Budget or Record.

### What changed

- **`steps.mo`:**
  - A new `enum Counting` with `ModelCalls` and `RecordedSteps`.
  - `asks?`, `uses?` and `budget_end` take it, and one helper `fits?` says whether
    one more step of a kind fits the steps budget. Under `ModelCalls` only a model
    step counts (`taken`); under `RecordedSteps` every step does (`n`).
  - `uses?` keeps `tokens <= budget` and `asks?` keeps `tokens < budget` for every
    run.
  - `budget_end` names the wall first, then steps as the run counts them, then
    tokens.
- **`run.mo`:**
  - The Run's state holds `counting: Counting = ModelCalls`. `ConfigureFixture` and
    `ConfigureApplication` set it to `RecordedSteps`, the one place a run is
    configured.
  - The steps gate in `thinking` and the duplicate steps-and-tokens gate in
    `acting` are gone. This also removes the early `tokens >= budget` check.
  - `thinking` now takes the same `Turn` as `acting`. Adding the value pushed it to
    seven parameters, past Mo's limit of six (MO0303).
- **What `profiled` still does in `run.mo`:** it now does only two things.
  - It chooses the step's start time (`asked`/`using`). That is timing, not budget.
  - It gates the 64 KiB `context_bytes` check. That was open item 3, which the
    decision did not cover, so it stays as it was, the one budget check left
    outside `steps.mo`.

  One ordering edge moves as a result: a profiled run past both its steps and its
  context bound now ends `context_bytes` instead of `steps`. No golden or matrix
  case reaches both at once.

### The control on the token bound

**The test:**
`boundaries.mo` "a model call that spends exactly the token budget still has its
tool used, and the next ask is refused". Budget 17 tokens; the one model reply
names `read_file` and spends 17. It runs twice, configured as a fixture run
(`RecordedSteps`) and as a plain run (`ModelCalls`). An end on the token bound must
have exactly 2 steps: the model step and an unrefused `read_file` tool step. There
is at most one model call and never Done.

**Against the old code**
(the committed `run.mo` and `steps.mo` put back, `m8-oldbudget.py.txt`):
- exit 1; the fixture run ended over budget before the tool step
  (`assert seen.steps.size == 2 and tools.size == 1 ... failed`);
- the plain-run mode alone passes on the old code (exit 0). Legacy already had
  this reading, so that half guards it rather than failing first.

**After the change:** 4 passed, exit 0. Under `--sim 100`:
"3 held under faults, 0 passed only without faults". The native test build also
passes it ("4 passed").

**One loosening, found by the simulator:** the first version asserted that every
over-budget end was "tokens". Under faults, seed 5698025395551875501 ended
`wall_ms` (a faulted model call running late past the wall budget). So the test
now allows `tokens` or `wall_ms`, and requires the tool step whenever the end is
"tokens".

`steps.mo` also has a new unit test covering both modes:
- after one model and one tool step (budget 2), ModelCalls may ask and
  RecordedSteps may not;
- a tool may run at n=1 in both modes, but at n=2 only under ModelCalls;
- a tool may run at exactly the token budget and not past it;
- the next ask is refused at the bound, and `budget_end` names "tokens".

It passes (8 passed).

### Why strings: unchanged

Every coding-fixture case's terminal payload, exit code and event sequence was
compared with the matrices before the change: identical in all 24 cases on both
runtimes. The budget cases still end `steps`, `tokens` and `context_bytes`.
The legacy goldens, including `agent.expected:48,62` (r_5, `"error": "steps"`,
`steps_taken: 2`), pass 12 of 12.

### Numbers (every process under `guard.py`)

- **`verify.py`:** exit 0.
  - fmt and writes: all exit 0;
  - `steps.mo` "8 passed";
  - `run.mo` "2 passed; 2 held under faults";
  - coding-fixture `boundaries.mo` "4 passed; 3 held under faults";
  - native build: exit 0;
  - `legacy.py`: 12 of 12, exit 0;
  - native tests: boundaries 4, main 5, record 14, tools 5, steps 8, run 2,
    registry 0, transcript 5 (all exit 0).

  The tree was unchanged afterwards. Evidence: `m8-verify.jsonl`.
- **Coding-fixture matrix:** interpreter 24 of 24, `run.py` exit 0; compiled 24 of
  24, exit 0. Evidence: `m8-matrix-interpreter.jsonl`, `m8-matrix-compiled.jsonl`.
- **Application workspace:**
  - `controls.py` 8 of 8, exit 0;
  - `matrix.py interpreter` 33 of 33 rows, exit 0;
  - `matrix.py native` 34 of 34 rows, exit 0.

  The output was moved out of that suite's `evidence/`: `m8-app-*.jsonl`.
- **Every verified line was regenerated** with the real `mo test --write` in
  dependency order, `--sim 100` where the line records it. All exit 0.
- **Not run:** the full `zig build test`, `drivers.py`, `real_bridge.py`.

**Mo source lines, before → after:**

| File | Lines |
|---|---|
| `steps.mo` | 365 → 417 |
| `run.mo` | 392 → 392 |
| `boundaries.mo` | 292 → 352 |

### Still open

- **Item 3, the context bound.** `context_bytes` is still checked in `run.mo` for
  profiled runs only. Moving it into `asks?`/`budget_end` for every run would
  change no current golden, but it gives plain runs a new over-budget reason, so
  it is left for the lead.

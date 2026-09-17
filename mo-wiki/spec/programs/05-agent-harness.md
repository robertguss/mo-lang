# Program 5: `agent`, an agent harness

The spec altitude of program 5 from the program menu: "is Mo good at the thing it is for?" An agent harness runs a model's loop under permissions, budgets, and retries, and records everything. Written by Claude (Fable) in session 5, night of 14 Sep 2026, after step 23. **Status:** implemented in session 6 as the agent program; the lowest completeness in measurement 1 (`plans/bodies-as-cache.md`). A worker implements it in Mo; Robert reads this page, the signatures, the contracts, the `never`s, and the `verified:` lines.

## Intent

`agent` is a service that runs agent runs: a client gives a goal, a folder, the tools the run may use, and a budget; the harness asks a model what to do next, runs the tool the model names with only the capability the run granted, feeds the result back, and stops when the model says it is done or the budget is spent. Every model call and tool call is in the transcript before the next one starts. It stresses capabilities as permissions, deadlines derived from a run's budget (`reply_by`), retries, and the runtime surface as the operator's view.

## The model

There is no TLS brick yet, so the model is any HTTP server on plain HTTP at `host:port` that answers `POST /complete`. The harness sends `{"goal", "tools": [names], "transcript": [steps so far]}` and the model answers either `{"tool": "read_file", "args": {...}, "tokens": n}` or `{"done": "the answer", "tokens": n}`. A model reply that is not JSON, names a tool the run did not grant, or gives arguments of the wrong shape is a model error; the harness retries the call up to the run's `retries` (immediate, since Mo has no timer; a delay between retries is a gap if the worker wants one) and then fails the run. `agent mock <script>` is a model the program ships: a script file of replies, one JSON object a line, played in order to every run, with `{"slow_ms": n}` and `{"garbage": true}` lines to make a reply late or malformed, so a check can exercise retries with no network.

## The package story

One new recipe, `Recipes.ModelClient` in `examples/recipes/model-client.mo`, written by the worker first: `complete(http: Http, model: Model, request: Request, retries: UInt32, by: Deadline) : Result(Reply, ModelError)`, the retrying call, whose waiting signature takes a `Deadline` as the decision log now asks of recipes; its `never`s (a reply is never used after the deadline; the call is never made more than `retries + 1` times) and tests on `Http.fixture()` and `Deadline.fixture()`. Then implemented in the program and checked with `mo check --recipe`.

## Tools

A run grants tools by name; the harness holds `Fs`, `Http`, and `Clock` from `main` and hands each tool only what its row says, narrowed.

| tool | what it gets | what it does |
|---|---|---|
| `list_files` | `fs.scoped(folder).read_only` | the names under a path inside the run's folder |
| `read_file` | the same | a file's text, at most 64 KiB |
| `search` | the same | the lines under the folder matching a plain substring, at most 200 |
| `write_file` | `fs.scoped(folder)` | writes a file inside the folder; granted only when the run asks for `write` |
| `http_get` | `http`, and the run's `hosts` list | a GET to a host on the list, body at most 64 KiB |
| `now` | `clock` | the time |

A tool call that names a path outside the folder, a host off the list, or a tool the run did not grant is refused and recorded, and counts as a step; the model sees the refusal.

## Budgets

A run has `steps` (1 to 200), `tokens` (1 to 10,000,000, summed from the model's `tokens` fields), `wall_ms` (100 to 3,600,000), `retries` (0 to 10), and a per-tool `tool_ms` (100 to 60,000). The run's wall budget is one `Deadline` taken when the run starts; every model call and tool call runs on what remains of it, tightened by `tool_ms`, so no literal deadline inside a run is chosen for its call. A step that would pass `steps` or `tokens` is not taken: the run ends `over_budget`. A run past `wall_ms` ends `over_budget` at its next look.

## The API

Every request carries `authorization: Bearer <token>`, as in `notes`; the token is the run's owner and a client sees only its runs.

```
POST   /runs        {"goal", "folder", "tools": [...], "hosts": [...], "budget": {"steps", "tokens", "wall_ms", "retries", "tool_ms"}}
                    → 201 {run}
GET    /runs/{id}   → 200 {run}  |  404
GET    /runs?state=s → 200 {"runs": [...]}  by id, at most 100
GET    /runs/{id}/transcript → 200 {"steps": [ {step} ... ]}  |  404
POST   /runs/{id}/cancel → 200 {run}  |  409 when not running  |  404
GET    /health      → 200 {"running": n, "done": n, "failed": n, "over_budget": n, "cancelled": n, "uptime_ms": n}   no token
```

`{run}` is `{"id", "state", "goal", "steps_taken", "tokens_used", "result", "error", "created_at", "updated_at"}`; states are `running`, `done`, `failed`, `over_budget`, `cancelled`. `{step}` is `{"n", "kind": "model" | "tool", "name", "args", "result", "tokens", "took_ms", "refused"}`. Budget fields left out take the defaults `20`, `100000`, `60000`, `2`, `5000`. `folder` is a path under the service's folder; a folder that is not there is `400`. Validation and statuses as `notes` and `jobq` have them (`400` for a bad body, `405`, `404`, `401`).

## Durability

The transcript of a run is appended to `<dir>/runs/<id>.log`, one step a line, before the next step starts; a run is created in the same file before its first step. On restart, every run that was `running` becomes `failed` with `error: "restarted"`; its transcript is intact. The store is the store recipe, one record per run, or the log alone if the worker judges the recipe wrong for an append-only transcript, said in the report.

## Usage

```
agent serve <dir> --model host:port [--port N]     default port 7950
agent mock <script> [--port N]                     the scripted model, default port 7951
agent run <dir> --model host:port <goal> [--tools a,b] [--folder p]   one run, prints the transcript, exit 0 done, 3 failed, 4 over budget
agent client <host> <port> <token> <method> <path> [<json>]
agent check <dir> <script> <runs>   starts a mock model on the script and the service on free ports, plays the runs file through the client, prints
```

Exit 2 on a usage error, 1 if `<dir>` cannot be opened or a port cannot be bound.

## Nevers

- A tool never runs with a capability the run did not grant, and never reaches outside the run's folder or hosts.
- A run never takes a step past its `steps` or `tokens` budget, and never runs a tool past its wall budget.
- A cancelled run never runs another tool.
- A step is never taken before the one before it is in the transcript.
- A model reply is never acted on after the call's deadline.
- Two runs never share a step number or a transcript file.

## Contracts the reader expects to see

`requires` on every budget bound, the tool names, the folder, and the hosts, each with its `rejects`; `ensures` on a step that the transcript grew by one; the recipe's contracts honoured by its implementation; `invariant`s on the run process only where a message can break them, each with the `test rejects` that trips it, the rest left out and named.

## Deadlines

The report counts the `within:` literals outside tests, chosen against derived from the run's deadline; the spec expects nearly all derived, and every chosen one named with why.

## The runtime surface

`agent serve --surface PORT` is the operator's view. The report answers three questions from the surface during the measurements, with the route each used: which runs are on which step and what each is waiting on; the slowest tool of the last minute; how many model calls are in flight.

## Tests the reader expects to see

Unit tests for the JSON shapes, the routes, and each status; the recipe's tests on the implementation; a run of three steps against `Http.fixture()` playing a scripted model; a run that hits each budget (`steps`, `tokens`, `wall_ms`) and ends `over_budget` with the transcript intact; a refused tool (a path with `..`, a host off the list, an ungranted tool) recorded and shown to the model; a model that is garbage twice then right, under `retries: 2`, and garbage three times, failing; a cancel mid-run; a replay after a stop with the run `failed: restarted`; a `--sim 100` run under `--faults --until` in which no `never` trips and every run ends in a final state once faults stop; a program-level check through a real socket with `agent mock` and `agent check`.

## Measured

Runs completed per second with 32 concurrent runs of five steps each against `agent mock` on the same machine, under `mo run` and as a binary; the harness's own time per step (a step's `took_ms` less the model's and the tool's); resident memory with 1,000 concurrent runs; the `within:` count; the three surface questions; loops to green by cause; the Q16 ledger; the invariants left out; wall-clock.

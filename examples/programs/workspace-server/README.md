# Workspace server (part A)

One Mo program that speaks `mo-workspace-http-v1` and serves the five file
tools against a workspace folder it holds as a narrowed `Fs`. No machine, no
Docker, no `Exec`. `command` is refused by `main.mo`; `double.mo` scripts it
the way `test_owner.py` scripts the Python owner, so the existing local groups
can run unchanged.

## Layout

| File | Role |
|---|---|
| `wire.mo` | Request line and headers |
| `schema.mo` | JSON body, identities, args |
| `envelope.mo` | Response shape, H4 / H5 |
| `tools.mo` | The five file tools |
| `journal.mo` | Four observations + cleanup, binding hashes |
| `admission.mo` | One call, 16, 900 s lease |
| `worker.mo` | Executes against the workspace `Fs` |
| `connection.mo` | One process per connection, F1 line reads |
| `door.mo` | Lets `main` exit |
| `operator.mo` | D2: freeze / verify / close on its own port |
| `server.mo` | Start one run from a folder |
| `main.mo` | Production entry |
| `double.mo` | Local test double |
| `behaviour.py` | Line-completing client over `local.py --target` |
| `hostile.py` | Step-40 filesystem cases |
| `size.py` | The size table |
| `timings.py` | Best-of-five numbers |
| `observations.py` | Dump one call's four journal rows |
| `evidence.py` | Tee a run into `evidence/NAME/` |

## Run

From the repository root, with `mo` built in `toolchain/` and every process
under `toolchain/bench/step36/guard.py`:

```sh
python3 toolchain/bench/step36/guard.py 180 -- \
  toolchain/zig-out/bin/mo run examples/programs/workspace-server/main.mo -- RUN_FOLDER
```

`RUN_FOLDER` is laid out by the operator (`config.json`, `capability.json`,
`workspace/data`). The server writes `ready.json` (`port`, `operator_port`),
and `owner.json`.

The local groups, aimed at the double:

```sh
python3 toolchain/bench/step36/guard.py 600 -- \
  python3 -B examples/programs/workspace-server/behaviour.py \
  --groups six-tools,schema,framing,byte-bounds,identities-capability,duplicate-calls,concurrent-admission,file-refusals,deadlines,disconnect,lost-response,journal-order-bound,shutdown \
  --target "python3 toolchain/bench/step36/guard.py 180 -- toolchain/zig-out/bin/mo run examples/programs/workspace-server/double.mo --"
```

`mo build` binaries land at `zig-out/mo-build/workspace-server/` and
`zig-out/mo-build/workspace-server-double/`. See `REPORT.md` for the filed
runs, the size table, and what is unmet.

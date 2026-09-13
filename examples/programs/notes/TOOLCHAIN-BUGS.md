# Toolchain bugs found while writing notes

Recorded while writing program 4 (`mo-wiki/spec/programs/04-web-backend.md`, brief `mo-wiki/plans/program-4.md`), whose write scope was `examples/`. None is fixed here; each has a minimal reproduction, what it cost notes, and the workaround notes uses. Timings are `toolchain/zig-out/bin/mo` (ReleaseSafe, built from `da0484b`) on an Apple M-series machine with 14 cores and 96 GiB.

## 1. A started process is never freed, so a program that starts one per request runs out of memory

Every `Name.start(...)` under `mo run` keeps an OS thread and about 30 KiB (70 KiB with an `Exchange` in its start arguments) for as long as the program runs, after its last message is taken and when nothing holds its handle. A program that starts a process per request grows without bound and, somewhere between 5,000 and 20,000 processes, ends with `error: OutOfMemory` and exit 1: not a Mo crash report, and not exit 70.

```
module Main
expose Idle, Idles, main

intent "probe: processes that finish their one message and are never used again"

process Idle()
  state
    n: UInt64
  end

  message Poke

  fn update(state, message)
    case message
      Poke:
        state.n += 1
    end
  end
end

supervisor Idles
  child Idle, restart: :always
end

fn started(n: UInt64, out: Out) : UInt64
  var count = 0
  for i in 0..n
    idle = Idle.start()
    idle.send(Poke)
    count += 1
    if i % 1_000 == 0
      out.write_line("started #{i}")
      out.flush
    end
  end
  count
end

fn main(platform: Platform)
  n = (platform.args.first or "1000").to_u64 or 1000
  platform.stdout.write_line("done #{started(n, platform.stdout)}")
end
```

| `n` | exit | peak resident | wall |
|---|---|---|---|
| 2,000 | 0 | 141 MiB | 0.15 s |
| 5,000 | 0 | 348 MiB | 0.39 s |
| 20,000 | 1, `error: OutOfMemory` on stderr after `done 20000` | 574 MiB | 0.64 s |

The same shape over HTTP, an acceptor that starts `Worker.start(exchange)` for each exchange and sends it `Answer` (the shape of `examples/effects/http.mo`), served 5,000 requests from one client at 6,069 a second and then held 5,006 threads (`ps -M`) and 437 MiB resident. During a second run of 15,000 requests it stopped after about 3,000 more: every later connection was refused, the process had exited, and its `served` line was never printed.

What it costs notes: the brief's shape, a worker process per exchange, cannot serve more than a few thousand requests. Workaround: `Notes.Server.Acceptor` answers each exchange itself, in the update that accepted it, as `programs/httpd` does, so notes starts two processes in its life. Its exchanges are answered one at a time; the measurements in the final report are of that shape.

## 2. A process that starts a worker and sends it a message inside a long update deadlocks

Not a bug in the runtime, which does what chapter 3 says, but a trap the toolchain does not flag: an update that loops over `listener.accept`, starting a worker and sending it `Answer` for each exchange, never answers anyone. The sends are buffered until the update ends (an update is a transaction), so the first client waits for a reply that is not sent while the acceptor waits in `accept` for the second. `mo check` and `mo test` accept the file; under `mo run` the server sits at 0% CPU with one connection established.

Workaround: one `accept` per message, and a loop outside the process that asks for the next (`Notes.Main.accepted_awhile`), as kv does.

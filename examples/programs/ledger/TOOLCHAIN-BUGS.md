# Toolchain bugs found while writing ledger

Recorded while writing program 6 (`mo-wiki/spec/programs/06-ledger.md`, brief `mo-wiki/plans/program-6.md`), whose write scope was `examples/`. None is fixed here; each has a reproduction, what it cost the ledger, and the workaround the ledger uses. The `mo` is `toolchain/zig-out/bin/mo` (ReleaseSafe) built from `97b3f20` (step 28), on the exe.dev Linux x86_64 VM.

## 1. A process whose supervisor line says `restart: :never` is restarted after a crash

Chapter 3 says a store that does not replay its state "must say `restart: :never` and mean it", and `Ledger.Journals` says it: a journal that crashed would come back with an empty book and forget the batch it held. Under `mo run` the crashed process answers the next message from a fresh state all the same, and under `mo test` the runner restarts it until it has crashed more than three times.

Reproduction (`never-run.mo`, in a folder of its own):

```
module NeverRun
expose Crasher, Crashers, main

intent "probe: under mo run, does a process whose only supervisor line says restart: :never answer again after it crashed"

process Crasher()
  state
    count: UInt64
  end

  invariant "count stays below two"
    state.count < 2
  end

  message Bump : UInt64
  message Count : UInt64

  fn update(state, message)
    case message
      Bump:
        state.count += 2
        state.count
      Count: state.count
    end
  end
end

supervisor Crashers
  child Crasher, restart: :never
end

fn main(platform: Platform)
  crasher = Crasher.start()
  first = crasher.ask(Bump, within: 1_000.ms)
  after = crasher.ask(Count, within: 1_000.ms)
  platform.stdout.write_line("bump: #{first}, count after: #{after}")
end
```

```
$ mo run never-run.mo
bump: Error(Down), count after: Ok(0)
process crashed: never-run.mo:11:3: invariant "count stays below two" no longer holds in Crasher; state = Crasher(count: 2)
```

`Ok(0)` is a restarted `Crasher`; with `:never` the second ask should find it down. Under `mo test`, a `test rejects` that asks the same process five times after its first crash fails with "the test runner gave up: Crasher crashed more than 3 times within 5000.ms", where one trip was the point of the test.

What it cost the ledger: one loop. `Ledger.Journal`'s `test rejects` over a planted log tried `Open` again when the first ask came back without an answer, the restarted journal replayed the same log and tripped again, and the runner gave up. Workaround: those tests send `Open` again only when the journal answered `Unready` (a fault refused a read), never after an ask that got no answer. Under `mo run` nothing more is needed: a restarted journal holds `opened: false`, and every call it takes is answered 503 ("the ledger has not been opened") until `Open`, which only `main` sends, once; so a tripped invariant stops the ledger as `:never` intends, by another road.

## 2. `platform.exit` does not end a program while a delayed send is pending

`platform.exit(code)` is how a command that is done ends a program that served a listener (`jobq check`, `notes check`, `ledger check`). When any process has a `send(..., delay:)` still pending, the program prints what `main` wrote and then does not end: it waits for the delayed send, however far away, where the exit asked for the program to end now. The runtime's row says a pending delayed send "keeps `main` from finishing", which is right for a `main` that returns; an explicit exit is not a `main` that returns.

Reproduction (`exit-timer.mo`, in a folder of its own):

```
module ExitTimer
expose Alarm, Alarms, main

intent "probe: does platform.exit end a program while a delayed send an hour away is pending"

process Alarm()
  state
    rung: UInt64
  end

  message Arm(me: Handle(Alarm)) : Bool
  message Ring

  fn update(state, message)
    case message
      Arm(me):
        me.send(Ring, delay: 3_600_000.ms)
        true
      Ring:
        state.rung += 1
    end
  end
end

supervisor Alarms
  child Alarm, restart: :never
end

fn main(platform: Platform)
  alarm = Alarm.start()
  armed = alarm.ask(Arm(me: alarm), within: 1_000.ms)
  platform.stdout.write_line("armed: #{armed}")
  platform.stdout.flush
  platform.exit(0)
end
```

```
$ timeout 15 mo run exit-timer.mo; echo $?
armed: Ok(true)
124
```

What it cost the ledger: one loop, and the demo's shape. The journal sends itself an `Expire` for every live hold, so the first `ledger check` printed its whole transcript and then hung until the timeout killed it (a hold in `data/demo/ledger.log` expired in 2099). Workaround: `data/demo/ledger.log` holds no hold that is still live when the check ends (both of its holds expired before the check runs, so the journal releases them as it opens and sends no `Expire`), and the holds `data/session.txt` places live 1 second or less, so the check ends within a second of its last line. A ledger that serves is stopped by a signal, so `ledger serve` is not affected.

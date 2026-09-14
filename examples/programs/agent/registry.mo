module Agent.Registry
expose Registry, Registries, started_run

use Agent.Api{Command, Want}
use Agent.Book{Book}
use Agent.Model{Model}
use Agent.Record{Health, Order}
use Agent.Run{Run}
use Agent.Shelf{Outcome}
use Agent.Steps{Setup}
use Agent.Tools{Writer}

intent "The registry serves every request about runs: it starts a process per new run, once the book has made the run and written its first line, over the run's folder, and asks it to begin on a deadline of the order's wall budget, which the run keeps as its budget; every other request it asks of the book on what remains of its asker's deadline."

# The registry holds no run's handle, since a handle is never kept in a value: a run reports to
# the book, and a client reaches a run through the book.
process Registry(book: Handle(Book), fs: Fs, http: Http, clock: Clock, model: Model) mailbox: 4_096
  state
    started: UInt64
    unanswered: UInt64
  end

  message Serve(command: Command) : Outcome
  message Counts : Option(Health)
  message Swept : UInt64

  fn update(state, message)
    case message
      Serve(command):
        case command.want
          WantNew(order):
            outcome = created(book, command.owner, order, reply_by)
            if outcome is Made(run)
              setup = Setup(id: run.id, order: order, model: model)
              state.unanswered += missed(begun(started_run(book, fs, http, clock, setup), order))
              state.started += 1
            end
            outcome
          WantRun(_) | WantRuns(_) | WantSteps(_) | WantCancel(_):
            looked_up(book, command, reply_by)
        end
      Counts:
        case book.ask(Tally, within: reply_by)
          Ok(counts): Some(counts)
          Error(_): None
        end
      Swept:
        case book.ask(Sweep, within: reply_by)
          Ok(lost): lost
          Error(_): 0
        end
    end
  end
end

supervisor Registries(book: Handle(Book), fs: Fs, http: Http, clock: Clock, model: Model)
  child Registry(book, fs, http, clock, model), restart: :always
end

# A run's process over its folder read-only. Only a run whose order grants write_file gets a writer,
# the process over the folder writable (step 25), so a run not granted it holds no Fs that writes.
fn started_run(book: Handle(Book), fs: Fs, http: Http, clock: Clock, setup: Setup) : Handle(Run)
  folder = fs.scoped(setup.order.folder)
  if setup.order.tools.contains?("write_file")
    return Run.start(book, folder.read_only, Some(Writer.start(folder)), http, clock, setup)
  end
  Run.start(book, folder.read_only, None, http, clock, setup)
end

# The run asked to begin on its wall budget; a begin whose answer did not come still began it,
# since the message arrives.
fn begun(run: Handle(Run), order: Order) : Bool
  run.ask(Begin(me: run), within: order.budget.wall_ms.to_i64.ms) is Ok(_)
end

fn missed(answered: Bool) : UInt64
  return 0 if answered
  1
end

fn created(book: Handle(Book), owner: String, order: Order, by: Deadline) : Outcome
  case book.ask(Create(owner: owner, order: order), within: by)
    Ok(outcome): outcome
    Error(_): Unavailable(why: "the book did not answer in time")
  end
end

fn looked_up(book: Handle(Book), command: Command, by: Deadline) : Outcome
  owner = command.owner
  asked = case command.want
    WantRun(id): book.ask(Look(owner: owner, id: id), within: by)
    WantRuns(status): book.ask(Listing(owner: owner, status: status), within: by)
    WantSteps(id): book.ask(Steps(owner: owner, id: id), within: by)
    WantCancel(id): book.ask(Cancel(owner: owner, id: id), within: by)
    WantNew(_): Ok(Unavailable(why: "a new run is made by the registry"))
  end
  case asked
    Ok(outcome): outcome
    Error(_): Unavailable(why: "the book did not answer in time")
  end
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run

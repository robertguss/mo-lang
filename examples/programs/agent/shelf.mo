module Agent.Shelf
expose Entry, Shelf, Readied, Moment, Asked, Named, Placed, Ended, Ending, Outcome, Verdict, Opened, Change, Put, Settled, Swept, unready, grace, with_shelf, opened_answer, settled_run, verdict_of, ending

use Agent.Record{Order, Record, Status}
use Agent.Transcript{Step}

intent "What the book of runs holds: every run's record and the last step its log holds, the answers the book gives a client and a run, and how a run ends."

# A run on the shelf: its record, the number of the last step its log holds, and when it is
# taken as lost if it is still running.
struct Entry
  run: Record
  steps: UInt64
  lost_at: Time
end

# Every run by id, the number the next run takes, and the runs failed as restarted when the
# shelf was opened.
struct Shelf
  entries: Map(String, Entry)
  next: UInt64
  restarted: UInt64
end

# The shelf a message is served against, whether the logs were opened, and why not.
struct Readied
  shelf: Shelf
  opened: Bool
  why: String
end

# When a message is served: the book's clock, and the deadline of the ask it answers.
struct Moment
  now: Time
  by: Deadline
end

struct Asked
  owner: String
  order: Order
end

# A run as a client names it: the client's token, and the id.
struct Named
  owner: String
  id: String
end

struct Placed
  id: String
  step: Step
end

struct Ended
  id: String
  ending: Ending
end

# How a run ends: its final state, and its result or its error.
struct Ending
  status: Status
  answer: Option(String)
  why: Option(String)
end

enum Outcome
  Made(run: Record)
  Found(run: Record)
  Listed(runs: List(Record))
  Transcribed(steps: List(String))
  Stopped(run: Record)
  NotRunning(run: Record)
  NoFolder
  NoRun
  Unavailable(why: String)
end

# What a run hears once it asks for a step to be written: go on, stop since it is no longer
# running, or ask again since the step is not written.
enum Verdict
  Go
  Stop(status: Status)
  Unrecorded
end

enum Opened
  Ready(runs: UInt64, restarted: UInt64)
  Unready(why: String)
end

struct Change
  shelf: Shelf
  outcome: Outcome
end

struct Put
  shelf: Shelf
  verdict: Verdict
end

struct Settled
  shelf: Shelf
  status: Status
end

struct Swept
  shelf: Shelf
  lost: UInt64
end

fn unready() : Readied
  Readied(shelf: Shelf(entries: Map.new(), next: 1, restarted: 0), opened: false, why: "")
end

# How long past its wall budget a run still running is taken as lost: time for its last step and
# its end to reach the book, which a run asks at most ten times, 10 seconds each, before it
# stops asking.
fn grace() : Duration
  120_000.ms
end

fn with_shelf(ready: Readied, shelf: Shelf) : Readied
  var after = ready
  after.shelf = shelf
  after
end

fn opened_answer(ready: Readied) : Opened
  return Unready(why: ready.why) if !ready.opened
  Ready(runs: ready.shelf.entries.size, restarted: ready.shelf.restarted)
end

fn settled_run(run: Record, ending: Ending, now: Time) : Record
  var after = run
  after.status = ending.status
  after.answer = ending.answer
  after.why = ending.why
  after.updated_at = now
  after
end

fn verdict_of(status: Status) : Verdict
  return Go if status == Running
  Stop(status: status)
end

fn ending(status: Status, answer: Option(String), why: Option(String)) : Ending
  requires status != Running

  Ending(status: status, answer: answer, why: why)
end

test rejects "an ending that leaves the run running"
  ending(Running, None, None)
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run

# sim: --faults 20 --until 0.5
module Effects.Sim
expose Stamp, stamp, Keeper, Keeping

intent "mo test always runs on the deterministic simulator, so effectful code gives the same answer every time; under --faults a test asserts what holds while calls fail, and with --until what holds once they stop."

struct Stamp
  note: String
  at: Time
end

fn stamp(clock: Clock, note: String) : Stamp
  Stamp(note: note, at: clock.now)
end

# Appends each note to notes.log, and counts the notes that landed.
process Keeper(fs: Fs)
  state
    saved: UInt64
  end

  message Save(note: String) : Bool
  message Saved : UInt64

  fn update(state, message)
    case message
      Save(note):
        case fs.append("notes.log", "#{note}\n", within: 100.ms)
          Ok(_):
            state.saved += 1
            true
          Error(_): false
        end
      Saved: state.saved
    end
  end
end

supervisor Keeping(fs: Fs)
  child Keeper(fs), restart: :always
end

# The notes the keeper counts, or none when it does not answer.
fn saved(keeper: Handle(Keeper)) : UInt64
  case keeper.ask(Saved, within: 1.minute)
    Ok(n): n
    Error(_): 0
  end
end

# The notes on disk.
fn on_disk(fs: Fs) : UInt64
  case fs.read_lines("notes.log", within: 1.minute)
    Ok(lines): lines.size
    Error(_): 0
  end
end

test "the simulated clock stamps the same note the same way twice"
  clock = Clock.fixture()
  assert stamp(clock, "hello") == stamp(clock, "hello")
end

# Run with mo test --sim --faults 20 --until 0.5: the first ten saves are the first half of
# the calls that can fail, so any of them may fail, and none of the last ten does.
test "a note that fails to save is never counted, and every note saves once faults stop"
  fs = Fs.fixture()
  keeper = Keeper.start(fs)
  for i in 0..10
    assert keeper.ask(Save(note: "early #{i}"), within: 1.minute) is Ok(_)
    assert saved(keeper) <= i + 1
  end
  for i in 0..10
    assert keeper.ask(Save(note: "late #{i}"), within: 1.minute) is Ok(true)
  end
  assert saved(keeper) >= 10
  assert saved(keeper) == on_disk(fs)
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs)
          proven: not run

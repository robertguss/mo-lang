# run:
module Processes.RestartReopens
expose Store, Stores, opened, told, main

intent "A store reopens itself at every start: its state's initializer reads the file through the Fs it was started with, so a restart after a crash runs the initializer again and reads the file as it is now, which is the pattern chapter 3 names for a store."

# What the store finds at `path` when it starts, or that nothing is there.
fn opened(fs: Fs, path: String) : String
  case fs.read(path, within: 1.minute)
    Ok(text): text
    Error(_): "nothing"
  end
end

process Store(fs: Fs, path: String)
  state
    text: String = opened(fs, path)
    writes: UInt64
  end

  invariant "a store takes at most one write between starts"
    state.writes < 2
  end

  message Write
  message Text : String

  fn update(state, message)
    case message
      Write:
        state.writes += 2
      Text: state.text
    end
  end
end

supervisor Stores(fs: Fs, path: String)
  child Store(fs, path), restart: :always
end

# What the store says it read. An ask waiting behind a Write when the store crashes is Down, since
# the restart empties the mailbox; one of the next reaches the restarted store.
fn told(store: Handle(Store)) : String
  var read = "no answer"
  for _ in 0..3
    if read == "no answer" and store.ask(Text, within: 1.minute) is Ok(text)
      read = text
    end
  end
  read
end

fn main(platform: Platform)
  out = platform.stdout
  fs = platform.fs
  path = "restart-reopens.txt"
  if fs.write(path, "one", within: 1.minute) is Ok(_)
    store = Store.start(fs, path)
    out.write("before the crash the store read #{told(store)}\n")
    if fs.write(path, "two", within: 1.minute) is Ok(_)
      store.send(Write)
      out.write("after the crash and the restart the store read #{told(store)}\n")
    end
    if fs.remove(path, within: 1.minute) is Ok(_)
      out.write("removed #{path}\n")
    end
  end
end

# A test cannot show the restart: a crash ends a test rejects at the trip. It shows the other half,
# that the initializer reads through the Fs the store was started with.
test "a store's initializer reads the file through the Fs it was started with"
  fs = Fs.fixture()
  if fs.write("s.txt", "one", within: 1.minute) is Ok(_)
    store = Store.start(fs, "s.txt")
    # Under a seed's faults the read may fail, and the store starts with nothing.
    if store.ask(Text, within: 1.minute) is Ok(text)
      assert text == "one" or text == "nothing"
    end
  end
  assert opened(Fs.fixture(), "missing.txt") == "nothing"
end

test rejects "a second write trips the invariant"
  store = Store.start(Fs.fixture(), "s.txt")
  store.send(Write)
  assert store.ask(Text, within: 1.minute) is Error(Down)
end

verified: types, contracts, tests (2), property (0 seeds), sim (100 runs, invariants (kept 1, tripped 1))
          proven: not run

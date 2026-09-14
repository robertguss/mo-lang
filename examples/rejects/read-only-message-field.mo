module Rejects.ReadOnlyMessageField
expose Saver, Savers, handed

intent "An Fs narrowed to read_only stays read-only in a message: a process whose arm writes through a message's Fs cannot be sent a read-only one."

process Saver()
  state
    saved: UInt32
  end

  message Save(files: Fs) : Bool

  fn update(state, message)
    case message
      Save(files):
        wrote = files.write("a.txt", "b", within: reply_by) is Ok(_)
        if wrote
          state.saved += 1
        end
        wrote
    end
  end
end

supervisor Savers
  child Saver, restart: :always
end

# expect MO0404: a read-only Fs reaches Save through fs.read_only; the never that read_only promises forbids it.
fn handed(fs: Fs, saver: Handle(Saver)) : Bool
  saver.ask(Save(files: fs.read_only), within: 1.minute) is Ok(_)
end

test "a saver saves what it is handed"
  assert handed(Fs.fixture(), Saver.start()) or true
end

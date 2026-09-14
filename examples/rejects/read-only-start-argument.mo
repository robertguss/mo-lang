module Rejects.ReadOnlyStartArgument
expose Saver, Savers, started

intent "An Fs narrowed to read_only stays read-only when a process is started with it: a process that writes through a start argument cannot be handed a read-only one."

process Saver(files: Fs)
  state
    saved: Bool
  end

  message Save : Bool

  fn update(state, message)
    case message
      Save:
        state.saved = files.write("a.txt", "b", within: reply_by) is Ok(_)
        state.saved
    end
  end
end

supervisor Savers(files: Fs)
  child Saver(files), restart: :always
end

# expect MO0404: a read-only Fs reaches Saver.start through fs.read_only; the never that read_only promises forbids it.
fn started(fs: Fs) : Handle(Saver)
  Saver.start(fs.read_only)
end

test "a saver saves"
  assert started(Fs.fixture()).ask(Save, within: 1.minute) is Ok(_)
end

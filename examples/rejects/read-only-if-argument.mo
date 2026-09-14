module Rejects.ReadOnlyIfArgument
expose Writer, Writers, started

intent "An Fs narrowed to read_only stays read-only inside an if: a process that writes through its start argument cannot be handed an if whose branch is a read-only Fs."

process Writer(files: Fs)
  state
    wrote: Bool
  end

  message Write : Bool

  fn update(state, message)
    case message
      Write:
        state.wrote = files.write("a.txt", "b", within: reply_by) is Ok(_)
        state.wrote
    end
  end
end

supervisor Writers(files: Fs)
  child Writer(files), restart: :always
end

# expect MO0404: Writer writes through its parameter files, and fs.read_only was narrowed to read_only and only reads; hand it the Fs fs.read_only was narrowed from.
fn started(fs: Fs, careful: Bool) : Handle(Writer)
  Writer.start(if careful: fs.read_only else: fs)
end

test "a writer writes"
  assert started(Fs.fixture(), false).ask(Write, within: 1.minute) is Ok(true)
end

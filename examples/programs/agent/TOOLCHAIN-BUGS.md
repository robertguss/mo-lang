# Toolchain bugs found while writing agent

Recorded while writing program 5 (`mo-wiki/spec/programs/05-agent-harness.md`, brief `mo-wiki/plans/program-5.md`), whose write scope was `examples/`. None is fixed here; each has a reproduction, what it cost agent, and the workaround agent uses. The `mo` is `toolchain/zig-out/bin/mo` (ReleaseSafe) built from `b86e1f5`, on an Apple M-series machine.

## 1. `MO0404` does not follow a read-only `Fs` into a process's start arguments

Fixed in step 24 (`mo-wiki/plans/interpreter-step-24.md`, part A): the checker follows the narrowing into a process's start arguments, a supervisor's child lines, and a message's fields, and `p6.mo` below is refused at `Tool.start(fs.read_only)` with `MO0404 Tool writes through its parameter files`. `examples/rejects/read-only-start-argument.mo` and `read-only-message-field.mo` hold it; `Agent.Registry.started_run` now hands the run its folder writable, and the run's tools refuse an ungranted write before it is made.

`Fs.read_only`'s row promises the checker refuses it "where a write reaches it (`MO0404`)", and it does for a function: handing `folder.read_only` to a function parameter that some branch writes through is refused at the call. Handed to a process's start argument that its update writes through, it is accepted, and the write crashes the process at run time with "writes through an Fs narrowed to read_only, which only reads".

Reproduction (`p6.mo`, in a folder of its own):

```
module P6
expose Tool, Tools, used

intent "probe: a read-only Fs handed to a process that writes when granted"

process Tool(files: Fs)
  state
    wrote: Bool
  end

  message Write : Bool

  fn update(state, message)
    case message
      Write:
        state.wrote = files.write("a", "b", within: reply_by) is Ok(_)
        state.wrote
    end
  end
end

supervisor Tools(files: Fs)
  child Tool(files), restart: :always
end

fn used(fs: Fs, granted: Bool) : Handle(Tool)
  if granted
    return Tool.start(fs)
  end
  Tool.start(fs.read_only)
end

test "a write through a read-only Fs a process was started with"
  fs = Fs.fixture()
  assert used(fs, true).ask(Write, within: 1.minute) is Ok(true)
  assert used(fs, false).ask(Write, within: 1.minute) is Ok(false)
end
```

```
$ mo check p6.mo                  # exit 0, no MO0404
$ mo test p6.mo
FAIL  test "a write through a read-only Fs a process was started with": fs.write("a") writes through an Fs narrowed to read_only, which only reads
      in process Tool, seed 1299120131
```

The same `Fs` handed straight to a function that writes, in `agent/tools.mo`'s first draft, was refused at tier 1: `MO0404 used writes through its parameter writes, and reads was narrowed to read_only and only reads`.

What it cost agent: nothing, and agent leans on it. `Agent.Registry.started_run` starts a `Run` with its folder writable only when the order grants `write_file`, and read-only otherwise; the run checks the grant before any tool runs, so the read-only folder is the backstop that makes an ungranted write a crash rather than a write. The checker cannot see that promise, since it does not follow the start argument. Workaround: none needed; the report names it so the rule's reach is known.

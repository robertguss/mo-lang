# Step 41 report: `Exec`, a child process narrowed to fixed commands

Worker: Claude Opus 5 in its own worktree (`toolchain/step-41-exec`), based on
`853a27df` (step 40 accepted). Brief: `mo-wiki/plans/interpreter-step-41.md`;
design: `mo-wiki/plans/mo-capabilities-for-the-harness.md`, section 3.

## A. RED

### Before building: can the MO0407 rule be said without new syntax?

Yes. `caps.zig` enforces `MO0407` for a `Platform` in two places, both keyed on
the type: `platformParams` (no function, process or supervisor but `main` takes
one; `platformIn` looks through `List`, `Option`, `Result`, `Map`, `Set` and
tuples) and `platformUses` (a name whose type is `Platform` is only ever the
receiver of a `.`; passed, bound to another name, put in a list, interpolated or
returned, it is refused). Fields of a struct or state and return types are
already refused for every capability (`MO0403`), and a capture for every
capability (`MO0409`). Making the same two functions ask "is this a `Platform`,
an `Exec` or a `Program`" instead of "is this a `Platform`" says the rule; one
gap is added: a message line's field of those types (a `Platform` in a message
line is not refused today either). No new syntax.

### The RED tests

- `src/exec_controls.zig` (new, in `root.zig`), three corpus tests, each under
  `mo run` and as a `mo build` binary against helper scripts the test writes
  into a temporary folder:
  1. exit codes 0, 1, 255; `kill -9 $$` (`Signalled(signal: 9)`); a child that
     ignores `SIGTERM` and sleeps 30 s with a grandchild, run
     `within: 1.seconds` (`Timeout`, both pids gone afterwards, checked with
     `ps`, and the whole program well under 20 s); a child that leaves a
     grandchild holding its stdout and exits (`Exited(code: 0)` at once,
     grandchild gone); 1 MiB on stdout and on stderr past a bound of 1000, past
     the default 65,536, and under a bound of 2 MiB; a hole holding spaces,
     quotes, `$(...)`, backquotes, `;` and a newline arriving as one argument
     byte for byte (and no `pwned` file), a leading `--help`, an empty hole; a
     NUL in a hole, no value and two values for one hole (`Refused`); a missing
     program (`Missing`); a folder as the program (`Failed`); `/usr/bin/env`
     with no environment and with a map; `/bin/pwd` in
     `platform.fs.scoped("work")`, in the operator's link to it, in a link
     inside the scope, in a folder not there, and in a scope that climbed out
     (the last three `Failed`); the default folder new, empty and gone after the
     run; `/bin/cat` with `stdin:`, without it (closed: `cat` ends), and 1 MiB
     through it; the descriptors open in the child (`0,1,2,` only, listed from
     inside the child); no controlling terminal; the child leads its own process
     group; `took`.
  2. a relative program path (`"bin/sh"`) crashes when the `Program` is made:
     exit 70, what was written before it stays, the report names the path.
  3. `Exec.fixture` under `mo test`, in a `mo build --tests` binary, and under
     `mo test --sim 40 --seed 1 --faults 50`: the fixture's function gets the
     program's path first and the holes filled, and `stdin`; the fixture refuses
     what the real one refuses; a process holding a `Command` counts every run
     whatever happens, while "no run ever times out" and "no run ever fails"
     each pass only without faults (so both `Timeout` and `Failed` are
     injected).
- `src/caps.zig`, one test: a `Command` passed down, narrowed with `env`,
  `output` and `in`, is clean; `Program` in a struct field (`MO0403`), `Exec`
  and `Program` as parameters and as values passed (`MO0407` each); a `Program`
  in a message line (`MO0407`); a `Program` captured by an anonymous function
  (`MO0409`); `Exec.fixture` outside a test (`MO0403`);
  `flows(Token, into: Command)` (`MO0404`).

Command:
`python3 bench/step36/guard.py 1500 -- zig build test -Dtest-filter="step 41" --summary all`.
Real exit code: **1**. Summary line:
`Build Summary: 3/5 steps succeeded (1 failed); 1/5 tests passed (4 failed)`.

Every one of the four fails because nothing of `Exec` exists yet; the first
lines of each:

```
error: 'caps.test.step 41: Exec and Program stay in main, and a Command travels as an Fs does' failed:
       expected 0 diagnostics:
       found:
         MO0202: there is no type named Command
         MO0209: a named argument appears only inside a call's parentheses
         MO0208: Platform has no field or function named exec
         MO0201: there is no struct or variant named Fixed
         MO0201: there is no struct or variant named Fixed
         MO0201: there is no variant named Hole
error: 'exec_controls.test.corpus: step 41, Exec runs a fixed command: ...' failed:
       controls.mo:4:14: MO0202 there is no type named Exit
       controls.mo:11:15: MO0202 there is no type named ExecError
       controls.mo:20:22: MO0202 there is no type named Done
       ...
       controls.mo:62:19: MO0208 Platform has no field or function named exec
       controls.mo:63:50: MO0201 there is no variant named Hole
error: 'exec_controls.test.corpus: step 41, a relative program path is refused ...' failed:
       mo build relative.mo: exit 1
       relative.mo:7:17: MO0208 Platform has no field or function named exec
error: 'exec_controls.test.corpus: step 41, Exec.fixture answers every run ...' failed:
       remover.mo:4:15: MO0202 there is no type named Command
       remover.mo:4:54: MO0202 there is no type named ExecError
```

(The first RED run also caught a mistake of mine in the fixture module,
`Error(_): assert false` on one line, which Mo refuses, MO0102; it was fixed
before this run and before this commit.)

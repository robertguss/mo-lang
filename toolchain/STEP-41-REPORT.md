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

## Where the brief or the design does not match the code

Three places. I resolved each inside the write scope and did not change the grammar. Each one is for the lead to confirm or reverse.

1. **`Command.in` cannot be written.** `in` is a keyword (`src/token.zig:100`, `for x in xs`), and after a `.` the parser takes only a name or a type name (`src/parser.zig:1213`), so `cmd.in(fs)` is MO0101. Accepting a keyword there would be new syntax, and the design says there is none. The row is **`in_folder`**. If the lead wants `in`, the change is one arm in `parsePostfix` (accept `.kw_in` as a member name) plus the formatter; the row name is one string in `prelude.zig`, `vm.zig`, `exec.zig`, `mo_rt.h`/`mo_rt.c`, `PRELUDE.md` and chapter 09.
2. **`Fixed("rm")` is `Fixed(text: "rm")`.** Mo builds every variant by naming its fields (grammar §6, MO0222); only `Some`, `Ok` and `Error` are positional. I followed the language and added no exception. The design page's example needs the field name.
3. **A stdlib struct named `Done` collided with programs.** Before this step, a stdlib struct was in every module's names, and a module's own variant or message of the same name was refused (MO0205, `checkVariantNames`); a construction `Done(...)` built the stdlib struct first. The corpus already has a `Done` variant (`examples/programs/agent/run.mo`). Fix in `check.zig`: a module's own variant or message now hides a stdlib struct of that name in that module (`ownVariant`), the way its own type already did. A module that declares `message Done` can still read a `Done`'s fields, but cannot build one by name. `Entry`, `Request` and the other stdlib structs get the same rule.

Also found and fixed: a `flows(T, into: Command)` rule could never fire. A hole's values are always a `List(String)`, and tier 1 did not look inside a list. `carries` now follows a list literal written at the call, as it already followed a construction (`caps.zig`). A `List` bound elsewhere is still not chased. The existing `flows` tests still pass (`-Dtest-filter="flows"`, `4/4`).

## B. What was built

**Checker (`caps.zig`).** `MO0407` covers `Exec` and `Program`, as the answer to the stop question above promised: `mainOnlyIn` looks through the same containers `platformIn` did. A function, process or supervisor parameter of those types is refused, and so is **a message line's field** (not refused for `Platform` before either; it is now). A name of one may only be a receiver. A value made on the spot (`platform.exec`, `exec.program(p)`) may be bound to a name, and otherwise only used as a receiver. Each message names the Command to hand on instead. Everything else comes from these being capabilities: `MO0403` (field, return, fixture outside a test), `MO0409` (capture), `MO0410` (a `Command` sent moves), `flows`. I also fixed the article in "take an Exec parameter" (it said "a Exec", and "a Events" before).

**Prelude.** Capabilities `Exec`, `Program`, `Command`; enums `Arg`, `Exit`; error enum `ExecError`; struct `Done`. All hideable, since programs already name a type `Command` (`kv`, `ledger`, `jobq`, `notes`, `agent`). Nine rows, `run` twice (with and without `stdin:`; C names the second `mo_r_Command_run_stdin`). `types.CapKind` gains `exec, program, command` at the end, and `mo_rt.h` matches. Five new fixed variant names in C (`Fixed`, `Hole`, `Exited`, `Signalled`, `Failed`).

**Values.** Each `Exec`, `Program` and `Command` is pointer-free: `Cap.handle` indexes a `Table` held by the Server under `mo run`, by the Sim in a test, and by static arrays in C. The strings are copied into the table. `env`, `in_folder` and `output` each append a new `Command`, as `scoped` appends an `Fs`, so a loop that makes commands grows the table (chapter 09 says to make them in `main`).

**The run** (`src/exec.zig` `Job.spawnAndWait`; `mo_rt.c` `exec_now`, the same algorithm in C):
- Three pipes (stdin, stdout, stderr), every end moved to 3 or above and close-on-exec.
- **Darwin: one `posix_spawn`** with `SETSID` (its own session, so it leads its own group and has no terminal), `CLOEXEC_DEFAULT` (the kernel closes every descriptor the file actions do not name, however high), `SETSIGDEF` for signals 1 to 31 but `KILL` and `STOP` (the interpreter's thread blocks `SIGPIPE` and the C runtime ignores it, which a child would otherwise inherit), `SETSIGMASK` empty, `adddup2` onto 0, 1 and 2, and `addfchdir_np` to the working folder. Its return is the errno: `ENOENT` or `ENOTDIR` is `Missing`, anything else `Failed(why)`. (`addfchdir_np` is deprecated in macOS 26's SDK for `addfchdir`, which only macOS 26 has; `mo_rt.c` silences the warning for that call, since `mo build` compiles with `-Werror`.)
- **Linux (and anything else): `fork`**, and in the child only system calls through std's per-target wrappers (Zig) or libc (C), each checked through `posix.errno`: `setsid`; `dup2` onto 0, 1 and 2; `fchdir`; every signal 1 to 31 to `SIG_DFL` and the mask emptied; every descriptor from 3 up closed but a report pipe (`close_range`, or a loop to the descriptor limit on a kernel older than 5.9); `execve`. On failure, the errno of the call that failed goes down the report pipe, then `_exit(127)`. The parent reads the report pipe: empty means the exec succeeded, and four bytes are the errno, mapped as on Darwin.
- **Why two paths.** The first GREEN used fork everywhere, so the Darwin tests exercised the Linux child code, and it passed every control. The benchmark then showed **94 ms a run in both runtimes against 1 ms for C**: this Mac's soft descriptor limit is 1,048,576 (`ulimit -n`; `kern.maxfilesperproc` 245,760), so the child's close loop made a million `close` calls. Darwin has no `close_range`, and `CLOEXEC_DEFAULT` is its answer, so Darwin now uses `posix_spawn`. The cost is that the fork child is now compiled on Darwin but only runs on Linux (below). The numbers of the fork version are kept in `bench/step41/numbers-fork-close-loop.tsv`.
- Parent: the report pipe closing empty means the exec succeeded. Four bytes are the errno: `ENOENT` or `ENOTDIR` is `Missing`, anything else `Failed(why)`. Then a `poll` loop drains stdout and stderr (bytes past the bound are dropped and `truncated` set) and writes stdin non-blocking (Darwin: `F_SETNOSIGPIPE`; Linux: the thread blocks `SIGPIPE`, so a closed reader is `EPIPE`).
- Exit is detected with `waitid(WEXITED | WNOHANG | WNOWAIT)`. The leader is **not reaped** until `kill(-pid, SIGKILL)` has hit the rest of its group, so the pid still names the group. At the deadline the group is killed, the leader reaped, and only then `Timeout`. A leader that exited before the deadline is its own answer even when an escaped process still holds its pipes.
- Wait slices: `poll` grows from 1 ms to 50 ms while nothing happens; once all pipes are closed, naps grow from 20 µs to 10 ms.
- Working folder: `Server.scopeFolder` (new) opens the scope's folder as `list` reaches it through step 40's walk, so a link the program named is refused; C uses `scope_place` the same way. By default the folder is a new `$TMPDIR/mo-exec-<24 hex>` (Zig) or `mkdtemp` (C), mode 0700, and its tree is removed after the run without following links.

**Not holding the scheduler** (`blocking.alone`, C `exec_alone`). A run gets a thread of its own, never one of the pool's four, so long runs cannot starve file writes. Under processes the caller waits on the thread's signal through `turns.block` (C: `net_wait`), as a pool write does. Without processes the interpreter still runs it on a thread and joins it, so `SIGPIPE` is blocked there. C runs it in place (it ignores `SIGPIPE` already). If the wait in `block` errors, `alone` waits for the job before returning, because the job lives on the caller's stack. Step 40 noted that `blocking.run` lacks this guard; it still does, and I did not change it.

**The fixture and `--sim`.** `Exec.fixture(fn)` stores the function (Zig: the `Value.Func`, live for the test's arena; C: packed into a `Parcel`, freed at each test's reset). A run hands it the argument list with the program's path first and the stdin, after the same `Refused` checks as the real one. Under `--sim` a run goes through `Sim.fault` with a new `Fault.failed`: it fails with `Timeout` (having waited its deadline) or `Failed(why: "a fault the simulator injected")`, or waits a random slice as a slow call does. C test binaries have no `--sim`, as before.

**Docs.** `PRELUDE.md` (types, variants, rows) and a new `## Exec` section at the end of `mo-wiki/spec/design-v0/09-stdlib.md`, which states `in_folder`, `Fixed(text:)`, and that the working folder is where the child starts, not a fence.

**Corpus.** `examples/stdlib/exec.mo` (new): `remove` and `inspect` through Commands narrowed to `docker rm -f NAME` and `docker inspect --format {{json .}} NAME`, tested with `Exec.fixture`. It includes a hole holding `a b; $(rm -rf /)` arriving as one argument, and the `Refused` cases. Its `verified:` line and its `.mo.ids` entries are the output of `mo test --write`.

### A fourth control, written after GREEN, and the run that shows it can fail

The first three controls have no processes, so none of them shows that a run leaves its scheduler free. I added `corpus: step 41, a run waits holding no scheduler ...` after GREEN. With `MO_CORES=1`, main's code runs on scheduler 0's thread, and `sleeper.send(Start)` returns only when every update has ended or parked. The Sleeper runs `sh -c 'sleep 1; echo done > marker'`, and main checks for `marker` on its next statement. To show it discriminates, I temporarily ran the job in place in both runtimes (`blocking.alone` calling the work directly; C `exec_alone` calling `exec_now` whatever `turns_on` says), rebuilt, and ran it, then restored both files:

```
== INLINE (the run blocks its scheduler)      mo run and binary, both:
main went on while the child ran: false
another process answered meanwhile: true
the run then answered: true
and the child had finished: true
== ALONE (as built)                           mo run and binary, both:
main went on while the child ran: true
...
```

My first two versions of this control (one ask, then eight asks between naps) printed the same thing both ways, for the reason above. They are not in the tree.

### Changes to tests after the RED commit

None weakens an expectation:
- `.in(` → `.in_folder(` and `Fixed("x")` → `Fixed(text: "x")` everywhere (finding 1 and 2 above).
- The fixture module gained the supervisor Mo requires (MO0316).
- The caps test: a message-arm pattern `Keep(docker: _)` → `Keep(_)` (MO0212) and its supervisor added, which then showed two `MO0407` (the message line and the send), both wanted, so the expectation lists both. The fixture-outside-a-test case was rewritten so its source has no unused bindings (MO0307).
- The fourth test was added.

## Verification (Darwin, this Mac)

Every process ran under `bench/step36/guard.py`. The only test binaries I saw running besides my own were the lead's (`lead-verify-step43`, then `lead-verify-reportcap`; I checked their working folders with `lsof`), and I left them alone. None of mine were orphaned after any run. The results below are from the final code (Darwin on `posix_spawn`), unless a line says otherwise.

- `zig build`: exit 0.
- `zig build test -Dtest-filter="step 41" --summary all`: exit **0**, `Build Summary: 5/5 steps succeeded; 6/6 tests passed` (RED: exit 1, `1/5 tests passed (4 failed)`).
  - The controls program ran for 2.4 s in total under `mo run` and 1.6 s as a binary. The 1-second deadline was kept by killing, not by waiting out the 30-second sleep. Both runtimes printed the same 44 lines, both pid files were gone, and no `pwned` file was made.
  - The same filter was also exit 0, `6/6`, on the fork version (`29bb783a`).
- `-Dtest-filter="corpus: every example passes every implemented stage"`: exit **0**, `2/2 tests passed`. It passed three times: on the fork version before `examples/stdlib/exec.mo` existed, again with it, and again on the final code.
- `-Dtest-filter="corpus: every module's tests and every program, built by mo build"`: exit **0**, `2/2 tests passed`. It passed three times: 16 min without the example, 6 min with it, and 15 min on the final code.
- Filters that touch what changed, each exit **0** (run on the fork version; the `posix_spawn` change touches none of them): `flows` 4/4, `Platform` 3/3, `fixture` 9/9, `step 40` 6/6, `a write on the pool is on disk when it answers` 2/2, `a struct and a variant` 2/2, `capability` 11/11.
- **Linux, compile only** (no VM, nothing run), after the `posix_spawn` change as before it: `zig build -Dtarget=x86_64-linux` and `-Dtarget=aarch64-linux` exit 0. The first attempt failed on `linux.close_range`'s flag struct, a Linux-only branch a Darwin build never compiles; it is fixed. The Linux `mo` is statically linked with no libc, so the raw-syscall branches (`fork`, `waitid`, `wait4`, `close_range`, `exit_group`) are the ones that compiled and the ones Linux will run. `mo build controls.mo --target x86_64-linux-musl` and `aarch64-linux-musl` exit 0 (the C runtime). `--target x86_64-linux-gnu` is refused by `mo build` itself ("requires dynamic linking"), which predates this step.
- The unfiltered `zig build test` was not run; it is the lead's.

## What the lead must rerun on Linux

`-Dtest-filter="step 41"` on the VM (all four controls in both runtimes); both corpus filters. Things that only Linux exercises:
- **the whole fork child** (`exec.zig` `start`'s else branch and `child`; `mo_rt.c` `exec_child`): since the switch to `posix_spawn` on Darwin, no test here runs it. Before the switch, every control passed through it on this Mac (commit `29bb783a`);
- `close_range`, falling back to a loop on a kernel older than 5.9 (with a limit like this Mac's, that loop would cost what it cost here);
- raw `waitid` with `WNOWAIT` and the `signo` check;
- `SIGPIPE` blocked per thread (Darwin used `F_SETNOSIGPIPE`);
- the eventfd signal of `alone`;
- `/dev/fd` listing through `/proc/self/fd` in the descriptors check;
- `ps -o pgid=` in the group check;
- `/usr/bin/env`, `/bin/pwd`, `/bin/test`, `/bin/ls`, `/bin/cat` paths as the controls name them (on some distributions `pwd`/`test` live only in `/usr/bin`; a `Missing` there is the path, not the code).

## Numbers

`bench/step41/measure.py` (with `runs.mo` and `floor.c`). Each row is a whole process timed as a whole, best of five; the same process with no runs is subtracted, so a number is what one run costs. Runs of the three runtimes are interleaved. `true` is `/usr/bin/true`, 300 runs. `mib` is `/usr/bin/head -c 1048576 /dev/zero`, 30 runs, with the MiB kept (`output(2 MiB)`, checked to be 1,048,576 bytes). The floor is C: `posix_spawn`, stdout and stderr as pipes read to their end, `waitpid`. Darwin, this Mac, while another worker was building (load in the table). Raw rows: `bench/step41/numbers.tsv`.

| per run | `mo run` | binary | C `posix_spawn` (floor) | load (1 min) |
|---|---:|---:|---:|---|
| `/usr/bin/true` | 1,228 µs (1.31×) | 1,113 µs (1.19×) | 934 µs | 14.2–14.6 |
| a child writing 1 MiB | 5,808 µs (3.9×) | 3,393 µs (2.3×) | 1,478 µs | 14.2 |

- **`true`.** What the extra 180 to 290 µs pays for: the new session and signal set in the spawn, a thread for each run, and the `waitid` poll. Once the pipes close, the parent naps from 20 µs until the leader has exited, because there is no notification for a child's exit that does not take a process-wide `SIGCHLD` handler. A kqueue `EVFILT_PROC` on Darwin and a `pidfd` on Linux would remove the naps, at the price of a second code path each.
- **1 MiB.** Most of the difference is Mo's, not the spawn's: the MiB becomes a `List(UInt8)` of 1,048,576 values, as `Fs.read_bytes` gives, where C keeps a byte buffer. The interpreter pays that per value. The design's `List(UInt8)` makes a 16 MiB bound cost that many values; a `Bytes` type would be the fix if a program needs big output.
- **The first version's numbers** (fork with a close loop; `numbers-fork-close-loop.tsv`, load 8 to 24): 93.5 ms and 95.9 ms a run of `true` against the floor's 1.0 ms. That is what moved Darwin to `posix_spawn` (see B).

## Decisions the brief did not cover

- `in_folder` for `in`, and `Fixed(text:)`: see "Where the brief or the design does not match the code".
- A module's own variant or message hides a stdlib struct of its name (`check.zig`), so `Done` did not break programs that already use the name.
- `flows` follows a list literal written at the call.
- A message line's field may not be a `Platform`, an `Exec` or a `Program` (`MO0407`).
- When the leader exits, the rest of its group is killed before the leader is reaped, not only at the deadline: the design's "not in this version: a child that outlives the run", made true. A leader that exited before the deadline is its own answer even if something it started left the group and still holds its pipes.
- The child starts its own **session** (`setsid`), not only its own group: it leads its group, as the brief asks, and also has no controlling terminal (a control checks `/dev/tty` cannot be opened).
- The argument list the fixture's function gets has the program's path first, so one fixture can answer several programs.
- A relative path, a NUL in the path or in a `Fixed`, and `output` past 16 MiB are crashes when the value is made (the caller broke a rule). A bad environment is `Refused` at the run, since the map is data.
- `in_folder` on a scope that is a link, not there, or climbed out makes the run `Failed("the working folder is not there, or is reached through a link")`: whether it was a link or an absence is not told apart, as step 40 does not tell them apart.
- Each run gets a thread of its own rather than a pool thread, so long runs cannot hold up file writes. There is no cap on concurrent runs; a program that starts thousands at once starts thousands of threads.
- The default working folder is `$TMPDIR/mo-exec-<24 hex>` (Zig) or `mkdtemp`'s `mo-exec-XXXXXXXXXXXX` (C), mode 0700, removed with its contents after the run, links not followed.
- Benchmarks under `toolchain/bench/step41/`, as every step's `bench/stepNN/`.

## Not done, or left for the lead

- Linux runs (see above), and the unfiltered `zig build test`.
- `Command.run`'s exit detection naps (see Numbers).
- `blocking.run` (step 30's pool) still returns if `block` errors while the job is on the pool, as step 40 reported. `alone` does not, but I did not change `run`.
- The wiki outside chapter 09 (the design page's `in` and `Fixed("rm")`, the decision log) is the lead's.

## Commits

| commit | what |
|---|---|
| `75834c97` | RED: `src/exec_controls.zig` (three controls), the caps test, this report's part A |
| `29bb783a` | GREEN: `exec.zig`, both runtimes, the fixture and `--sim` faults, `MO0407` for `Exec` and `Program`, the `Done` and `flows` fixes, the fourth control |
| `8ed27a20` | Darwin on one `posix_spawn` (`exec.zig`, `mo_rt.c`); Linux keeps fork and `close_range` |
| this one | `PRELUDE.md`, chapter 09's `## Exec`, `examples/stdlib/exec.mo` and its `.mo.ids`, `bench/step41/`, this report |

## Linux follow-up

The lead's run on the Linux VM (x86_64, `lead/verify-step41` at `0b0f494b`, which is `6eafb762` merged with `main`): build exit 0, `-Dtest-filter="step 41"` 5 of 6. The main controls test failed on one line, and only in the binary: `took: true` expected, `took: false` printed. `mo run` printed `true`, and the other 41 lines were right in both runtimes (the fork child's descriptors, group, terminal, Timeout by killing, and the folder cases included).

**How `took` is measured, checked in the source.**
- Interpreter (`src/exec.zig`, `Job.spawnAndWait`): the start is `Io.Clock.Timestamp.now(io, .awake)`, the monotonic clock, taken before the pipes are made and the child is started. The end is taken after the child is reaped. `took_ms = @divFloor(end - start, ns_per_ms)`.
- C runtime (`runtime/mo_rt.c`, `exec_now`): `awake_ns()`, which is `CLOCK_MONOTONIC`, is taken before the pipes and the spawn, and again after `exec_reap`. `took_ms = (end - start) / 1000000`.

Both truncate to whole milliseconds, so a run shorter than 1 ms is `0.ms`. On Linux, the static binary forks and execs `sh` running `exit 0` in under a millisecond. The control's `done.took > 0.ms` asked a question about speed, not about measurement. The runtimes are unchanged, since truncation is acceptable.

**The control, changed** (`src/exec_controls.zig`; nothing else touched):
- `took, a fast run` now asserts `0.ms <= took < 10.seconds`.
- A new line, `took, a 0.2-second sleep`, runs `/bin/sh -c 'sleep 0.2'` and asserts `150.ms <= took < 10.seconds`. It measures a known wait, and it would fail if `took` stayed 0 or were not measured across the run.

**Rerun on this Mac**, under the guard, logged to `bench/step41/step41-darwin-followup.log`, exit code in `bench/step41/step41-darwin-followup.exit`:
- `python3 bench/step36/guard.py 1500 -- zig build test -Dtest-filter="step 41" --summary all`: exit **0**, `Build Summary: 5/5 steps succeeded; 6/6 tests passed`.
- Both new lines printed `true` under `mo run` and in the binary.

The one test binary running before the rerun was the lead's (`lead-verify-step41`, working folder checked with `lsof`), and I left it alone; none of mine were left afterwards. Linux is the lead's to rerun from this commit.

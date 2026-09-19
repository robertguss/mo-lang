---
title: "Design: a scope that holds, Fs.replace, and Exec"
created: 2026-09-19
updated: 2026-09-19
type: plan
tags: [stdlib, security, effects, processes]
sources: [plans/mo-harness-in-mo.md, spec/design-v0/09-stdlib.md]
status: in-progress
---

# Design: a scope that holds, `Fs.replace`, and `Exec`

The lead's design for the first three capabilities of [[mo-harness-in-mo]]. No
new syntax anywhere on this page: every row is a method on a capability, in the
shape chapter 09 already uses. It becomes spec text in
`spec/design-v0/09-stdlib.md` when the toolchain step is briefed; the decisions
are rows in [[decision-log]].

## 1. A scope that holds

**The defect.** Chapter 09 says of a narrowed `Fs` that "nothing outside the
scope is reachable". The runtime checks the path's text only
(`toolchain/src/stdlib.zig`, `pathIn`: a `..` count and a lexical resolve), and
`list_kinds` documents "a link counting as what it points at". So a symlink
inside `fs.scoped("work")` that points at `/etc` reaches `/etc`. The sentence in
the spec is false today.

**Correction, 19 Sep 2026, 11:29 AM ET.** The lead's statement of the defect was half
right. The text-only check (`stdlib.zig`, `pathIn`, `climbsOut`) is the
*fixture's*. The real `Fs` (`server.zig` `realScopedIn`, `mo_rt.c`
`real_scoped`) already compared resolved paths, so a read through a link
pointing outside the scope was already `Missing`. Step 40's RED run showed the
holes that were real: a program's own `fs.scoped("link")` rooted the new scope
outside (an escape); links pointing inside, and folder links as a middle
component, were followed; `write`, `append`, `remove` and `rename` acted
through links; a FIFO hung both runtimes until killed; and the check and the
use were separate path lookups. The decision to make `scoped` hold stands.

**Decision: fix `scoped`, do not add a second kind of scope.** One scope whose
promise is true beats two where the default leaks.

- Every row opens the path one component at a time from the scope's folder
  (`openat` with `O_NOFOLLOW`), so a symlink at any component is refused.
- A refused path is `Missing(path)`, as a path outside the scope is today: a
  program cannot tell a link from an absence, so a link leaks nothing.
- `list` and `list_kinds` still name a link; `EntryKind` gains `Link`, and a
  link is no longer reported as what it points at.
- Reads and writes take regular files only (a FIFO or device is `Missing`).
- The scope's own folder may be reached through links: that path is the
  operator's, given to `main`, not the program's.
- `Fs.fixture()` has no links, so its behaviour is unchanged.

Hardlink count and setuid checks, which `workspace_files.py` makes, are not
scope rules: they become a row the harness calls, `fs.kind_of(path)`, returning
an `Entry` with `links: UInt64` and `setuid: Bool` added. A program that cares
asks; every program is safe from links without asking.

**What may break.** A corpus program that reads through a symlink on purpose.
The toolchain step's first part is a sweep of `examples/` for one; none is
expected.

## 2. `Fs.replace`

| receiver | name      | parameters                     | returns                 |                                                                                                                                                                                                                                                                  |
| -------- | --------- | ------------------------------ | ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Fs`     | `replace` | `path: String`, `text: String` | `Result(none, FsError)` | the file holds exactly the text, and a reader sees the old file or the new one, never a part: written to a temporary name in the same folder, synced, renamed over `path`, the folder synced. Created private to the owner (mode 0600). On a fixture, as `write` |

`write` stays as it is (in place, synced). The folder sync is the one generation
six asked for: a rename is durable only when its folder is. On macOS the sync is
`F_FULLFSYNC`, which step 39 part F owes; `replace` does not claim more than
`write` does until that lands.

## 3. `Exec`

Robert's decision, 19 Sep 2026. The reviewer who mapped the harness argued
against it: a child process has none of Mo's checked authority, so a handle to
"run anything" would make every capability claim in the program untrue. The
design answers that by never letting such a handle exist below `main`.

```ruby
fn main(platform: Platform)
  docker = platform.exec.program("/usr/bin/docker")
  remove = docker.command([Fixed("rm"), Fixed("-f"), Hole])   # one hole, a whole argument
  inspect = docker.command([Fixed("inspect"), Fixed("--format"), Fixed("{{json .}}"), Hole])
  Executor.start(remove, inspect, platform.fs.scoped("runs"))
end

# far from main, holding only `remove`:
case remove.run([name], within: 10.seconds)
  Ok(done): done.exit        # Exited(code: 0), Signalled(signal: 9)
  Error(Timeout): ...        # the group was killed; see below
  Error(_): ...
end
```

| receiver         | name      | parameters                                 | returns                   |                                                                                     |
| ---------------- | --------- | ------------------------------------------ | ------------------------- | ----------------------------------------------------------------------------------- |
| `Platform`       | `exec`    |                                            | `Exec`                    | `main` only, like every part of the platform                                        |
| `Exec`           | `program` | `path: String`                             | `Program`                 | an absolute path; no `PATH` search, ever                                            |
| `Program`        | `command` | `List(Arg)`                                | `Command`                 | a fixed argument list; `Arg` is an ordinary enum, `Fixed(text: String)` or `Hole`                        |
| `Command`        | `env`     | `Map(String, String)`                      | `Command`                 | the child's whole environment; the default is empty, never the parent's             |
| `Command`        | `in`      | `Fs`                                       | `Command`                 | the working folder is this scope's folder; the default is an empty temporary folder |
| `Command`        | `output`  | `UInt64`                                   | `Command`                 | bytes kept of stdout and of stderr each; default 65,536, at most 16 MiB             |
| `Command`        | `run`     | `List(String)`, `stdin: String` (optional) | `Result(Done, ExecError)` | fills the holes in order; waits, so it takes `within:`                              |
| `Exec` (on type) | `fixture` | `fn(List(String), String) Done`            | `Exec`                    | tests and `mo test --sim`: the function answers every run                           |

`Done` is `exit: Exit` (`Exited(code: UInt8)` or `Signalled(signal: UInt8)`),
`stdout` and `stderr` as `List(UInt8)`, `truncated: Bool`, `took: Duration`.
`ExecError` is `Missing` (no such program), `Refused` (wrong hole count, or a
value holding a NUL), `Timeout`, `Failed(why: String)`.

The rules that make it safe to hold:

- **No shell and no interpolation.** A hole is one whole argument. No row builds
  a command from text, so finding E5 (a name concatenated into a systemd
  directive) cannot be written.
- **Narrowing only goes down.** `Exec` makes `Program`, `Program` makes
  `Command`; nothing goes back up, and only `Command` can run. A process handed
  `remove` can remove containers and do nothing else.
- **`Exec` and `Program` stay in `main`** (`MO0407`, as `Platform`): not stored,
  sent or returned. `Command` travels like an `Fs`.
- **The deadline is kept by killing.** The child starts in its own process
  group; at the deadline the group gets `SIGKILL`, and `Timeout` is returned
  only after the group is reaped. A child that escaped its group is the
  operating system's to contain (a cgroup, a container): Mo says so and does not
  pretend otherwise.
- **Output is bounded** and the bound is reported (`truncated`), never silent.
- **The child inherits nothing**: no environment, no open descriptors but the
  three standard ones, no terminal.
- The simulator schedules a run like any other wait and injects `Timeout` and
  `Failed` at its fault rate.

Not in this version: streaming output, a child that outlives the run, signals
other than the deadline's kill, a pseudo-terminal, pipes between children. The
harness needs none of them; a long-running server is started by `systemd-run`,
which returns.

## Order and acceptance

One toolchain step, three parts, each accepted with both runtimes and the
simulator: (1) the scope, against the hostile-filesystem cases already in
`toolchain/harness/executor/test_workspace.py` (symlink, hardlink, FIFO, setuid)
rewritten as corpus tests; (2) `replace`, with a kill between write and rename
showing the old file whole; (3) `Exec`, with controls for deadline kill of a
child that ignores `SIGTERM`, a grandchild in the group, output past the bound,
a hole holding spaces and quotes arriving as one argument, an empty environment,
and a missing program. Linux and Darwin both.

## Related

- [[interpreter-step-40]]
- [[mo-harness-in-mo]]
- [[decision-log]]

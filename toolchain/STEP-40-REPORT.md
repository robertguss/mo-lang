# Step 40 report: a scope that holds, and `Fs.replace`

Worker: Claude Opus 5 in its own worktree (`toolchain/step-40-scope`). This file grows
with the step; this first version holds only part A (the sweep and the RED run),
committed before any fix.

## A. Sweep, then RED

### 1. Sweep

- `examples/`: no program reads or lists through a symlink on purpose. The only
  mention is prose in `examples/programs/agent/tests/coding-fixture-v1/README.md:43`
  ("does not ... establish a symlink sandbox").
- `toolchain/` tests: one test makes a link. It is `src/server.zig`'s
  "a scoped read that cannot escape", with `data/link.txt -> ../secret.txt`, and it
  expects `Missing`. That stays true.
- One corpus program is touched by `EntryKind` and `Entry` changing:
  `examples/stdlib/files.mo`. It compares `e.kind == File`, which is not a `case`
  match, so the exhaustiveness check does not flag it. But its test builds
  `Entry(name:, kind:)` values, and those need the new fields.

**The brief does not match the code here.** The brief says the check is on the
path's text only (`stdlib.zig`, `pathIn` and `climbsOut`). That is the *fixture's*
check. The real `Fs` (`server.zig` `realScopedIn`/`targetScoped`, and
`mo_rt.c` `real_scoped`/`target_scoped`) already compares `realpath`s. So a link
pointing *outside* was already `Missing` in both runtimes. The holes that remain are
these:

- a link pointing *inside* is followed;
- a folder link as a middle component is followed;
- **a program's own `fs.scoped("link")` escapes**: the narrowed root is resolved
  through the link, and later reads are checked against that new root
  (`scoped dirout_link: ok outer` below);
- `remove`, `rename`, `write` and `append` act through a link on its target;
- a FIFO blocks both runtimes forever (guard killed each at 60 s);
- a device reads;
- the check and the use are separate path lookups.

### 2. RED run

Command: `python3 bench/step36/guard.py 1500 -- zig build test -Dtest-filter="step 40"`
(tests in the new `src/fs_scope.zig`). Real exit code: **1**.
Summary line: `Build Summary: 3/5 steps succeeded (1 failed); 1/6 tests passed (5 failed)`

The hostile program's output (`mo run`, then the binary, on the same tree, so the
binary sees what `mo run` changed). Both runs were killed by guard at `write fifo`:

```
---- mo run, exit 137
read a.txt: ok safe
read hard: ok safe
read out_link: missing out_link
read in_link: ok safe
read dirlink/a.txt: ok safe
read dirout_link/x.txt: missing dirout_link/x.txt
read_lines in_link: ok
read_bytes in_link: ok
size in_link: ok
fold_lines in_link: ok
scoped dirout_link: ok outer
scoped dirlink: ok safe
scoped dirlink, listed: a.txt, dirlink, dirout_link, fifo, hard, in_link, out_link, sub
operator's link: ok safe
operator's link, then in_link: ok safe
device: ok
list: a.txt, dirlink, dirout_link, fifo, hard, in_link, out_link, sub
list_kinds: a.txt file, dirlink folder, dirout_link folder, fifo file, hard file, in_link file, out_link file, sub folder
write out_link: missing out_link
write in_link: ok
append in_link: ok
write dirlink/new.txt: ok
mkdir dirlink: ok
mkdir dirlink/made: ok
remove in_link: ok
rename in_link to moved: missing in_link
rename sub/b.txt to in_link: ok
rename sub/b.txt to dirlink/b.txt: missing sub/b.txt
read a.txt after: missing a.txt
---- binary, exit 137
read a.txt: missing a.txt
read hard: ok xx
read out_link: missing out_link
read in_link: ok deep
read dirlink/a.txt: missing dirlink/a.txt
read dirout_link/x.txt: missing dirout_link/x.txt
read_lines in_link: ok
read_bytes in_link: ok
size in_link: ok
fold_lines in_link: ok
scoped dirout_link: ok outer
scoped dirlink: missing a.txt
scoped dirlink, listed: dirlink, dirout_link, fifo, hard, in_link, made, new.txt, out_link, sub
operator's link: missing a.txt
operator's link, then in_link: ok deep
device: ok
list: dirlink, dirout_link, fifo, hard, in_link, made, new.txt, out_link, sub
list_kinds: dirlink folder, dirout_link folder, fifo file, hard file, in_link file, made folder, new.txt file, out_link file, sub folder
write out_link: missing out_link
write in_link: ok
append in_link: ok
write dirlink/new.txt: ok
mkdir dirlink: ok
mkdir dirlink/made: ok
remove in_link: ok
rename in_link to moved: missing in_link
rename sub/b.txt to in_link: missing sub/b.txt
rename sub/b.txt to dirlink/b.txt: missing sub/b.txt
read a.txt after: missing a.txt
```

The `kind_of` and `replace` programs, and both replace controls, do not compile
today (`MO0208 Fs has no field or function named replace` / `kind_of`).

The caps test with `replace` and `kind_of` added to the read-only case:
`python3 bench/step36/guard.py 900 -- zig build test -Dtest-filter="a write through an Fs narrowed to read_only, where the function can see it"`,
exit **1**, `Build Summary: 3/5 steps succeeded (1 failed); 1/2 tests passed (1 failed)`:

```
expected 1 diagnostics: MO0404
MO0208: Fs has no field or function named replace
MO0209: a named argument appears only inside a call's parentheses
MO0208: Fs has no field or function named kind_of
MO0209: a named argument appears only inside a call's parentheses
```

## Who finished this step

The first worker's tab closed at about 10:07 AM ET, after the RED commit (`373d7f85`) and
with its GREEN work uncommitted; the lead preserved that work as `a687fd2f` ("WIP snapshot",
unverified). A second worker (Claude Opus 5, same worktree) reviewed the snapshot as a
reviewer would, fixed what was wrong, reran every test, measured, and wrote the rest of
this report. Nothing was rebased; the fixes are commits on top.

## Commits

| commit | what |
|---|---|
| `373d7f85` | RED: the hostile-tree, `kind_of`, `replace` and replace-control tests (`src/fs_scope.zig`), the caps case; this report's part A |
| `a687fd2f` | the first worker's GREEN work, as the lead preserved it (13 files) |
| `0bb7723c` | RED: `Fs.replace` of a 255-byte name, failing on the WIP (see below) |
| `fba04fe8` | GREEN: the review's fixes (both runtimes, `blocking.zig`, `server.zig`, `stdlib.zig`) |
| `5c1454ec` | `examples/stdlib/files.mo` as `mo fmt` leaves it; `.mo.ids` by `mo test --write` |
| this one | `bench/step40/` (the benchmark and its numbers) and this report |

## B. The scope holds: what was built

Both runtimes have the same shape (`server.zig` `place`/`openScoped`/`statAt`/`fileAt`,
`mo_rt.c` `scope_place`/`open_scoped`/`stat_at`/`file_at`):

- **The anchor.** A `Scope` gains `anchor`: the folder `platform.fs.scoped(...)` named. It is
  opened with links followed (that path is the operator's). A narrowing of a narrowed `Fs`
  keeps the anchor, so the program's own `scoped` is walked from it like any other path.
  `platform.fs` itself (no anchor) is the whole file system: the system resolves its paths.
- **The walk.** The path is resolved lexically against the scope (`..` included, refused
  past the scope's root as before), then walked from the anchor one name at a time with
  `openat(dir, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)`, each folder's
  descriptor closed once the next is open. Because no component can be a link, the lexical
  `..` is the physical one. The result is a *place*: an open folder descriptor and the last
  name in it.
- **Acting on the descriptor.** Every row acts on the place, never on the path again:
  - `read`, `read_lines`, `read_bytes`, `fold_lines`: `openat(place, name, O_RDONLY |
    O_NOFOLLOW | O_NONBLOCK | O_NOCTTY | O_CLOEXEC)`, then `fstat` on that descriptor: not
    a regular file is `Missing`, before a byte is read. `O_NONBLOCK` is what keeps a FIFO
    from blocking the open (RED: both runtimes hung on `write fifo` until guard killed them).
  - `write`, `append`: the same open, `O_WRONLY | O_CREAT` (and `O_APPEND`), the `fstat`
    check, then `ftruncate(fd, 0)` for `write` (never `O_TRUNC`, which would empty a file
    before the check). The pool writes and syncs that descriptor (`blocking.write(fd)`),
    no longer a path.
  - `size`, `kind_of`: `fstatat(place, name, AT_SYMLINK_NOFOLLOW)`, one call relative to
    the resolved folder.
  - `remove`: `fstatat` no-follow says regular file, then `unlinkat(place, name, 0)`.
  - `rename`: both ends are walked; `from` must be a regular file (no-follow), `to` must be
    absent or a regular file (no-follow), then `renameat(from_place, from_name, to_place,
    to_name)`.
  - `mkdir`: `mkdirat(place, name)`; on `EEXIST` a no-follow `fstatat` must say folder.
  - `list`, `list_kinds`: the scope's folder opened as the walk opens a folder, iterated
    through that descriptor; `list_kinds` `fstatat`s each entry without following it.
- **What Darwin and Linux each need.** The same calls on both: `openat` with `O_NOFOLLOW |
  O_DIRECTORY` per folder, `O_NOFOLLOW | O_NONBLOCK` and an `fstat` for the last name,
  `fstatat(AT_SYMLINK_NOFOLLOW)`, `unlinkat`, `renameat`, `mkdirat`, `fsync` on a folder
  descriptor. Both refuse a final link under `O_NOFOLLOW` with `ELOOP` (with or without
  `O_CREAT`), and both answer `O_WRONLY | O_NONBLOCK` on a FIFO with no reader with `ENXIO`.
  Each has a one-call form of the walk the step did not use: Darwin's `O_NOFOLLOW_ANY`
  (macOS 11) and Linux's `openat2` with `RESOLVE_NO_SYMLINKS | RESOLVE_BENEATH` (5.6). See
  the numbers for why the lead may want them.
- **What is left of the window between check and use.** For the rows that open, none: they
  act on the descriptor they checked. For `remove`, `rename`, `replace`'s target check and
  `mkdir`'s `EEXIST` check, the last name is checked and then acted on by name inside the
  resolved folder, so it could be swapped between the two. Nothing is reached through it:
  `unlinkat`, `renameat` and `mkdirat` never follow a final link, so a swap can at worst
  remove, rename or replace the link itself, inside the scope. The anchor is opened by its
  path on each call, links followed, by design (it is the operator's path).
- `EntryKind` gains `Link`; `Entry` gains `links: UInt64` and `setuid: Bool`
  (`prelude.zig`, `PRELUDE.md`, chapter 09, `emit_c.zig`'s `fixed_names`, `mo_rt.h`'s
  `MO_N_LINK`). `list_kinds` reports a link as `Link`; a FIFO or device is `File` there
  (chapter 09 says so) and `Missing` to read.
- `Fs.kind_of(path)`: the name's `Entry`, never followed; `name` is the path as the program
  wrote it. On a fixture: a file or a folder, one link, never setuid.
- `Fs.fixture()` behaviour is unchanged apart from the new rows.

## C. `Fs.replace`: what was built

`blocking.replaceNow` / `mo_rt.c` `replace_now`, on the blocking pool like `write`: the target's
place is walked as above and its name must be absent or a regular file (no-follow). In the
same folder descriptor: a name `.mo-replace-<24 hex>` from 12 random bytes, created with
`O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC`, mode `0600` (up to eight tries on
`EEXIST`); the text written and `fsync`ed; `renameat` over the name; the folder `fsync`ed.
Any failure before the rename unlinks the temporary name, so the old file is whole and no
temporary file is left. The one exception is a kill: a process killed between the write and
the rename leaves its temporary file (the kill control counts them; see below). A folder
sync that fails *after* the rename answers `Missing` too, with the new text in place but not
known to be durable, as a `write` whose `fsync` fails does. The syncs are `fsync`, as
`write`'s; `F_FULLFSYNC` is step 39 part F's, not claimed here. A read-only `Fs` refuses it
(`MO0404`, `caps.zig`'s `writesFiles`); on a fixture it is `write`.

## What the review found wrong in the inherited work, and what was done

The snapshot was mostly right: every row in both runtimes did act on its resolved
descriptor, a link pointing inside the scope was refused, `rename` checked both ends, and
`replace` removed its temporary file on every failure path it had. What was wrong:

1. **`Fs.replace` could not replace a long name, in both runtimes.** The temporary name was
   `.<name>.mo-<24 hex>`, 29 bytes longer than the name, so a name over 226 bytes could not
   be replaced (`Missing`). RED in `0bb7723c`, against the WIP's `blocking.zig` and
   `mo_rt.c`: `replace a 255-byte name: missing llll…`, exit 1, `1/2 tests passed (1
   failed)`. Fixed in `fba04fe8`: a fixed-length `.mo-replace-<hex>`. `blocking.zig`'s unit
   test replaced its "a 250-byte name fails and leaves nothing" case (which enshrined the
   bug) with a 255-byte name that succeeds and a rename that fails (a folder at the name)
   and leaves no temporary file.
2. **The interpreter's `read` leaked.** The WIP's `readScoped` returned `ArrayList.items`
   from a buffer grown 64 KiB at a time: up to 64 KiB of spare capacity leaked with every
   read (the text is never freed while the program holds it), and the whole buffer on a
   refused read (past the limit, a failed `read`). Fixed: sized from `fstat`, as
   `readFileAlloc` sized it, returned by `toOwnedSlice`, freed on every refusal.
3. **No `O_NOCTTY`** on the opens that can now reach a device (reads through `platform.fs`
   or an operator's scope over `/dev`). Added in both runtimes.
4. **The fixture's `kind_of`** leaked the folder prefix it allocated per call (`stdlib.zig`).
5. **`examples/stdlib/files.mo` was not formatted**, so the first corpus test failed at its
   `mo fmt --check` (`corpus: stdlib/files.mo is not formatted`). The WIP's report did not
   mention it, so its "full corpus run" either predates that edit or missed this line.
   Fixed in `5c1454ec`: the expected entries are a local, which `mo fmt` leaves as written;
   the sidecar is `mo test --write`'s.
6. The WIP changed the RED tests after the RED commit. Every change is a correction of the
   test harness, not of an expectation: the flipper read `args.get(1)`/`get(2)` where the
   first argument is `get(0)`; the replace test never built its tree (`s.sh(tree)` was
   missing); `mo test --native` does not exist (now `mo build --tests` and the binary);
   `Missing("b.log")` is `Missing(path: "b.log")`. No `want` line changed. The RED output
   stands: these tests did not compile before the fix, as part A says.

Not changed, noted for the lead: `blocking.run` returns if the scheduler's `block` fails
while the job is still on the pool, and the job lives on the caller's stack. That is
older than this step (the job held a path before; it now holds a descriptor the caller then
closes). It needs a run that errors inside `block`, which no test makes.

## Verification (Darwin, this Mac)

Every process under `bench/step36/guard.py`. No orphaned test binaries were found before or
after any run.

- `zig build`: exit 0.
- `zig build test -Dtest-filter="step 40" --summary all`: exit **0**, `Build Summary: 5/5
  steps succeeded; 6/6 tests passed` (RED in `373d7f85`: exit 1, `1/6 tests passed (5
  failed)`). The hostile program prints exactly the `want` of part A under `mo run` and in a
  binary, and outside files and links are untouched. `kind_of`, `replace` (with the 255-byte
  name), their fixture tests under `mo test` and `mo build --tests`: all pass.
  - Reader control: `1000 replaced`, 937 reads under `mo run` and 1,278 in the binary, **0
    partial, 0 not there**.
  - Kill control: 8 of 8 rounds killed in each runtime, the target whole every time;
    temporary files left by the kills: 4 (all whole) under `mo run`, 5 (all whole) in the
    binary, so kills did land between write and rename.
- `-Dtest-filter="a write through an Fs narrowed to read_only, where the function can see
  it"` (the caps case with `replace`): exit 0, `2/2 tests passed` (RED: `1/2`).
- `-Dtest-filter="a write on the pool is on disk when it answers"` (blocking.zig): exit 0,
  `2/2 tests passed`.
- `-Dtest-filter="a scoped read that cannot escape"` (server.zig's older link test): exit 0,
  `2/2 tests passed`.
- `-Dtest-filter="corpus: every example passes every implemented stage"`: first run exit 1
  (the `mo fmt` finding above), after `5c1454ec` exit **0**, `2/2 tests passed`.
- `-Dtest-filter="corpus: every module's tests and every program, built by mo build"`: exit
  **0**, `2/2 tests passed`, 13 min. It ran before `5c1454ec`, whose only change is how
  one test of `files.mo` binds its expected list; `mo test --write` and `mo build --tests`
  of that file afterwards: 6 passed, exit 0.
- The unfiltered `zig build test` was not run: it is the lead's.

## Corpus programs touched

`examples/stdlib/files.mo` only (its `list_kinds` test builds `Entry` values, which need the
new fields). No corpus program matches on `EntryKind` with `case`, so the checker's
exhaustiveness flagged none. The sweep (part A) found no program that reads through a link on
purpose.

## Numbers

`bench/step40/files.mo` runs one row many times over a tree `bench/step40/measure.py` makes
(a small file, the same file 16 folders deeper, a 12 MB file of 200,000 lines, a folder of
10,000 files). There were no file benchmarks in the corpus for these rows (the nearest,
`logstat-4k`, reads one small log), and the first worker recorded no "before" numbers, so
"before" is the base commit `9304fc65` built from `git archive` in a scratch folder outside
the repo, and "after" is this branch. Each row is a whole process, best of five, runs of the
two interleaved; the same process with no calls is subtracted, so a number is the cost of one
call. Two runs, the second shown; the first (load 7 to 11) agreed within a few percent on
every row. Raw rows of both: `bench/step40/numbers.tsv`.

| row (calls) | `mo run` before | after | binary before | after | load (1 min) |
|---|---:|---:|---:|---:|---|
| `read` small file (2,000) | 28.7 µs | 20.3 µs | 26.4 µs | 19.2 µs | 5.3 |
| `read` 16 folders down (2,000) | 50.5 µs | **176.4 µs** | 47.2 µs | **174.4 µs** | 5.0–5.3 |
| `size` (2,000) | 18.8 µs | 10.8 µs | 16.4 µs | 9.9 µs | 5.0 |
| `write`, synced (300) | 83.8 µs | 66.7 µs | 79.2 µs | 61.8 µs | 5.0 |
| `append`, synced (300) | 65.3 µs | 49.3 µs | 66.5 µs | 46.3 µs | 5.0 |
| `fold_lines`, 200,000 lines (1) | 21.5 ms | 21.6 ms | 13.1 ms | 13.4 ms | 4.8–5.0 |
| `list`, 10,000 names (30) | 4.75 ms | 4.79 ms | 75.0 ms | 4.36 ms | 4.8–7.2 |
| `list_kinds`, 10,000 names (30) | 4.94 ms | **16.2 ms** | 71.8 ms | 12.5 ms | 5.5–6.7 |

**Cost per path component**, (deep − read) / 16: before 1.36 µs (`mo run`) and 1.30 µs
(binary); after **9.75 µs** and **9.70 µs**. The walk is two system calls a folder (`openat`,
`close`), and on this Mac an `open` costs far more than the `lstat`s `realpath` made. A path
of one or two folders, the usual, is cheaper than before, because the two `realpath`s a call
made (the scope's and the path's, each walking the whole absolute path) are gone; the walk
now starts at the scope's folder.

**Findings for the lead (regressions past 10%):**

1. **A deep path costs 3.5 times as much** (16 folders: 50 → 176 µs). The one-call forms
   would remove the walk: Darwin's `O_NOFOLLOW_ANY` on the relative path from the anchor's
   descriptor (the lexical resolve already removed every `..`), Linux's `openat2` with
   `RESOLVE_NO_SYMLINKS | RESOLVE_BENEATH`. Not done here: it adds a second code path per
   platform, and the Linux one could not be tested on this Mac.
2. **`list_kinds` under `mo run` costs 3.3 times as much** (4.9 → 16.2 ms for 10,000 names):
   every entry is now `fstatat`ed without following, since `links` and `setuid` need it;
   before, the interpreter trusted `readdir`'s type and stat'ed only links. In the binary it is
   5.7 times *cheaper* (71.8 → 12.5 ms): before, the C runtime stat'ed every entry, `list`
   included, by its full absolute path. The cost is the price of the new fields; a
   `list_kinds` that stat'ed only when asked would need a different row.

`read`, `size`, `write`, `append` got cheaper (about 25 to 40%); `fold_lines` and the
interpreter's `list` are unchanged; the binary's `list` is 17 times cheaper.

## Decisions the brief did not cover

- The temporary name is `.mo-replace-<24 hex>`, not derived from the target's name (review
  finding 1). A kill between write and rename leaves one such file beside the target; a
  harness that wants them gone can remove names of that shape.
- A folder sync that fails after the rename is `Missing`, though the new text is in place.
- `O_NOCTTY` on every open of a last name.
- `platform.fs`, never narrowed, keeps following links (the system resolves its paths);
  only a narrowed `Fs` walks. Chapter 09 says so.
- Benchmarks under `toolchain/bench/step40/` (outside the brief's write scope list, as every
  step's `bench/stepNN/` has been), so the lead can rerun them.

## What I could not check on Darwin, and what the lead must rerun

- **Linux**, on the machine's trusted toolchain: `zig build`, then
  `-Dtest-filter="step 40"` (every hostile case, the FIFO's `ENXIO`, `O_NOFOLLOW` with
  `O_CREAT`, setuid by a non-root user, the hard-link count, the kill and reader controls),
  the caps, blocking-pool and scoped-read filters above, and both corpus filters. Zig's
  `posix.O.NOCTTY` and `Io.File.Stat.nlink`, and C's `O_NOCTTY`/`fdopendir`, compiled only on
  Darwin here.
- The unfiltered `zig build test`.
- Optionally the numbers on Linux: `python3 toolchain/bench/step40/measure.py OUT
  before=<mo at 9304fc65> after=<mo at this branch>`, where the per-component cost of
  `openat` may differ a lot from Darwin's.

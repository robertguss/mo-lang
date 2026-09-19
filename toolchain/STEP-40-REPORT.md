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

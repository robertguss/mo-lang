# Toolchain bugs found while writing logstat

Recorded, not fixed (the brief's write scope is `examples/`). Each has a minimal reproduction and the workaround the program uses.

## 1. One file sees one module: `use` loads nothing, so a multi-module program cannot run or be tested

`pipeline.zig` compiles exactly one source for `mo check`, `mo test`, and `mo run`. A `use` line only registers the named types as opaque (`check.zig`, `registerModule`), and a function from another module is not in scope.

```
# a/lib.mo
module A.Lib
expose Pair, twice

intent "probe"

struct Pair
  x: UInt32
end

fn twice(n: UInt32) : UInt32
  n * 2
end

# a/app.mo
module A.App

use A.Lib{Pair}

intent "probe"

fn main(platform: Platform)
  platform.stdout.write("#{twice(2)}\n")
end
```

`mo run a/app.mo` prints `a/app.mo:8:28: MO0201 there is no twice in scope`. The grammar's `use` braces take only `TypeName`s, so there is also no way to name a function from another module at all.

Consequences for logstat:
- `Logstat.Main` calls all three other modules, so `mo check main.mo` and `mo test main.mo` fail with MO0201 on their own.
- A module that takes another module's type (Stats takes `Record`, Report takes `Summary`) cannot build one in its tests from an opaque `use`, so it declares a copy of that type, marked `# copy of Logstat.X`.

Workaround: `check.sh` joins the four modules into one file (declarations in dependency order, the copies dropped, `use` lines dropped, tests after all declarations) in a temporary folder and runs `mo test` and `mo run` on that. The four `.mo` files stay the source.

## 2. The corpus test cannot hold a program made of several files

`corpus.zig` treats every `.mo` under `programs/` as a program: its first line must be `# run:`, its output is `<name>.expected`, and the test expects exactly 3 programs (`expectEqual(@as(u32, 3), programs)`). `parse.mo`, `stats.mo`, and `report.mo` have no `main` and no `# run:` line, and `main.mo` cannot run alone (bug 1), so `zig build test` fails on `examples/programs/logstat/` for four reasons at once.

Workaround: the program-level check is the shell line in `examples/README.md`, `examples/programs/logstat/check.sh`.

## 3. MO0302 says "split it into modules", which bug 1 makes impossible, so no program over 500 lines can run

A file of 503 lines with a `main`:

```
long.mo:501:1: MO0302 this file is 503 lines long and the limit is 500; split it into modules.
  why: A file is at most 500 lines (chapter 2, shape laws), so a module is read in one sitting. The fix is a second module.
```

The law is right for a module, and the fix it names does not exist: a second module cannot be loaded (bug 1). Together they cap a runnable program at 500 lines. logstat's declarations alone are about 600 lines across four modules before any test, so the joined file of bug 1's workaround is refused too.

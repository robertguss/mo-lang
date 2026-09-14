# Toolchain bugs found while writing jobq

Recorded while writing program 1 (`mo-wiki/spec/programs/01-job-queue.md`, brief `mo-wiki/plans/program-1.md`), whose write scope was `examples/`. None is fixed here; each has a reproduction, what it cost jobq, and the workaround jobq uses. The `mo` is `toolchain/zig-out/bin/mo` (ReleaseSafe) built from `881c870`, on an Apple M-series machine.

## 1. `mo check --recipe` counts the recipe's tests against the implementation's 500-line law

A module that `mo check` and `mo test` accept is refused by `mo check --recipe` with `MO0302` when the file and the recipe's tests together pass 500 lines, and the line the diagnostic points at is a line of the recipe, not of the file. The file law is about a file a reader reads in one sitting; the recipe's tests are not in it.

Reproduction: `examples/programs/jobq/store.mo` at 457 lines (the store recipe implemented, with two functions and two tests beyond `notes`'s copy), then:

```
$ mo check jobq/store.mo                                  # exit 0
$ mo check --recipe Recipes.Store.Store jobq/store.mo
jobq/store.mo with recipe Recipes.Store.Store:502:1: MO0302 this file is 515 lines long and the limit is 500; split it into modules.
    assert fs.read_lines(log(whole), within: 1.minute) is Ok(lines)
  ^
```

The line quoted is the recipe's test "a last line cut short is left out, and a compacted store takes changes again" (`examples/recipes/store.mo`), and the corpus test runs the same check for every file whose first line says `# recipe:`, so the whole suite goes red.

What it cost jobq: one loop, and two of `notes`'s copied tests ("a store opened again from its log holds as many keys as before it stopped", "a store writing to another log keeps its keys and leaves the first log alone"), removed so the file is 431 lines and the file plus the recipe's tests fit; what they covered is covered by the recipe's own tests and by jobq's "many pairs go to the log in one append, and another log replays over the first". Workaround: keep a recipe implementation under 500 less the recipe's test lines (about 430 for `Recipes.Store`).

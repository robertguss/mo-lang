# jobq: toolchain bugs

What writing `jobq` (program 1, round 7 of the control run) found in the toolchain. Nothing in `toolchain/` was changed.

No toolchain bug was found. Every failed `mo check` or `mo test` run while writing the program was the program's or its tests' own mistake, or a law the checker enforced as written (`examples/GAPS.md` records the gaps the program met).

One behavior looked like a bug and is not: a test's `Clock.fixture()` does not move while a fixture call waits, so a lease never runs out on a running queue in a test. Grammar §8 says the fixture clock is frozen, so it is recorded in `GAPS.md` as a gap, not here. The reproduction, for whoever settles the gap:

```
test "the clock moves across a fixture call that waits 200 ms"
  keeper = Keeper.start()
  clock = Clock.fixture()
  before = clock.now
  assert Fs.fixture(delay: 200.ms).list(within: 1.minute) is Ok(_)
  assert keeper.ask(Poke, within: 1.minute) is Ok(_)
  after = clock.now
  assert after - before >= 200.ms
end
```

`mo test` and `mo test --sim 5`: `assert after - before >= 200.ms failed; left = 0.ms, right = 200.ms`.

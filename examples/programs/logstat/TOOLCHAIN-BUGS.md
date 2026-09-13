# Toolchain bugs found while writing logstat

Recorded while writing program 2 (`mo-wiki/spec/programs/02-log-analyzer.md`, brief `mo-wiki/plans/program-2.md`), round 3 of the control run, on branch `control3-mo`. The write scope was `examples/`, so none is fixed here: each has a minimal reproduction and the workaround logstat uses. `mo` is `toolchain/zig-out/bin/mo` built from `2580ecf` (ReleaseSafe).

## 1. `any(T)` ignores a refinement: a generated value breaks its own type's `where`

`any(Code)` for `type Code = UInt16 where value >= 100 and value <= 599` generates `0`, and so does a `Code` field of a generated struct. The value then reaches the code under test as a `Code` without its refinement ever being checked, so a property sees values the type says cannot exist.

```
module Probe.Refined
expose Code, Row

intent "probe: any(Row) and a refined field"

type Code = UInt16 where value >= 100 and value <= 599

struct Row
  code: Code
end

property "a generated row's code is in its refinement"
  for row in any(Row)
    assert row.code >= 100 and row.code <= 599
  end
end

property "a generated code is in its refinement"
  for code in any(Code)
    assert code >= 100 and code <= 599
  end
end
```

```
FAIL  property "a generated row's code is in its refinement": seed 1299120134 with row = Row(code: 0): refined.mo:14:5: assert row.code >= 100 and row.code <= 599 failed
FAIL  property "a generated code is in its refinement": seed 1299120134 with code = 0: refined.mo:20:5: assert code >= 100 and code <= 599 failed
```

What it cost logstat: the `Logstat.Stats` property over `any(List(Record))` was handed records with `status: 65535` and `status: 0`, which `Logstat.Parse` can never produce. A guard (`if records.all?(...)`) would throw away almost every seed, so the property instead generates plain numbers (`any(UInt16)`, `any(UInt8)`) and builds each record and the top through the refined types itself, so every value it passes is one the program can hold.

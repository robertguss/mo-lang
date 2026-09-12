module Effects.Sim
expose label
use Mo.Sim
intent "Select the deterministic platform for a module with a pure test."

fn label(n: UInt32) : String
  "sample #{n}"
end

test "the same input gives the same label under the selected platform"
  first = label(3)
  second = label(3)
  assert first == second
  assert first == "sample 3"
end

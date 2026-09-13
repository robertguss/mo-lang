# run:
# exit: 70
module Programs.Runaway
expose depth

intent "A call past the depth limit crashes main with a report naming the function, as any crash does, and exits 70."

# A count of n goes n calls down.
fn depth(n: UInt64) : UInt64
  return 0 if n == 0
  1 + depth(n - 1)
end

fn main(platform: Platform)
  out = platform.stdout
  out.write_line("#{depth(9_998)} calls down")
  out.write_line("#{depth(20_000)} calls down")
end

test "a count goes as many calls down as it counts"
  assert depth(0) == 0
  assert depth(3) == 3
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run

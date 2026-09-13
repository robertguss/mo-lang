# run: 4 5 6
# exit: 70
module Programs.Halves
expose halve

intent "Contracts run in every build: an odd number handed to halve crashes the run, compiled or not."

fn halve(n: UInt64) : UInt64
  requires n % 2 == 0

  n / 2
end

fn main(platform: Platform)
  for arg in platform.args
    n = arg.to_u64 or 0
    platform.stdout.write_line("#{n} halves to #{halve(n)}")
  end
end

test "an even number halves"
  assert halve(4) == 2
end

test rejects "halving an odd number"
  halve(5)
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run

# run:
module Effects.RandomFixture
expose new_key, Keys, KeyMakers, main

intent "Random is a capability like Fs: platform.random is the OS's generator, passed down as a parameter; in a test Random.fixture() draws a stream from the run's seed, so a test that draws a key draws the same key every time it runs."

fn new_key(random: Random) : List(UInt8)
  random.bytes(32)
end

# A process holds a Random only when it is started with one.
process Keys(random: Random)
  state
    made: UInt64 = 0
  end

  message Make : List(UInt8)

  fn update(state, message)
    case message
      Make:
        state.made += 1
        new_key(random)
    end
  end
end

supervisor KeyMakers(random: Random)
  child Keys(random), restart: :always
end

fn main(platform: Platform)
  out = platform.stdout
  first = new_key(platform.random)
  second = new_key(platform.random)
  out.write_line("a key has #{first.size} bytes")
  out.write_line("two keys differ: #{first != second}")
  out.write_line("nothing drawn: #{platform.random.bytes(0) == []}")
end

test "a fixture draws the run's stream, so the test replays its bytes"
  random = Random.fixture()
  assert Hash.hex(random.bytes(8)) == "db9efde7e16bf8ef"
end

test "two fixtures in one run draw the same stream, and one fixture's draws go on along it"
  one = Random.fixture()
  two = Random.fixture()
  first = new_key(one)
  assert new_key(two) == first
  assert new_key(one) != first
  whole = Random.fixture().bytes(64)
  assert whole.take(32) == first
end

test "a process started with a fixture draws from it, and two draws differ"
  keys = Keys.start(Random.fixture())
  first = keys.ask(Make, within: 1.minute)
  second = keys.ask(Make, within: 1.minute)
  assert first is Ok(_)
  assert first != second
  case (first, second)
    (Ok(a), Ok(b)):
      assert a.size == 32 and b.size == 32
    _:
      assert true
  end
end

verified: types, contracts, tests (3), property (0 seeds), sim (100 runs)
          proven: not run

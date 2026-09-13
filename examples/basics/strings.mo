module Basics.Strings
expose greeting, letter

intent "Build text with interpolation, and count it in graphemes or in bytes."

fn greeting(name: String) : String
  "Hello, #{name}!"
end

fn letter(name: String, cents: UInt32) : String
  """
  Dear #{name},
  your refund of #{cents} cents is on its way.
  """
end

test "interpolation fills in the name"
  assert greeting("Ada") == "Hello, Ada!"
end

test "a multi-line string starts at its first line"
  assert letter("Ada", 500).starts_with?("Dear Ada,")
end

test "size counts graphemes and bytes counts bytes"
  word = "café"
  assert word.size == 4
  assert word.bytes.size == 5
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run

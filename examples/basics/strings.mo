module Basics.Strings
expose greeting, letter

intent "Build text with interpolation, count it in graphemes or in bytes, and write a character by its escape."

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

test "each escape is one character, and \\u{X} names any character by its code point"
  assert "\t".byte_size == 1 and "\r".byte_size == 1 and "\n".byte_size == 1
  assert "\\".byte_size == 1 and "\"".byte_size == 1 and "\#{".byte_size == 2
  assert "\u{85}".byte_size == 2 and "a\u{0}b".byte_size == 3
  assert "caf\u{E9}" == "café" and "\u{1F600}".byte_size == 4
end

verified: types, contracts, tests (4), property (0 seeds), sim (not run)
          proven: not run

module Basics.Strings
expose greet, stanza, sizes

intent "Interpolation, triple-quoted strings, size in graphemes vs bytes."

fn greet(name: String) : String
  "Hello #{name}"
end

fn stanza() : String
  """
  line
  """
end

fn sizes(s: String) : (UInt32, UInt32)
  (s.size, s.bytes)
end

test "interpolates and counts graphemes"
  s = stanza()
  assert greet("Mo") == "Hello Mo"
  assert s.size > 0
  assert sizes("a").0 == 1
end

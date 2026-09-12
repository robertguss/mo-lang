module Basics.Strings
expose greet, verse
intent "Interpolate strings and count graphemes separately from bytes."

fn greet(name: String) : String
  "Hello #{name}"
end

fn verse() : String
  """
  Hello
  Mo
  """
end

test "one accented grapheme has two UTF-8 bytes"
  assert greet("Mo") == "Hello Mo"
  assert "é".size == 1
  assert "é".bytes.size == 2
  assert verse().size > 0
end

module Rejects.UnknownEscape
expose tabbed

intent "A string knows a few escapes, and a backslash before any other letter is refused rather than read as that letter."

# expect MO0101: expected an escape a string knows after this backslash: \n, \t, \r, \\, \", \#, or \u{XXXX}, 1 to 6 hex digits naming a Unicode character; a backslash itself is written \\
fn tabbed(text: String) : String
  "#{text}\q"
end

test "a tab follows the text"
  assert tabbed("a") == "a\t"
end

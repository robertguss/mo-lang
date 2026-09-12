module Basics.Option
expose pick, label

intent "Some, None, or for a default, and case on Option."

fn pick(flag: Bool) : Option(UInt32)
  if flag
    Some(1)
  else
    None
  end
end

fn label(flag: Bool) : UInt32
  case pick(flag)
    Some(n): n
    None: 0
  end
end

test "or and case"
  assert (pick(true) or 9) == 1
  assert (pick(false) or 9) == 9
  assert label(true) == 1
  assert label(false) == 0
end

module Basics.Option
expose choose, describe
intent "Consume an optional value with a default or exhaustive matching."

fn choose(ready: Bool) : Option(UInt32)
  if ready
    Some(7)
  else
    None
  end
end

fn describe(value: Option(UInt32)) : String
  case value
    Some(n): "value #{n}"
    None: "missing"
  end
end

test "both optional outcomes are consumed"
  assert (choose(true) or 0) == 7
  assert (choose(false) or 0) == 0
  assert describe(choose(true)) == "value 7"
  assert describe(choose(false)) == "missing"
end

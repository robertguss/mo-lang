module Rejects.PositionalVariant
expose Reading, gap

intent "A variant's fields are matched by name, as they are built by name; a pattern by position does not parse."

# expect MO0101: expected field names: a variant's fields are matched by name, not by position; write Short(by: a, of: b)
enum Reading
  Short(by: UInt8, of: UInt8)
  Full
end

fn gap(r: Reading) : UInt8
  case r
    Short(a, b): b - a
    Full: 0
  end
end

test "a short reading's gap"
  assert gap(Short(by: 2, of: 5)) == 3
end

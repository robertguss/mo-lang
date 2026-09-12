module Types.Nested
expose LookupError, value_or
intent "Handle both layers of a result containing an optional value."

enum LookupError
  MissingSource
end

fn value_or(value: Result(Option(T), E), fallback: T) : T
  case value
    Ok(Some(item)): item
    Ok(None): fallback
    Error(_): fallback
  end
end

fn lookup(found: Bool) : Result(Option(UInt32), LookupError)
  if found
    Ok(Some(3))
  else
    Ok(None)
  end
end

test "present, absent, and failed lookups are consumed"
  assert value_or(lookup(true), 0) == 3
  assert value_or(lookup(false), 0) == 0
  assert value_or(Error(MissingSource), 0) == 0
end

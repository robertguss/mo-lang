module Types.Nested
expose LookupError, lookup, show

intent "Handle a lookup that can fail and can also find nothing, and keep the three outcomes apart."

enum LookupError
  Offline
end

fn lookup(online: Bool, name: String) : Result(Option(UInt32), LookupError)
  return Error(Offline) if !online
  case name
    "ada": Ok(Some(36))
    _: Ok(None)
  end
end

fn show(online: Bool, name: String) : String
  case lookup(online, name)
    Ok(Some(age)): "#{name} is #{age}"
    Ok(None): "no one is named #{name}"
    Error(Offline): "offline, try again later"
  end
end

test "every outcome has its own arm"
  assert show(true, "ada") == "ada is 36"
  assert show(true, "bob") == "no one is named bob"
  assert show(false, "ada") == "offline, try again later"
end

test "the nested value matches in one pattern"
  assert lookup(true, "ada") is Ok(Some(36))
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run

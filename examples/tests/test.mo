module Tests.Test
expose Signup, SignupError, signup

intent "Check behavior with assert, and pull a value out of a result while checking it."

struct Signup
  email: String
  age: UInt8
end

enum SignupError
  TooYoung(age: UInt8)
end

fn signup(email: String, age: UInt8) : Result(Signup, SignupError)
  return Error(TooYoung(age: age)) if age < 13
  Ok(Signup(email: email, age: age))
end

test "an adult signs up"
  assert signup("ada@example.com", 36) is Ok(user)
  assert user.email == "ada@example.com"
  assert user.age == 36
end

test "a child is turned away with the age they gave"
  assert signup("kid@example.com", 9) is Error(TooYoung(9))
end

# run: correct horse
module Effects.Password
expose stored, main

intent "A password is kept as Argon2id in a PHC string and checked against it: the hash is deterministic given its salt, so a test fixes the salt, and a string that is not one Password.hash writes, malformed or naming other parameters, checks to false instead of crashing."

# A real program draws the salt from platform.random; a fixed one makes the stored string replay.
fn stored(password: String) : String
  Password.hash(password, "0123456789abcdef".bytes)
end

fn main(platform: Platform)
  out = platform.stdout
  password = String.join(platform.args, " ")
  phc = stored(password)
  out.write_line(phc)
  out.write_line("verifies: #{Password.verify?(password, phc)}")
  other = "#{password}!"
  out.write_line("another verifies: #{Password.verify?(other, phc)}")
  salt = platform.random.bytes(16)
  fresh = Password.hash(password, salt)
  out.write_line("a random salt verifies: #{Password.verify?(password, fresh)}")
end

test "a hash with a fixed salt is the same PHC string every run"
  assert stored("password") == "$argon2id$v=19$m=65536,t=3,p=1$MDEyMzQ1Njc4OWFiY2RlZg$2vFngNy3PoYhRil/oXuBuGtIDzPAtn2u8PLHyAnFeXs"
end

test "the password verifies and another does not"
  phc = stored("password")
  assert Password.verify?("password", phc)
  assert !Password.verify?("passwore", phc)
  assert !Password.verify?("", phc)
end

test "a malformed or foreign PHC string verifies to false"
  phc = stored("password")
  assert !Password.verify?("password", "")
  assert !Password.verify?("password", "$argon2id$v=19$m=65536")
  assert !Password.verify?("password", phc.replace("argon2id", "argon2i"))
  assert !Password.verify?("password", phc.replace("t=3", "t=4"))
  assert !Password.verify?("password", phc.replace("m=65536", "m=1048576"))
  assert !Password.verify?("password", "#{phc}$")
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run

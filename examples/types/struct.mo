module Types.Struct
expose User, rename, visit

intent "Group named fields in a struct, build it by name, and change it only through a var copy."

struct User
  name: String
  email: String
  visits: UInt32
end

fn rename(user: User, name: String) : User
  var copy = user
  copy.name = name
  copy
end

fn visit(user: User) : User
  var copy = user
  copy.visits += 1
  copy
end

test "the copy changes and the original does not"
  ada = User(name: "Ada", email: "ada@example.com", visits: 0)
  renamed = rename(ada, "Ada L.")
  assert renamed.name == "Ada L."
  assert ada.name == "Ada"
end

test "a field on the copy can be added to"
  ada = User(name: "Ada", email: "ada@example.com", visits: 2)
  assert visit(ada).visits == 3
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run

module Types.Generics
expose first, label

intent "List(T) generic and a where T: Trait bound."

trait Named
  fn name(x: T) : String
end

fn first(xs: List(T)) : Option(T)
  xs.reduce(None, fn(acc, x) acc or Some(x) end)
end

fn label(x: T) : String where T: Named
  x.name
end

struct User
  name: String
end

impl Named for User
  fn name(x: User) : String
    x.name
  end
end

test "first of a list and a named bound"
  assert first([1, 2]) is Some(n)
  assert n == 1
  assert label(User(name: "Mo")) == "Mo"
end

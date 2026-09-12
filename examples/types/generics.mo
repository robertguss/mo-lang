module Types.Generics
expose first, same?, Equal
intent "Infer a generic element type and declare a trait bound when needed."

trait Equal
  fn equal?(left: T, right: T) : Bool
end

fn first(xs: List(T)) : Option(T)
  for x in xs
    return Some(x)
  end
  None
end

fn same?(left: T, right: T) : Bool where T: Equal
  equal?(left, right)
end

test "first works for different element types"
  assert (first([1, 2]) or 0) == 1
  assert (first(["Mo"]) or "") == "Mo"
  assert (first([]) or 7) == 7
end

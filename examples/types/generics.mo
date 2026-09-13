module Types.Generics
expose Weighed, Parcel, first, total_weight

intent "Write one function for many types with a type parameter, and bound it by a trait when the body needs one."

trait Weighed
  fn weight(item: Self) : UInt32
end

struct Parcel
  grams: UInt32
end

impl Weighed for Parcel
  fn weight(item: Parcel) : UInt32
    item.grams
  end
end

fn first(xs: List(T)) : Option(T)
  for x in xs
    return Some(x)
  end
  None
end

fn total_weight(xs: List(T)) : UInt32 where T: Weighed
  xs.reduce(0, fn(sum, x) sum + x.weight end)
end

test "first works for any element type"
  assert first([3, 4]) is Some(3)
  assert first(["a", "b"]) is Some("a")
end

test "the bound lets the body call weight"
  assert total_weight([Parcel(grams: 200), Parcel(grams: 50)]) == 250
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run

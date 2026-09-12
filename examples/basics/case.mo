module Basics.Case
expose Parcel, Weight, label
intent "Match nested data with guards, literals, and an ignored field."

enum Weight
  Grams(amount: UInt32)
end

enum Parcel
  Box(weight: Weight, note: String)
  Empty
end

fn label(parcel: Parcel) : String
  case parcel
    Box(weight: Grams(amount: 0), note: _): "empty box"
    Box(weight: Grams(amount: n), note: _) if n > 100: "heavy"
    Box(weight: Grams(amount: n), note: _): "#{n} grams"
    Empty: "no parcel"
  end
end

test "literal, guarded, and remaining variants match"
  assert label(Box(weight: Grams(amount: 0), note: "")) == "empty box"
  assert label(Box(weight: Grams(amount: 101), note: "")) == "heavy"
  assert label(Box(weight: Grams(amount: 2), note: "")) == "2 grams"
  assert label(Empty) == "no parcel"
end

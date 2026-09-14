module Basics.Option
expose find_price, price_or_zero, label, doubled

intent "Mark a value that may be missing with Option, and always say what happens when it is."

fn find_price(sku: String) : Option(UInt32)
  case sku
    "apple": Some(120)
    "pear": Some(95)
    _: None
  end
end

fn price_or_zero(sku: String) : UInt32
  find_price(sku) or 0
end

fn doubled(sku: String) : Option(UInt32)
  find_price(sku).map(fn(cents) cents * 2 end)
end

fn label(sku: String) : String
  case find_price(sku)
    Some(cents): "#{sku} costs #{cents} cents"
    None: "#{sku} is not sold here"
  end
end

test "or gives a default for None"
  assert price_or_zero("apple") == 120
  assert price_or_zero("kiwi") == 0
end

test "map changes the value inside a Some and leaves a None as it is"
  assert doubled("pear") == Some(190)
  assert doubled("kiwi") == None
  assert find_price("apple").map(fn(cents) "#{cents}c" end) == Some("120c")
end

test "case handles both forms"
  assert find_price("pear") is Some(95)
  assert label("kiwi") == "kiwi is not sold here"
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run

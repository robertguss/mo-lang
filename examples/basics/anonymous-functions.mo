module Basics.AnonymousFunctions
expose cheap, receipt_lines

intent "Pass a small unnamed function straight into a call, on one line or as a block."

fn cheap(prices: List(UInt32), limit: UInt32) : List(UInt32)
  prices.filter(fn(price) price <= limit end)
end

fn receipt_lines(prices: List(UInt32)) : List(String)
  prices.map(fn(price)
    tax = price / 10
    "#{price} + #{tax} tax"
  end)
end

test "the one-line form reads the limit it was given"
  assert cheap([50, 150, 90], 100) == [50, 90]
end

test "the block form runs every line for each item"
  assert receipt_lines([100, 250]) == ["100 + 10 tax", "250 + 25 tax"]
end

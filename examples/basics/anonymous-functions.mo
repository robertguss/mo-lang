module Basics.AnonymousFunctions
expose cheap, receipt_lines, counted

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

# A parameter named _ is left unread (step 28).
fn counted(prices: List(UInt32)) : UInt64
  prices.reduce(0, fn(count, _) count + 1 end)
end

test "the one-line form reads the limit it was given"
  assert cheap([50, 150, 90], 100) == [50, 90]
end

test "a parameter named _ is taken and never read"
  assert counted([50, 150, 90]) == 3
end

test "the block form runs every line for each item"
  assert receipt_lines([100, 250]) == ["100 + 10 tax", "250 + 25 tax"]
end

verified: types, contracts, tests (3), property (0 seeds), sim (not run)
          proven: not run

module Basics.Bindings
expose invoice

intent "Bind a name once with =, and use var only for a value that changes."

fn invoice(subtotal: UInt32, shipping: UInt32) : UInt32
  tax = subtotal / 10
  var total = subtotal
  total += tax
  total += shipping
  total
end

test "tax and shipping are each added once"
  assert invoice(1_000, 250) == 1_350
end

test "a var can be assigned and added to"
  var count = 1
  count += 2
  count = count * 2
  assert count == 6
end

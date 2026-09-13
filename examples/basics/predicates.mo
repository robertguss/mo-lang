module Basics.Predicates
expose Order, empty?, ready?

intent "Name a yes-or-no question with a trailing ?, and ask it with a dot."

struct Order
  items: UInt32
  paid: Bool
end

fn empty?(order: Order) : Bool
  order.items == 0
end

fn ready?(order: Order) : Bool
  order.paid and !order.empty?
end

test "a dot call and a plain call are the same call"
  order = Order(items: 2, paid: true)
  assert order.ready?
  assert ready?(order)
end

test "an unpaid order is not ready"
  order = Order(items: 2, paid: false)
  assert !order.ready?
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run

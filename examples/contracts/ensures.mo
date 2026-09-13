module Contracts.Ensures
expose Cart, CheckoutError, add, checkout

intent "Promise what a function gives back, in terms of its result and its inputs on entry."

struct Cart
  items: UInt32
  total: UInt32
end

enum CheckoutError
  EmptyCart
end

fn add(inout cart: Cart, price: UInt32) : UInt32
  ensures cart.items == old(cart.items) + 1
  ensures result == cart.total

  cart.items += 1
  cart.total += price
  cart.total
end

fn checkout(cart: Cart) : Result(UInt32, CheckoutError)
  ensures result is Ok(paid) implies paid == cart.total

  return Error(EmptyCart) if cart.items == 0
  Ok(cart.total)
end

test "add changes the cart the caller holds"
  var cart = Cart(items: 0, total: 0)
  assert add(cart, 500) == 500
  assert cart.items == 1
end

test "checkout pays the total or refuses an empty cart"
  assert checkout(Cart(items: 2, total: 900)) is Ok(900)
  assert checkout(Cart(items: 0, total: 0)) is Error(EmptyCart)
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run

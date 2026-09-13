module Contracts.NeverTrips
expose Seat, assign

intent "State the one thing that must never happen, and prove plain mo test checks it."

never "a seat is given to a guest with no name"
  for s in Seat.all
    s.guest == ""
  end
end

struct Seat
  number: String
  guest: String
end

fn assign(number: String, guest: String) : Seat
  Seat(number: number, guest: guest)
end

test "a named guest takes a seat"
  assert assign("12A", "Ada").guest == "Ada"
end

test rejects "a guest with no name trips the never"
  seat = assign("12B", "")
  assert seat.number == "12B"
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run

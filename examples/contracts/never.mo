module Contracts.Never
expose Booking, BookError, book

intent "Book seats one at a time, and state the one thing that must never happen."

never "a seat holds two bookings"
  for a in Booking.all, b in Booking.all if a.seat == b.seat
    a.guest != b.guest
  end
end

struct Booking
  seat: String
  guest: String
end

enum BookError
  SeatTaken(seat: String)
end

fn book(held: List(Booking), seat: String, guest: String) : Result(Booking, BookError)
  return Error(SeatTaken(seat: seat)) if held.map(fn(b) b.seat end).contains?(seat)
  Ok(Booking(seat: seat, guest: guest))
end

test "a free seat can be booked"
  held = [Booking(seat: "12A", guest: "Ada")]
  assert book(held, "12B", "Bob") is Ok(_)
end

test "a taken seat cannot be booked again"
  held = [Booking(seat: "12A", guest: "Ada")]
  assert book(held, "12A", "Bob") is Error(SeatTaken(seat: "12A"))
end

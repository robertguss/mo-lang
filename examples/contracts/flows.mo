module Contracts.Flows
expose CardNumber, CardEvent, digits

intent "flows(CardNumber, into: Events) beside a struct that carries one."

struct CardNumber
  digits: String
end

struct CardEvent
  card: CardNumber
end

never "a card number reaches an event"
  flows(CardNumber, into: Events)
end

fn digits(c: CardNumber) : String
  c.digits
end

test "a card number is just digits"
  c = CardNumber(digits: "4242")
  assert digits(c) == "4242"
end

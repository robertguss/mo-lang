module Contracts.Flows
expose CardNumber, Card, last_four
intent "Keep a card number out of the Events capability."

never "a card number reaches an event"
  flows(CardNumber, into: Events)
end

type CardNumber = UInt64

struct Card
  number: CardNumber
end

fn last_four(card: Card) : UInt64
  card.number % 10_000
end

test "card data can be used without emitting an event"
  card = Card(number: 1234_5678)
  assert last_four(card) == 5678
end

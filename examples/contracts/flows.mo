module Contracts.Flows
expose CardNumber, Payment, Receipt, receipt

intent "Carry a card number where it is needed, and prove it never reaches the event log."

never "a card number reaches an event"
  flows(CardNumber, into: Events)
end

type CardNumber = String where value.size == 16

struct Payment
  card: CardNumber
  cents: UInt32
end

struct Receipt
  cents: UInt32
end

fn receipt(payment: Payment) : Receipt
  Receipt(cents: payment.cents)
end

test "a receipt keeps the amount and leaves the card behind"
  payment = Payment(card: "4242424242424242", cents: 500)
  assert receipt(payment) == Receipt(cents: 500)
end

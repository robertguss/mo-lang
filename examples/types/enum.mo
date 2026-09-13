module Types.Enum
expose Payment, fee, label

intent "List every form a value can take, with data on the forms that need it, and handle each one."

enum Payment
  Cash
  Card(last4: String)
  Transfer(bank: String, days: UInt32)
end

fn fee(payment: Payment, amount: UInt32) : UInt32
  case payment
    Cash: 0
    Card(_): amount / 50
    Transfer(bank: _, days: n): n * 25
  end
end

fn label(payment: Payment) : String
  case payment
    Cash: "cash"
    Card(digits): "card ending #{digits}"
    Transfer(bank: name, days: _): "transfer from #{name}"
  end
end

test "each form has its own fee"
  assert Cash.fee(1_000) == 0
  assert Card(last4: "4242").fee(1_000) == 20
  assert Transfer(bank: "Acme Bank", days: 2).fee(1_000) == 50
end

test "data carried by a variant can be read back"
  assert Card(last4: "4242").label == "card ending 4242"
end

verified: types, contracts, tests (2), property (0 seeds), sim (not run)
          proven: not run

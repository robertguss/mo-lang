module Types.Enum
expose Delivery, describe
intent "Give each enum variant its own named data and match every variant."

enum Delivery
  Waiting
  Sent(code: UInt32)
  Failed(reason: String)
end

fn describe(delivery: Delivery) : String
  case delivery
    Waiting: "waiting"
    Sent(code: n): "sent #{n}"
    Failed(reason: text): text
  end
end

test "all delivery variants have a description"
  assert describe(Waiting) == "waiting"
  assert describe(Sent(code: 8)) == "sent 8"
  assert describe(Failed(reason: "closed")) == "closed"
end

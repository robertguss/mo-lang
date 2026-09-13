module Contracts.PropertyRefined
expose Percent, Status, share, class_of

intent "A property over a refined type is handed only the values its where admits, so a claim about a Percent never sees 65,535."

type Percent = UInt16 where value <= 100

# Few UInt16 values are a status code, so any(Status) generates from the where's bounds.
type Status = UInt16 where value >= 100 and value <= 599

fn share(total: UInt16, part: Percent) : UInt16
  total / 100 * part
end

fn class_of(status: Status) : UInt16
  status / 100
end

property "a share of a total is never more than the total"
  for total in any(UInt16), part in any(Percent)
    assert share(total, part) <= total
  end
end

property "every status is in one of the five classes"
  for status in any(Status)
    assert class_of(status) >= 1 and class_of(status) <= 5
  end
end

verified: types, contracts, tests (2), property (200 seeds), sim (not run)
          proven: not run

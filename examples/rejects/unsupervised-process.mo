module Rejects.UnsupervisedProcess
expose Counter, increment
intent "Every process must belong to a supervisor."
# expect error: Counter is declared without a supervising parent.

fn increment(n: UInt32) : UInt32
  n + 1
end

process Counter() mailbox: 4
  state
    count: UInt32
  end
  message Increment
  fn update(state, message)
    case message
      Increment:
        state.count = increment(state.count)
    end
  end
end

test "testing an update helper does not provide supervision"
  assert increment(0) == 1
end

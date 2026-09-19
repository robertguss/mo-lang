module Audit.MailboxOverflow
intent "Probe an out-of-range mailbox bound."
process Counter() mailbox: 4294967296
  state
    count: UInt64
  end
  message Count : UInt64
  fn update(state, message)
    case message
      Count: state.count
    end
  end
end
supervisor Counters
  child Counter, restart: :always
end
fn main(platform: Platform)
  platform.stdout.write("ok\n")
end

module Audit.MailboxControl
intent "Probe an in-range mailbox bound."
process Counter() mailbox: 100
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

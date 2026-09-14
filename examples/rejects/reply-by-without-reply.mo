module Rejects.ReplyByWithoutReply
expose Keeper, Keepers

intent "reply_by is the deadline of the ask an arm answers; a message with no reply has no asker, so its arm has no reply_by and its calls take a Duration."

# expect MO0201: there is no reply_by in scope
process Keeper(fs: Fs)
  state
    kept: UInt32
  end

  message Keep

  fn update(state, message)
    case message
      Keep:
        if fs.append("kept.log", "one\n", within: reply_by) is Ok(_)
          state.kept += 1
        end
    end
  end
end

supervisor Keepers(fs: Fs)
  child Keeper(fs), restart: :always
end

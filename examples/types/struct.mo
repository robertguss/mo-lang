module Types.Struct
expose Ticket, close
intent "Construct named fields and update a local copy of a struct."

struct Ticket
  id: UInt32
  closed: Bool
end

fn close(ticket: Ticket) : Ticket
  var copy = ticket
  copy.closed = true
  copy
end

test "closing a copy preserves the original"
  ticket = Ticket(id: 7, closed: false)
  closed = close(ticket)
  assert closed == Ticket(id: 7, closed: true)
  assert !ticket.closed
end

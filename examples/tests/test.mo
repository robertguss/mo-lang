module Tests.Test
expose TicketError, ticket
use Types.Struct{Ticket}
intent "Assert a Result pattern and then inspect the bound success value."

enum TicketError
  Missing
end

fn ticket(id: UInt32) : Result(Ticket, TicketError)
  return Error(Missing) if id == 0
  Ok(Ticket(id: id, closed: false))
end

test "a successful pattern assertion binds the ticket"
  assert ticket(7) is Ok(c)
  assert c.id == 7
  assert !c.closed
end

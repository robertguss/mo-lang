module Rejects.IsInsideComparison
expose same_outcome?

intent "`is` and a comparison share one level, so an `is` compared with something takes parentheses."

# expect MO0101: expected the end of the `is`: `is` binds loosely inside a comparison, so read is Ok(_) == wrote compares nothing; put the `is` in parentheses: (read is Ok(_)) == wrote
fn same_outcome?(read: Result(String, FsError), wrote: Bool) : Bool
  read is Ok(_) == wrote
end

test "a read that worked matches a write that worked"
  assert same_outcome?(Ok("x"), true)
end

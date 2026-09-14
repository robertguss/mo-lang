module Types.KeywordFields
expose Task, Revision, Tracker, Trackers, shown, revised, settled, first_over

intent "A struct's field may be named state or old, and outside a process, an ensures, and an invariant state, result, and old are names like any other: a parameter, a binding, a var, and a for name, while state alone is still a process's state."

# A task's state is a field of its own.
struct Task
  name: String
  state: String
end

# A revision keeps the old text beside the new.
struct Revision
  old: String
  new: String
end

# A process whose state holds a task: `state` alone is the process's, `.state` the task's.
process Tracker()
  state
    task: Task = Task(name: "build", state: "queued")
  end

  message Move(to: String)
  message Look : String

  fn update(state, message)
    case message
      Move(to):
        state.task.state = to
      Look: state.task.state
    end
  end
end

supervisor Trackers
  child Tracker, restart: :always
end

fn shown(task: Task) : String
  "#{task.name} is #{task.state}"
end

fn revised(revision: Revision, text: String) : Revision
  var next = revision
  next.old = revision.new
  next.new = text
  next
end

# Outside a process state is a name, and outside an ensures result is one (step 27).
fn settled(state: String, result: Option(UInt32)) : String
  count = result or 0
  "#{state} after #{count}"
end

# Outside an ensures and an invariant old is a name, here a for's; result is a var.
fn first_over(ages: List(UInt32), limit: UInt32) : UInt32
  ensures result == 0 or result > limit

  var result = 0
  for old in ages
    if old > limit
      result = old
      break
    end
  end
  result
end

test "a field named state is given by name and read after a dot"
  task = Task(name: "build", state: "running")
  assert task.state == "running"
  assert shown(task) == "build is running"
end

test "a field named old is set on a var copy and read after a dot"
  revision = revised(Revision(old: "a", new: "b"), "c")
  assert revision.old == "b" and revision.new == "c"
end

test "Json.encode writes each field's key as it is named"
  task = Json.encode(Task(name: "build", state: "done"))
  assert task == "{\"name\": \"build\", \"state\": \"done\"}"
  assert Json.encode(Revision(old: "a", new: "b")) == "{\"old\": \"a\", \"new\": \"b\"}"
end

test "state and result name a parameter and a binding, and old a for's name"
  state = "done"
  assert settled(state, Some(3)) == "done after 3"
  result = first_over([3, 9, 12], 8)
  assert result == 9 and first_over([1], 8) == 0
end

test "a process's state holds a task whose state moves"
  tracker = Tracker.start()
  tracker.send(Move(to: "running"))
  assert tracker.ask(Look, within: 1.minute) == Ok("running")
end

verified: types, contracts, tests (5), property (0 seeds), sim (100 runs)
          proven: not run

module Step44.Chunks
expose Seen, Collector, Collectors, bounded?

intent "Read exact bounded byte chunks through the runtime source: available short data is delivered while the peer stays open, retained pull-read bytes come first, and EOF follows pending bytes."

struct Seen
  bytes: List(UInt8)
  sizes: List(UInt64)
  closed: Bool
  idle: Bool
end

process Collector() mailbox: 8
  state
    bytes: List(UInt8)
    sizes: List(UInt64)
    closed: Bool
    idle: Bool
    waiting: List(Reply(Seen))
    want_bytes: UInt64
    want_closed: Bool
    want_idle: Bool
  end

  message Chunk(bytes: List(UInt8))
  message Closed
  message Idle
  message Snapshot : Seen
  message Await(me: Handle(Collector), bytes: UInt64, closed: Bool, idle: Bool) : Seen
  message Check

  fn update(state, message)
    case message
      Chunk(bytes):
        state.bytes = state.bytes.concat(bytes)
        state.sizes = state.sizes.push(bytes.size)
        if state.waiting.size > 0 and state.bytes.size >= state.want_bytes and state.closed == state.want_closed and state.idle == state.want_idle
          seen = Seen(bytes: state.bytes, sizes: state.sizes, closed: state.closed,
            idle: state.idle)
          for waiter in state.waiting
            waiter.answer(seen)
          end
          state.waiting = []
        end
      Closed:
        state.closed = true
        if state.waiting.size > 0 and state.bytes.size >= state.want_bytes and state.closed == state.want_closed and state.idle == state.want_idle
          seen = Seen(bytes: state.bytes, sizes: state.sizes, closed: state.closed,
            idle: state.idle)
          for waiter in state.waiting
            waiter.answer(seen)
          end
          state.waiting = []
        end
      Idle:
        state.idle = true
        if state.waiting.size > 0 and state.bytes.size >= state.want_bytes and state.closed == state.want_closed and state.idle == state.want_idle
          seen = Seen(bytes: state.bytes, sizes: state.sizes, closed: state.closed,
            idle: state.idle)
          for waiter in state.waiting
            waiter.answer(seen)
          end
          state.waiting = []
        end
      Snapshot: Seen(bytes: state.bytes, sizes: state.sizes, closed: state.closed, idle: state.idle)
      Await(me: me, bytes: bytes, closed: closed, idle: idle):
        state.want_bytes = bytes
        state.want_closed = closed
        state.want_idle = idle
        state.waiting = state.waiting.push(reply_to)
        me.send(Check)
      Check:
        if state.waiting.size > 0 and state.bytes.size >= state.want_bytes and state.closed == state.want_closed and state.idle == state.want_idle
          seen = Seen(bytes: state.bytes, sizes: state.sizes, closed: state.closed,
            idle: state.idle)
          for waiter in state.waiting
            waiter.answer(seen)
          end
          state.waiting = []
        end
    end
  end
end

supervisor Collectors
  child Collector, restart: :always
end

fn bounded?(sizes: List(UInt64), max: UInt64) : Bool
  sizes.all?(fn(n) n > 0 and n <= max end)
end

test "available short bytes arrive while the peer stays open"
  net = Net.fixture()
  assert net.listen(0, within: 1.minute) is Ok(listener)
  assert net.connect("localhost", listener.port, within: 1.minute) is Ok(client)
  assert listener.accept(within: 1.minute) is Ok(server)
  collector = Collector.start()
  server.chunks(into: collector, max_bytes: 8, idle: 1.minute)
  assert client.write("abc", within: 1.minute) is Ok(_)
  assert collector.ask(Await(me: collector, bytes: 3, closed: false, idle: false),
    within: 1.minute) is Ok(seen)
  assert seen.bytes == "abc".bytes
  assert bounded?(seen.sizes, 8)
  assert !seen.closed and !seen.idle
end

test "bytes retained after read_line are delivered first"
  net = Net.fixture()
  assert net.listen(0, within: 1.minute) is Ok(listener)
  assert net.connect("localhost", listener.port, within: 1.minute) is Ok(client)
  assert listener.accept(within: 1.minute) is Ok(server)
  assert client.write("head\nbody", within: 1.minute) is Ok(_)
  assert server.read_line(within: 1.minute) == Ok(Some("head"))
  collector = Collector.start()
  server.chunks(into: collector, max_bytes: 2, idle: 1.minute)
  assert collector.ask(Await(me: collector, bytes: 4, closed: false, idle: false),
    within: 1.minute) is Ok(seen)
  assert seen.bytes == "body".bytes
  assert bounded?(seen.sizes, 2)
end

test "pending bytes precede one Closed"
  net = Net.fixture()
  assert net.listen(0, within: 1.minute) is Ok(listener)
  assert net.connect("localhost", listener.port, within: 1.minute) is Ok(client)
  assert listener.accept(within: 1.minute) is Ok(server)
  collector = Collector.start()
  server.chunks(into: collector, max_bytes: 2, idle: 1.minute)
  assert client.write("tail", within: 1.minute) is Ok(_)
  client.close
  assert collector.ask(Await(me: collector, bytes: 4, closed: true, idle: false),
    within: 1.minute) is Ok(seen)
  assert seen.bytes == "tail".bytes
  assert seen.closed and !seen.idle
  assert bounded?(seen.sizes, 2)
end

test "mailbox backpressure preserves copied chunks and one end"
  net = Net.fixture()
  assert net.listen(0, within: 1.minute) is Ok(listener)
  assert net.connect("localhost", listener.port, within: 1.minute) is Ok(client)
  assert listener.accept(within: 1.minute) is Ok(server)
  collector = Collector.start()
  server.chunks(into: collector, max_bytes: 1, idle: 1.minute)
  whole = "x".repeat(100)
  assert client.write(whole, within: 1.minute) is Ok(_)
  client.close
  assert collector.ask(Await(me: collector, bytes: 100, closed: true, idle: false),
    within: 1.minute) is Ok(seen)
  assert seen.bytes == whole.bytes and seen.sizes.size == 100
  assert seen.closed and !seen.idle and bounded?(seen.sizes, 1)
end

test "idle closes an unread connection"
  net = Net.fixture()
  assert net.listen(0, within: 1.minute) is Ok(listener)
  assert net.connect("localhost", listener.port, within: 1.minute) is Ok(client)
  assert listener.accept(within: 1.minute) is Ok(server)
  collector = Collector.start()
  server.chunks(into: collector, max_bytes: 8, idle: 0.ms)
  assert collector.ask(Await(me: collector, bytes: 0, closed: false, idle: true),
    within: 1.minute) is Ok(seen)
  assert seen.bytes == [] and !seen.closed and seen.idle
  assert client.write("late", within: 1.minute) is Error(Closed)
end

test "a local full close stops without a synthetic end message"
  net = Net.fixture()
  assert net.listen(0, within: 1.minute) is Ok(listener)
  assert net.connect("localhost", listener.port, within: 1.minute) is Ok(_)
  assert listener.accept(within: 1.minute) is Ok(server)
  collector = Collector.start()
  server.chunks(into: collector, max_bytes: 8, idle: 1.minute)
  server.close
  assert collector.ask(Snapshot, within: 1.minute) is Ok(seen)
  assert seen.bytes == [] and !seen.closed and !seen.idle
end

test "the maximum accepted chunk bound still delivers"
  net = Net.fixture()
  assert net.listen(0, within: 1.minute) is Ok(listener)
  assert net.connect("localhost", listener.port, within: 1.minute) is Ok(client)
  assert listener.accept(within: 1.minute) is Ok(server)
  collector = Collector.start()
  server.chunks(into: collector, max_bytes: 65_536, idle: 1.minute)
  assert client.write("upper", within: 1.minute) is Ok(_)
  client.close
  assert collector.ask(Await(me: collector, bytes: 5, closed: true, idle: false),
    within: 1.minute) is Ok(seen)
  assert seen.bytes == "upper".bytes and seen.closed
  assert bounded?(seen.sizes, 65_536)
end

test "a pull read is Busy after chunks owns input"
  net = Net.fixture()
  assert net.listen(0, within: 1.minute) is Ok(listener)
  assert net.connect("localhost", listener.port, within: 1.minute) is Ok(_)
  assert listener.accept(within: 1.minute) is Ok(server)
  server.chunks(into: Collector.start(), max_bytes: 8, idle: 1.minute)
  assert server.read_line(within: 1.minute) is Error(Busy)
end

verified: types, contracts, tests (8), property (0 seeds), sim (not run)
          proven: not run

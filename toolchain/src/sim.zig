//! Mo.Sim: the deterministic scheduler `mo test` runs processes on (design-v0/03,
//! processes and failure; 08, the milestone). One thread and one fixed order: no green
//! threads, and no clock that moves by itself. A test's sends are delivered before its
//! next statement runs (bytecode `settle`); `ask` runs the target's waiting messages,
//! then its own. `update` is a transaction: a crash discards that message's state
//! writes and its buffered sends and emits, the supervisor restarts the process from
//! its initial state, and the crash is kept with its complete report.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const contracts = @import("contracts.zig");
const vm_mod = @import("vm.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Error = vm_mod.Error;
const none = bytecode.none;

/// A child line with no max_restarts: three restarts within five seconds.
pub const default_max_restarts: u32 = 3;
pub const default_window_ms: i64 = 5_000;
/// Deliveries one settle makes before the processes count as never settling.
pub const settle_limit: u32 = 1_000_000;
/// `Proc.supervisor` of a process a test started directly: the test runner.
pub const test_runner: u32 = none;

pub const Policy = struct { restart: bytecode.Restart, max_restarts: u32, window_ms: i64 };

const Entry = struct { message: Value, seq: u64 };
const Outgoing = struct { to: u32, message: Value };

pub const Proc = struct {
    /// Index in `Program.processes`.
    process: u32,
    args: []const Value,
    state: Value,
    /// Index in `Sim.supervisors`, or `test_runner`.
    supervisor: u32,
    policy: Policy,
    mailbox: std.ArrayList(Entry) = .empty,
    head: usize = 0,
    /// Every message since the last (re)start, the running one included.
    log: std.ArrayList(Value) = .empty,
    /// When each restart inside the current window happened.
    restarts: std.ArrayList(i64) = .empty,
    up: bool = true,
    /// Its update is on the stack.
    busy: bool = false,
    /// Sends and emits of the running update, delivered only when it commits.
    outbox: std.ArrayList(Outgoing) = .empty,
    emits: std.ArrayList(Value) = .empty,

    pub fn queued(p: *const Proc) usize {
        return p.mailbox.items.len - p.head;
    }
};

pub const Supervisor = struct { index: u32 };

pub const Sim = struct {
    gpa: std.mem.Allocator,
    vm: *Vm,
    /// The run's seed, named in every crash report.
    seed: u64,
    /// The test the run belongs to: the sender of every message sent from outside a process.
    test_name: []const u8,
    /// `clock.now`: frozen for a whole update, and in this step for the whole run.
    now: i64 = vm_mod.fixture_time,
    procs: std.ArrayList(Proc) = .empty,
    supervisors: std.ArrayList(Supervisor) = .empty,
    /// The process whose update is running, innermost.
    running: ?u32 = null,
    next_seq: u64 = 0,
    /// Every process crash, in order, each report complete.
    crashes: std.ArrayList(contracts.Report) = .empty,
    /// A supervisor gave up: `Vm.report` says which, and the run stops.
    gave_up: bool = false,
    /// Events emitted by committed updates and by the test, in order.
    events: std.ArrayList(Value) = .empty,

    pub fn init(vm: *Vm, seed: u64, test_name: []const u8) Sim {
        return .{ .gpa = vm.gpa, .vm = vm, .seed = seed, .test_name = test_name };
    }

    pub fn firstCrash(sim: *const Sim) ?contracts.Report {
        return if (sim.crashes.items.len > 0) sim.crashes.items[0] else null;
    }

    pub fn nameOf(sim: *const Sim, id: u32) []const u8 {
        return sim.vm.program.processes[sim.procs.items[id].process].name;
    }

    // ---- starting

    /// `Name.start(args)` in a test: the test runner supervises it with :always, and with
    /// the max_restarts of the first child line in the module that names the process.
    pub fn start(sim: *Sim, process: u32, args: []const Value) Error!u32 {
        var policy: Policy = .{ .restart = .always, .max_restarts = default_max_restarts, .window_ms = default_window_ms };
        for (sim.vm.program.supervisors) |s| for (s.children) |c| {
            if (c.process == process and c.max_restarts != none) {
                policy = .{ .restart = .always, .max_restarts = c.max_restarts, .window_ms = try sim.window(c) };
                break;
            }
        };
        return sim.startUnder(process, args, test_runner, policy);
    }

    /// Starts supervisors[index]: each child in order, with the arguments its line passes.
    pub fn startSupervisor(sim: *Sim, index: u32, args: []const Value) Error!u32 {
        const s = sim.vm.program.supervisors[index];
        const sid: u32 = @intCast(sim.supervisors.items.len);
        try sim.supervisors.append(sim.gpa, .{ .index = index });
        for (s.children) |c| {
            const child_args = (try sim.vm.call(c.args, args)).tuple;
            const max = if (c.max_restarts == none) default_max_restarts else c.max_restarts;
            _ = try sim.startUnder(c.process, child_args, sid, .{ .restart = c.restart, .max_restarts = max, .window_ms = try sim.window(c) });
        }
        return sid;
    }

    fn window(sim: *Sim, c: bytecode.Child) Error!i64 {
        if (c.per == none) return default_window_ms;
        return (try sim.vm.call(c.per, &.{})).duration;
    }

    /// A state that cannot be built crashes whoever called start: the process never began.
    fn startUnder(sim: *Sim, process: u32, args: []const Value, supervisor: u32, policy: Policy) Error!u32 {
        const state = try sim.vm.call(sim.vm.program.processes[process].init, args);
        const id: u32 = @intCast(sim.procs.items.len);
        try sim.procs.append(sim.gpa, .{ .process = process, .args = args, .state = state, .supervisor = supervisor, .policy = policy });
        return id;
    }

    // ---- messages

    /// `h.send(message)`: never blocks. From inside an update the message waits in the
    /// sender's outbox until the update commits. A target that is down drops it.
    pub fn send(sim: *Sim, to: u32, message: Value) Error!void {
        if (!sim.procs.items[to].up) return;
        try sim.roomFor(to, message);
        if (sim.running) |from| {
            try sim.procs.items[from].outbox.append(sim.gpa, .{ .to = to, .message = message });
        } else _ = try sim.enqueue(to, message);
    }

    /// `h.ask(message, within: d)`: the target's waiting messages run, then this one, and
    /// the reply is the value of its arm. `Timeout` when the target's fixtures are slower
    /// than `d`; `Down` when the target is down or crashed before replying.
    pub fn ask(sim: *Sim, to: u32, message: Value, within: i64) Error!Value {
        if (!sim.procs.items[to].up) return sim.askError("Down");
        // A target whose update is on the stack is waiting on this very call.
        if (sim.procs.items[to].busy) return sim.askError("Timeout");
        try sim.roomFor(to, message);
        const seq = try sim.enqueue(to, message);
        const reply = while (true) {
            const p = &sim.procs.items[to];
            // A restart empties the mailbox, this message with it.
            if (!p.up or p.queued() == 0 or p.mailbox.items[p.head].seq > seq) return sim.askError("Down");
            const d = try sim.deliver(to);
            if (d.seq == seq) break d.reply orelse return sim.askError("Down");
        };
        if (sim.delayOf(to) > within) return sim.askError("Timeout");
        return sim.vm.variant("Ok", &.{reply});
    }

    /// Delivers waiting messages, one per process per round in start order, until every
    /// mailbox is empty.
    pub fn settle(sim: *Sim) Error!void {
        var delivered: u32 = 0;
        var progressed = true;
        while (progressed) {
            progressed = false;
            var id: u32 = 0;
            while (id < sim.procs.items.len) : (id += 1) {
                const p = &sim.procs.items[id];
                if (!p.up or p.busy or p.queued() == 0) continue;
                _ = try sim.deliver(id);
                progressed = true;
                delivered += 1;
                if (delivered == settle_limit) {
                    sim.vm.report = .{ .kind = .other, .clause = "the processes did not settle: a million messages delivered and mailboxes still waiting", .within = sim.test_name, .at = 0 };
                    return error.Crash;
                }
            }
        }
    }

    /// `events.emit(e)`: inside an update it waits for the commit, like a send.
    pub fn emit(sim: *Sim, event: Value) Error!void {
        if (sim.running) |id| {
            try sim.procs.items[id].emits.append(sim.gpa, event);
        } else try sim.events.append(sim.gpa, event);
    }

    fn enqueue(sim: *Sim, to: u32, message: Value) Error!u64 {
        const seq = sim.next_seq;
        sim.next_seq += 1;
        try sim.procs.items[to].mailbox.append(sim.gpa, .{ .message = message, .seq = seq });
        return seq;
    }

    /// A mailbox at its bound crashes the sender, and the report names both (d33).
    fn roomFor(sim: *Sim, to: u32, message: Value) Error!void {
        const target = sim.procs.items[to];
        var waiting = target.queued();
        if (sim.running) |from| {
            for (sim.procs.items[from].outbox.items) |o| waiting += @intFromBool(o.to == to);
        }
        const bound = sim.vm.program.processes[target.process].mailbox;
        if (waiting < bound) return;
        const from_name = if (sim.running) |from| sim.nameOf(from) else try std.fmt.allocPrint(sim.gpa, "the test \"{s}\"", .{sim.test_name});
        const values = try sim.gpa.alloc(contracts.Involved, 1);
        values[0] = .{ .name = "message", .value = try sim.vm.render(message) };
        sim.vm.report = .{
            .kind = .mailbox,
            .clause = try std.fmt.allocPrint(sim.gpa, "{s} sent to {s}, whose mailbox is full at its bound of {d}", .{ from_name, sim.nameOf(to), bound }),
            .within = from_name,
            .at = 0,
            .values = values,
        };
        return error.Crash;
    }

    fn askError(sim: *Sim, name: []const u8) Error!Value {
        return sim.vm.variant("Error", &.{try sim.vm.variant(name, &.{})});
    }

    /// The slowest fixture the process was started with.
    fn delayOf(sim: *const Sim, id: u32) i64 {
        var delay: i64 = 0;
        for (sim.procs.items[id].args) |a| if (a == .cap) {
            delay = @max(delay, a.cap.delay);
        };
        return delay;
    }

    // ---- one message

    const Delivered = struct { seq: u64, reply: ?Value };

    /// Runs the next message in the mailbox of `id` as one transaction. A null reply
    /// means the process crashed on it.
    fn deliver(sim: *Sim, id: u32) Error!Delivered {
        const vm = sim.vm;
        var p = &sim.procs.items[id];
        const entry = p.mailbox.items[p.head];
        p.head += 1;
        if (p.head == p.mailbox.items.len) {
            p.mailbox.clearRetainingCapacity();
            p.head = 0;
        }
        try p.log.append(sim.gpa, entry.message);
        const before = p.state;
        const base = vm.stack.items.len;
        const outer = sim.running;
        sim.running = id;
        p.busy = true;
        const result = sim.update(id, entry.message, before);
        // An update may start processes, so the pointer is taken again.
        p = &sim.procs.items[id];
        p.busy = false;
        sim.running = outer;
        const after = result catch |err| switch (err) {
            error.Crash => {
                vm.stack.shrinkRetainingCapacity(base);
                p.outbox.clearRetainingCapacity();
                p.emits.clearRetainingCapacity();
                if (sim.gave_up) return error.Crash;
                try sim.crashed(id, before);
                return .{ .seq = entry.seq, .reply = null };
            },
            else => return err,
        };
        p.state = after.tuple[1];
        for (p.outbox.items) |o| {
            if (sim.procs.items[o.to].up) _ = try sim.enqueue(o.to, o.message);
        }
        p.outbox.clearRetainingCapacity();
        try sim.events.appendSlice(sim.gpa, p.emits.items);
        p.emits.clearRetainingCapacity();
        return .{ .seq = entry.seq, .reply = after.tuple[0] };
    }

    /// One update, then every invariant against the state before it. Gives (reply, state).
    fn update(sim: *Sim, id: u32, message: Value, before: Value) Error!Value {
        const vm = sim.vm;
        const proc = sim.procs.items[id];
        const p = vm.program.processes[proc.process];
        const n = proc.args.len;
        const args = try sim.gpa.alloc(Value, n + 2);
        @memcpy(args[0..n], proc.args);
        args[n] = before;
        args[n + 1] = message;
        const out = try vm.call(p.update, args);
        args[n] = out.tuple[1];
        args[n + 1] = before;
        for (p.invariants) |inv| {
            if (!(try vm.call(inv.function, args)).bool) continue;
            const c = vm.program.clauses[inv.clause];
            const values = try sim.gpa.alloc(contracts.Involved, 1);
            values[0] = .{ .name = "state", .value = try vm.render(out.tuple[1]) };
            vm.report = .{ .kind = .invariant, .clause = c.text, .within = c.within, .at = c.at, .values = values };
            return error.Crash;
        }
        return out;
    }

    // ---- failure

    /// Keeps the crash with its complete report, then does what the child line says.
    /// :always and :on_crash restart alike: an update never ends a process but by crashing.
    fn crashed(sim: *Sim, id: u32, before: Value) Error!void {
        const vm = sim.vm;
        var report = vm.report.?;
        var p = &sim.procs.items[id];
        const log = try sim.gpa.alloc([]const u8, p.log.items.len);
        for (p.log.items, log) |m, *o| o.* = try vm.render(m);
        report.process = .{ .process = sim.nameOf(id), .seed = sim.seed, .log = log, .state = try vm.render(before) };
        try sim.crashes.append(sim.gpa, report);
        if (p.policy.restart == .never) {
            p.up = false;
            return;
        }
        var kept: usize = 0;
        for (p.restarts.items) |t| if (t > sim.now - p.policy.window_ms) {
            p.restarts.items[kept] = t;
            kept += 1;
        };
        p.restarts.shrinkRetainingCapacity(kept);
        if (kept >= p.policy.max_restarts) return sim.giveUp(id, report);
        try p.restarts.append(sim.gpa, sim.now);
        p.mailbox.clearRetainingCapacity();
        p.head = 0;
        p.log.clearRetainingCapacity();
        const state = vm.call(vm.program.processes[p.process].init, p.args) catch |err| switch (err) {
            error.Crash => return sim.giveUp(id, vm.report.?),
            else => return err,
        };
        p = &sim.procs.items[id];
        p.state = state;
    }

    /// The child crashed more than max_restarts times within the window: its supervisor
    /// crashes, every child of that supervisor goes down, and the run stops.
    fn giveUp(sim: *Sim, id: u32, last: contracts.Report) Error {
        const vm = sim.vm;
        const p = sim.procs.items[id];
        const sup_name = if (p.supervisor == test_runner) "the test runner" else vm.program.supervisors[sim.supervisors.items[p.supervisor].index].name;
        for (sim.procs.items) |*q| {
            if (q.supervisor == p.supervisor) q.up = false;
        }
        sim.gave_up = true;
        const values = try sim.gpa.alloc(contracts.Involved, 1);
        values[0] = .{ .name = "last crash", .value = last.clause };
        vm.report = .{
            .kind = .supervisor,
            .clause = try std.fmt.allocPrint(sim.gpa, "{s} gave up: {s} crashed more than {d} times within {d}.ms", .{ sup_name, sim.nameOf(id), p.policy.max_restarts, p.policy.window_ms }),
            .within = sup_name,
            .at = last.at,
            .values = values,
            .process = last.process,
        };
        return error.Crash;
    }
};

// ---- tests

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const check = @import("check.zig");
const caps = @import("caps.zig");
const diag = @import("diag.zig");
const runner = @import("runner.zig");

fn compile(arena: std.mem.Allocator, src: []const u8) !*bytecode.Program {
    var diags: diag.List = .empty;
    const tokens = try lexer.lex(arena, src, &diags);
    const tree = try parser.parse(arena, src, tokens, &diags);
    const checked = try check.check(arena, tree, &diags);
    try caps.check(arena, checked, &diags);
    for (diags.items) |d| std.debug.print("{s} at {d}: {s}\n", .{ d.code, d.at, d.what });
    try std.testing.expectEqual(@as(usize, 0), diags.items.len);
    const program = try arena.create(bytecode.Program);
    program.* = try bytecode.lower(arena, checked);
    return program;
}

/// Runs one test of a program and keeps its Vm and Sim to look at.
const Harness = struct {
    machine: Vm,
    sim: Sim,

    fn run(h: *Harness, arena: std.mem.Allocator, program: *const bytecode.Program, name: []const u8) Error!void {
        h.machine = .init(arena, program, 7);
        h.sim = .init(&h.machine, 7, name);
        h.machine.sim = &h.sim;
        const t = for (program.tests) |t| {
            if (std.mem.eql(u8, t.name, name)) break t;
        } else unreachable;
        _ = try h.machine.call(t.function, &.{});
    }
};

const tally_src =
    \\module T.Sched
    \\process Tally(fs: Fs)
    \\  state
    \\    votes: UInt32
    \\    seen: List(UInt32)
    \\  end
    \\  message Vote(n: UInt32)
    \\  message Total : UInt32
    \\  fn update(state, message)
    \\    case message
    \\      Vote(n):
    \\        state.votes += 1
    \\        state.seen = state.seen.push(n)
    \\      Total: state.votes
    \\    end
    \\  end
    \\end
    \\supervisor Tallies(fs: Fs)
    \\  child Tally(fs), restart: :always
    \\end
    \\test "in order"
    \\  tally = Tally.start(Fs.fixture())
    \\  for n in [4, 5, 6]
    \\    tally.send(Vote(n: n))
    \\  end
    \\  assert tally.ask(Total, within: 100.ms) is Ok(3)
    \\end
    \\test "slow"
    \\  tally = Tally.start(Fs.fixture(delay: 1.minute))
    \\  tally.send(Vote(n: 1))
    \\  assert tally.ask(Total, within: 100.ms) is Error(Timeout)
    \\  assert tally.ask(Total, within: 2.minute) is Ok(1)
    \\end
;

test "messages arrive in order, one update each; ask replies after the waiting ones" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, tally_src);
    var h: Harness = undefined;
    try h.run(arena, program, "in order");
    try std.testing.expectEqual(@as(usize, 1), h.sim.procs.items.len);
    const tally = h.sim.procs.items[0];
    try std.testing.expectEqual(@as(usize, 0), tally.queued());
    // Three votes and the ask, each its own update.
    try std.testing.expectEqual(@as(usize, 4), tally.log.items.len);
    const seen = tally.state.record.fields[1].list;
    try std.testing.expectEqual(@as(usize, 3), seen.len);
    for (seen, [_]i128{ 4, 5, 6 }) |v, want| try std.testing.expectEqual(want, v.int);
    try std.testing.expectEqual(@as(usize, 0), h.sim.crashes.items.len);
}

test "an ask past the target's fixture delay is a Timeout, and the message still arrives" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, tally_src);
    var h: Harness = undefined;
    try h.run(arena, program, "slow");
    try std.testing.expectEqual(@as(i128, 1), h.sim.procs.items[0].state.record.fields[0].int);
}

const tx_src =
    \\module T.Tx
    \\process Meter() mailbox: 2
    \\  state
    \\    n: UInt8
    \\  end
    \\  invariant "n never goes backwards"
    \\    state.n < old(state.n)
    \\  end
    \\  message Add(k: UInt8)
    \\  message Back
    \\  message Read : UInt8
    \\  fn update(state, message)
    \\    case message
    \\      Add(k):
    \\        state.n += k
    \\      Back:
    \\        state.n -= 1
    \\      Read: state.n
    \\    end
    \\  end
    \\end
    \\process Relay(meter: Handle(Meter), events: Events)
    \\  state
    \\    sent: UInt32
    \\  end
    \\  message Poke
    \\  message Flood
    \\  fn update(state, message)
    \\    case message
    \\      Poke:
    \\        meter.send(Add(k: 1))
    \\        events.emit(state.sent)
    \\        state.sent -= 1
    \\      Flood:
    \\        meter.send(Add(k: 1))
    \\        meter.send(Add(k: 1))
    \\        meter.send(Add(k: 1))
    \\    end
    \\  end
    \\end
    \\supervisor Meters(meter: Handle(Meter), events: Events)
    \\  child Meter, restart: :always
    \\  child Relay(meter, events), restart: :always
    \\end
    \\test "undone"
    \\  meter = Meter.start()
    \\  relay = Relay.start(meter, Events.fixture())
    \\  meter.send(Add(k: 5))
    \\  relay.send(Poke)
    \\end
    \\test "backwards"
    \\  meter = Meter.start()
    \\  meter.send(Add(k: 5))
    \\  meter.send(Back)
    \\end
    \\test "flooded by a test"
    \\  meter = Meter.start()
    \\  for k in [1, 2, 3]
    \\    meter.send(Add(k: k))
    \\  end
    \\end
    \\test "flooded by a process"
    \\  meter = Meter.start()
    \\  relay = Relay.start(meter, Events.fixture())
    \\  relay.send(Flood)
    \\end
    \\test rejects "going backwards trips the invariant"
    \\  meter = Meter.start()
    \\  meter.send(Add(k: 5))
    \\  meter.send(Back)
    \\end
;

test "update is a transaction: a crash drops its state writes, sends, and emits, and the process restarts" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, tx_src);
    var h: Harness = undefined;
    try h.run(arena, program, "undone");
    const meter = h.sim.procs.items[0];
    const relay = h.sim.procs.items[1];
    // The meter took the test's Add(5) and never the relay's Add(1).
    try std.testing.expectEqual(@as(i128, 5), meter.state.record.fields[0].int);
    try std.testing.expectEqual(@as(usize, 1), meter.log.items.len);
    try std.testing.expectEqual(@as(usize, 0), h.sim.events.items.len);
    try std.testing.expect(relay.up);
    try std.testing.expectEqual(@as(i128, 0), relay.state.record.fields[0].int);
    try std.testing.expectEqual(@as(usize, 1), relay.restarts.items.len);
    try std.testing.expectEqual(@as(usize, 0), relay.log.items.len);
    const crash = h.sim.crashes.items[0];
    try std.testing.expectEqual(contracts.Kind.overflow, crash.kind);
    try std.testing.expectEqualStrings("Relay", crash.process.?.process);
    try std.testing.expectEqualStrings("Poke", crash.process.?.log[0]);
    try std.testing.expectEqualStrings("Relay(sent: 0)", crash.process.?.state);
    try std.testing.expectEqual(@as(u64, 7), crash.process.?.seed);
}

test "an invariant is true when broken, reads old(state), and trips a test rejects" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, tx_src);
    var h: Harness = undefined;
    try h.run(arena, program, "backwards");
    const crash = h.sim.crashes.items[0];
    try std.testing.expectEqual(contracts.Kind.invariant, crash.kind);
    try std.testing.expectEqualStrings("invariant \"n never goes backwards\"", crash.clause);
    try std.testing.expectEqualStrings("Meter", crash.within);
    try std.testing.expectEqualStrings("Meter(n: 4)", crash.values[0].value);
    try std.testing.expectEqualStrings("Meter(n: 5)", crash.process.?.state);
    try std.testing.expectEqual(@as(usize, 2), crash.process.?.log.len);
    try std.testing.expectEqualStrings("Back", crash.process.?.log[1]);
    // Restarted from its initial state, not from the state that broke the invariant.
    try std.testing.expectEqual(@as(i128, 0), h.sim.procs.items[0].state.record.fields[0].int);

    const r = try runner.run(arena, program);
    try std.testing.expectEqual(runner.Outcome.failed, r.results[1].outcome);
    try std.testing.expectEqual(runner.Outcome.tripped_as_expected, r.results[4].outcome);
    try std.testing.expectEqual(contracts.Kind.invariant, r.results[4].report.?.kind);
}

test "a mailbox at its bound crashes the sender, a test or a process, and names both" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compile(arena, tx_src);
    var h: Harness = undefined;
    // All three sends are one statement, so none is delivered before the third.
    try std.testing.expectError(error.Crash, h.run(arena, program, "flooded by a test"));
    try std.testing.expectEqual(contracts.Kind.mailbox, h.machine.report.?.kind);
    try std.testing.expectEqualStrings("the test \"flooded by a test\" sent to Meter, whose mailbox is full at its bound of 2", h.machine.report.?.clause);
    try std.testing.expectEqualStrings("Add(3)", h.machine.report.?.values[0].value);
    try std.testing.expectEqual(@as(usize, 2), h.sim.procs.items[0].queued());

    try h.run(arena, program, "flooded by a process");
    const crash = h.sim.crashes.items[0];
    try std.testing.expectEqual(contracts.Kind.mailbox, crash.kind);
    try std.testing.expectEqualStrings("Relay sent to Meter, whose mailbox is full at its bound of 2", crash.clause);
    // The receiver did not crash, and the two sends that fit went with the sender's update.
    try std.testing.expectEqual(@as(usize, 1), h.sim.crashes.items.len);
    try std.testing.expectEqual(@as(usize, 0), h.sim.procs.items[0].log.items.len);
}

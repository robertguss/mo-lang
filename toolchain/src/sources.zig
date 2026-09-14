//! The loops the runtime owns (design-v0/09, Net and Http; step 20). A process never loops
//! around a call that waits: `listener.serve(into: p, idle: d)`, `conn.lines(into: p, idle:
//! d)`, and `http_listener.serve(into: p, idle: d)` make the runtime accept or read from that
//! call on and send each result to `p` as a message `p` declares, as Erlang's active sockets
//! do. The scheduler is the loop.
//!
//! - `Listener.serve`: `Accepted(conn: Conn)` per connection, and `Idle` whenever no
//!   connection came for `idle`; the listener goes on being served.
//! - `Conn.lines`: `Line(text: String)` per line, `LineTooLong` for a line over 64 KiB (the
//!   next starts after it), `Closed` at the end of the stream (a last line with no newline
//!   first), and `Idle` when no line came for `idle`, after which the connection is closed.
//!   A connection this side closes stops being read, with no message.
//! - `HttpListener.serve`: `Accepted(exchange: Exchange)` per whole request, and `Idle` as
//!   `Listener.serve` sends it. Each connection's request is read on its own, so a slow client
//!   holds up no other; one not whole within `idle` is closed, and one that is not HTTP is
//!   answered 400, 413, or 501 and closed, with no message.
//!
//! Backpressure: a source delivers while its target's mailbox holds fewer than its bound less
//! `headroom` (4, or half a bound under 8) waiting messages, counting an HTTP source's requests
//! in flight; at that it stops accepting or reading, and it starts again once the mailbox has
//! drained to half its bound. So overload waits in the kernel's queues, not in a crash. While a
//! source waits for room its idle time does not run.
//!
//! Under `mo test` (Mo.Sim) every source is pumped at the start of each delivery round, one
//! message each, in start order or the seed's, before the round's deliveries; nothing happens
//! while a simulated call waits, so a source with nothing to take waits, and `Idle` comes only
//! when fixture calls have waited past its deadline. With faults, a source about to deliver
//! can instead find its connection `Closed` or wait out its deadline (`Idle`), by the seed.
//! Under `mo run` (Mo.Server), each source waits on one task at a time (an accept or a read),
//! whose end wakes main's thread, and main's thread turns what came into messages each time it
//! hands out turns (turns.zig, step).
const std = @import("std");
const Io = std.Io;
const http = @import("http.zig");
const net = @import("net.zig");
const sim_mod = @import("sim.zig");
const turns_mod = @import("turns.zig");
const vm_mod = @import("vm.zig");

const Sim = sim_mod.Sim;
const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Error = vm_mod.Error;
const Turns = turns_mod.Turns;

pub const Kind = enum { serve, lines, http_serve, request };

/// The messages each row sends, for the checker (check.zig, MO0223): each name, and its one
/// field's name as the spec writes it and its type, or none.
pub const Sent = struct { name: []const u8, field: ?[]const u8 = null, type: ?[]const u8 = null };
pub const serve_messages = [_]Sent{ .{ .name = "Accepted", .field = "conn", .type = "Conn" }, .{ .name = "Idle" } };
pub const lines_messages = [_]Sent{ .{ .name = "Line", .field = "text", .type = "String" }, .{ .name = "LineTooLong" }, .{ .name = "Closed" }, .{ .name = "Idle" } };
pub const http_messages = [_]Sent{ .{ .name = "Accepted", .field = "exchange", .type = "Exchange" }, .{ .name = "Idle" } };

/// The messages of the row `recv.name`, or null when it is not a source row.
pub fn messagesOf(recv: []const u8, name: []const u8) ?[]const Sent {
    if (std.mem.eql(u8, recv, "Listener") and std.mem.eql(u8, name, "serve")) return &serve_messages;
    if (std.mem.eql(u8, recv, "Conn") and std.mem.eql(u8, name, "lines")) return &lines_messages;
    if (std.mem.eql(u8, recv, "HttpListener") and std.mem.eql(u8, name, "serve")) return &http_messages;
    return null;
}

/// Waiting messages a source leaves free below its target's bound.
pub fn headroom(bound: u32) u32 {
    return @min(4, bound / 2);
}

pub const Source = struct {
    kind: Kind,
    /// The listener's handle (serve, http_serve) or the connection's (lines, request).
    handle: u32,
    /// The process each message goes to.
    to: u32,
    idle_ms: i64,
    /// When the idle time last started: simulated under Mo.Sim, the wall clock under Mo.Server.
    since: i64,
    /// A serve source's last Idle, so simulated time must pass again before the next.
    idled_at: i64 = std.math.minInt(i64),
    done: bool = false,
    /// Stopped at its target's bound, until the mailbox drains to half of it.
    paused: bool = false,
    /// A request source's http_serve source, whose requests in flight it counts.
    parent: ?*Source = null,
    /// An http_serve source's requests still being read.
    inflight: u32 = 0,
    /// Under Mo.Server: a connection accepted and not yet given, the task it waits on, and
    /// what that task's end sets.
    held: ?u32 = null,
    waker: net.Waker = .{},
    accepting: ?Io.Future(Io.net.Server.AcceptError!Io.net.Stream) = null,
    reading: ?Io.Future(Io.net.Stream.Reader.Error!usize) = null,
};

pub const Sources = struct {
    list: std.ArrayList(*Source) = .empty,
    order: std.ArrayList(u32) = .empty,
    /// Under Mo.Server: the earliest time a waiting source's idle time runs out, for main's
    /// thread to wake at (turns.zig, idle).
    deadline: ?i64 = null,

    /// Whether any source can still deliver: under Mo.Server the run goes on while one can.
    pub fn active(s: *const Sources) bool {
        for (s.list.items) |x| if (!x.done) return true;
        return false;
    }
};

/// The runtime as a message's sender, in a seeded run's trace (runner.zig).
pub const runtime_sender: u32 = std.math.maxInt(u32) - 1;

fn crash(vm: *Vm, within: []const u8, clause: []const u8) Error {
    vm.report = .{ .kind = .other, .clause = clause, .within = within, .at = 0 };
    return error.Crash;
}

/// A source row: `a` is the receiver, then `into:`, then `idle:`.
pub fn row(vm: *Vm, kind: Kind, a: []const Value) Error!Value {
    const label = switch (kind) {
        .serve => "Listener.serve",
        .lines => "Conn.lines",
        .http_serve => "HttpListener.serve",
        .request => unreachable,
    };
    const sim = vm.sim orelse return crash(vm, label, "a source runs only under mo run or mo test");
    const h = a[0].cap.handle;
    var since: i64 = elapsed(sim);
    if (vm.server) |server| {
        const n = &server.sockets;
        switch (kind) {
            .serve, .http_serve => {
                const l = n.listeners.items[h];
                if (l.served) return crash(vm, label, "this listener is already served: a listener is served into one process");
                l.served = true;
            },
            .lines => {
                const c = n.conns.items[h];
                if (c.lining) return crash(vm, label, "this connection's lines already go to a process: a connection is read into one process");
                c.lining = true;
            },
            .request => unreachable,
        }
        if (sim.turns) |t| since = t.now();
    } else {
        const f = &sim.fixture;
        switch (kind) {
            .serve, .http_serve => {
                const l = &f.listeners.items[h];
                if (l.served) return crash(vm, label, "this listener is already served: a listener is served into one process");
                l.served = true;
            },
            .lines => {
                const c = &f.conns.items[h];
                if (c.lining) return crash(vm, label, "this connection's lines already go to a process: a connection is read into one process");
                c.lining = true;
            },
            .request => unreachable,
        }
    }
    _ = try add(sim, .{ .kind = kind, .handle = h, .to = a[1].handle, .idle_ms = @max(a[2].duration, 0), .since = since });
    return .none;
}

fn add(sim: *Sim, source: Source) Error!*Source {
    const s = try std.heap.smp_allocator.create(Source);
    s.* = source;
    try sim.sources.list.append(sim.gpa, s);
    return s;
}

/// Simulated time: the clock, and what fixture calls waited that it has not moved by yet.
fn elapsed(sim: *const Sim) i64 {
    return sim.now + sim.lag;
}

/// Whether `s` may deliver one more message to its target, counting `extra` more waiting.
fn room(sim: *Sim, s: *Source, extra: u32) bool {
    const p = &sim.procs.items[s.to];
    const bound = sim.vm.program.processes[p.process].mailbox;
    const waiting = p.queued() + extra;
    if (s.paused) {
        if (waiting > bound / 2) return false;
        s.paused = false;
    }
    if (waiting + headroom(bound) >= bound) {
        s.paused = true;
        return false;
    }
    return true;
}

/// A message from the runtime to process `to`, packed under `mo run`.
fn send(sim: *Sim, to: u32, name: []const u8, fields: []const Value) Error!void {
    const vm = sim.vm;
    const message = try vm.variant(name, fields);
    const parcel = if (sim.packs) try vm.pack(message) else null;
    _ = try sim.enqueue(runtime_sender, to, if (parcel) |p| p.value else message, parcel);
}

fn text(sim: *Sim, line: []const u8) Error!Value {
    return .{ .string = try vm_mod.rawDupe(sim.vm.heap, u8, line) };
}

// ---- Mo.Sim

/// One message from each source that has one and room for it; true when one went.
pub fn pumpFixture(sim: *Sim) Error!bool {
    const list = sim.sources.list.items;
    if (list.len == 0) return false;
    const order = &sim.sources.order;
    order.clearRetainingCapacity();
    for (0..list.len) |k| try order.append(sim.gpa, @intCast(k));
    if (sim.schedule) |*rng| rng.random().shuffle(u32, order.items);
    var progressed = false;
    for (order.items) |k| {
        const s = list[k];
        if (s.done) continue;
        const went = switch (s.kind) {
            .serve, .http_serve => try serveFixture(sim, s),
            .lines => try linesFixture(sim, s),
            .request => unreachable,
        };
        if (went) progressed = true;
    }
    return progressed;
}

fn idleFixture(sim: *Sim, s: *Source) Error!bool {
    const now = elapsed(sim);
    if (now - s.since < s.idle_ms or now <= s.idled_at or !room(sim, s, 0)) return false;
    try send(sim, s.to, "Idle", &.{});
    s.since = now;
    s.idled_at = now;
    return true;
}

fn serveFixture(sim: *Sim, s: *Source) Error!bool {
    const f = &sim.fixture;
    const l = &f.listeners.items[s.handle];
    if (l.head == l.backlog.items.len) return idleFixture(sim, s);
    if (!sim.procs.items[s.to].up or !room(sim, s, 0)) return false;
    const h = l.backlog.items[l.head];
    if (s.kind == .serve) {
        // The accept waited out its deadline, by the seed.
        if (sim.fault(null, s.idle_ms) != null) {
            try send(sim, s.to, "Idle", &.{});
            s.since = elapsed(sim);
            return true;
        }
        l.head += 1;
        s.since = elapsed(sim);
        try send(sim, s.to, "Accepted", &.{.{ .cap = .{ .kind = .conn, .handle = h } }});
        return true;
    }
    const c = &f.conns.items[h];
    const peer_closed = f.conns.items[c.peer].closed;
    switch (http.parse(c.inbound.items[c.start..], peer_closed, .request)) {
        .whole => |m| {
            l.head += 1;
            s.since = elapsed(sim);
            if (sim.fault(.closed, s.idle_ms)) |fault| {
                c.closed = true;
                if (fault == .timeout) try send(sim, s.to, "Idle", &.{});
                return true;
            }
            const bytes = try sim.gpa.dupe(u8, c.inbound.items[c.start .. c.start + m.len]);
            c.start += m.len;
            try f.exchanges.append(sim.gpa, .{ .conn = h, .request = bytes });
            try send(sim, s.to, "Accepted", &.{.{ .cap = .{ .kind = .exchange, .handle = @intCast(f.exchanges.items.len - 1) } }});
            return true;
        },
        .more => {
            // A request not whole within the idle time is closed, and the next client's is read.
            if (elapsed(sim) - s.since < s.idle_ms) return false;
            l.head += 1;
            c.closed = true;
            return true;
        },
        .failed => |why| {
            l.head += 1;
            if (http.refusal(why)) |refused| if (!peer_closed) try f.conns.items[c.peer].inbound.appendSlice(sim.gpa, refused);
            c.closed = true;
            return true;
        },
    }
}

fn linesFixture(sim: *Sim, s: *Source) Error!bool {
    const f = &sim.fixture;
    const c = &f.conns.items[s.handle];
    if (c.closed) {
        s.done = true;
        return false;
    }
    if (!sim.procs.items[s.to].up) {
        c.closed = true;
        s.done = true;
        return false;
    }
    var skipping = c.skipping;
    const taken, const what = net.scanLine(c.inbound.items[c.start..], f.conns.items[c.peer].closed, &skipping);
    if (what == .more) {
        c.start += taken;
        c.skipping = skipping;
        compactInbound(c);
        if (elapsed(sim) - s.since < s.idle_ms or !room(sim, s, 0)) return false;
        try send(sim, s.to, "Idle", &.{});
        c.closed = true;
        s.done = true;
        return true;
    }
    if (!room(sim, s, 0)) return false;
    if (sim.fault(.closed, s.idle_ms)) |fault| {
        try send(sim, s.to, if (fault == .timeout) "Idle" else "Closed", &.{});
        c.closed = true;
        s.done = true;
        return true;
    }
    switch (what) {
        .line => |line| try send(sim, s.to, "Line", &.{try text(sim, line)}),
        .too_long => try send(sim, s.to, "LineTooLong", &.{}),
        .end => {
            try send(sim, s.to, "Closed", &.{});
            s.done = true;
        },
        .more => unreachable,
    }
    c.start += taken;
    c.skipping = skipping;
    compactInbound(c);
    s.since = elapsed(sim);
    return true;
}

fn compactInbound(c: *net.Fixture.FixtureConn) void {
    if (c.start == c.inbound.items.len) {
        c.inbound.clearRetainingCapacity();
        c.start = 0;
    }
}

// ---- Mo.Server

/// From main's thread, holding the turn: every task that ended becomes messages, idle times
/// that ran out end their waits, and each source with room waits on its next task.
pub fn pumpServer(sim: *Sim, t: *Turns) Error!void {
    if (sim.sources.list.items.len == 0) return;
    var deadline: ?i64 = null;
    // A request source an http_serve source adds is pumped in this same pass, since nothing
    // else would wake main's thread for it; adding one may move the list, so each source is
    // read from it again.
    var k: usize = 0;
    while (k < sim.sources.list.items.len) : (k += 1) {
        const s = sim.sources.list.items[k];
        if (s.done) continue;
        switch (s.kind) {
            .serve, .http_serve => try serveServer(sim, t, s),
            .lines => try linesServer(sim, t, s),
            .request => try requestServer(sim, t, s),
        }
        if (s.done or s.paused) continue;
        const at = s.since + s.idle_ms;
        deadline = if (deadline) |d| @min(d, at) else at;
    }
    sim.sources.deadline = deadline;
    // Sources that ended give their slots back.
    var kept: usize = 0;
    for (sim.sources.list.items) |s| {
        if (s.done and s.accepting == null and s.reading == null) {
            std.heap.smp_allocator.destroy(s);
            continue;
        }
        sim.sources.list.items[kept] = s;
        kept += 1;
    }
    sim.sources.list.shrinkRetainingCapacity(kept);
}

fn serveServer(sim: *Sim, t: *Turns, s: *Source) Error!void {
    const n = &sim.server.?.sockets;
    if (s.accepting) |*task| if (s.waker.done.isSet()) {
        const got = task.await(n.io);
        s.accepting = null;
        if (got) |stream| {
            const h = try n.adopt(stream);
            n.conns.items[h].listener = s.handle;
            s.held = h;
        } else |_| {}
    };
    if (s.held) |h| {
        if (s.kind == .http_serve) {
            s.held = null;
            s.inflight += 1;
            s.since = t.now();
            const r = try add(sim, .{ .kind = .request, .handle = h, .to = s.to, .idle_ms = s.idle_ms, .since = t.now(), .parent = s });
            n.conns.items[h].lining = true;
            _ = r;
        } else if (sim.procs.items[s.to].up and room(sim, s, 0)) {
            s.held = null;
            s.since = t.now();
            try send(sim, s.to, "Accepted", &.{.{ .cap = .{ .kind = .conn, .handle = h } }});
        }
    }
    const extra = s.inflight;
    if (s.held == null and s.accepting == null and room(sim, s, extra)) {
        const l = n.listeners.items[s.handle];
        s.waker = .{ .main = &t.main_wake };
        s.accepting = n.io.concurrent(net.acceptTask, .{ n.io, &l.server, &s.waker }) catch null;
    }
    if (s.paused) {
        s.since = t.now();
    } else if (t.now() - s.since >= s.idle_ms and room(sim, s, extra)) {
        try send(sim, s.to, "Idle", &.{});
        s.since = t.now();
    }
}

/// Makes room in `c`'s buffer for the next read, as Net.fill does: false when it is full.
fn roomToRead(c: *net.Conn, initial: usize, cap: usize) Error!bool {
    if (c.start > 0) {
        std.mem.copyForwards(u8, c.buf, c.buf[c.start..c.end]);
        c.end -= c.start;
        c.start = 0;
    }
    if (c.end < c.buf.len) return true;
    if (c.buf.len >= cap) return false;
    const size = if (c.buf.len == 0) initial else @min(cap, 2 * c.buf.len);
    const grown = std.heap.page_allocator.alloc(u8, size) catch return error.OutOfMemory;
    @memcpy(grown[0..c.end], c.buf[0..c.end]);
    if (c.buf.len > 0) std.heap.page_allocator.free(c.buf);
    c.buf = grown;
    return true;
}

/// A read task that ended: what it read is in the buffer. Null while it has not ended;
/// false when the stream broke or this side closed the connection.
fn readEnded(n: *net.Net, s: *Source, c: *net.Conn) ?bool {
    const task = &(s.reading orelse return true);
    if (!s.waker.done.isSet()) return null;
    const got = task.await(n.io);
    s.reading = null;
    c.reading = false;
    if (c.closed) {
        n.release(c);
        return false;
    }
    const k = got catch {
        n.close(c);
        return false;
    };
    if (k == 0) c.eof = true else c.end += k;
    return true;
}

/// Ends the read `s` waits on, when its idle time ran out: true when it did.
fn idleOut(n: *net.Net, t: *Turns, s: *Source, c: *net.Conn) bool {
    if (s.reading == null or t.now() - s.since < s.idle_ms) return false;
    _ = s.reading.?.cancel(n.io) catch 0;
    s.reading = null;
    c.reading = false;
    return true;
}

fn startRead(n: *net.Net, t: *Turns, s: *Source, c: *net.Conn) void {
    s.waker = .{ .main = &t.main_wake };
    c.reading = true;
    s.reading = n.io.concurrent(net.readTask, .{ n.io, c.stream, c.buf[c.end..], &s.waker }) catch blk: {
        c.reading = false;
        break :blk null;
    };
}

fn linesServer(sim: *Sim, t: *Turns, s: *Source) Error!void {
    const n = &sim.server.?.sockets;
    const c = n.conns.items[s.handle];
    const ended = readEnded(n, s, c) orelse {
        if (!s.paused and idleOut(n, t, s, c)) {
            try send(sim, s.to, "Idle", &.{});
            n.close(c);
            s.done = true;
        }
        return;
    };
    if (!ended) {
        if (!c.closed or c.released) {
            // The stream broke: the other side's end, as far as the process can tell.
            if (sim.procs.items[s.to].up) try send(sim, s.to, "Closed", &.{});
        }
        s.done = true;
        return;
    }
    if (c.closed) {
        n.release(c);
        s.done = true;
        return;
    }
    if (!sim.procs.items[s.to].up) {
        n.close(c);
        s.done = true;
        return;
    }
    while (room(sim, s, 0)) {
        switch (c.scan()) {
            .line => |line| try send(sim, s.to, "Line", &.{try text(sim, line)}),
            .too_long => try send(sim, s.to, "LineTooLong", &.{}),
            .end => {
                try send(sim, s.to, "Closed", &.{});
                s.done = true;
                return;
            },
            .more => break,
        }
        s.since = t.now();
    }
    if (s.paused) {
        s.since = t.now();
        return;
    }
    // A line too long is taken before the buffer fills, so there is always room to read.
    if (try roomToRead(c, 2 * net.line_limit, 2 * net.line_limit)) startRead(n, t, s, c);
}

fn requestServer(sim: *Sim, t: *Turns, s: *Source) Error!void {
    const n = &sim.server.?.sockets;
    const c = n.conns.items[s.handle];
    const parent = s.parent.?;
    const ended = readEnded(n, s, c) orelse {
        if (idleOut(n, t, s, c)) {
            n.close(c);
            finishRequest(s, parent);
        }
        return;
    };
    if (!ended) return finishRequest(s, parent);
    switch (http.parse(c.buf[c.start..c.end], c.eof, .request)) {
        .whole => |m| {
            const bytes = try n.gpa.dupe(u8, c.buf[c.start .. c.start + m.len]);
            c.start += m.len;
            c.lining = false;
            try n.exchanges.append(n.gpa, .{ .conn = s.handle, .request = bytes });
            const handle: u32 = @intCast(n.exchanges.items.len - 1);
            finishRequest(s, parent);
            if (!sim.procs.items[s.to].up) {
                n.exchanges.items[handle].forget(n.gpa);
                n.close(c);
                return;
            }
            try send(sim, s.to, "Accepted", &.{.{ .cap = .{ .kind = .exchange, .handle = handle } }});
        },
        .failed => |why| {
            if (http.refusal(why)) |refused| _ = std.posix.system.write(c.stream.socket.handle, refused.ptr, refused.len);
            n.close(c);
            finishRequest(s, parent);
        },
        .more => {
            if (try roomToRead(c, http.buffer_initial, http.buffer_cap)) return startRead(n, t, s, c);
            if (http.refusal(.TooLarge)) |refused| _ = std.posix.system.write(c.stream.socket.handle, refused.ptr, refused.len);
            n.close(c);
            finishRequest(s, parent);
        },
    }
}

fn finishRequest(s: *Source, parent: *Source) void {
    s.done = true;
    parent.inflight -= 1;
}

/// The run is over, or main called exit and returned: every source stops, its task ended.
pub fn stopServer(sim: *Sim, t: *Turns) void {
    const server = sim.server orelse return;
    const n = &server.sockets;
    for (sim.sources.list.items) |s| {
        if (s.accepting) |*task| {
            if (task.cancel(t.io)) |stream| stream.close(t.io) else |_| {}
            s.accepting = null;
        }
        if (s.reading) |*task| {
            _ = task.cancel(t.io) catch 0;
            s.reading = null;
            n.conns.items[s.handle].reading = false;
        }
        s.done = true;
    }
    sim.sources.deadline = null;
}

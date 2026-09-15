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
//! Under `mo run` (Mo.Server) sockets are nonblocking, and main's thread pumps only the sources
//! that can do something (step 21): one just added, one whose socket the poller reported
//! ready, one paused at its target's bound, and one whose idle time has run out, which a heap
//! of deadlines finds. A source that has taken all there is arms the poller and waits.
const std = @import("std");
const Io = std.Io;
const http = @import("http.zig");
const net = @import("net.zig");
const poller = @import("poller.zig");
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

/// Under Mo.Server, how long a listener waits before accepting again after the system refused
/// a connection for want of descriptors or memory.
const refused_retry_ms: i64 = 100;

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
    /// It serves the runtime surface (step 23), so it does not keep a program running.
    background: bool = false,
    /// Stopped at its target's bound, until the mailbox drains to half of it.
    paused: bool = false,
    /// A request source's http_serve source, whose requests in flight it counts.
    parent: ?*Source = null,
    /// An http_serve source's requests still being read.
    inflight: u32 = 0,
    /// Under Mo.Server: what the poller reports when its socket is ready.
    waiter: poller.Waiter = .{ .fd = -1, .filter = .read },
    /// Under Mo.Server: its place in Sources.list; in Sources.dirty, in Sources.paused; its
    /// place in Sources.timers, when it has one.
    index: usize = 0,
    dirty: bool = false,
    in_paused: bool = false,
    timer: ?usize = null,
    /// Under Mo.Server: a listener the system refused a connection waits until then.
    retry_at: i64 = 0,
};

const Timer = struct { at: i64, source: *Source };

pub const Sources = struct {
    list: std.ArrayList(*Source) = .empty,
    order: std.ArrayList(u32) = .empty,
    /// Under Mo.Server: the sources to pump next, the ones paused at their target's bound, and
    /// a heap of idle deadlines, earliest first, one entry per source at most. An entry may be
    /// earlier than its source's deadline, since `since` moves on; it is put back when it comes.
    dirty: std.ArrayList(*Source) = .empty,
    paused: std.ArrayList(*Source) = .empty,
    timers: std.ArrayList(Timer) = .empty,

    /// Whether any source can still deliver: under Mo.Server the run goes on while one can. A
    /// source that is done leaves the list under Mo.Server; under Mo.Sim it stays, marked.
    pub fn active(s: *const Sources) bool {
        for (s.list.items) |x| if (!x.done and !x.background) return true;
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
    s.background = sim.hidden(source.to);
    s.index = sim.sources.list.items.len;
    try sim.sources.list.append(sim.gpa, s);
    if (sim.server != null) try markDirty(&sim.sources, s);
    // Scheduler 0 pumps the loops: one added on another wakes it (turns.zig, step 30).
    if (sim.turns) |t| t.stir(t.scheds[0]);
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
        recordPause(sim, s, .source_resumed);
    }
    if (waiting + headroom(bound) >= bound) {
        s.paused = true;
        recordPause(sim, s, .source_paused);
        return false;
    }
    return true;
}

/// The row a source serves, as the events and the surface name it.
pub fn rowLabel(kind: Kind) []const u8 {
    return switch (kind) {
        .serve => "Listener.serve",
        .lines => "Conn.lines",
        .http_serve, .request => "HttpListener.serve",
    };
}

/// A source stopped or started again at its target's bound (events.zig, step 23).
fn recordPause(sim: *Sim, s: *Source, kind: @import("events.zig").Kind) void {
    const inflight = if (s.parent) |p| p.inflight else s.inflight;
    sim.record(.{ .kind = kind, .process = s.to, .name = rowLabel(s.kind), .count = inflight });
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

fn markDirty(ss: *Sources, s: *Source) Error!void {
    if (s.dirty or s.done) return;
    s.dirty = true;
    try ss.dirty.append(std.heap.smp_allocator, s);
}

/// The poller reported the socket `s` waits on (turns.zig, idle).
pub fn fired(sim: *Sim, s: *Source) void {
    markDirty(&sim.sources, s) catch {};
}

/// Whether a source can do something now, without waiting.
pub fn hasWork(sim: *const Sim) bool {
    return sim.sources.dirty.items.len > 0;
}

/// The earliest time a source's idle time, or a listener's retry, may run out.
pub fn nextDeadline(sim: *const Sim) ?i64 {
    const timers = sim.sources.timers.items;
    return if (timers.len > 0) timers[0].at else null;
}

/// From main's thread, holding the turn: every source that can do something turns what it
/// took into messages, and arms the poller when it has taken all there is.
pub fn pumpServer(sim: *Sim, t: *Turns) Error!void {
    const ss = &sim.sources;
    if (ss.list.items.len == 0) return;
    const now = t.now();
    while (ss.timers.items.len > 0 and ss.timers.items[0].at <= now) {
        const s = ss.timers.items[0].source;
        timerRemove(ss, s);
        if (dueAt(s) <= now) try markDirty(ss, s) else try timerPush(ss, s, dueAt(s));
    }
    // A paused source looks at its target's mailbox again.
    for (ss.paused.items) |s| try markDirty(ss, s);
    // A request source an http_serve source adds is pumped in this same pass; the list may
    // grow as it is read.
    var k: usize = 0;
    while (k < ss.dirty.items.len) : (k += 1) {
        const s = ss.dirty.items[k];
        s.dirty = false;
        if (s.done) continue;
        switch (s.kind) {
            .serve, .http_serve => try serveServer(sim, t, s, now),
            .lines => try linesServer(sim, t, s, now),
            .request => try requestServer(sim, t, s, now),
        }
        if (s.done) continue;
        try settleSource(ss, s);
    }
    // Sources that ended give their memory back once nothing holds them.
    for (ss.dirty.items) |s| if (s.done) std.heap.smp_allocator.destroy(s);
    ss.dirty.clearRetainingCapacity();
}

/// When `s` must be looked at again with nothing reported: its idle time, or a retry.
fn dueAt(s: *const Source) i64 {
    return if (s.retry_at > s.since + s.idle_ms or s.paused) s.retry_at else s.since + s.idle_ms;
}

/// After a pump: a paused source is in the paused list and has no deadline; any other has one.
fn settleSource(ss: *Sources, s: *Source) Error!void {
    const gpa = std.heap.smp_allocator;
    if (s.paused) {
        if (!s.in_paused) {
            s.in_paused = true;
            try ss.paused.append(gpa, s);
        }
        if (s.timer != null and s.retry_at == 0) timerRemove(ss, s);
        return;
    }
    if (s.in_paused) leavePaused(ss, s);
    if (s.timer == null) try timerPush(ss, s, dueAt(s));
}

fn leavePaused(ss: *Sources, s: *Source) void {
    s.in_paused = false;
    for (ss.paused.items, 0..) |x, i| if (x == s) {
        _ = ss.paused.swapRemove(i);
        return;
    };
}

/// `s` is done: it stops being watched, leaves every list, and is destroyed at the end of the
/// pump (it is in the dirty list then).
fn retire(sim: *Sim, t: *Turns, s: *Source) void {
    const ss = &sim.sources;
    s.done = true;
    if (t.madeSourcePoller()) |p| p.disarm(&s.waiter);
    if (s.in_paused) leavePaused(ss, s);
    if (s.timer != null) timerRemove(ss, s);
    const last = ss.list.pop().?;
    if (last != s) {
        ss.list.items[s.index] = last;
        last.index = s.index;
    }
}

fn watch(t: *Turns, s: *Source, fd: std.posix.fd_t) void {
    const p = t.sourcePoller() catch return;
    if (s.waiter.armed and s.waiter.fd == fd) return;
    p.disarm(&s.waiter);
    s.waiter = .{ .fd = fd, .filter = .read, .source = s };
    _ = p.arm(&s.waiter);
}

fn serveServer(sim: *Sim, t: *Turns, s: *Source, now: i64) Error!void {
    const n = &sim.server.?.sockets;
    const fd = n.listeners.items[s.handle].server.socket.handle;
    while (now >= s.retry_at and sim.procs.items[s.to].up and room(sim, s, s.inflight)) {
        switch (net.acceptOne(fd)) {
            .ok => |conn| {
                const h = try n.adopt(conn);
                n.conns.items[h].listener = s.handle;
                s.since = now;
                if (s.kind == .http_serve) {
                    s.inflight += 1;
                    n.conns.items[h].lining = true;
                    _ = try add(sim, .{ .kind = .request, .handle = h, .to = s.to, .idle_ms = s.idle_ms, .since = now, .parent = s });
                } else {
                    try send(sim, s.to, "Accepted", &.{.{ .cap = .{ .kind = .conn, .handle = h } }});
                }
            },
            .again => {
                watch(t, s, fd);
                break;
            },
            // Out of descriptors or memory: the connection waits in the kernel's queue.
            .busy => {
                s.retry_at = now + refused_retry_ms;
                if (s.timer != null) timerRemove(&sim.sources, s);
                break;
            },
            .closed => break,
        }
    }
    if (s.paused) {
        s.since = now;
    } else if (now - s.since >= s.idle_ms and room(sim, s, s.inflight)) {
        try send(sim, s.to, "Idle", &.{});
        s.since = now;
    }
}

fn linesServer(sim: *Sim, t: *Turns, s: *Source, now: i64) Error!void {
    const n = &sim.server.?.sockets;
    const c = n.conns.items[s.handle];
    if (c.closed) {
        n.release(c);
        return retire(sim, t, s);
    }
    if (!sim.procs.items[s.to].up) {
        n.close(c);
        return retire(sim, t, s);
    }
    while (true) {
        while (room(sim, s, 0)) {
            switch (c.scan()) {
                .line => |line| try send(sim, s.to, "Line", &.{try text(sim, line)}),
                .too_long => try send(sim, s.to, "LineTooLong", &.{}),
                .end => {
                    try send(sim, s.to, "Closed", &.{});
                    return retire(sim, t, s);
                },
                .more => break,
            }
            s.since = now;
        }
        if (s.paused) {
            s.since = now;
            return;
        }
        // A line too long is taken before the buffer fills, so there is always room to read.
        _ = try c.roomToRead(net.buffer_initial, 2 * net.line_limit);
        switch (net.readOne(c.fd(), c.buf[c.end..])) {
            .done => |k| if (k == 0) {
                c.eof = true;
            } else {
                c.end += k;
            },
            .again => break,
            .broke => {
                // The stream broke: the other side's end, as far as the process can tell.
                n.close(c);
                try send(sim, s.to, "Closed", &.{});
                return retire(sim, t, s);
            },
        }
    }
    if (now - s.since >= s.idle_ms) {
        try send(sim, s.to, "Idle", &.{});
        n.close(c);
        return retire(sim, t, s);
    }
    c.giveBack();
    watch(t, s, c.fd());
}

fn requestServer(sim: *Sim, t: *Turns, s: *Source, now: i64) Error!void {
    const n = &sim.server.?.sockets;
    const c = n.conns.items[s.handle];
    while (true) {
        switch (http.parse(c.buf[c.start..c.end], c.eof, .request)) {
            .whole => |m| {
                const bytes = try n.gpa.dupe(u8, c.buf[c.start .. c.start + m.len]);
                c.start += m.len;
                c.lining = false;
                try n.exchanges.append(n.gpa, .{ .conn = s.handle, .request = bytes });
                const handle: u32 = @intCast(n.exchanges.items.len - 1);
                finishRequest(sim, t, s);
                if (!sim.procs.items[s.to].up) {
                    n.exchanges.items[handle].forget(n.gpa);
                    n.close(c);
                    return;
                }
                return send(sim, s.to, "Accepted", &.{.{ .cap = .{ .kind = .exchange, .handle = handle } }});
            },
            .failed => |why| {
                if (http.refusal(why)) |refused| _ = net.writeOne(c.fd(), refused);
                n.close(c);
                return finishRequest(sim, t, s);
            },
            .more => {},
        }
        if (c.closed or c.eof) {
            if (c.closed) n.release(c) else n.close(c);
            return finishRequest(sim, t, s);
        }
        if (!try c.roomToRead(http.buffer_initial, http.buffer_cap)) {
            if (http.refusal(.TooLarge)) |refused| _ = net.writeOne(c.fd(), refused);
            n.close(c);
            return finishRequest(sim, t, s);
        }
        switch (net.readOne(c.fd(), c.buf[c.end..])) {
            .done => |k| if (k == 0) {
                c.eof = true;
            } else {
                c.end += k;
            },
            .again => break,
            .broke => {
                n.close(c);
                return finishRequest(sim, t, s);
            },
        }
    }
    if (now - s.since >= s.idle_ms) {
        n.close(c);
        return finishRequest(sim, t, s);
    }
    watch(t, s, c.fd());
}

fn finishRequest(sim: *Sim, t: *Turns, s: *Source) void {
    s.parent.?.inflight -= 1;
    retire(sim, t, s);
}

/// The run is over, or main called exit and returned: every source stops.
pub fn stopServer(sim: *Sim, t: *Turns) void {
    if (sim.server == null) return;
    const s_ = &sim.sources;
    for (s_.list.items) |s| {
        if (t.madeSourcePoller()) |p| p.disarm(&s.waiter);
        s.done = true;
        if (!s.dirty) std.heap.smp_allocator.destroy(s);
    }
    s_.list.clearRetainingCapacity();
    s_.paused.clearRetainingCapacity();
    s_.timers.clearRetainingCapacity();
}

// ---- the deadline heap

fn timerPush(sources: *Sources, s: *Source, at: i64) Error!void {
    const i = sources.timers.items.len;
    try sources.timers.append(std.heap.smp_allocator, .{ .at = at, .source = s });
    s.timer = i;
    siftUp(sources, i);
}

fn timerRemove(sources: *Sources, s: *Source) void {
    const i = s.timer orelse return;
    s.timer = null;
    const last = sources.timers.pop().?;
    if (i == sources.timers.items.len) return;
    sources.timers.items[i] = last;
    last.source.timer = i;
    siftDown(sources, i);
    siftUp(sources, i);
}

fn swapTimers(sources: *Sources, a: usize, b: usize) void {
    const items = sources.timers.items;
    std.mem.swap(Timer, &items[a], &items[b]);
    items[a].source.timer = a;
    items[b].source.timer = b;
}

fn siftUp(sources: *Sources, start: usize) void {
    var i = start;
    while (i > 0) {
        const parent = (i - 1) / 2;
        if (sources.timers.items[parent].at <= sources.timers.items[i].at) return;
        swapTimers(sources, i, parent);
        i = parent;
    }
}

fn siftDown(sources: *Sources, start: usize) void {
    var i = start;
    const items = sources.timers.items;
    while (true) {
        var least = i;
        const l = 2 * i + 1;
        const r = l + 1;
        if (l < items.len and items[l].at < items[least].at) least = l;
        if (r < items.len and items[r].at < items[least].at) least = r;
        if (least == i) return;
        swapTimers(sources, i, least);
        i = least;
    }
}

test "the deadline heap gives the earliest first and removes from the middle" {
    var sources: Sources = .{};
    defer sources.timers.deinit(std.heap.smp_allocator);
    var xs: [8]Source = undefined;
    const ats = [_]i64{ 50, 10, 70, 30, 20, 80, 60, 40 };
    for (&xs, ats) |*x, at| {
        x.* = .{ .kind = .lines, .handle = 0, .to = 0, .idle_ms = 0, .since = 0 };
        try timerPush(&sources, x, at);
    }
    timerRemove(&sources, &xs[3]); // 30
    var got: std.ArrayList(i64) = .empty;
    defer got.deinit(std.testing.allocator);
    while (sources.timers.items.len > 0) {
        const top = sources.timers.items[0];
        try got.append(std.testing.allocator, top.at);
        timerRemove(&sources, top.source);
    }
    try std.testing.expectEqualSlices(i64, &.{ 10, 20, 40, 50, 60, 70, 80 }, got.items);
}

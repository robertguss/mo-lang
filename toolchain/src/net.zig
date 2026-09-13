//! Net: TCP for `mo run` (design-v0/09, Net), over std.Io, and `Net.fixture()` for
//! `mo test`. A Listener or a Conn is a capability; its `Value.Cap.handle` is its index in
//! `Net.listeners` or `Net.conns`, or under the simulator in `Fixture`'s.
//!
//! Every real call that can wait runs its blocking part as a concurrent task
//! (`io.concurrent`: a thread under std.Io.Threaded) and waits for it at most its deadline.
//! Past the deadline the task is canceled, which interrupts its system call, and the call
//! is `Timeout`. A task that finished as it was canceled keeps its result, so a connection
//! already accepted, or bytes already read, are never dropped. While a process waits it
//! gives up its turn, so the other processes go on (turns.zig).
//!
//! What a call past its deadline leaves: `accept` leaves the listener listening; `connect`
//! leaves no connection; `read_line` keeps the bytes of an unfinished line for the next
//! call; `write` closes the connection, since part of the text may have gone.
const std = @import("std");
const Io = std.Io;
const posix = std.posix;
const sim_mod = @import("sim.zig");
const vm_mod = @import("vm.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Error = vm_mod.Error;

/// The longest line `read_line` gives: 64 KiB before its newline.
pub const line_limit = 64 << 10;
/// Connections the kernel queues for a listener before `accept` takes them.
const backlog = 128;

pub const Row = enum { listen, connect, accept, port, read_line, write, close };

/// NetError's variants, by name.
pub const Failure = enum { Timeout, Refused, Closed, LineTooLong, Busy };

const Scan = union(enum) { line: []const u8, too_long, end, more };

/// The next line in `pending`, the bytes of the stream so far not given out: how many
/// bytes it takes, and the line, what stands in its way, or `more` to read first. `eof`:
/// nothing follows `pending`. A line of more than 64 KiB is too long, and the bytes up to
/// its newline are taken, at once or as they arrive (`skipping`).
fn scanLine(pending: []const u8, eof: bool, skipping: *bool) struct { usize, Scan } {
    var off: usize = 0;
    while (true) {
        const rest = pending[off..];
        if (std.mem.indexOfScalar(u8, rest, '\n')) |k| {
            off += k + 1;
            if (skipping.*) {
                skipping.* = false;
                continue;
            }
            if (k > line_limit) return .{ off, .too_long };
            return .{ off, .{ .line = withoutCr(rest[0..k]) } };
        }
        if (skipping.* or rest.len > line_limit) {
            const first = !skipping.*;
            skipping.* = !eof;
            if (first) return .{ pending.len, .too_long };
            return .{ pending.len, if (eof) .end else .more };
        }
        if (!eof) return .{ off, .more };
        if (rest.len == 0) return .{ off, .end };
        return .{ pending.len, .{ .line = withoutCr(rest) } };
    }
}

fn withoutCr(line: []const u8) []const u8 {
    return if (line.len > 0 and line[line.len - 1] == '\r') line[0 .. line.len - 1] else line;
}

/// `Ok(Some(line))`, `LineTooLong`, `Ok(None)`, or null for `more`.
fn lineResult(vm: *Vm, what: Scan) Error!?Value {
    return switch (what) {
        .line => |line| try vm.variant("Ok", &.{try vm.variant("Some", &.{.{ .string = try vm.heap.dupe(u8, line) }})}),
        .too_long => try fail(vm, .LineTooLong),
        .end => try vm.variant("Ok", &.{try vm.variant("None", &.{})}),
        .more => null,
    };
}

pub const Listener = struct {
    server: Io.net.Server,
    port: u16,
    /// An accept is waiting on it.
    accepting: bool = false,
};

pub const Conn = struct {
    stream: Io.net.Stream,
    /// Bytes read and not yet given out are buf[start..end]; allocated at the first read.
    buf: []u8 = &.{},
    start: usize = 0,
    end: usize = 0,
    /// The other side closed its end: what is buffered is the rest of the stream.
    eof: bool = false,
    /// `close` ran, a write timed out, the stream broke, or the process holding it stopped.
    closed: bool = false,
    /// The descriptor is closed: at once, or when the call waiting on it returns.
    released: bool = false,
    /// After LineTooLong, the rest of that line is dropped.
    skipping: bool = false,
    reading: bool = false,
    writing: bool = false,

    fn scan(c: *Conn) Scan {
        const taken, const what = scanLine(c.buf[c.start..c.end], c.eof, &c.skipping);
        c.start += taken;
        if (c.start == c.end) {
            c.start = 0;
            c.end = 0;
        }
        return what;
    }
};

/// Set when a call's task ends; also wakes main's thread when it hands out turns while it
/// waits (turns.zig).
pub const Waker = struct {
    done: Io.Event = .unset,
    main: ?*Io.Event = null,

    fn set(w: *Waker, io: Io) void {
        w.done.set(io);
        if (w.main) |m| m.set(io);
    }
};

fn wakerFor(vm: *Vm) Waker {
    const s = vm.sim orelse return .{};
    const t = s.turns orelse return .{};
    return .{ .main = &t.main_wake };
}

pub const Net = struct {
    io: Io,
    gpa: std.mem.Allocator,
    listeners: std.ArrayList(*Listener) = .empty,
    conns: std.ArrayList(*Conn) = .empty,

    /// One row; `a` is the receiver, then the parameters, then `within`.
    pub fn call(n: *Net, vm: *Vm, which: Row, a: []const Value) Error!Value {
        return switch (which) {
            .listen => n.listen(vm, @intCast(a[1].int)),
            .connect => n.connect(vm, a[1].string, @intCast(a[2].int), a[3].duration),
            .accept => n.accept(vm, n.listeners.items[a[0].cap.handle], a[1].duration),
            .port => .{ .int = n.listeners.items[a[0].cap.handle].port },
            .read_line => n.readLine(vm, n.conns.items[a[0].cap.handle], a[1].duration),
            .write => n.write(vm, n.conns.items[a[0].cap.handle], a[1].string, a[2].duration),
            .close => blk: {
                n.close(n.conns.items[a[0].cap.handle]);
                break :blk .none;
            },
        };
    }

    /// `net.listen(port)`: TCP on 127.0.0.1, at `port` or, given 0, at a free port the
    /// system picks. Binding does not wait, so the deadline is never reached. The socket
    /// reuses an address only its closed connections still hold: a port another listener
    /// holds is Busy, and a server that restarts at once binds again.
    fn listen(n: *Net, vm: *Vm, port: u16) Error!Value {
        const bound = bindLoopback(port) catch |err| return fail(vm, if (err == error.AddressInUse) .Busy else .Refused);
        const l = try n.gpa.create(Listener);
        l.* = .{ .server = .{ .socket = .{ .handle = bound.fd, .address = .{ .ip4 = .loopback(bound.port) } }, .options = {} }, .port = bound.port };
        const handle: u32 = @intCast(n.listeners.items.len);
        try n.listeners.append(n.gpa, l);
        return vm.variant("Ok", &.{.{ .cap = .{ .kind = .listener, .handle = handle } }});
    }

    fn connect(n: *Net, vm: *Vm, host: []const u8, port: u16, ms: i64) Error!Value {
        var waker = wakerFor(vm);
        var task = n.io.concurrent(connectTask, .{ n.io, host, port, &waker }) catch return fail(vm, .Busy);
        const in_time = n.wait(vm, &waker, ms) catch |err| {
            if (task.cancel(n.io)) |s| s.close(n.io) else |_| {}
            return err;
        };
        const r = if (in_time) task.await(n.io) else task.cancel(n.io);
        const stream = r catch |err| return fail(vm, switch (err) {
            error.Canceled, error.Timeout => .Timeout,
            error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.SystemResources => .Busy,
            else => .Refused,
        });
        return vm.variant("Ok", &.{try n.adopt(stream)});
    }

    fn accept(n: *Net, vm: *Vm, l: *Listener, ms: i64) Error!Value {
        if (l.accepting) return fail(vm, .Busy);
        l.accepting = true;
        defer l.accepting = false;
        var waker = wakerFor(vm);
        var task = n.io.concurrent(acceptTask, .{ n.io, &l.server, &waker }) catch return fail(vm, .Busy);
        const in_time = n.wait(vm, &waker, ms) catch |err| {
            if (task.cancel(n.io)) |s| s.close(n.io) else |_| {}
            return err;
        };
        const r = if (in_time) task.await(n.io) else task.cancel(n.io);
        const stream = r catch |err| return fail(vm, switch (err) {
            error.Canceled => .Timeout,
            error.SocketNotListening => .Closed,
            else => .Busy,
        });
        return vm.variant("Ok", &.{try n.adopt(stream)});
    }

    fn adopt(n: *Net, stream: Io.net.Stream) Error!Value {
        const c = try n.gpa.create(Conn);
        c.* = .{ .stream = stream };
        const handle: u32 = @intCast(n.conns.items.len);
        try n.conns.append(n.gpa, c);
        return .{ .cap = .{ .kind = .conn, .handle = handle } };
    }

    /// `conn.read_line`: the next line, `None` at the end of the stream, or why not.
    fn readLine(n: *Net, vm: *Vm, c: *Conn, ms: i64) Error!Value {
        if (c.closed) return fail(vm, .Closed);
        if (c.reading) return fail(vm, .Busy);
        if (c.buf.len == 0) c.buf = std.heap.page_allocator.alloc(u8, 2 * line_limit) catch return error.OutOfMemory;
        const t0 = Io.Clock.Timestamp.now(n.io, .awake);
        while (true) {
            if (try lineResult(vm, c.scan())) |v| return v;
            const left = ms - t0.durationTo(Io.Clock.Timestamp.now(n.io, .awake)).raw.toMilliseconds();
            if (left <= 0) return fail(vm, .Timeout);
            if (c.start > 0) {
                std.mem.copyForwards(u8, c.buf, c.buf[c.start..c.end]);
                c.end -= c.start;
                c.start = 0;
            }
            c.reading = true;
            var waker = wakerFor(vm);
            var task = n.io.concurrent(readTask, .{ n.io, c.stream, c.buf[c.end..], &waker }) catch {
                c.reading = false;
                return fail(vm, .Busy);
            };
            const in_time = n.wait(vm, &waker, left) catch |err| {
                _ = task.cancel(n.io) catch 0;
                c.reading = false;
                return err;
            };
            const r = if (in_time) task.await(n.io) else task.cancel(n.io);
            c.reading = false;
            if (c.closed) {
                n.release(c);
                return fail(vm, .Closed);
            }
            const got = r catch |err| {
                if (err == error.Canceled) return fail(vm, .Timeout);
                n.close(c);
                return fail(vm, .Closed);
            };
            if (got == 0) c.eof = true else c.end += got;
        }
    }

    /// `conn.write(text)`: all of the text, or why not.
    fn write(n: *Net, vm: *Vm, c: *Conn, text: []const u8, ms: i64) Error!Value {
        if (c.closed) return fail(vm, .Closed);
        if (c.writing) return fail(vm, .Busy);
        c.writing = true;
        var waker = wakerFor(vm);
        var task = n.io.concurrent(writeTask, .{ n.io, c.stream, text, &waker }) catch {
            c.writing = false;
            return fail(vm, .Busy);
        };
        const in_time = n.wait(vm, &waker, ms) catch |err| {
            task.cancel(n.io) catch {};
            c.writing = false;
            return err;
        };
        const r = if (in_time) task.await(n.io) else task.cancel(n.io);
        c.writing = false;
        if (c.closed) {
            n.release(c);
            return fail(vm, .Closed);
        }
        r catch |err| {
            n.close(c);
            return fail(vm, if (err == error.Canceled) .Timeout else .Closed);
        };
        return vm.variant("Ok", &.{.none});
    }

    /// `conn.close`: a call waiting on the connection ends, and every later call is Closed.
    pub fn close(n: *Net, c: *Conn) void {
        if (!c.closed) {
            c.closed = true;
            c.stream.shutdown(n.io, .both) catch {};
        }
        n.release(c);
    }

    /// Closes the descriptor once no call is waiting on it.
    fn release(n: *Net, c: *Conn) void {
        if (c.released or c.reading or c.writing) return;
        c.released = true;
        c.stream.close(n.io);
        if (c.buf.len > 0) std.heap.page_allocator.free(c.buf);
        c.buf = &.{};
        c.start = 0;
        c.end = 0;
    }

    /// A process holding these arguments stopped: every Conn among them closes.
    pub fn closeHeld(n: *Net, args: []const Value) void {
        for (args) |a| if (a == .cap and a.cap.kind == .conn) n.close(n.conns.items[a.cap.handle]);
    }

    /// The run is over: every connection and listener closes.
    pub fn closeAll(n: *Net) void {
        for (n.conns.items) |c| n.close(c);
        for (n.listeners.items) |l| l.server.socket.close(n.io);
        n.listeners.clearRetainingCapacity();
    }

    /// Waits for a task; under Mo.Server with processes the wait gives up the turn.
    fn wait(n: *Net, vm: *Vm, waker: *Waker, ms: i64) Error!bool {
        if (vm.sim) |s| if (s.turns) |t| return t.block(s, waker, ms);
        return waitFor(n.io, &waker.done, ms);
    }
};

/// Waits for `event` at most `ms` milliseconds; false when the deadline came first.
pub fn waitFor(io: Io, event: *Io.Event, ms: i64) bool {
    const deadline = (Io.Timeout{ .duration = .{ .raw = .fromMilliseconds(@max(ms, 0)), .clock = .awake } }).toDeadline(io);
    while (!event.isSet()) {
        event.waitTimeout(io, deadline) catch |err| switch (err) {
            error.Timeout => if (deadline.deadline.durationFromNow(io).raw.toNanoseconds() <= 0) return event.isSet(),
            error.Canceled => return event.isSet(),
        };
    }
    return true;
}

fn fail(vm: *Vm, f: Failure) Error!Value {
    return vm.variant("Error", &.{try vm.variant(@tagName(f), &.{})});
}

// ---- the blocking parts, each on a thread of its own

fn connectTask(io: Io, host: []const u8, port: u16, waker: *Waker) anyerror!Io.net.Stream {
    defer waker.set(io);
    if (Io.net.IpAddress.parse(host, port)) |addr| {
        return addr.connect(io, .{ .mode = .stream });
    } else |_| {}
    const name = try Io.net.HostName.init(host);
    return name.connect(io, port, .{ .mode = .stream });
}

fn acceptTask(io: Io, server: *Io.net.Server, waker: *Waker) Io.net.Server.AcceptError!Io.net.Stream {
    defer waker.set(io);
    while (true) {
        return server.accept(io) catch |err| {
            if (err == error.ConnectionAborted) continue;
            return err;
        };
    }
}

fn readTask(io: Io, stream: Io.net.Stream, dest: []u8, waker: *Waker) Io.net.Stream.Reader.Error!usize {
    defer waker.set(io);
    var data = [_][]u8{dest};
    return io.vtable.netRead(io.userdata, stream.socket.handle, &data);
}

fn writeTask(io: Io, stream: Io.net.Stream, text: []const u8, waker: *Waker) anyerror!void {
    defer waker.set(io);
    var w = stream.writer(io, &.{});
    w.interface.writeAll(text) catch return w.err orelse error.WriteFailed;
}

/// A listening TCP socket on 127.0.0.1 with SO_REUSEADDR alone. std.Io's listen sets
/// SO_REUSEPORT with it, which lets a second listener take a port the first still holds.
fn bindLoopback(port: u16) error{ AddressInUse, Refused }!struct { fd: posix.socket_t, port: u16 } {
    const sys = posix.system;
    const rc = sys.socket(posix.AF.INET, posix.SOCK.STREAM, posix.IPPROTO.TCP);
    if (posix.errno(rc) != .SUCCESS) return error.Refused;
    const fd: posix.socket_t = @intCast(rc);
    errdefer _ = sys.close(fd);
    posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1))) catch return error.Refused;
    var addr: posix.sockaddr.in = .{ .port = std.mem.nativeToBig(u16, port), .addr = std.mem.nativeToBig(u32, 0x7f00_0001) };
    switch (posix.errno(sys.bind(fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.in)))) {
        .SUCCESS => {},
        .ADDRINUSE => return error.AddressInUse,
        else => return error.Refused,
    }
    if (posix.errno(sys.listen(fd, backlog)) != .SUCCESS) return error.Refused;
    var len: posix.socklen_t = @sizeOf(posix.sockaddr.in);
    if (posix.errno(sys.getsockname(fd, @ptrCast(&addr), &len)) != .SUCCESS) return error.Refused;
    return .{ .fd = fd, .port = std.mem.bigToNative(u16, addr.port) };
}

// ---- Net.fixture()

/// `Net.fixture()`: one network in memory per test run (sim.zig), for a test that starts a
/// server process, connects a client, and drives the protocol with no real socket. What
/// one end writes waits for the other end to read it, and a closed end is the end of the
/// stream for the other. Nothing happens while a simulated call waits, so a call with
/// nothing to take (an accept with no client, a read with no whole line) waits its whole
/// deadline and is `Timeout`, as a real one would be.
/// In a seeded run with faults (step 9), a call that can wait can time out by the seed, and
/// a read or a write can find its connection `Closed`; each leaves the connection as the
/// real call would. `listen` does not wait, so it never fails that way.
pub const Fixture = struct {
    listeners: std.ArrayList(FixtureListener) = .empty,
    conns: std.ArrayList(FixtureConn) = .empty,
    /// The port `listen(0)` tries next.
    next_port: u16 = 49_152,

    const FixtureListener = struct { port: u16, backlog: std.ArrayList(u32) = .empty, head: usize = 0 };

    const FixtureConn = struct {
        /// The other end of the connection.
        peer: u32,
        /// What the peer wrote that this end has not read: inbound.items[start..].
        inbound: std.ArrayList(u8) = .empty,
        start: usize = 0,
        closed: bool = false,
        skipping: bool = false,
    };

    pub fn call(f: *Fixture, vm: *Vm, sim: *sim_mod.Sim, which: Row, a: []const Value) Error!Value {
        const gpa = sim.gpa;
        switch (which) {
            .listen => {
                var port: u16 = @intCast(a[1].int);
                if (port == 0) {
                    while (f.portTaken(f.next_port)) f.next_port +%= 1;
                    port = f.next_port;
                }
                if (f.portTaken(port)) return fail(vm, .Busy);
                try f.listeners.append(gpa, .{ .port = port });
                return vm.variant("Ok", &.{.{ .cap = .{ .kind = .listener, .handle = @intCast(f.listeners.items.len - 1) } }});
            },
            .port => return .{ .int = f.listeners.items[a[0].cap.handle].port },
            .connect => {
                if (sim.fault(null, a[3].duration) != null) return fail(vm, .Timeout);
                const port: u16 = @intCast(a[2].int);
                const l = for (f.listeners.items) |*l| {
                    if (l.port == port) break l;
                } else return fail(vm, .Refused);
                const client: u32 = @intCast(f.conns.items.len);
                try f.conns.append(gpa, .{ .peer = client + 1 });
                try f.conns.append(gpa, .{ .peer = client });
                try l.backlog.append(gpa, client + 1);
                return vm.variant("Ok", &.{.{ .cap = .{ .kind = .conn, .handle = client } }});
            },
            .accept => {
                const within = a[1].duration;
                if (sim.fault(null, within) != null) return fail(vm, .Timeout);
                const l = &f.listeners.items[a[0].cap.handle];
                if (l.head == l.backlog.items.len) {
                    sim.wait(within);
                    return fail(vm, .Timeout);
                }
                l.head += 1;
                return vm.variant("Ok", &.{.{ .cap = .{ .kind = .conn, .handle = l.backlog.items[l.head - 1] } }});
            },
            .read_line => {
                const h = a[0].cap.handle;
                const within = a[1].duration;
                if (f.conns.items[h].closed) return fail(vm, .Closed);
                if (sim.fault(.closed, within)) |fault| {
                    if (fault == .timeout) return fail(vm, .Timeout);
                    f.conns.items[h].closed = true;
                    return fail(vm, .Closed);
                }
                const c = &f.conns.items[h];
                const taken, const what = scanLine(c.inbound.items[c.start..], f.conns.items[c.peer].closed, &c.skipping);
                c.start += taken;
                const got = try lineResult(vm, what) orelse {
                    sim.wait(within);
                    return fail(vm, .Timeout);
                };
                if (c.start == c.inbound.items.len) {
                    c.inbound.clearRetainingCapacity();
                    c.start = 0;
                }
                return got;
            },
            .write => {
                const h = a[0].cap.handle;
                const peer = f.conns.items[h].peer;
                if (f.conns.items[h].closed) return fail(vm, .Closed);
                if (f.conns.items[peer].closed) {
                    f.conns.items[h].closed = true;
                    return fail(vm, .Closed);
                }
                // A write that times out closes the connection, as a real one does.
                if (sim.fault(.closed, a[2].duration)) |fault| {
                    f.conns.items[h].closed = true;
                    return fail(vm, if (fault == .timeout) .Timeout else .Closed);
                }
                try f.conns.items[peer].inbound.appendSlice(gpa, a[1].string);
                return vm.variant("Ok", &.{.none});
            },
            .close => {
                f.conns.items[a[0].cap.handle].closed = true;
                return .none;
            },
        }
    }

    fn portTaken(f: *const Fixture, port: u16) bool {
        for (f.listeners.items) |l| if (l.port == port) return true;
        return false;
    }

    /// A process holding these arguments stopped: every Conn among them closes.
    pub fn closeHeld(f: *Fixture, args: []const Value) void {
        for (args) |a| if (a == .cap and a.cap.kind == .conn) {
            f.conns.items[a.cap.handle].closed = true;
        };
    }
};

// ---- tests

test "a line is cut at its newline, keeps no \\r, and one past 64 KiB is dropped through its newline" {
    var buf: [4 * line_limit]u8 = undefined;
    var c: Conn = .{ .stream = undefined, .buf = &buf };
    const text = "a\r\nb\n";
    @memcpy(buf[0..text.len], text);
    c.end = text.len;
    try std.testing.expectEqualStrings("a", c.scan().line);
    try std.testing.expectEqualStrings("b", c.scan().line);
    try std.testing.expect(c.scan() == .more);

    @memset(buf[0 .. line_limit + 1], 'x');
    c.start = 0;
    c.end = line_limit + 1;
    try std.testing.expect(c.scan() == .too_long);
    try std.testing.expect(c.scan() == .more);
    @memcpy(buf[0..7], "xx\nok\nz");
    c.end = 7;
    try std.testing.expectEqualStrings("ok", c.scan().line);
    try std.testing.expect(c.scan() == .more);
    c.eof = true;
    try std.testing.expectEqualStrings("z", c.scan().line);
    try std.testing.expect(c.scan() == .end);
}

fn named(v: Value) []const u8 {
    const inner = v.variant.fields[0];
    return if (inner == .variant) inner.variant.name else v.variant.name;
}

test "Net.fixture: bytes one end writes reach the other, lines are cut as on a socket, nothing to take waits its deadline, and close ends the stream" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var machine: Vm = .init(arena, undefined, 0);
    var s: sim_mod.Sim = .init(&machine, 0, "fixture");
    machine.sim = &s;
    const f = &s.fixture;
    const net_cap: Value = .{ .cap = .{ .kind = .net } };
    const d: Value = .{ .duration = 100 };

    const listener = (try f.call(&machine, &s, .listen, &.{ net_cap, .{ .int = 0 }, d })).variant.fields[0];
    const port = (try f.call(&machine, &s, .port, &.{listener})).int;
    try std.testing.expectEqualStrings("Busy", named(try f.call(&machine, &s, .listen, &.{ net_cap, .{ .int = port }, d })));
    try std.testing.expectEqualStrings("Refused", named(try f.call(&machine, &s, .connect, &.{ net_cap, .{ .string = "localhost" }, .{ .int = 1 }, d })));
    try std.testing.expectEqualStrings("Timeout", named(try f.call(&machine, &s, .accept, &.{ listener, d })));
    try std.testing.expectEqual(@as(i64, 100), s.waited);

    const client = (try f.call(&machine, &s, .connect, &.{ net_cap, .{ .string = "localhost" }, .{ .int = port }, d })).variant.fields[0];
    _ = try f.call(&machine, &s, .write, &.{ client, .{ .string = "a\r\nb" }, d });
    const conn = (try f.call(&machine, &s, .accept, &.{ listener, d })).variant.fields[0];
    const read: []const Value = &.{ conn, d };
    try std.testing.expectEqualStrings("a", (try f.call(&machine, &s, .read_line, read)).variant.fields[0].variant.fields[0].string);
    try std.testing.expectEqualStrings("Timeout", named(try f.call(&machine, &s, .read_line, read)));
    try std.testing.expectEqual(@as(i64, 200), s.waited);
    const long = try arena.alloc(u8, line_limit + 3);
    @memset(long, 'x');
    long[0] = '\n';
    long[long.len - 1] = '\n';
    _ = try f.call(&machine, &s, .write, &.{ client, .{ .string = long }, d });
    _ = try f.call(&machine, &s, .write, &.{ client, .{ .string = "c\n" }, d });
    try std.testing.expectEqualStrings("b", (try f.call(&machine, &s, .read_line, read)).variant.fields[0].variant.fields[0].string);
    try std.testing.expectEqualStrings("LineTooLong", named(try f.call(&machine, &s, .read_line, read)));
    try std.testing.expectEqualStrings("c", (try f.call(&machine, &s, .read_line, read)).variant.fields[0].variant.fields[0].string);

    _ = try f.call(&machine, &s, .close, &.{client});
    try std.testing.expectEqualStrings("None", (try f.call(&machine, &s, .read_line, read)).variant.fields[0].variant.name);
    try std.testing.expectEqualStrings("Closed", named(try f.call(&machine, &s, .write, &.{ conn, .{ .string = "late" }, d })));
    try std.testing.expectEqualStrings("Closed", named(try f.call(&machine, &s, .read_line, &.{ client, d })));
}

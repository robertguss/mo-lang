//! Net: TCP for `mo run` (design-v0/09, Net), and `Net.fixture()` for `mo test`. A Listener
//! or a Conn is a capability; its `Value.Cap.handle` is its index in `Net.listeners` or
//! `Net.conns`, or under the simulator in `Fixture`'s.
//!
//! Every socket is nonblocking (step 21). A call that can wait tries its system call, and when
//! the socket is not ready waits for it at most its deadline: under Mo.Server with processes in
//! the poller, giving up the thread (turns.zig, block), so the other processes go on; with no
//! processes in poll(2) on this thread. Past the deadline the call is `Timeout`, and bytes
//! already read or a connection already accepted are never dropped.
//!
//! What a call past its deadline leaves: `accept` leaves the listener listening; `connect`
//! leaves no connection; `read_line` keeps the bytes of an unfinished line for the next
//! call; `write` closes the connection, since part of the text may have gone.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const posix = std.posix;
const poller = @import("poller.zig");
const sim_mod = @import("sim.zig");
const vm_mod = @import("vm.zig");

const Vm = vm_mod.Vm;
const Value = vm_mod.Value;
const Error = vm_mod.Error;

/// The longest line `read_line` gives: 64 KiB before its newline.
pub const line_limit = 64 << 10;
/// A connection's read buffer at its first read; it grows to what the reader allows.
pub const buffer_initial = 16 << 10;
/// Connections the kernel queues for a listener before `accept` takes them.
const backlog = 128;

pub const Row = enum { listen, connect, accept, port, read_line, write, close, serve, lines };

/// NetError's variants, by name.
pub const Failure = enum { Timeout, Refused, Closed, LineTooLong, Busy };

pub const Scan = union(enum) { line: []const u8, too_long, end, more };

/// What a call that gives a connection came to: its handle, or why not.
pub const Outcome = union(enum) { ok: u32, failed: Failure };

/// What one read into a connection's buffer came to (`Net.fill`).
pub const Filled = enum { got, eof, timeout, closed, busy, full };

fn connResult(vm: *Vm, o: Outcome) Error!Value {
    return switch (o) {
        .ok => |h| vm.variant("Ok", &.{.{ .cap = .{ .kind = .conn, .handle = h } }}),
        .failed => |f| fail(vm, f),
    };
}

/// The next line in `pending`, the bytes of the stream so far not given out: how many
/// bytes it takes, and the line, what stands in its way, or `more` to read first. `eof`:
/// nothing follows `pending`. A line of more than 64 KiB is too long, and the bytes up to
/// its newline are taken, at once or as they arrive (`skipping`).
pub fn scanLine(pending: []const u8, eof: bool, skipping: *bool) struct { usize, Scan } {
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
        .line => |line| try vm.variant("Ok", &.{try vm.variant("Some", &.{.{ .string = try vm_mod.rawDupe(vm.heap, u8, line) }})}),
        .too_long => try fail(vm, .LineTooLong),
        .end => try vm.variant("Ok", &.{try vm.variant("None", &.{})}),
        .more => null,
    };
}

/// `Conn.listener` of a connection no listener accepted.
pub const no_listener: u32 = std.math.maxInt(u32);

pub const Listener = struct {
    server: Io.net.Server,
    port: u16,
    /// An accept is waiting on it.
    accepting: bool = false,
    /// `serve` gave it to the runtime (sources.zig): an accept on it is Busy.
    served: bool = false,
};

pub const Conn = struct {
    stream: Io.net.Stream,
    /// Bytes read and not yet given out are buf[start..end]; allocated at the first read, and
    /// given back while the runtime waits on a connection with nothing buffered.
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
    /// `lines` gave its reading to the runtime (sources.zig): a read_line on it is Busy.
    lining: bool = false,
    /// The listener that accepted it, or no_listener: a wait on that listener can hear from
    /// a process holding it only after that process acts (sim.zig, held sends).
    listener: u32 = no_listener,

    pub fn scan(c: *Conn) Scan {
        const taken, const what = scanLine(c.buf[c.start..c.end], c.eof, &c.skipping);
        c.start += taken;
        if (c.start == c.end) {
            c.start = 0;
            c.end = 0;
        }
        return what;
    }

    pub fn fd(c: *const Conn) posix.fd_t {
        return c.stream.socket.handle;
    }

    /// Makes room in the buffer for the next read: moves what is buffered to the front, and
    /// grows the buffer from `initial` bytes up to `cap`. False when it holds `cap` bytes.
    pub fn roomToRead(c: *Conn, initial: usize, cap: usize) Error!bool {
        if (c.start > 0) {
            std.mem.copyForwards(u8, c.buf, c.buf[c.start..c.end]);
            c.end -= c.start;
            c.start = 0;
        }
        if (c.end < c.buf.len) return true;
        if (c.buf.len >= cap) return false;
        const size = if (c.buf.len == 0) @min(initial, cap) else @min(cap, 2 * c.buf.len);
        const gpa = std.heap.smp_allocator;
        const grown = gpa.alloc(u8, size) catch return error.OutOfMemory;
        @memcpy(grown[0..c.end], c.buf[0..c.end]);
        if (c.buf.len > 0) gpa.free(c.buf);
        c.buf = grown;
        return true;
    }

    /// With nothing buffered, the buffer goes back: a connection at rest holds none.
    pub fn giveBack(c: *Conn) void {
        if (c.start != c.end or c.buf.len == 0) return;
        std.heap.smp_allocator.free(c.buf);
        c.buf = &.{};
        c.start = 0;
        c.end = 0;
    }
};

/// An Exchange (http.zig): the connection it answers on, and until it is answered the
/// request's bytes, which `exchange.request` reads.
pub const Exchange = struct {
    conn: u32,
    request: []u8,
    answered: bool = false,

    /// Answered: the request's bytes are no longer kept.
    pub fn forget(e: *Exchange, gpa: std.mem.Allocator) void {
        if (!e.answered) gpa.free(e.request);
        e.answered = true;
        e.request = &.{};
    }
};

// ---- nonblocking system calls

pub fn nonblocking(fd: posix.fd_t) void {
    const nb: u32 = @bitCast(posix.O{ .NONBLOCK = true });
    if (builtin.os.tag == .linux) {
        const linux = std.os.linux;
        const flags = linux.fcntl(fd, linux.F.GETFL, 0);
        if (posix.errno(flags) != .SUCCESS) return;
        _ = linux.fcntl(fd, linux.F.SETFL, flags | nb);
    } else {
        const flags = std.c.fcntl(fd, std.c.F.GETFL);
        if (flags < 0) return;
        _ = std.c.fcntl(fd, std.c.F.SETFL, flags | @as(c_int, @bitCast(nb)));
    }
}

/// What one nonblocking read or write came to: bytes, not ready, or a broken stream.
pub const Io1 = union(enum) { done: usize, again, broke };

pub fn readOne(fd: posix.fd_t, dest: []u8) Io1 {
    while (true) {
        const rc = posix.system.read(fd, dest.ptr, dest.len);
        switch (posix.errno(rc)) {
            .SUCCESS => return .{ .done = @intCast(rc) },
            .INTR => continue,
            .AGAIN => return .again,
            else => return .broke,
        }
    }
}

/// A write that never raises SIGPIPE: a peer that is gone is a broken stream.
pub fn writeOne(fd: posix.fd_t, bytes: []const u8) Io1 {
    while (true) {
        const rc = posix.system.sendto(fd, bytes.ptr, bytes.len, posix.MSG.NOSIGNAL, null, 0);
        switch (posix.errno(rc)) {
            .SUCCESS => return .{ .done = @intCast(rc) },
            .INTR => continue,
            .AGAIN => return .again,
            else => return .broke,
        }
    }
}

pub const Accepted = union(enum) { ok: posix.fd_t, again, closed, busy };

/// One connection from the listening socket's queue, nonblocking, or why not.
pub fn acceptOne(fd: posix.fd_t) Accepted {
    while (true) {
        const rc = posix.system.accept(fd, null, null);
        switch (posix.errno(rc)) {
            .SUCCESS => {
                const conn: posix.fd_t = @intCast(rc);
                nonblocking(conn);
                return .{ .ok = conn };
            },
            .INTR, .CONNABORTED => continue,
            .AGAIN => return .again,
            .INVAL, .BADF, .NOTSOCK => return .closed,
            else => return .busy,
        }
    }
}

pub const Net = struct {
    io: Io,
    gpa: std.mem.Allocator,
    listeners: std.ArrayList(*Listener) = .empty,
    conns: std.ArrayList(*Conn) = .empty,
    /// Each Exchange's connection and request (http.zig); its handle is its index.
    exchanges: std.ArrayList(Exchange) = .empty,

    fn now(n: *const Net) i64 {
        return Io.Clock.Timestamp.now(n.io, .awake).raw.toMilliseconds();
    }

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
            // The runtime's loops (sources.zig); vm.zig sends them there.
            .serve, .lines => unreachable,
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
        return connResult(vm, try n.connectConn(vm, host, port, ms));
    }

    /// A connection to `host` at `port`, as `connect` makes it (http.zig makes its own).
    pub fn connectConn(n: *Net, vm: *Vm, host: []const u8, port: u16, ms: i64) Error!Outcome {
        const deadline = n.now() + @max(ms, 0);
        const address = Io.net.IpAddress.parse(host, port) catch {
            // A name, not an address: looked up and connected on this thread, which waits.
            const name = Io.net.HostName.init(host) catch return .{ .failed = .Refused };
            const stream = name.connect(n.io, port, .{ .mode = .stream }) catch |err| return .{ .failed = switch (err) {
                error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded, error.SystemResources => .Busy,
                else => .Refused,
            } };
            nonblocking(stream.socket.handle);
            return .{ .ok = try n.adopt(stream.socket.handle) };
        };
        const family: u32 = if (address == .ip4) posix.AF.INET else posix.AF.INET6;
        const rc = posix.system.socket(family, posix.SOCK.STREAM, posix.IPPROTO.TCP);
        switch (posix.errno(rc)) {
            .SUCCESS => {},
            .MFILE, .NFILE, .NOBUFS, .NOMEM => return .{ .failed = .Busy },
            else => return .{ .failed = .Refused },
        }
        const fd: posix.fd_t = @intCast(rc);
        nonblocking(fd);
        var in4: posix.sockaddr.in = undefined;
        var in6: posix.sockaddr.in6 = undefined;
        const sa: *const posix.sockaddr, const len: posix.socklen_t = switch (address) {
            .ip4 => |a| blk: {
                in4 = .{ .port = std.mem.nativeToBig(u16, port), .addr = @bitCast(a.bytes) };
                break :blk .{ @ptrCast(&in4), @sizeOf(posix.sockaddr.in) };
            },
            .ip6 => |a| blk: {
                in6 = .{ .port = std.mem.nativeToBig(u16, port), .flowinfo = 0, .addr = a.bytes, .scope_id = 0 };
                break :blk .{ @ptrCast(&in6), @sizeOf(posix.sockaddr.in6) };
            },
        };
        const failed: ?Failure = switch (posix.errno(posix.system.connect(fd, sa, len))) {
            .SUCCESS => null,
            .INPROGRESS, .AGAIN => blk: {
                const in_time = n.wait(vm, fd, .write, deadline - n.now()) catch |err| {
                    _ = posix.system.close(fd);
                    return err;
                };
                if (!in_time) break :blk .Timeout;
                var so_error: c_int = 0;
                var so_len: posix.socklen_t = @sizeOf(c_int);
                _ = posix.system.getsockopt(fd, posix.SOL.SOCKET, posix.SO.ERROR, @ptrCast(&so_error), &so_len);
                break :blk if (so_error == 0) null else .Refused;
            },
            else => .Refused,
        };
        if (failed) |f| {
            _ = posix.system.close(fd);
            return .{ .failed = f };
        }
        return .{ .ok = try n.adopt(fd) };
    }

    fn accept(n: *Net, vm: *Vm, l: *Listener, ms: i64) Error!Value {
        return connResult(vm, try n.acceptConn(vm, l, ms));
    }

    /// The next client of `l`, as `accept` takes it (http.zig takes its own).
    pub fn acceptConn(n: *Net, vm: *Vm, l: *Listener, ms: i64) Error!Outcome {
        if (l.accepting or l.served) return .{ .failed = .Busy };
        l.accepting = true;
        defer l.accepting = false;
        const deadline = n.now() + @max(ms, 0);
        const fd = l.server.socket.handle;
        while (true) {
            switch (acceptOne(fd)) {
                .ok => |conn| {
                    const h = try n.adopt(conn);
                    for (n.listeners.items, 0..) |x, i| if (x == l) {
                        n.conns.items[h].listener = @intCast(i);
                    };
                    return .{ .ok = h };
                },
                .again => {
                    const left = deadline - n.now();
                    if (left <= 0 or !try n.wait(vm, fd, .read, left)) return .{ .failed = .Timeout };
                },
                .closed => return .{ .failed = .Closed },
                .busy => return .{ .failed = .Busy },
            }
        }
    }

    pub fn adopt(n: *Net, fd: posix.fd_t) Error!u32 {
        const c = try n.gpa.create(Conn);
        c.* = .{ .stream = .{ .socket = .{ .handle = fd, .address = .{ .ip4 = .loopback(0) } } } };
        const handle: u32 = @intCast(n.conns.items.len);
        try n.conns.append(n.gpa, c);
        return handle;
    }

    /// `conn.read_line`: the next line, `None` at the end of the stream, or why not.
    fn readLine(n: *Net, vm: *Vm, c: *Conn, ms: i64) Error!Value {
        if (c.closed) return fail(vm, .Closed);
        if (c.reading or c.lining) return fail(vm, .Busy);
        const t0 = n.now();
        while (true) {
            if (try lineResult(vm, c.scan())) |v| return v;
            const left = ms - (n.now() - t0);
            if (left <= 0) return fail(vm, .Timeout);
            switch (try n.fill(vm, c, left, buffer_initial, 2 * line_limit)) {
                .got, .eof => {},
                .timeout => return fail(vm, .Timeout),
                .closed => return fail(vm, .Closed),
                .busy => return fail(vm, .Busy),
                // A line too long is taken before the buffer fills.
                .full => unreachable,
            }
        }
    }

    /// Reads what arrives next on `c` into its buffer, waiting at most `ms`. The buffer is
    /// `initial` bytes at the first read and grows to at most `cap`; `full` when it holds
    /// `cap` bytes not given out. A read past its deadline keeps what was buffered; a stream
    /// that broke closes the connection.
    pub fn fill(n: *Net, vm: *Vm, c: *Conn, ms: i64, initial: usize, cap: usize) Error!Filled {
        if (!try c.roomToRead(initial, cap)) return .full;
        const deadline = n.now() + @max(ms, 0);
        c.reading = true;
        const got: Io1 = while (true) {
            const r = readOne(c.fd(), c.buf[c.end..]);
            if (r != .again) break r;
            const left = deadline - n.now();
            if (left <= 0) break .again;
            const in_time = n.wait(vm, c.fd(), .read, left) catch |err| {
                c.reading = false;
                return err;
            };
            if (c.closed or !in_time) break .again;
        };
        c.reading = false;
        if (c.closed) {
            n.release(c);
            return .closed;
        }
        switch (got) {
            .again => return .timeout,
            .broke => {
                n.close(c);
                return .closed;
            },
            .done => |k| {
                if (k == 0) {
                    c.eof = true;
                    return .eof;
                }
                c.end += k;
                return .got;
            },
        }
    }

    /// `conn.write(text)`: all of the text, or why not.
    fn write(n: *Net, vm: *Vm, c: *Conn, text: []const u8, ms: i64) Error!Value {
        if (try n.writeAll(vm, c, text, ms)) |f| return fail(vm, f);
        return vm.variant("Ok", &.{.none});
    }

    /// All of `text` on `c`, as `write` writes it: null, or why not.
    pub fn writeAll(n: *Net, vm: *Vm, c: *Conn, text: []const u8, ms: i64) Error!?Failure {
        if (c.closed) return .Closed;
        if (c.writing) return .Busy;
        c.writing = true;
        const deadline = n.now() + @max(ms, 0);
        var done: usize = 0;
        var failed: ?Failure = null;
        while (done < text.len) {
            switch (writeOne(c.fd(), text[done..])) {
                .done => |k| done += k,
                .broke => {
                    failed = .Closed;
                    break;
                },
                .again => {
                    const left = deadline - n.now();
                    const in_time = left > 0 and (n.wait(vm, c.fd(), .write, left) catch |err| {
                        c.writing = false;
                        return err;
                    });
                    if (c.closed) break;
                    if (!in_time) {
                        failed = .Timeout;
                        break;
                    }
                },
            }
        }
        c.writing = false;
        if (c.closed) {
            n.release(c);
            return .Closed;
        }
        if (failed) |f| {
            n.close(c);
            return f;
        }
        return null;
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
    pub fn release(n: *Net, c: *Conn) void {
        if (c.released or c.reading or c.writing) return;
        c.released = true;
        c.stream.close(n.io);
        if (c.buf.len > 0) std.heap.smp_allocator.free(c.buf);
        c.buf = &.{};
        c.start = 0;
        c.end = 0;
    }

    /// A process holding these arguments stopped: every Conn and Exchange among them closes.
    pub fn closeHeld(n: *Net, args: []const Value) void {
        for (args) |a| if (a == .cap) switch (a.cap.kind) {
            .conn => n.close(n.conns.items[a.cap.handle]),
            .exchange => n.close(n.conns.items[n.exchanges.items[a.cap.handle].conn]),
            else => {},
        };
    }

    /// The run is over: every connection and listener closes.
    pub fn closeAll(n: *Net) void {
        for (n.exchanges.items) |*e| e.forget(n.gpa);
        for (n.conns.items) |c| n.close(c);
        for (n.listeners.items) |l| l.server.socket.close(n.io);
        n.listeners.clearRetainingCapacity();
    }

    /// Waits for `fd` to be ready: under Mo.Server with processes the wait gives up the thread.
    fn wait(n: *Net, vm: *Vm, fd: posix.fd_t, filter: poller.Filter, ms: i64) Error!bool {
        _ = n;
        if (vm.sim) |s| if (s.turns) |t| return t.block(s, fd, filter, ms);
        return poller.pollOne(fd, filter, ms);
    }
};

fn fail(vm: *Vm, f: Failure) Error!Value {
    return vm.variant("Error", &.{try vm.variant(@tagName(f), &.{})});
}

/// A listening TCP socket on 127.0.0.1 with SO_REUSEADDR alone, nonblocking. std.Io's listen
/// sets SO_REUSEPORT with it, which lets a second listener take a port the first still holds.
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
    nonblocking(fd);
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
    exchanges: std.ArrayList(Exchange) = .empty,
    /// The port `listen(0)` tries next.
    next_port: u16 = 49_152,

    /// `served`: `serve` gave it to the runtime (sources.zig), and an accept on it is Busy.
    pub const FixtureListener = struct { port: u16, backlog: std.ArrayList(u32) = .empty, head: usize = 0, served: bool = false };

    pub const FixtureConn = struct {
        /// The other end of the connection.
        peer: u32,
        /// What the peer wrote that this end has not read: inbound.items[start..].
        inbound: std.ArrayList(u8) = .empty,
        start: usize = 0,
        closed: bool = false,
        skipping: bool = false,
        /// The listener whose backlog it went into, or no_listener for a client's end.
        listener: u32 = no_listener,
        /// `lines` gave its reading to the runtime (sources.zig): a read_line on it is Busy.
        lining: bool = false,
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
                const li = for (f.listeners.items, 0..) |l, i| {
                    if (l.port == port) break i;
                } else return fail(vm, .Refused);
                const l = &f.listeners.items[li];
                const client: u32 = @intCast(f.conns.items.len);
                try f.conns.append(gpa, .{ .peer = client + 1 });
                try f.conns.append(gpa, .{ .peer = client, .listener = @intCast(li) });
                try l.backlog.append(gpa, client + 1);
                return vm.variant("Ok", &.{.{ .cap = .{ .kind = .conn, .handle = client } }});
            },
            .accept => {
                const within = a[1].duration;
                if (sim.fault(null, within) != null) return fail(vm, .Timeout);
                const l = &f.listeners.items[a[0].cap.handle];
                if (l.served) return fail(vm, .Busy);
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
                if (f.conns.items[h].lining) return fail(vm, .Busy);
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
            .serve, .lines => unreachable,
        }
    }

    pub fn portTaken(f: *const Fixture, port: u16) bool {
        for (f.listeners.items) |l| if (l.port == port) return true;
        return false;
    }

    /// A process holding these arguments stopped: every Conn and Exchange among them closes.
    pub fn closeHeld(f: *Fixture, args: []const Value) void {
        for (args) |a| if (a == .cap) switch (a.cap.kind) {
            .conn => f.conns.items[a.cap.handle].closed = true,
            .exchange => f.conns.items[f.exchanges.items[a.cap.handle].conn].closed = true,
            else => {},
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

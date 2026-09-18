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
const brick = @import("bricks/tls.zig");
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

/// What one read of ciphertext into the TLS engine came to (step 36). `broken`: a record the
/// engine refused, whose alert is written before the connection closes.
const Fed = enum { got, eof, timeout, closed, broken };

/// What `TlsServer.accept` came to: the handshake finished, or the `TlsError` it gives back
/// (every one but `BadPem`, which only `Tls.server` can give).
pub const Handshook = enum { done, Handshake, Timeout, Closed, Untrusted };

/// The engine a handshake starts (step 37): a server's connection, or a client's with its hello
/// queued. Every step after is the same for both.
pub const Side = union(enum) {
    server: *brick.Server,
    client: struct { client: *brick.Client, host: []const u8, now: i64 },

    pub fn start(side: Side) Error!*brick.Conn {
        return switch (side) {
            .server => |s| brick.mo_tls_conn_new(s),
            .client => |c| brick.mo_tls_connect(c.client, c.host.ptr, c.host.len, c.now),
        } orelse error.OutOfMemory;
    }

    pub fn row(side: Side) []const u8 {
        return if (side == .server) "TlsServer.accept" else "TlsClient.connect";
    }
};

/// What an engine that failed its handshake gives the program: `Untrusted` when this client
/// refused the server's chain (its alert already written), `Handshake` for anything else.
fn refused(t: *brick.Conn) Handshook {
    return if (brick.mo_tls_untrusted(t)) .Untrusted else .Handshake;
}

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
    /// A read (`read_line`, a handshake's read) or a write waits on it: a second of either kind
    /// is Busy. Each goes on while the other waits (step 38): a read proceeds while a write on the
    /// same connection is blocked on the peer.
    reading: bool = false,
    writing: bool = false,
    /// Behind TLS: ciphertext `mo_tls_flush` gave is on its way to the socket, and whoever took
    /// it may be waiting to write the rest. Only that caller writes to the socket until it is
    /// done, so a record is never cut by another (a read's KeyUpdate answer, an alert); the
    /// engine seals each record whole into one queue, in order, under the runtime's lock.
    flushing: bool = false,
    /// `lines` gave its reading to the runtime (sources.zig): a read_line on it is Busy.
    lining: bool = false,
    /// The listener that accepted it, or no_listener: a wait on that listener can hear from
    /// a process holding it only after that process acts (sim.zig, held sends).
    listener: u32 = no_listener,
    /// The TLS engine behind it (step 36, bricks/tls.zig), or null for a plain socket. With
    /// one, `fill` reads ciphertext off the socket and gives the plaintext the records held,
    /// and `writeAll` puts the engine's ciphertext on the socket; `buf`, `read_line`, `write`,
    /// `lines`, and the NetErrors are the same either way.
    tls: ?*brick.Conn = null,
    /// The row that first read or wrote on it: `TlsServer.accept` takes only a connection
    /// nothing has used, and names this row in its crash when one has.
    used: []const u8 = "",

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
    /// The TLS servers `Tls.server` made (step 36): a `TlsServer`'s handle is its index. They
    /// live here, beside the listeners, because every process's vm reaches the same sockets;
    /// the brick owns each one's chain and key, and `closeAll` gives them back. The clients
    /// `Tls.client` made (step 37) are kept the same way.
    tls_servers: std.ArrayList(*brick.Server) = .empty,
    tls_clients: std.ArrayList(*brick.Client) = .empty,

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
        if (c.used.len == 0) c.used = "Conn.read_line";
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
        if (c.tls) |t| return n.fillTls(vm, c, t, ms, initial, cap);
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
        if (c.used.len == 0) c.used = "Conn.write";
        if (c.closed) return .Closed;
        if (c.writing) return .Busy;
        c.writing = true;
        if (c.tls) |t| return n.writeAllTls(vm, c, t, text, ms);
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

    // ---- TLS (step 36): the same rows, with the brick's engine between the socket and `buf`

    /// The ciphertext a socket read or a flush moves at once: one record and its header.
    const wire_size = brick.max_ciphertext + 5;

    /// Everything the engine owes the socket, waiting for the socket to take it: a write's
    /// records, and a handshake's flight. Null when it all went; a Failure when the deadline
    /// passed or the stream broke. The caller is the connection's one flusher while it runs
    /// (`flushing`); what the engine queues meanwhile (a read's KeyUpdate answer) goes out in
    /// this same loop, after the records before it.
    fn flushTls(n: *Net, vm: *Vm, c: *Conn, t: *brick.Conn, deadline: i64) Error!?Failure {
        var wire: [wire_size]u8 = undefined;
        std.debug.assert(!c.flushing);
        c.flushing = true;
        defer c.flushing = false;
        while (true) {
            var got: usize = 0;
            if (brick.mo_tls_flush(t, &wire, wire.len, &got) != brick.ok) return .Closed;
            if (got == 0) return null;
            var done: usize = 0;
            defer brick.mo_tls_sent(t, done);
            while (done < got) {
                switch (writeOne(c.fd(), wire[done..got])) {
                    .done => |k| done += k,
                    .broke => return .Closed,
                    .again => {
                        const left = deadline - n.now();
                        const in_time = left > 0 and try n.wait(vm, c.fd(), .write, left);
                        if (c.closed) return .Closed;
                        if (!in_time) return .Timeout;
                    },
                }
            }
        }
    }

    /// One read of ciphertext off the socket into the engine. `got` and `eof` say what came;
    /// `timeout` and `closed` are the Filled the caller gives back.
    fn feedTls(n: *Net, vm: *Vm, c: *Conn, t: *brick.Conn, deadline: i64) Error!Fed {
        var wire: [wire_size]u8 = undefined;
        c.reading = true;
        const got: Io1 = while (true) {
            const r = readOne(c.fd(), &wire);
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
                // The peer's stream ended with no close_notify: a truncated session, which the
                // program sees as the end of the stream, as a plain socket's end is.
                if (k == 0) return .eof;
                if (brick.mo_tls_feed(t, &wire, k) != brick.ok) return .broken;
                return .got;
            },
        }
    }

    /// `fill` behind TLS: the plaintext the records held, read into `buf` as a plain read
    /// fills it. A record that does not check out ends the connection, after its alert has
    /// been written.
    fn fillTls(n: *Net, vm: *Vm, c: *Conn, t: *brick.Conn, ms: i64, initial: usize, cap: usize) Error!Filled {
        const deadline = n.now() + @max(ms, 0);
        while (true) {
            var got: usize = 0;
            const rc = brick.mo_tls_read(t, c.buf[c.end..].ptr, c.buf.len - c.end, &got);
            if (rc == brick.ok and got > 0) {
                c.end += got;
                return .got;
            }
            switch (rc) {
                brick.closed => {
                    c.eof = true;
                    return .eof;
                },
                // The alert goes out if the socket takes it now and no write is mid-record.
                brick.failed => {
                    n.drainNow(c, t);
                    n.close(c);
                    return .closed;
                },
                else => {},
            }
            // What the engine owes the socket (a KeyUpdate answered) goes as far as the socket
            // takes it now; a read never waits for the socket's send side, so it goes on while
            // a write on the same connection waits for the peer (step 38).
            n.drainNow(c, t);
            switch (try n.feedTls(vm, c, t, deadline)) {
                .got => {},
                .eof => {
                    c.eof = true;
                    return .eof;
                },
                .timeout => return .timeout,
                .closed => return .closed,
                // The engine answered with an alert: it goes out if it can, then the connection
                // closes.
                .broken => {
                    n.drainNow(c, t);
                    n.close(c);
                    return .closed;
                },
            }
            if (!try c.roomToRead(initial, cap)) return .full;
        }
    }

    /// `writeAll` behind TLS: the text as records, then the ciphertext on the socket.
    /// `c.writing` is set; it is let go here.
    fn writeAllTls(n: *Net, vm: *Vm, c: *Conn, t: *brick.Conn, text: []const u8, ms: i64) Error!?Failure {
        const deadline = n.now() + @max(ms, 0);
        const failed: ?Failure = if (brick.mo_tls_write(t, text.ptr, text.len) != brick.ok)
            .Closed
        else
            n.flushTls(vm, c, t, deadline) catch |err| {
                c.writing = false;
                return err;
            };
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

    /// One nonblocking read into `c.buf`, through the TLS engine when there is one: what the
    /// runtime's loops use (sources.zig), since they do their own waiting in the poller. The
    /// engine's own bytes (a KeyUpdate answered, an alert) go out first, as far as the socket
    /// takes them now, and never while a `write` is in the middle of its own flush.
    pub fn readInto(n: *Net, c: *Conn) Io1 {
        const t = c.tls orelse return readOne(c.fd(), c.buf[c.end..]);
        var wire: [wire_size]u8 = undefined;
        while (true) {
            n.drainNow(c, t);
            var got: usize = 0;
            const rc = brick.mo_tls_read(t, c.buf[c.end..].ptr, c.buf.len - c.end, &got);
            if (rc == brick.ok and got > 0) return .{ .done = got };
            // close_notify from the client is the end of the stream, as a plain socket's is.
            if (rc == brick.closed) return .{ .done = 0 };
            if (rc == brick.failed) return .broke;
            switch (readOne(c.fd(), &wire)) {
                .done => |k| {
                    if (k == 0) return .{ .done = 0 };
                    if (brick.mo_tls_feed(t, &wire, k) != brick.ok) {
                        n.drainNow(c, t);
                        return .broke;
                    }
                },
                .again => return .again,
                .broke => return .broke,
            }
        }
    }

    /// What the engine owes the socket, as far as a nonblocking write takes it now, unless a
    /// flush is under way (`flushing`), which writes it after its own records. Never waits.
    fn drainNow(n: *Net, c: *Conn, t: *brick.Conn) void {
        _ = n;
        if (c.flushing or c.closed) return;
        var wire: [wire_size]u8 = undefined;
        while (true) {
            var got: usize = 0;
            if (brick.mo_tls_flush(t, &wire, wire.len, &got) != brick.ok or got == 0) return;
            switch (writeOne(c.fd(), wire[0..got])) {
                .done => |k| {
                    brick.mo_tls_sent(t, k);
                    if (k < got) return;
                },
                else => return,
            }
        }
    }

    /// `tls_server.accept(conn, within:)` and `tls_client.connect(conn, host:, within:)`: one
    /// side's half of the handshake on `c`'s socket, the server's or the client's. The connection
    /// it gives back is the same one; from here its bytes are records.
    pub fn handshake(n: *Net, vm: *Vm, c: *Conn, side: Side, ms: i64) Error!Handshook {
        const deadline = n.now() + @max(ms, 0);
        if (c.closed) return .Closed;
        const t = try side.start();
        errdefer brick.mo_tls_conn_free(t);
        const failed: Handshook = fail: while (true) {
            if (try n.flushTls(vm, c, t, deadline)) |f| break :fail if (f == .Timeout) .Timeout else .Closed;
            if (brick.mo_tls_ready(t)) {
                c.tls = t;
                return .done;
            }
            // A fatal alert from the peer leaves the engine failed though its read went in, and
            // is `Handshake`, as under the fixture; close_notify or user_canceled is `Closed`.
            var none: usize = 0;
            switch (brick.mo_tls_read(t, null, 0, &none)) {
                brick.failed => {
                    _ = try n.flushTls(vm, c, t, deadline);
                    break :fail refused(t);
                },
                brick.closed => break :fail .Closed,
                else => {},
            }
            switch (try n.feedTls(vm, c, t, deadline)) {
                .got => {},
                // A hello that stops mid-record, or a peer that never finishes.
                .eof => break :fail .Closed,
                .timeout => break :fail .Timeout,
                .closed => break :fail .Closed,
                // The engine answered with an alert; it reaches the peer before the socket goes.
                .broken => {
                    _ = try n.flushTls(vm, c, t, deadline);
                    break :fail refused(t);
                },
            }
        };
        brick.mo_tls_conn_free(t);
        n.close(c);
        return failed;
    }

    /// `conn.close`: a call waiting on the connection ends, and every later call is Closed.
    pub fn close(n: *Net, c: *Conn) void {
        if (!c.closed) {
            // A TLS connection says goodbye before the socket goes: close_notify is written if
            // it fits in the socket's buffer, and never waited for, since `close` cannot wait;
            // not while a flush is under way, whose record it would cut.
            if (c.tls != null and !c.flushing) {
                const t = c.tls.?;
                brick.mo_tls_close(t);
                var wire: [4096]u8 = undefined;
                var got: usize = 0;
                while (brick.mo_tls_flush(t, &wire, wire.len, &got) == brick.ok and got > 0) {
                    switch (writeOne(c.fd(), wire[0..got])) {
                        .done => |k| brick.mo_tls_sent(t, k),
                        else => break,
                    }
                }
            }
            c.closed = true;
            c.stream.shutdown(n.io, .both) catch {};
        }
        n.release(c);
    }

    /// Closes the descriptor once no call is waiting on it.
    pub fn release(n: *Net, c: *Conn) void {
        if (c.released or c.reading or c.writing or c.flushing) return;
        c.released = true;
        c.stream.close(n.io);
        if (c.tls) |t| {
            brick.mo_tls_conn_free(t);
            c.tls = null;
        }
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
        for (n.tls_servers.items) |s| brick.mo_tls_server_free(s);
        n.tls_servers.clearRetainingCapacity();
        for (n.tls_clients.items) |cl| brick.mo_tls_client_free(cl);
        n.tls_clients.clearRetainingCapacity();
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
    /// The TLS servers `Tls.server` and the clients `Tls.client` made in this test.
    tls_servers: std.ArrayList(*brick.Server) = .empty,
    tls_clients: std.ArrayList(*brick.Client) = .empty,
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
        /// The TLS engine behind it (step 36), or null. With one, `inbound` holds the peer's
        /// ciphertext and `clear` the plaintext the records gave up, which is what a line is
        /// cut from; a write is sealed into the peer's `inbound`.
        tls: ?*brick.Conn = null,
        clear: std.ArrayList(u8) = .empty,
        clear_start: usize = 0,
        /// The row that first read or wrote on it (`TlsServer.accept` takes neither).
        used: []const u8 = "",
    };

    /// The plaintext a fixture connection has, after every record its peer wrote is read.
    /// Nothing waits here: a simulated call cannot wait for bytes that have not been written.
    pub fn pumpTls(f: *Fixture, gpa: std.mem.Allocator, h: u32) Error!bool {
        const c = &f.conns.items[h];
        const t = c.tls orelse return true;
        const fed = c.inbound.items[c.start..];
        if (fed.len > 0) {
            const answer = brick.mo_tls_feed(t, fed.ptr, fed.len);
            c.inbound.clearRetainingCapacity();
            c.start = 0;
            if (answer != brick.ok and answer != brick.failed) return error.OutOfMemory;
        }
        var wire: [brick.max_ciphertext + 5]u8 = undefined;
        while (true) {
            var got: usize = 0;
            if (brick.mo_tls_flush(t, &wire, wire.len, &got) != brick.ok or got == 0) break;
            brick.mo_tls_sent(t, got);
            const peer = &f.conns.items[c.peer];
            if (!peer.closed) try peer.inbound.appendSlice(gpa, wire[0..got]);
        }
        while (true) {
            var got: usize = 0;
            const room = try c.clear.addManyAsSlice(gpa, brick.max_ciphertext);
            const rc = brick.mo_tls_read(t, room.ptr, room.len, &got);
            c.clear.items.len -= room.len - got;
            if (rc == brick.failed) return false;
            if (got == 0) break;
        }
        return true;
    }

    /// `accept` and `connect` on the in-memory network: one side's half of the handshake over the
    /// bytes the peer has written. A handshake takes two rounds, so while this side has nothing
    /// to read, the peer goes on: when the peer's own handshake is under way (in an update that
    /// called `accept` or `connect` and is waiting in this call's rounds, or the other way round)
    /// its engine reads what this side wrote and answers, as its own read would; and the other
    /// processes take their messages, a round at a time, as a fixture call that waits for a
    /// process does (http.zig's `send`), so a server whose `serve` hands it the connection
    /// accepts it here. Nothing to take and nobody to run is `Timeout`, after the whole deadline;
    /// a peer that sent something that is not the handshake is `Handshake`, and a chain this
    /// client refused is `Untrusted`.
    pub fn handshake(f: *Fixture, sim: *sim_mod.Sim, h: u32, side: Side, ms: i64) Error!Handshook {
        if (f.conns.items[h].closed) return .Closed;
        const t = try side.start();
        f.conns.items[h].tls = t;
        var delivered: u32 = 0;
        const since = sim.deadlineNow();
        const outcome: Handshook = while (true) {
            if (!try f.pumpTls(sim.gpa, h)) break refused(t);
            if (brick.mo_tls_ready(t)) return .done;
            const peer = f.conns.items[h].peer;
            if (f.conns.items[peer].tls != null) {
                const before = f.conns.items[h].inbound.items.len;
                _ = try f.pumpTls(sim.gpa, peer);
                if (f.conns.items[h].inbound.items.len > before) continue;
            }
            if (f.conns.items[peer].closed and f.conns.items[h].inbound.items.len == 0) break .Closed;
            if (try sim.deliverRound(&delivered)) continue;
            sim.wait(@max(since + ms - sim.deadlineNow(), 0));
            break .Timeout;
        };
        f.conns.items[h].tls = null;
        brick.mo_tls_conn_free(t);
        f.conns.items[h].closed = true;
        return outcome;
    }

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
                if (f.conns.items[h].used.len == 0) f.conns.items[h].used = "Conn.read_line";
                if (f.conns.items[h].closed) return fail(vm, .Closed);
                if (f.conns.items[h].lining) return fail(vm, .Busy);
                if (sim.fault(.closed, within)) |fault| {
                    if (fault == .timeout) return fail(vm, .Timeout);
                    f.conns.items[h].closed = true;
                    return fail(vm, .Closed);
                }
                if (f.conns.items[h].tls != null) {
                    if (!try f.pumpTls(gpa, h)) {
                        f.conns.items[h].closed = true;
                        return fail(vm, .Closed);
                    }
                    const c = &f.conns.items[h];
                    const taken, const what = scanLine(c.clear.items[c.clear_start..], f.conns.items[c.peer].closed, &c.skipping);
                    c.clear_start += taken;
                    const got = try lineResult(vm, what) orelse {
                        sim.wait(within);
                        return fail(vm, .Timeout);
                    };
                    if (c.clear_start == c.clear.items.len) {
                        c.clear.clearRetainingCapacity();
                        c.clear_start = 0;
                    }
                    return got;
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
                if (f.conns.items[h].used.len == 0) f.conns.items[h].used = "Conn.write";
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
                if (f.conns.items[h].tls) |t| {
                    const text = a[1].string;
                    if (brick.mo_tls_write(t, text.ptr, text.len) != brick.ok) {
                        f.conns.items[h].closed = true;
                        return fail(vm, .Closed);
                    }
                    _ = try f.pumpTls(gpa, h);
                    return vm.variant("Ok", &.{.none});
                }
                try f.conns.items[peer].inbound.appendSlice(gpa, a[1].string);
                return vm.variant("Ok", &.{.none});
            },
            .close => {
                const h = a[0].cap.handle;
                if (f.conns.items[h].tls) |t| {
                    brick.mo_tls_close(t);
                    _ = try f.pumpTls(gpa, h);
                    brick.mo_tls_conn_free(t);
                    f.conns.items[h].tls = null;
                }
                f.conns.items[h].closed = true;
                return .none;
            },
            .serve, .lines => unreachable,
        }
    }

    pub fn portTaken(f: *const Fixture, port: u16) bool {
        for (f.listeners.items) |l| if (l.port == port) return true;
        return false;
    }

    /// The test is over: every server it made goes back.
    pub fn closeAll(f: *Fixture) void {
        for (f.conns.items) |*c| if (c.tls) |t| {
            brick.mo_tls_conn_free(t);
            c.tls = null;
        };
        for (f.tls_servers.items) |s| brick.mo_tls_server_free(s);
        f.tls_servers.clearRetainingCapacity();
        for (f.tls_clients.items) |cl| brick.mo_tls_client_free(cl);
        f.tls_clients.clearRetainingCapacity();
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

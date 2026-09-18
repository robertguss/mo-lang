//! The fuzz driver (bench/step37/fuzz.py runs it): the TLS brick's parsers on both roles, fed
//! mutated inputs at every state of the handshake and after it. Built by `zig build tls-tools` as
//! a test executable, so the brick's test hooks exist: each connection's entropy is fixed, which
//! makes every canonical session the same bytes each time it is replayed.
//!
//! An input is a file: `MOFZ`, one byte naming the case (suite, key type, ALPN, HelloRetryRequest:
//! sixteen), then frames, each a kind byte, a little-endian u32 length, and the bytes. Kind 0 is a
//! record the client sent (so the server reads it), 1 a record the server sent, 2 a handshake
//! message the client sent, in plaintext, and 3 one the server sent. `MO_FUZZ_RECORD=dir` writes
//! the sixteen canonical inputs, unmutated: the corpus fuzz.py starts from.
//!
//! For each input (listed one path a line in the file `MO_FUZZ_INPUTS` names), for each role and
//! each state k (the first k canonical records of the peer's replayed into a fresh connection):
//! the input's records of the peer's from the k-th on, fed to the engine as they are; and, on
//! another fresh connection at the same state, the input's plaintext messages of the peer's fed
//! behind the AEAD, to the handshake parser itself. After each, the engine's answer is flushed
//! and its plaintext read. A crash is a signal, an abort, a Zig panic (the driver is built with
//! safety checks), or a step that does not return within two seconds, which a watchdog thread
//! turns into exit 3 with the step named.
const std = @import("std");
const brick = @import("tls_brick");

const gpa = std.heap.smp_allocator;
const Conn = brick.Conn;

const Case = struct { suite: brick.Suite, p256: bool, alpn: bool, retry: bool };

fn caseOf(i: u8) Case {
    return .{
        .suite = if (i & 1 != 0) .chacha20_poly1305 else .aes_128_gcm,
        .p256 = i & 2 != 0,
        .alpn = i & 4 != 0,
        .retry = i & 8 != 0,
    };
}

const Frame = struct { kind: u8, bytes: []const u8 };

/// A canonical session's frames, in the order they went.
const Transcript = struct {
    frames: std.ArrayList(Frame) = .empty,
    sending: u8 = 0,

    fn add(t: *Transcript, kind: u8, bytes: []const u8) void {
        t.frames.append(gpa, .{ .kind = kind, .bytes = gpa.dupe(u8, bytes) catch @panic("out of memory") }) catch @panic("out of memory");
    }

    fn sentBy(ctx: *anyopaque, message: []const u8) void {
        const which: *Sender = @ptrCast(@alignCast(ctx));
        which.t.add(which.kind, message);
    }
};

const Sender = struct { t: *Transcript, kind: u8 };

fn serverOf(c: Case) *brick.Server {
    const chain = if (c.p256) brick.fx_chain_p256 else brick.fx_chain;
    const key = if (c.p256) brick.fx_key_p256 else brick.fx_key;
    var s = brick.mo_tls_server_new(chain.ptr, chain.len, key.ptr, key.len).?;
    if (c.alpn) {
        const names = "echo/1";
        const offered = brick.mo_tls_server_offer(s, names.ptr, names.len).?;
        brick.mo_tls_server_free(s);
        s = offered;
    }
    s.prefer = c.suite;
    return s;
}

fn clientOf(c: Case) *brick.Client {
    const root = if (c.p256) brick.fx_root_p256 else brick.fx_root;
    var cl = brick.mo_tls_client_new(root.ptr, root.len).?;
    if (c.alpn) {
        const names = "mo/1\x00echo/1";
        const offered = brick.mo_tls_client_offer(cl, names.ptr, names.len).?;
        brick.mo_tls_client_free(cl);
        cl = offered;
    }
    return cl;
}

const session_id: [32]u8 = @splat(5);

fn serverConn(s: *brick.Server, hooks: brick.TestHooks) *Conn {
    const conn = brick.mo_tls_conn_new(s).?;
    conn.hooks = hooks;
    conn.hooks.random = @splat(1);
    conn.hooks.x25519_secret = @splat(2);
    return conn;
}

fn clientConn(cl: *brick.Client, c: Case, hooks: brick.TestHooks) *Conn {
    var h = hooks;
    h.random = @splat(3);
    h.x25519_secret = @splat(4);
    h.session_id = &session_id;
    h.no_share = c.retry;
    return brick.connectWith(cl, "localhost", brick.test_now, h) catch @panic("out of memory");
}

/// The records `bytes` holds, each whole.
fn eachRecord(bytes: []const u8, t: *Transcript, kind: u8, into: *Conn) void {
    var at: usize = 0;
    while (at + 5 <= bytes.len) {
        const len = std.mem.readInt(u16, bytes[at + 3 ..][0..2], .big);
        const rec = bytes[at..@min(bytes.len, at + 5 + len)];
        t.add(kind, rec);
        _ = brick.mo_tls_feed(into, rec.ptr, rec.len);
        at += rec.len;
    }
}

fn drain(conn: *Conn, buf: []u8) []const u8 {
    var n: usize = 0;
    _ = brick.mo_tls_flush(conn, buf.ptr, buf.len, &n);
    brick.mo_tls_sent(conn, n);
    return buf[0..n];
}

/// Moves each side's records to the other, one record at a time, recording each, until quiet.
fn shuttle(t: *Transcript, client: *Conn, server: *Conn) void {
    const buf = gpa.alloc(u8, 1 << 20) catch @panic("out of memory");
    defer gpa.free(buf);
    var rounds: usize = 0;
    while (rounds < 64) : (rounds += 1) {
        const from_client = drain(client, buf);
        if (from_client.len > 0) eachRecord(from_client, t, 0, server);
        const from_server = drain(server, buf);
        if (from_server.len > 0) eachRecord(from_server, t, 1, client);
        if (from_client.len == 0 and from_server.len == 0) return;
    }
}

fn readAll(conn: *Conn) void {
    var buf: [16384]u8 = undefined;
    while (true) {
        var got: usize = 0;
        if (brick.mo_tls_read(conn, &buf, buf.len, &got) != brick.ok or got == 0) return;
    }
}

/// The canonical session of a case: the handshake, 100 bytes each way, a KeyUpdate the client
/// starts asking for the server's, 50 bytes more from the server, then close_notify both ways.
fn canonical(c: Case) Transcript {
    var t: Transcript = .{};
    var to_server: Sender = .{ .t = &t, .kind = 2 };
    var to_client: Sender = .{ .t = &t, .kind = 3 };
    const s = serverOf(c);
    const cl = clientOf(c);
    const server = serverConn(s, .{ .sent = Transcript.sentBy, .ctx = &to_client });
    const client = clientConn(cl, c, .{ .sent = Transcript.sentBy, .ctx = &to_server });
    shuttle(&t, client, server);
    if (!brick.mo_tls_ready(client) or !brick.mo_tls_ready(server)) @panic("a canonical session did not handshake");
    const hundred: [100]u8 = @splat('m');
    _ = brick.mo_tls_write(client, &hundred, hundred.len);
    shuttle(&t, client, server);
    readAll(server);
    _ = brick.mo_tls_write(server, &hundred, hundred.len);
    _ = brick.mo_tls_key_update(client, true);
    shuttle(&t, client, server);
    readAll(client);
    _ = brick.mo_tls_write(server, hundred[0..50], 50);
    brick.mo_tls_close(client);
    shuttle(&t, client, server);
    brick.mo_tls_close(server);
    shuttle(&t, client, server);
    brick.mo_tls_conn_free(client);
    brick.mo_tls_conn_free(server);
    brick.mo_tls_server_free(s);
    brick.mo_tls_client_free(cl);
    return t;
}

fn encode(case: u8, t: Transcript) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.appendSlice(gpa, "MOFZ");
    try out.append(gpa, case);
    for (t.frames.items) |f| {
        try out.append(gpa, f.kind);
        var len: [4]u8 = undefined;
        std.mem.writeInt(u32, &len, @intCast(f.bytes.len), .little);
        try out.appendSlice(gpa, &len);
        try out.appendSlice(gpa, f.bytes);
    }
    return out.toOwnedSlice(gpa);
}

/// The frames of an input, read leniently: a frame whose length runs past the end takes the rest.
fn decode(bytes: []const u8, into: *std.ArrayList(Frame)) void {
    var at: usize = 5;
    while (at + 5 <= bytes.len) {
        const kind = bytes[at] & 3;
        const len = std.mem.readInt(u32, bytes[at + 1 ..][0..4], .little);
        at += 5;
        const n = @min(len, bytes.len - at);
        into.append(gpa, .{ .kind = kind, .bytes = bytes[at..][0..n] }) catch @panic("out of memory");
        at += n;
    }
}

// ---- the watchdog: a step that runs past two seconds is a hang, and ends the run as a crash

var step_started = std.atomic.Value(i64).init(0);
var step_name: [128]u8 = undefined;
var step_name_len = std.atomic.Value(usize).init(0);

fn nowMs() i64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
    return @as(i64, ts.sec) * 1000 + @divTrunc(ts.nsec, 1_000_000);
}

fn watchdog() void {
    while (true) {
        _ = std.os.linux.nanosleep(&.{ .sec = 0, .nsec = 100_000_000 }, null);
        const started = step_started.load(.acquire);
        if (started != 0 and nowMs() - started > 2000) {
            std.debug.print("fuzz: HANG, a step ran past 2 s: {s}\n", .{step_name[0..step_name_len.load(.acquire)]});
            std.process.exit(3);
        }
    }
}

fn begin(comptime format: []const u8, args: anytype) void {
    const name = std.fmt.bufPrint(&step_name, format, args) catch step_name[0..0];
    step_name_len.store(name.len, .release);
    step_started.store(nowMs(), .release);
}

fn end() void {
    step_started.store(0, .release);
}

// ---- one input

const Canon = struct { case: Case, server_reads: [][]const u8, client_reads: [][]const u8 };
var canons: [16]?Canon = @splat(null);

fn canonOf(i: u8) Canon {
    if (canons[i]) |c| return c;
    const c = caseOf(i);
    const t = canonical(c);
    var server_reads: std.ArrayList([]const u8) = .empty;
    var client_reads: std.ArrayList([]const u8) = .empty;
    for (t.frames.items) |f| switch (f.kind) {
        0 => server_reads.append(gpa, f.bytes) catch unreachable,
        1 => client_reads.append(gpa, f.bytes) catch unreachable,
        else => {},
    };
    canons[i] = .{ .case = c, .server_reads = server_reads.items, .client_reads = client_reads.items };
    return canons[i].?;
}

fn fresh(role: enum { server, client }, c: Case, s: *brick.Server, cl: *brick.Client) *Conn {
    return switch (role) {
        .server => serverConn(s, .{}),
        .client => blk: {
            const conn = clientConn(cl, c, .{});
            var buf: [4096]u8 = undefined;
            _ = drain(conn, &buf);
            break :blk conn;
        },
    };
}

fn settle(conn: *Conn) void {
    var buf: [65536]u8 = undefined;
    _ = drain(conn, &buf);
    readAll(conn);
}

fn one(path: []const u8, bytes: []const u8) void {
    if (bytes.len < 5 or !std.mem.eql(u8, bytes[0..4], "MOFZ")) return;
    // fuzz.py's self-check, before the hour: an input whose case byte is 0xEE panics and one whose
    // case byte is 0xED never returns from its step, so the log shows each kind of crash counted.
    if (bytes[4] == 0xEE) @panic("fuzz.py's self-check: a planted panic");
    if (bytes[4] == 0xED) {
        begin("{s} a planted hang", .{path});
        while (true) _ = std.os.linux.nanosleep(&.{ .sec = 1, .nsec = 0 }, null);
    }
    const case_index = bytes[4] % 16;
    const canon = canonOf(case_index);
    var frames: std.ArrayList(Frame) = .empty;
    defer frames.deinit(gpa);
    decode(bytes, &frames);
    const s = serverOf(canon.case);
    defer brick.mo_tls_server_free(s);
    const cl = clientOf(canon.case);
    defer brick.mo_tls_client_free(cl);

    inline for (.{ .server, .client }) |role| {
        const replay = if (role == .server) canon.server_reads else canon.client_reads;
        const wire_kind: u8 = if (role == .server) 0 else 1;
        const msg_kind: u8 = if (role == .server) 2 else 3;
        var wire: std.ArrayList([]const u8) = .empty;
        defer wire.deinit(gpa);
        var msgs: std.ArrayList([]const u8) = .empty;
        defer msgs.deinit(gpa);
        for (frames.items) |f| {
            if (f.kind == wire_kind) wire.append(gpa, f.bytes) catch unreachable;
            if (f.kind == msg_kind) msgs.append(gpa, f.bytes) catch unreachable;
        }
        for (0..replay.len + 1) |k| {
            // The records as they are, from the k-th on (at most four).
            {
                const conn = fresh(role, canon.case, s, cl);
                for (replay[0..k]) |r| _ = brick.mo_tls_feed(conn, r.ptr, r.len);
                settle(conn);
                var n: usize = 0;
                for (wire.items[@min(k, wire.items.len)..]) |r| {
                    if (n == 4) break;
                    n += 1;
                    begin("{s} {s} state {d}, record {d}", .{ path, @tagName(role), k, n });
                    _ = brick.mo_tls_feed(conn, r.ptr, r.len);
                    settle(conn);
                    end();
                }
                brick.mo_tls_conn_free(conn);
            }
            // The plaintext messages, behind the AEAD, to the handshake parser.
            {
                const conn = fresh(role, canon.case, s, cl);
                for (replay[0..k]) |r| _ = brick.mo_tls_feed(conn, r.ptr, r.len);
                settle(conn);
                var n: usize = 0;
                for (msgs.items) |m| {
                    if (n == 4) break;
                    n += 1;
                    begin("{s} {s} state {d}, message {d}", .{ path, @tagName(role), k, n });
                    conn.handshakeBytes(m) catch {};
                    settle(conn);
                    end();
                }
                brick.mo_tls_conn_free(conn);
            }
        }
    }
}

test "the fuzz driver" {
    const io = std.testing.io;
    const environ = std.testing.environ;
    if (environ.getAlloc(gpa, "MO_FUZZ_RECORD") catch null) |dir| {
        for (0..16) |i| {
            const t = canonical(caseOf(@intCast(i)));
            const bytes = try encode(@intCast(i), t);
            var name_buf: [512]u8 = undefined;
            const name = try std.fmt.bufPrint(&name_buf, "{s}/case-{d:0>2}.bin", .{ dir, i });
            try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = name, .data = bytes });
        }
        std.debug.print("fuzz: wrote 16 canonical inputs to {s}\n", .{dir});
        return;
    }
    const list_path = environ.getAlloc(gpa, "MO_FUZZ_INPUTS") catch return;
    const list = try std.Io.Dir.cwd().readFileAlloc(io, list_path, gpa, .limited(64 << 20));
    _ = try std.Thread.spawn(.{}, watchdog, .{});
    var count: usize = 0;
    var it = std.mem.tokenizeScalar(u8, list, '\n');
    while (it.next()) |path| {
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1 << 20)) catch continue;
        defer gpa.free(bytes);
        one(path, bytes);
        count += 1;
    }
    std.debug.print("fuzz: {d} inputs, no crash\n", .{count});
}

//! mo-tls-peer: the brick's side of the differential run (bench/step37/diff.py), one TLS session
//! over a real socket driven through the brick's exports (src/bricks/tls.zig) exactly as the
//! runtimes drive it, with OpenSSL's `s_client` or `s_server` on the other end. It prints what the
//! brick's engine saw as one JSON line, which diff.py sets beside what OpenSSL printed.
//!
//!   mo-tls-peer server --port N --cert PEM --key PEM [--alpn a,b] [--prefer chacha]
//!                      [--expect N] [--ku-after N] [--ku-request] [--close-first] [--wait-ms N]
//!   mo-tls-peer client --port N --host H --trust PEM [--alpn a,b] [--send 10,300,...]
//!                      [--ku-after N] [--ku-request] [--close-first] [--now SEC] [--wait-ms N]
//!
//! The server echoes every byte; `--expect` is how many the client will send, so the server
//! knows when it may close first. The client writes each `--send` size as one write, reads the
//! echo back, and closes first or waits for the server to. `--ku-after N` has this side start a
//! KeyUpdate (`mo_tls_key_update`, `--ku-request` asking the peer for its own) once N bytes have
//! come in. Every wait is bounded by `--wait-ms` (10 s by default); diff.py also runs this under
//! guard.py.
const std = @import("std");
const brick = @import("tls_brick");
const posix = std.posix;

const Args = struct {
    role: enum { server, client } = .server,
    port: u16 = 0,
    cert: []const u8 = "",
    key: []const u8 = "",
    trust: []const u8 = "",
    host: []const u8 = "localhost",
    alpn: []const u8 = "",
    prefer_chacha: bool = false,
    expect: usize = 0,
    send: []const u8 = "",
    ku_after: ?usize = null,
    ku_request: bool = false,
    close_first: bool = false,
    now: ?i64 = null,
    wait_ms: i64 = 10_000,
};

const Report = struct {
    role: []const u8,
    handshake: bool = false,
    suite: []const u8 = "",
    alpn: []const u8 = "",
    bytes_in: usize = 0,
    bytes_out: usize = 0,
    echo_ok: bool = false,
    alert: c_int = -1,
    alert_from_peer: bool = false,
    untrusted: bool = false,
    ku_sent: u32 = 0,
    ku_read: u32 = 0,
    /// Whether this side's close_notify went out.
    sent_close: bool = false,
    end: []const u8 = "",
};

fn readFile(io: std.Io, gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1 << 20));
}

fn parseArgs(io: std.Io, gpa: std.mem.Allocator, argv: []const []const u8) !Args {
    var a: Args = .{};
    if (argv.len < 2) return error.Usage;
    a.role = if (std.mem.eql(u8, argv[1], "client")) .client else if (std.mem.eql(u8, argv[1], "server")) .server else return error.Usage;
    var i: usize = 2;
    while (i < argv.len) : (i += 1) {
        const flag = argv[i];
        const takes = !(std.mem.eql(u8, flag, "--ku-request") or std.mem.eql(u8, flag, "--close-first"));
        const value = if (takes) (if (i + 1 < argv.len) argv[i + 1] else return error.Usage) else "";
        if (takes) i += 1;
        if (std.mem.eql(u8, flag, "--port")) a.port = try std.fmt.parseInt(u16, value, 10) else if (std.mem.eql(u8, flag, "--cert")) a.cert = try readFile(io, gpa, value) else if (std.mem.eql(u8, flag, "--key")) a.key = try readFile(io, gpa, value) else if (std.mem.eql(u8, flag, "--trust")) a.trust = try readFile(io, gpa, value) else if (std.mem.eql(u8, flag, "--host")) a.host = value else if (std.mem.eql(u8, flag, "--alpn")) a.alpn = value else if (std.mem.eql(u8, flag, "--prefer")) a.prefer_chacha = std.mem.eql(u8, value, "chacha") else if (std.mem.eql(u8, flag, "--expect")) a.expect = try std.fmt.parseInt(usize, value, 10) else if (std.mem.eql(u8, flag, "--send")) a.send = value else if (std.mem.eql(u8, flag, "--ku-after")) a.ku_after = try std.fmt.parseInt(usize, value, 10) else if (std.mem.eql(u8, flag, "--ku-request")) a.ku_request = true else if (std.mem.eql(u8, flag, "--close-first")) a.close_first = true else if (std.mem.eql(u8, flag, "--now")) a.now = try std.fmt.parseInt(i64, value, 10) else if (std.mem.eql(u8, flag, "--wait-ms")) a.wait_ms = try std.fmt.parseInt(i64, value, 10) else return error.Usage;
    }
    return a;
}

/// ALPN names as the brick takes them: comma-separated here, NUL-separated there.
fn nulNames(gpa: std.mem.Allocator, list: []const u8) ![]u8 {
    const out = try gpa.dupe(u8, list);
    for (out) |*c| if (c.* == ',') {
        c.* = 0;
    };
    return out;
}

fn nowMs() i64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
    return @as(i64, ts.sec) * 1000 + @divTrunc(ts.nsec, 1_000_000);
}

fn wallSec() i64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.REALTIME, &ts);
    return ts.sec;
}

fn nonblocking(fd: posix.fd_t) void {
    const linux = std.os.linux;
    const flags = linux.fcntl(fd, linux.F.GETFL, 0);
    _ = linux.fcntl(fd, linux.F.SETFL, flags | @as(u32, @bitCast(posix.O{ .NONBLOCK = true })));
}

fn loopback(port: u16) posix.sockaddr.in {
    return .{ .port = std.mem.nativeToBig(u16, port), .addr = std.mem.nativeToBig(u32, 0x7f00_0001) };
}

fn listenOn(port: u16) !posix.fd_t {
    const sys = posix.system;
    const rc = sys.socket(posix.AF.INET, posix.SOCK.STREAM, posix.IPPROTO.TCP);
    if (posix.errno(rc) != .SUCCESS) return error.Socket;
    const fd: posix.fd_t = @intCast(rc);
    try posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    var addr = loopback(port);
    if (posix.errno(sys.bind(fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.in))) != .SUCCESS) return error.Bind;
    if (posix.errno(sys.listen(fd, 8)) != .SUCCESS) return error.Listen;
    return fd;
}

fn acceptOne(fd: posix.fd_t, wait_ms: i64) !posix.fd_t {
    var p = [_]posix.pollfd{.{ .fd = fd, .events = posix.POLL.IN, .revents = 0 }};
    if (try posix.poll(&p, @intCast(wait_ms)) == 0) return error.Timeout;
    const rc = posix.system.accept(fd, null, null);
    if (posix.errno(rc) != .SUCCESS) return error.Accept;
    return @intCast(rc);
}

fn connectTo(port: u16) !posix.fd_t {
    const sys = posix.system;
    const rc = sys.socket(posix.AF.INET, posix.SOCK.STREAM, posix.IPPROTO.TCP);
    if (posix.errno(rc) != .SUCCESS) return error.Socket;
    const fd: posix.fd_t = @intCast(rc);
    var addr = loopback(port);
    if (posix.errno(sys.connect(fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.in))) != .SUCCESS) return error.Refused;
    return fd;
}

const suite_names = [_][]const u8{ "TLS_AES_128_GCM_SHA256", "TLS_CHACHA20_POLY1305_SHA256" };

/// The session, either role, over a connected socket. Every wait is poll with the deadline left.
const Session = struct {
    fd: posix.fd_t,
    t: *brick.Conn,
    args: Args,
    report: *Report,
    /// Ciphertext the engine gave that the socket has not taken yet.
    pending: std.ArrayList(u8) = .empty,
    gpa: std.mem.Allocator,
    deadline: i64,
    peer_eof: bool = false,
    sent_close: bool = false,
    ku_done: bool = false,

    fn drainEngine(s: *Session) !void {
        var wire: [brick.max_ciphertext + 5]u8 = undefined;
        while (true) {
            var got: usize = 0;
            _ = brick.mo_tls_flush(s.t, &wire, wire.len, &got);
            if (got == 0) return;
            brick.mo_tls_sent(s.t, got);
            try s.pending.appendSlice(s.gpa, wire[0..got]);
        }
    }

    /// Writes what is pending, as far as the socket takes it now; true when all of it went.
    fn writeSome(s: *Session) bool {
        while (s.pending.items.len > 0) {
            const rc = posix.system.sendto(s.fd, s.pending.items.ptr, s.pending.items.len, posix.MSG.NOSIGNAL, null, 0);
            switch (posix.errno(rc)) {
                .SUCCESS => {
                    const n: usize = @intCast(rc);
                    std.mem.copyForwards(u8, s.pending.items, s.pending.items[n..]);
                    s.pending.items.len -= n;
                },
                .AGAIN => return false,
                .INTR => {},
                else => {
                    s.pending.clearRetainingCapacity();
                    return true;
                },
            }
        }
        return true;
    }

    /// One round: the engine's bytes out, then what the socket has in, waiting at most until the
    /// deadline. False when the stream ended or the deadline passed.
    fn step(s: *Session) !bool {
        try s.drainEngine();
        _ = s.writeSome();
        const left = s.deadline - nowMs();
        if (left <= 0) {
            s.report.end = "timeout";
            return false;
        }
        var p = [_]posix.pollfd{.{ .fd = s.fd, .events = if (s.pending.items.len > 0) posix.POLL.IN | posix.POLL.OUT else posix.POLL.IN, .revents = 0 }};
        if (try posix.poll(&p, @intCast(@min(left, 200))) == 0) return true;
        if (p[0].revents & posix.POLL.OUT != 0) _ = s.writeSome();
        if (p[0].revents & (posix.POLL.IN | posix.POLL.HUP | posix.POLL.ERR) == 0) return true;
        var wire: [32768]u8 = undefined;
        const rc = posix.system.read(s.fd, &wire, wire.len);
        switch (posix.errno(rc)) {
            .SUCCESS => {},
            .AGAIN, .INTR => return true,
            else => {
                s.peer_eof = true;
                s.report.end = "reset";
                return false;
            },
        }
        const n: usize = @intCast(rc);
        if (n == 0) {
            s.peer_eof = true;
            if (s.report.end.len == 0) s.report.end = "eof";
            return false;
        }
        _ = brick.mo_tls_feed(s.t, &wire, n);
        return true;
    }

    fn handshake(s: *Session) !bool {
        while (!brick.mo_tls_ready(s.t)) {
            if (brick.mo_tls_alert(s.t) >= 0) {
                // The alert goes out before the socket closes.
                try s.drainEngine();
                _ = s.writeSome();
                return false;
            }
            if (!try s.step()) return false;
        }
        s.report.handshake = true;
        s.report.suite = suite_names[@intFromEnum(s.t.suite)];
        var name: [255]u8 = undefined;
        const n = brick.mo_tls_protocol(s.t, &name, name.len);
        s.report.alpn = try s.gpa.dupe(u8, name[0..n]);
        return true;
    }

    /// Plaintext the engine holds, into `into` (or dropped when null); `closed` once the peer's
    /// close_notify came.
    fn readPlain(s: *Session, into: ?*std.ArrayList(u8)) !c_int {
        var buf: [16384]u8 = undefined;
        while (true) {
            var got: usize = 0;
            const rc = brick.mo_tls_read(s.t, &buf, buf.len, &got);
            if (rc != brick.ok or got == 0) return rc;
            s.report.bytes_in += got;
            if (into) |list| try list.appendSlice(s.gpa, buf[0..got]);
            if (s.args.role == .server) {
                _ = brick.mo_tls_write(s.t, &buf, got);
                s.report.bytes_out += got;
            }
            s.maybeKeyUpdate();
        }
    }

    fn maybeKeyUpdate(s: *Session) void {
        if (s.args.role == .client) return;
        const after = s.args.ku_after orelse return;
        if (s.ku_done or s.report.bytes_in < after) return;
        s.ku_done = true;
        _ = brick.mo_tls_key_update(s.t, s.args.ku_request);
    }

    fn closeNow(s: *Session) !void {
        if (s.sent_close) return;
        s.sent_close = true;
        brick.mo_tls_close(s.t);
        try s.drainEngine();
        _ = s.writeSome();
    }

    /// After this side's close_notify, the peer's: at most a second more.
    fn awaitPeerClose(s: *Session) !void {
        s.deadline = @min(s.deadline, nowMs() + 1000);
        while (true) {
            const rc = try s.readPlain(null);
            if (rc == brick.closed) {
                s.report.end = if (s.args.close_first) "closed-self-first" else "closed-peer-first";
                return;
            }
            if (rc == brick.failed) {
                s.report.end = "alert";
                return;
            }
            if (!try s.step()) return;
        }
    }
};

pub fn main(init: std.process.Init) !u8 {
    const gpa = std.heap.smp_allocator;
    const argv = try init.minimal.args.toSlice(init.arena.allocator());
    const args = parseArgs(init.io, gpa, argv) catch {
        std.debug.print("usage: mo-tls-peer server|client [flags]: see bench/step37/peer.zig\n", .{});
        return 2;
    };
    var report: Report = .{ .role = @tagName(args.role) };
    const deadline = nowMs() + args.wait_ms;
    var out_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &out_buf);
    const w = &stdout.interface;

    var fd: posix.fd_t = undefined;
    var t: *brick.Conn = undefined;
    switch (args.role) {
        .server => {
            var server = brick.mo_tls_server_new(args.cert.ptr, args.cert.len, args.key.ptr, args.key.len) orelse {
                report.end = "badpem";
                try emit(w, report);
                return 1;
            };
            if (args.alpn.len > 0) {
                const names = try nulNames(gpa, args.alpn);
                const offered = brick.mo_tls_server_offer(server, names.ptr, names.len).?;
                brick.mo_tls_server_free(server);
                server = offered;
            }
            if (args.prefer_chacha) server.prefer = .chacha20_poly1305;
            const listener = try listenOn(args.port);
            try w.writeAll("listening\n");
            try w.flush();
            fd = acceptOne(listener, args.wait_ms) catch {
                report.end = "no-client";
                try emit(w, report);
                return 1;
            };
            t = brick.mo_tls_conn_new(server).?;
        },
        .client => {
            var client = brick.mo_tls_client_new(args.trust.ptr, args.trust.len) orelse {
                report.end = "badpem";
                try emit(w, report);
                return 1;
            };
            if (args.alpn.len > 0) {
                const names = try nulNames(gpa, args.alpn);
                const offered = brick.mo_tls_client_offer(client, names.ptr, names.len).?;
                brick.mo_tls_client_free(client);
                client = offered;
            }
            fd = connectTo(args.port) catch {
                report.end = "refused";
                try emit(w, report);
                return 1;
            };
            t = brick.mo_tls_connect(client, args.host.ptr, args.host.len, args.now orelse wallSec()).?;
        },
    }
    nonblocking(fd);
    var s: Session = .{ .fd = fd, .t = t, .args = args, .report = &report, .gpa = gpa, .deadline = deadline };

    if (try s.handshake()) {
        switch (args.role) {
            .server => try serve(&s),
            .client => try talk(&s),
        }
    } else if (report.end.len == 0) report.end = "alert";
    try s.drainEngine();
    _ = s.writeSome();
    report.alert = brick.mo_tls_alert(t);
    report.alert_from_peer = t.alert_from_peer;
    report.untrusted = brick.mo_tls_untrusted(t);
    report.ku_sent = t.key_updates_sent;
    report.ku_read = t.key_updates_read;
    report.sent_close = s.sent_close;
    _ = posix.system.shutdown(fd, posix.SHUT.RDWR);
    _ = posix.system.close(fd);
    try emit(w, report);
    return 0;
}

/// The server: every byte echoed, until the client closes, or until `--expect` bytes have come
/// and this side closes first.
fn serve(s: *Session) !void {
    while (true) {
        const rc = try s.readPlain(null);
        if (rc == brick.closed) {
            // The client's close_notify: ours goes back.
            try s.closeNow();
            s.report.end = "closed-peer-first";
            s.report.echo_ok = s.report.bytes_in == s.args.expect;
            return;
        }
        if (rc == brick.failed) {
            s.report.end = "alert";
            return;
        }
        if (s.args.close_first and s.report.bytes_in >= s.args.expect) {
            s.report.echo_ok = s.report.bytes_in == s.args.expect;
            try s.closeNow();
            try s.awaitPeerClose();
            return;
        }
        if (!try s.step()) return;
    }
}

/// The client: each size in `--send` as one write, in two halves; the echo of the first half is
/// read back whole before the second goes, and a KeyUpdate this side starts (`--ku-after`) goes
/// between them, so records flow both ways after it. Then this side closes first or waits for
/// the server to.
fn talk(s: *Session) !void {
    var sizes: std.ArrayList(usize) = .empty;
    var it = std.mem.tokenizeScalar(u8, s.args.send, ',');
    while (it.next()) |part| try sizes.append(s.gpa, try std.fmt.parseInt(usize, part, 10));
    var total: usize = 0;
    for (sizes.items) |n| total += n;
    // Bytes from an alphabet with no command letter of s_server's or s_client's in it.
    const alphabet = "23456789bfjlmpvxyz";
    const sent = try s.gpa.alloc(u8, total);
    for (sent, 0..) |*ch, k| ch.* = alphabet[(k * 7 + 3) % alphabet.len];
    var back: std.ArrayList(u8) = .empty;
    const half = total / 2;
    var at: usize = 0;
    for (0..2) |round| {
        const upto = if (round == 0) half else total;
        // The writes as `--send` sizes them, cut at the half.
        var edge: usize = 0;
        for (sizes.items) |n| {
            const lo = @max(edge, at);
            const hi = @min(edge + n, upto);
            edge += n;
            if (hi <= lo) continue;
            _ = brick.mo_tls_write(s.t, sent[lo..hi].ptr, hi - lo);
            s.report.bytes_out += hi - lo;
            try s.drainEngine();
            _ = s.writeSome();
        }
        at = upto;
        while (back.items.len < upto) {
            const rc = try s.readPlain(&back);
            if (rc == brick.closed) {
                s.report.end = "closed-peer-first";
                break;
            }
            if (rc == brick.failed) {
                s.report.end = "alert";
                return;
            }
            if (back.items.len >= upto) break;
            if (!try s.step()) break;
        }
        if (s.report.end.len > 0) break;
        if (round == 0 and s.args.ku_after != null) {
            s.ku_done = true;
            _ = brick.mo_tls_key_update(s.t, s.args.ku_request);
        }
    }
    s.report.echo_ok = std.mem.eql(u8, sent, back.items);
    if (s.report.end.len > 0) return;
    if (s.args.close_first) {
        try s.closeNow();
        try s.awaitPeerClose();
        return;
    }
    // The server closes first: read until its close_notify, then answer it.
    while (true) {
        const rc = try s.readPlain(null);
        if (rc == brick.closed) {
            try s.closeNow();
            s.report.end = "closed-peer-first";
            return;
        }
        if (rc == brick.failed) {
            s.report.end = "alert";
            return;
        }
        if (!try s.step()) return;
    }
}

fn emit(w: *std.Io.Writer, r: Report) !void {
    try w.print(
        "{{\"role\":\"{s}\",\"handshake\":{},\"suite\":\"{s}\",\"alpn\":\"{s}\",\"bytes_in\":{d},\"bytes_out\":{d},\"echo_ok\":{},\"alert\":{d},\"alert_from_peer\":{},\"untrusted\":{},\"ku_sent\":{d},\"ku_read\":{d},\"sent_close\":{},\"end\":\"{s}\"}}\n",
        .{ r.role, r.handshake, r.suite, r.alpn, r.bytes_in, r.bytes_out, r.echo_ok, r.alert, r.alert_from_peer, r.untrusted, r.ku_sent, r.ku_read, r.sent_close, r.end },
    );
    try w.flush();
}

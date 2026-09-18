//! Step 39's cost of the chain check (bench/step39/cost.py builds and runs it): for each key type,
//! the brick's `checkChain` on gen.sh's chain of three (the leaf and intermediate a server sends,
//! the root trusted), µs a call, and whole handshakes a second, the brick's client against the
//! brick's server through the exported ABI in memory, one thread, no socket. Built once against
//! this tree's tls.zig and once against the tree before step 39 (whose `checkChain` cost.py makes
//! `pub` in a copy), so the two differ in the chain check alone.
//!
//! Usage: mo-tls-cost DIR CALLS HANDSHAKES, DIR holding gen.sh's cert.pem, key.pem, root.pem and
//! their -p256 twins. Output, one line a key type: `key µs-a-check handshakes-a-second`.
const std = @import("std");
const brick = @import("tls_brick");

const now: i64 = 1767225600; // 2026-01-01, inside every fixture's dates

pub fn main(init: std.process.Init) !u8 {
    const gpa = std.heap.smp_allocator;
    const argv = try init.minimal.args.toSlice(init.arena.allocator());
    if (argv.len != 4) {
        std.debug.print("usage: mo-tls-cost DIR CALLS HANDSHAKES\n", .{});
        return 2;
    }
    const calls = try std.fmt.parseInt(usize, argv[2], 10);
    const handshakes = try std.fmt.parseInt(usize, argv[3], 10);
    var out_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &out_buf);
    const w = &stdout.interface;
    for ([_][]const u8{ "", "-p256" }, [_][]const u8{ "ed25519", "p256" }) |sfx, label| {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const dir = std.Io.Dir.cwd();
        const cert = try dir.readFileAlloc(init.io, try std.fmt.allocPrint(arena, "{s}/cert{s}.pem", .{ argv[1], sfx }), arena, .limited(1 << 16));
        const key = try dir.readFileAlloc(init.io, try std.fmt.allocPrint(arena, "{s}/key{s}.pem", .{ argv[1], sfx }), arena, .limited(1 << 16));
        const root = try dir.readFileAlloc(init.io, try std.fmt.allocPrint(arena, "{s}/root{s}.pem", .{ argv[1], sfx }), arena, .limited(1 << 16));
        const chain = try ders(arena, cert);
        const trust = try ders(arena, root);

        var t0 = std.Io.Clock.awake.now(init.io);
        for (0..calls) |_| {
            if (brick.checkChain(chain, trust, "localhost", now)) |alert| {
                std.debug.print("the chain was refused: {t}\n", .{alert});
                return 1;
            }
        }
        const check_ns = t0.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds();

        const server = brick.mo_tls_server_new(cert.ptr, cert.len, key.ptr, key.len) orelse return error.NoServer;
        defer brick.mo_tls_server_free(server);
        const client = brick.mo_tls_client_new(root.ptr, root.len) orelse return error.NoClient;
        defer brick.mo_tls_client_free(client);
        t0 = std.Io.Clock.awake.now(init.io);
        for (0..handshakes) |_| {
            const s = brick.mo_tls_conn_new(server) orelse return error.NoConn;
            defer brick.mo_tls_conn_free(s);
            const c = brick.mo_tls_connect(client, "localhost", 9, now) orelse return error.NoConn;
            defer brick.mo_tls_conn_free(c);
            var buf: [1 << 16]u8 = undefined;
            for (0..20) |_| {
                var moved: usize = 0;
                for ([_]*brick.Conn{ c, s }, [_]*brick.Conn{ s, c }) |from, to| {
                    var n: usize = 0;
                    _ = brick.mo_tls_flush(from, &buf, buf.len, &n);
                    brick.mo_tls_sent(from, n);
                    if (n > 0) _ = brick.mo_tls_feed(to, &buf, n);
                    moved += n;
                }
                if (moved == 0) break;
            }
            if (!brick.mo_tls_ready(c) or !brick.mo_tls_ready(s)) {
                std.debug.print("a handshake did not finish\n", .{});
                return 1;
            }
        }
        const hs_ns = t0.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds();
        const us_check = @as(f64, @floatFromInt(check_ns)) / 1000.0 / @as(f64, @floatFromInt(calls));
        const per_sec = @as(f64, @floatFromInt(handshakes)) * 1e9 / @as(f64, @floatFromInt(hs_ns));
        try w.print("{s} {d:.1} {d:.0}\n", .{ label, us_check, per_sec });
    }
    try w.flush();
    return 0;
}

/// The DER of each certificate in PEM text, in order.
fn ders(arena: std.mem.Allocator, pem: []const u8) ![][]u8 {
    var out: std.ArrayList([]u8) = .empty;
    const begin = "-----BEGIN CERTIFICATE-----";
    const end = "-----END CERTIFICATE-----";
    var rest = pem;
    while (std.mem.indexOf(u8, rest, begin)) |b| {
        const e = std.mem.indexOfPos(u8, rest, b, end) orelse break;
        var text: std.ArrayList(u8) = .empty;
        for (rest[b + begin.len .. e]) |ch| if (!std.ascii.isWhitespace(ch)) try text.append(arena, ch);
        const der = try arena.alloc(u8, try std.base64.standard.Decoder.calcSizeForSlice(text.items));
        try std.base64.standard.Decoder.decode(der, text.items);
        try out.append(arena, der);
        rest = rest[e + end.len ..];
    }
    return out.toOwnedSlice(arena);
}

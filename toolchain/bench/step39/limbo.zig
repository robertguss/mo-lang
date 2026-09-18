//! The x509-limbo run's checker (bench/step39/limbo.py writes its input and reads its output):
//! the TLS brick's own chain check, `checkChain`, the code a client runs on a server's chain,
//! called on each case with no handshake around it (limbo gives no leaf's private key for most
//! cases, and the check is the same code either way).
//!
//! Input, the file named on the command line: one case a line, `id`, then the chain as a server
//! sends it (leaf first, hex DER, comma-separated), the trusted roots (hex DER, comma-separated),
//! the host, and the validation time in seconds, separated by tabs. Output, one line a case: the
//! id, a tab, and `ok` or the alert's name.
const std = @import("std");
const brick = @import("tls_brick");

pub fn main(init: std.process.Init) !u8 {
    const gpa = std.heap.smp_allocator;
    const argv = try init.minimal.args.toSlice(init.arena.allocator());
    if (argv.len != 2) {
        std.debug.print("usage: mo-tls-limbo CASES\n", .{});
        return 2;
    }
    const text = try std.Io.Dir.cwd().readFileAlloc(init.io, argv[1], gpa, .limited(512 << 20));
    var out_buf: [1 << 16]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &out_buf);
    const w = &stdout.interface;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        var fields = std.mem.splitScalar(u8, line, '\t');
        const id = fields.next() orelse continue;
        const chain = try hexList(arena, fields.next() orelse "");
        const trust = try hexList(arena, fields.next() orelse "");
        const host = fields.next() orelse "";
        const now = try std.fmt.parseInt(i64, fields.next() orelse "0", 10);
        const answer = if (chain.len == 0) "no-chain" else if (brick.checkChain(chain, trust, host, now)) |desc| @tagName(desc) else "ok";
        try w.print("{s}\t{s}\n", .{ id, answer });
    }
    try w.flush();
    return 0;
}

fn hexList(arena: std.mem.Allocator, field: []const u8) ![][]u8 {
    var out: std.ArrayList([]u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, field, ',');
    while (it.next()) |h| {
        const bytes = try arena.alloc(u8, h.len / 2);
        _ = try std.fmt.hexToBytes(bytes, h);
        try out.append(arena, bytes);
    }
    return out.toOwnedSlice(arena);
}

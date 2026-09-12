//! The benchmark harness, from day one (design-v0/08: "50 ms and 100 ms targets:
//! the benchmark suite, from day one"). Times every pipeline stage over every file
//! in the corpus, best of N iterations, and prints one row per stage. Stages that
//! are not implemented print "n/a" and the row lights up when the stage lands.
//!
//!   zig build bench                      corpus at ../examples, 20 iterations
//!   zig build bench -- <dir> <iters>     override both
//!   zig build bench -- ... --record      also append a row to bench/results.tsv
//!
//! bench/rebuild.sh times the toolchain's own incremental build, the other number
//! chapter 8 asks for.
const std = @import("std");
const Io = std.Io;
const mo = @import("mo");

const Row = struct { stage: mo.pipeline.Stage, files: u32, best_ns: i96, implemented: bool };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    var root: []const u8 = "../examples";
    var iters: u32 = 20;
    var record = false;
    var positional: u32 = 0;
    for (args[1..]) |a| {
        if (std.mem.eql(u8, a, "--record")) {
            record = true;
        } else if (positional == 0) {
            root = a;
            positional += 1;
        } else {
            iters = try std.fmt.parseInt(u32, a, 10);
        }
    }

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const out = &stdout_writer.interface;
    defer out.flush() catch {};

    const paths = try mo.corpus.collect(arena, io, root);
    var sources = try arena.alloc([]const u8, paths.len);
    var dir = try Io.Dir.cwd().openDir(io, root, .{});
    defer dir.close(io);
    var total_bytes: usize = 0;
    for (paths, 0..) |rel, i| {
        sources[i] = try dir.readFileAlloc(io, rel, arena, .limited(1 << 20));
        total_bytes += sources[i].len;
    }

    try out.print("mo-bench: {d} files, {d} bytes, best of {d}\n", .{ paths.len, total_bytes, iters });
    try out.print("{s:<8} {s:>12} {s:>12}\n", .{ "stage", "total", "per file" });

    var rows: [mo.pipeline.stages.len]Row = undefined;
    for (mo.pipeline.stages, 0..) |stage, si| {
        var best: i96 = std.math.maxInt(i96);
        var implemented = true;
        var it: u32 = 0;
        while (it < iters and implemented) : (it += 1) {
            const t0 = Io.Clock.Timestamp.now(io, .awake);
            for (sources) |src| {
                var diags: mo.diag.List = .empty;
                defer diags.deinit(arena);
                mo.pipeline.runTo(arena, src, stage, &diags) catch |e| switch (e) {
                    error.NotImplemented => {
                        implemented = false;
                        break;
                    },
                    else => {},
                };
            }
            const t1 = Io.Clock.Timestamp.now(io, .awake);
            const ns = t0.durationTo(t1).raw.toNanoseconds();
            if (ns < best) best = ns;
        }
        rows[si] = .{ .stage = stage, .files = @intCast(paths.len), .best_ns = best, .implemented = implemented };
        if (implemented) {
            const per: i96 = if (paths.len == 0) 0 else @divTrunc(best, @as(i96, @intCast(paths.len)));
            try out.print("{s:<8} {d:>9} µs {d:>9} µs\n", .{ @tagName(stage), @as(u64, @intCast(@divTrunc(best, 1000))), @as(u64, @intCast(@divTrunc(per, 1000))) });
        } else {
            try out.print("{s:<8} {s:>12} {s:>12}\n", .{ @tagName(stage), "n/a", "n/a" });
        }
    }

    if (record) try appendResults(io, &rows, paths.len);
}

/// One row per stage: date, stage, files, best total µs ("n/a" when unimplemented).
fn appendResults(io: Io, rows: []const Row, files: usize) !void {
    var file = try Io.Dir.cwd().openFile(io, "bench/results.tsv", .{ .mode = .write_only });
    defer file.close(io);
    var buf: [1024]u8 = undefined;
    var w: Io.File.Writer = .init(file, io, &buf);
    try w.seekTo(try file.length(io));
    defer w.interface.flush() catch {};
    const secs = Io.Clock.Timestamp.now(io, .real).raw.toNanoseconds();
    const day = @divTrunc(secs, std.time.ns_per_s);
    for (rows) |r| {
        if (r.implemented) {
            try w.interface.print("{d}\t{s}\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), @tagName(r.stage), files, @as(u64, @intCast(@divTrunc(r.best_ns, 1000))) });
        } else {
            try w.interface.print("{d}\t{s}\t{d}\tn/a\n", .{ @as(u64, @intCast(day)), @tagName(r.stage), files });
        }
    }
}

//! The corpus test: every `examples/**/*.mo` must pass every implemented stage,
//! except `examples/rejects/`, which must be rejected with a diagnostic. Until a
//! stage exists it returns NotImplemented and the file counts as skipped, so this
//! test is green on day one and tightens as stages land.
const std = @import("std");
const Io = std.Io;
const pipeline = @import("pipeline.zig");
const diag = @import("diag.zig");

pub const Tally = struct { passed: u32 = 0, rejected_as_expected: u32 = 0, skipped: u32 = 0, failed: u32 = 0 };

pub fn isRejectsPath(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "rejects/") or std.mem.indexOf(u8, path, "/rejects/") != null;
}

/// Collects the relative paths of every .mo file under `root`, sorted.
pub fn collect(gpa: std.mem.Allocator, io: Io, root: []const u8) ![][]const u8 {
    var dir = try Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(gpa);
    defer walker.deinit();
    var paths: std.ArrayList([]const u8) = .empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.basename, ".mo")) continue;
        try paths.append(gpa, try gpa.dupe(u8, entry.path));
    }
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);
    return paths.toOwnedSlice(gpa);
}

pub fn runOne(gpa: std.mem.Allocator, io: Io, root: []const u8, rel: []const u8, stage: pipeline.Stage, tally: *Tally) !void {
    var dir = try Io.Dir.cwd().openDir(io, root, .{});
    defer dir.close(io);
    // Everything a stage allocates, diagnostics included, lives in one arena per file.
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const source = try dir.readFileAlloc(io, rel, arena, .limited(1 << 20));
    var diags: diag.List = .empty;
    const expect_reject = isRejectsPath(rel);
    if (pipeline.runTo(arena, source, stage, &diags)) {
        if (expect_reject) tally.failed += 1 else tally.passed += 1;
    } else |err| switch (err) {
        error.NotImplemented => tally.skipped += 1,
        error.Rejected => if (expect_reject) {
            tally.rejected_as_expected += 1;
        } else {
            tally.failed += 1;
        },
        else => tally.failed += 1,
    }
}

test "corpus: every example passes every implemented stage; rejects/ is rejected" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const root = "../examples";
    const paths = collect(gpa, io, root) catch |err| switch (err) {
        error.FileNotFound => return, // no corpus checked out beside the toolchain
        else => return err,
    };
    defer {
        for (paths) |p| gpa.free(p);
        gpa.free(paths);
    }
    var tally: Tally = .{};
    for (paths) |rel| try runOne(gpa, io, root, rel, .run, &tally);
    try std.testing.expectEqual(@as(u32, 0), tally.failed);
}

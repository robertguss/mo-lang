//! The corpus test: every `examples/**/*.mo` must pass every implemented stage,
//! except `examples/rejects/`, whose first diagnostic must carry the code on the
//! file's `# expect MO0xxx: sentence` line. At the run stage every test of every
//! other file passes, every `test rejects` trips, and every property holds; the only
//! skips are tests that start a process and recipe tests that reach a signature no
//! agent has implemented. Until a stage exists it returns NotImplemented and the file
//! counts as skipped, so this test is green on day one and tightens as stages land.
const std = @import("std");
const Io = std.Io;
const pipeline = @import("pipeline.zig");
const runner = @import("runner.zig");
const diag = @import("diag.zig");

pub const Tally = struct {
    passed: u32 = 0,
    rejected_as_expected: u32 = 0,
    skipped: u32 = 0,
    failed: u32 = 0,
    /// Files whose tests start a process.
    process_files: u32 = 0,
    skipped_tests: u32 = 0,
};

pub const process_skip = "processes run in step 4";
pub const recipe_skip = "until an agent implements the recipe";

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

/// The code on a rejects file's `# expect MO0xxx: sentence` line.
pub fn expectedCode(source: []const u8) ?[]const u8 {
    const marker = "# expect ";
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, source, from, marker)) |at| {
        from = at + 1;
        if (at > 0 and source[at - 1] != '\n') continue;
        const rest = source[at + marker.len ..];
        const colon = std.mem.indexOfScalar(u8, rest, ':') orelse return null;
        const code = rest[0..colon];
        return if (code.len == 6 and std.mem.startsWith(u8, code, "MO")) code else null;
    }
    return null;
}

test "a rejects file names the code its first diagnostic carries" {
    try std.testing.expectEqualStrings("MO0306", expectedCode("module A\n# expect MO0306: base is bound twice.\n").?);
    try std.testing.expect(expectedCode("module A\n# expect error: something\n") == null);
    try std.testing.expect(expectedCode("x = 1 # expect MO0306: not at a line start\n") == null);
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
    // A rejects/ file breaks a law, so it must lex and parse; only the checker rejects it.
    const expect_reject = isRejectsPath(rel) and @intFromEnum(stage) >= @intFromEnum(pipeline.Stage.check);
    if (stage == .run and !expect_reject) {
        if (pipeline.testSource(arena, source, &diags)) |r| {
            var ok = r.summary.failures == 0;
            var process_skips: u32 = 0;
            for (r.results) |result| {
                const reason = if (result.report) |report| report.clause else "";
                switch (result.outcome) {
                    .passed, .tripped_as_expected => continue,
                    .skipped => {
                        tally.skipped_tests += 1;
                        if (std.mem.eql(u8, reason, process_skip)) {
                            process_skips += 1;
                            continue;
                        }
                        if (std.mem.startsWith(u8, rel, "recipes/") and std.mem.endsWith(u8, reason, recipe_skip)) continue;
                        ok = false;
                    },
                    .failed, .did_not_trip => {},
                }
                var buf: [2048]u8 = undefined;
                var w: Io.Writer = .fixed(&buf);
                runner.writeResult(&w, rel, source, result) catch {};
                std.debug.print("corpus: {s}", .{w.buffered()});
            }
            if (r.summary.processes > 0) tally.process_files += 1;
            if (ok) tally.passed += 1 else tally.failed += 1;
            return;
        } else |err| switch (err) {
            error.Rejected => {
                tally.failed += 1;
                const d = diags.items[0];
                std.debug.print("corpus: {s} at byte {d}: {s} {s}\n", .{ rel, d.at, d.code, d.what });
                return;
            },
            else => return err,
        }
    }
    if (pipeline.runTo(arena, source, stage, &diags)) {
        if (expect_reject) {
            tally.failed += 1;
            std.debug.print("corpus: {s} was not rejected\n", .{rel});
        } else tally.passed += 1;
    } else |err| switch (err) {
        error.NotImplemented => tally.skipped += 1,
        error.Rejected => {
            const d = diags.items[0];
            const want = expectedCode(source);
            if (expect_reject and d.category != .syntax and want != null and std.mem.eql(u8, d.code, want.?)) {
                tally.rejected_as_expected += 1;
            } else if (expect_reject) {
                tally.failed += 1;
                std.debug.print("corpus: {s} expects {s}, but its first diagnostic is {s} {s}\n", .{ rel, want orelse "an `# expect MO0xxx:` line", d.code, d.what });
            } else {
                tally.failed += 1;
                std.debug.print("corpus: {s} at byte {d}: {s} {s}\n", .{ rel, d.at, d.code, d.what });
            }
        },
        else => {
            tally.failed += 1;
            std.debug.print("corpus: {s}: {t}\n", .{ rel, err });
        },
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
    // A claimed stage handles the whole corpus: no failures and no NotImplemented.
    var tally: Tally = .{};
    for (paths) |rel| try runOne(gpa, io, root, rel, pipeline.implemented, &tally);
    try std.testing.expectEqual(@as(u32, 0), tally.failed);
    try std.testing.expectEqual(@as(u32, 0), tally.skipped);
    try std.testing.expectEqual(paths.len, tally.passed + tally.rejected_as_expected);
    // The seven processes/ files and the refund queue start processes and run their tests.
    if (pipeline.implemented == .run) try std.testing.expectEqual(@as(u32, 8), tally.process_files);

    // Stages beyond `implemented` may still be stubs; those files count as skipped.
    var beyond: Tally = .{};
    if (pipeline.implemented != .run) {
        for (paths) |rel| try runOne(gpa, io, root, rel, .run, &beyond);
    }
    try std.testing.expectEqual(@as(u32, 0), beyond.failed);
}

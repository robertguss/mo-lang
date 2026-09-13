//! The corpus test: every `examples/**/*.mo` must pass every implemented stage,
//! except `examples/rejects/`, whose first diagnostic must carry the code on the
//! file's `# expect MO0xxx: sentence` line. At the run stage every test of every
//! other file passes, every `test rejects` trips, every property holds, and no process
//! crashes; the only skips are recipe tests that reach a signature no agent has
//! implemented. Until a stage exists it returns NotImplemented and the file
//! counts as skipped, so this test is green on day one and tightens as stages land.
//! Every file, rejects/ included, also passes `mo fmt --check`: it is already in its
//! one shape (toolchain/FORMAT.md) and has no pure for body (MO0501).
//! Every program in `examples/programs/` also runs through `mo run`, on Mo.Server, as a
//! subprocess of the test: its stdout must equal `<name>.expected` and its exit code
//! the one on its `# exit:` line, or 0.
const std = @import("std");
const Io = std.Io;
const pipeline = @import("pipeline.zig");
const runner = @import("runner.zig");
const diag = @import("diag.zig");
const fmt = @import("fmt.zig");

pub const Tally = struct {
    passed: u32 = 0,
    rejected_as_expected: u32 = 0,
    skipped: u32 = 0,
    failed: u32 = 0,
    /// Files whose tests start a process.
    process_files: u32 = 0,
    skipped_tests: u32 = 0,
};

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

pub fn isProgramPath(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "programs/");
}

/// A program's first line, `# run: arg1 arg2`: the arguments `mo run` passes after `--`.
pub fn runArgs(gpa: std.mem.Allocator, source: []const u8) !?[]const []const u8 {
    const marker = "# run:";
    if (!std.mem.startsWith(u8, source, marker)) return null;
    const line_end = std.mem.indexOfScalar(u8, source, '\n') orelse source.len;
    var args: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeScalar(u8, source[marker.len..line_end], ' ');
    while (it.next()) |a| try args.append(gpa, a);
    return try args.toOwnedSlice(gpa);
}

/// The code on a program's `# exit: N` line, or 0 when it has none.
pub fn expectedExit(source: []const u8) !u8 {
    const marker = "\n# exit: ";
    const at = std.mem.indexOf(u8, source, marker) orelse return 0;
    const rest = source[at + marker.len ..];
    return std.fmt.parseInt(u8, rest[0 .. std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len], 10);
}

test "a program names its arguments on its first line and its exit code on an # exit: line" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const src = "# run: a  b\n# exit: 3\nmodule P\n";
    const args = (try runArgs(arena, src)).?;
    try std.testing.expectEqual(@as(usize, 2), args.len);
    try std.testing.expectEqualStrings("b", args[1]);
    try std.testing.expectEqual(@as(u8, 3), try expectedExit(src));
    try std.testing.expectEqual(@as(usize, 0), (try runArgs(arena, "# run:\nmodule P\n")).?.len);
    try std.testing.expectEqual(@as(u8, 0), try expectedExit("# run:\nmodule P\n"));
    try std.testing.expect(try runArgs(arena, "module P\n# run: a\n") == null);
}

/// The `mo` build.zig installed and named in MO_EXE (or zig-out/bin/mo), made absolute
/// so a program can run in its own folder.
pub fn moExe(gpa: std.mem.Allocator, io: Io, from_environ: ?[]const u8) ![:0]u8 {
    return Io.Dir.cwd().realPathFileAlloc(io, from_environ orelse "zig-out/bin/mo", gpa);
}

/// `mo run <program> -- <its # run: arguments>`, with the program's own folder as the
/// working directory, so it names its data/ folder by that relative path.
pub fn runProgram(arena: std.mem.Allocator, io: Io, mo_exe: []const u8, root: []const u8, rel: []const u8, source: []const u8) !std.process.RunResult {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ mo_exe, "run", std.fs.path.basename(rel), "--" });
    try argv.appendSlice(arena, (try runArgs(arena, source)) orelse &.{});
    const cwd = try std.fs.path.join(arena, &.{ root, std.fs.path.dirname(rel) orelse "." });
    return std.process.run(arena, io, .{ .argv = argv.items, .cwd = .{ .path = cwd } });
}

/// Runs one program: true when its stdout equals `<name>.expected` and its exit code the
/// one its `# exit:` line names.
pub fn checkProgram(gpa: std.mem.Allocator, io: Io, mo_exe: []const u8, root: []const u8, rel: []const u8) !bool {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var dir = try Io.Dir.cwd().openDir(io, root, .{});
    defer dir.close(io);
    const source = try dir.readFileAlloc(io, rel, arena, .limited(1 << 20));
    if ((try runArgs(arena, source)) == null) {
        std.debug.print("corpus: {s} is a program, so its first line is # run: and its arguments\n", .{rel});
        return false;
    }
    const expected_path = try std.fmt.allocPrint(arena, "{s}.expected", .{rel[0 .. rel.len - ".mo".len]});
    const expected = dir.readFileAlloc(io, expected_path, arena, .limited(1 << 20)) catch |err| {
        std.debug.print("corpus: {s} has no {s} beside it: {t}\n", .{ rel, expected_path, err });
        return false;
    };
    const r = try runProgram(arena, io, mo_exe, root, rel, source);
    const want = try expectedExit(source);
    if (r.term != .exited or r.term.exited != want) {
        std.debug.print("corpus: {s} ended with {any}, not exit {d}; its stderr:\n{s}\n", .{ rel, r.term, want, r.stderr });
        return false;
    }
    if (!std.mem.eql(u8, r.stdout, expected)) {
        std.debug.print("corpus: {s} printed\n{s}\nbut {s} holds\n{s}\n", .{ rel, r.stdout, expected_path, expected });
        return false;
    }
    return true;
}

/// `mo fmt --check` on one file: true when formatting changes nothing and the loop
/// rule finds nothing.
pub fn fmtCheck(gpa: std.mem.Allocator, io: Io, root: []const u8, rel: []const u8) !bool {
    var dir = try Io.Dir.cwd().openDir(io, root, .{});
    defer dir.close(io);
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const source = try dir.readFileAlloc(io, rel, arena, .limited(1 << 20));
    var diags: diag.List = .empty;
    const formatted = fmt.format(arena, source, &diags) catch |err| switch (err) {
        error.Rejected => {
            std.debug.print("corpus: {s} does not format: {s} {s}\n", .{ rel, diags.items[0].code, diags.items[0].what });
            return false;
        },
        else => return err,
    };
    if (!std.mem.eql(u8, source, formatted)) {
        std.debug.print("corpus: {s} is not formatted; run mo fmt on it\n", .{rel});
        return false;
    }
    var findings: diag.List = .empty;
    pipeline.loopFindings(arena, source, &findings) catch |err| switch (err) {
        error.Rejected => {},
        else => return err,
    };
    if (findings.items.len > 0) {
        std.debug.print("corpus: {s} at byte {d}: {s} {s}\n", .{ rel, findings.items[0].at, findings.items[0].code, findings.items[0].what });
        return false;
    }
    return true;
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
            for (r.results) |result| {
                const reason = if (result.report) |report| report.clause else "";
                switch (result.outcome) {
                    .passed, .tripped_as_expected => continue,
                    .skipped => {
                        tally.skipped_tests += 1;
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
    if (pipeline.implemented == .run) {
        try std.testing.expectEqual(@as(u32, 8), tally.process_files);
        // No test is skipped for a process reason: the four recipe tests are the only skips.
        try std.testing.expectEqual(@as(u32, 4), tally.skipped_tests);
    }

    // `mo fmt --check` over every file.
    var unformatted: u32 = 0;
    for (paths) |rel| {
        if (!try fmtCheck(gpa, io, root, rel)) unformatted += 1;
    }
    try std.testing.expectEqual(@as(u32, 0), unformatted);

    // Every program runs through the installed `mo run`, on Mo.Server.
    const from_environ = std.testing.environ.getAlloc(gpa, "MO_EXE") catch null;
    defer if (from_environ) |e| gpa.free(e);
    const mo_exe = try moExe(gpa, io, from_environ);
    defer gpa.free(mo_exe);
    var programs: u32 = 0;
    var wrong: u32 = 0;
    for (paths) |rel| {
        if (!isProgramPath(rel)) continue;
        programs += 1;
        if (!try checkProgram(gpa, io, mo_exe, root, rel)) wrong += 1;
    }
    try std.testing.expectEqual(@as(u32, 3), programs);
    try std.testing.expectEqual(@as(u32, 0), wrong);

    // Stages beyond `implemented` may still be stubs; those files count as skipped.
    var beyond: Tally = .{};
    if (pipeline.implemented != .run) {
        for (paths) |rel| try runOne(gpa, io, root, rel, .run, &beyond);
    }
    try std.testing.expectEqual(@as(u32, 0), beyond.failed);
}

//! The corpus test: every `examples/**/*.mo` must pass every implemented stage,
//! except `examples/rejects/`, whose first diagnostic must carry the code on the
//! file's `# expect MO0xxx: sentence` line. At the run stage every test of every
//! other file passes, every `test rejects` trips, every property holds, and no process
//! crashes; the only skips are recipe tests that reach a signature no agent has
//! implemented. Every test that starts a process also runs under 100 seeds with faults
//! (`mo test --sim 100`, seeded by the file's hash) and holds under them, except
//! `processes/racy.mo`, whose tests must fail under --sim and pass without it.
//! Until a stage exists it returns NotImplemented and the file
//! counts as skipped, so this test is green on day one and tightens as stages land.
//! Each file is loaded with every module it uses (program.zig), and its own tests run.
//! Every file, rejects/ included, also passes `mo fmt --check`: it is already in its
//! one shape (toolchain/FORMAT.md) and has no pure for body (MO0501). The error catalog
//! page, mo-wiki/spec/errors.md, is what the diagnostic tables render.
//! Every program in `examples/programs/` also runs through `mo run`, on Mo.Server, as a
//! subprocess of the test. A program is `programs/<name>.mo`, or `programs/<name>/main.mo`
//! beside the modules it uses. Each `# run:` line at the top of its main file is one
//! run: the first run's stdout must equal `<name>.expected`, the second's
//! `<name>-2.expected`, and so on, and its exit code the one on the `# exit:` line after
//! it, or 0.
const std = @import("std");
const Io = std.Io;
const pipeline = @import("pipeline.zig");
const program = @import("program.zig");
const runner = @import("runner.zig");
const diag = @import("diag.zig");
const fmt = @import("fmt.zig");
const errors = @import("errors.zig");

pub const Tally = struct {
    passed: u32 = 0,
    rejected_as_expected: u32 = 0,
    skipped: u32 = 0,
    failed: u32 = 0,
    /// Files whose tests start a process.
    process_files: u32 = 0,
    skipped_tests: u32 = 0,
    /// Process tests that held under 100 seeds with faults, and those that passed only
    /// without faults.
    held_under_faults: u32 = 0,
    fault_free_only: u32 = 0,
};

pub const recipe_skip = "until an agent implements the recipe";

/// Seeded runs of every process test in the corpus test.
pub const sim_runs: u32 = 100;
/// The corpus's race: its tests hold in the fixed order and fail under --sim.
pub const racy = "processes/racy.mo";

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

/// A program's main file: `programs/<name>.mo`, or `programs/<name>/main.mo`. The other
/// files in a program's folder are the modules it uses.
pub fn isProgramPath(path: []const u8) bool {
    const prefix = "programs/";
    if (!std.mem.startsWith(u8, path, prefix)) return false;
    const rest = path[prefix.len..];
    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return true;
    return std.mem.eql(u8, rest[slash + 1 ..], "main.mo");
}

/// A program's name: its file's, or its folder's.
pub fn programName(path: []const u8) []const u8 {
    const rest = path["programs/".len..];
    if (std.mem.indexOfScalar(u8, rest, '/')) |slash| return rest[0..slash];
    return rest[0 .. rest.len - ".mo".len];
}

pub const Run = struct { args: []const []const u8, exit: u8 = 0 };

/// The runs a program's main file names on its first lines: each `# run: a b` passes
/// a and b after `--`, and an `# exit: N` line right after it names the code that run
/// ends with.
pub fn runs(gpa: std.mem.Allocator, source: []const u8) ![]const Run {
    var out: std.ArrayList(Run) = .empty;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "# run:")) {
            var args: std.ArrayList([]const u8) = .empty;
            var it = std.mem.tokenizeScalar(u8, line["# run:".len..], ' ');
            while (it.next()) |a| try args.append(gpa, a);
            try out.append(gpa, .{ .args = try args.toOwnedSlice(gpa) });
        } else if (std.mem.startsWith(u8, line, "# exit: ") and out.items.len > 0) {
            out.items[out.items.len - 1].exit = try std.fmt.parseInt(u8, line["# exit: ".len..], 10);
        } else break;
    }
    return out.toOwnedSlice(gpa);
}

test "a program names its runs, and each run's exit code, on its first lines" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const found = try runs(arena, "# run: a  b\n# exit: 3\n# run: c\nmodule P\n# run: d\n");
    try std.testing.expectEqual(@as(usize, 2), found.len);
    try std.testing.expectEqualStrings("b", found[0].args[1]);
    try std.testing.expectEqual(@as(u8, 3), found[0].exit);
    try std.testing.expectEqual(@as(usize, 1), found[1].args.len);
    try std.testing.expectEqual(@as(u8, 0), found[1].exit);
    try std.testing.expectEqual(@as(usize, 0), (try runs(arena, "# run:\nmodule P\n"))[0].args.len);
    try std.testing.expectEqual(@as(usize, 0), (try runs(arena, "module P\n# run: a\n")).len);
    try std.testing.expect(isProgramPath("programs/hello.mo") and isProgramPath("programs/logstat/main.mo"));
    try std.testing.expect(!isProgramPath("programs/logstat/parse.mo") and !isProgramPath("basics/hello.mo"));
    try std.testing.expectEqualStrings("logstat", programName("programs/logstat/main.mo"));
    try std.testing.expectEqualStrings("hello", programName("programs/hello.mo"));
}

/// The `mo` build.zig installed and named in MO_EXE (or zig-out/bin/mo), made absolute
/// so a program can run in its own folder.
pub fn moExe(gpa: std.mem.Allocator, io: Io, from_environ: ?[]const u8) ![:0]u8 {
    return Io.Dir.cwd().realPathFileAlloc(io, from_environ orelse "zig-out/bin/mo", gpa);
}

/// `mo run <main file> -- <args>`, with the main file's own folder as the working
/// directory, so it names its data by a path relative to that folder.
pub fn runProgram(arena: std.mem.Allocator, io: Io, mo_exe: []const u8, root: []const u8, rel: []const u8, args: []const []const u8) !std.process.RunResult {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, &.{ mo_exe, "run", std.fs.path.basename(rel), "--" });
    try argv.appendSlice(arena, args);
    const cwd = try std.fs.path.join(arena, &.{ root, std.fs.path.dirname(rel) orelse "." });
    return std.process.run(arena, io, .{ .argv = argv.items, .cwd = .{ .path = cwd } });
}

/// Runs a program once per `# run:` line: true when every run's stdout equals its
/// expected file and its exit code the one its `# exit:` line names.
pub fn checkProgram(gpa: std.mem.Allocator, io: Io, mo_exe: []const u8, root: []const u8, rel: []const u8) !bool {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var dir = try Io.Dir.cwd().openDir(io, root, .{});
    defer dir.close(io);
    const source = try dir.readFileAlloc(io, rel, arena, .limited(1 << 20));
    const program_runs = try runs(arena, source);
    if (program_runs.len == 0) {
        std.debug.print("corpus: {s} is a program, so its first line is # run: and its arguments\n", .{rel});
        return false;
    }
    const folder = std.fs.path.dirname(rel) orelse ".";
    const name = programName(rel);
    var ok = true;
    for (program_runs, 1..) |run, n| {
        const expected_path = if (n == 1)
            try std.fmt.allocPrint(arena, "{s}/{s}.expected", .{ folder, name })
        else
            try std.fmt.allocPrint(arena, "{s}/{s}-{d}.expected", .{ folder, name, n });
        const expected = dir.readFileAlloc(io, expected_path, arena, .limited(1 << 20)) catch |err| {
            std.debug.print("corpus: {s} has no {s} for its run {d}: {t}\n", .{ rel, expected_path, n, err });
            ok = false;
            continue;
        };
        const r = try runProgram(arena, io, mo_exe, root, rel, run.args);
        if (r.term != .exited or r.term.exited != run.exit) {
            std.debug.print("corpus: {s} run {d} ended with {any}, not exit {d}; its stderr:\n{s}\n", .{ rel, n, r.term, run.exit, r.stderr });
            ok = false;
            continue;
        }
        if (!std.mem.eql(u8, r.stdout, expected)) {
            std.debug.print("corpus: {s} run {d} printed\n{s}\nbut {s} holds\n{s}\n", .{ rel, n, r.stdout, expected_path, expected });
            ok = false;
        }
    }
    return ok;
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

/// Whether mo-wiki/spec/errors.md is what the diagnostic tables render.
pub fn catalogCurrent(gpa: std.mem.Allocator, io: Io) !bool {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const on_disk = Io.Dir.cwd().readFileAlloc(io, errors.page, arena, .limited(1 << 20)) catch |err| {
        std.debug.print("corpus: {s}: {t}; run zig build errors\n", .{ errors.page, err });
        return false;
    };
    var rendered: Io.Writer.Allocating = .init(arena);
    try errors.render(&rendered.writer, try errors.rows(arena));
    if (std.mem.eql(u8, on_disk, rendered.written())) return true;
    std.debug.print("corpus: {s} is not what the diagnostic tables render; run zig build errors\n", .{errors.page});
    return false;
}

/// racy.mo under --sim: every test failed in a seeded run (so it held in the fixed order
/// first), and every test passes when the file runs without --sim.
fn checkRacy(arena: std.mem.Allocator, prog: program.Program, simulated: runner.Run, tally: *Tally) !void {
    var diags: diag.List = .empty;
    const fixed = try pipeline.testProgram(arena, prog, false, .{}, &diags);
    var ok = simulated.results.len > 0 and fixed.summary.failures == 0;
    for (simulated.results) |result| {
        if (result.outcome != .failed or result.sim_seed == null) ok = false;
    }
    if (simulated.summary.processes > 0) tally.process_files += 1;
    if (ok) tally.passed += 1 else {
        tally.failed += 1;
        std.debug.print("corpus: {s} must hold without --sim and fail under it\n", .{racy});
    }
}

/// A diagnostic, in the file it points into.
fn printFinding(prog: program.Program, d: diag.Record) void {
    const loc = diag.locate(prog.files, d.at);
    std.debug.print("corpus: {s} at byte {d}: {s} {s}\n", .{ loc.path, loc.at, d.code, d.what });
}

pub fn runOne(gpa: std.mem.Allocator, io: Io, root: []const u8, rel: []const u8, stage: pipeline.Stage, tally: *Tally) !void {
    // Everything a stage allocates, diagnostics included, lives in one arena per file.
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var diags: diag.List = .empty;
    const prog = try program.load(arena, io, try std.fs.path.join(arena, &.{ root, rel }), &diags);
    const source = prog.main().source;
    // A rejects/ file breaks a law, so it must lex and parse; only the checker rejects it.
    const expect_reject = isRejectsPath(rel) and @intFromEnum(stage) >= @intFromEnum(pipeline.Stage.check);
    if (stage == .run and !expect_reject) {
        // The toolchain's line is in the file; the checker says whether it is current.
        if (std.mem.indexOf(u8, source, "\nverified: ") == null) {
            tally.failed += 1;
            std.debug.print("corpus: {s} has no verified: line; run mo test --write --sim 100 on it\n", .{rel});
            return;
        }
        const options: runner.Options = .{ .sim_runs = sim_runs, .sim_seed = runner.seedOf(source) };
        if (pipeline.testProgram(arena, prog, false, options, &diags)) |r| {
            if (std.mem.eql(u8, rel, racy)) return checkRacy(arena, prog, r, tally);
            tally.held_under_faults += r.summary.held_under_faults;
            tally.fault_free_only += r.summary.fault_free_only;
            var ok = r.summary.failures == 0;
            for (r.results) |result| {
                const reason = if (result.report) |report| report.clause else "";
                switch (result.outcome) {
                    // A test that passes only without faults is shown, and counted.
                    .passed, .tripped_as_expected => if (result.fault_seed == null) continue,
                    .skipped => {
                        tally.skipped_tests += 1;
                        if (std.mem.startsWith(u8, rel, "recipes/") and std.mem.endsWith(u8, reason, recipe_skip)) continue;
                        ok = false;
                    },
                    .failed, .did_not_trip => {},
                }
                var buf: [2048]u8 = undefined;
                var w: Io.Writer = .fixed(&buf);
                runner.writeResult(&w, prog.files, result) catch {};
                std.debug.print("corpus: {s}", .{w.buffered()});
            }
            if (r.summary.processes > 0) tally.process_files += 1;
            if (ok) tally.passed += 1 else tally.failed += 1;
            return;
        } else |err| switch (err) {
            error.Rejected => {
                tally.failed += 1;
                printFinding(prog, diags.items[0]);
                return;
            },
            else => return err,
        }
    }
    if (pipeline.runTo(arena, prog, stage, &diags)) {
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
                printFinding(prog, d);
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
    // The eight processes/ files and the refund queue start processes and run their tests.
    if (pipeline.implemented == .run) {
        try std.testing.expectEqual(@as(u32, 9), tally.process_files);
        // Each of the ten process tests outside racy.mo held under 100 seeds with faults,
        // and none needs a world where nothing fails.
        try std.testing.expectEqual(@as(u32, 10), tally.held_under_faults);
        try std.testing.expectEqual(@as(u32, 0), tally.fault_free_only);
        // No test is skipped for a process reason: the four recipe tests are the only skips.
        try std.testing.expectEqual(@as(u32, 4), tally.skipped_tests);
    }

    // `mo fmt --check` over every file.
    var unformatted: u32 = 0;
    for (paths) |rel| {
        if (!try fmtCheck(gpa, io, root, rel)) unformatted += 1;
    }
    try std.testing.expectEqual(@as(u32, 0), unformatted);

    // The error catalog page is what the diagnostic tables render (zig build errors).
    try std.testing.expect(try catalogCurrent(gpa, io));

    // Every program runs through the installed `mo run`, on Mo.Server, once per # run: line.
    const from_environ = std.testing.environ.getAlloc(gpa, "MO_EXE") catch null;
    defer if (from_environ) |e| gpa.free(e);
    const mo_exe = try moExe(gpa, io, from_environ);
    defer gpa.free(mo_exe);
    var programs: std.ArrayList([]const u8) = .empty;
    defer programs.deinit(gpa);
    var wrong: u32 = 0;
    for (paths) |rel| {
        if (!isProgramPath(rel)) continue;
        try programs.append(gpa, programName(rel));
        if (!try checkProgram(gpa, io, mo_exe, root, rel)) wrong += 1;
    }
    const want = [_][]const u8{ "count-lines", "exit-code", "hello", "lines-per-file", "logstat" };
    try std.testing.expectEqual(want.len, programs.items.len);
    for (want, programs.items) |w, found| try std.testing.expectEqualStrings(w, found);
    try std.testing.expectEqual(@as(u32, 0), wrong);

    // Stages beyond `implemented` may still be stubs; those files count as skipped.
    var beyond: Tally = .{};
    if (pipeline.implemented != .run) {
        for (paths) |rel| try runOne(gpa, io, root, rel, .run, &beyond);
    }
    try std.testing.expectEqual(@as(u32, 0), beyond.failed);
}

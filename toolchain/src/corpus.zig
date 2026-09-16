//! The corpus test: every `examples/**/*.mo` must pass every implemented stage,
//! except `examples/rejects/`, whose first diagnostic must carry the code on the
//! file's `# expect MO0xxx: sentence` line. At the run stage every test of every
//! other file passes, every `test rejects` trips, every property holds, and no process
//! crashes; the only skips are recipe tests that reach a signature no agent has
//! implemented. Every test that starts a process also runs under 100 seeds with faults
//! (`mo test --sim 100`, seeded by the file's hash) and holds under them, except
//! `processes/racy.mo`, whose tests must fail under --sim and pass without it. A file whose
//! first lines hold `# sim: --faults P --until F` runs its seeds under those instead.
//! A file whose first lines hold `# recipe: Module.Recipe` is also held to that recipe, as
//! `mo check --recipe` holds it (recipe.zig): its signatures match and the recipe's tests pass
//! against it.
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
//! Every one of those files is also compiled by `mo build` (the C backend, emit_c.zig), with
//! contracts on as in every build, and set beside the interpreter, which is the reference: each module's tests built with
//! `--tests` must print what `mo test` prints and exit as it exits, and each program's binary
//! must print the same stdout and stderr and exit with the same code as `mo run`, once per
//! `# run:` line. No file is refused: a module's process tests run in the fixed order in its test
//! binary, and echo and kv serve over real sockets from their binaries as under `mo run`.
const std = @import("std");
const Io = std.Io;
const pipeline = @import("pipeline.zig");
const program = @import("program.zig");
const runner = @import("runner.zig");
const diag = @import("diag.zig");
const fmt = @import("fmt.zig");
const errors = @import("errors.zig");
const recipe = @import("recipe.zig");
const ast = @import("ast.zig");
const check = @import("check.zig");
const prelude = @import("prelude.zig");

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
    /// Process tests outside racy.mo that ran under seeds: each must be held under faults.
    simulated: u32 = 0,
    /// Recipe tests skipped until an agent implements the recipe: the only skips allowed.
    recipe_skips: u32 = 0,
    /// Files held to the recipe their `# recipe:` line names.
    recipe_checks: u32 = 0,
};

pub const recipe_skip = "until an agent implements the recipe";

/// Seeded runs of every process test in the corpus test.
pub const sim_runs: u32 = 100;
/// The corpus's race: its tests hold in the fixed order and fail under --sim.
pub const racy = "processes/racy.mo";

/// The rows that wait on the outside for something with no bound the program knows: a
/// listener's next client, and a connection's next line.
fn waitsOnOutside(row: prelude.Fn) bool {
    if (std.mem.eql(u8, row.name, "accept")) return std.mem.eql(u8, row.recv, "Listener") or std.mem.eql(u8, row.recv, "HttpListener");
    return std.mem.eql(u8, row.recv, "Conn") and std.mem.eql(u8, row.name, "read_line");
}

/// The source offsets of every `for` in `checked` at or past `from` whose body waits on the
/// outside: calls `accept` or `read_line`, or a function that does, however deep (step 20:
/// the runtime owns that loop, through `serve` and `lines`). An `ask` is not followed: what a
/// process does with a message is its own update's.
pub fn loopsAroundWaits(gpa: std.mem.Allocator, checked: check.Checked, from: u32) ![]const u32 {
    const tree = checked.tree;
    const Unit = struct { first: ast.Index, last: ast.Index, waits: bool = false };
    var units: std.ArrayList(Unit) = .empty;
    // Each item's nodes run from the one after the previous item's to its own (caps.zig).
    const root = tree.nodes[0];
    var prev: ast.Index = 0;
    for (tree.span(root.lhs, root.rhs)) |it| {
        try units.append(gpa, .{ .first = prev + 1, .last = it });
        prev = it;
    }
    const sig_unit = try gpa.alloc(?u32, checked.sigs.len);
    for (checked.sigs, sig_unit) |sig, *u| {
        u.* = for (units.items, 0..) |unit, k| {
            if (sig.node >= unit.first and sig.node <= unit.last) break @intCast(k);
        } else null;
    }
    for (units.items) |*unit| {
        var j = unit.first;
        while (j <= unit.last) : (j += 1) switch (checked.callee[j]) {
            .prelude => |r| if (waitsOnOutside(prelude.fns[r])) {
                unit.waits = true;
            },
            else => {},
        };
    }
    var changed = true;
    while (changed) {
        changed = false;
        for (units.items) |*unit| {
            if (unit.waits) continue;
            var j = unit.first;
            while (j <= unit.last) : (j += 1) switch (checked.callee[j]) {
                .user => |si| if (sig_unit[si]) |k| if (units.items[k].waits) {
                    unit.waits = true;
                    changed = true;
                    break;
                },
                else => {},
            };
        }
    }
    var found: std.ArrayList(u32) = .empty;
    for (tree.nodes, 0..) |n, i| {
        if (n.kind != .for_stmt) continue;
        const at = tree.tokens[n.main_token].start;
        if (at < from) continue;
        // The body's nodes come after the iterable's and before the for's own.
        var j: ast.Index = n.lhs + 1;
        const waits = while (j < i) : (j += 1) switch (checked.callee[j]) {
            .prelude => |r| if (waitsOnOutside(prelude.fns[r])) break true,
            .user => |si| if (sig_unit[si]) |k| if (units.items[k].waits) break true,
            .none => {},
        } else false;
        if (waits) try found.append(gpa, at);
    }
    return found.items;
}

/// How many `for` loops of the file at `rel`, a program with the modules it uses, wait on the
/// outside; each is printed.
pub fn waitingLoops(gpa: std.mem.Allocator, io: Io, root: []const u8, rel: []const u8) !u32 {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var diags: diag.List = .empty;
    const prog = try program.load(arena, io, try std.fs.path.join(arena, &.{ root, rel }), &diags);
    const checked = pipeline.buildable(arena, prog, true, &diags) catch return 0;
    const found = try loopsAroundWaits(arena, checked, prog.main().base);
    for (found) |at| {
        const d: diag.Record = .{ .code = "", .category = .laws, .at = at, .what = "a for around accept or read_line; the runtime owns this loop: serve the listener or read the connection into a process", .why = "" };
        printFinding(prog, d);
    }
    return @intCast(found.len);
}

test "a for whose body waits on a listener or a connection, itself or through a call, is found" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var diags: diag.List = .empty;
    const src =
        \\module T.Loops
        \\fn read(conn: Conn) : Bool
        \\  conn.read_line(within: 1.ms) is Ok(_)
        \\end
        \\fn deeper(conn: Conn) : Bool
        \\  read(conn)
        \\end
        \\fn direct(conn: Conn) : UInt64
        \\  var n = 0
        \\  for _ in 0..3
        \\    if conn.read_line(within: 1.ms) is Ok(_)
        \\      n += 1
        \\    end
        \\  end
        \\  n
        \\end
        \\fn through(conn: Conn, lines: List(String)) : UInt64
        \\  var n = 0
        \\  for line in lines
        \\    if deeper(conn) and line.size > 0
        \\      n += 1
        \\    end
        \\  end
        \\  n
        \\end
        \\fn writes(conn: Conn, lines: List(String)) : UInt64
        \\  var n = 0
        \\  for line in lines
        \\    if conn.write(line, within: 1.ms) is Ok(_)
        \\      n += 1
        \\    end
        \\  end
        \\  n
        \\end
    ;
    const tokens = try @import("lexer.zig").lex(arena, src, &diags);
    const tree = try @import("parser.zig").parse(arena, src, tokens, &diags);
    const checked = try check.check(arena, tree, &diags);
    const found = try loopsAroundWaits(arena, checked, 0);
    try std.testing.expectEqual(@as(usize, 2), found.len);
    try std.testing.expect(std.mem.startsWith(u8, src[found[0] - 4 ..], "for _ in 0..3"));
    try std.testing.expect(std.mem.startsWith(u8, src[found[1] - 4 ..], "for line in lines\n    if deeper"));
}

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

/// The corpus's `--sim` options for a file: `defaults`, with the `--faults P` and `--until F`
/// its `# sim:` line names among its first comment lines.
pub fn simOptions(source: []const u8, defaults: runner.Options) runner.Options {
    var options = defaults;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "#")) break;
        if (!std.mem.startsWith(u8, line, "# sim:")) continue;
        var it = std.mem.tokenizeScalar(u8, line["# sim:".len..], ' ');
        while (it.next()) |flag| {
            const value = it.next() orelse break;
            if (std.mem.eql(u8, flag, "--faults")) options.fault_percent = std.fmt.parseInt(u32, value, 10) catch options.fault_percent;
            if (std.mem.eql(u8, flag, "--until")) options.fault_until = std.fmt.parseFloat(f64, value) catch options.fault_until;
        }
    }
    return options;
}

test "a file's # sim: line names the faults its seeds run under" {
    const plain = simOptions("module A\n", .{ .sim_runs = 100 });
    try std.testing.expectEqual(runner.default_fault_percent, plain.fault_percent);
    try std.testing.expectEqual(@as(f64, 1), plain.fault_until);
    const named = simOptions("# sim: --faults 20 --until 0.5\nmodule A\n", .{ .sim_runs = 100 });
    try std.testing.expectEqual(@as(u32, 20), named.fault_percent);
    try std.testing.expectEqual(@as(f64, 0.5), named.fault_until);
    try std.testing.expectEqual(@as(u32, 100), named.sim_runs);
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

/// Whether the corpus test also runs `rel` through `mo run` and as a binary: a program under
/// `programs/`, or any other corpus file that names its runs on its first line. `processes/`
/// holds one of the latter (step 31), a module whose main shows the construct running.
pub fn isRunnable(io: Io, root: []const u8, rel: []const u8) !bool {
    if (isProgramPath(rel)) return true;
    var dir = try Io.Dir.cwd().openDir(io, root, .{});
    defer dir.close(io);
    var buf: [6]u8 = undefined;
    var file = dir.openFile(io, rel, .{}) catch return false;
    defer file.close(io);
    var reader = file.reader(io, &.{});
    reader.interface.readSliceAll(&buf) catch return false;
    return std.mem.eql(u8, &buf, "# run:");
}

/// A program's name: its file's, or its folder's.
pub fn programName(path: []const u8) []const u8 {
    const rest = if (std.mem.startsWith(u8, path, "programs/")) path["programs/".len..] else std.fs.path.basename(path);
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

/// The programs whose output depends on the order in which two of their processes act, which the
/// spec never promised (design-v0/03, processes; step 30): each runs on one scheduler here, under
/// `mo run` and as a binary, so its expected file holds. programs/agent's check starts several runs at
/// once against one mock model that hands out its script's replies in the order requests reach it, so
/// on more cores than one two runs can take each other's replies. Its source is left as it is.
pub const one_core_programs = [_][]const u8{"programs/agent/main.mo"};

/// Before a program's command: `env MO_CORES=1` when it is one of one_core_programs.
fn coresPrefix(arena: std.mem.Allocator, rel: []const u8, argv: *std.ArrayList([]const u8)) !void {
    for (one_core_programs) |p| if (std.mem.eql(u8, p, rel)) return argv.appendSlice(arena, &.{ "/usr/bin/env", "MO_CORES=1" });
}

/// `mo run <main file> -- <args>`, with the main file's own folder as the working
/// directory, so it names its data by a path relative to that folder.
pub fn runProgram(arena: std.mem.Allocator, io: Io, mo_exe: []const u8, root: []const u8, rel: []const u8, args: []const []const u8) !std.process.RunResult {
    var argv: std.ArrayList([]const u8) = .empty;
    try coresPrefix(arena, rel, &argv);
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

/// What the differential test found: files whose build matched the interpreter, and files that
/// differ.
pub const Built = struct { same: u32 = 0, wrong: u32 = 0 };

/// A build's name: the path with its `/` and `.` as `_`, so no build is itself a .mo file.
fn buildKey(arena: std.mem.Allocator, rel: []const u8) ![]const u8 {
    const key = try arena.dupe(u8, rel[0 .. rel.len - ".mo".len]);
    for (key) |*ch| if (ch.* == '/' or ch.* == '.') {
        ch.* = '_';
    };
    return key;
}

fn sameRun(a: std.process.RunResult, b: std.process.RunResult) bool {
    const exits = a.term == .exited and b.term == .exited and a.term.exited == b.term.exited;
    return exits and std.mem.eql(u8, a.stdout, b.stdout) and std.mem.eql(u8, a.stderr, b.stderr);
}

fn printDifference(what: []const u8, interp: std.process.RunResult, compiled: std.process.RunResult) void {
    std.debug.print("corpus: {s} differs from the interpreter\n  mo:  {any}\n{s}{s}\n  C:   {any}\n{s}{s}\n", .{ what, interp.term, interp.stdout, interp.stderr, compiled.term, compiled.stdout, compiled.stderr });
}

/// `mo build --tests` of one module, from the corpus root, beside `mo test` of it.
pub fn checkBuiltTests(gpa: std.mem.Allocator, io: Io, mo_exe: []const u8, root: []const u8, rel: []const u8, tally: *Built) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const key = try buildKey(arena, rel);
    const built = try std.process.run(arena, io, .{ .argv = &.{ mo_exe, "build", "--tests", "-o", key, rel }, .cwd = .{ .path = root } });
    if (built.term != .exited or built.term.exited != 0) {
        std.debug.print("corpus: mo build --tests {s} failed: {s}\n", .{ rel, built.stderr });
        tally.wrong += 1;
        return;
    }
    const abs_root = try Io.Dir.cwd().realPathFileAlloc(io, root, arena);
    const binary = try std.fs.path.join(arena, &.{ abs_root, "zig-out/mo-build", key, key });
    const interp = try std.process.run(arena, io, .{ .argv = &.{ mo_exe, "test", rel }, .cwd = .{ .path = root } });
    const compiled = try std.process.run(arena, io, .{ .argv = &.{binary}, .cwd = .{ .path = root } });
    if (sameRun(interp, compiled)) tally.same += 1 else {
        printDifference(rel, interp, compiled);
        tally.wrong += 1;
    }
}

/// `mo build` of one program, from its own folder, beside `mo run` of it: one comparison per
/// `# run:` line.
pub fn checkBuiltProgram(gpa: std.mem.Allocator, io: Io, mo_exe: []const u8, root: []const u8, rel: []const u8, tally: *Built) !void {
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var dir = try Io.Dir.cwd().openDir(io, root, .{});
    defer dir.close(io);
    const source = try dir.readFileAlloc(io, rel, arena, .limited(1 << 20));
    const folder = try std.fs.path.join(arena, &.{ root, std.fs.path.dirname(rel) orelse "." });
    const file = std.fs.path.basename(rel);
    const name = programName(rel);
    const built = try std.process.run(arena, io, .{ .argv = &.{ mo_exe, "build", file, "-o", name }, .cwd = .{ .path = folder } });
    const builds = try std.fs.path.join(arena, &.{ folder, "zig-out" });
    defer Io.Dir.cwd().deleteTree(io, builds) catch {};
    if (built.term != .exited or built.term.exited != 0) {
        std.debug.print("corpus: mo build {s} failed: {s}\n", .{ rel, built.stderr });
        tally.wrong += 1;
        return;
    }
    const binary = try std.fs.path.join(arena, &.{ try Io.Dir.cwd().realPathFileAlloc(io, folder, arena), "zig-out/mo-build", name, name });
    for (try runs(arena, source), 1..) |run, n| {
        var interp_argv: std.ArrayList([]const u8) = .empty;
        try coresPrefix(arena, rel, &interp_argv);
        try interp_argv.appendSlice(arena, &.{ mo_exe, "run", file, "--" });
        try interp_argv.appendSlice(arena, run.args);
        var compiled_argv: std.ArrayList([]const u8) = .empty;
        try coresPrefix(arena, rel, &compiled_argv);
        try compiled_argv.append(arena, binary);
        try compiled_argv.appendSlice(arena, run.args);
        const interp = try std.process.run(arena, io, .{ .argv = interp_argv.items, .cwd = .{ .path = folder } });
        const compiled = try std.process.run(arena, io, .{ .argv = compiled_argv.items, .cwd = .{ .path = folder } });
        if (sameRun(interp, compiled)) tally.same += 1 else {
            printDifference(try std.fmt.allocPrint(arena, "{s} run {d}", .{ rel, n }), interp, compiled);
            tally.wrong += 1;
        }
    }
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
    // A rejects file that expects a syntax code does not parse, so it has no one shape.
    if (isRejectsPath(rel)) if (expectedCode(source)) |code| if (std.mem.startsWith(u8, code, "MO01")) return true;
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

/// `mo check --recipe` of a file against the recipe its `# recipe:` line names: every signature
/// matches, and every one of the recipe's tests runs against the file and passes.
fn checkRecipe(arena: std.mem.Allocator, io: Io, root: []const u8, rel: []const u8, name: []const u8) !bool {
    var diags: diag.List = .empty;
    const c = try recipe.conform(arena, io, try std.fs.path.join(arena, &.{ root, rel }), name, &diags);
    const r = c.run orelse {
        const d = diags.items[0];
        const loc = diag.locate(c.files, d.at);
        std.debug.print("corpus: {s} against recipe {s}: {s} at byte {d}: {s} {s}\n", .{ rel, name, loc.path, loc.at, d.code, d.what });
        return false;
    };
    for (r.results) |result| {
        if (result.outcome == .passed or result.outcome == .tripped_as_expected) continue;
        var buf: [2048]u8 = undefined;
        var w: Io.Writer = .fixed(&buf);
        runner.writeResult(&w, c.files, result) catch {};
        std.debug.print("corpus: {s} against recipe {s}: {s}", .{ rel, name, w.buffered() });
    }
    return r.summary.failures == 0 and r.results.len > 0;
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
        const options = simOptions(source, .{ .sim_runs = sim_runs, .sim_seed = runner.seedOf(source) });
        if (pipeline.testProgram(arena, prog, false, options, &diags)) |r| {
            if (std.mem.eql(u8, rel, racy)) return checkRacy(arena, prog, r, tally);
            tally.held_under_faults += r.summary.held_under_faults;
            tally.fault_free_only += r.summary.fault_free_only;
            tally.simulated += r.summary.simulated;
            var ok = r.summary.failures == 0;
            for (r.results) |result| {
                const reason = if (result.report) |report| report.clause else "";
                switch (result.outcome) {
                    // A test that passes only without faults is shown, and counted.
                    .passed, .tripped_as_expected => if (result.fault_seed == null) continue,
                    .skipped => {
                        tally.skipped_tests += 1;
                        if (std.mem.startsWith(u8, rel, "recipes/") and std.mem.endsWith(u8, reason, recipe_skip)) {
                            tally.recipe_skips += 1;
                            continue;
                        }
                        ok = false;
                    },
                    .failed, .did_not_trip => {},
                }
                var buf: [2048]u8 = undefined;
                var w: Io.Writer = .fixed(&buf);
                runner.writeResult(&w, prog.files, result) catch {};
                std.debug.print("corpus: {s}", .{w.buffered()});
            }
            if (recipe.named(source)) |name| {
                if (try checkRecipe(arena, io, root, rel, name)) {
                    tally.recipe_checks += 1;
                } else ok = false;
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
            // A rejects file breaks a law the checker enforces, or, when it expects an MO01xx, is
            // a shape the grammar does not have, whose first diagnostic is the parser's (step 21).
            const syntax_ok = d.category != .syntax or (want != null and std.mem.startsWith(u8, want.?, "MO01"));
            if (expect_reject and syntax_ok and want != null and std.mem.eql(u8, d.code, want.?)) {
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
    // Nothing here names a file or counts the corpus: the counts are what the files hold.
    if (pipeline.implemented == .run) {
        // racy.mo's tests start processes, so at least one file does.
        try std.testing.expect(tally.process_files > 0);
        // Every process test outside racy.mo ran under 100 seeds with faults and held under
        // them, and none needs a world where nothing fails.
        try std.testing.expectEqual(tally.simulated, tally.held_under_faults);
        try std.testing.expectEqual(@as(u32, 0), tally.fault_free_only);
        // No test is skipped for a process reason: recipe tests are the only skips.
        try std.testing.expectEqual(tally.recipe_skips, tally.skipped_tests);
        // Some implementation names the recipe it implements, and was held to it.
        try std.testing.expect(tally.recipe_checks > 0);
    }

    // `mo fmt --check` over every file.
    var unformatted: u32 = 0;
    for (paths) |rel| {
        if (!try fmtCheck(gpa, io, root, rel)) unformatted += 1;
    }
    try std.testing.expectEqual(@as(u32, 0), unformatted);

    // No for waits on the outside (step 20): the runtime owns the loop around accept and
    // read_line, through serve and lines.
    var waiting: u32 = 0;
    for (paths) |rel| {
        if (!isRejectsPath(rel)) waiting += try waitingLoops(gpa, io, root, rel);
    }
    try std.testing.expectEqual(@as(u32, 0), waiting);

    // The error catalog page is what the diagnostic tables render (zig build errors).
    try std.testing.expect(try catalogCurrent(gpa, io));

    // Every program runs through the installed `mo run`, on Mo.Server, once per # run: line.
    const from_environ = std.testing.environ.getAlloc(gpa, "MO_EXE") catch null;
    defer if (from_environ) |e| gpa.free(e);
    const mo_exe = try moExe(gpa, io, from_environ);
    defer gpa.free(mo_exe);
    // A program is found, not named: every programs/<name>.mo and programs/<name>/main.mo.
    var programs: u32 = 0;
    var wrong: u32 = 0;
    for (paths) |rel| {
        if (!try isRunnable(io, root, rel)) continue;
        programs += 1;
        if (!try checkProgram(gpa, io, mo_exe, root, rel)) wrong += 1;
    }
    try std.testing.expect(programs > 0);
    try std.testing.expectEqual(@as(u32, 0), wrong);

    // Stages beyond `implemented` may still be stubs; those files count as skipped.
    // (the differential test of the C backend is the next test)
    var beyond: Tally = .{};
    if (pipeline.implemented != .run) {
        for (paths) |rel| try runOne(gpa, io, root, rel, .run, &beyond);
    }
    try std.testing.expectEqual(@as(u32, 0), beyond.failed);
}

test "corpus: every module's tests and every program, built by mo build, print what the interpreter prints" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const root = "../examples";
    const paths = collect(gpa, io, root) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer {
        for (paths) |p| gpa.free(p);
        gpa.free(paths);
    }
    const from_environ = std.testing.environ.getAlloc(gpa, "MO_EXE") catch null;
    defer if (from_environ) |e| gpa.free(e);
    const mo_exe = try moExe(gpa, io, from_environ);
    defer gpa.free(mo_exe);
    defer Io.Dir.cwd().deleteTree(io, root ++ "/zig-out") catch {};

    // Every module outside rejects/, its tests built with --tests beside mo test.
    var modules: Built = .{};
    var outside_rejects: u32 = 0;
    for (paths) |rel| {
        if (isRejectsPath(rel)) continue;
        outside_rejects += 1;
        try checkBuiltTests(gpa, io, mo_exe, root, rel, &modules);
    }
    // Every program, each # run: line beside mo run.
    var programs: Built = .{};
    for (paths) |rel| {
        if (try isRunnable(io, root, rel)) try checkBuiltProgram(gpa, io, mo_exe, root, rel, &programs);
    }
    try std.testing.expectEqual(@as(u32, 0), modules.wrong);
    try std.testing.expectEqual(@as(u32, 0), programs.wrong);
    try std.testing.expect(modules.same > 0 and programs.same > 0);
    // Every module was built and compared, the process and network modules among them.
    try std.testing.expectEqual(outside_rejects, modules.same);
}

test "corpus: mo run --surface and a binary built with --surface serve the runtime's rows over HTTP" {
    // programs/surface asks its own surface at the port it is given (step 23): its # run: line
    // finds nothing listening, and here the surface listens there, under mo run and as a binary.
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const folder = "../examples/programs/surface";
    Io.Dir.cwd().access(io, folder ++ "/main.mo", .{}) catch return;
    const from_environ = std.testing.environ.getAlloc(gpa, "MO_EXE") catch null;
    defer if (from_environ) |e| gpa.free(e);
    const mo_exe = try moExe(gpa, io, from_environ);
    defer gpa.free(mo_exe);
    const want =
        \\200, holds "name": "Tally"
        \\200, does not hold Surface
        \\200, holds Tally(votes: 2)
        \\200, holds "taking": "Vote"
        \\200, holds done
        \\409, holds Unparsed
        \\404, holds no row
        \\the tally holds 5
        \\
    ;
    // Two ports of their own, picked by the clock so a run does not meet the last one's, and
    // below every system's ephemeral range (Linux 32768-60999, macOS 49152-65535): a port an
    // earlier test's client connection took there sits in TIME_WAIT, and Linux refuses to bind a
    // listener over a TIME_WAIT socket that did not set SO_REUSEADDR itself (macOS allows it).
    const base: i64 = 21_000 + @mod(Io.Clock.real.now(io).toMilliseconds(), 2_000) * 2;
    const port = try std.fmt.allocPrint(arena, "{d}", .{base});
    const interp = try std.process.run(arena, io, .{ .argv = &.{ mo_exe, "run", "--surface", port, "main.mo", "--", port }, .cwd = .{ .path = folder } });
    try std.testing.expectEqualStrings(want, interp.stdout);
    try std.testing.expect(std.mem.indexOf(u8, interp.stderr, "runtime surface: http://127.0.0.1:") != null);

    defer Io.Dir.cwd().deleteTree(io, folder ++ "/zig-out") catch {};
    const built = try std.process.run(arena, io, .{ .argv = &.{ mo_exe, "build", "--surface", "main.mo", "-o", "surface-served" }, .cwd = .{ .path = folder } });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const binary = try std.fs.path.join(arena, &.{ try Io.Dir.cwd().realPathFileAlloc(io, folder, arena), "zig-out/mo-build/surface-served/surface-served" });
    const port2 = try std.fmt.allocPrint(arena, "{d}", .{base + 1});
    var environ: std.process.Environ.Map = .init(arena);
    try environ.put("MO_SURFACE", port2);
    const compiled = try std.process.run(arena, io, .{ .argv = &.{ binary, port2 }, .cwd = .{ .path = folder }, .environ_map = &environ });
    try std.testing.expectEqualStrings(want, compiled.stdout);
    try std.testing.expect(std.mem.indexOf(u8, compiled.stderr, "runtime surface: http://127.0.0.1:") != null);
}

test "corpus: a crash 200 updates back, past a ring of 64, is still in crashes under mo run and in a binary" {
    // processes/crash-kept.mo reads its own runtime (step 32): the crash reports are kept apart
    // from the ring, which the updates after the crash have turned over.
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const folder = "../examples/processes";
    Io.Dir.cwd().access(io, folder ++ "/crash-kept.mo", .{}) catch return;
    const from_environ = std.testing.environ.getAlloc(gpa, "MO_EXE") catch null;
    defer if (from_environ) |e| gpa.free(e);
    const mo_exe = try moExe(gpa, io, from_environ);
    defer gpa.free(mo_exe);
    const want =
        \\restarted at 0: true
        \\1 crash kept
        \\Counter crashed on Add(1000000): invariant "count stays below a million", state Counter(count: 3)
        \\0 crashes in the ring's last 64 events
        \\
    ;
    const interp = try std.process.run(arena, io, .{ .argv = &.{ mo_exe, "run", "--events", "64", "crash-kept.mo" }, .cwd = .{ .path = folder } });
    try std.testing.expectEqualStrings(want, interp.stdout);
    // --crashes 0 keeps none.
    const none = try std.process.run(arena, io, .{ .argv = &.{ mo_exe, "run", "--crashes", "0", "crash-kept.mo" }, .cwd = .{ .path = folder } });
    try std.testing.expect(std.mem.indexOf(u8, none.stdout, "0 crash kept\n") != null);

    defer Io.Dir.cwd().deleteTree(io, folder ++ "/zig-out") catch {};
    const built = try std.process.run(arena, io, .{ .argv = &.{ mo_exe, "build", "--surface", "crash-kept.mo", "-o", "crash-kept-served" }, .cwd = .{ .path = folder } });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const binary = try std.fs.path.join(arena, &.{ try Io.Dir.cwd().realPathFileAlloc(io, folder, arena), "zig-out/mo-build/crash-kept-served/crash-kept-served" });
    var environ: std.process.Environ.Map = .init(arena);
    try environ.put("MO_EVENTS", "64");
    const compiled = try std.process.run(arena, io, .{ .argv = &.{binary}, .cwd = .{ .path = folder }, .environ_map = &environ });
    try std.testing.expectEqualStrings(want, compiled.stdout);
    try environ.put("MO_CRASHES", "0");
    const kept_none = try std.process.run(arena, io, .{ .argv = &.{binary}, .cwd = .{ .path = folder }, .environ_map = &environ });
    try std.testing.expect(std.mem.indexOf(u8, kept_none.stdout, "0 crash kept\n") != null);
}

test "corpus: a process whose state is megabytes restarts twenty times and its reports do not stay, under mo run and in a binary" {
    // Step 33: each crash report rendered the state before the message and, for an invariant, the state
    // after it, and kept both for the run: 71 MiB over these twenty restarts under mo run, 113 MiB in a
    // binary. The reports go to stderr, about 90 MiB of them, which the test does not read.
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const from_environ = std.testing.environ.getAlloc(gpa, "MO_EXE") catch null;
    defer if (from_environ) |e| gpa.free(e);
    const mo_exe = try moExe(gpa, io, from_environ);
    defer gpa.free(mo_exe);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const leak =
        \\module Leak
        \\expose Holder, Holders, crash, main
        \\
        \\intent "A process whose state is megabytes crashes and restarts twenty times, and what its reports rendered does not stay."
        \\
        \\process Holder()
        \\  state
        \\    items: List(UInt64) = []
        \\  end
        \\
        \\  invariant "holds fewer than 200,000 items"
        \\    state.items.size < 200_000
        \\  end
        \\
        \\  message Grow(n: UInt64)
        \\  message Size : UInt64
        \\
        \\  fn update(state, message)
        \\    case message
        \\      Grow(n):
        \\        for i in 0..n
        \\          state.items = state.items.push(i + 1_000_000_000)
        \\        end
        \\      Size: state.items.size
        \\    end
        \\  end
        \\end
        \\
        \\supervisor Holders
        \\  child Holder, restart: :always, max_restarts: 1000 per 1.minute
        \\end
        \\
        \\# Crashes the holder `n` times, each with a large state before the message and after it.
        \\fn crash(holder: Handle(Holder), n: UInt64) : UInt64
        \\  var gone = 0
        \\  for _ in 0..n
        \\    holder.send(Grow(n: 100_000))
        \\    holder.send(Grow(n: 100_000))
        \\    # An ask the restart drops is Down; the next is answered by the restarted holder.
        \\    var empty = false
        \\    for _ in 0..3
        \\      if !empty and holder.ask(Size, within: 1.minute) is Ok(size) and size == 0
        \\        empty = true
        \\      end
        \\    end
        \\    if empty
        \\      gone += 1
        \\    end
        \\  end
        \\  gone
        \\end
        \\
        \\fn main(platform: Platform)
        \\  out = platform.stdout
        \\  case platform.runtime
        \\    Some(runtime):
        \\      holder = Holder.start()
        \\      warm = crash(holder, 5)
        \\      before = runtime.memory(within: 1.minute).resident_bytes
        \\      gone = crash(holder, 20)
        \\      after = runtime.memory(within: 1.minute).resident_bytes
        \\      mib = (after - before) / 1_048_576
        \\      out.write("25 restarts: #{warm + gone}; under 16 MiB more: #{after < before + 16 * 1_048_576} (#{mib} MiB)\n")
        \\      kept = runtime.crashes(1, within: 1.minute)
        \\      out.write("kept: #{kept.size}\n")
        \\    None: out.write("no runtime: build with --surface\n")
        \\  end
        \\end
        \\
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "leak.mo", .data = leak });
    const cwd = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    const quiet = "exec \"$0\" \"$@\" 2>/dev/null";
    const want = "25 restarts: 25; under 16 MiB more: true";
    const interp = try std.process.run(arena, io, .{ .argv = &.{ "/bin/sh", "-c", quiet, mo_exe, "run", "leak.mo" }, .cwd = .{ .path = cwd } });
    try std.testing.expect(std.mem.startsWith(u8, interp.stdout, want));
    try std.testing.expect(std.mem.endsWith(u8, interp.stdout, "kept: 1\n"));
    const built = try std.process.run(arena, io, .{ .argv = &.{ mo_exe, "build", "--surface", "leak.mo", "-o", "leak-served" }, .cwd = .{ .path = cwd } });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const compiled = try std.process.run(arena, io, .{ .argv = &.{ "/bin/sh", "-c", quiet, "./zig-out/mo-build/leak-served/leak-served" }, .cwd = .{ .path = cwd } });
    try std.testing.expect(std.mem.startsWith(u8, compiled.stdout, want));
    try std.testing.expect(std.mem.endsWith(u8, compiled.stdout, "kept: 1\n"));
}

test "corpus: a callee's body changed in another module makes its caller's verified: line stale" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const from_environ = std.testing.environ.getAlloc(gpa, "MO_EXE") catch null;
    defer if (from_environ) |e| gpa.free(e);
    const mo_exe = try moExe(gpa, io, from_environ);
    defer gpa.free(mo_exe);
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "app/lib");
    try tmp.dir.writeFile(io, .{ .sub_path = "app/mo.root", .data = "" });
    const callee = "module Lib.Double\nexpose double\n\nintent \"Double a number.\"\n\nfn double(n: UInt32) : UInt32\n  n * 2\nend\n\ntest \"two doubles to four\"\n  assert double(2) == 4\nend\n";
    try tmp.dir.writeFile(io, .{ .sub_path = "app/lib/double.mo", .data = callee });
    try tmp.dir.writeFile(io, .{ .sub_path = "app/caller.mo", .data = "module Caller\nexpose quadruple\n\nuse Lib.Double{double}\n\nintent \"Quadruple a number by doubling it twice.\"\n\nfn quadruple(n: UInt32) : UInt32\n  double(double(n))\nend\n\ntest \"one quadruples to four\"\n  assert quadruple(1) == 4\nend\n" });
    const cwd = try std.fmt.allocPrint(arena, ".zig-cache/tmp/{s}/app", .{tmp.sub_path});
    const Mo = struct {
        fn run(a: std.mem.Allocator, i: Io, exe: []const u8, dir: []const u8, args: []const []const u8) !std.process.RunResult {
            var argv: std.ArrayList([]const u8) = .empty;
            try argv.append(a, exe);
            try argv.appendSlice(a, args);
            return std.process.run(a, i, .{ .argv = argv.items, .cwd = .{ .path = dir } });
        }
        fn exited(r: std.process.RunResult) ?u8 {
            return if (r.term == .exited) r.term.exited else null;
        }
    };
    try std.testing.expectEqual(@as(?u8, 0), Mo.exited(try Mo.run(arena, io, mo_exe, cwd, &.{ "test", "--write", "lib/double.mo" })));
    try std.testing.expectEqual(@as(?u8, 0), Mo.exited(try Mo.run(arena, io, mo_exe, cwd, &.{ "test", "--write", "caller.mo" })));
    try std.testing.expectEqual(@as(?u8, 0), Mo.exited(try Mo.run(arena, io, mo_exe, cwd, &.{ "check", "caller.mo" })));

    // The callee's body changes and its own line is written again; the caller's tests ran
    // against the old body, so its line is stale.
    const edited = try std.mem.replaceOwned(u8, arena, try tmp.dir.readFileAlloc(io, "app/lib/double.mo", arena, .limited(1 << 16)), "  n * 2\n", "  n + n\n");
    try tmp.dir.writeFile(io, .{ .sub_path = "app/lib/double.mo", .data = edited });
    try std.testing.expectEqual(@as(?u8, 0), Mo.exited(try Mo.run(arena, io, mo_exe, cwd, &.{ "test", "--write", "lib/double.mo" })));
    const stale = try Mo.run(arena, io, mo_exe, cwd, &.{ "check", "caller.mo" });
    try std.testing.expectEqual(@as(?u8, 1), Mo.exited(stale));
    try std.testing.expect(std.mem.indexOf(u8, stale.stderr, "MO0317 Lib.Double, a module it uses, changed since mo test --write recorded the verified: line") != null);

    try std.testing.expectEqual(@as(?u8, 0), Mo.exited(try Mo.run(arena, io, mo_exe, cwd, &.{ "test", "--write", "caller.mo" })));
    try std.testing.expectEqual(@as(?u8, 0), Mo.exited(try Mo.run(arena, io, mo_exe, cwd, &.{ "check", "caller.mo" })));
}

test "a build is named so that it is never itself a .mo file" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    try std.testing.expectEqualStrings("programs_logstat_main", try buildKey(arena_state.allocator(), "programs/logstat/main.mo"));
    try std.testing.expectEqualStrings("basics_anonymous-functions", try buildKey(arena_state.allocator(), "basics/anonymous-functions.mo"));
}

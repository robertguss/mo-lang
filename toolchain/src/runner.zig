//! Runs `test`, `test rejects`, and `property` blocks of a module on the vm.
//! A `rejects` test passes only when it trips a `requires`, a refinement, or an `invariant`.
//! Property tests run under N seeds; results feed verified.zig. Every test runs on its
//! own Mo.Sim (sim.zig): a process it starts has the runner as its supervisor, and the
//! first crash, in a process or in the body, is the verdict.
//! Each test runs in its own arena, freed whole; a result keeps copies of what it shows.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const contracts = @import("contracts.zig");
const diag = @import("diag.zig");
const sim = @import("sim.zig");
const vm = @import("vm.zig");

pub const seeds_per_property: u32 = 200;
/// Seed i of every property is base_seed + i, so a reported seed reproduces the run.
pub const base_seed: u64 = 0x4d6f_0003;
/// Generated inputs tried under one seed before the guard counts it as discarded.
pub const attempts_per_seed: u32 = 100;

pub const Outcome = enum { passed, failed, tripped_as_expected, did_not_trip, skipped };

pub const Result = struct {
    kind: bytecode.TestKind,
    name: []const u8,
    at: u32,
    outcome: Outcome,
    /// What crashed, what a rejects test tripped, or why it was skipped.
    report: ?contracts.Report = null,
    /// A property: the seeds it ran under, and on failure the seed and what it generated.
    seeds: u32 = 0,
    seed: u64 = 0,
    generated: []const contracts.Involved = &.{},
    /// Why it failed when no report says.
    note: []const u8 = "",
    /// Processes the test started.
    processes: u32 = 0,
};

pub const Summary = struct {
    /// Test blocks of every kind that passed: the N in `tests (N)`.
    tests: u32 = 0,
    rejects: u32 = 0,
    properties: u32 = 0,
    /// The seeds each property ran under, once one has.
    seeds: u32 = 0,
    failures: u32 = 0,
    /// Tests that reached something this step does not run (a recipe signature with
    /// no body).
    skipped: u32 = 0,
    /// Processes started across every test.
    processes: u32 = 0,
};

pub const Run = struct { results: []const Result, summary: Summary };

pub const Error = error{OutOfMemory};

/// Runs every test of `program` in source order. What the results keep is allocated
/// with `gpa`.
pub fn run(gpa: std.mem.Allocator, program: *const bytecode.Program) Error!Run {
    var results: std.ArrayList(Result) = .empty;
    var summary: Summary = .{};
    for (program.tests) |t| {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        const r = if (t.kind == .property) try runProperty(gpa, arena, program, t) else try runTest(gpa, arena, program, t);
        switch (r.outcome) {
            .passed, .tripped_as_expected => {
                summary.tests += 1;
                if (t.kind == .rejects) summary.rejects += 1;
                if (t.kind == .property) {
                    summary.properties += 1;
                    summary.seeds = seeds_per_property;
                }
            },
            .failed, .did_not_trip => summary.failures += 1,
            .skipped => summary.skipped += 1,
        }
        summary.processes += r.processes;
        try results.append(gpa, r);
    }
    return .{ .results = results.items, .summary = summary };
}

fn runTest(gpa: std.mem.Allocator, arena: std.mem.Allocator, program: *const bytecode.Program, t: bytecode.Test) Error!Result {
    var machine: vm.Vm = .init(arena, program, base_seed);
    var simulator: sim.Sim = .init(&machine, base_seed, t.name);
    machine.sim = &simulator;
    var r: Result = .{ .kind = t.kind, .name = t.name, .at = t.at, .outcome = .passed };
    const ran = machine.call(t.function, &.{});
    r.processes = @intCast(simulator.procs.items.len);
    if (ran) |_| {
        if (simulator.firstCrash()) |report| {
            try verdict(gpa, &r, report);
        } else if (t.kind == .rejects) {
            r.outcome = .did_not_trip;
            r.note = "the body ran to its end without tripping a requires, a refinement, or an invariant";
        }
    } else |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Skip => {
            r.outcome = .skipped;
            r.report = try keep(gpa, machine.report.?);
        },
        error.Crash => try verdict(gpa, &r, crashOf(&machine, &simulator)),
        error.Discard => unreachable,
    }
    return r;
}

/// What stopped a run: a supervisor that gave up, else the first crash in a process,
/// else the body's own.
fn crashOf(machine: *const vm.Vm, simulator: *const sim.Sim) contracts.Report {
    if (simulator.gave_up) return machine.report.?;
    return simulator.firstCrash() orelse machine.report.?;
}

fn verdict(gpa: std.mem.Allocator, r: *Result, report: contracts.Report) Error!void {
    r.report = try keep(gpa, report);
    r.outcome = if (r.kind == .rejects and report.tripsRejects()) .tripped_as_expected else .failed;
}

/// One attempt per seed that gets past the guard; the first crash is the verdict.
fn runProperty(gpa: std.mem.Allocator, arena: std.mem.Allocator, program: *const bytecode.Program, t: bytecode.Test) Error!Result {
    var r: Result = .{ .kind = t.kind, .name = t.name, .at = t.at, .outcome = .passed, .seeds = seeds_per_property };
    var held: u32 = 0;
    for (0..seeds_per_property) |i| {
        const seed = base_seed + i;
        var machine: vm.Vm = .init(arena, program, seed);
        var attempt: u32 = 0;
        while (attempt < attempts_per_seed) : (attempt += 1) {
            machine.stack.clearRetainingCapacity();
            machine.generated.clearRetainingCapacity();
            var simulator: sim.Sim = .init(&machine, seed, t.name);
            machine.sim = &simulator;
            const ran = machine.call(t.function, &.{});
            r.processes = @max(r.processes, @as(u32, @intCast(simulator.procs.items.len)));
            const crash: ?contracts.Report = if (ran) |_| simulator.firstCrash() else |err| switch (err) {
                error.Crash => crashOf(&machine, &simulator),
                else => null,
            };
            if (crash) |report| {
                r.outcome = .failed;
                r.report = try keep(gpa, report);
                r.seed = seed;
                const generated = try gpa.alloc(contracts.Involved, machine.generated.items.len);
                for (machine.generated.items, generated) |g, *o| {
                    o.* = .{ .name = try gpa.dupe(u8, g.name), .value = try gpa.dupe(u8, machine.render(g.value) catch return error.OutOfMemory) };
                }
                r.generated = generated;
                return r;
            }
            if (ran) |_| {
                held += 1;
                break;
            } else |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Discard => continue,
                error.Skip => {
                    r.outcome = .skipped;
                    r.report = try keep(gpa, machine.report.?);
                    return r;
                },
                error.Crash => unreachable,
            }
        }
    }
    if (held == 0) {
        r.outcome = .failed;
        r.note = "the guard held for no generated value under any seed";
    }
    return r;
}

/// A copy of a report that outlives the test's arena.
fn keep(gpa: std.mem.Allocator, r: contracts.Report) Error!contracts.Report {
    const values = try gpa.alloc(contracts.Involved, r.values.len);
    for (r.values, values) |v, *o| o.* = .{ .name = try gpa.dupe(u8, v.name), .value = try gpa.dupe(u8, v.value) };
    const process: ?contracts.ProcessCrash = if (r.process) |p| blk: {
        const log = try gpa.alloc([]const u8, p.log.len);
        for (p.log, log) |m, *o| o.* = try gpa.dupe(u8, m);
        break :blk .{ .process = try gpa.dupe(u8, p.process), .seed = p.seed, .log = log, .state = try gpa.dupe(u8, p.state) };
    } else null;
    return .{ .kind = r.kind, .clause = try gpa.dupe(u8, r.clause), .within = try gpa.dupe(u8, r.within), .at = r.at, .values = values, .process = process };
}

/// One line per test: `pass`, `skip`, or `FAIL`, the test, and what happened.
pub fn writeResult(w: *std.Io.Writer, files: []const diag.File, r: Result) std.Io.Writer.Error!void {
    const tag = switch (r.outcome) {
        .passed, .tripped_as_expected => "pass",
        .skipped => "skip",
        .failed, .did_not_trip => "FAIL",
    };
    const kind = switch (r.kind) {
        .test_ => "test",
        .rejects => "test rejects",
        .property => "property",
    };
    try w.print("{s}  {s} \"{s}\"", .{ tag, kind, r.name });
    switch (r.outcome) {
        .passed => if (r.kind == .property) try w.print(": {d} seeds", .{r.seeds}),
        .tripped_as_expected => try w.print(": tripped {s}", .{r.report.?.clause}),
        .skipped => try w.print(": {s}", .{r.report.?.clause}),
        .failed, .did_not_trip => {
            try w.writeAll(": ");
            if (r.kind == .property and r.report != null) {
                try w.print("seed {d}", .{r.seed});
                for (r.generated, 0..) |g, i| try w.print("{s}{s} = {s}", .{ if (i == 0) " with " else ", ", g.name, g.value });
                try w.writeAll(": ");
            }
            if (r.report) |report| try writeReport(w, files, report) else try w.writeAll(r.note);
        },
    }
    try w.writeAll("\n");
}

/// A crash as prose: where, what tripped, and the values involved. A crash inside a
/// process goes on with chapter 3's report: the seed, every message since the process
/// started, and its state before the last one.
pub fn writeReport(w: *std.Io.Writer, files: []const diag.File, r: contracts.Report) std.Io.Writer.Error!void {
    if (r.at != 0) {
        const loc = diag.locate(files, r.at);
        const pos = diag.position(loc.source, loc.at);
        try w.print("{s}:{d}:{d}: ", .{ loc.path, pos.line, pos.column });
    }
    switch (r.kind) {
        .assert => try w.print("{s} failed", .{r.clause}),
        .requires, .ensures, .refinement, .invariant => try w.print("{s} tripped in {s}", .{ r.clause, r.within }),
        .overflow => try w.print("overflow in {s}", .{r.clause}),
        .divide_by_zero => try w.print("division by zero in {s}", .{r.clause}),
        .mailbox, .supervisor, .other => try w.print("{s}", .{r.clause}),
    }
    for (r.values, 0..) |v, i| try w.print("{s}{s} = {s}", .{ if (i == 0) "; " else ", ", v.name, v.value });
    if (r.process) |p| {
        try w.print("\n      in process {s}, seed {d}\n      messages since it started: ", .{ p.process, p.seed });
        for (p.log, 0..) |m, i| try w.print("{s}{s}", .{ if (i == 0) "" else ", ", m });
        try w.print("\n      state before the last message: {s}", .{p.state});
    }
}

pub fn writeSummary(w: *std.Io.Writer, s: Summary) std.Io.Writer.Error!void {
    try w.print("{d} passed, {d} failed, {d} skipped\n", .{ s.tests, s.failures, s.skipped });
}

// ---- tests

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const check = @import("check.zig");
const caps = @import("caps.zig");

fn runSource(arena: std.mem.Allocator, src: []const u8) !Run {
    var diags: diag.List = .empty;
    const tokens = try lexer.lex(arena, src, &diags);
    const tree = try parser.parse(arena, src, tokens, &diags);
    const checked = try check.check(arena, tree, &diags);
    try caps.check(arena, checked, &diags);
    for (diags.items) |d| std.debug.print("{s} at {d}: {s}\n", .{ d.code, d.at, d.what });
    try std.testing.expectEqual(@as(usize, 0), diags.items.len);
    const program = try arena.create(bytecode.Program);
    program.* = try bytecode.lower(arena, checked);
    return run(arena, program);
}

test "a test passes, a rejects test trips, a property holds, and each failure is reported" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const r = try runSource(arena,
        \\module T.Run
        \\fn take(stock: UInt32, n: UInt32) : UInt32
        \\  requires n <= stock
        \\
        \\  stock - n
        \\end
        \\test "takes"
        \\  assert take(5, 2) == 3
        \\end
        \\test "wrong"
        \\  assert take(5, 2) == 4
        \\end
        \\test rejects "too many"
        \\  take(5, 6)
        \\end
        \\test rejects "not too many"
        \\  take(5, 5)
        \\end
        \\property "taking all leaves nothing"
        \\  for n in any(UInt32)
        \\    assert take(n, n) == 0
        \\  end
        \\end
        \\property "taking one leaves less"
        \\  for n in any(UInt32)
        \\    assert take(n, 1) < n
        \\  end
        \\end
    );
    try std.testing.expectEqual(Outcome.passed, r.results[0].outcome);
    try std.testing.expectEqual(Outcome.failed, r.results[1].outcome);
    try std.testing.expectEqualStrings("4", r.results[1].report.?.values[1].value);
    try std.testing.expectEqual(Outcome.tripped_as_expected, r.results[2].outcome);
    try std.testing.expectEqual(Outcome.did_not_trip, r.results[3].outcome);
    try std.testing.expectEqual(Outcome.passed, r.results[4].outcome);
    // take(0, 1) trips the requires: a property failure names the seed and the value.
    try std.testing.expectEqual(Outcome.failed, r.results[5].outcome);
    try std.testing.expectEqual(contracts.Kind.requires, r.results[5].report.?.kind);
    try std.testing.expectEqualStrings("n", r.results[5].generated[0].name);
    try std.testing.expectEqual(Summary{ .tests = 3, .rejects = 1, .properties = 1, .seeds = 200, .failures = 3 }, r.summary);
}

test "mo test prints a process crash with its seed, message log, and state before the message" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const src =
        \\module T.Report
        \\process Meter()
        \\  state
        \\    n: UInt8
        \\  end
        \\  message Add(k: UInt8)
        \\  fn update(state, message)
        \\    case message
        \\      Add(k):
        \\        state.n += k
        \\    end
        \\  end
        \\end
        \\supervisor Meters
        \\  child Meter, restart: :always
        \\end
        \\test "too much"
        \\  meter = Meter.start()
        \\  meter.send(Add(k: 200))
        \\  meter.send(Add(k: 100))
        \\end
    ;
    const r = try runSource(arena, src);
    try std.testing.expectEqual(Outcome.failed, r.results[0].outcome);
    var buf: [1024]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writeResult(&w, &.{.{ .path = "report.mo", .source = src }}, r.results[0]);
    try std.testing.expectEqualStrings(
        \\FAIL  test "too much": report.mo:10:9: overflow in state.n += k; left = 200, right = 100
        \\      in process Meter, seed 1299120131
        \\      messages since it started: Add(200), Add(100)
        \\      state before the last message: Meter(n: 200)
        \\
    , w.buffered());
}

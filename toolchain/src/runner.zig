//! Runs `test`, `test rejects`, and `property` blocks of a module on the vm.
//! A `rejects` test passes only when it trips a `requires`, a refinement, an `invariant`,
//! or a `never`. Every never is checked when a test's body ends and when a property's
//! attempt ends, in the fixed order and under seeds alike (sim.zig, checkNevers).
//! Property tests run under N seeds; results feed verified.zig. Every test runs on its
//! own Mo.Sim (sim.zig): a process it starts has the runner as its supervisor, and the
//! first crash, in a process or in the body, is the verdict.
//! With `--sim N` (tier 3), a test that starts a process and holds in the fixed order
//! runs N more times, each on a seeded Mo.Sim with faults, and must hold under every
//! seed. A seed it fails under with faults runs again without them: a failure there too is
//! a race, and a pass means the test holds only in a world where nothing fails, which is
//! reported as a design smell rather than a failure.
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
/// `--sim` without a count.
pub const default_sim_runs: u32 = 100;
/// `--sim` without `--faults`: the percent chance a fixture call fails in a seeded run.
pub const default_fault_percent: u32 = 5;

pub const Options = struct {
    /// Seeded runs of each test that starts a process; 0 runs the fixed order alone.
    sim_runs: u32 = 0,
    /// Seeded run i runs under sim_seed + i, so `--sim 1 --seed S` repeats the run of seed S.
    sim_seed: u64 = 0,
    fault_percent: u32 = default_fault_percent,
};

/// The base seed when none is given: the file's hash, so a file runs under the same
/// seeds until it changes.
/// The file's hash without its `verified:` line and the blank line above it, so writing
/// the line never changes the seeds the line reports.
pub fn seedOf(source: []const u8) u64 {
    var end = source.len;
    if (std.mem.startsWith(u8, source, "verified:")) end = 0;
    if (std.mem.lastIndexOf(u8, source, "\nverified:")) |i| end = i + 1;
    if (end < source.len and std.mem.endsWith(u8, source[0..end], "\n\n")) end -= 1;
    return std.hash.Wyhash.hash(0, source[0..end]);
}

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
    /// Seeded runs made: every one it held under, or up to the one it failed.
    sim_runs: u32 = 0,
    /// The seed of the seeded run that failed, and that run's messages in order.
    sim_seed: ?u64 = null,
    interleaving: []const []const u8 = &.{},
    /// The fault percent the seed named in the result ran with.
    sim_faults: u32 = 0,
    /// Faults the run injected.
    faults: u32 = 0,
    /// A test that held under every seed once faults were taken away: the first seed it
    /// failed under with them, and what failed.
    fault_seed: ?u64 = null,
    fault_report: ?contracts.Report = null,
    fault_note: []const u8 = "",
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
    /// The N of `--sim N` and its fault percent, once a test has run under it, and the
    /// tests that did.
    sim_runs: u32 = 0,
    sim_faults: u32 = 0,
    simulated: u32 = 0,
    /// Simulated tests that held under faults, and those that passed only without them.
    held_under_faults: u32 = 0,
    fault_free_only: u32 = 0,
};

pub const Run = struct { results: []const Result, summary: Summary };

pub const Error = error{OutOfMemory};

/// Runs every test of `program` in source order. What the results keep is allocated
/// with `gpa`.
pub fn run(gpa: std.mem.Allocator, program: *const bytecode.Program, options: Options) Error!Run {
    var results: std.ArrayList(Result) = .empty;
    var summary: Summary = .{};
    for (program.tests) |t| {
        var arena_state = std.heap.ArenaAllocator.init(gpa);
        defer arena_state.deinit();
        const arena = arena_state.allocator();
        var r = if (t.kind == .property) try runProperty(gpa, arena, program, t) else try runTest(gpa, arena, program, t, null, 0);
        // A property already runs under its own seeds.
        if (options.sim_runs > 0 and t.kind != .property and r.processes > 0 and holds(r)) try simulate(gpa, &arena_state, program, t, options, &r);
        if (r.sim_runs > 0) {
            summary.simulated += 1;
            summary.sim_runs = options.sim_runs;
            summary.sim_faults = options.fault_percent;
            if (holds(r) and r.fault_seed != null) {
                summary.fault_free_only += 1;
            } else if (holds(r) and options.fault_percent > 0) summary.held_under_faults += 1;
        }
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

fn holds(r: Result) bool {
    return r.outcome == .passed or r.outcome == .tripped_as_expected;
}

/// `--sim N`: the test runs under seeds sim_seed to sim_seed + N - 1, and the first it
/// fails under is its verdict. A failure in a run that injected a fault runs the seed again
/// without faults, on the same schedule: if that fails too it is the verdict; if it holds,
/// the test passes only without faults, and the seeds go on.
fn simulate(gpa: std.mem.Allocator, arena_state: *std.heap.ArenaAllocator, program: *const bytecode.Program, t: bytecode.Test, options: Options, r: *Result) Error!void {
    for (0..options.sim_runs) |i| {
        _ = arena_state.reset(.retain_capacity);
        const seed = options.sim_seed +% i;
        var s = try runTest(gpa, arena_state.allocator(), program, t, seed, options.fault_percent);
        s.sim_faults = options.fault_percent;
        if (holds(s)) continue;
        if (s.faults > 0) {
            _ = arena_state.reset(.retain_capacity);
            const quiet = try runTest(gpa, arena_state.allocator(), program, t, seed, 0);
            if (holds(quiet)) {
                if (r.fault_seed == null) {
                    r.fault_seed = seed;
                    r.sim_faults = options.fault_percent;
                    r.fault_report = s.report;
                    r.fault_note = s.note;
                }
                continue;
            }
            s = quiet;
        }
        s.sim_runs = @intCast(i + 1);
        s.sim_seed = seed;
        r.* = s;
        return;
    }
    r.sim_runs = options.sim_runs;
}

/// One run of a test: in the fixed order, or on a Mo.Sim seeded with `seed` whose
/// fixtures fail at `fault_percent`.
fn runTest(gpa: std.mem.Allocator, arena: std.mem.Allocator, program: *const bytecode.Program, t: bytecode.Test, seed: ?u64, fault_percent: u32) Error!Result {
    var machine: vm.Vm = .init(arena, program, seed orelse base_seed);
    var simulator: sim.Sim = if (seed) |s| .seeded(&machine, s, t.name, fault_percent) else .init(&machine, base_seed, t.name);
    machine.sim = &simulator;
    simulator.records = program.nevers.len > 0;
    var r: Result = .{ .kind = t.kind, .name = t.name, .at = t.at, .outcome = .passed };
    const ran = body(&machine, &simulator, t.function);
    r.processes = @intCast(simulator.procs.items.len);
    r.faults = simulator.injected;
    if (ran) |_| {
        if (simulator.firstCrash()) |report| {
            try verdict(gpa, &r, report);
        } else if (t.kind == .rejects) {
            r.outcome = .did_not_trip;
            r.note = "the body ran to its end without tripping a requires, a refinement, an invariant, or a never";
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
    if (seed != null and !holds(r)) r.interleaving = try interleaving(gpa, &machine, &simulator);
    return r;
}

/// The body, then every message still waiting, then every never.
fn body(machine: *vm.Vm, simulator: *sim.Sim, function: u32) vm.Error!void {
    _ = try machine.call(function, &.{});
    try simulator.finish();
}

/// One attempt of a property, then every never over what the attempt held. An attempt
/// its guard discards ends before the nevers.
fn propertyAttempt(machine: *vm.Vm, simulator: *sim.Sim, function: u32) vm.Error!void {
    _ = try machine.call(function, &.{});
    try simulator.checkNevers();
}

/// A seeded run's messages, oldest first: `the test sent Go to Writer #1`, `Writer #1 took
/// Go`. The same step again and again is one line: `... to Journal #0 100 times`.
fn interleaving(gpa: std.mem.Allocator, machine: *vm.Vm, simulator: *const sim.Sim) Error![]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    var repeats: u32 = 1;
    for (simulator.trace.items) |step| {
        const message = machine.render(step.message) catch return error.OutOfMemory;
        const to = simulator.nameOf(step.to);
        const line = if (step.took)
            try std.fmt.allocPrint(gpa, "{s} #{d} took {s}", .{ to, step.to, message })
        else if (step.from == sim.test_runner)
            try std.fmt.allocPrint(gpa, "the test sent {s} to {s} #{d}", .{ message, to, step.to })
        else
            try std.fmt.allocPrint(gpa, "{s} #{d} sent {s} to {s} #{d}", .{ simulator.nameOf(step.from), step.from, message, to, step.to });
        if (out.items.len > 0 and std.mem.eql(u8, out.items[out.items.len - 1], line)) {
            repeats += 1;
            continue;
        }
        try endRepeats(gpa, &out, repeats);
        repeats = 1;
        try out.append(gpa, line);
    }
    try endRepeats(gpa, &out, repeats);
    return out.items;
}

fn endRepeats(gpa: std.mem.Allocator, out: *std.ArrayList([]const u8), repeats: u32) Error!void {
    if (repeats == 1) return;
    const last = &out.items[out.items.len - 1];
    last.* = try std.fmt.allocPrint(gpa, "{s} {d} times", .{ last.*, repeats });
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
            simulator.records = program.nevers.len > 0;
            const ran = propertyAttempt(&machine, &simulator, t.function);
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
        .passed => if (r.kind == .property) {
            try w.print(": {d} seeds", .{r.seeds});
        } else if (r.sim_runs > 0) {
            try w.print(": {d} simulated runs", .{r.sim_runs});
            try writeFaultFreeOnly(w, files, r);
        },
        .tripped_as_expected => {
            try w.print(": tripped {s}", .{r.report.?.clause});
            if (r.sim_runs > 0) try w.print(" ({d} simulated runs)", .{r.sim_runs});
            try writeFaultFreeOnly(w, files, r);
        },
        .skipped => try w.print(": {s}", .{r.report.?.clause}),
        .failed, .did_not_trip => {
            try w.writeAll(": ");
            if (r.sim_seed) |seed| try w.print("simulated run {d}, seed {d}: ", .{ r.sim_runs, seed });
            if (r.kind == .property and r.report != null) {
                try w.print("seed {d}", .{r.seed});
                for (r.generated, 0..) |g, i| try w.print("{s}{s} = {s}", .{ if (i == 0) " with " else ", ", g.name, g.value });
                try w.writeAll(": ");
            }
            if (r.report) |report| try writeReport(w, files, report) else try w.writeAll(r.note);
            if (r.sim_seed) |seed| {
                try w.writeAll("\n      interleaving: ");
                if (r.interleaving.len == 0) try w.writeAll("no message delivered");
                for (r.interleaving, 0..) |m, i| try w.print("{s}{s}", .{ if (i == 0) "" else ", ", m });
                try writeReplay(w, seed, r.sim_faults);
            }
        },
    }
    try w.writeAll("\n");
}

/// A test that held under every seed only once faults were taken away: a design smell,
/// shown with the first seed it failed under and what failed.
fn writeFaultFreeOnly(w: *std.Io.Writer, files: []const diag.File, r: Result) std.Io.Writer.Error!void {
    const seed = r.fault_seed orelse return;
    try w.print(", but passes only without faults\n      seed {d}, with faults: ", .{seed});
    if (r.fault_report) |report| try writeReport(w, files, report) else try w.writeAll(r.fault_note);
    try writeReplay(w, seed, r.sim_faults);
}

fn writeReplay(w: *std.Io.Writer, seed: u64, fault_percent: u32) std.Io.Writer.Error!void {
    try w.print("\n      mo test --sim 1 --seed {d}", .{seed});
    if (fault_percent != default_fault_percent) try w.print(" --faults {d}", .{fault_percent});
    try w.writeAll(" runs it again");
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
        .requires, .ensures, .refinement => try w.print("{s} tripped in {s}", .{ r.clause, r.within }),
        .invariant => try w.print("{s} no longer holds in {s}", .{ r.clause, r.within }),
        .never => try w.print("{s} tripped", .{r.clause}),
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
    try w.print("{d} passed, {d} failed, {d} skipped", .{ s.tests, s.failures, s.skipped });
    if (s.sim_runs > 0) {
        try w.print("; {d} {s} under {d} {s}", .{ s.simulated, if (s.simulated == 1) "test" else "tests", s.sim_runs, if (s.sim_runs == 1) "seed" else "seeds" });
        if (s.sim_faults == 0) {
            try w.writeAll(" without faults");
        } else {
            try w.print(" with {d}% faults: {d} held under faults, {d} passed only without faults", .{ s.sim_faults, s.held_under_faults, s.fault_free_only });
        }
    }
    try w.writeAll("\n");
}

// ---- tests

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const check = @import("check.zig");
const caps = @import("caps.zig");

fn runSource(arena: std.mem.Allocator, src: []const u8) !Run {
    return run(arena, try compileSource(arena, src), .{});
}

fn compileSource(arena: std.mem.Allocator, src: []const u8) !*bytecode.Program {
    var diags: diag.List = .empty;
    const tokens = try lexer.lex(arena, src, &diags);
    const tree = try parser.parse(arena, src, tokens, &diags);
    const checked = try check.check(arena, tree, &diags);
    try caps.check(arena, checked, &diags);
    for (diags.items) |d| std.debug.print("{s} at {d}: {s}\n", .{ d.code, d.at, d.what });
    try std.testing.expectEqual(@as(usize, 0), diags.items.len);
    const program = try arena.create(bytecode.Program);
    program.* = try bytecode.lower(arena, checked);
    return program;
}

const race_src =
    \\module T.Race
    \\process Log()
    \\  state
    \\    first: String
    \\  end
    \\  message Add(name: String)
    \\  message First : String
    \\  fn update(state, message)
    \\    case message
    \\      Add(name):
    \\        if state.first == ""
    \\          state.first = name
    \\        end
    \\      First: state.first
    \\    end
    \\  end
    \\end
    \\process Writer(log: Handle(Log))
    \\  state
    \\    sent: UInt32
    \\  end
    \\  message Go(name: String)
    \\  fn update(state, message)
    \\    case message
    \\      Go(name):
    \\        log.send(Add(name: name))
    \\        state.sent += 1
    \\    end
    \\  end
    \\end
    \\supervisor Logs(log: Handle(Log))
    \\  child Log, restart: :always
    \\  child Writer(log), restart: :always
    \\end
    \\test "the writer told first is logged first"
    \\  log = Log.start()
    \\  a = Writer.start(log)
    \\  b = Writer.start(log)
    \\  a.send(Go(name: "a"))
    \\  b.send(Go(name: "b"))
    \\  assert log.ask(First, within: 100.ms) is Ok("a")
    \\end
;

test "a race holds in the fixed order and fails under --sim, with a seed that runs it again" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compileSource(arena, race_src);
    const fixed = try run(arena, program, .{});
    try std.testing.expectEqual(Outcome.passed, fixed.results[0].outcome);
    try std.testing.expectEqual(@as(u32, 0), fixed.summary.sim_runs);

    const simulated = try run(arena, program, .{ .sim_runs = 100, .sim_seed = seedOf(race_src) });
    const r = simulated.results[0];
    try std.testing.expectEqual(Outcome.failed, r.outcome);
    try std.testing.expectEqual(contracts.Kind.assert, r.report.?.kind);
    try std.testing.expectEqual(@as(u32, 1), simulated.summary.failures);
    try std.testing.expectEqual(Summary{ .failures = 1, .processes = 3, .sim_runs = 100, .sim_faults = 5, .simulated = 1 }, simulated.summary);
    // Nothing in it can fail, so no fault was drawn and the failure is the race itself.
    try std.testing.expectEqual(@as(u32, 0), r.faults);
    const seed = r.sim_seed.?;

    // The failing seed, run alone, fails the same way with the same interleaving.
    const again = (try run(arena, program, .{ .sim_runs = 1, .sim_seed = seed })).results[0];
    try std.testing.expectEqual(seed, again.sim_seed.?);
    try std.testing.expectEqual(r.interleaving.len, again.interleaving.len);
    for (r.interleaving, again.interleaving) |x, y| try std.testing.expectEqualStrings(x, y);

    var buf: [2048]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writeResult(&w, &.{.{ .path = "race.mo", .source = race_src }}, again);
    const text = w.buffered();
    try std.testing.expect(std.mem.startsWith(u8, text, "FAIL  test \"the writer told first is logged first\": simulated run 1, seed "));
    try std.testing.expect(std.mem.indexOf(u8, text, "\n      interleaving: ") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "\n      mo test --sim 1 --seed ") != null);
}

test "sends a seed leaves waiting fill a mailbox the fixed order empties, and repeats print once" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compileSource(arena,
        \\module T.Bound
        \\process Journal() mailbox: 3
        \\  state
        \\    lines: UInt32
        \\  end
        \\  message Write
        \\  message Count : UInt32
        \\  fn update(state, message)
        \\    case message
        \\      Write:
        \\        state.lines += 1
        \\      Count: state.lines
        \\    end
        \\  end
        \\end
        \\supervisor Journals
        \\  child Journal, restart: :always
        \\end
        \\test "three writes, then an ask"
        \\  journal = Journal.start()
        \\  for _ in 0..3
        \\    journal.send(Write)
        \\  end
        \\  assert journal.ask(Count, within: 100.ms) is Ok(3)
        \\end
    );
    try std.testing.expectEqual(Outcome.passed, (try run(arena, program, .{})).results[0].outcome);
    const r = (try run(arena, program, .{ .sim_runs = 100, .sim_seed = 5 })).results[0];
    try std.testing.expectEqual(Outcome.failed, r.outcome);
    try std.testing.expectEqual(contracts.Kind.mailbox, r.report.?.kind);
    // The ask's own message never got in.
    try std.testing.expectEqual(@as(usize, 1), r.interleaving.len);
    try std.testing.expectEqualStrings("the test sent Write to Journal #0 3 times", r.interleaving[0]);
}

test "a never over T.all is checked when every test ends, in the fixed order as under --sim" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const src =
        \\module T.Never
        \\never "a seat holds two bookings"
        \\  for a in Booking.all, b in Booking.all if a.seat == b.seat
        \\    a.guest != b.guest
        \\  end
        \\end
        \\struct Booking
        \\  seat: String
        \\  guest: String
        \\end
        \\process Desk()
        \\  state
        \\    held: List(Booking)
        \\  end
        \\  message Book(booking: Booking)
        \\  message Held : UInt64
        \\  fn update(state, message)
        \\    case message
        \\      Book(booking):
        \\        state.held = state.held.push(booking)
        \\      Held: state.held.size
        \\    end
        \\  end
        \\end
        \\supervisor Desks
        \\  child Desk, restart: :always
        \\end
        \\test "two guests book one seat"
        \\  desk = Desk.start()
        \\  desk.send(Book(booking: Booking(seat: "12A", guest: "Ada")))
        \\  desk.send(Book(booking: Booking(seat: "12A", guest: "Bob")))
        \\  assert desk.ask(Held, within: 100.ms) is Ok(2)
        \\end
        \\test "two guests book two seats"
        \\  desk = Desk.start()
        \\  desk.send(Book(booking: Booking(seat: "12A", guest: "Ada")))
        \\  desk.send(Book(booking: Booking(seat: "12B", guest: "Bob")))
        \\  assert desk.ask(Held, within: 100.ms) is Ok(2)
        \\end
    ;
    const program = try compileSource(arena, src);
    try std.testing.expectEqual(@as(usize, 1), program.nevers.len);
    const fixed = try run(arena, program, .{});
    const tripped = fixed.results[0];
    try std.testing.expectEqual(Outcome.failed, tripped.outcome);
    try std.testing.expectEqual(contracts.Kind.never, tripped.report.?.kind);
    try std.testing.expectEqual(Outcome.passed, fixed.results[1].outcome);

    // Under --sim the fixed-order run already fails; a test that holds there checks its
    // nevers under every seed as well.
    const r = try run(arena, program, .{ .sim_runs = 3, .sim_seed = 9 });
    try std.testing.expectEqual(Outcome.failed, r.results[0].outcome);
    try std.testing.expect(r.results[0].sim_seed == null);
    try std.testing.expectEqual(Outcome.passed, r.results[1].outcome);
    try std.testing.expectEqual(@as(u32, 3), r.results[1].sim_runs);

    var buf: [2048]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writeResult(&w, &.{.{ .path = "never.mo", .source = src }}, tripped);
    try std.testing.expectEqualStrings("FAIL  test \"two guests book one seat\": never.mo:2:1: never \"a seat holds two bookings\" tripped; a = Booking(seat: \"12A\", guest: \"Ada\"), b = Booking(seat: \"12A\", guest: \"Bob\")\n", w.buffered());
}

test "every never is checked at the end of every test, test rejects, and property, over enums and primitives the run held" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const program = try compileSource(arena,
        \\module T.Held
        \\never "a level is past its cap"
        \\  for n in UInt8.all
        \\    n > 200
        \\  end
        \\end
        \\never "a light is red"
        \\  for light in Light.all
        \\    light is Red
        \\  end
        \\end
        \\enum Light
        \\  Green
        \\  Red
        \\end
        \\fn next(n: UInt8) : UInt8
        \\  n + 1
        \\end
        \\test "one step, under a green light"
        \\  light = Green
        \\  assert light is Green
        \\  assert next(1) == 2
        \\end
        \\test rejects "a level raised past the cap"
        \\  var level = next(1)
        \\  level += 240
        \\  assert level == 242
        \\end
        \\test rejects "a red light"
        \\  light = Red
        \\  assert light is Red
        \\end
        \\property "small steps hold"
        \\  for n in any(UInt8) if n < 100
        \\    assert next(n) > n
        \\  end
        \\end
        \\property "a step from past the cap"
        \\  for n in any(UInt8) if n > 220 and n < 250
        \\    assert next(n) > n
        \\  end
        \\end
    );
    const r = try run(arena, program, .{});
    try std.testing.expectEqual(Outcome.passed, r.results[0].outcome);
    for (r.results[1..3]) |t| {
        try std.testing.expectEqual(Outcome.tripped_as_expected, t.outcome);
        try std.testing.expectEqual(contracts.Kind.never, t.report.?.kind);
    }
    try std.testing.expectEqualStrings("never \"a level is past its cap\"", r.results[1].report.?.clause);
    try std.testing.expectEqualStrings("never \"a light is red\"", r.results[2].report.?.clause);
    try std.testing.expectEqual(Outcome.passed, r.results[3].outcome);
    try std.testing.expectEqual(Outcome.failed, r.results[4].outcome);
    try std.testing.expectEqual(contracts.Kind.never, r.results[4].report.?.kind);
}

test "any(T) of a refined type gives only what the refinement admits, from its bounds when few pass, else MO0325" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const r = try runSource(arena,
        \\module T.Refined
        \\type Code = UInt16 where value >= 100 and value <= 599
        \\type Odd = UInt32 where value % 1_000_000 == 7
        \\struct Row
        \\  code: Code
        \\end
        \\property "a code and a row's code are in range"
        \\  for code in any(Code), row in any(Row)
        \\    assert code >= 100 and code <= 599
        \\    assert row.code >= 100 and row.code <= 599
        \\  end
        \\end
        \\property "an odd one"
        \\  for x in any(Odd)
        \\    assert x % 1_000_000 == 7
        \\  end
        \\end
    );
    try std.testing.expectEqual(Outcome.passed, r.results[0].outcome);
    try std.testing.expectEqual(Outcome.failed, r.results[1].outcome);
    try std.testing.expect(std.mem.startsWith(u8, r.results[1].report.?.clause, "MO0325 the refinement of Odd admits none of the 200 values any(Odd) generated;"));
}

test "under faults a test holds, or passes only without faults, and the summary counts each" {
    var arena_state = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const src =
        \\module T.Kinds
        \\process Loader(fs: Fs)
        \\  state
        \\    loads: UInt32
        \\    timeouts: UInt32
        \\  end
        \\  message Load
        \\  message Loads : UInt32
        \\  message Timeouts : UInt32
        \\  fn update(state, message)
        \\    case message
        \\      Load:
        \\        state.loads += 1
        \\        if fs.read("/etc/app.conf", within: 50.ms) is Error(Timeout)
        \\          state.timeouts += 1
        \\        end
        \\      Loads: state.loads
        \\      Timeouts: state.timeouts
        \\    end
        \\  end
        \\end
        \\supervisor Loaders(fs: Fs)
        \\  child Loader(fs), restart: :always
        \\end
        \\test "every load is counted, whatever the file system did"
        \\  loader = Loader.start(Fs.fixture())
        \\  loader.send(Load)
        \\  loader.send(Load)
        \\  assert loader.ask(Loads, within: 1.minute) is Ok(2)
        \\end
        \\test "no load ever times out"
        \\  loader = Loader.start(Fs.fixture())
        \\  loader.send(Load)
        \\  loader.send(Load)
        \\  assert loader.ask(Timeouts, within: 1.minute) is Ok(0)
        \\end
    ;
    const program = try compileSource(arena, src);
    const r = try run(arena, program, .{ .sim_runs = 20, .sim_seed = 1, .fault_percent = 50 });
    try std.testing.expectEqual(Outcome.passed, r.results[0].outcome);
    try std.testing.expect(r.results[0].fault_seed == null);
    try std.testing.expectEqual(Outcome.passed, r.results[1].outcome);
    const smell = r.results[1];
    try std.testing.expectEqual(contracts.Kind.assert, smell.fault_report.?.kind);
    try std.testing.expectEqual(Summary{ .tests = 2, .processes = 2, .sim_runs = 20, .sim_faults = 50, .simulated = 2, .held_under_faults = 1, .fault_free_only = 1 }, r.summary);

    var buf: [2048]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try writeResult(&w, &.{.{ .path = "kinds.mo", .source = src }}, smell);
    try writeSummary(&w, r.summary);
    const text = try std.fmt.allocPrint(arena, "{s}", .{w.buffered()});
    const head = "pass  test \"no load ever times out\": 20 simulated runs, but passes only without faults\n      seed ";
    try std.testing.expect(std.mem.startsWith(u8, text, head));
    try std.testing.expect(std.mem.indexOf(u8, text, ", with faults: kinds.mo:35:3: assert loader.ask(Timeouts, within: 1.minute) is Ok(0) failed\n      mo test --sim 1 --seed ") != null);
    try std.testing.expect(std.mem.endsWith(u8, text, " --faults 50 runs it again\n2 passed, 0 failed, 0 skipped; 2 tests under 20 seeds with 50% faults: 1 held under faults, 1 passed only without faults\n"));

    // Without faults both hold, and neither is counted as holding under them.
    const quiet = try run(arena, program, .{ .sim_runs = 20, .sim_seed = 1, .fault_percent = 0 });
    try std.testing.expectEqual(Summary{ .tests = 2, .processes = 2, .sim_runs = 20, .simulated = 2 }, quiet.summary);
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

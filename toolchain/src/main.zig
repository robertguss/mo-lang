//! `mo`: the toolchain CLI. Subcommands land with their stages:
//!   mo check <file.mo>   tier 1 (lex, parse, check, caps) → exit 0 or diagnostics
//!   mo test  <file.mo>   tier 2 (run the file's tests)  → one line per test, the
//!                        summary, and the verified: line; exit 1 when a test fails
//!     --all              runs the tests of every module the file loads
//!     --write            also writes the verified: line at the bottom of the file and
//!                        records it in .mo.ids at the program root (ids.zig)
//!     --sim [N]          tier 3: each test that starts a process runs N more times
//!                        (default 100), each on a seeded Mo.Sim
//!     --seed S           the first of those seeds; by default the file's hash
//!     --faults P         the percent chance a fixture call fails in a seeded run
//!                        (default 5; 0 for none)
//!     --until F          faults stop after fraction F (0 to 1) of each seeded run's
//!                        fixture calls, counted on the same seed without faults, so a
//!                        test asserts safety while calls fail and progress once they stop
//!   mo run   <file.mo> [-- args...]
//!     --events N         the runtime keeps the last N events (events.zig; default 4,096)
//!     --crashes N        the surface keeps the last N crash reports (events.zig; default 16)
//!     --surface PORT     serves the runtime surface's rows as JSON over HTTP on 127.0.0.1:PORT
//!                        (0: a free port) from before main runs (surface.mo; step 23)
//!                        tier 1, then `main` on Mo.Server with the args after `--`;
//!                        no test runs. Exit 0, or the last platform.exit(code), or 70
//!                        with the crash report on stderr; MO0408 when there is no main
//!   mo fmt   <file.mo>   rewrites the file in its one shape (toolchain/FORMAT.md)
//!     --check            changes nothing; exit 1 with a unified diff when the file
//!                        is not formatted, or with MO0501 for a pure for body
//!     --stdout           prints the formatted file instead of writing it
//!   mo build <file.mo>   tier 1, then the program as C (emit_c.zig) compiled by zig cc into one
//!                        binary that runs main on Mo.Server (cbuild.zig): the C in
//!                        zig-out/mo-build/<name>/, the binary beside it, its path on stdout
//!     -o <name>          the build's name; by default the file's, or its folder's for main.mo
//!     --no-contracts     the binary does not check requires, ensures, or refinements, which
//!                        every build checks by default (chapter 3); for a measurement only,
//!                        and it says so on stderr
//!     --tests            the binary runs the file's tests and prints what mo test prints,
//!                        process tests in the fixed order (--sim has no compiled form)
//!     --target <triple>  cross-compiles for a zig target, such as x86_64-linux-musl
//!     --surface          platform.runtime is Some in the binary, as under mo run, and MO_SURFACE=PORT
//!                        serves the surface over HTTP as mo run --surface PORT does (step 23)
//!   mo fix   <file.mo>   applies every fix of confidence 100 (fix.zig: MO0501, MO0307,
//!                        and MO0312), formats, and rewrites the file;
//!                        one line per fix
//!     --dry-run          changes nothing; prints the unified diff it would apply
//! check, test, and run load the file and every module it uses (program.zig); fmt
//! reads the one file. Diagnostics render as prose on stderr, or with --json as one
//! JSON record per line on stdout, each in the file it points into. A file that does
//! not parse is never rewritten.
const std = @import("std");
const Io = std.Io;
const mo = @import("mo");

const usage =
    \\usage: mo check [--recipe Module.Recipe] <file.mo> [--json]
    \\       mo test [--all | --write] [--sim [N]] [--seed S] [--faults P] [--until F] <file.mo> [--json]
    \\       mo run [--clock ISO-8601] [--events N] [--crashes N] [--surface PORT] <file.mo> [--json] [-- args...]
    \\       mo build <file.mo> [-o name] [--no-contracts] [--tests] [--target triple] [--surface] [--json]
    \\       mo fmt [--check | --stdout] <file.mo> [--json]
    \\       mo fix [--dry-run] <file.mo> [--json]
    \\
;

const FmtMode = enum { write, check, stdout };

/// A crashed `main` exits with this code (Q18; EX_SOFTWARE in sysexits.h).
const crash_exit: u8 = 70;

/// Mo code runs on a thread with room for contracts.depth_limit nested calls, so recursion
/// that does not end is a crash report, never a stack overflow (step 18).
pub fn main(init: std.process.Init) !void {
    var result: anyerror!void = {};
    const thread = try std.Thread.spawn(.{ .stack_size = mo.contracts.vm_stack_bytes }, onStack, .{ init, &result });
    thread.join();
    return result;
}

fn onStack(init: std.process.Init, result: *anyerror!void) void {
    result.* = run(init);
}

fn run(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer: Io.File.Writer = .initStreaming(.stderr(), io, &stderr_buffer);
    const err = &stderr_writer.interface;
    defer err.flush() catch {};
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: Io.File.Writer = .initStreaming(.stdout(), io, &stdout_buffer);
    const out = &stdout_writer.interface;
    defer out.flush() catch {};

    var json = false;
    var all = false;
    var write = false;
    var dry_run = false;
    var fmt_mode: FmtMode = .write;
    var positional: std.ArrayList([]const u8) = .empty;
    // Everything after `--` belongs to the program `mo run` runs.
    var program_args: ?[]const []const u8 = null;
    var sim_runs: ?u32 = null;
    var seed: ?u64 = null;
    var faults: ?u32 = null;
    var until: ?f64 = null;
    var build_name: ?[]const u8 = null;
    var target: ?[]const u8 = null;
    var no_contracts = false;
    var tests = false;
    var recipe_name: ?[]const u8 = null;
    var clock: ?[]const u8 = null;
    var events_cap: ?u32 = null;
    var crashes_cap: ?u32 = null;
    // `mo build --surface`, and `mo run --surface PORT` (step 23).
    var surface = false;
    var surface_port: ?u16 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--")) {
            const rest = try arena.alloc([]const u8, args.len - i - 1);
            for (args[i + 1 ..], rest) |r, *o| o.* = r;
            program_args = rest;
            break;
        } else if (std.mem.eql(u8, a, "--sim")) {
            sim_runs = mo.runner.default_sim_runs;
            if (i + 1 < args.len) {
                if (std.fmt.parseInt(u32, args[i + 1], 10)) |n| {
                    sim_runs = n;
                    i += 1;
                } else |_| {}
            }
        } else if (std.mem.eql(u8, a, "--seed")) {
            i += 1;
            if (i == args.len) return usageExit(err);
            seed = std.fmt.parseInt(u64, args[i], 10) catch return usageExit(err);
        } else if (std.mem.eql(u8, a, "--faults")) {
            i += 1;
            if (i == args.len) return usageExit(err);
            const percent = std.fmt.parseInt(u32, args[i], 10) catch return usageExit(err);
            if (percent > 100) return usageExit(err);
            faults = percent;
        } else if (std.mem.eql(u8, a, "--until")) {
            i += 1;
            if (i == args.len) return usageExit(err);
            const fraction = std.fmt.parseFloat(f64, args[i]) catch return usageExit(err);
            if (!(fraction >= 0 and fraction <= 1)) return usageExit(err);
            until = fraction;
        } else if (std.mem.eql(u8, a, "-o")) {
            i += 1;
            if (i == args.len) return usageExit(err);
            build_name = args[i];
        } else if (std.mem.eql(u8, a, "--target")) {
            i += 1;
            if (i == args.len) return usageExit(err);
            target = args[i];
        } else if (std.mem.eql(u8, a, "--no-contracts")) {
            no_contracts = true;
        } else if (std.mem.eql(u8, a, "--tests")) {
            tests = true;
        } else if (std.mem.eql(u8, a, "--clock")) {
            i += 1;
            if (i == args.len) return usageExit(err);
            clock = args[i];
        } else if (std.mem.eql(u8, a, "--surface")) {
            surface = true;
            if (i + 1 < args.len) {
                if (std.fmt.parseInt(u16, args[i + 1], 10)) |port| {
                    surface_port = port;
                    i += 1;
                } else |_| {}
            }
        } else if (std.mem.eql(u8, a, "--events")) {
            i += 1;
            if (i == args.len) return usageExit(err);
            events_cap = std.fmt.parseInt(u32, args[i], 10) catch return usageExit(err);
        } else if (std.mem.eql(u8, a, "--crashes")) {
            i += 1;
            if (i == args.len) return usageExit(err);
            crashes_cap = std.fmt.parseInt(u32, args[i], 10) catch return usageExit(err);
        } else if (std.mem.eql(u8, a, "--recipe")) {
            i += 1;
            if (i == args.len) return usageExit(err);
            recipe_name = args[i];
        } else if (std.mem.eql(u8, a, "--json")) {
            json = true;
        } else if (std.mem.eql(u8, a, "--all")) {
            all = true;
        } else if (std.mem.eql(u8, a, "--write")) {
            write = true;
        } else if (std.mem.eql(u8, a, "--dry-run")) {
            dry_run = true;
        } else if (std.mem.eql(u8, a, "--check")) {
            fmt_mode = .check;
        } else if (std.mem.eql(u8, a, "--stdout")) {
            fmt_mode = .stdout;
        } else try positional.append(arena, a);
    }
    if (positional.items.len != 2) return usageExit(err);
    const command = positional.items[0];
    const path = positional.items[1];
    const is_fmt = std.mem.eql(u8, command, "fmt");
    if (!is_fmt and fmt_mode != .write) return usageExit(err);
    const is_run = std.mem.eql(u8, command, "run");
    const is_fix = std.mem.eql(u8, command, "fix");
    if (dry_run and !is_fix) return usageExit(err);
    const is_build = std.mem.eql(u8, command, "build");
    if (!is_build and (build_name != null or target != null or no_contracts or tests)) return usageExit(err);
    if (surface and !is_build and !is_run) return usageExit(err);
    if (surface and (is_build == (surface_port != null))) return usageExit(err);
    if (!is_run and (program_args != null or clock != null or events_cap != null or crashes_cap != null)) return usageExit(err);
    if (all and !std.mem.eql(u8, command, "test")) return usageExit(err);
    if (recipe_name != null and !std.mem.eql(u8, command, "check")) return usageExit(err);
    // The line is one file's: --all's summary covers the modules it loads too.
    if (write and (all or !std.mem.eql(u8, command, "test"))) return usageExit(err);
    // A seed and faults shape a simulated run, so they mean nothing without --sim.
    if (sim_runs != null and !std.mem.eql(u8, command, "test")) return usageExit(err);
    if ((seed != null or faults != null or until != null) and sim_runs == null) return usageExit(err);

    var diags: mo.diag.List = .empty;

    if (is_fmt) {
        const source = try Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 20));
        const files: []const mo.diag.File = &.{.{ .path = path, .source = source }};
        const formatted = mo.fmt.format(arena, source, &diags) catch |e| switch (e) {
            error.Rejected => return reject(out, err, files, diags.items, json),
            else => return e,
        };
        switch (fmt_mode) {
            .stdout => try out.writeAll(formatted),
            .write => if (!std.mem.eql(u8, source, formatted)) {
                try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = formatted });
            },
            .check => {
                // The loop rule (MO0501) is the formatter's to enforce, and the checker's.
                var findings: mo.diag.List = .empty;
                try mo.pipeline.loopFindings(arena, source, &findings);
                const changed = !std.mem.eql(u8, source, formatted);
                if (changed) try mo.diff.unified(arena, out, path, source, formatted);
                if (changed or findings.items.len > 0) return reject(out, err, files, findings.items, json);
            },
        }
        return;
    }

    // The file and every module it uses, from the program root.
    var program = try mo.program.load(arena, io, path, &diags);
    // The runtime surface's module goes first when mo run or mo build serves it (step 23).
    if (surface and !tests) program = try mo.program.withSurface(arena, program);

    if (is_fix) {
        // A file that does not load or parse has nothing to fix (step 25).
        if (diags.items.len > 0) return reject(out, err, program.files, diags.items, json);
        const outcome = try mo.fix.run(arena, program);
        const before = program.main().source;
        if (std.mem.eql(u8, before, outcome.source)) return;
        if (dry_run) return mo.diff.labeled(arena, out, path, "fixed", before, outcome.source);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = outcome.source });
        for (outcome.taken) |t| try out.print("{s}:{d}: {s} {s}\n", .{ path, t.line, t.code, t.description });
        return;
    }

    if (is_build) {
        const checked = mo.pipeline.buildable(arena, program, tests, &diags) catch |e| switch (e) {
            error.Rejected => return reject(out, err, program.files, diags.items, json),
            else => return e,
        };
        const options: mo.cbuild.Options = .{
            .name = build_name orelse mo.cbuild.defaultName(path),
            .contracts = !no_contracts,
            .tests = tests,
            .surface = surface,
            .target = target,
        };
        // Chapter 3: contracts run in every build. Turning them off is for a measurement.
        if (no_contracts) {
            try err.print("mo build: warning: {s}: built with --no-contracts, so requires, ensures, and refinements are not checked; use it to measure, not to ship\n", .{path});
            err.flush() catch {};
        }
        switch (try mo.cbuild.build(arena, io, init.environ_map, program, &checked, options)) {
            .built => |b| try out.print("{s}\n", .{b.binary}),
            .failed => |why| {
                try err.print("mo build: {s}: {s}\n", .{ path, why });
                err.flush() catch {};
                std.process.exit(1);
            },
        }
        return;
    }

    if (is_run) {
        const m = mo.pipeline.mainProgram(arena, program, &diags) catch |e| switch (e) {
            error.Rejected => return reject(out, err, program.files, diags.items, json),
            else => return e,
        };
        const cwd = try std.process.currentPathAlloc(io, arena);
        var server: mo.server.Server = try .init(arena, io, cwd, program_args orelse &.{}, init.environ_map, out, err);
        server.files = program.files;
        if (events_cap) |n| server.events_cap = n;
        if (crashes_cap) |n| server.crashes_cap = n;
        server.surface_port = surface_port;
        // --clock, else MO_CLOCK, fixes where main's clock starts; a built binary reads MO_CLOCK.
        if (clock orelse init.environ_map.get("MO_CLOCK")) |text| {
            server.startClock(mo.stdlib.parseTime(text) orelse {
                try err.print("mo run: {s} is not an ISO-8601 time such as 2026-01-01T00:00:00Z\n", .{text});
                try err.flush();
                std.process.exit(2);
            });
        }
        const stats = init.environ_map.get("MO_STATS") != null;
        if (stats) {
            const act: std.posix.Sigaction = .{ .handler = .{ .handler = statsOnTerm }, .mask = std.posix.sigemptyset(), .flags = 0 };
            std.posix.sigaction(.TERM, &act, null);
        }
        const code: u8 = switch (try server.run(m.program, m.main)) {
            .exited => |c| c,
            .crashed => |report| blk: {
                out.flush() catch {};
                try err.writeAll("main crashed: ");
                try mo.runner.writeReport(err, program.files, report);
                try err.writeAll("\n");
                break :blk crash_exit;
            },
        };
        out.flush() catch {};
        err.flush() catch {};
        if (stats) printStats();
        std.process.exit(code);
    }

    const stage: mo.pipeline.Stage = if (std.mem.eql(u8, command, "check"))
        .check
    else if (std.mem.eql(u8, command, "test"))
        .run
    else
        return usageExit(err);

    if (stage == .run) {
        const options: mo.runner.Options = .{
            .sim_runs = sim_runs orelse 0,
            .sim_seed = seed orelse mo.runner.seedOf(program.main().source),
            .fault_percent = faults orelse mo.runner.default_fault_percent,
            .fault_until = until orelse 1,
        };
        // --write replaces the file's line, so the line it has now is no finding.
        const last = program.files.len - 1;
        if (write and last < program.verified_lines.len) program.verified_lines[last] = .recorded;
        const r = mo.pipeline.testProgram(arena, program, all, options, &diags) catch |e| switch (e) {
            error.Rejected => return reject(out, err, program.files, diags.items, json),
            else => return e,
        };
        for (r.results) |result| try mo.runner.writeResult(out, program.files, result);
        try mo.runner.writeInvariants(out, r.invariants);
        try mo.runner.writeSummary(out, r.summary);
        var line: Io.Writer.Allocating = .init(arena);
        try mo.verified.render(&line.writer, r.summary);
        try out.writeAll(line.written());
        if (write) {
            const main_file = program.main();
            const uses = if (last < program.uses.len) program.uses[last] else &.{};
            try mo.ids.write(arena, io, program.root, main_file.path, program.keys[last], main_file.source, line.written(), uses);
        }
        try out.flush();
        if (r.summary.failures > 0) std.process.exit(1);
        return;
    }
    // --recipe: the file against a recipe's signatures, then the recipe's tests run on it. A file
    // whose first lines say `# recipe: Module.Recipe` is held to that recipe by a plain check too,
    // as the corpus test holds it (step 20).
    if (recipe_name orelse mo.recipe.named(program.main().source)) |name| {
        diags.clearRetainingCapacity();
        const c = try mo.recipe.conform(arena, io, path, name, &diags);
        const r = c.run orelse return reject(out, err, c.files, diags.items, json);
        try out.print("recipe {s}: {d} signatures match\n", .{ name, c.signatures });
        for (r.results) |result| try mo.runner.writeResult(out, c.files, result);
        try mo.runner.writeSummary(out, r.summary);
        try out.flush();
        if (r.summary.failures > 0) std.process.exit(1);
        return;
    }
    mo.pipeline.runTo(arena, program, stage, &diags) catch |e| switch (e) {
        error.Rejected => return reject(out, err, program.files, diags.items, json),
        else => return e,
    };
}

/// `MO_STATS=1`: what the run allocated and copied, on stderr when it ends or is terminated.
/// With more than one scheduler (step 30), a line for the run and then one for each scheduler, whose
/// counts are its thread's.
fn printStats() void {
    const own = mo.region.main_stats orelse &mo.region.stats;
    var total = mo.region.joined;
    total.add(own.*);
    for (mo.turns.live_stats[1..]) |live| if (live) |x| total.add(x.*);
    statsLine("", total);
    const cores = mo.turns.last_cores;
    if (cores < 2) return;
    var sweeps: [96]u8 = undefined;
    const line = std.fmt.bufPrint(&sweeps, "mo stats: schedulers {d} sweeps {d} missed {d} ids {d}\n", .{ cores, mo.turns.sweeps_run, mo.turns.sweeps_missed, mo.turns.ids_used }) catch "";
    _ = std.posix.system.write(2, line.ptr, line.len);
    for (0..cores) |k| {
        const counts = if (k == 0) own.* else if (mo.turns.live_stats[k]) |x| x.* else mo.turns.last_stats[k];
        var label: [32]u8 = undefined;
        statsLine(std.fmt.bufPrint(&label, "scheduler {d} ", .{k}) catch "", counts);
    }
    // Where the processes went (step 34), a line per scheduler after the counts.
    for (0..cores) |k| {
        const pl = mo.turns.placementOf(k);
        var buf: [160]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "mo stats: scheduler {d} placed {d} with_starter {d} live {d} asks_across {d}\n", .{ k, pl.placed, pl.with_starter, pl.live, pl.asks_across }) catch continue;
        _ = std.posix.system.write(2, text.ptr, text.len);
    }
}

fn statsLine(label: []const u8, s: mo.region.Stats) void {
    var buf: [360]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "mo stats: {s}allocations {d} bytes {d} packed {d} packed_bytes {d} packed_capacity {d} freed {d} freed_ns {d} spilled {d}\n", .{ label, s.allocations, s.allocated_bytes, s.packed_values, s.packed_bytes, s.packed_capacity, s.freed, s.freed_ns, s.spilled_bytes }) catch return;
    _ = std.posix.system.write(2, line.ptr, line.len);
}

fn statsOnTerm(_: std.posix.SIG) callconv(.c) void {
    printStats();
    std.process.exit(0);
}

fn usageExit(err: *Io.Writer) !void {
    try err.writeAll(usage);
    try err.flush();
    std.process.exit(2);
}

fn reject(out: *Io.Writer, err: *Io.Writer, files: []const mo.diag.File, records: []const mo.diag.Record, json: bool) !void {
    for (records) |d| {
        const loc = mo.diag.locate(files, d.at);
        var r = d;
        r.at = loc.at;
        // A fix's edits point into the program's source too.
        if (json and d.fixes.len > 0) r.fixes = try rebase(d.fixes, d.at - loc.at);
        if (json) try mo.diag.renderJson(out, loc.path, loc.source, r) else try mo.diag.renderProse(err, loc.path, loc.source, r);
    }
    try out.flush();
    try err.flush();
    std.process.exit(1);
}

/// Fixes with each edit moved back by `shift`, into the file it points into.
fn rebase(fixes: []const mo.diag.Fix, shift: u32) ![]const mo.diag.Fix {
    const gpa = std.heap.page_allocator;
    const out = try gpa.dupe(mo.diag.Fix, fixes);
    for (out) |*f| {
        const edits = try gpa.dupe(mo.diag.Edit, f.edits);
        for (edits) |*e| e.at -= shift;
        f.edits = edits;
    }
    return out;
}

//! The benchmark harness, from day one (design-v0/08: "50 ms and 100 ms targets:
//! the benchmark suite, from day one"). Times every pipeline stage over every file
//! in the corpus, each loaded with the modules it uses, best of N iterations, and
//! prints one row per stage. Stages that are not implemented print "n/a" and the row
//! lights up when the stage lands. A last `fmt` row times every file lexed, parsed, and
//! formatted to memory (`mo fmt` without the write), and a `run-programs` row times every
//! run of every program in programs/ end to end through `mo run` (MO_EXE), process
//! start included. A `logstat-4k` row times program 2 over 4_000 generated log lines in
//! this process: its four modules loaded and checked, then main on Mo.Server with its
//! output discarded, so the runtime has a permanent number. A `sim-100` row times
//! payments/refund.mo's tests as `mo test --sim 100` runs them, in this process, with the
//! same file without --sim beside it, so a seeded run's cost reads off the difference. An
//! `echo-1k` row times programs/echo given 1_000 lines in this process: 1_000 round trips
//! over a real socket on 127.0.0.1, a client process to a worker process, main on
//! Mo.Server with its output discarded. A `map-100k` row times a program that sets 100_000
//! keys in a map and then gets each one, in this process. A `kv-10k-get` row times 10_000
//! GETs over one real socket to programs/kv, served by `mo run` (MO_EXE) in a process of
//! its own, each GET waiting for its answer.
//! A `logstat-4k-c` row times program 2 built by `mo build` (cbuild.zig) over the same 4_000
//! lines, contracts on as in every build, the binary a process of its own with its output
//! discarded, and names its ratio to `logstat-4k`; the same build with wrapping arithmetic and
//! no overflow checks (-fwrapv, for this comparison only, never shipped) runs beside it, so the
//! checks' cost reads off the difference, and so does the same build `--no-contracts`
//! (`logstat-4k-c-nocontracts`), so the contracts' cost does. A `build-logstat` row times `mo build` of program 2, best of three: loading,
//! checking, and emitting the C, then `zig cc`, each build a real compile (a define that
//! changes every time keeps zig cc from answering out of its cache).
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
const posix = std.posix;

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
    var stdout_writer: Io.File.Writer = .initStreaming(.stdout(), io, &stdout_buffer);
    const out = &stdout_writer.interface;
    defer out.flush() catch {};

    const paths = try mo.corpus.collect(arena, io, root);
    // Each file with the modules it uses, read once, so a row times the stages and not the disk.
    var programs = try arena.alloc(mo.program.Program, paths.len);
    var total_bytes: usize = 0;
    for (paths, 0..) |rel, i| {
        var load_diags: mo.diag.List = .empty;
        programs[i] = try mo.program.load(arena, io, try std.fs.path.join(arena, &.{ root, rel }), &load_diags);
        total_bytes += programs[i].main().source.len;
    }

    try out.print("mo-bench: {d} files, {d} bytes, best of {d}\n", .{ paths.len, total_bytes, iters });
    try out.print("{s:<8} {s:>12} {s:>12}\n", .{ "stage", "total", "per file" });

    // One arena, reset per file and kept warm, so a row times the stage and not the page faults.
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();

    // The run stage also keeps each file's best, to name the slowest file. Only that
    // stage reads the clock per file, so the other rows time exactly what they did.
    const run_best = try arena.alloc(i96, paths.len);
    @memset(run_best, std.math.maxInt(i96));

    var rows: [mo.pipeline.stages.len]Row = undefined;
    for (mo.pipeline.stages, 0..) |stage, si| {
        var best: i96 = std.math.maxInt(i96);
        var implemented = true;
        var it: u32 = 0;
        while (it < iters and implemented) : (it += 1) {
            const t0 = Io.Clock.Timestamp.now(io, .awake);
            for (programs, 0..) |prog, fi| {
                _ = scratch.reset(.retain_capacity);
                var diags: mo.diag.List = .empty;
                const f0 = if (stage == .run) Io.Clock.Timestamp.now(io, .awake) else t0;
                mo.pipeline.runTo(scratch.allocator(), prog, stage, &diags) catch |e| switch (e) {
                    error.NotImplemented => {
                        implemented = false;
                        break;
                    },
                    else => {},
                };
                if (stage == .run) {
                    const file_ns = f0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
                    if (file_ns < run_best[fi]) run_best[fi] = file_ns;
                }
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

    var fmt_best: i96 = std.math.maxInt(i96);
    var fmt_it: u32 = 0;
    while (fmt_it < iters) : (fmt_it += 1) {
        const t0 = Io.Clock.Timestamp.now(io, .awake);
        for (programs) |prog| {
            _ = scratch.reset(.retain_capacity);
            var diags: mo.diag.List = .empty;
            _ = mo.fmt.format(scratch.allocator(), prog.main().source, &diags) catch {};
        }
        const ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        if (ns < fmt_best) fmt_best = ns;
    }
    const fmt_per: i96 = if (paths.len == 0) 0 else @divTrunc(fmt_best, @as(i96, @intCast(paths.len)));
    try out.print("{s:<8} {d:>9} µs {d:>9} µs\n", .{ "fmt", @as(u64, @intCast(@divTrunc(fmt_best, 1000))), @as(u64, @intCast(@divTrunc(fmt_per, 1000))) });

    // Each program as a user runs it: a fresh `mo run` process per `# run:` line that
    // loads, checks, lowers, and runs main on Mo.Server.
    const mo_exe = try mo.corpus.moExe(arena, io, init.environ_map.get("MO_EXE"));
    var program_count: usize = 0;
    for (paths) |rel| program_count += @intFromBool(mo.corpus.isProgramPath(rel));
    var programs_best: i96 = std.math.maxInt(i96);
    var programs_it: u32 = 0;
    while (program_count > 0 and programs_it < iters) : (programs_it += 1) {
        const t0 = Io.Clock.Timestamp.now(io, .awake);
        for (paths, programs) |rel, prog| {
            if (!mo.corpus.isProgramPath(rel)) continue;
            _ = scratch.reset(.retain_capacity);
            for (try mo.corpus.runs(scratch.allocator(), prog.main().source)) |run| {
                _ = try mo.corpus.runProgram(scratch.allocator(), io, mo_exe, root, rel, run.args);
            }
        }
        const ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        if (ns < programs_best) programs_best = ns;
    }
    if (program_count > 0) {
        const per: i96 = @divTrunc(programs_best, @as(i96, @intCast(program_count)));
        try out.print("{s:<8} {d:>9} µs {d:>9} µs  ({d} programs)\n", .{ "run-programs", @as(u64, @intCast(@divTrunc(programs_best, 1000))), @as(u64, @intCast(@divTrunc(per, 1000))), program_count });
    } else {
        try out.print("{s:<8} {s:>12} {s:>12}\n", .{ "run-programs", "n/a", "n/a" });
    }

    const logstat_ns = try logstat4k(arena, io, init.environ_map, root, iters, &scratch);
    if (logstat_ns) |ns| {
        const us: u64 = @intCast(@divTrunc(ns, 1000));
        try out.print("{s:<8} {d:>9} µs {d:>9} µs a line  (4000 lines)\n", .{ "logstat-4k", us, us / log_lines });
    } else {
        try out.print("{s:<8} {s:>12} {s:>12}\n", .{ "logstat-4k", "n/a", "n/a" });
    }

    const compiled = try logstat4kC(arena, io, init.environ_map, root, iters);
    if (compiled) |c| {
        const us: u64 = @intCast(@divTrunc(c.run_ns, 1000));
        const wrap_us: u64 = @intCast(@divTrunc(c.wrap_ns, 1000));
        try out.print("{s:<8} {d:>9} µs {d:>9} µs a line  (4000 lines, a process of its own", .{ "logstat-4k-c", us, us / log_lines });
        if (logstat_ns) |ns| try out.print("; the interpreter's logstat-4k takes {d:.1}x as long", .{@as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(c.run_ns))});
        try out.print(")\n{s:<8} {d:>9} µs without overflow checks (-fwrapv): the checks cost {d:.1}%\n", .{ "logstat-4k-c-wrap", wrap_us, (@as(f64, @floatFromInt(c.run_ns)) / @as(f64, @floatFromInt(c.wrap_ns)) - 1.0) * 100.0 });
        try out.print("{s:<8} {d:>9} µs without contracts (--no-contracts): the contracts cost {d:.1}%\n", .{ "logstat-4k-c-nocontracts", @as(u64, @intCast(@divTrunc(c.nocontracts_ns, 1000))), (@as(f64, @floatFromInt(c.run_ns)) / @as(f64, @floatFromInt(c.nocontracts_ns)) - 1.0) * 100.0 });
        try out.print("{s:<8} {d:>9} µs  (load, check, and emit C {d} µs; zig cc {d} µs)\n", .{ "build-logstat", @as(u64, @intCast(@divTrunc(c.emit_ns + c.cc_ns, 1000))), @as(u64, @intCast(@divTrunc(c.emit_ns, 1000))), @as(u64, @intCast(@divTrunc(c.cc_ns, 1000))) });
    } else {
        try out.print("{s:<8} {s:>12} {s:>12}\n{s:<8} {s:>12} {s:>12}\n", .{ "logstat-4k-c", "n/a", "n/a", "build-logstat", "n/a", "n/a" });
    }

    const sim = try sim100(io, paths, programs, iters, &scratch);
    if (sim) |t| {
        const us: u64 = @intCast(@divTrunc(t.sim_ns, 1000));
        const per_run: u64 = @intCast(@divTrunc(@max(t.sim_ns - t.fixed_ns, 0), 1000 * sim_seeds));
        const fixed_us: u64 = @intCast(@divTrunc(t.fixed_ns, 1000));
        try out.print("{s:<8} {d:>9} µs {d:>9} µs a seeded run  ({s}, {d} seeds; {d} µs without --sim)\n", .{ "sim-100", us, per_run, sim_file, sim_seeds, fixed_us });
    } else {
        try out.print("{s:<8} {s:>12} {s:>12}\n", .{ "sim-100", "n/a", "n/a" });
    }

    const echo_ns = try echo1k(arena, io, init.environ_map, root, iters, &scratch);
    if (echo_ns) |ns| {
        const us: u64 = @intCast(@divTrunc(ns, 1000));
        try out.print("{s:<8} {d:>9} µs {d:>9} µs a round trip  ({d} round trips over 127.0.0.1)\n", .{ "echo-1k", us, us / echo_trips, echo_trips });
    } else {
        try out.print("{s:<8} {s:>12} {s:>12}\n", .{ "echo-1k", "n/a", "n/a" });
    }

    const map_ns = try map100k(arena, io, init.environ_map, iters, &scratch);
    if (map_ns) |ns| {
        const us: u64 = @intCast(@divTrunc(ns, 1000));
        try out.print("{s:<8} {d:>9} µs {d:>9} ns a set and a get  ({d} keys)\n", .{ "map-100k", us, @as(u64, @intCast(@divTrunc(ns, map_keys))), map_keys });
    } else {
        try out.print("{s:<8} {s:>12} {s:>12}\n", .{ "map-100k", "n/a", "n/a" });
    }

    const kv_ns = try kv10kGet(arena, io, mo_exe, root, iters);
    if (kv_ns) |ns| {
        const us: u64 = @intCast(@divTrunc(ns, 1000));
        try out.print("{s:<8} {d:>9} µs {d:>9} µs a GET  ({d} GETs over 127.0.0.1 from one client)\n", .{ "kv-10k-get", us, us / kv_gets, kv_gets });
    } else {
        try out.print("{s:<8} {s:>12} {s:>12}\n", .{ "kv-10k-get", "n/a", "n/a" });
    }

    if (rows[rows.len - 1].implemented and paths.len > 0) {
        var worst: usize = 0;
        for (run_best, 0..) |ns, i| if (ns > run_best[worst]) {
            worst = i;
        };
        try out.print("slowest run: {s}, {d} µs\n", .{ paths[worst], @as(u64, @intCast(@divTrunc(run_best[worst], 1000))) });
    }

    if (record) try appendResults(io, &rows, paths.len, fmt_best, program_count, programs_best, logstat_ns, if (sim) |t| t.sim_ns else null, echo_ns, map_ns, kv_ns, compiled);
}

const sim_seeds = 100;
const sim_file = "payments/refund.mo";

const SimTimes = struct { sim_ns: i96 = std.math.maxInt(i96), fixed_ns: i96 = std.math.maxInt(i96) };

/// The best of `iters` runs of refund.mo's tests from its loaded program to their results
/// (check, lower, and every test), under --sim 100 and without it; null when the corpus
/// has no refund.mo or one of its tests fails.
fn sim100(io: Io, paths: []const []const u8, programs: []const mo.program.Program, iters: u32, scratch: *std.heap.ArenaAllocator) !?SimTimes {
    const k = for (paths, 0..) |rel, i| {
        if (std.mem.eql(u8, rel, sim_file)) break i;
    } else return null;
    const prog = programs[k];
    var times: SimTimes = .{};
    for ([_]u32{ 0, sim_seeds }) |runs| {
        const best = if (runs == 0) &times.fixed_ns else &times.sim_ns;
        var it: u32 = 0;
        while (it < iters) : (it += 1) {
            _ = scratch.reset(.retain_capacity);
            var diags: mo.diag.List = .empty;
            const options: mo.runner.Options = .{ .sim_runs = runs, .sim_seed = mo.runner.seedOf(prog.main().source) };
            const t0 = Io.Clock.Timestamp.now(io, .awake);
            const r = mo.pipeline.testProgram(scratch.allocator(), prog, false, options, &diags) catch |e| {
                std.debug.print("sim-100: {s}: {t}\n", .{ sim_file, e });
                return null;
            };
            const ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
            if (r.summary.failures > 0) {
                std.debug.print("sim-100: {s} has a failing test\n", .{sim_file});
                return null;
            }
            if (ns < best.*) best.* = ns;
        }
    }
    return times;
}

const log_lines = 4_000;
const log_dir = ".zig-cache/bench";
const log_name = "logstat-4k.log";

/// The best of `iters` runs of programs/logstat/main.mo over the generated log, or null
/// when the corpus has no logstat or a run does not exit 0.
fn logstat4k(arena: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map, root: []const u8, iters: u32, scratch: *std.heap.ArenaAllocator) !?i96 {
    const main_path = try std.fs.path.join(arena, &.{ root, "programs/logstat/main.mo" });
    Io.Dir.cwd().access(io, main_path, .{}) catch return null;
    try writeLog(arena, io);
    const cwd = try std.process.currentPathAlloc(io, arena);
    var best: i96 = std.math.maxInt(i96);
    var it: u32 = 0;
    while (it < iters) : (it += 1) {
        _ = scratch.reset(.retain_capacity);
        const a = scratch.allocator();
        var out_buffer: [4096]u8 = undefined;
        var discard_out: Io.Writer.Discarding = .init(&out_buffer);
        var err_buffer: [1024]u8 = undefined;
        var discard_err: Io.Writer.Discarding = .init(&err_buffer);
        const t0 = Io.Clock.Timestamp.now(io, .awake);
        var diags: mo.diag.List = .empty;
        const program = try mo.program.load(a, io, main_path, &diags);
        const m = mo.pipeline.mainProgram(a, program, &diags) catch |e| {
            std.debug.print("logstat-4k: {t}: {s}\n", .{ e, if (diags.items.len > 0) diags.items[0].what else "" });
            return null;
        };
        var server: mo.server.Server = try .init(a, io, cwd, &.{log_dir}, environ, &discard_out.writer, &discard_err.writer);
        switch (try server.run(m.program, m.main)) {
            .exited => |code| if (code != 0) {
                std.debug.print("logstat-4k: main exited {d}\n", .{code});
                return null;
            },
            .crashed => |report| {
                std.debug.print("logstat-4k: main crashed: {s}\n", .{report.clause});
                return null;
            },
        }
        const ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        if (ns < best) best = ns;
    }
    return best;
}

const LogstatC = struct { run_ns: i96, wrap_ns: i96, nocontracts_ns: i96, emit_ns: i96, cc_ns: i96 };

/// The three builds of the compiled logstat: as `mo build` makes it, without overflow checks,
/// and without contracts.
const Variant = enum { shipped, wrap, nocontracts };

const build_dir = ".zig-cache/bench/mo-build";

/// Program 2 as `mo build` builds it: the binary's best of `iters` runs over the logstat-4k
/// log, a process of its own with its output discarded; the same with -fwrapv and no overflow
/// checks; the same --no-contracts; and the build's best of three, loading, checking, and emitting apart from zig cc.
/// Null when the corpus has no logstat, a build fails, or a run does not exit 0.
fn logstat4kC(arena: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map, root: []const u8, iters: u32) !?LogstatC {
    const main_path = try std.fs.path.join(arena, &.{ root, "programs/logstat/main.mo" });
    Io.Dir.cwd().access(io, main_path, .{}) catch return null;
    try writeLog(arena, io);
    const most = std.math.maxInt(i96);
    var result: LogstatC = .{ .run_ns = most, .wrap_ns = most, .nocontracts_ns = most, .emit_ns = most, .cc_ns = most };
    for ([_]Variant{ .shipped, .wrap, .nocontracts }) |variant| {
        var binary: []const u8 = "";
        var b: u32 = 0;
        while (b < @min(iters, 3)) : (b += 1) {
            const t0 = Io.Clock.Timestamp.now(io, .awake);
            var diags: mo.diag.List = .empty;
            const program = try mo.program.load(arena, io, main_path, &diags);
            const checked = mo.pipeline.buildable(arena, program, false, &diags) catch |e| {
                std.debug.print("logstat-4k-c: {t}: {s}\n", .{ e, if (diags.items.len > 0) diags.items[0].what else "" });
                return null;
            };
            const front_ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
            const salt: u64 = @intCast(@mod(Io.Clock.Timestamp.now(io, .real).raw.toNanoseconds(), std.math.maxInt(u63)));
            const options: mo.cbuild.Options = .{
                .name = switch (variant) {
                    .shipped => "logstat",
                    .wrap => "logstat-wrap",
                    .nocontracts => "logstat-nocontracts",
                },
                .wrap = variant == .wrap,
                .contracts = variant != .nocontracts,
                .out_dir = build_dir,
                .salt = salt,
            };
            switch (try mo.cbuild.build(arena, io, environ, program, &checked, options)) {
                .built => |built| {
                    binary = built.binary;
                    if (variant == .shipped) {
                        result.emit_ns = @min(result.emit_ns, front_ns + built.emit_ns);
                        result.cc_ns = @min(result.cc_ns, built.cc_ns);
                    }
                },
                .refused, .failed => |why| {
                    std.debug.print("logstat-4k-c: {s}\n", .{why});
                    return null;
                },
            }
        }
        var it: u32 = 0;
        while (it < iters) : (it += 1) {
            const t0 = Io.Clock.Timestamp.now(io, .awake);
            const ran = try std.process.run(arena, io, .{ .argv = &.{ binary, log_dir } });
            const ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
            if (ran.term != .exited or ran.term.exited != 0) {
                std.debug.print("logstat-4k-c: {s} ended with {any}: {s}\n", .{ binary, ran.term, ran.stderr });
                return null;
            }
            const best = switch (variant) {
                .shipped => &result.run_ns,
                .wrap => &result.wrap_ns,
                .nocontracts => &result.nocontracts_ns,
            };
            if (ns < best.*) best.* = ns;
        }
    }
    return result;
}

const echo_trips = 1_000;

/// The best of `iters` runs of programs/echo/main.mo given 1_000 lines: its one client
/// process sends each line and reads it back from its worker over a real socket on
/// 127.0.0.1, so a run is 1_000 round trips, from loading the program to main's end, with
/// the output discarded. Null when the corpus has no echo or a run does not exit 0 (echo
/// exits 1 when a round trip is lost).
fn echo1k(arena: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map, root: []const u8, iters: u32, scratch: *std.heap.ArenaAllocator) !?i96 {
    const main_path = try std.fs.path.join(arena, &.{ root, "programs/echo/main.mo" });
    Io.Dir.cwd().access(io, main_path, .{}) catch return null;
    const lines = try arena.alloc([]const u8, echo_trips);
    @memset(lines, "x");
    const cwd = try std.process.currentPathAlloc(io, arena);
    var best: i96 = std.math.maxInt(i96);
    var it: u32 = 0;
    while (it < iters) : (it += 1) {
        _ = scratch.reset(.retain_capacity);
        const a = scratch.allocator();
        var out_buffer: [4096]u8 = undefined;
        var discard_out: Io.Writer.Discarding = .init(&out_buffer);
        var err_buffer: [1024]u8 = undefined;
        var discard_err: Io.Writer.Discarding = .init(&err_buffer);
        const t0 = Io.Clock.Timestamp.now(io, .awake);
        var diags: mo.diag.List = .empty;
        const program = try mo.program.load(a, io, main_path, &diags);
        const m = mo.pipeline.mainProgram(a, program, &diags) catch |e| {
            std.debug.print("echo-1k: {t}: {s}\n", .{ e, if (diags.items.len > 0) diags.items[0].what else "" });
            return null;
        };
        var server: mo.server.Server = try .init(a, io, cwd, lines, environ, &discard_out.writer, &discard_err.writer);
        switch (try server.run(m.program, m.main)) {
            .exited => |code| if (code != 0) {
                std.debug.print("echo-1k: main exited {d}\n", .{code});
                return null;
            },
            .crashed => |report| {
                std.debug.print("echo-1k: main crashed: {s}\n", .{report.clause});
                return null;
            },
        }
        const ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        if (ns < best) best = ns;
    }
    return best;
}

const map_keys = 100_000;
const map_dir = ".zig-cache/bench/map";

const map_source =
    \\module Bench.Map
    \\
    \\intent "Set 100,000 keys in a map, then get each of them."
    \\
    \\fn filled(n: UInt64) : Map(String, UInt64)
    \\  var m = Map.new()
    \\  for i in 0..n
    \\    m = m.set("key#{i}", i)
    \\  end
    \\  m
    \\end
    \\
    \\fn found(m: Map(String, UInt64), n: UInt64) : UInt64
    \\  var hits = 0
    \\  for i in 0..n
    \\    if m.get("key#{i}") == Some(i)
    \\      hits += 1
    \\    end
    \\  end
    \\  hits
    \\end
    \\
    \\fn main(platform: Platform)
    \\  m = filled(100_000)
    \\  if found(m, 100_000) != 100_000
    \\    platform.exit(1)
    \\  end
    \\end
    \\
;

/// The best of `iters` runs of a program that sets 100_000 keys in a map and then gets each
/// one, from loading it to main's end; null when a run does not exit 0.
fn map100k(arena: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map, iters: u32, scratch: *std.heap.ArenaAllocator) !?i96 {
    try Io.Dir.cwd().createDirPath(io, map_dir);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = map_dir ++ "/mo.root", .data = "" });
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = map_dir ++ "/map.mo", .data = map_source });
    const cwd = try std.process.currentPathAlloc(io, arena);
    var best: i96 = std.math.maxInt(i96);
    var it: u32 = 0;
    while (it < iters) : (it += 1) {
        _ = scratch.reset(.retain_capacity);
        const a = scratch.allocator();
        var out_buffer: [256]u8 = undefined;
        var discard: Io.Writer.Discarding = .init(&out_buffer);
        const t0 = Io.Clock.Timestamp.now(io, .awake);
        var diags: mo.diag.List = .empty;
        const program = try mo.program.load(a, io, map_dir ++ "/map.mo", &diags);
        const m = mo.pipeline.mainProgram(a, program, &diags) catch |e| {
            std.debug.print("map-100k: {t}: {s}\n", .{ e, if (diags.items.len > 0) diags.items[0].what else "" });
            return null;
        };
        var server: mo.server.Server = try .init(a, io, cwd, &.{}, environ, &discard.writer, &discard.writer);
        switch (try server.run(m.program, m.main)) {
            .exited => |code| if (code != 0) {
                std.debug.print("map-100k: main exited {d}\n", .{code});
                return null;
            },
            .crashed => |report| {
                std.debug.print("map-100k: main crashed: {s}\n", .{report.clause});
                return null;
            },
        }
        const ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        if (ns < best) best = ns;
    }
    return best;
}

const kv_gets = 10_000;
const kv_dir = ".zig-cache/bench/kv";

/// The best of `iters` passes of 10_000 GETs from one client over one socket on 127.0.0.1 to
/// programs/kv, which `mo run` serves in a process of its own from a log that holds the key:
/// each GET is written, then its answer read, before the next. Null when the corpus has no
/// kv or kv does not answer.
fn kv10kGet(arena: std.mem.Allocator, io: Io, mo_exe: []const u8, root: []const u8, iters: u32) !?i96 {
    const main_path = try std.fs.path.join(arena, &.{ root, "programs/kv/main.mo" });
    Io.Dir.cwd().access(io, main_path, .{}) catch return null;
    try Io.Dir.cwd().createDirPath(io, kv_dir);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = kv_dir ++ "/kv.log", .data = "SET greeting hello wide world\n" });
    const port = freePort() orelse return null;
    var port_buf: [8]u8 = undefined;
    const port_text = try std.fmt.bufPrint(&port_buf, "{d}", .{port});
    const main_abs = try Io.Dir.cwd().realPathFileAlloc(io, main_path, arena);
    const data = try Io.Dir.cwd().realPathFileAlloc(io, kv_dir, arena);
    var child = try std.process.spawn(io, .{
        .argv = &.{ mo_exe, "run", main_abs, "--", "serve", data, "--port", port_text },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    defer child.kill(io);
    // kv listens once it has replayed its log.
    const fd = for (0..500) |_| {
        if (connectLoopback(port)) |fd| break fd;
        io.sleep(.fromMilliseconds(20), .awake) catch {};
    } else {
        std.debug.print("kv-10k-get: kv did not listen on port {d}\n", .{port});
        return null;
    };
    defer _ = posix.system.close(fd);
    var reply: [256]u8 = undefined;
    var best: i96 = std.math.maxInt(i96);
    var it: u32 = 0;
    while (it < iters) : (it += 1) {
        const t0 = Io.Clock.Timestamp.now(io, .awake);
        for (0..kv_gets) |_| {
            const line = exchange(fd, "GET greeting\n", &reply) orelse {
                std.debug.print("kv-10k-get: the connection ended\n", .{});
                return null;
            };
            if (!std.mem.eql(u8, line, "VALUE hello wide world\n")) {
                std.debug.print("kv-10k-get: kv answered {s}\n", .{line});
                return null;
            }
        }
        const ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        if (ns < best) best = ns;
    }
    return best;
}

/// A port on 127.0.0.1 nothing listens on, as the system picks one.
fn freePort() ?u16 {
    const sys = posix.system;
    const rc = sys.socket(posix.AF.INET, posix.SOCK.STREAM, posix.IPPROTO.TCP);
    if (posix.errno(rc) != .SUCCESS) return null;
    const fd: posix.socket_t = @intCast(rc);
    defer _ = sys.close(fd);
    var addr: posix.sockaddr.in = .{ .port = 0, .addr = std.mem.nativeToBig(u32, 0x7f00_0001) };
    if (posix.errno(sys.bind(fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.in))) != .SUCCESS) return null;
    var len: posix.socklen_t = @sizeOf(posix.sockaddr.in);
    if (posix.errno(sys.getsockname(fd, @ptrCast(&addr), &len)) != .SUCCESS) return null;
    return std.mem.bigToNative(u16, addr.port);
}

fn connectLoopback(port: u16) ?posix.socket_t {
    const sys = posix.system;
    const rc = sys.socket(posix.AF.INET, posix.SOCK.STREAM, posix.IPPROTO.TCP);
    if (posix.errno(rc) != .SUCCESS) return null;
    const fd: posix.socket_t = @intCast(rc);
    var addr: posix.sockaddr.in = .{ .port = std.mem.nativeToBig(u16, port), .addr = std.mem.nativeToBig(u32, 0x7f00_0001) };
    if (posix.errno(sys.connect(fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.in))) != .SUCCESS) {
        _ = sys.close(fd);
        return null;
    }
    return fd;
}

/// Writes `request` whole, then reads until a line ends; the line, or null when the stream
/// ends or breaks first.
fn exchange(fd: posix.socket_t, request: []const u8, buf: []u8) ?[]const u8 {
    const sys = posix.system;
    var sent: usize = 0;
    while (sent < request.len) {
        const n = sys.write(fd, request[sent..].ptr, request.len - sent);
        if (n <= 0) return null;
        sent += @intCast(n);
    }
    var got: usize = 0;
    while (got < buf.len) {
        const n = sys.read(fd, buf[got..].ptr, buf.len - got);
        if (n <= 0) return null;
        got += @intCast(n);
        if (std.mem.indexOfScalar(u8, buf[0..got], '\n')) |end| return buf[0 .. end + 1];
    }
    return null;
}

/// 4_000 lines in logstat's format, the same every run: a malformed line every 97th,
/// the others one second apart with methods, paths, statuses, and durations drawn from a
/// fixed seed.
fn writeLog(arena: std.mem.Allocator, io: Io) !void {
    const methods = [_][]const u8{ "GET", "GET", "GET", "POST", "DELETE", "PUT" };
    const paths = [_][]const u8{ "/api/users", "/api/orders", "/api/orders/17", "/health", "/api/cards/4111111111111111/charge", "/api/items/42" };
    const statuses = [_]u16{ 200, 200, 200, 201, 204, 404, 500, 503 };
    var prng: std.Random.DefaultPrng = .init(7);
    const rand = prng.random();
    var text: std.ArrayList(u8) = .empty;
    for (0..log_lines) |i| {
        if (i % 97 == 13) {
            try text.appendSlice(arena, "this line is not a log line\n");
            continue;
        }
        const secs: std.time.epoch.EpochSeconds = .{ .secs = 1_789_200_000 + i };
        const year_day = secs.getEpochDay().calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_secs = secs.getDaySeconds();
        const line = try std.fmt.allocPrint(arena, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z {s} {s} {d} {d}\n", .{
            year_day.year,                                  month_day.month.numeric(),                  month_day.day_index + 1,
            day_secs.getHoursIntoDay(),                     day_secs.getMinutesIntoHour(),              day_secs.getSecondsIntoMinute(),
            methods[rand.uintLessThan(usize, methods.len)], paths[rand.uintLessThan(usize, paths.len)], statuses[rand.uintLessThan(usize, statuses.len)],
            rand.intRangeAtMost(u32, 1, 2_000),
        });
        try text.appendSlice(arena, line);
    }
    try Io.Dir.cwd().createDirPath(io, log_dir);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = log_dir ++ "/" ++ log_name, .data = text.items });
}

/// One row per stage, then the fmt row, the run-programs row (its count is the programs),
/// the logstat-4k row (its count is the lines), the sim-100 row (its count is the seeds),
/// the echo-1k row (its count is the round trips), the map-100k row (its count is the keys),
/// and the kv-10k-get row (its count is the GETs): date, stage, count, best total µs ("n/a"
/// when unimplemented).
fn appendResults(io: Io, rows: []const Row, files: usize, fmt_ns: i96, programs: usize, programs_ns: i96, logstat_ns: ?i96, sim_ns: ?i96, echo_ns: ?i96, map_ns: ?i96, kv_ns: ?i96, compiled: ?LogstatC) !void {
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
    try w.interface.print("{d}\tfmt\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), files, @as(u64, @intCast(@divTrunc(fmt_ns, 1000))) });
    if (programs > 0) {
        try w.interface.print("{d}\trun-programs\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), programs, @as(u64, @intCast(@divTrunc(programs_ns, 1000))) });
    } else {
        try w.interface.print("{d}\trun-programs\t0\tn/a\n", .{@as(u64, @intCast(day))});
    }
    if (logstat_ns) |ns| {
        try w.interface.print("{d}\tlogstat-4k\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), log_lines, @as(u64, @intCast(@divTrunc(ns, 1000))) });
    } else {
        try w.interface.print("{d}\tlogstat-4k\t{d}\tn/a\n", .{ @as(u64, @intCast(day)), log_lines });
    }
    if (sim_ns) |ns| {
        try w.interface.print("{d}\tsim-100\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), sim_seeds, @as(u64, @intCast(@divTrunc(ns, 1000))) });
    } else {
        try w.interface.print("{d}\tsim-100\t{d}\tn/a\n", .{ @as(u64, @intCast(day)), sim_seeds });
    }
    if (echo_ns) |ns| {
        try w.interface.print("{d}\techo-1k\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), echo_trips, @as(u64, @intCast(@divTrunc(ns, 1000))) });
    } else {
        try w.interface.print("{d}\techo-1k\t{d}\tn/a\n", .{ @as(u64, @intCast(day)), echo_trips });
    }
    if (map_ns) |ns| {
        try w.interface.print("{d}\tmap-100k\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), map_keys, @as(u64, @intCast(@divTrunc(ns, 1000))) });
    } else {
        try w.interface.print("{d}\tmap-100k\t{d}\tn/a\n", .{ @as(u64, @intCast(day)), map_keys });
    }
    if (kv_ns) |ns| {
        try w.interface.print("{d}\tkv-10k-get\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), kv_gets, @as(u64, @intCast(@divTrunc(ns, 1000))) });
    } else {
        try w.interface.print("{d}\tkv-10k-get\t{d}\tn/a\n", .{ @as(u64, @intCast(day)), kv_gets });
    }
    // The compiled logstat: its run, its run without overflow checks, without contracts, and its
    // build whole,
    // then the build's two parts.
    if (compiled) |c| {
        const us = struct {
            fn of(ns: i96) u64 {
                return @intCast(@divTrunc(ns, 1000));
            }
        }.of;
        try w.interface.print("{d}\tlogstat-4k-c\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), log_lines, us(c.run_ns) });
        try w.interface.print("{d}\tlogstat-4k-c-wrap\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), log_lines, us(c.wrap_ns) });
        try w.interface.print("{d}\tlogstat-4k-c-nocontracts\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), log_lines, us(c.nocontracts_ns) });
        try w.interface.print("{d}\tbuild-logstat\t1\t{d}\n", .{ @as(u64, @intCast(day)), us(c.emit_ns + c.cc_ns) });
        try w.interface.print("{d}\tbuild-logstat-emit\t1\t{d}\n", .{ @as(u64, @intCast(day)), us(c.emit_ns) });
        try w.interface.print("{d}\tbuild-logstat-cc\t1\t{d}\n", .{ @as(u64, @intCast(day)), us(c.cc_ns) });
    } else {
        for ([_][]const u8{ "logstat-4k-c", "logstat-4k-c-wrap", "logstat-4k-c-nocontracts", "build-logstat", "build-logstat-emit", "build-logstat-cc" }) |row| {
            try w.interface.print("{d}\t{s}\tn/a\tn/a\n", .{ @as(u64, @intCast(day)), row });
        }
    }
}

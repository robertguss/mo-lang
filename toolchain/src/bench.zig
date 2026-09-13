//! The benchmark harness, from day one (design-v0/08: "50 ms and 100 ms targets:
//! the benchmark suite, from day one"). Times every pipeline stage over every file
//! in the corpus, each loaded with the modules it uses, best of N iterations, and
//! prints one row per stage. Stages that are not implemented print "n/a" and the row
//! lights up when the stage lands. A last `fmt` row times every file lexed, parsed, and
//! formatted to memory (`mo fmt` without the write), and a `run-programs` row times every
//! run of every program in programs/ end to end through `mo run` (MO_EXE), process
//! start included. A `logstat-4k` row times program 2 over 4_000 generated log lines in
//! this process: its four modules loaded and checked, then main on Mo.Server with its
//! output discarded, so the runtime has a permanent number.
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

    if (rows[rows.len - 1].implemented and paths.len > 0) {
        var worst: usize = 0;
        for (run_best, 0..) |ns, i| if (ns > run_best[worst]) {
            worst = i;
        };
        try out.print("slowest run: {s}, {d} µs\n", .{ paths[worst], @as(u64, @intCast(@divTrunc(run_best[worst], 1000))) });
    }

    if (record) try appendResults(io, &rows, paths.len, fmt_best, program_count, programs_best, logstat_ns);
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
/// and the logstat-4k row (its count is the lines): date, stage, count, best total µs
/// ("n/a" when unimplemented).
fn appendResults(io: Io, rows: []const Row, files: usize, fmt_ns: i96, programs: usize, programs_ns: i96, logstat_ns: ?i96) !void {
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
}

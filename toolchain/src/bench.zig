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
//! `echo-1k-c` and `kv-10k-get-c` time programs/echo and programs/kv built by `mo build`,
//! contracts on: echo's binary given the same 1_000 lines, a process of its own with its output
//! discarded, and the same 10_000 GETs to kv's binary serving the same log; each names its ratio
//! to the interpreter's row. `kv-50k-set-rss-kib` and `kv-50k-set-rss-kib-c` are kv's resident
//! memory in KiB, `mo run` and the binary, after 50_000 SETs of distinct keys from one client
//! over one socket, served from an empty log, each SET waiting for its OK.
//! `reuse-<shape>-100k` and `reuse-<shape>-100k-c` time 100_000 updates of one var (design-v0/07,
//! the reuse bet; step 21), under Mo.Server in this process and as the `mo build` binary, for six
//! shapes: `push` on a list, `set` and `remove` (newest key first) on a map, a field set on a struct, a string grown
//! by interpolation, and `add` on a set; `reuse-<shape>-100k-allocs` and `-allocs-c` count the
//! allocations each run made (Region.alloc in the interpreter, `MO_STATS=1` in the binary).
//! `http-1k` and `http-1k-c` time 1_000 `GET /hello` round trips from one client to
//! programs/httpd serving (`httpd serve --port N`) under `mo run` and as its `mo build` binary,
//! each request a connection of its own read to the end of the stream; `http-1k-rss-kib` and
//! `http-1k-rss-kib-c` are each server's resident memory in KiB after 1_000 of them.
//! `map-set-80k`, `map-remove-80k`, and `reduce-tuple-50k` (step 28) time round 7's shapes inside a
//! process's update, under Mo.Server in this process and as the `mo build` binary (`-c`): a map of
//! 80_000 entries filled in one update, then 2_000 updates that each set an existing key through a
//! function (`state.book = overwritten(state.book, i)`) or remove one; and a map of 50_000 entries,
//! then 2_000 updates that each add eight keys through `reduce` with a tuple accumulator. Each row
//! is the best of three runs of the 2_000 updates less the best of three runs that only fill.
//! `--updates` runs only these rows, and with `--record` appends only them.
//! `replay-1m` and `replay-1m-c` (step 28) time programs/jobq opening a log of 1_000_000 records under
//! `mo run` and as its `mo build` binary: from the process's start to its first answer to `GET /health`,
//! the log's replay whole. The log is 500_000 jobs each set twice, queued then leased, written once to
//! .zig-cache/bench/replay. `--replay` runs only these two, and with `--record` appends only them.
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
    var updates_only = false;
    var replay_only = false;
    var positional: u32 = 0;
    for (args[1..]) |a| {
        if (std.mem.eql(u8, a, "--record")) {
            record = true;
        } else if (std.mem.eql(u8, a, "--updates")) {
            updates_only = true;
        } else if (std.mem.eql(u8, a, "--replay")) {
            replay_only = true;
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

    // One arena, reset per run and kept warm, so a row times the run and not the page faults.
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer scratch.deinit();

    if (replay_only) {
        const replay = try replay1m(arena, io, init.environ_map, root, try mo.corpus.moExe(arena, io, init.environ_map.get("MO_EXE")));
        try printReplay(out, replay);
        if (record) try appendReplay(io, replay);
        return;
    }

    const updates = try updates2k(arena, io, init.environ_map, &scratch);
    for (update_shapes, updates) |shape, u| {
        if (u.ns) |ns| {
            try out.print("{s:<8} {d:>9} µs  (2000 updates under mo run, less the run that only fills)\n", .{ shape.name, @as(u64, @intCast(@divTrunc(ns, 1000))) });
        } else try out.print("{s:<8} {s:>12}\n", .{ shape.name, "n/a" });
        if (u.c_ns) |ns| {
            try out.print("{s}-c {d:>9} µs  (the mo build binary)\n", .{ shape.name, @as(u64, @intCast(@divTrunc(ns, 1000))) });
        } else try out.print("{s}-c {s:>12}\n", .{ shape.name, "n/a" });
    }
    if (updates_only) {
        if (record) try appendUpdates(io, updates);
        return;
    }

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

    const echo_c_ns = try echo1kC(arena, io, init.environ_map, root, iters);
    if (echo_c_ns) |ns| {
        const us: u64 = @intCast(@divTrunc(ns, 1000));
        try out.print("{s:<8} {d:>9} µs {d:>9} µs a round trip  ({d} round trips, the mo build binary, a process of its own", .{ "echo-1k-c", us, us / echo_trips, echo_trips });
        if (echo_ns) |i| try out.print("; the interpreter's echo-1k takes {d:.1}x as long", .{ratio(i, ns)});
        try out.writeAll(")\n");
    } else {
        try out.print("{s:<8} {s:>12} {s:>12}\n", .{ "echo-1k-c", "n/a", "n/a" });
    }

    const kv_binary = try buildNative(arena, io, init.environ_map, root, "kv");
    const kv_c_ns = if (kv_binary) |binary| try kvGets(arena, io, &.{binary}, iters) else null;
    if (kv_c_ns) |ns| {
        const us: u64 = @intCast(@divTrunc(ns, 1000));
        try out.print("{s:<8} {d:>9} µs {d:>9} µs a GET  ({d} GETs over 127.0.0.1 from one client to the mo build binary", .{ "kv-10k-get-c", us, us / kv_gets, kv_gets });
        if (kv_ns) |i| try out.print("; the interpreter's kv-10k-get takes {d:.1}x as long", .{ratio(i, ns)});
        try out.writeAll(")\n");
    } else {
        try out.print("{s:<8} {s:>12} {s:>12}\n", .{ "kv-10k-get-c", "n/a", "n/a" });
    }

    const kv_main = try kvMain(arena, io, root);
    const rss_kib = if (kv_main) |m| try kvSetsRss(arena, io, &.{ mo_exe, "run", m, "--" }) else null;
    const rss_c_kib = if (kv_binary) |binary| try kvSetsRss(arena, io, &.{binary}) else null;
    for ([_]?u64{ rss_kib, rss_c_kib }, [_][]const u8{ "kv-50k-set-rss-kib", "kv-50k-set-rss-kib-c" }, [_][]const u8{ "mo run", "the mo build binary" }) |kib, row, who| {
        if (kib) |k| {
            try out.print("{s:<8} {d:>9} KiB  ({s}'s resident memory after {d} SETs of distinct keys)\n", .{ row, k, who, kv_sets });
        } else try out.print("{s:<8} {s:>12}\n", .{ row, "n/a" });
    }

    const httpd_main = try programMain(arena, io, root, "httpd");
    const httpd_binary = try buildNative(arena, io, init.environ_map, root, "httpd");
    var http: Http = .{};
    if (httpd_main) |m| http.ns = try httpTrips(arena, io, &.{ mo_exe, "run", m, "--" }, iters);
    if (httpd_binary) |binary| http.c_ns = try httpTrips(arena, io, &.{binary}, iters);
    if (http.ns) |ns| {
        const us: u64 = @intCast(@divTrunc(ns, 1000));
        try out.print("{s:<8} {d:>9} µs {d:>9} µs a round trip  ({d} GET /hello over 127.0.0.1 from one client to httpd under mo run, a connection each)\n", .{ "http-1k", us, us / http_trips, http_trips });
    } else try out.print("{s:<8} {s:>12} {s:>12}\n", .{ "http-1k", "n/a", "n/a" });
    if (http.c_ns) |ns| {
        const us: u64 = @intCast(@divTrunc(ns, 1000));
        try out.print("{s:<8} {d:>9} µs {d:>9} µs a round trip  ({d} GET /hello to the mo build binary", .{ "http-1k-c", us, us / http_trips, http_trips });
        if (http.ns) |i| try out.print("; the interpreter's http-1k takes {d:.1}x as long", .{ratio(i, ns)});
        try out.writeAll(")\n");
    } else try out.print("{s:<8} {s:>12} {s:>12}\n", .{ "http-1k-c", "n/a", "n/a" });
    if (httpd_main) |m| http.rss_kib = try httpRss(arena, io, &.{ mo_exe, "run", m, "--" });
    if (httpd_binary) |binary| http.rss_c_kib = try httpRss(arena, io, &.{binary});
    for ([_]?u64{ http.rss_kib, http.rss_c_kib }, [_][]const u8{ "http-1k-rss-kib", "http-1k-rss-kib-c" }, [_][]const u8{ "mo run", "the mo build binary" }) |kib, row, who| {
        if (kib) |k| {
            try out.print("{s:<8} {d:>9} KiB  (httpd's resident memory under {s} after {d} GET /hello)\n", .{ row, k, who, http_trips });
        } else try out.print("{s:<8} {s:>12}\n", .{ row, "n/a" });
    }

    const reuse = try reuse100k(arena, io, init.environ_map, iters, &scratch);
    for (reuse_shapes, reuse) |shape, r| {
        const label = try std.fmt.allocPrint(arena, "reuse-{s}-100k", .{shape.name});
        if (r.ns) |ns| {
            try out.print("{s:<8} {d:>9} µs {d:>9} allocations  (100000 updates of one var under mo run)\n", .{ label, @as(u64, @intCast(@divTrunc(ns, 1000))), r.allocs });
        } else try out.print("{s:<8} {s:>12}\n", .{ label, "n/a" });
        if (r.c_ns) |ns| {
            try out.print("{s}-c {d:>9} µs {d:>9} allocations  (the mo build binary)\n", .{ label, @as(u64, @intCast(@divTrunc(ns, 1000))), r.c_allocs });
        } else try out.print("{s}-c {s:>12}\n", .{ label, "n/a" });
    }

    if (rows[rows.len - 1].implemented and paths.len > 0) {
        var worst: usize = 0;
        for (run_best, 0..) |ns, i| if (ns > run_best[worst]) {
            worst = i;
        };
        try out.print("slowest run: {s}, {d} µs\n", .{ paths[worst], @as(u64, @intCast(@divTrunc(run_best[worst], 1000))) });
    }

    const replay = try replay1m(arena, io, init.environ_map, root, mo_exe);
    try printReplay(out, replay);

    if (record) {
        try appendReplay(io, replay);
        try appendResults(io, &rows, paths.len, fmt_best, program_count, programs_best, logstat_ns, if (sim) |t| t.sim_ns else null, echo_ns, map_ns, kv_ns, compiled, .{ .echo_ns = echo_c_ns, .kv_ns = kv_c_ns, .rss_kib = rss_kib, .rss_c_kib = rss_c_kib }, http, reuse);
        try appendUpdates(io, updates);
    }
}

fn ratio(slow: i96, fast: i96) f64 {
    return @as(f64, @floatFromInt(slow)) / @as(f64, @floatFromInt(fast));
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

/// The compiled echo and kv (echo-1k-c, kv-10k-get-c), and kv's resident memory after 50_000 SETs.
const Native = struct { echo_ns: ?i96, kv_ns: ?i96, rss_kib: ?u64, rss_c_kib: ?u64 };

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
                .failed => |why| {
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

/// programs/<name>/main.mo built by `mo build` as it ships, contracts on: its binary, or null when
/// the corpus has no such program or the build fails.
fn buildNative(arena: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map, root: []const u8, name: []const u8) !?[]const u8 {
    const main_path = try std.fs.path.join(arena, &.{ root, "programs", name, "main.mo" });
    Io.Dir.cwd().access(io, main_path, .{}) catch return null;
    var diags: mo.diag.List = .empty;
    const program = try mo.program.load(arena, io, main_path, &diags);
    const checked = mo.pipeline.buildable(arena, program, false, &diags) catch |e| {
        std.debug.print("{s}: {t}: {s}\n", .{ name, e, if (diags.items.len > 0) diags.items[0].what else "" });
        return null;
    };
    switch (try mo.cbuild.build(arena, io, environ, program, &checked, .{ .name = name, .out_dir = build_dir })) {
        .built => |built| return built.binary,
        .failed => |why| {
            std.debug.print("{s}: {s}\n", .{ name, why });
            return null;
        },
    }
}

/// The best of `iters` runs of echo's binary given the 1_000 lines echo-1k gives it, each a
/// process of its own with its output discarded; null when a run does not exit 0.
fn echo1kC(arena: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map, root: []const u8, iters: u32) !?i96 {
    const binary = try buildNative(arena, io, environ, root, "echo") orelse return null;
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(arena, binary);
    for (0..echo_trips) |_| try argv.append(arena, "x");
    var best: i96 = std.math.maxInt(i96);
    var it: u32 = 0;
    while (it < iters) : (it += 1) {
        const t0 = Io.Clock.Timestamp.now(io, .awake);
        const ran = try std.process.run(arena, io, .{ .argv = argv.items });
        const ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        if (ran.term != .exited or ran.term.exited != 0) {
            std.debug.print("echo-1k-c: {s} ended with {any}: {s}\n", .{ binary, ran.term, ran.stderr });
            return null;
        }
        if (ns < best) best = ns;
    }
    return best;
}

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

const reuse_dir = ".zig-cache/bench/reuse";

/// The six shapes of the reuse rows: each updates one var 100_000 times and exits 1 when the
/// result is wrong.
const reuse_shapes = [_]struct { name: []const u8, source: []const u8 }{
    .{ .name = "push", .source =
    \\module Reuse.Push
    \\
    \\intent "Push 100,000 integers onto a list a var holds."
    \\
    \\fn pushed(n: UInt64) : List(UInt64)
    \\  var xs = []
    \\  for i in 0..n
    \\    xs = xs.push(i)
    \\  end
    \\  xs
    \\end
    \\
    \\fn main(platform: Platform)
    \\  if pushed(100_000).size != 100_000
    \\    platform.exit(1)
    \\  end
    \\end
    \\
    },
    .{ .name = "map-set", .source =
    \\module Reuse.MapSet
    \\
    \\intent "Set 100,000 integer keys in a map a var holds."
    \\
    \\fn filled(n: UInt64) : Map(UInt64, UInt64)
    \\  var m = Map.new()
    \\  for i in 0..n
    \\    m = m.set(i, i)
    \\  end
    \\  m
    \\end
    \\
    \\fn main(platform: Platform)
    \\  if filled(100_000).size != 100_000
    \\    platform.exit(1)
    \\  end
    \\end
    \\
    },
    .{ .name = "map-remove", .source =
    \\module Reuse.MapRemove
    \\
    \\intent "Fill a map a var holds with 100,000 integer keys, then remove every one, newest first."
    \\
    \\fn emptied(n: UInt64) : Map(UInt64, UInt64)
    \\  var m = Map.new()
    \\  for i in 0..n
    \\    m = m.set(i, i)
    \\  end
    \\  for i in 0..n
    \\    m = m.remove(n - 1 - i)
    \\  end
    \\  m
    \\end
    \\
    \\fn main(platform: Platform)
    \\  if emptied(100_000).size != 0
    \\    platform.exit(1)
    \\  end
    \\end
    \\
    },
    .{ .name = "field", .source =
    \\module Reuse.Field
    \\
    \\intent "Update a field of a struct a var holds 100,000 times."
    \\
    \\struct Tally
    \\  count: UInt64
    \\  total: UInt64
    \\  name: String
    \\end
    \\
    \\fn tallied(n: UInt64) : Tally
    \\  var t = Tally(count: 0, total: 0, name: "tally")
    \\  for i in 0..n
    \\    t.count += 1
    \\    t.total += i
    \\  end
    \\  t
    \\end
    \\
    \\fn main(platform: Platform)
    \\  if tallied(100_000).count != 100_000
    \\    platform.exit(1)
    \\  end
    \\end
    \\
    },
    .{ .name = "append", .source =
    \\module Reuse.Append
    \\
    \\intent "Append one character to a string a var holds 100,000 times."
    \\
    \\fn appended(n: UInt64) : String
    \\  var s = ""
    \\  for _ in 0..n
    \\    s = "#{s}x"
    \\  end
    \\  s
    \\end
    \\
    \\fn main(platform: Platform)
    \\  if appended(100_000).size != 100_000
    \\    platform.exit(1)
    \\  end
    \\end
    \\
    },
    .{ .name = "set-add", .source =
    \\module Reuse.SetAdd
    \\
    \\intent "Add 100,000 integers to a set a var holds."
    \\
    \\fn added(n: UInt64) : Set(UInt64)
    \\  var s = Set.new()
    \\  for i in 0..n
    \\    s = s.add(i)
    \\  end
    \\  s
    \\end
    \\
    \\fn main(platform: Platform)
    \\  if added(100_000).size != 100_000
    \\    platform.exit(1)
    \\  end
    \\end
    \\
    },
};

/// One reuse shape's best times and the allocations a run made, under Mo.Server and as a binary.
const Reuse = struct { ns: ?i96 = null, allocs: u64 = 0, c_ns: ?i96 = null, c_allocs: u64 = 0 };

/// Each reuse shape: the best of `iters` runs in this process under Mo.Server, from loading it to
/// main's end, and the best of `iters` runs of its `mo build` binary, each with the allocations it
/// made. A shape whose run does not exit 0 keeps null times.
fn reuse100k(arena: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map, iters: u32, scratch: *std.heap.ArenaAllocator) ![reuse_shapes.len]Reuse {
    var out: [reuse_shapes.len]Reuse = @splat(.{});
    try Io.Dir.cwd().createDirPath(io, reuse_dir);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = reuse_dir ++ "/mo.root", .data = "" });
    const cwd = try std.process.currentPathAlloc(io, arena);
    var stats_env: std.process.Environ.Map = .init(arena);
    try stats_env.put("MO_STATS", "1");
    for (reuse_shapes, &out) |shape, *r| {
        const path = try std.fmt.allocPrint(arena, "{s}/{s}.mo", .{ reuse_dir, shape.name });
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = shape.source });
        var it: u32 = 0;
        while (it < iters) : (it += 1) {
            _ = scratch.reset(.retain_capacity);
            const a = scratch.allocator();
            var out_buffer: [256]u8 = undefined;
            var discard: Io.Writer.Discarding = .init(&out_buffer);
            const before = mo.region.total().allocations;
            const t0 = Io.Clock.Timestamp.now(io, .awake);
            var diags: mo.diag.List = .empty;
            const program = try mo.program.load(a, io, path, &diags);
            const m = mo.pipeline.mainProgram(a, program, &diags) catch break;
            var server: mo.server.Server = try .init(a, io, cwd, &.{}, environ, &discard.writer, &discard.writer);
            switch (try server.run(m.program, m.main)) {
                .exited => |code| if (code != 0) break,
                .crashed => break,
            }
            const ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
            r.allocs = mo.region.total().allocations - before;
            r.ns = if (r.ns) |b| @min(b, ns) else ns;
        }
        var diags: mo.diag.List = .empty;
        const program = try mo.program.load(arena, io, path, &diags);
        const checked = mo.pipeline.buildable(arena, program, false, &diags) catch continue;
        const name = try std.fmt.allocPrint(arena, "reuse-{s}", .{shape.name});
        const binary = switch (try mo.cbuild.build(arena, io, environ, program, &checked, .{ .name = name, .out_dir = build_dir })) {
            .built => |built| built.binary,
            .failed => continue,
        };
        it = 0;
        while (it < iters) : (it += 1) {
            const t0 = Io.Clock.Timestamp.now(io, .awake);
            const ran = try std.process.run(arena, io, .{ .argv = &.{binary}, .environ_map = &stats_env });
            const ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
            if (ran.term != .exited or ran.term.exited != 0) break;
            r.c_allocs = statsCount(ran.stderr, "allocations") orelse 0;
            r.c_ns = if (r.c_ns) |b| @min(b, ns) else ns;
        }
    }
    return out;
}

const update_dir = ".zig-cache/bench/updates";
const update_steps = 2_000;

/// The update rows' shapes (step 28): each takes the number of updates as its first argument, fills
/// in one update, runs that many, and exits 1 when the map's size is wrong.
const update_shapes = [_]struct { name: []const u8, source: []const u8 }{
    .{ .name = "map-set-80k", .source =
    \\module Rows.MapSet
    \\
    \\intent "Fill a map of 80,000 entries in one update, then set an existing key through a function in each update the first argument counts."
    \\
    \\struct Entry
    \\  name: String
    \\  at: UInt64
    \\end
    \\
    \\struct Book
    \\  entries: Map(UInt64, Entry)
    \\end
    \\
    \\fn filled(book: Book, n: UInt64) : Book
    \\  var next = book
    \\  for i in 0..n
    \\    next.entries = next.entries.set(i, Entry(name: "first", at: i))
    \\  end
    \\  next
    \\end
    \\
    \\fn overwritten(book: Book, i: UInt64) : Book
    \\  var next = book
    \\  next.entries = next.entries.set(i, Entry(name: "again", at: i))
    \\  next
    \\end
    \\
    \\process Keeper()
    \\  state
    \\    book: Book = Book(entries: Map.new())
    \\  end
    \\
    \\  message Fill : UInt64
    \\  message Step(i: UInt64) : UInt64
    \\
    \\  fn update(state, message)
    \\    case message
    \\      Fill:
    \\        state.book = filled(state.book, 80_000)
    \\        state.book.entries.size
    \\      Step(i):
    \\        state.book = overwritten(state.book, i)
    \\        state.book.entries.size
    \\    end
    \\  end
    \\end
    \\
    \\supervisor Keepers
    \\  child Keeper, restart: :always
    \\end
    \\
    \\fn main(platform: Platform)
    \\  steps = (platform.args.first or "2000").to_u64 or 2000
    \\  keeper = Keeper.start()
    \\  var size = 0
    \\  for i in 0..steps + 1
    \\    asked = if i == 0: Fill else: Step(i: i - 1)
    \\    if keeper.ask(asked, within: 600_000.ms) is Ok(now)
    \\      size = now
    \\    end
    \\  end
    \\  if size != 80_000
    \\    platform.exit(1)
    \\  end
    \\end
    \\
    },
    .{ .name = "map-remove-80k", .source =
    \\module Rows.MapRemove
    \\
    \\intent "Fill a map of 80,000 entries in one update, then remove a key, oldest first, in each update the first argument counts."
    \\
    \\struct Book
    \\  entries: Map(UInt64, UInt64)
    \\end
    \\
    \\fn filled(book: Book, n: UInt64) : Book
    \\  var next = book
    \\  for i in 0..n
    \\    next.entries = next.entries.set(i, i)
    \\  end
    \\  next
    \\end
    \\
    \\fn without(book: Book, i: UInt64) : Book
    \\  var next = book
    \\  next.entries = next.entries.remove(i)
    \\  next
    \\end
    \\
    \\process Keeper()
    \\  state
    \\    book: Book = Book(entries: Map.new())
    \\  end
    \\
    \\  message Fill : UInt64
    \\  message Step(i: UInt64) : UInt64
    \\
    \\  fn update(state, message)
    \\    case message
    \\      Fill:
    \\        state.book = filled(state.book, 80_000)
    \\        state.book.entries.size
    \\      Step(i):
    \\        state.book = without(state.book, i)
    \\        state.book.entries.size
    \\    end
    \\  end
    \\end
    \\
    \\supervisor Keepers
    \\  child Keeper, restart: :always
    \\end
    \\
    \\fn main(platform: Platform)
    \\  steps = (platform.args.first or "2000").to_u64 or 2000
    \\  keeper = Keeper.start()
    \\  var size = 0
    \\  for i in 0..steps + 1
    \\    asked = if i == 0: Fill else: Step(i: i - 1)
    \\    if keeper.ask(asked, within: 600_000.ms) is Ok(now)
    \\      size = now
    \\    end
    \\  end
    \\  if size != 80_000 - steps
    \\    platform.exit(1)
    \\  end
    \\end
    \\
    },
    .{ .name = "reduce-tuple-50k", .source =
    \\module Rows.ReduceTuple
    \\
    \\intent "Fill a map of 50,000 entries in one update, then add eight keys through a reduce whose accumulator is a tuple in each update the first argument counts."
    \\
    \\struct Board
    \\  jobs: Map(UInt64, UInt64)
    \\end
    \\
    \\fn put(board: Board, key: UInt64) : Board
    \\  var next = board
    \\  next.jobs = next.jobs.set(key, key)
    \\  next
    \\end
    \\
    \\fn filled(board: Board, n: UInt64) : Board
    \\  var next = board
    \\  for i in 0..n
    \\    next.jobs = next.jobs.set(1_000_000 + i, i)
    \\  end
    \\  next
    \\end
    \\
    \\process Boarder()
    \\  state
    \\    board: Board = Board(jobs: Map.new())
    \\  end
    \\
    \\  message Fill : UInt64
    \\  message Step(i: UInt64) : UInt64
    \\
    \\  fn update(state, message)
    \\    case message
    \\      Fill:
    \\        state.board = filled(state.board, 50_000)
    \\        state.board.jobs.size
    \\      Step(i):
    \\        state.board = [0, 1, 2, 3, 4, 5, 6, 7].reduce((state.board, [0].take(0)), fn(acc, k) (put(acc.0, i * 8 + k), acc.1.push(k)) end).0
    \\        state.board.jobs.size
    \\    end
    \\  end
    \\end
    \\
    \\supervisor Boarders
    \\  child Boarder, restart: :always
    \\end
    \\
    \\fn main(platform: Platform)
    \\  steps = (platform.args.first or "2000").to_u64 or 2000
    \\  board = Boarder.start()
    \\  var size = 0
    \\  for i in 0..steps + 1
    \\    asked = if i == 0: Fill else: Step(i: i - 1)
    \\    if board.ask(asked, within: 600_000.ms) is Ok(now)
    \\      size = now
    \\    end
    \\  end
    \\  if size != 50_000 + 8 * steps
    \\    platform.exit(1)
    \\  end
    \\end
    \\
    },
};

/// An update row: the updates' best under Mo.Server and as a binary, each less the best that only
/// fills; null when a run does not exit 0.
const Updates = struct { ns: ?i96 = null, c_ns: ?i96 = null };

fn updates2k(arena: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map, scratch: *std.heap.ArenaAllocator) ![update_shapes.len]Updates {
    var out: [update_shapes.len]Updates = @splat(.{});
    try Io.Dir.cwd().createDirPath(io, update_dir);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = update_dir ++ "/mo.root", .data = "" });
    const cwd = try std.process.currentPathAlloc(io, arena);
    const steps = try std.fmt.allocPrint(arena, "{d}", .{update_steps});
    for (update_shapes, &out) |shape, *r| {
        const path = try std.fmt.allocPrint(arena, "{s}/{s}.mo", .{ update_dir, shape.name });
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = shape.source });
        if (try updatesInProcess(io, environ, cwd, path, "0", scratch)) |fill| {
            if (try updatesInProcess(io, environ, cwd, path, steps, scratch)) |all| r.ns = @max(0, all - fill);
        }
        var diags: mo.diag.List = .empty;
        const program = try mo.program.load(arena, io, path, &diags);
        const checked = mo.pipeline.buildable(arena, program, false, &diags) catch continue;
        const binary = switch (try mo.cbuild.build(arena, io, environ, program, &checked, .{ .name = shape.name, .out_dir = build_dir })) {
            .built => |built| built.binary,
            .failed => continue,
        };
        if (try updatesBinary(arena, io, binary, "0")) |fill| {
            if (try updatesBinary(arena, io, binary, steps)) |all| r.c_ns = @max(0, all - fill);
        }
    }
    return out;
}

/// The best of three runs of an update shape's main under Mo.Server in this process, from loading it.
fn updatesInProcess(io: Io, environ: *const std.process.Environ.Map, cwd: []const u8, path: []const u8, arg: []const u8, scratch: *std.heap.ArenaAllocator) !?i96 {
    var best: ?i96 = null;
    for (0..3) |_| {
        _ = scratch.reset(.retain_capacity);
        const a = scratch.allocator();
        var out_buffer: [256]u8 = undefined;
        var discard: Io.Writer.Discarding = .init(&out_buffer);
        const t0 = Io.Clock.Timestamp.now(io, .awake);
        var diags: mo.diag.List = .empty;
        const program = try mo.program.load(a, io, path, &diags);
        const m = mo.pipeline.mainProgram(a, program, &diags) catch return null;
        const args = try a.dupe([]const u8, &.{arg});
        var server: mo.server.Server = try .init(a, io, cwd, args, environ, &discard.writer, &discard.writer);
        switch (try server.run(m.program, m.main)) {
            .exited => |code| if (code != 0) return null,
            .crashed => return null,
        }
        const ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        best = if (best) |b| @min(b, ns) else ns;
    }
    return best;
}

/// The best of three runs of an update shape's binary.
fn updatesBinary(arena: std.mem.Allocator, io: Io, binary: []const u8, arg: []const u8) !?i96 {
    var best: ?i96 = null;
    for (0..3) |_| {
        const t0 = Io.Clock.Timestamp.now(io, .awake);
        const ran = try std.process.run(arena, io, .{ .argv = &.{ binary, arg } });
        const ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        if (ran.term != .exited or ran.term.exited != 0) return null;
        best = if (best) |b| @min(b, ns) else ns;
    }
    return best;
}

/// The update rows: date, row, the updates, µs.
fn appendUpdates(io: Io, updates: [update_shapes.len]Updates) !void {
    var file = try Io.Dir.cwd().openFile(io, "bench/results.tsv", .{ .mode = .write_only });
    defer file.close(io);
    var buf: [1024]u8 = undefined;
    var w: Io.File.Writer = .init(file, io, &buf);
    try w.seekTo(try file.length(io));
    defer w.interface.flush() catch {};
    const day: u64 = @intCast(@divTrunc(Io.Clock.Timestamp.now(io, .real).raw.toNanoseconds(), std.time.ns_per_s));
    for (update_shapes, updates) |shape, u| {
        for ([_]?i96{ u.ns, u.c_ns }, [_][]const u8{ "", "-c" }) |ns, suffix| {
            if (ns) |t| {
                try w.interface.print("{d}\t{s}{s}\t{d}\t{d}\n", .{ day, shape.name, suffix, update_steps, @as(u64, @intCast(@divTrunc(t, 1000))) });
            } else try w.interface.print("{d}\t{s}{s}\t{d}\tn/a\n", .{ day, shape.name, suffix, update_steps });
        }
    }
}

const replay_records: u64 = 1_000_000;
const replay_dir = ".zig-cache/bench/replay";

/// The replay rows: programs/jobq's time to its first /health on the log, under mo run and as a binary.
const Replay = struct { ns: ?i96 = null, c_ns: ?i96 = null };

fn replay1m(arena: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map, root: []const u8, mo_exe: []const u8) !Replay {
    const main_abs = try programMain(arena, io, root, "jobq") orelse return .{};
    const log = try replayLog(arena, io);
    var r: Replay = .{};
    r.ns = try replayTime(arena, io, &.{ mo_exe, "run", main_abs, "--" }, log);
    if (try buildNative(arena, io, environ, root, "jobq")) |binary| r.c_ns = try replayTime(arena, io, &.{binary}, log);
    return r;
}

/// The folder of the replay's log, written when it is not there yet.
fn replayLog(arena: std.mem.Allocator, io: Io) ![]const u8 {
    const path = replay_dir ++ "/log/jobq.log";
    Io.Dir.cwd().access(io, path, .{}) catch {
        try Io.Dir.cwd().createDirPath(io, replay_dir ++ "/log");
        var text: std.ArrayList(u8) = .empty;
        const jobs = replay_records / 2;
        try text.print(arena, "SET ids {d}\n", .{jobs});
        const payload = "x" ** 100;
        for ([_][]const u8{ "queued", "leased" }, 0..) |state, pass| {
            for (1..jobs + 1) |i| {
                const lease = if (pass == 0) "" else ", \"worker\": \"w1\", \"lease_until\": \"2099-01-01T00:00:00Z\"";
                try text.print(arena, "SET j_{d} {{\"id\": \"j_{d}\", \"queue\": \"q{d}\", \"state\": \"{s}\", \"payload\": \"{s}\", \"attempts\": {d}, \"max_attempts\": 3, \"created_at\": \"2026-09-13T10:00:00Z\", \"updated_at\": \"2026-09-13T10:00:00Z\"{s}}}\n", .{ i, i, i % 4, state, payload, pass, lease });
            }
        }
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = text.items });
    };
    const file = try Io.Dir.cwd().realPathFileAlloc(io, path, arena);
    return std.fs.path.dirname(file).?;
}

/// From starting `prefix serve DIR --port N` to its first 200 for GET /health; null when none comes
/// within twenty minutes.
fn replayTime(arena: std.mem.Allocator, io: Io, prefix: []const []const u8, dir: []const u8) !?i96 {
    const port = freePort() orelse return null;
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, prefix);
    try argv.appendSlice(arena, &.{ "serve", dir, "--port", try std.fmt.allocPrint(arena, "{d}", .{port}) });
    const t0 = Io.Clock.Timestamp.now(io, .awake);
    var child = try std.process.spawn(io, .{ .argv = argv.items, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore });
    defer child.kill(io);
    var buf: [256]u8 = undefined;
    for (0..60_000) |_| {
        if (healthy(port, &buf)) return t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        io.sleep(.fromMilliseconds(20), .awake) catch {};
    }
    std.debug.print("replay-1m: {s} did not answer /health\n", .{prefix[0]});
    return null;
}

/// Whether jobq on `port` answers GET /health with a 200.
fn healthy(port: u16, buf: []u8) bool {
    const sys = posix.system;
    const fd = connectLoopback(port) orelse return false;
    defer _ = sys.close(fd);
    const request = "GET /health HTTP/1.1\r\nhost: 127.0.0.1\r\nauthorization: Bearer bench\r\n\r\n";
    var sent: usize = 0;
    while (sent < request.len) {
        const n = sys.write(fd, request[sent..].ptr, request.len - sent);
        if (n <= 0) return false;
        sent += @intCast(n);
    }
    var got: usize = 0;
    while (got < 12) {
        const n = sys.read(fd, buf[got..].ptr, buf.len - got);
        if (n <= 0) return false;
        got += @intCast(n);
    }
    return std.mem.startsWith(u8, buf[0..got], "HTTP/1.1 200");
}

fn printReplay(out: *Io.Writer, r: Replay) !void {
    for ([_]?i96{ r.ns, r.c_ns }, [_][]const u8{ "replay-1m", "replay-1m-c" }, [_][]const u8{ "mo run", "the mo build binary" }) |ns, row, who| {
        if (ns) |t| {
            try out.print("{s:<8} {d:>9} µs  (programs/jobq opening a log of {d} records under {s}, to its first /health)\n", .{ row, @as(u64, @intCast(@divTrunc(t, 1000))), replay_records, who });
        } else try out.print("{s:<8} {s:>12}\n", .{ row, "n/a" });
    }
}

/// The replay rows: date, row, the records, µs.
fn appendReplay(io: Io, r: Replay) !void {
    var file = try Io.Dir.cwd().openFile(io, "bench/results.tsv", .{ .mode = .write_only });
    defer file.close(io);
    var buf: [256]u8 = undefined;
    var w: Io.File.Writer = .init(file, io, &buf);
    try w.seekTo(try file.length(io));
    defer w.interface.flush() catch {};
    const day: u64 = @intCast(@divTrunc(Io.Clock.Timestamp.now(io, .real).raw.toNanoseconds(), std.time.ns_per_s));
    for ([_]?i96{ r.ns, r.c_ns }, [_][]const u8{ "replay-1m", "replay-1m-c" }) |ns, row| {
        if (ns) |t| {
            try w.interface.print("{d}\t{s}\t{d}\t{d}\n", .{ day, row, replay_records, @as(u64, @intCast(@divTrunc(t, 1000))) });
        } else try w.interface.print("{d}\t{s}\t{d}\tn/a\n", .{ day, row, replay_records });
    }
}

/// The number after `word` on a `mo stats:` line.
fn statsCount(text: []const u8, word: []const u8) ?u64 {
    const at = std.mem.indexOf(u8, text, "mo stats:") orelse return null;
    var words = std.mem.tokenizeScalar(u8, text[at..], ' ');
    while (words.next()) |w| {
        if (std.mem.eql(u8, w, word)) return std.fmt.parseInt(u64, std.mem.trim(u8, words.next() orelse return null, "\n"), 10) catch null;
    }
    return null;
}

const kv_gets = 10_000;
const kv_dir = ".zig-cache/bench/kv";

/// The best of `iters` passes of 10_000 GETs from one client over one socket on 127.0.0.1 to
/// programs/kv, which `mo run` serves in a process of its own from a log that holds the key:
/// each GET is written, then its answer read, before the next. Null when the corpus has no
/// kv or kv does not answer.
fn kv10kGet(arena: std.mem.Allocator, io: Io, mo_exe: []const u8, root: []const u8, iters: u32) !?i96 {
    const main_abs = try kvMain(arena, io, root) orelse return null;
    return kvGets(arena, io, &.{ mo_exe, "run", main_abs, "--" }, iters);
}

/// programs/kv/main.mo's absolute path, or null when the corpus has no kv.
fn kvMain(arena: std.mem.Allocator, io: Io, root: []const u8) !?[]const u8 {
    return programMain(arena, io, root, "kv");
}

/// programs/<name>/main.mo's absolute path, or null when the corpus has no such program.
fn programMain(arena: std.mem.Allocator, io: Io, root: []const u8, name: []const u8) !?[]const u8 {
    const main_path = try std.fs.path.join(arena, &.{ root, "programs", name, "main.mo" });
    Io.Dir.cwd().access(io, main_path, .{}) catch return null;
    return try Io.Dir.cwd().realPathFileAlloc(io, main_path, arena);
}

const http_trips = 1_000;
const http_request = "GET /hello?name=bench HTTP/1.1\r\nhost: 127.0.0.1\r\n\r\n";

/// httpd's rows: 1_000 round trips under mo run and as a binary, and each server's resident memory after them.
const Http = struct { ns: ?i96 = null, c_ns: ?i96 = null, rss_kib: ?u64 = null, rss_c_kib: ?u64 = null };

/// httpd serving on a free port, started by `prefix` then `serve --port N`; null when it does not listen.
fn serveHttpd(arena: std.mem.Allocator, io: Io, prefix: []const []const u8) !?struct { child: std.process.Child, port: u16 } {
    const port = freePort() orelse return null;
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, prefix);
    try argv.appendSlice(arena, &.{ "serve", "--port", try std.fmt.allocPrint(arena, "{d}", .{port}) });
    var child = try std.process.spawn(io, .{ .argv = argv.items, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore });
    // The probe's connection ends with no request, which httpd counts as a client that left.
    for (0..500) |_| {
        if (connectLoopback(port)) |fd| {
            _ = posix.system.close(fd);
            return .{ .child = child, .port = port };
        }
        io.sleep(.fromMilliseconds(20), .awake) catch {};
    }
    std.debug.print("httpd: {s} did not listen on port {d}\n", .{ prefix[0], port });
    child.kill(io);
    return null;
}

/// One GET /hello on a connection of its own, read to the end of the stream: true when httpd
/// answered 200 with the hello.
fn httpGet(port: u16, buf: []u8) bool {
    const sys = posix.system;
    const fd = connectLoopback(port) orelse return false;
    defer _ = sys.close(fd);
    var sent: usize = 0;
    while (sent < http_request.len) {
        const n = sys.write(fd, http_request[sent..].ptr, http_request.len - sent);
        if (n <= 0) return false;
        sent += @intCast(n);
    }
    var got: usize = 0;
    while (got < buf.len) {
        const n = sys.read(fd, buf[got..].ptr, buf.len - got);
        if (n < 0) return false;
        if (n == 0) break;
        got += @intCast(n);
    }
    return std.mem.startsWith(u8, buf[0..got], "HTTP/1.1 200 OK\r\n") and std.mem.endsWith(u8, buf[0..got], "\r\n\r\nhello, bench");
}

/// `http_trips` GETs to httpd on `port`; false, and why on stderr, when one is not the hello.
fn httpGets(port: u16) bool {
    var buf: [512]u8 = undefined;
    for (0..http_trips) |_| if (!httpGet(port, &buf)) {
        std.debug.print("http-1k: httpd did not answer GET /hello with the hello\n", .{});
        return false;
    };
    return true;
}

/// The best of `iters` passes of http-1k's GETs to httpd started by `prefix`.
fn httpTrips(arena: std.mem.Allocator, io: Io, prefix: []const []const u8, iters: u32) !?i96 {
    var server = try serveHttpd(arena, io, prefix) orelse return null;
    defer server.child.kill(io);
    var best: i96 = std.math.maxInt(i96);
    var it: u32 = 0;
    while (it < iters) : (it += 1) {
        const t0 = Io.Clock.Timestamp.now(io, .awake);
        if (!httpGets(server.port)) return null;
        const ns = t0.durationTo(Io.Clock.Timestamp.now(io, .awake)).raw.toNanoseconds();
        if (ns < best) best = ns;
    }
    return best;
}

/// The resident memory in KiB of a fresh httpd started by `prefix` after `http_trips` GETs.
fn httpRss(arena: std.mem.Allocator, io: Io, prefix: []const []const u8) !?u64 {
    var server = try serveHttpd(arena, io, prefix) orelse return null;
    defer server.child.kill(io);
    if (!httpGets(server.port)) return null;
    const pid = try std.fmt.allocPrint(arena, "{d}", .{server.child.id.?});
    const ps = try std.process.run(arena, io, .{ .argv = &.{ "ps", "-o", "rss=", "-p", pid } });
    return std.fmt.parseInt(u64, std.mem.trim(u8, ps.stdout, " \n"), 10) catch null;
}

const Kv = struct { child: std.process.Child, fd: posix.socket_t };

/// kv serving the folder `data` on a free port, started by `prefix` then `serve`, and one client
/// connected once it listens; null when it does not listen.
fn serveKv(arena: std.mem.Allocator, io: Io, prefix: []const []const u8, data: []const u8) !?Kv {
    const port = freePort() orelse return null;
    const port_text = try std.fmt.allocPrint(arena, "{d}", .{port});
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(arena, prefix);
    try argv.appendSlice(arena, &.{ "serve", data, "--port", port_text });
    var child = try std.process.spawn(io, .{ .argv = argv.items, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore });
    // kv listens once it has replayed its log.
    const fd = for (0..500) |_| {
        if (connectLoopback(port)) |fd| break fd;
        io.sleep(.fromMilliseconds(20), .awake) catch {};
    } else {
        std.debug.print("kv: {s} did not listen on port {d}\n", .{ prefix[0], port });
        child.kill(io);
        return null;
    };
    return .{ .child = child, .fd = fd };
}

/// The best of `iters` passes of kv-10k-get's GETs to kv started by `prefix`.
fn kvGets(arena: std.mem.Allocator, io: Io, prefix: []const []const u8, iters: u32) !?i96 {
    try Io.Dir.cwd().createDirPath(io, kv_dir);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = kv_dir ++ "/kv.log", .data = "SET greeting hello wide world\n" });
    const data = try Io.Dir.cwd().realPathFileAlloc(io, kv_dir, arena);
    var kv = try serveKv(arena, io, prefix, data) orelse return null;
    defer kv.child.kill(io);
    const fd = kv.fd;
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

const kv_sets = 50_000;
const kv_sets_dir = ".zig-cache/bench/kv-sets";

/// kv's resident memory in KiB after 50_000 SETs of distinct keys from one client over one socket,
/// each waiting for its OK, served from an empty log by kv started with `prefix`; null when kv does
/// not answer OK.
fn kvSetsRss(arena: std.mem.Allocator, io: Io, prefix: []const []const u8) !?u64 {
    Io.Dir.cwd().deleteTree(io, kv_sets_dir) catch {};
    try Io.Dir.cwd().createDirPath(io, kv_sets_dir);
    try Io.Dir.cwd().writeFile(io, .{ .sub_path = kv_sets_dir ++ "/kv.log", .data = "" });
    const data = try Io.Dir.cwd().realPathFileAlloc(io, kv_sets_dir, arena);
    var kv = try serveKv(arena, io, prefix, data) orelse return null;
    defer kv.child.kill(io);
    defer _ = posix.system.close(kv.fd);
    var reply: [256]u8 = undefined;
    var request: [64]u8 = undefined;
    for (0..kv_sets) |i| {
        const line = exchange(kv.fd, try std.fmt.bufPrint(&request, "SET key{d} value{d}\n", .{ i, i }), &reply) orelse {
            std.debug.print("kv-50k-set: the connection ended\n", .{});
            return null;
        };
        if (!std.mem.eql(u8, line, "OK\n")) {
            std.debug.print("kv-50k-set: kv answered {s}\n", .{line});
            return null;
        }
    }
    const pid = try std.fmt.allocPrint(arena, "{d}", .{kv.child.id.?});
    const ps = try std.process.run(arena, io, .{ .argv = &.{ "ps", "-o", "rss=", "-p", pid } });
    return std.fmt.parseInt(u64, std.mem.trim(u8, ps.stdout, " \n"), 10) catch null;
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
/// the kv-10k-get row (its count is the GETs), the compiled logstat's rows, and the compiled
/// echo and kv: date, stage, count, best total µs ("n/a" when unimplemented), except the two
/// kv-50k-set-rss-kib rows, whose count is the SETs and whose number is KiB; then httpd's rows,
/// http-1k and http-1k-c (µs), and http-1k-rss-kib and http-1k-rss-kib-c (KiB), each counting
/// the round trips; then the reuse rows, µs and allocations under mo run and as a binary, each
/// counting the updates.
fn appendResults(io: Io, rows: []const Row, files: usize, fmt_ns: i96, programs: usize, programs_ns: i96, logstat_ns: ?i96, sim_ns: ?i96, echo_ns: ?i96, map_ns: ?i96, kv_ns: ?i96, compiled: ?LogstatC, native: Native, http: Http, reuse: [reuse_shapes.len]Reuse) !void {
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
    const timed = [_]struct { name: []const u8, count: u64, ns: ?i96 }{
        .{ .name = "echo-1k-c", .count = echo_trips, .ns = native.echo_ns },
        .{ .name = "kv-10k-get-c", .count = kv_gets, .ns = native.kv_ns },
    };
    for (timed) |t| {
        if (t.ns) |ns| {
            try w.interface.print("{d}\t{s}\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), t.name, t.count, @as(u64, @intCast(@divTrunc(ns, 1000))) });
        } else try w.interface.print("{d}\t{s}\t{d}\tn/a\n", .{ @as(u64, @intCast(day)), t.name, t.count });
    }
    for ([_]?u64{ native.rss_kib, native.rss_c_kib }, [_][]const u8{ "kv-50k-set-rss-kib", "kv-50k-set-rss-kib-c" }) |kib, name| {
        if (kib) |k| {
            try w.interface.print("{d}\t{s}\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), name, kv_sets, k });
        } else try w.interface.print("{d}\t{s}\t{d}\tn/a\n", .{ @as(u64, @intCast(day)), name, kv_sets });
    }
    for ([_]?i96{ http.ns, http.c_ns }, [_][]const u8{ "http-1k", "http-1k-c" }) |ns, name| {
        if (ns) |t| {
            try w.interface.print("{d}\t{s}\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), name, http_trips, @as(u64, @intCast(@divTrunc(t, 1000))) });
        } else try w.interface.print("{d}\t{s}\t{d}\tn/a\n", .{ @as(u64, @intCast(day)), name, http_trips });
    }
    for ([_]?u64{ http.rss_kib, http.rss_c_kib }, [_][]const u8{ "http-1k-rss-kib", "http-1k-rss-kib-c" }) |kib, name| {
        if (kib) |k| {
            try w.interface.print("{d}\t{s}\t{d}\t{d}\n", .{ @as(u64, @intCast(day)), name, http_trips, k });
        } else try w.interface.print("{d}\t{s}\t{d}\tn/a\n", .{ @as(u64, @intCast(day)), name, http_trips });
    }
    for (reuse_shapes, reuse) |shape, r| {
        for ([_]?i96{ r.ns, r.c_ns }, [_]u64{ r.allocs, r.c_allocs }, [_][]const u8{ "", "-c" }) |ns, allocs, suffix| {
            if (ns) |t| {
                try w.interface.print("{d}\treuse-{s}-100k{s}\t100000\t{d}\n", .{ @as(u64, @intCast(day)), shape.name, suffix, @as(u64, @intCast(@divTrunc(t, 1000))) });
                try w.interface.print("{d}\treuse-{s}-100k-allocs{s}\t100000\t{d}\n", .{ @as(u64, @intCast(day)), shape.name, suffix, allocs });
            } else try w.interface.print("{d}\treuse-{s}-100k{s}\t100000\tn/a\n", .{ @as(u64, @intCast(day)), shape.name, suffix });
        }
    }
}

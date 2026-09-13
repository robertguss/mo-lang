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
//!   mo run   <file.mo> [-- args...]
//!                        tier 1, then `main` on Mo.Server with the args after `--`;
//!                        no test runs. Exit 0, or the last platform.exit(code), or 70
//!                        with the crash report on stderr; MO0408 when there is no main
//!   mo fmt   <file.mo>   rewrites the file in its one shape (toolchain/FORMAT.md)
//!     --check            changes nothing; exit 1 with a unified diff when the file
//!                        is not formatted, or with MO0501 for a pure for body
//!     --stdout           prints the formatted file instead of writing it
//!   mo fix   <file.mo>   applies every fix of confidence 100 (fix.zig: MO0501, MO0307,
//!                        MO0312), formats, and rewrites the file; one line per fix
//!     --dry-run          changes nothing; prints the unified diff it would apply
//! check, test, and run load the file and every module it uses (program.zig); fmt
//! reads the one file. Diagnostics render as prose on stderr, or with --json as one
//! JSON record per line on stdout, each in the file it points into. A file that does
//! not parse is never rewritten.
const std = @import("std");
const Io = std.Io;
const mo = @import("mo");

const usage =
    \\usage: mo check <file.mo> [--json]
    \\       mo test [--all | --write] [--sim [N]] [--seed S] [--faults P] <file.mo> [--json]
    \\       mo run <file.mo> [--json] [-- args...]
    \\       mo fmt [--check | --stdout] <file.mo> [--json]
    \\       mo fix [--dry-run] <file.mo> [--json]
    \\
;

const FmtMode = enum { write, check, stdout };

/// A crashed `main` exits with this code (Q18; EX_SOFTWARE in sysexits.h).
const crash_exit: u8 = 70;

pub fn main(init: std.process.Init) !void {
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
    if (!is_run and program_args != null) return usageExit(err);
    if (all and !std.mem.eql(u8, command, "test")) return usageExit(err);
    // The line is one file's: --all's summary covers the modules it loads too.
    if (write and (all or !std.mem.eql(u8, command, "test"))) return usageExit(err);
    // A seed and faults shape a simulated run, so they mean nothing without --sim.
    if (sim_runs != null and !std.mem.eql(u8, command, "test")) return usageExit(err);
    if ((seed != null or faults != null) and sim_runs == null) return usageExit(err);

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
    const program = try mo.program.load(arena, io, path, &diags);

    if (is_fix) {
        // A file that does not parse has nothing to fix.
        if (diags.items.len > 0) return reject(out, err, program.files, diags.items, json);
        const outcome = try mo.fix.run(arena, program);
        const before = program.main().source;
        if (std.mem.eql(u8, before, outcome.source)) return;
        if (dry_run) return mo.diff.labeled(arena, out, path, "fixed", before, outcome.source);
        try Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = outcome.source });
        for (outcome.taken) |t| try out.print("{s}:{d}: {s} {s}\n", .{ path, t.line, t.code, t.description });
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
        };
        // --write replaces the file's line, so the line it has now is no finding.
        const last = program.files.len - 1;
        if (write and last < program.verified_lines.len) program.verified_lines[last] = .recorded;
        const r = mo.pipeline.testProgram(arena, program, all, options, &diags) catch |e| switch (e) {
            error.Rejected => return reject(out, err, program.files, diags.items, json),
            else => return e,
        };
        for (r.results) |result| try mo.runner.writeResult(out, program.files, result);
        try mo.runner.writeSummary(out, r.summary);
        var line: Io.Writer.Allocating = .init(arena);
        try mo.verified.render(&line.writer, r.summary);
        try out.writeAll(line.written());
        if (write) {
            const main_file = program.main();
            try mo.ids.write(arena, io, program.root, main_file.path, program.keys[last], main_file.source, line.written());
        }
        try out.flush();
        if (r.summary.failures > 0) std.process.exit(1);
        return;
    }
    mo.pipeline.runTo(arena, program, stage, &diags) catch |e| switch (e) {
        error.Rejected => return reject(out, err, program.files, diags.items, json),
        else => return e,
    };
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

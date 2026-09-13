//! `mo`: the toolchain CLI. Subcommands land with their stages:
//!   mo check <file.mo>   tier 1 (lex, parse, check, caps) → exit 0 or diagnostics
//!   mo test  <file.mo>   tier 2 (run the module's tests)  → one line per test, the
//!                        summary, and the verified: line; exit 1 when a test fails
//!   mo run   <file.mo> [-- args...]
//!                        tier 1, then `main` on Mo.Server with the args after `--`;
//!                        no test runs. Exit 0, or the last platform.exit(code), or 70
//!                        with the crash report on stderr; MO0408 when there is no main
//!   mo fmt   <file.mo>   rewrites the file in its one shape (toolchain/FORMAT.md)
//!     --check            changes nothing; exit 1 with a unified diff when the file
//!                        is not formatted, or with MO0501 for a pure for body
//!     --stdout           prints the formatted file instead of writing it
//! Diagnostics render as prose on stderr, or with --json as one JSON record per line
//! on stdout. A file that does not parse is never rewritten.
const std = @import("std");
const Io = std.Io;
const mo = @import("mo");

const usage =
    \\usage: mo <check|test> <file.mo> [--json]
    \\       mo run <file.mo> [--json] [-- args...]
    \\       mo fmt [--check | --stdout] <file.mo> [--json]
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
    var fmt_mode: FmtMode = .write;
    var positional: std.ArrayList([]const u8) = .empty;
    // Everything after `--` belongs to the program `mo run` runs.
    var program_args: ?[]const []const u8 = null;
    for (args[1..], 1..) |a, i| {
        if (std.mem.eql(u8, a, "--")) {
            const rest = try arena.alloc([]const u8, args.len - i - 1);
            for (args[i + 1 ..], rest) |r, *o| o.* = r;
            program_args = rest;
            break;
        } else if (std.mem.eql(u8, a, "--json")) {
            json = true;
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
    if (!is_run and program_args != null) return usageExit(err);

    const source = try Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 20));
    var diags: mo.diag.List = .empty;

    if (is_fmt) {
        const formatted = mo.fmt.format(arena, source, &diags) catch |e| switch (e) {
            error.Rejected => return reject(out, err, path, source, diags.items, json),
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
                if (changed or findings.items.len > 0) return reject(out, err, path, source, findings.items, json);
            },
        }
        return;
    }

    if (is_run) {
        const m = mo.pipeline.mainProgram(arena, source, &diags) catch |e| switch (e) {
            error.Rejected => return reject(out, err, path, source, diags.items, json),
            else => return e,
        };
        const cwd = try std.process.currentPathAlloc(io, arena);
        var server: mo.server.Server = try .init(arena, io, cwd, program_args orelse &.{}, init.environ_map, out, err);
        const code: u8 = switch (try server.run(m.program, m.main)) {
            .exited => |c| c,
            .crashed => |report| blk: {
                out.flush() catch {};
                try err.writeAll("main crashed: ");
                try mo.runner.writeReport(err, path, source, report);
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
        const r = mo.pipeline.testSource(arena, source, &diags) catch |e| switch (e) {
            error.Rejected => return reject(out, err, path, source, diags.items, json),
            else => return e,
        };
        for (r.results) |result| try mo.runner.writeResult(out, path, source, result);
        try mo.runner.writeSummary(out, r.summary);
        try mo.verified.render(out, r.summary);
        try out.flush();
        if (r.summary.failures > 0) std.process.exit(1);
        return;
    }
    mo.pipeline.runTo(arena, source, stage, &diags) catch |e| switch (e) {
        error.Rejected => return reject(out, err, path, source, diags.items, json),
        else => return e,
    };
}

fn usageExit(err: *Io.Writer) !void {
    try err.writeAll(usage);
    try err.flush();
    std.process.exit(2);
}

fn reject(out: *Io.Writer, err: *Io.Writer, path: []const u8, source: []const u8, records: []const mo.diag.Record, json: bool) !void {
    for (records) |d| {
        if (json) try mo.diag.renderJson(out, path, source, d) else try mo.diag.renderProse(err, path, source, d);
    }
    try out.flush();
    try err.flush();
    std.process.exit(1);
}

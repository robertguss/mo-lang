//! `mo`: the toolchain CLI. Subcommands land with their stages:
//!   mo check <file.mo>   tier 1 (lex, parse, check, caps) → exit 0 or diagnostics
//!   mo test  <file.mo>   tier 2 (run the module's tests)  → summary + verified: line
//!   mo run   <file.mo>   run the module on the interpreter
//! Diagnostics render as prose on stderr, or with --json as one JSON record per line
//! on stdout.
const std = @import("std");
const Io = std.Io;
const mo = @import("mo");

const usage =
    \\usage: mo <check|test|run> <file.mo> [--json]
    \\
;

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
    var positional: std.ArrayList([]const u8) = .empty;
    for (args[1..]) |a| {
        if (std.mem.eql(u8, a, "--json")) json = true else try positional.append(arena, a);
    }
    if (positional.items.len != 2) {
        try err.writeAll(usage);
        try err.flush();
        std.process.exit(2);
    }
    const command = positional.items[0];
    const path = positional.items[1];
    const stage: mo.pipeline.Stage = if (std.mem.eql(u8, command, "check"))
        .check
    else if (std.mem.eql(u8, command, "test") or std.mem.eql(u8, command, "run"))
        .run
    else {
        try err.writeAll(usage);
        try err.flush();
        std.process.exit(2);
    };

    const source = try Io.Dir.cwd().readFileAlloc(io, path, arena, .limited(1 << 20));
    var diags: mo.diag.List = .empty;
    mo.pipeline.runTo(arena, source, stage, &diags) catch |e| switch (e) {
        error.NotImplemented => {
            try err.print("mo {s}: {s} passes {t}; the stages after it are not implemented yet (see toolchain/README.md for the build order)\n", .{ command, path, mo.pipeline.implemented });
            try err.flush();
            std.process.exit(3);
        },
        error.Rejected => {
            for (diags.items) |d| {
                if (json) try mo.diag.renderJson(out, path, source, d) else try mo.diag.renderProse(err, path, source, d);
            }
            try out.flush();
            try err.flush();
            std.process.exit(1);
        },
        else => return e,
    };
}
